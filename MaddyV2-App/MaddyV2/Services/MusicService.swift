//
//  MusicService.swift
//  MaddyV2
//
//  Created by Arber on 03.03.26.
//

import Foundation
import Combine
import AppKit

// =====================================================
// MARK: - Music Models
// [TAG: V2_MUSIC_MODELS]
// =====================================================

enum MusicPlaybackState: String, Codable {
    case playing
    case paused
    case stopped
}

struct MusicSnapshot: Equatable {
    var state: MusicPlaybackState
    var artist: String
    var title: String
    var album: String
    var progress: Double
    var volume: Double
    var positionSeconds: Double
    var durationSeconds: Double

    static let empty = MusicSnapshot(
        state: .stopped,
        artist: "",
        title: "",
        album: "",
        progress: 0,
        volume: 0.5,
        positionSeconds: 0,
        durationSeconds: 0
    )

    var progressString: String {
        String(format: "%.3f", progress.clamped(to: 0...1))
    }

    var volumeString: String {
        String(format: "%.3f", volume.clamped(to: 0...1))
    }
}

// =====================================================
// MARK: - MusicService
// [TAG: V2_MUSIC_SERVICE]
// =====================================================

@MainActor
final class MusicService: ObservableObject {
    @Published var snapshot: MusicSnapshot = .empty
    @Published var coverArt: NSImage?
    @Published var lastError: String?
    @Published var permissionMessage: String?

    private var pollIntervalSeconds: TimeInterval = 3
    private var pollTimer: Timer?
    private var pollInFlight = false
    private var artworkKey: String = ""

    private let workerQueue = DispatchQueue(label: "maddyv2.music.worker", qos: .userInitiated)

    private let notAuthorizedMessage = "Not authorized. Enable Automation permission for MaddyV2 in System Settings → Privacy & Security → Automation."

    // =====================================================
    // MARK: - Public API
    // =====================================================

    func setPollingInterval(seconds: Double) {
        pollIntervalSeconds = max(1, seconds)
        if pollTimer != nil {
            startPolling()
        }
    }

    func startPolling() {
        stopPolling()
        pollNow()

        pollTimer = Timer.scheduledTimer(withTimeInterval: pollIntervalSeconds, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.pollNow()
            }
        }

