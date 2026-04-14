import Foundation

enum HapticStatus: String, Codable {
    case queued
    case extractingAudio = "extracting_audio"
    case analyzingDSP = "analyzing_dsp"
    case analyzingVideo = "analyzing_video"
    case classifyingAI = "classifying_ai"
    case scoring
    case generatingAHAP = "generating_ahap"
    case completed
    case failed

    var displayLabel: String {
        switch self {
        case .queued: "Queued"
        case .extractingAudio: "Extracting Audio"
        case .analyzingDSP: "Analyzing Audio"
        case .analyzingVideo: "Analyzing Video"
        case .classifyingAI: "AI Classification"
        case .scoring: "Scoring"
        case .generatingAHAP: "Generating Haptics"
        case .completed: "Completed"
        case .failed: "Failed"
        }
    }
}

struct VideoItem: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    let fileName: String
    let dateAdded: Date
    var duration: TimeInterval?
    var lastPlaybackPosition: TimeInterval?

    // Haptic analysis fields
    var hapticJobId: String?
    var hapticStatus: HapticStatus?
    var hapticProgress: Double?
    var ahapFileName: String?

    var fileURL: URL {
        VideoItem.videosDirectory.appendingPathComponent(fileName)
    }

    var ahapFileURL: URL? {
        guard let ahapFileName else { return nil }
        return VideoItem.hapticsDirectory.appendingPathComponent(ahapFileName)
    }

    var hasHaptics: Bool {
        guard let ahapFileURL else { return false }
        return FileManager.default.fileExists(atPath: ahapFileURL.path)
    }

    var isProcessingHaptics: Bool {
        guard let status = hapticStatus else { return false }
        return status != .completed && status != .failed
    }

    static var videosDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Videos", isDirectory: true)
    }

    static var hapticsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Haptics", isDirectory: true)
    }

    static var metadataURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("videos.json")
    }
}
