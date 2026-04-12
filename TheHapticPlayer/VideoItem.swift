import Foundation

struct VideoItem: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    let fileName: String
    let dateAdded: Date
    var duration: TimeInterval?
    var lastPlaybackPosition: TimeInterval?

    var fileURL: URL {
        VideoItem.videosDirectory.appendingPathComponent(fileName)
    }

    static var videosDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Videos", isDirectory: true)
    }

    static var metadataURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("videos.json")
    }
}
