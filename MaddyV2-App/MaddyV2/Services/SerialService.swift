//
//  SerialService.swift
//  MaddyV2
//
//  Created by Arber on 03.03.26.
//

import Foundation
import Combine
#if canImport(ORSSerial)
import ORSSerial
#else
import Darwin
#endif

// =====================================================
// MARK: - ESP View
// [TAG: V2_ESP_VIEW]
// =====================================================

enum EspView: String {
    case idle
    case music
    case focus
    case tasks
    case habits
    case coach
    case game
    case stats
    case settings
    case debug
}

struct SerialPortDebugInfo: Identifiable, Equatable {
    let path: String
    let name: String
    let vendorID: Int?
    let productID: Int?

    var id: String { path }
}

// =====================================================
// MARK: - SerialService
// [TAG: V2_SERIAL_SERVICE]
// =====================================================

final class SerialService: NSObject, ObservableObject {
    // =====================================================
    // MARK: - Published State
    // =====================================================

    @Published var availablePorts: [String] = []
    @Published var availablePortDebugInfo: [SerialPortDebugInfo] = []
    @Published var preferredPort: String?
    @Published var selectedPort: String?
    @Published var lastConnectedPort: String?

    @Published var isConnected: Bool = false
    @Published var status: String = "Idle (USB)"
    @Published var firmwareVersion: String = "Unknown"
    @Published var lastError: String?
    @Published var debugLines: [String] = []

    @Published var autoReconnectEnabled: Bool = true

    @Published var helloProtoVersion: Int?
    @Published var helloFirmware: String?
    @Published var helloScreen: String?
    @Published var lastGamifyPayload: String?

    // =====================================================
    // MARK: - Private State
    // =====================================================

    private let maxDebugLines = 600
    private let busyHint = "Port busy/locked. Close Arduino Serial Monitor, screen, miniterm, or any other serial app, then retry."
    private let startupEnumerationDelay: TimeInterval = 1.2
    private let reconnectRetryDelay: TimeInterval = 3.0
    private let heartbeatInterval: TimeInterval = 5.0
    private let maxMissedHeartbeats = 2
    private let lastConnectedPortDefaultsKey = "maddy.serial.lastConnectedPort"

    private let espVendorIDs: Set<Int> = [0x10C4, 0x1A86, 0x0403, 0x303A]

    private var wantsConnection = false
    private var lastConnectedPortPath: String?
    private var isOpeningPort = false
    private var openingPortPath: String?
    private var reconnectAttemptCounter: Int = 0
    private var missedHeartbeats: Int = 0
    private var lastPongAt: Date = .distantPast
    private var hasSeenPongInSession = false

    private var inputBuffer = Data()
    private var scanTicker: AnyCancellable?
    private var heartbeatTicker: AnyCancellable?
    private var reconnectWorkItem: DispatchWorkItem?
    private var openTimeoutWorkItem: DispatchWorkItem?
    private var timeTicker: AnyCancellable?
    private var hasAnnouncedOpen = false

    private var lastMusicPayload: String?
    private var lastMusicSentAt: Date = .distantPast

    private var lastPomoPayload: String?
    private var lastPomoSentAt: Date = .distantPast
    private var lastPomoRunning = false
    private var lastGamifySentAt: Date = .distantPast

#if canImport(ORSSerial)
    private var port: ORSSerialPort?
#else
    private var fallbackFD: Int32 = -1
    private var fallbackReadSource: DispatchSourceRead?
    private var fallbackConnectedPath: String?
#endif

    override init() {
        super.init()
        let persisted = UserDefaults.standard.string(forKey: lastConnectedPortDefaultsKey)
        lastConnectedPortPath = persisted
        lastConnectedPort = persisted
        preferredPort = persisted
        selectedPort = persisted
        wantsConnection = true

        registerPortNotifications()
        startPortScanner()
        refreshPorts()
        scheduleStartupAutoConnect()
    }

    deinit {
        scanTicker?.cancel()
        heartbeatTicker?.cancel()
        timeTicker?.cancel()
        reconnectWorkItem?.cancel()
        openTimeoutWorkItem?.cancel()
        NotificationCenter.default.removeObserver(self)
#if canImport(ORSSerial)
        closeCurrentPort(preserveDesiredConnection: false)
#else
        closeFallbackPort(preserveDesiredConnection: false)
#endif
    }

    // =====================================================
    // MARK: - Public API
    // =====================================================

    func setAutoReconnect(enabled: Bool) {
        autoReconnectEnabled = enabled
        if enabled == false {
            reconnectWorkItem?.cancel()
            reconnectWorkItem = nil
            if isConnected == false {
                publish { self.status = "Disconnected (auto-connect off)" }
            }
            return
        }

        wantsConnection = true
        autoReconnectIfNeeded(reason: "auto reconnect enabled")
    }

