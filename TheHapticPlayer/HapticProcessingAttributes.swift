import ActivityKit
import Foundation

struct HapticProcessingAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var statusRaw: String
        var statusLabel: String
        var progress: Double
    }

    var videoId: UUID
    var videoName: String
}
