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

    func addVideo(from sourceURL: URL, originalName: String) async {
        let ext = sourceURL.pathExtension.isEmpty ? "mov" : sourceURL.pathExtension
        let fileName = "\(UUID().uuidString).\(ext)"
        let destinationURL = VideoItem.videosDirectory.appendingPathComponent(fileName)

        do {
            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
        } catch {
            print("Failed to copy video: \(error)")
            return
        }

        var item = VideoItem(
            id: UUID(),
            name: originalName,
            fileName: fileName,
            dateAdded: Date()
        )

        // Fetch duration immediately so it shows in the list right away
        let asset = AVURLAsset(url: destinationURL)
        if let duration = try? await asset.load(.duration) {
            let seconds = CMTimeGetSeconds(duration)
            if seconds.isFinite {
                item.duration = seconds
            }
        }

        videos.insert(item, at: 0)
        save()
    }

    func renameVideo(id: UUID, newName: String) {
        if let index = videos.firstIndex(where: { $0.id == id }) {
            videos[index].name = newName
            save()
        }
    }

    func updatePlaybackPosition(for videoID: UUID, position: TimeInterval) {
        if let index = videos.firstIndex(where: { $0.id == videoID }) {
            videos[index].lastPlaybackPosition = position
            save()
        }
    }

    func updateDuration(for videoID: UUID, duration: TimeInterval) {
        if let index = videos.firstIndex(where: { $0.id == videoID }) {
            videos[index].duration = duration
            save()
        }
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