        if let pollTimer {
            RunLoop.main.add(pollTimer, forMode: .common)
        }
    }

    func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    func playPause() {
        runControlScript(Self.playPauseScript)
    }

    func togglePlayPause() {
        playPause()
    }

    func nextTrack() {
        runControlScript(Self.nextTrackScript)
    }

    func previousTrack() {
        runControlScript(Self.previousTrackScript)
    }

    func setVolume(_ value: Double) {
        let clamped = min(max(value, 0), 1)
        let volumePercent = Int((clamped * 100).rounded())
        runControlScript(Self.setVolumeScript(volumePercent))

        var updated = snapshot
        updated.volume = clamped
        snapshot = updated
    }

    func pollNow() {
        guard pollInFlight == false else { return }
        pollInFlight = true

        let stateScript = Self.stateQueryScript
        let albumScript = Self.albumQueryScript

        workerQueue.async { [weak self] in
            guard let self else { return }

            if Self.isMusicRunning() == false {
                Task { @MainActor in
                    self.pollInFlight = false
                    self.permissionMessage = nil
                    self.lastError = nil
                    self.snapshot = .empty
                    self.coverArt = nil
                }
                return
            }

            let stateResult = Self.runAppleScriptWithRetryAndFallback(stateScript)
            var albumValue = ""

            if Self.isAuthorizationError(stateResult.errorOutput) == false,
               stateResult.exitCode == 0 {
                let parts = Self.parsePipeFields(stateResult.standardOutput)
                let title = parts[safe: 2] ?? ""
                if title.isEmpty == false {
                    let albumResult = Self.runAppleScriptWithRetryAndFallback(albumScript)
                    if albumResult.exitCode == 0 {
                        albumValue = albumResult.standardOutput
                    }
                }
            }
            let albumValueFinal = albumValue

            Task { @MainActor in
                self.pollInFlight = false
                self.applyStateResult(stateResult, album: albumValueFinal)
            }
        }
    }

    // =====================================================
    // MARK: - Internals
    // =====================================================

    private func runControlScript(_ script: String) {
        workerQueue.async { [weak self] in
            guard let self else { return }
            guard Self.isMusicRunning() else {
                Task { @MainActor in
                    self.permissionMessage = nil
                    self.lastError = "Music.app is not running."
                }
                return
            }

            let result = Self.runAppleScriptWithRetryAndFallback(script)

            Task { @MainActor in
                if Self.isAuthorizationError(result.errorOutput) {
                    self.permissionMessage = self.notAuthorizedMessage
                    self.lastError = self.notAuthorizedMessage
                } else if result.exitCode != 0 {
                    self.permissionMessage = nil
                    if Self.isMusicNotRunningError(result.errorOutput) {
                        self.lastError = "Music app not reachable (-600). Open Music.app once and retry."
                    } else {
                        self.lastError = result.errorOutput.isEmpty ? "Music command failed" : result.errorOutput
                    }
                } else {
                    self.permissionMessage = nil
                    self.lastError = nil
                }

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                    self?.pollNow()
                }
            }
        }
    }

    private func applyStateResult(_ result: ScriptExecutionResult, album: String) {
        if Self.isAuthorizationError(result.errorOutput) {
            permissionMessage = notAuthorizedMessage
            lastError = notAuthorizedMessage
            snapshot = .empty
            coverArt = nil
            artworkKey = ""
            return
        }

        guard result.exitCode == 0 else {
            permissionMessage = nil
            if Self.isMusicNotRunningError(result.errorOutput) {
                lastError = nil
                snapshot = .empty
                coverArt = nil
                artworkKey = ""
                return
            }
            lastError = result.errorOutput.isEmpty ? "Music query failed" : result.errorOutput
            snapshot = .empty
            coverArt = nil
            artworkKey = ""
            return
        }

        let parts = Self.parsePipeFields(result.standardOutput)
        guard parts.count == 6 else {
            permissionMessage = nil
            lastError = "Unexpected Music response"
            snapshot = .empty
            coverArt = nil
            artworkKey = ""
            return
        }

        let state = Self.mapState(parts[0])
        let artist = parts[1]
        let title = parts[2]
        let position = max(0, Self.parseLocalizedDouble(parts[3]) ?? 0)
        let duration = max(0, Self.parseLocalizedDouble(parts[4]) ?? 0)
        let volumePercent = min(max(Self.parseLocalizedDouble(parts[5]) ?? 50, 0), 100)

        let progress: Double
        if duration > 0 {
            progress = min(max(position / duration, 0), 1)
        } else {
            progress = 0
        }

        snapshot = MusicSnapshot(
            state: state,
            artist: artist,
            title: title,
            album: album,
            progress: progress,
            volume: volumePercent / 100,
            positionSeconds: position,
            durationSeconds: duration
        )

        refreshCoverArtIfNeeded(for: snapshot)

        permissionMessage = nil
        lastError = nil
    }

    private func refreshCoverArtIfNeeded(for snapshot: MusicSnapshot) {
        guard snapshot.title.isEmpty == false else {
            coverArt = nil
            artworkKey = ""
            return
        }

        let key = "\(snapshot.artist)|\(snapshot.title)|\(snapshot.album)"
        if key == artworkKey, coverArt != nil {
            return
        }
        artworkKey = key

        workerQueue.async { [weak self] in
            guard let self else { return }
            let result = Self.runAppleScriptWithRetryAndFallback(Self.artworkExportScript)
            var image: NSImage?
            if result.exitCode == 0 {
                let path = result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
                if path.isEmpty == false {
                    image = NSImage(contentsOfFile: path)
                }
            }
            let loadedImage = image

            Task { @MainActor in
                guard self.artworkKey == key else { return }
                self.coverArt = loadedImage
            }
        }
    }

    private nonisolated static func mapState(_ raw: String) -> MusicPlaybackState {
        let lowered = raw.lowercased()
        if lowered.contains("play") { return .playing }
        if lowered.contains("pause") { return .paused }
        return .stopped
    }

    private nonisolated static func parsePipeFields(_ value: String) -> [String] {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: "|")
    }

    private nonisolated static func isAuthorizationError(_ stderr: String) -> Bool {
        let text = stderr.lowercased()
        if text.isEmpty { return false }

        return text.contains("-1743") ||
            text.contains("not authorized") ||
            text.contains("not authorised") ||
            text.contains("not permitted") ||
            text.contains("automation")
    }

    private nonisolated static func runAppleScript(_ source: String) -> ScriptExecutionResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-"]

        let input = Pipe()
        let output = Pipe()
        let errors = Pipe()

        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors

        do {
            try process.run()
        } catch {
            return ScriptExecutionResult(
                standardOutput: "",
                errorOutput: error.localizedDescription,
                exitCode: -1
            )
        }

        if let data = source.data(using: .utf8) {
            input.fileHandleForWriting.write(data)
        }
        input.fileHandleForWriting.closeFile()

        process.waitUntilExit()

        let outData = output.fileHandleForReading.readDataToEndOfFile()
        let errData = errors.fileHandleForReading.readDataToEndOfFile()

        let stdout = String(data: outData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let stderr = String(data: errData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        return ScriptExecutionResult(
            standardOutput: stdout,
            errorOutput: stderr,
            exitCode: process.terminationStatus
        )
    }

    private nonisolated static func runAppleScriptWithRetryAndFallback(_ source: String) -> ScriptExecutionResult {
        var result = runAppleScript(source)
        guard isMusicNotRunningError(result.errorOutput) else { return result }

        launchMusicAppIfNeeded()
        usleep(900_000)
        result = runAppleScript(source)
        guard isMusicNotRunningError(result.errorOutput) else { return result }

        usleep(180_000)
        result = runAppleScript(source)
        guard isMusicNotRunningError(result.errorOutput) else { return result }

        usleep(420_000)
        result = runAppleScript(source)
        guard isMusicNotRunningError(result.errorOutput) else { return result }

        // Fallback for environments where app-id targeting intermittently fails.
        let fallbackSource = source.replacingOccurrences(
            of: "application id \"com.apple.Music\"",
            with: "application \"Music\""
        )
        result = runAppleScript(fallbackSource)
        if isMusicNotRunningError(result.errorOutput) {
            let fallbackGerman = source.replacingOccurrences(
                of: "application id \"com.apple.Music\"",
                with: "application \"Musik\""
            )
            return runAppleScript(fallbackGerman)
        }
        return result
    }

    private nonisolated static func isMusicRunning() -> Bool {
        NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music")
            .contains { !$0.isTerminated }
    }

    private nonisolated static func isMusicNotRunningError(_ stderr: String) -> Bool {
        let text = stderr.lowercased()
        return text.contains("-600") || text.contains("program läuft nicht") || text.contains("application isn’t running")
    }

    private nonisolated static func parseLocalizedDouble(_ value: String) -> Double? {
        if let direct = Double(value) {
            return direct
        }

        let normalized = value.replacingOccurrences(of: ",", with: ".")
        if let normalizedValue = Double(normalized) {
            return normalizedValue
        }

        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.numberStyle = .decimal
        if let number = formatter.number(from: value) {
            return number.doubleValue
        }

        return nil
    }

    private nonisolated static func launchMusicAppIfNeeded() {
        if isMusicRunning() { return }

        let launchBlock = {
            let candidatePaths = [
                "/System/Applications/Music.app",
                "/Applications/Music.app",
                "/Applications/Musik.app"
            ]

            for path in candidatePaths {
                let url = URL(fileURLWithPath: path)
                if FileManager.default.fileExists(atPath: url.path) {
                    NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
                    return
                }
            }

            if let bundleURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Music") {
                NSWorkspace.shared.openApplication(at: bundleURL, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
            }
        }

        if Thread.isMainThread {
            launchBlock()
        } else {
            DispatchQueue.main.sync {
                launchBlock()
            }
        }
    }

    private nonisolated static let stateQueryScript: String = """
    on sanitizeText(t)
        set s to t as text
        set AppleScript's text item delimiters to {"|", return, linefeed}
        set cleanedItems to every text item of s
        set AppleScript's text item delimiters to " "
        set outText to cleanedItems as text
        set AppleScript's text item delimiters to ""
        return outText
    end sanitizeText

    tell application id "com.apple.Music"
        set pState to (player state as text)
        set pVol to (sound volume as integer)

        if exists current track then
            set tName to my sanitizeText(name of current track)
            set tArtist to my sanitizeText(artist of current track)
            set tDuration to (duration of current track as real)
            set tPosition to (player position as real)
            return pState & "|" & tArtist & "|" & tName & "|" & tPosition & "|" & tDuration & "|" & pVol
        else
            return pState & "|||0|0|" & pVol
        end if
    end tell
    """

    private nonisolated static let albumQueryScript: String = """
    on sanitizeText(t)
        set s to t as text
        set AppleScript's text item delimiters to {"|", return, linefeed}
        set cleanedItems to every text item of s
        set AppleScript's text item delimiters to " "
        set outText to cleanedItems as text
        set AppleScript's text item delimiters to ""
        return outText
    end sanitizeText

    tell application id "com.apple.Music"
        if exists current track then
            return my sanitizeText(album of current track)
        end if

        return ""
    end tell
    """

    private nonisolated static let artworkExportScript: String = """
    set outputFile to POSIX file "/tmp/maddyv2_music_artwork.jpg"
    tell application id "com.apple.Music"
        if exists current track then
            if (count of artworks of current track) > 0 then
                try
                    set rawData to data of artwork 1 of current track
                    set fh to open for access outputFile with write permission
                    set eof fh to 0
                    write rawData to fh
                    close access fh
                    return POSIX path of outputFile
                on error
                    try
                        close access outputFile
                    end try
                end try
            end if
        end if
    end tell
    return ""
    """

    private nonisolated static let playPauseScript = "tell application id \"com.apple.Music\" to playpause"

    private nonisolated static let nextTrackScript = "tell application id \"com.apple.Music\" to next track"

    private nonisolated static let previousTrackScript = "tell application id \"com.apple.Music\" to previous track"

    private nonisolated static func setVolumeScript(_ volumePercent: Int) -> String {
        "tell application id \"com.apple.Music\" to set sound volume to \(volumePercent)"
    }
}

private struct ScriptExecutionResult {
    let standardOutput: String
    let errorOutput: String
    let exitCode: Int32
}
