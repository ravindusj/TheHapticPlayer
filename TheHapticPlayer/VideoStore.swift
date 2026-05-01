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
        try? FileManager.default.createDirectory(
            at: VideoItem.hapticsDirectory,
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

    func updateHapticStatus(for videoID: UUID, jobId: String, status: HapticStatus, progress: Double?) {
        if let index = videos.firstIndex(where: { $0.id == videoID }) {
            videos[index].hapticJobId = jobId
            videos[index].hapticStatus = status
            videos[index].hapticProgress = progress
            save()
        }
    }

    func setAHAPFile(for videoID: UUID, fileName: String) {
        if let index = videos.firstIndex(where: { $0.id == videoID }) {
            videos[index].ahapFileName = fileName
            videos[index].hapticStatus = .completed
            videos[index].hapticProgress = 100
            save()
        }
    }

    @discardableResult
    func toggleHapticsEnabled(for videoID: UUID) -> Bool? {
        guard let index = videos.firstIndex(where: { $0.id == videoID }) else { return nil }
        let newValue = !videos[index].isHapticsEnabled
        videos[index].hapticsEnabled = newValue
        save()
        return newValue
    }

    func clearHapticData(for videoID: UUID) {
        if let index = videos.firstIndex(where: { $0.id == videoID }) {
            if let ahapURL = videos[index].ahapFileURL {
                try? FileManager.default.removeItem(at: ahapURL)
            }
            videos[index].hapticJobId = nil
            videos[index].hapticStatus = nil
            videos[index].hapticProgress = nil
            videos[index].ahapFileName = nil
            save()
        }
    }

    func deleteVideo(at offsets: IndexSet) {
        for index in offsets {
            let item = videos[index]
            try? FileManager.default.removeItem(at: item.fileURL)
            if let ahapURL = item.ahapFileURL {
                try? FileManager.default.removeItem(at: ahapURL)
            }
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
