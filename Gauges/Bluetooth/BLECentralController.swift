import CoreBluetooth
import Foundation

/// Generic BLE "serial pipe" transport. Knows nothing about ELM327/OBD — just finds a
/// notify+write characteristic pair on whatever peripheral it's pointed at, and shuttles
/// text through them. This is what makes an unbranded/"Generic" ELM327 clone work: instead
/// of hardcoding one adapter's service UUIDs, we discover everything the peripheral exposes
/// and probe for the pair that actually talks back.
final class BLECentralController: NSObject {
    private static let lastPeripheralKey = "com.potatogremlin.carplaygauges.lastPeripheralID"
    private static let cachedServiceKey = "com.potatogremlin.carplaygauges.cachedServiceUUID"
    private static let cachedWriteCharKey = "com.potatogremlin.carplaygauges.cachedWriteCharUUID"
    private static let cachedNotifyCharKey = "com.potatogremlin.carplaygauges.cachedNotifyCharUUID"

    var onStateChanged: ((ConnectionState) -> Void)?
    var onPeripheralDiscovered: ((DiscoveredPeripheral) -> Void)?
    var onSerialPipeReady: (() -> Void)?
    var onDataChunk: ((String) -> Void)?
    var onDisconnected: ((_ wasExplicit: Bool) -> Void)?
    var onFailure: ((String) -> Void)?
    var onBluetoothUnavailable: ((String) -> Void)?

    private var centralManager: CBCentralManager!
    private var knownPeripherals: [UUID: CBPeripheral] = [:]
    private var connectedPeripheral: CBPeripheral?

    private var notifyCandidates: [CBCharacteristic] = []
    private var writeCandidates: [CBCharacteristic] = []
    private var activeWriteChar: CBCharacteristic?
    private var activeNotifyChar: CBCharacteristic?

    private var expectedServiceCount = 0
    private var respondedServiceCount = 0
    private var probeIndex = 0
    private var probeInFlight = false
    private var probeTimeoutWorkItem: DispatchWorkItem?
    private var rxBuffer = ""

    private var pendingScanRequested = false
    private var explicitDisconnectRequested = false
    private var usingCachedPipe = false

    override init() {
        super.init()
        centralManager = CBCentralManager(
            delegate: self,
            queue: nil,
            options: [
                CBCentralManagerOptionRestoreIdentifierKey: "com.potatogremlin.carplaygauges.central",
                CBCentralManagerOptionShowPowerAlertKey: true,
            ]
        )
    }

    // MARK: - Public API

    func startScanning() {
        guard centralManager.state == .poweredOn else {
            pendingScanRequested = true
            return
        }
        pendingScanRequested = false
        centralManager.scanForPeripherals(withServices: nil, options: [
            CBCentralManagerScanOptionAllowDuplicatesKey: false,
        ])
        onStateChanged?(.scanning)
    }

    func stopScanning() {
        pendingScanRequested = false
        if centralManager.state == .poweredOn {
            centralManager.stopScan()
        }
    }

    func connect(to id: UUID) {
        guard let peripheral = knownPeripherals[id] else { return }
        usingCachedPipe = false
        connect(peripheral: peripheral)
    }

    /// Attempts to reconnect to whichever peripheral we last had a working serial pipe on,
    /// using the cached service/characteristic UUIDs to skip the discovery probe entirely.
    /// Returns false if there's nothing to reconnect to.
    @discardableResult
    func reconnectToSavedPeripheral() -> Bool {
        guard centralManager.state == .poweredOn,
              let idString = UserDefaults.standard.string(forKey: Self.lastPeripheralKey),
              let uuid = UUID(uuidString: idString) else { return false }
        let peripherals = centralManager.retrievePeripherals(withIdentifiers: [uuid])
        guard let peripheral = peripherals.first else { return false }
        knownPeripherals[uuid] = peripheral
        usingCachedPipe = UserDefaults.standard.string(forKey: Self.cachedServiceKey) != nil
        connect(peripheral: peripheral)
        return true
    }

    func disconnect() {
        explicitDisconnectRequested = true
        if let peripheral = connectedPeripheral {
            centralManager.cancelPeripheralConnection(peripheral)
        }
    }

    func send(_ text: String) {
        guard let characteristic = activeWriteChar, let peripheral = connectedPeripheral,
              peripheral.state == .connected else { return }
        guard let data = text.data(using: .ascii) else { return }
        // A previous command's response may never have arrived (dropped/incomplete BLE
        // packet), leaving partial bytes with no '>' terminator sitting in the buffer.
        // Without this, that leftover text silently prepends onto the next real response
        // forever, permanently desyncing every reading after the first hiccup.
        rxBuffer = ""
        let writeType: CBCharacteristicWriteType = characteristic.properties.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse
        let maxLength = max(peripheral.maximumWriteValueLength(for: writeType), 20)
        var offset = 0
        while offset < data.count {
            let end = min(offset + maxLength, data.count)
            peripheral.writeValue(data.subdata(in: offset..<end), for: characteristic, type: writeType)
            offset = end
        }
    }