    func refreshPorts() {
        let details = Self.serialPortDetails()
        let ports = details.map(\.path)

        publish {
            self.availablePorts = ports
            self.availablePortDebugInfo = details

            if let selected = self.selectedPort, ports.contains(selected) == false {
                self.selectedPort = nil
            }

            if self.selectedPort == nil {
                self.selectedPort = self.reconnectCandidate()
            }
        }

        guard isConnected == false else { return }
        autoReconnectIfNeeded(reason: "refresh")
    }

    func connect(to portPath: String? = nil) {
        let target = portPath ?? selectedPort ?? preferredPort ?? lastConnectedPortPath ?? reconnectCandidate()
        guard let path = target, path.isEmpty == false else {
            publish {
                self.lastError = "No matching USB serial port found yet"
                self.status = "Reconnecting (waiting for ESP USB)…"
            }
            trace("SERIAL_AUTOCONNECT", "No candidate port available; waiting for enumeration")
            autoReconnectIfNeeded(reason: "no candidate")
            return
        }

        if isConnected, selectedPort == path {
            trace("SERIAL_AUTOCONNECT", "Already connected to \(path)")
            return
        }

        if isOpeningPort, openingPortPath == path {
            trace("SERIAL_RECONNECT_LOOP", "Connect already in progress for \(path)")
            return
        }

        wantsConnection = true
        reconnectWorkItem?.cancel()
        reconnectWorkItem = nil
        publish {
            self.selectedPort = path
            self.preferredPort = path
            self.lastError = nil
            self.status = "Connecting…"
        }
        trace("SERIAL_PORT_SELECT", "Selected port \(path)")

#if canImport(ORSSerial)
        connectUsingORSSerial(path)
#else
        connectUsingFallbackPOSIX(path)
#endif
    }

    func disconnect(userInitiated: Bool = true) {
        if userInitiated {
            wantsConnection = false
        }

        reconnectWorkItem?.cancel()
        reconnectWorkItem = nil

#if canImport(ORSSerial)
        closeCurrentPort(preserveDesiredConnection: !userInitiated)
#else
        closeFallbackPort(preserveDesiredConnection: !userInitiated)
#endif

        if userInitiated {
            publish {
                self.status = "Disconnected"
            }
        }
    }

    func forceReconnect() {
        wantsConnection = true
        disconnect(userInitiated: false)
        autoReconnectIfNeeded(reason: "force reconnect")
    }

    func setEspView(_ view: EspView) {
        sendLine("view:\(view.rawValue)")
    }

    func sendView(screen: String) {
        let normalized = screen.lowercased()
        switch normalized {
        case "music":
            setEspView(.music)
        case "focus":
            setEspView(.focus)
        case "tasks":
            setEspView(.tasks)
        case "habits":
            setEspView(.habits)
        case "ai", "coach":
            setEspView(.coach)
        case "gamify", "game":
            setEspView(.game)
        case "stats":
            setEspView(.stats)
        case "settings":
            setEspView(.settings)
        case "debug":
            setEspView(.debug)
        case "idle", "home":
            setEspView(.idle)
        default:
            sendLine("view:\(sanitize(normalized))")
        }
    }

    func sendTime(_ payload: String) {
        let parts = payload.components(separatedBy: "|")
        if parts.count >= 2 {
            let timePart = sanitize(parts[0])
            let datePart = sanitize(parts[1])
            sendLine("time:\(timePart)|\(datePart)")
        } else {
            sendLine("time:\(sanitize(payload))")
        }
    }

    func sendCurrentTime(date: Date = Date()) {
        let timeFormatter = DateFormatter()
        timeFormatter.locale = Locale(identifier: "en_US_POSIX")
        timeFormatter.dateFormat = "HH:mm"
        sendTime(timeFormatter.string(from: date))
    }

    func sendMusic(state: String, artist: String, title: String, progress0to1: Double, vol0to1: Double) {
        let payload = "music:\(sanitize(state.lowercased()))|\(sanitize(artist))|\(sanitize(title))"

        let now = Date()
        let shouldSend = payload != lastMusicPayload || now.timeIntervalSince(lastMusicSentAt) >= 3
        guard shouldSend else { return }

        if sendLine(payload) {
            lastMusicPayload = payload
            lastMusicSentAt = now
        }
    }

    func sendMusic(snapshot: MusicSnapshot) {
        let posSec = max(0, Int(snapshot.positionSeconds.rounded()))
        let durSec = max(0, Int(snapshot.durationSeconds.rounded()))

        let payload: String
        if durSec > 0 {
            payload = "music:\(sanitize(snapshot.state.rawValue.lowercased()))|\(sanitize(snapshot.artist))|\(sanitize(snapshot.title))|\(posSec)|\(durSec)"
        } else {
            payload = "music:\(sanitize(snapshot.state.rawValue.lowercased()))|\(sanitize(snapshot.artist))|\(sanitize(snapshot.title))"
        }

        let now = Date()
        let shouldSend = payload != lastMusicPayload || now.timeIntervalSince(lastMusicSentAt) >= 3
        guard shouldSend else { return }

        if sendLine(payload) {
            lastMusicPayload = payload
            lastMusicSentAt = now
        }
    }

