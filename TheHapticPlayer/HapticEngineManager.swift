import CoreHaptics
import AVFoundation
import UIKit
import Combine
import QuartzCore

@Observable
class HapticEngineManager {
    var isHapticEnabled = true {
        didSet {
            if isHapticEnabled {
                resumeIfPlaying()
            } else {
                pauseHaptic()
            }
        }
    }

    private(set) var isLoaded = false

    // Developer hooks (nil unless dev panel is on)
    var onEventFired: ((HapticEvent) -> Void)?
    var onTimeUpdated: ((TimeInterval) -> Void)?
    var onSeekDetected: (() -> Void)?
    private var devEvents: [HapticEvent] = []
    private var nextDevEventIndex: Int = 0

    // Engine
    private var engine: CHHapticEngine?
    private var engineNeedsStart = false

    // Pattern data — full AHAP split into ≤30s chunks (Core Haptics per-pattern limit)
    private var chunkPatterns: [[CHHapticPattern.Key: Any]] = []
    private var totalDuration: TimeInterval = 0
    private let chunkDuration: TimeInterval = 30.0

    // Active playback
    private var activePlayer: CHHapticAdvancedPatternPlayer?
    private var currentChunkIndex: Int = -1

    // Pre-rolled next chunk, scheduled to start at the upcoming boundary.
    private var pendingPlayer: CHHapticAdvancedPatternPlayer?
    private var pendingChunkIndex: Int = -1
    private var pendingActivationMediaTime: TimeInterval = .infinity
    // Outgoing player held briefly after promotion so its scheduled stop fires.
    private var expiringPlayer: CHHapticAdvancedPatternPlayer?

    // AVPlayer sync
    private weak var avPlayer: AVPlayer?
    private var timeObserverToken: Any?
    private var statusObservation: AnyCancellable?
    private var rateObservation: AnyCancellable?
    private var lifecycleObservers: [NSObjectProtocol] = []

    // Sync tuning
    private var lastObservedMediaTime: TimeInterval = 0
    private var lastObservedRealTime: CFTimeInterval = 0
    private let seekDeltaThreshold: TimeInterval = 0.4
    private let chunkSwitchLeadIn: TimeInterval = 0.05
    // Begin building the next chunk this far ahead of the boundary.
    private let chunkPrerollLead: TimeInterval = 0.2
    // How long to keep the outgoing chunk playing past the boundary so its
    // tail (events whose EventDuration spans the boundary) crossfades with
    // the incoming chunk's opening.
    private let chunkOverlap: TimeInterval = 0.1

    static var supportsHaptics: Bool {
        CHHapticEngine.capabilitiesForHardware().supportsHaptics
    }

    // MARK: - Public API

    func loadAHAP(from url: URL) throws {
        guard Self.supportsHaptics else { return }

        let data = try Data(contentsOf: url)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let pattern = json["Pattern"] as? [[String: Any]] else {
            return
        }

        let metadata = json["Metadata"] as? [String: Any]
        totalDuration = metadata?["TotalDuration"] as? TimeInterval ?? 0
        let totalChunks = metadata?["TotalChunks"] as? Int ?? 1

        if totalDuration <= 0 {
            totalDuration = Self.maxTime(in: pattern)
        }

        if totalChunks <= 1 && totalDuration <= chunkDuration + 0.5 {
            chunkPatterns = [Self.makePatternDict(version: 1.0, pattern: pattern)]
        } else {
            chunkPatterns = Self.split(pattern: pattern,
                                       chunkDuration: chunkDuration,
                                       totalDuration: totalDuration)
        }

        let parsed = AHAPParser.parse(url: url)
        devEvents = parsed.events
        nextDevEventIndex = 0

        configureAudioSession()
        try setupEngine()
        isLoaded = true
    }

    func attachToPlayer(_ player: AVPlayer) {
        unhookCurrentPlayer()
        avPlayer = player
        lastObservedMediaTime = 0
        lastObservedRealTime = 0
        registerLifecycleObservers()

        let interval = CMTime(value: 1, timescale: 10) // 0.1s of media time
        timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            self?.handleTimeUpdate(CMTimeGetSeconds(time))
        }

        statusObservation = player.publisher(for: \.timeControlStatus)
            .removeDuplicates()
            .sink { [weak self] status in
                guard let self else { return }
                switch status {
                case .playing:
                    self.resumeIfPlaying()
                case .paused, .waitingToPlayAtSpecifiedRate:
                    self.pauseHaptic()
                @unknown default:
                    break
                }
            }

