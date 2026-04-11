import SwiftUI

struct ContentView: View {
    @Environment(VideoStore.self) var videoStore
    @State private var showingAddOptions = false
    @State private var showingPhotoPicker = false
    @State private var showingDocumentPicker = false
    @State private var selectedVideoForInfo: VideoItem?

    var body: some View {
        NavigationStack {
            Group {
                if videoStore.videos.isEmpty {
                    ContentUnavailableView(
                        "No Videos",
                        systemImage: "film",
                        description: Text("Tap + to add videos from your library or files.")
                    )
                } else {
                    List {
                        ForEach(videoStore.videos) { video in
                            NavigationLink(destination: VideoPlayerView(video: video)) {
                                HStack(spacing: 12) {
                                    Image(systemName: "film")
                                        .font(.title2)
                                        .foregroundStyle(.secondary)
                                        .frame(width: 44, height: 44)
                                        .background(Color(.tertiarySystemFill))
                                        .clipShape(RoundedRectangle(cornerRadius: 8))

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(video.name)
                                            .font(.body)
                                            .lineLimit(1)
                                        HStack(spacing: 8) {
                                            Text(video.dateAdded, style: .date)
                                            if let duration = video.duration {
                                                Text("·")
                                                Text(formatDuration(duration))
                                            }
                                        }
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                            .contextMenu {
                                Button {
                                    selectedVideoForInfo = video
                                } label: {
                                    Label("Info", systemImage: "info.circle")
                                }
                                Button(role: .destructive) {
                                    if let index = videoStore.videos.firstIndex(where: { $0.id == video.id }) {
                                        videoStore.deleteVideo(at: IndexSet(integer: index))
                                    }
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                        .onDelete(perform: videoStore.deleteVideo)
                    }
                }
            }
            .navigationTitle("TheHaptic Player")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            showingPhotoPicker = true
                        } label: {
                            Label("Photo Library", systemImage: "photo.on.rectangle")
                        }
                        Button {
                            showingDocumentPicker = true
                        } label: {
                            Label("Files", systemImage: "folder")
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(item: $selectedVideoForInfo) { video in
                NavigationStack {
                    List {
                        Section("Details") {
                            LabeledContent("Name", value: video.name)
                            LabeledContent("Added", value: video.dateAdded, format: .dateTime)
                            LabeledContent("File Size", value: fileSizeString(for: video))
                            LabeledContent("Format", value: video.fileName.components(separatedBy: ".").last?.uppercased() ?? "Unknown")
                            if let duration = video.duration {
                                LabeledContent("Duration", value: formatDuration(duration))
                            }
                            if let position = video.lastPlaybackPosition, position > 0 {
                                LabeledContent("Resume At", value: formatDuration(position))
                            }
                        }
                    }
                    .navigationTitle("Video Info")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") {
                                selectedVideoForInfo = nil
                            }
                        }
                    }
                }
                .presentationDetents([.medium])
            }
            .sheet(isPresented: $showingPhotoPicker) {
                PhotoPickerView()
            }
            .sheet(isPresented: $showingDocumentPicker) {
                DocumentPickerView()
            }
        }
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        let secs = Int(seconds) % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }

    private func fileSizeString(for video: VideoItem) -> String {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: video.fileURL.path),
              let size = attrs[.size] as? Int64 else {
            return "Unknown"
        }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }
}