    func sendPomo(phase: String, remaining: Int, total: Int, running: Bool) {
        let runFlag = running ? "1" : "0"
        let payload = "pomo:\(sanitize(phase))|\(remaining)|\(total)|\(runFlag)"

        if running {
            let now = Date()
            let samePayload = payload == lastPomoPayload
            let tooSoon = now.timeIntervalSince(lastPomoSentAt) < 0.95
            if samePayload && tooSoon {
                return
            }

            if sendLine(payload) {
                lastPomoPayload = payload
                lastPomoSentAt = now
                lastPomoRunning = true
            }
            return
        }

        // Send stop transition once.
        if lastPomoRunning {
            if sendLine(payload) {
                lastPomoPayload = payload
                lastPomoSentAt = Date()
            }
        }

        lastPomoRunning = false
    }

    func sendPomodoro(phase: String, remaining: Int, total: Int, running: Bool) {
        sendPomo(phase: phase, remaining: remaining, total: total, running: running)
    }

    func sendHabitPreview(name: String) {
        setEspView(.habits)
        appendLog("Habit preview: \(sanitize(name))")
    }

    func sendHabitsSummary(doneToday: Int, totalToday: Int, streak: Int) {
        let d = max(0, doneToday)
        let t = max(0, totalToday)
        let s = max(0, streak)
        _ = sendLine("habits:\(d)|\(t)|\(s)")
    }

    func sendHabitDetail(id: String, title: String, symbol: String, colorHex: String, streak: Int, doneToday: Bool) {
        let payload = "habit:\(sanitize(id))|\(sanitize(title))|\(sanitize(symbol))|\(sanitize(colorHex))|\(max(0, streak))|\(doneToday ? 1 : 0)"
        _ = sendLine(payload)
    }

    func sendHabitDone(_ idOrTitle: String) {
        _ = sendLine("habit_done:\(sanitize(idOrTitle))")
    }

    func sendGamify(level: Int, values: [Int]) {
        var normalized = values
        if normalized.count < 6 {
            normalized.append(contentsOf: repeatElement(0, count: 6 - normalized.count))
        } else if normalized.count > 6 {
            normalized = Array(normalized.prefix(6))
        }

        let safeLevel = max(0, level)
        let safeValues = normalized.map { max(0, min(100, $0)) }
        let payload = "gamify:\(safeLevel)|\(safeValues[0])|\(safeValues[1])|\(safeValues[2])|\(safeValues[3])|\(safeValues[4])|\(safeValues[5])"

        let now = Date()
        let shouldSend = payload != lastGamifyPayload || now.timeIntervalSince(lastGamifySentAt) >= 2.0
        guard shouldSend else { return }

        if sendLine(payload) {
            lastGamifyPayload = payload
            lastGamifySentAt = now
            publish {
                self.lastGamifyPayload = payload
            }
        }
    }

    func sendAIStyle(_ token: String) {
        let normalized = sanitize(token.lowercased())
        guard normalized.isEmpty == false else { return }

        let allowed: Set<String> = ["orb", "face", "status"]
        guard allowed.contains(normalized) else { return }

        _ = sendLine("ai_style:\(normalized)")
    }

    @discardableResult
    func sendLine(_ rawLine: String) -> Bool {
        guard isConnected else {
            appendLog("drop (disconnected): \(rawLine)")
            return false
        }

#if canImport(ORSSerial)
        guard let port, port.isOpen else {
            appendLog("drop (port closed): \(rawLine)")
            return false
        }

        let line = rawLine.hasSuffix("\n") ? rawLine : rawLine + "\n"
        guard let data = line.data(using: .utf8) else { return false }

        port.send(data)
        appendLog("-> \(rawLine)")
        return true
#else
        guard fallbackFD >= 0 else {
            appendLog("drop (fd closed): \(rawLine)")
            return false
        }

        let line = rawLine.hasSuffix("\n") ? rawLine : rawLine + "\n"
        guard let data = line.data(using: .utf8) else { return false }

        let written = data.withUnsafeBytes { rawBuffer -> Int in
            guard let baseAddress = rawBuffer.baseAddress else { return -1 }
            return Darwin.write(fallbackFD, baseAddress, rawBuffer.count)
        }

        if written < 0 {
            let err = errno
            let message = String(cString: strerror(err))
            appendLog("write error (\(err)): \(message)")
            publish {
                self.lastError = self.isBusyErrno(err) ? self.busyHint : message
                self.status = "Write error"
            }
            closeFallbackPort(preserveDesiredConnection: true)
            autoReconnectIfNeeded(reason: "write error")
            return false
        }

        appendLog("-> \(rawLine)")
        return true
#endif
    }

    // =====================================================
    // MARK: - Internal Wiring
    // =====================================================

    // =====================================================
    // MARK: - Startup AutoConnect
    // [TAG: SERIAL_AUTOCONNECT]
    // =====================================================

    private func scheduleStartupAutoConnect() {
        reconnectWorkItem?.cancel()
        reconnectAttemptCounter = 0

        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard self.autoReconnectEnabled else { return }
            self.wantsConnection = true
            self.refreshPorts()
            self.autoReconnectIfNeeded(reason: "startup")
        }
        reconnectWorkItem = item