        rateObservation = player.publisher(for: \.rate)
            .removeDuplicates()
            .sink { [weak self] rate in
                self?.applyPlaybackRate(rate)
            }
    }

    func detach() {
        unhookCurrentPlayer()

        for obs in lifecycleObservers {
            NotificationCenter.default.removeObserver(obs)
        }
        lifecycleObservers = []

        engine?.stop(completionHandler: nil)
        engine = nil
        chunkPatterns = []
        currentChunkIndex = -1
        lastObservedMediaTime = 0
        lastObservedRealTime = 0
        isLoaded = false

        onEventFired = nil
        onTimeUpdated = nil
        onSeekDetected = nil
        devEvents = []
        nextDevEventIndex = 0
    }

    private func firstDevEventIndex(after time: TimeInterval) -> Int {
        var lo = 0
        var hi = devEvents.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if devEvents[mid].time < time {
                lo = mid + 1
            } else {
                hi = mid
            }
        }
        return lo
    }

    private func unhookCurrentPlayer() {
        if let token = timeObserverToken, let player = avPlayer {
            player.removeTimeObserver(token)
        }
        timeObserverToken = nil
        statusObservation?.cancel()
        statusObservation = nil
        rateObservation?.cancel()
        rateObservation = nil
        avPlayer = nil
        cancelPendingPlayer()
        expiringPlayer = nil
        stopActivePlayer()
        currentChunkIndex = -1
    }

    // MARK: - Audio session

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .moviePlayback, options: [])
            try session.setActive(true, options: [])
        } catch {
            // Non-fatal — AVPlayer will still activate its own session,
            // and the engine will retry on demand.
        }
    }

    // MARK: - Engine lifecycle

    private func setupEngine() throws {
        guard Self.supportsHaptics else { return }

        if let existing = engine {
            existing.stop(completionHandler: nil)
            engine = nil
        }

        let newEngine = try CHHapticEngine()
        newEngine.playsHapticsOnly = true
        newEngine.isAutoShutdownEnabled = false

        newEngine.resetHandler = { [weak self] in
            DispatchQueue.main.async {
                guard let self else { return }
                do {
                    try self.engine?.start()
                    self.engineNeedsStart = false
                    self.activePlayer = nil
                    self.pendingPlayer = nil
                    self.pendingChunkIndex = -1
                    self.pendingActivationMediaTime = .infinity
                    self.expiringPlayer = nil
                    self.currentChunkIndex = -1
                    self.resumeIfPlaying()
                } catch {
                    self.engineNeedsStart = true
                }
            }
        }

        newEngine.stoppedHandler = { [weak self] _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.activePlayer = nil
                self.pendingPlayer = nil
                self.pendingChunkIndex = -1
                self.pendingActivationMediaTime = .infinity
                self.expiringPlayer = nil
                self.currentChunkIndex = -1
                self.engineNeedsStart = true
            }
        }

        try newEngine.start()
        engine = newEngine
        engineNeedsStart = false
    }

    private func ensureEngineRunning() throws {
        if engine == nil {
            try setupEngine()
            return
        }
        if engineNeedsStart {
            try engine?.start()
            engineNeedsStart = false
        }
    }

    // MARK: - Playback driver

    private func handleTimeUpdate(_ currentTime: TimeInterval) {
        guard isHapticEnabled,
              isLoaded,
              !chunkPatterns.isEmpty,
              let player = avPlayer else { return }

        let now = CACurrentMediaTime()
        let realDelta = now - lastObservedRealTime
        let mediaDelta = currentTime - lastObservedMediaTime
        let rate = Double(player.rate)
        let expectedDelta = realDelta * rate
        let driftFromExpected = abs(mediaDelta - expectedDelta)

        // Treat as seek when there's a sane real-time gap but media jumped unexpectedly.
        let isSeek = lastObservedRealTime > 0
            && realDelta > 0
            && realDelta < 1.0
            && driftFromExpected > seekDeltaThreshold

        lastObservedMediaTime = currentTime
        lastObservedRealTime = now

        // Developer hooks — cheap when callbacks are nil.
        onTimeUpdated?(currentTime)
        if !devEvents.isEmpty {
            if isSeek {
                onSeekDetected?()
                nextDevEventIndex = firstDevEventIndex(after: currentTime)
            }
            while nextDevEventIndex < devEvents.count,
                  devEvents[nextDevEventIndex].time <= currentTime {
                onEventFired?(devEvents[nextDevEventIndex])
                nextDevEventIndex += 1
            }
        }

        guard player.timeControlStatus == .playing else { return }

        let chunkIndex = chunkIndexFor(time: currentTime)
        guard chunkIndex >= 0 else { return }

        if isSeek {
            cancelPendingPlayer()
            switchToChunk(chunkIndex, at: currentTime)
            return
        }

        // If a pre-rolled chunk's start time has elapsed in media time,
        // promote it to active without re-issuing start() — it's already running.
        if pendingPlayer != nil,
           chunkIndex == pendingChunkIndex,
           currentTime >= pendingActivationMediaTime {
            promotePendingToActive()
        }

        if chunkIndex != currentChunkIndex {
            // Pre-roll didn't happen (first chunk, or skipped). Hard switch.
            cancelPendingPlayer()
            switchToChunk(chunkIndex, at: currentTime)
            return
        }

        maybePrerollNextChunk(currentTime: currentTime)
    }

    private func chunkIndexFor(time: TimeInterval) -> Int {
        guard !chunkPatterns.isEmpty else { return -1 }
        let idx = Int(max(0, time) / chunkDuration)
        return min(idx, chunkPatterns.count - 1)
    }

    private func switchToChunk(_ chunkIndex: Int, at currentTime: TimeInterval) {
        guard chunkIndex < chunkPatterns.count else { return }

        do {
            try ensureEngineRunning()
            try startChunk(chunkIndex, at: currentTime)
        } catch {
            // First failure is almost always -4805 (engineNotRunning).
            // Force a clean restart and retry once.
            engineNeedsStart = true
            do {
                try setupEngine()
                try startChunk(chunkIndex, at: currentTime)
            } catch {
                stopActivePlayer()
            }
        }
    }

    private func startChunk(_ chunkIndex: Int, at currentTime: TimeInterval) throws {
        guard let engine else { return }

        try? activePlayer?.stop(atTime: CHHapticTimeImmediate)
        activePlayer = nil

        let pattern = try CHHapticPattern(dictionary: chunkPatterns[chunkIndex])
        let player = try engine.makeAdvancedPlayer(with: pattern)
        player.loopEnabled = false

        if let rate = avPlayer?.rate, rate > 0 {
            player.playbackRate = max(0.0625, rate)
        }

        let chunkStart = Double(chunkIndex) * chunkDuration
        let offsetInChunk = max(0, currentTime - chunkStart)

        try player.start(atTime: CHHapticTimeImmediate)
        if offsetInChunk > chunkSwitchLeadIn {
            try player.seek(toOffset: offsetInChunk)
        }

        activePlayer = player
        currentChunkIndex = chunkIndex
    }

    private func maybePrerollNextChunk(currentTime: TimeInterval) {
        guard pendingPlayer == nil,
              currentChunkIndex >= 0,
              currentChunkIndex + 1 < chunkPatterns.count,
              let engine,
              let avPlayer else { return }

        let nextChunkIndex = currentChunkIndex + 1
        let boundary = Double(nextChunkIndex) * chunkDuration
        let timeToBoundary = boundary - currentTime
        guard timeToBoundary > 0, timeToBoundary <= chunkPrerollLead else { return }

        let rate = max(0.0625, Double(avPlayer.rate))
        let realTimeToBoundary = timeToBoundary / rate

        do {
            try ensureEngineRunning()

            let pattern = try CHHapticPattern(dictionary: chunkPatterns[nextChunkIndex])
            let player = try engine.makeAdvancedPlayer(with: pattern)
            player.loopEnabled = false
            player.playbackRate = Float(rate)

            let boundaryEngineTime = engine.currentTime + realTimeToBoundary
            try player.start(atTime: boundaryEngineTime)

            // Let the outgoing chunk keep playing past the boundary so events
            // whose EventDuration straddles the boundary crossfade naturally
            // with the incoming chunk's opening events.
            try? activePlayer?.stop(atTime: boundaryEngineTime + chunkOverlap)

            pendingPlayer = player
            pendingChunkIndex = nextChunkIndex
            pendingActivationMediaTime = boundary
        } catch {
            // Preroll failed — fall back to the hard-switch path at the boundary.
            cancelPendingPlayer()
        }
    }

    private func promotePendingToActive() {
        guard let pending = pendingPlayer else { return }
        // Hold the outgoing player until its scheduled stop fires; otherwise
        // ARC could drop it before the engine processes the stop time.
        expiringPlayer = activePlayer
        activePlayer = pending
        currentChunkIndex = pendingChunkIndex
        pendingPlayer = nil
        pendingChunkIndex = -1
        pendingActivationMediaTime = .infinity

        let releaseAfter = chunkOverlap + 0.1
        DispatchQueue.main.asyncAfter(deadline: .now() + releaseAfter) { [weak self] in
            self?.expiringPlayer = nil
        }
    }

    private func cancelPendingPlayer() {
        if let pending = pendingPlayer {
            try? pending.stop(atTime: CHHapticTimeImmediate)
        }
        pendingPlayer = nil
        pendingChunkIndex = -1
        pendingActivationMediaTime = .infinity
    }

    private func resumeIfPlaying() {
        guard isHapticEnabled,
              isLoaded,
              let player = avPlayer,
              player.timeControlStatus == .playing else { return }

        let time = CMTimeGetSeconds(player.currentTime())
        let chunkIndex = chunkIndexFor(time: time)
        guard chunkIndex >= 0 else { return }

        switchToChunk(chunkIndex, at: time)
    }

    private func pauseHaptic() {
        cancelPendingPlayer()
        expiringPlayer = nil
        stopActivePlayer()
        // Force reload of the current chunk on resume so we re-seek to the exact AVPlayer position.
        currentChunkIndex = -1
    }

    private func stopActivePlayer() {
        try? activePlayer?.stop(atTime: CHHapticTimeImmediate)
        activePlayer = nil
    }

    private func applyPlaybackRate(_ rate: Float) {
        guard rate > 0 else { return }
        activePlayer?.playbackRate = max(0.0625, rate)
        // The pending player's boundary time was computed at the previous rate,
        // so it would now fire at the wrong moment. Cancel and let the next
        // tick re-preroll under the new rate.
        cancelPendingPlayer()
    }

    // MARK: - App / session lifecycle

    private func registerLifecycleObservers() {
        let center = NotificationCenter.default

        let bg = center.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.stopActivePlayer()
            self?.engine?.stop(completionHandler: nil)
            self?.engineNeedsStart = true
        }

        let fg = center.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.configureAudioSession()
            try? self?.ensureEngineRunning()
            self?.resumeIfPlaying()
        }

        let interrupt = center.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(), queue: .main
        ) { [weak self] note in
            guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
            switch type {
            case .began:
                self?.stopActivePlayer()
                self?.engineNeedsStart = true
            case .ended:
                try? AVAudioSession.sharedInstance().setActive(true, options: [])
                try? self?.ensureEngineRunning()
                self?.resumeIfPlaying()
            @unknown default:
                break
            }
        }

        lifecycleObservers = [bg, fg, interrupt]
    }

    // MARK: - Pattern utilities

    private static func makePatternDict(version: Double, pattern: [[String: Any]]) -> [CHHapticPattern.Key: Any] {
        [
            CHHapticPattern.Key(rawValue: "Version"): version,
            CHHapticPattern.Key(rawValue: "Pattern"): pattern,
        ]
    }

    private static func maxTime(in pattern: [[String: Any]]) -> TimeInterval {
        var maxTime: TimeInterval = 0
        for entry in pattern {
            if let event = entry["Event"] as? [String: Any],
               let time = event["Time"] as? TimeInterval {
                let duration = event["EventDuration"] as? TimeInterval ?? 0
                maxTime = max(maxTime, time + duration)
            } else if let curve = entry["ParameterCurve"] as? [String: Any],
                      let time = curve["Time"] as? TimeInterval {
                let points = curve["ParameterCurveControlPoints"] as? [[String: Any]] ?? []
                let lastPoint = points.compactMap { $0["Time"] as? TimeInterval }.max() ?? 0
                maxTime = max(maxTime, time + lastPoint)
            }
        }
        return maxTime
    }

    private static func split(pattern: [[String: Any]],
                              chunkDuration: TimeInterval,
                              totalDuration: TimeInterval) -> [[CHHapticPattern.Key: Any]] {
        let chunkCount = max(1, Int(ceil(totalDuration / chunkDuration)))
        var chunks: [[[String: Any]]] = Array(repeating: [], count: chunkCount)

        for entry in pattern {
            let entryTime: TimeInterval
            if let event = entry["Event"] as? [String: Any],
               let t = event["Time"] as? TimeInterval {
                entryTime = t
            } else if let curve = entry["ParameterCurve"] as? [String: Any],
                      let t = curve["Time"] as? TimeInterval {
                entryTime = t
            } else {
                continue
            }

            let chunkIndex = max(0, min(Int(entryTime / chunkDuration), chunkCount - 1))
            let chunkStart = Double(chunkIndex) * chunkDuration

            var adjusted = entry
            if var event = adjusted["Event"] as? [String: Any] {
                if let t = event["Time"] as? TimeInterval {
                    event["Time"] = max(0, t - chunkStart)
                }
                adjusted["Event"] = event
            } else if var curve = adjusted["ParameterCurve"] as? [String: Any] {
                if let t = curve["Time"] as? TimeInterval {
                    curve["Time"] = max(0, t - chunkStart)
                }
                adjusted["ParameterCurve"] = curve
            }

            chunks[chunkIndex].append(adjusted)
        }

        return chunks.map { makePatternDict(version: 1.0, pattern: $0) }
    }
}