    // MARK: - Connection flow

    private func connect(peripheral: CBPeripheral) {
        explicitDisconnectRequested = false
        connectedPeripheral = peripheral
        peripheral.delegate = self
        onStateChanged?(.connecting(name: displayName(for: peripheral)))
        centralManager.connect(peripheral, options: [
            CBConnectPeripheralOptionNotifyOnDisconnectionKey: true,
        ])
    }

    private func displayName(for peripheral: CBPeripheral) -> String {
        peripheral.name ?? "OBD Adapter"
    }

    private func beginDiscovery(cachedOnly: Bool) {
        guard let peripheral = connectedPeripheral else { return }
        notifyCandidates.removeAll()
        writeCandidates.removeAll()
        activeWriteChar = nil
        activeNotifyChar = nil
        rxBuffer = ""
        probeIndex = 0

        if cachedOnly,
           let serviceUUIDString = UserDefaults.standard.string(forKey: Self.cachedServiceKey) {
            peripheral.discoverServices([CBUUID(string: serviceUUIDString)])
        } else {
            usingCachedPipe = false
            peripheral.discoverServices(nil)
        }
    }

    private func beginProbing() {
        guard !notifyCandidates.isEmpty, !writeCandidates.isEmpty else {
            if usingCachedPipe {
                clearCachedPipe()
                beginDiscovery(cachedOnly: false)
            } else {
                onFailure?("No serial characteristic found on this device.")
            }
            return
        }

        for characteristic in notifyCandidates {
            connectedPeripheral?.setNotifyValue(true, for: characteristic)
        }

        if usingCachedPipe {
            // We already know the pair; skip probing and let the ELM327 init sequence validate it.
            activeWriteChar = writeCandidates.first
            activeNotifyChar = notifyCandidates.first
            onSerialPipeReady?()
            return
        }

        writeCandidates.sort { lhs, rhs in
            let l = lhs.service.map { BLEHeuristics.knownServiceUUIDs.contains($0.uuid) } ?? false
            let r = rhs.service.map { BLEHeuristics.knownServiceUUIDs.contains($0.uuid) } ?? false
            return l && !r
        }

        onStateChanged?(.initializing)
        tryNextProbe()
    }

    private func tryNextProbe() {
        guard probeIndex < writeCandidates.count else {
            onFailure?("Couldn't find a responsive serial characteristic on this device.")
            return
        }
        activeWriteChar = writeCandidates[probeIndex]
        probeInFlight = true
        send("ATI\r")

        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.probeInFlight else { return }
            self.probeInFlight = false
            self.probeIndex += 1
            self.tryNextProbe()
        }
        probeTimeoutWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: workItem)
    }

    private func confirmProbe(respondingCharacteristic: CBCharacteristic) {
        guard probeInFlight else { return }
        probeInFlight = false
        probeTimeoutWorkItem?.cancel()
        activeNotifyChar = respondingCharacteristic
        cachePipe()
        onSerialPipeReady?()
    }

    private func cachePipe() {
        guard let peripheral = connectedPeripheral,
              let writeChar = activeWriteChar,
              let service = writeChar.service else { return }
        UserDefaults.standard.set(peripheral.identifier.uuidString, forKey: Self.lastPeripheralKey)
        UserDefaults.standard.set(service.uuid.uuidString, forKey: Self.cachedServiceKey)
        UserDefaults.standard.set(writeChar.uuid.uuidString, forKey: Self.cachedWriteCharKey)
        if let notifyChar = activeNotifyChar {
            UserDefaults.standard.set(notifyChar.uuid.uuidString, forKey: Self.cachedNotifyCharKey)
        }
    }

    private func clearCachedPipe() {
        UserDefaults.standard.removeObject(forKey: Self.cachedServiceKey)
        UserDefaults.standard.removeObject(forKey: Self.cachedWriteCharKey)
        UserDefaults.standard.removeObject(forKey: Self.cachedNotifyCharKey)
    }
}

// MARK: - CBCentralManagerDelegate