        trace("SERIAL_AUTOCONNECT", "Scheduling startup auto-connect after \(startupEnumerationDelay)s")
        DispatchQueue.main.asyncAfter(deadline: .now() + startupEnumerationDelay, execute: item)
    }

    private func startPortScanner() {
        scanTicker = Timer.publish(every: reconnectRetryDelay, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.refreshPorts()
#if canImport(ORSSerial)
                self?.verifyConnectedPortStillPresent()
#else
                self?.verifyFallbackPortStillPresent()
#endif
            }
    }

    private func registerPortNotifications() {
#if canImport(ORSSerial)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handlePortsChanged(_:)),
            name: .ORSSerialPortsWereConnected,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handlePortsChanged(_:)),
            name: .ORSSerialPortsWereDisconnected,
            object: nil
        )
#endif
    }

#if !canImport(ORSSerial)
    private func connectUsingFallbackPOSIX(_ path: String) {
        closeFallbackPort(preserveDesiredConnection: true)
        isOpeningPort = true
        openingPortPath = path

        let fd = Darwin.open(path, O_RDWR | O_NOCTTY | O_NONBLOCK)
        guard fd >= 0 else {
            handleFallbackOpenFailure(path: path, errnoValue: errno)
            return
        }

        guard configureFallbackPort(fd: fd) else {
            let err = errno
            Darwin.close(fd)
            handleFallbackOpenFailure(path: path, errnoValue: err)
            return
        }

        fallbackFD = fd
        fallbackConnectedPath = path
        lastConnectedPortPath = path
        lastConnectedPort = path
        UserDefaults.standard.set(path, forKey: lastConnectedPortDefaultsKey)
        isOpeningPort = false
        openingPortPath = nil
        reconnectAttemptCounter = 0

        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: DispatchQueue.global(qos: .userInitiated))
        source.setEventHandler { [weak self] in
            self?.readFromFallbackFD(fd)
        }
        source.setCancelHandler {
            Darwin.close(fd)
        }
        fallbackReadSource = source
        source.resume()

        publish {
            self.isConnected = true
            self.status = "Connected: \(path)"
            self.lastError = nil
            self.selectedPort = path
            self.preferredPort = path
        }

        trace("SERIAL_AUTOCONNECT", "Opened fallback serial port \(path)")
        startConnectedTimers()
        sendHandshakeHello()
    }

    private func readFromFallbackFD(_ fd: Int32) {
        guard fd == fallbackFD else { return }

        var buffer = [UInt8](repeating: 0, count: 1024)
        while true {
            let count = Darwin.read(fd, &buffer, buffer.count)
            if count > 0 {
                consumeIncoming(Data(buffer.prefix(Int(count))))
                continue
            }

            if count == 0 {
                appendLog("fallback EOF")
                closeFallbackPort(preserveDesiredConnection: true)
                autoReconnectIfNeeded(reason: "fallback eof")
                return
            }

            let err = errno
            if err == EAGAIN || err == EWOULDBLOCK {
                return
            }

            let message = String(cString: strerror(err))
            appendLog("read error (\(err)): \(message)")
            publish {
                self.lastError = message
                self.status = "Read error"
            }
            closeFallbackPort(preserveDesiredConnection: true)
            autoReconnectIfNeeded(reason: "fallback read error")
            return
        }
    }

    private func closeFallbackPort(preserveDesiredConnection: Bool) {
        openTimeoutWorkItem?.cancel()
        openTimeoutWorkItem = nil
        stopConnectedTimers()
        isOpeningPort = false
        openingPortPath = nil

        if preserveDesiredConnection == false {
            wantsConnection = false
        }

        if let source = fallbackReadSource {
            source.cancel()
            fallbackReadSource = nil
        } else if fallbackFD >= 0 {
            Darwin.close(fallbackFD)
        }

        fallbackFD = -1
        fallbackConnectedPath = nil

        publish {
            self.isConnected = false
            self.status = "Disconnected"
        }
    }

    private func configureFallbackPort(fd: Int32) -> Bool {
        var options = termios()
        guard tcgetattr(fd, &options) == 0 else { return false }

        cfmakeraw(&options)

        options.c_cflag |= tcflag_t(CLOCAL | CREAD)
        options.c_cflag &= ~tcflag_t(CSTOPB)
        options.c_cflag &= ~tcflag_t(PARENB)
        options.c_cflag &= ~tcflag_t(CSIZE)
        options.c_cflag |= tcflag_t(CS8)

        let speed: speed_t = speed_t(B115200)
        guard cfsetispeed(&options, speed) == 0, cfsetospeed(&options, speed) == 0 else { return false }
        guard tcsetattr(fd, TCSANOW, &options) == 0 else { return false }
        return true
    }

    private func handleFallbackOpenFailure(path: String, errnoValue: Int32) {
        let message = String(cString: strerror(errnoValue))
        let readable = isBusyErrno(errnoValue) ? busyHint : "Open failed (\(errnoValue)): \(message)"
        isOpeningPort = false
        openingPortPath = nil

        publish {
            self.isConnected = false
            self.status = "Connection failed"
            self.lastError = readable
        }

        trace("SERIAL_OPEN_FAIL", "Fallback open fail \(path) errno=\(errnoValue) \(message)")
        autoReconnectIfNeeded(reason: "fallback open fail")
    }

    private func verifyFallbackPortStillPresent() {
        guard let path = fallbackConnectedPath else { return }
        guard isConnected else { return }

        if availablePorts.contains(path) == false {
            appendLog("fallback port removed: \(path)")
            closeFallbackPort(preserveDesiredConnection: true)
            publish {
                self.status = "Disconnected (port removed)"
            }
            autoReconnectIfNeeded(reason: "fallback removed")
        }
    }

    private func isBusyErrno(_ value: Int32) -> Bool {
        value == EBUSY || value == EACCES || value == EPERM
    }
