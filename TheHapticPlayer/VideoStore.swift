import SwiftUI
import AVFoundation

@Observable
class VideoStore {
    var videos: [VideoItem] = []

    init() {
        try? FileManager.default.createDirectory(
            at: VideoItem.videosDirectory,
            withIntermediateDirectories: true
        )
        load()
    }

    func addVideo(from sourceURL: URL, originalName: String) {
        let ext = sourceURL.pathExtension.isEmpty ? "mov" : sourceURL.pathExtension
        let fileName = "\(UUID().uuidString).\(ext)"
        let destinationURL = VideoItem.videosDirectory.appendingPathComponent(fileName)

        do {
            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
        } catch {
            print("Failed to copy video: \(error)")
            return
        }

        let item = VideoItem(
            id: UUID(),
            name: originalName,
            fileName: fileName,
            dateAdded: Date()
        )
        videos.insert(item, at: 0)
        save()
    }

    func deleteVideo(at offsets: IndexSet) {
        for index in offsets {
            let item = videos[index]
            try? FileManager.default.removeItem(at: item.fileURL)
        }
        videos.remove(atOffsets: offsets)
        save()
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(videos)
            try data.write(to: VideoItem.metadataURL, options: .atomic)
        } catch {
            print("Failed to save videos: \(error)")
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: VideoItem.metadataURL),
              let items = try? JSONDecoder().decode([VideoItem].self, from: data) else {
            return
        }
        videos = items
    }
}