extension BLECentralController: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            if pendingScanRequested { startScanning() }
        case .poweredOff:
            onBluetoothUnavailable?("Bluetooth is turned off.")
        case .unauthorized:
            onBluetoothUnavailable?("Bluetooth permission was denied. Enable it in Settings.")
        case .unsupported:
            onBluetoothUnavailable?("This device doesn't support Bluetooth LE.")
        default:
            break
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                         advertisementData: [String: Any], rssi RSSI: NSNumber) {
        knownPeripherals[peripheral.identifier] = peripheral
        let name = peripheral.name
            ?? (advertisementData[CBAdvertisementDataLocalNameKey] as? String)
            ?? "Unknown Device"
        onPeripheralDiscovered?(DiscoveredPeripheral(
            id: peripheral.identifier,
            name: name,
            rssi: RSSI.intValue,
            looksLikeOBDAdapter: BLEHeuristics.looksLikeOBDAdapter(name: name)
        ))
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        onStateChanged?(.initializing)
        beginDiscovery(cachedOnly: usingCachedPipe)
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        connectedPeripheral = nil
        onFailure?(error?.localizedDescription ?? "Failed to connect.")
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        connectedPeripheral = nil
        activeWriteChar = nil
        activeNotifyChar = nil
        probeTimeoutWorkItem?.cancel()
        probeInFlight = false
        let wasExplicit = explicitDisconnectRequested
        explicitDisconnectRequested = false
        onDisconnected?(wasExplicit)
    }

    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        guard let peripherals = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral],
              let peripheral = peripherals.first else { return }
        knownPeripherals[peripheral.identifier] = peripheral
        connectedPeripheral = peripheral
        peripheral.delegate = self
        usingCachedPipe = UserDefaults.standard.string(forKey: Self.cachedServiceKey) != nil

        guard peripheral.state == .connected else { return }
        onStateChanged?(.initializing)
        if let services = peripheral.services, !services.isEmpty {
            expectedServiceCount = services.count
            respondedServiceCount = 0
            for service in services {
                peripheral.discoverCharacteristics(usingCachedPipe ? cachedCharacteristicUUIDs() : nil, for: service)
            }
        } else {
            beginDiscovery(cachedOnly: usingCachedPipe)
        }
    }
}

// MARK: - CBPeripheralDelegate

extension BLECentralController: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil, let services = peripheral.services, !services.isEmpty else {
            if usingCachedPipe {
                clearCachedPipe()
                usingCachedPipe = false
                beginDiscovery(cachedOnly: false)
            } else {
                onFailure?(error?.localizedDescription ?? "No services found on this device.")
            }
            return
        }
        expectedServiceCount = services.count
        respondedServiceCount = 0
        for service in services {
            let targetChars: [CBUUID]? = usingCachedPipe ? cachedCharacteristicUUIDs() : nil
            peripheral.discoverCharacteristics(targetChars, for: service)
        }
    }

    private func cachedCharacteristicUUIDs() -> [CBUUID]? {
        guard let writeString = UserDefaults.standard.string(forKey: Self.cachedWriteCharKey) else { return nil }
        var uuids = [CBUUID(string: writeString)]
        if let notifyString = UserDefaults.standard.string(forKey: Self.cachedNotifyCharKey) {
            uuids.append(CBUUID(string: notifyString))
        }
        return uuids
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        respondedServiceCount += 1
        if error == nil, let characteristics = service.characteristics {
            for characteristic in characteristics {
                if characteristic.properties.contains(.notify) || characteristic.properties.contains(.indicate) {
                    notifyCandidates.append(characteristic)
                }
                if characteristic.properties.contains(.write) || characteristic.properties.contains(.writeWithoutResponse) {
                    writeCandidates.append(characteristic)
                }
            }
        }
        if respondedServiceCount >= expectedServiceCount {
            beginProbing()
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil, let data = characteristic.value, !data.isEmpty else { return }

        // Snapshot before confirmProbe() flips it, so the probe's own reply (e.g. "ELM327 v1.5")
        // never gets forwarded to the ELM327 session and misread as the reply to a real command.
        let wasProbing = probeInFlight
        if wasProbing {
            confirmProbe(respondingCharacteristic: characteristic)
        }

        guard characteristic.uuid == activeNotifyChar?.uuid,
              let text = String(data: data, encoding: .isoLatin1) else { return }
        rxBuffer += text
        while let range = rxBuffer.range(of: ">") {
            let chunk = String(rxBuffer[rxBuffer.startIndex..<range.lowerBound])
            rxBuffer.removeSubrange(rxBuffer.startIndex..<range.upperBound)
            if !wasProbing {
                onDataChunk?(chunk)
            }
        }
        // Belt-and-suspenders: a response that never gets its '>' terminator (and so is
        // never flushed above) shouldn't be able to grow the buffer forever.
        if rxBuffer.utf8.count > 512 {
            rxBuffer = ""
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        // No-op: command pacing is handled by the ELM327 session's response/timeout logic.
    }
}