#endif

#if canImport(ORSSerial)
    @objc
    private func handlePortsChanged(_ note: Notification) {
        trace("SERIAL_RECONNECT_LOOP", "Serial device list changed")
        refreshPorts()
        verifyConnectedPortStillPresent()

        if isConnected == false {
            autoReconnectIfNeeded(reason: "ports changed")
        }
    }
#endif

    private func autoReconnectIfNeeded(reason: String) {
        guard autoReconnectEnabled else { return }
        guard wantsConnection else { return }
        guard isConnected == false else { return }
        guard isOpeningPort == false else {
            trace("SERIAL_RECONNECT_LOOP", "Reconnect skipped, open already in progress (\(openingPortPath ?? "?"))")
            return
        }

        reconnectAttemptCounter += 1

        reconnectWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard self.isConnected == false else { return }

            self.refreshPorts()
            guard self.isConnected == false else { return }

            if let target = self.reconnectCandidate() {
                self.trace("SERIAL_RECONNECT_LOOP", "Attempt \(self.reconnectAttemptCounter) (\(reason)) -> \(target)")
                self.connect(to: target)
            } else {
                self.publish {
                    self.status = "Reconnecting (waiting for ESP USB)…"
                }
                self.trace("SERIAL_PORT_SELECT", "No port candidate found on attempt \(self.reconnectAttemptCounter)")
            }
        }
        reconnectWorkItem = item
        trace("SERIAL_RECONNECT_LOOP", "Scheduling reconnect in \(reconnectRetryDelay)s (reason: \(reason))")
        DispatchQueue.main.asyncAfter(deadline: .now() + reconnectRetryDelay, execute: item)
    }

    private func reconnectCandidate() -> String? {
        let details = availablePortDebugInfo
        guard details.isEmpty == false else { return nil }

        let directPreference: [String?] = [
            selectedPort,
            preferredPort,
            lastConnectedPortPath,
            lastConnectedPort
        ]

        for preferred in directPreference {
            guard let preferred else { continue }
            if details.contains(where: { $0.path == preferred }) {
                trace("SERIAL_PORT_SELECT", "Using preferred/last-known port \(preferred)")
                return preferred
            }
        }

        let ranked = details
            .map { ($0, self.score(port: $0)) }
            .sorted { lhs, rhs in
                if lhs.1 == rhs.1 {
                    return lhs.0.path < rhs.0.path
                }
                return lhs.1 > rhs.1
            }

        if let best = ranked.first?.0 {
            trace("SERIAL_PORT_SELECT", "Best-match port \(best.path) (score \(ranked.first?.1 ?? 0))")
            return best.path
        }

        return nil
    }

    private func score(port: SerialPortDebugInfo) -> Int {
        let normalizedPath = port.path.lowercased()
        let normalizedName = port.name.lowercased()
        var score = 0

        if port.path == lastConnectedPortPath || port.path == lastConnectedPort {
            score += 100
        }
        if port.path == preferredPort || port.path == selectedPort {
            score += 60
        }

        if normalizedPath.contains("usbmodem") || normalizedName.contains("usbmodem") {
            score += 30
        }
        if normalizedPath.contains("usbserial") || normalizedName.contains("usbserial") {
            score += 30
        }
        if normalizedPath.contains("wch") || normalizedName.contains("wch") {
            score += 15
        }
        if normalizedPath.contains("slab") || normalizedName.contains("cp210") {
            score += 15
        }
        if normalizedName.contains("ch340") {
            score += 15
        }
        if normalizedName.contains("esp") || normalizedPath.contains("esp") {
            score += 20
        }

        if let vendorID = port.vendorID, espVendorIDs.contains(vendorID) {
            score += 25
        }

        // Common ESP bridge product IDs (if available in future metadata).
        if let productID = port.productID, [0xEA60, 0x7523, 0x55D4].contains(productID) {
            score += 20
        }

        return score
    }

