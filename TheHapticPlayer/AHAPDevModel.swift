import Foundation

struct HapticEvent: Identifiable, Hashable {
    enum Kind: String { case transient, continuous }

    let id = UUID()
    let kind: Kind
    let time: TimeInterval
    let duration: TimeInterval
    let intensity: Double
    let sharpness: Double
}

enum AHAPParser {
    static func parse(url: URL) -> (events: [HapticEvent], totalDuration: TimeInterval) {
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let pattern = json["Pattern"] as? [[String: Any]] else {
            return ([], 0)
        }

        var events: [HapticEvent] = []
        events.reserveCapacity(pattern.count)

        for entry in pattern {
            guard let event = entry["Event"] as? [String: Any],
                  let typeRaw = event["EventType"] as? String,
                  let time = event["Time"] as? Double else {
                continue
            }

            let kind: HapticEvent.Kind
            switch typeRaw {
            case "HapticTransient": kind = .transient
            case "HapticContinuous": kind = .continuous
            default: continue
            }

            let duration = (event["EventDuration"] as? Double) ?? 0

            var intensity: Double = 1.0
            var sharpness: Double = 0.5
            if let params = event["EventParameters"] as? [[String: Any]] {
                for param in params {
                    guard let pid = param["ParameterID"] as? String,
                          let pval = param["ParameterValue"] as? Double else { continue }
                    switch pid {
                    case "HapticIntensity": intensity = pval
                    case "HapticSharpness": sharpness = pval
                    default: break
                    }
                }
            }

            events.append(HapticEvent(
                kind: kind,
                time: max(0, time),
                duration: max(0, duration),
                intensity: max(0, min(1, intensity)),
                sharpness: max(0, min(1, sharpness))
            ))
        }

        events.sort { $0.time < $1.time }

        let metadataDuration = (json["Metadata"] as? [String: Any])?["TotalDuration"] as? Double ?? 0
        let computedEnd = events.map { $0.time + $0.duration }.max() ?? 0
        let totalDuration = max(metadataDuration, computedEnd)

        return (events, totalDuration)
    }
}

@Observable
final class HapticDevSession {
    static let waveformSampleCount = 80

    var events: [HapticEvent] = []
    var totalDuration: TimeInterval = 0
    var currentTime: TimeInterval = 0
    var recentlyFired: [HapticEvent] = []
    var firedCount: Int = 0

    /// Ring buffer of intensity samples driven by the engine's periodic time
    /// updates. Each tick the value decays; firing an event bumps it. Renders
    /// as a live waveform that pulses with vibration power.
    var waveform: [Double] = Array(repeating: 0, count: HapticDevSession.waveformSampleCount)
    var currentIntensity: Double = 0
    var currentSharpness: Double = 0.5

    private let recentCap = 6
    private let decayPerTick: Double = 0.78

    func fire(_ event: HapticEvent) {
        firedCount += 1
        recentlyFired.insert(event, at: 0)
        if recentlyFired.count > recentCap {
            recentlyFired.removeLast(recentlyFired.count - recentCap)
        }

        if event.intensity > currentIntensity {
            currentIntensity = event.intensity
        }
        currentSharpness = event.sharpness
    }

    /// Called on every periodic time tick from the engine — advances the
    /// waveform ring buffer and decays the current intensity so the graph
    /// returns to baseline between events.
    func tickWaveform() {
        var next = waveform
        next.removeFirst()
        next.append(currentIntensity)
        waveform = next
        currentIntensity *= decayPerTick
        if currentIntensity < 0.01 { currentIntensity = 0 }
    }

    func resetForSeek() {
        recentlyFired.removeAll()
        firedCount = 0
        currentIntensity = 0
        waveform = Array(repeating: 0, count: HapticDevSession.waveformSampleCount)
    }
}
