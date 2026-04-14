import CoreHaptics
import AVFoundation
import UIKit
import Combine

@Observable
class HapticEngineManager {
    var isHapticEnabled = true {
        didSet {
            if isHapticEnabled {
                resumeIfPlaying()
            } else {
                pauseAllPlayers()
            }
        }
    }

    private(set) var isLoaded = false

    private var engine: CHHapticEngine?
    private var chunkPatterns: [[CHHapticPattern.Key: Any]] = []
    private var activePlayer: CHHapticAdvancedPatternPlayer?
    private var currentChunkIndex: Int = -1
    private var timeObserverToken: Any?
    private weak var avPlayer: AVPlayer?
    private var statusObservation: AnyCancellable?
    private var chunkDuration: TimeInterval = 30.0
    private var totalDuration: TimeInterval = 0
    private var backgroundObservers: [Any] = []

    static var supportsHaptics: Bool {
        CHHapticEngine.capabilitiesForHardware().supportsHaptics
    }

    func loadAHAP(from url: URL) throws {
        guard Self.supportsHaptics else { return }

        let data = try Data(contentsOf: url)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let pattern = json["Pattern"] as? [[String: Any]] else {
            return
        }

        let metadata = json["Metadata"] as? [String: Any]
        totalDuration = metadata?["TotalDuration"] as? TimeInterval ?? 30.0
        let totalChunks = metadata?["TotalChunks"] as? Int ?? 1
        chunkDuration = metadata?["SegmentDuration"] as? TimeInterval ?? 30.0
        // The actual chunk duration for splitting is always 30s
        let splitDuration: TimeInterval = 30.0

        if totalChunks <= 1 && totalDuration <= 30.0 {
            // Single chunk — use as-is
            chunkPatterns = [convertToPatternDict(version: 1.0, pattern: pattern)]
        } else {
            // Split into 30s chunks by absolute time
            chunkPatterns = splitIntoChunks(pattern: pattern, chunkDuration: splitDuration, totalDuration: totalDuration)
        }

        try setupEngine()
        isLoaded = true
    }

    func attachToPlayer(_ player: AVPlayer) {
        detach()
        avPlayer = player

        // Periodic time observer for chunk sync
        let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
        timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            self?.handleTimeUpdate(CMTimeGetSeconds(time))
        }

        // Observe play/pause via timeControlStatus
        statusObservation = player.publisher(for: \.timeControlStatus)
            .sink { [weak self] status in
                guard let self else { return }
                switch status {
                case .playing:
                    self.resumeIfPlaying()
                case .paused, .waitingToPlayAtSpecifiedRate:
                    self.pauseAllPlayers()
                @unknown default:
                    break
                }
            }

        // Handle app backgrounding
        let bgObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.stopEngine()
        }

        let fgObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            try? self?.setupEngine()
            self?.resumeIfPlaying()
        }

        backgroundObservers = [bgObserver, fgObserver]
    }

    func detach() {
        if let token = timeObserverToken, let player = avPlayer {
            player.removeTimeObserver(token)
        }
        timeObserverToken = nil
        statusObservation?.cancel()
        statusObservation = nil
        avPlayer = nil

        for observer in backgroundObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        backgroundObservers = []

        stopEngine()
        currentChunkIndex = -1
    }

    // MARK: - Private

    private func setupEngine() throws {
        guard Self.supportsHaptics else { return }

        engine?.stop()
        engine = try CHHapticEngine()

        engine?.resetHandler = { [weak self] in
            try? self?.engine?.start()
        }

        engine?.stoppedHandler = { [weak self] reason in
            if reason == .applicationSuspended {
                // Expected when backgrounded
            }
            self?.activePlayer = nil
            self?.currentChunkIndex = -1
        }

        try engine?.start()
    }

    private func stopEngine() {
        activePlayer = nil
        currentChunkIndex = -1
        engine?.stop()
    }

    private func handleTimeUpdate(_ currentTime: TimeInterval) {
        guard isHapticEnabled, isLoaded, !chunkPatterns.isEmpty else { return }

        let chunkIndex = min(Int(currentTime / 30.0), chunkPatterns.count - 1)
        guard chunkIndex >= 0 else { return }

        if chunkIndex != currentChunkIndex {
            switchToChunk(chunkIndex, at: currentTime)
        }
    }

    private func switchToChunk(_ chunkIndex: Int, at currentTime: TimeInterval) {
        guard chunkIndex < chunkPatterns.count, let engine else { return }

        // Stop current player
        try? activePlayer?.stop(atTime: CHHapticTimeImmediate)
        activePlayer = nil

        do {
            let pattern = try CHHapticPattern(dictionary: chunkPatterns[chunkIndex])
            let player = try engine.makeAdvancedPlayer(with: pattern)
            activePlayer = player

            let chunkStartTime = Double(chunkIndex) * 30.0
            let offsetInChunk = currentTime - chunkStartTime

            try player.start(atTime: CHHapticTimeImmediate)
            if offsetInChunk > 0.1 {
                try player.seek(toOffset: offsetInChunk)
            }

            currentChunkIndex = chunkIndex
        } catch {
            // Haptic playback error — non-fatal, just skip
        }
    }

    private func resumeIfPlaying() {
        guard isHapticEnabled, let player = avPlayer,
              player.timeControlStatus == .playing else { return }

        let currentTime = CMTimeGetSeconds(player.currentTime())
        let chunkIndex = min(Int(currentTime / 30.0), chunkPatterns.count - 1)

        if chunkIndex >= 0 {
            switchToChunk(chunkIndex, at: currentTime)
        }
    }

    private func pauseAllPlayers() {
        try? activePlayer?.stop(atTime: CHHapticTimeImmediate)
        activePlayer = nil
        currentChunkIndex = -1
    }

    private func convertToPatternDict(version: Double, pattern: [[String: Any]]) -> [CHHapticPattern.Key: Any] {
        [
            CHHapticPattern.Key(rawValue: "Version"): version,
            CHHapticPattern.Key(rawValue: "Pattern"): pattern
        ]
    }

    private func splitIntoChunks(pattern: [[String: Any]], chunkDuration: TimeInterval, totalDuration: TimeInterval) -> [[CHHapticPattern.Key: Any]] {
        let chunkCount = max(1, Int(ceil(totalDuration / chunkDuration)))
        var chunks: [[[String: Any]]] = Array(repeating: [], count: chunkCount)

        for entry in pattern {
            var entryTime: TimeInterval = 0

            if let event = entry["Event"] as? [String: Any],
               let time = event["Time"] as? TimeInterval {
                entryTime = time
            } else if let curve = entry["ParameterCurve"] as? [String: Any],
                      let time = curve["Time"] as? TimeInterval {
                entryTime = time
            }

            let chunkIndex = min(Int(entryTime / chunkDuration), chunkCount - 1)
            let chunkStartTime = Double(chunkIndex) * chunkDuration

            // Offset times to be chunk-relative
            var adjustedEntry = entry
            if var event = adjustedEntry["Event"] as? [String: Any] {
                if let time = event["Time"] as? TimeInterval {
                    event["Time"] = time - chunkStartTime
                }
                adjustedEntry["Event"] = event
            } else if var curve = adjustedEntry["ParameterCurve"] as? [String: Any] {
                if let time = curve["Time"] as? TimeInterval {
                    curve["Time"] = time - chunkStartTime
                }
                adjustedEntry["ParameterCurve"] = curve
            }

            chunks[chunkIndex].append(adjustedEntry)
        }

        return chunks.map { chunkPattern in
            convertToPatternDict(version: 1.0, pattern: chunkPattern)
        }
    }
}