#if canImport(ORSSerial)
    private func connectUsingORSSerial(_ path: String) {
        closeCurrentPort(preserveDesiredConnection: true)
        isOpeningPort = true
        openingPortPath = path

        guard let serial = ORSSerialPort(path: path) else {
            isOpeningPort = false
            openingPortPath = nil
            publish {
                self.status = "Invalid serial port"
                self.lastError = "Could not create ORSSerialPort for \(path)"
                self.isConnected = false
            }
            trace("SERIAL_OPEN_FAIL", "Invalid ORSSerial path \(path)")
            autoReconnectIfNeeded(reason: "invalid path")
            return
        }

        serial.delegate = self
        serial.baudRate = 115200
        serial.parity = .none
        serial.numberOfStopBits = 1
        serial.usesRTSCTSFlowControl = false

        port = serial
        inputBuffer.removeAll(keepingCapacity: false)
        hasAnnouncedOpen = false

        trace("SERIAL_AUTOCONNECT", "Opening ORSSerial port \(path)")
        serial.open()
        if serial.isOpen {
            handleOpened(serial)
        } else {
            scheduleOpenTimeout(for: path)
        }
    }

    private func closeCurrentPort(preserveDesiredConnection: Bool) {
        openTimeoutWorkItem?.cancel()
        openTimeoutWorkItem = nil
        stopConnectedTimers()
        isOpeningPort = false
        openingPortPath = nil

        if preserveDesiredConnection == false {
            wantsConnection = false
        }

        guard let current = port else {
            publish {
                self.isConnected = false
                self.status = "Disconnected"
            }
            return
        }

        current.delegate = nil
        if current.isOpen {
            current.close()
        }
        port = nil

        publish {
            self.isConnected = false
            self.status = "Disconnected"
        }
        trace("SERIAL_AUTOCONNECT", "Disconnected serial port")
    }

    private func scheduleOpenTimeout(for path: String) {
        openTimeoutWorkItem?.cancel()

        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard self.isConnected == false else { return }
            guard self.port?.path == path else { return }
            guard self.port?.isOpen == false else {
                if let livePort = self.port {
                    self.handleOpened(livePort)
                }
                return
            }

            self.publish {
                self.status = "Connection failed"
                self.lastError = self.busyHint
            }
            self.trace("SERIAL_OPEN_FAIL", "Open timeout on \(path)")
            self.closeCurrentPort(preserveDesiredConnection: true)
            self.autoReconnectIfNeeded(reason: "open timeout")
        }

        openTimeoutWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8, execute: item)
    }

    private func verifyConnectedPortStillPresent() {
        guard let connectedPath = port?.path else { return }
        guard isConnected else { return }

        if availablePorts.contains(connectedPath) == false {
            appendLog("port removed from /dev: \(connectedPath)")
            handlePortRemoval(path: connectedPath)
        }
    }

    private func handlePortRemoval(path: String) {
        closeCurrentPort(preserveDesiredConnection: true)
        publish {
            self.status = "Disconnected (port removed)"
        }
        autoReconnectIfNeeded(reason: "port removed")
    }
