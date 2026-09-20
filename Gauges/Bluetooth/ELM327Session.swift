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
    var onLog: ((DiagnosticsDirection, String) -> Void)?

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
    private var lastActivityDate = Date()
    private var watchdogTimer: Timer?

    /// Cheap/generic ELM327 clones are notoriously unreliable with "ATSP0" auto-detect on
    /// Ford's CAN bus. A 2015 Mustang's OBD port is ISO 15765-4 CAN, 11-bit ID, 500kbaud
    /// (SAE protocol 6) — try that explicitly first, and only fall back to auto-detect if
    /// it's clearly not yielding real data.
    private let protocolCandidates = ["6", "0"]
    private var protocolCandidateIndex = 0
    private var pollAttemptsSinceInit = 0
    private var pollSuccessesSinceInit = 0
    private static let protocolTrialSampleSize = 8

    private static let commandTimeout: TimeInterval = 3.0
    private static let maxReconnectDelay: TimeInterval = 20.0
    private static let watchdogStallThreshold: TimeInterval = 12.0

    init() {
        ble.onStateChanged = { [weak self] state in
            guard let self else { return }
            if case .connecting(let name) = state { self.pendingDeviceName = name }
            self.onLog?(.info, "state: \(state.label)")
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
        pollAttemptsSinceInit = 0
        pollSuccessesSinceInit = 0
        commandQueue.removeAll()
        awaitingResponse = nil
        let protocolCommand = "ATSP" + protocolCandidates[protocolCandidateIndex]
        onLog?(.info, "initializing adapter, protocol candidate \(protocolCandidates[protocolCandidateIndex])")
        for cmd in ["ATZ", "ATE0", "ATL0", "ATS0", "ATH0", "ATAT1", protocolCommand] {
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
        onLog?(.sent, command.text)
        ble.send(command.text + "\r")

        let workItem = DispatchWorkItem { [weak self] in self?.handleTimeout() }
        responseTimeoutWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.commandTimeout, execute: workItem)
    }

    private func handleTimeout() {
        guard let command = awaitingResponse else { return }
        awaitingResponse = nil
        onLog?(.error, "\(command.text) timed out")
        let wasLastSetupCommand = command.pidID == nil && commandQueue.isEmpty
        if command.pidID != nil { trackPollOutcome(success: false) }
        processQueueIfIdle()
        if wasLastSetupCommand { finishInitIfNeeded() }
    }

    private func handleResponse(_ raw: String) {
        responseTimeoutWorkItem?.cancel()
        guard let command = awaitingResponse else { return }
        awaitingResponse = nil
        receivedAnyResponseDuringInit = true
        lastActivityDate = Date()
        onLog?(.received, raw.trimmingCharacters(in: .whitespacesAndNewlines))

        if let pidID = command.pidID {
            let success = parsePIDResponse(raw, pidID: pidID)
            trackPollOutcome(success: success)
        }
        let wasLastSetupCommand = command.pidID == nil && commandQueue.isEmpty
        processQueueIfIdle()
        if wasLastSetupCommand { finishInitIfNeeded() }
    }

    @discardableResult
    private func parsePIDResponse(_ raw: String, pidID: String) -> Bool {
        guard let pid = OBDPIDCatalog.byID[pidID] else { return false }
        let expectedPIDHex = String(format: "%02X", pid.pid)
        let cleaned = raw.replacingOccurrences(of: "\r", with: " ").replacingOccurrences(of: "\n", with: " ")
        let tokens = cleaned.split(separator: " ").map(String.init).filter { !$0.isEmpty }
        // Match "41 <thisPID>" specifically, not just any "41" — guards against a stray
        // leftover fragment from an earlier exchange being misread as this PID's answer.
        guard let modeIndex = tokens.indices.first(where: {
            tokens[$0] == "41" && $0 + 1 < tokens.count && tokens[$0 + 1].uppercased() == expectedPIDHex
        }) else { return false }
        let byteStart = modeIndex + 2
        guard byteStart + pid.responseByteCount <= tokens.count else { return false }
        let byteTokens = tokens[byteStart..<(byteStart + pid.responseByteCount)]
        let bytes = byteTokens.compactMap { UInt8($0, radix: 16) }
        guard bytes.count == pid.responseByteCount,
              let value = OBDDecoder.decode(pidID: pidID, bytes: bytes) else { return false }
        onReading?(pidID, value)
        return true
    }

    /// Watches the first handful of PID polls after each init: if none of them produced real
    /// data (adapter is talking, e.g. "NO DATA"/"UNABLE TO CONNECT", or even just timing out
    /// on every single PID), the protocol we picked is probably wrong for this vehicle — try
    /// the next candidate rather than sit there polling a bus that isn't answering.
    private func trackPollOutcome(success: Bool) {
        pollAttemptsSinceInit += 1
        if success { pollSuccessesSinceInit += 1 }
        guard pollAttemptsSinceInit >= Self.protocolTrialSampleSize else { return }
        defer {
            pollAttemptsSinceInit = 0
            pollSuccessesSinceInit = 0
        }
        guard pollSuccessesSinceInit == 0 else { return }
        guard protocolCandidateIndex < protocolCandidates.count - 1 else {
            onLog?(.error, "no valid data on any protocol candidate")
            return
        }
        protocolCandidateIndex += 1
        onLog?(.info, "protocol \(protocolCandidates[protocolCandidateIndex - 1]) got no data, trying \(protocolCandidates[protocolCandidateIndex])")
        // Defer to the next run loop turn so we don't reinitialize from inside the very
        // handleResponse/handleTimeout call that's still unwinding.
        DispatchQueue.main.async { [weak self] in self?.beginAdapterInit() }
    }

    // MARK: - Polling

    private func startPolling() {
        guard !isPolling else { return }
        isPolling = true
        pollCycleIndex = 0
        lastActivityDate = Date()
        startWatchdog()
        queueNextPIDIfNeeded()
    }

    private func stopPolling() {
        isPolling = false
        commandQueue.removeAll { $0.pidID != nil }
        watchdogTimer?.invalidate()
        watchdogTimer = nil
    }

    /// Extra insurance on top of the per-command timeout: if the whole session goes quiet
    /// for way longer than any single command timeout should allow, something wedged
    /// (subscription silently dropped, adapter locked up, etc.) — reconnect from scratch
    /// rather than sit there showing stale numbers forever.
    private func startWatchdog() {
        watchdogTimer?.invalidate()
        let timer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: true) { [weak self] _ in
            guard let self, self.isPolling else { return }
            if Date().timeIntervalSince(self.lastActivityDate) > Self.watchdogStallThreshold {
                self.handleFailure("No response from the adapter for a while — reconnecting.")
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        watchdogTimer = timer
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
        onLog?(.error, message)
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
