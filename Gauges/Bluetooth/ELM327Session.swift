import Foundation

/// Owns the BLE transport and speaks the ELM327 AT-command dialect on top of it:
/// adapter init, a half-duplex command queue (ELM327 can't handle overlapping commands),
/// and a continuous PID polling loop once initialized.
final class ELM327Session {
    private struct PendingCommand {
        let text: String
        let pidID: String?
    }

    private let ble = BLECentralController()

    var onStateChanged: ((ConnectionState) -> Void)?
    var onReading: ((_ pidID: String, _ value: Double) -> Void)?
    var onDiscoveredPeripheral: ((DiscoveredPeripheral) -> Void)?
    var onBluetoothUnavailable: ((String) -> Void)?
    var onError: ((String) -> Void)?

    private var activePIDs: [OBDPID] = []
    private var commandQueue: [PendingCommand] = []
    private var awaitingResponse: PendingCommand?
    private var responseTimeoutWorkItem: DispatchWorkItem?
    private var reconnectWorkItem: DispatchWorkItem?
    private var reconnectAttempt = 0
    private var isPolling = false
    private var pollCycleIndex = 0
    private var pendingDeviceName = "OBD Adapter"
    private var receivedAnyResponseDuringInit = false

    private static let commandTimeout: TimeInterval = 3.0
    private static let maxReconnectDelay: TimeInterval = 20.0

    init() {
        ble.onStateChanged = { [weak self] state in
            guard let self else { return }
            if case .connecting(let name) = state { self.pendingDeviceName = name }
            self.onStateChanged?(state)
        }
        ble.onPeripheralDiscovered = { [weak self] peripheral in self?.onDiscoveredPeripheral?(peripheral) }
        ble.onSerialPipeReady = { [weak self] in self?.beginAdapterInit() }
        ble.onDataChunk = { [weak self] chunk in self?.handleResponse(chunk) }
        ble.onDisconnected = { [weak self] explicit in self?.handleDisconnect(explicit: explicit) }
        ble.onFailure = { [weak self] message in self?.handleFailure(message) }
        ble.onBluetoothUnavailable = { [weak self] message in self?.onBluetoothUnavailable?(message) }
    }

    // MARK: - Public API

    func startScanning() { ble.startScanning() }
    func stopScanning() { ble.stopScanning() }
    func connect(to id: UUID) { ble.connect(to: id) }

    @discardableResult
    func autoReconnect() -> Bool { ble.reconnectToSavedPeripheral() }

    func disconnect() {
        reconnectWorkItem?.cancel()
        stopPolling()
        ble.disconnect()
    }

    func setActivePIDs(_ pids: [OBDPID]) {
        activePIDs = pids.filter { !$0.isDerived }
    }

    // MARK: - Adapter init

    private func beginAdapterInit() {
        reconnectAttempt = 0
        receivedAnyResponseDuringInit = false
        commandQueue.removeAll()
        awaitingResponse = nil
        for cmd in ["ATZ", "ATE0", "ATL0", "ATS0", "ATH0", "ATSP0"] {
            commandQueue.append(PendingCommand(text: cmd, pidID: nil))
        }
        processQueueIfIdle()
    }

    private func finishInitIfNeeded() {
        guard receivedAnyResponseDuringInit else {
            // Every setup command timed out — likely a stale cached characteristic pair
            // or a dead connection. Don't report "connected" against silence; disconnect
            // and let the normal reconnect/backoff path try again (or re-probe from scratch).
            onError?("The adapter didn't respond to setup commands.")
            ble.disconnect()
            scheduleReconnect()
            return
        }
        onStateChanged?(.connected(name: pendingDeviceName))
        startPolling()
    }

    // MARK: - Command queue

    private func processQueueIfIdle() {
        guard awaitingResponse == nil else { return }
        guard !commandQueue.isEmpty else {
            if isPolling { queueNextPIDIfNeeded() }
            return
        }
        let command = commandQueue.removeFirst()
        awaitingResponse = command
        ble.send(command.text + "\r")

        let workItem = DispatchWorkItem { [weak self] in self?.handleTimeout() }
        responseTimeoutWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.commandTimeout, execute: workItem)
    }

    private func handleTimeout() {
        guard let command = awaitingResponse else { return }
        awaitingResponse = nil
        let wasLastSetupCommand = command.pidID == nil && commandQueue.isEmpty
        processQueueIfIdle()
        if wasLastSetupCommand { finishInitIfNeeded() }
    }

    private func handleResponse(_ raw: String) {
        responseTimeoutWorkItem?.cancel()
        guard let command = awaitingResponse else { return }
        awaitingResponse = nil
        receivedAnyResponseDuringInit = true

        if let pidID = command.pidID {
            parsePIDResponse(raw, pidID: pidID)
        }
        let wasLastSetupCommand = command.pidID == nil && commandQueue.isEmpty
        processQueueIfIdle()
        if wasLastSetupCommand { finishInitIfNeeded() }
    }

    private func parsePIDResponse(_ raw: String, pidID: String) {
        guard let pid = OBDPIDCatalog.byID[pidID] else { return }
        let cleaned = raw.replacingOccurrences(of: "\r", with: " ").replacingOccurrences(of: "\n", with: " ")
        let tokens = cleaned.split(separator: " ").map(String.init).filter { !$0.isEmpty }
        guard let modeIndex = tokens.firstIndex(of: "41") else { return }
        let byteStart = modeIndex + 2
        guard byteStart + pid.responseByteCount <= tokens.count else { return }
        let byteTokens = tokens[byteStart..<(byteStart + pid.responseByteCount)]
        let bytes = byteTokens.compactMap { UInt8($0, radix: 16) }
        guard bytes.count == pid.responseByteCount,
              let value = OBDDecoder.decode(pidID: pidID, bytes: bytes) else { return }
        onReading?(pidID, value)
    }

    // MARK: - Polling

    private func startPolling() {
        guard !isPolling else { return }
        isPolling = true
        pollCycleIndex = 0
        queueNextPIDIfNeeded()
    }

    private func stopPolling() {
        isPolling = false
        commandQueue.removeAll { $0.pidID != nil }
    }

    private func queueNextPIDIfNeeded() {
        guard isPolling, commandQueue.isEmpty, awaitingResponse == nil else { return }
        guard !activePIDs.isEmpty else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.queueNextPIDIfNeeded() }
            return
        }
        let pid = activePIDs[pollCycleIndex % activePIDs.count]
        pollCycleIndex += 1
        commandQueue.append(PendingCommand(text: String(format: "01%02X", pid.pid), pidID: pid.id))
        processQueueIfIdle()
    }

    // MARK: - Disconnect / reconnect

    private func handleDisconnect(explicit: Bool) {
        stopPolling()
        awaitingResponse = nil
        commandQueue.removeAll()
        responseTimeoutWorkItem?.cancel()
        if explicit {
            onStateChanged?(.disconnected)
        } else {
            scheduleReconnect()
        }
    }

    private func handleFailure(_ message: String) {
        onError?(message)
        stopPolling()
        ble.disconnect()
        scheduleReconnect()
    }

    private func scheduleReconnect() {
        reconnectAttempt += 1
        onStateChanged?(.reconnecting(attempt: reconnectAttempt))
        let delay = min(2.0 * Double(reconnectAttempt), Self.maxReconnectDelay)
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if !self.ble.reconnectToSavedPeripheral() {
                self.onStateChanged?(.disconnected)
            }
        }
        reconnectWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }
}