#endif

    private func startConnectedTimers() {
        stopConnectedTimers()
        missedHeartbeats = 0
        lastPongAt = Date()
        hasSeenPongInSession = false

        sendCurrentTime()
        timeTicker = Timer.publish(every: 15, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.sendCurrentTime()
            }

        heartbeatTicker = Timer.publish(every: heartbeatInterval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.sendHeartbeatPing()
            }
    }

    private func stopConnectedTimers() {
        timeTicker?.cancel()
        timeTicker = nil
        heartbeatTicker?.cancel()
        heartbeatTicker = nil
    }

    private func consumeIncoming(_ data: Data) {
        guard data.isEmpty == false else { return }

        inputBuffer.append(data)
        while let newlineRange = inputBuffer.range(of: Data([0x0A])) {
            let lineData = inputBuffer.subdata(in: 0..<newlineRange.lowerBound)
            inputBuffer.removeSubrange(0...newlineRange.lowerBound)

            guard var line = String(data: lineData, encoding: .utf8) else { continue }
            line = line.replacingOccurrences(of: "\r", with: "")
            guard line.isEmpty == false else { continue }

            appendLog("<- \(line)")
            parseIncomingLine(line)
        }
    }

    private func parseIncomingLine(_ line: String) {
        let normalized = line.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        if normalized == "pong" {
            lastPongAt = Date()
            missedHeartbeats = 0
            hasSeenPongInSession = true
            publish {
                if self.isConnected {
                    self.status = "Connected: \(self.selectedPort ?? self.lastConnectedPort ?? "ESP")"
                }
            }
            trace("SERIAL_HANDSHAKE", "Pong received")
            return
        }

        if line.hasPrefix("hello:esp") {
            parseHello(line)
            return
        }

        if line.hasPrefix("status:") {
            let message = String(line.dropFirst("status:".count))
            publish { self.status = message }
            return
        }

        if line.hasPrefix("fw:") {
            let fw = String(line.dropFirst("fw:".count))
            publish {
                self.firmwareVersion = fw
                self.helloFirmware = fw
            }
            return
        }

        if line.hasPrefix("err:") {
            let message = String(line.dropFirst("err:".count))
            publish {
                self.lastError = message
                self.status = "ESP error"
            }
            return
        }
    }

    private func parseHello(_ line: String) {
        var proto: Int?
        var fw: String?
        var screen: String?

        for token in line.split(separator: "|").map(String.init) {
            if token.hasPrefix("proto=") {
                proto = Int(token.dropFirst("proto=".count))
            } else if token.hasPrefix("fw=") {
                fw = String(token.dropFirst("fw=".count))
            } else if token.hasPrefix("screen=") {
                screen = String(token.dropFirst("screen=".count))
            }
        }

        publish {
            self.helloProtoVersion = proto
            self.helloFirmware = fw
            self.helloScreen = screen
            if let fw {
                self.firmwareVersion = fw
            }
            self.status = "Handshake OK"
        }

        trace("SERIAL_HANDSHAKE", "hello parsed: proto=\(proto.map(String.init) ?? "?") fw=\(fw ?? "?") screen=\(screen ?? "?")")
        lastPongAt = Date()
        missedHeartbeats = 0
    }

    // =====================================================
    // MARK: - Handshake / Heartbeat
    // [TAG: SERIAL_HANDSHAKE]
    // =====================================================

    private func sendHandshakeHello() {
        _ = sendLine("hello:maddyv2|proto=2")
        trace("SERIAL_HANDSHAKE", "Sent hello:maddyv2|proto=2")
    }

    private func sendHeartbeatPing() {
        guard isConnected else { return }

        // Do not force ping/pong on firmware that has not yet demonstrated pong support.
        if hasSeenPongInSession == false {
            missedHeartbeats += 1
            if missedHeartbeats == 1 || missedHeartbeats % 3 == 0 {
                sendHandshakeHello()
                trace("SERIAL_HANDSHAKE", "No pong support detected yet; sent hello probe")
            }
            return
        }

        _ = sendLine("ping")
        trace("SERIAL_HANDSHAKE", "Sent ping")

        missedHeartbeats += 1
        if missedHeartbeats <= maxMissedHeartbeats {
            return
        }

        let secondsWithoutPong: Int
        if lastPongAt == .distantPast {
            secondsWithoutPong = Int((Double(missedHeartbeats) * heartbeatInterval).rounded())
        } else {
            secondsWithoutPong = Int(Date().timeIntervalSince(lastPongAt).rounded())
        }

        if hasSeenPongInSession == false {
            // Some firmware builds may not implement pong yet. Keep the link alive and keep trying.
            publish {
                self.status = "Connected (awaiting heartbeat)…"
                self.lastError = nil
            }
            if missedHeartbeats % 3 == 0 {
                sendHandshakeHello()
            }
            trace("SERIAL_HANDSHAKE", "No pong yet (\(secondsWithoutPong)s). Keeping connection open.")
            return
        }

        trace("SERIAL_RECONNECT_LOOP", "Heartbeat timeout after \(secondsWithoutPong)s without pong")
        publish {
            self.status = "Reconnecting (heartbeat timeout)…"
            self.lastError = "Missed heartbeat (\(self.missedHeartbeats) pings)"
        }

#if canImport(ORSSerial)
        closeCurrentPort(preserveDesiredConnection: true)
#else
        closeFallbackPort(preserveDesiredConnection: true)
#endif
        autoReconnectIfNeeded(reason: "heartbeat timeout")
    }

    private func appendLog(_ line: String) {
        publish {
            let stamp = DateFormatter.serialLog.string(from: Date())
            self.debugLines.append("[\(stamp)] \(line)")
            if self.debugLines.count > self.maxDebugLines {
                self.debugLines.removeFirst(self.debugLines.count - self.maxDebugLines)
            }
        }
    }

    private func publish(_ updates: @escaping () -> Void) {
        if Thread.isMainThread {
            updates()
        } else {
            DispatchQueue.main.async(execute: updates)
        }
    }

    private func sanitize(_ value: String) -> String {
        value
            .replacingOccurrences(of: "|", with: "/")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func trace(_ tag: String, _ message: String) {
        print("[TAG: \(tag)] \(message)")
        appendLog("[TAG: \(tag)] \(message)")
    }

    private static func serialPortDetails() -> [SerialPortDebugInfo] {
#if canImport(ORSSerial)
        let all = ORSSerialPortManager.shared().availablePorts.map { port in
            SerialPortDebugInfo(
                path: port.path,
                name: port.name,
                vendorID: nil,
                productID: nil
            )
        }
#else
        let all = usbPathsFallback().map { path in
            SerialPortDebugInfo(
                path: path,
                name: URL(fileURLWithPath: path).lastPathComponent,
                vendorID: nil,
                productID: nil
            )
        }
#endif

        let filtered = all.filter {
            $0.path.hasPrefix("/dev/cu.") && (
                $0.path.localizedCaseInsensitiveContains("usb") ||
                $0.path.localizedCaseInsensitiveContains("modem") ||
                $0.path.localizedCaseInsensitiveContains("serial") ||
                $0.path.localizedCaseInsensitiveContains("wch") ||
                $0.path.localizedCaseInsensitiveContains("slab") ||
                $0.name.localizedCaseInsensitiveContains("usb") ||
                $0.name.localizedCaseInsensitiveContains("serial") ||
                $0.name.localizedCaseInsensitiveContains("esp")
            )
        }

        if filtered.isEmpty {
            return all
                .filter { $0.path.hasPrefix("/dev/cu.") }
                .sorted { $0.path < $1.path }
        }

        return filtered.sorted { $0.path < $1.path }
    }

#if !canImport(ORSSerial)
    private static func usbPathsFallback() -> [String] {
        let devURL = URL(fileURLWithPath: "/dev")
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: devURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return items.map(\.path)
    }
#endif
}

// =====================================================
// MARK: - ORSSerial Delegate
// [TAG: V2_SERIAL_ORS_DELEGATE]
// =====================================================

#if canImport(ORSSerial)
extension SerialService: ORSSerialPortDelegate {
    func serialPortWasOpened(_ serialPort: ORSSerialPort) {
        guard serialPort === port else {
            trace("SERIAL_RECONNECT_LOOP", "Ignoring stale open callback for \(serialPort.path)")
            return
        }
        handleOpened(serialPort)
    }

    private func handleOpened(_ serialPort: ORSSerialPort) {
        guard hasAnnouncedOpen == false else { return }
        hasAnnouncedOpen = true
        isOpeningPort = false
        openingPortPath = nil

        openTimeoutWorkItem?.cancel()
        openTimeoutWorkItem = nil

        lastConnectedPortPath = serialPort.path
        lastConnectedPort = serialPort.path
        UserDefaults.standard.set(serialPort.path, forKey: lastConnectedPortDefaultsKey)
        reconnectAttemptCounter = 0

        publish {
            self.isConnected = true
            self.status = "Connected: \(serialPort.path)"
            self.lastError = nil
            self.selectedPort = serialPort.path
            self.preferredPort = serialPort.path
        }

        trace("SERIAL_AUTOCONNECT", "Opened \(serialPort.path)")
        startConnectedTimers()

        sendHandshakeHello()
    }

    func serialPortWasClosed(_ serialPort: ORSSerialPort) {
        guard serialPort === port || serialPort.path == openingPortPath else {
            trace("SERIAL_RECONNECT_LOOP", "Ignoring stale close callback for \(serialPort.path)")
            return
        }

        hasAnnouncedOpen = false
        isOpeningPort = false
        openingPortPath = nil
        publish {
            self.isConnected = false
            if self.status.hasPrefix("Disconnected") == false {
                self.status = "Disconnected"
            }
        }

        trace("SERIAL_RECONNECT_LOOP", "Closed \(serialPort.path)")
        stopConnectedTimers()

        if wantsConnection {
            autoReconnectIfNeeded(reason: "closed")
        }
    }

    func serialPortWasRemovedFromSystem(_ serialPort: ORSSerialPort) {
        guard serialPort === port || serialPort.path == openingPortPath else {
            trace("SERIAL_RECONNECT_LOOP", "Ignoring stale removed callback for \(serialPort.path)")
            return
        }
        hasAnnouncedOpen = false
        isOpeningPort = false
        openingPortPath = nil
        trace("SERIAL_RECONNECT_LOOP", "Removed from system: \(serialPort.path)")
        handlePortRemoval(path: serialPort.path)
    }

    func serialPort(_ serialPort: ORSSerialPort, didEncounterError error: Error) {
        guard serialPort === port || serialPort.path == openingPortPath else {
            trace("SERIAL_RECONNECT_LOOP", "Ignoring stale error callback for \(serialPort.path): \(error.localizedDescription)")
            return
        }

        hasAnnouncedOpen = false
        isOpeningPort = false
        openingPortPath = nil
        let description = error.localizedDescription
        trace("SERIAL_OPEN_FAIL", "Serial error on \(serialPort.path): \(description)")

        let message: String
        if isBusyError(description) {
            message = busyHint
        } else {
            message = description
        }

        publish {
            self.lastError = message
            self.status = "Serial error"
            self.isConnected = false
        }

        closeCurrentPort(preserveDesiredConnection: true)

        if wantsConnection {
            autoReconnectIfNeeded(reason: "error")
        }
    }

    func serialPort(_ serialPort: ORSSerialPort, didReceive data: Data) {
        guard serialPort === port else { return }
        consumeIncoming(data)
    }

    func serialPort(_ serialPort: ORSSerialPort, didSend data: Data) {
        guard serialPort === port else { return }
        // Logged in sendLine(_:)
    }

    private func isBusyError(_ message: String) -> Bool {
        let lowered = message.lowercased()
        return lowered.contains("resource busy") ||
            lowered.contains("busy") ||
            lowered.contains("permission denied") ||
            lowered.contains("locked") ||
            lowered.contains("ebusy")
    }
}
#endif

private extension DateFormatter {
    static let serialLog: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}
