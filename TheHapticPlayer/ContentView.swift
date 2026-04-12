import SwiftUI

struct ContentView: View {
    @Environment(VideoStore.self) var videoStore
    @State private var showingAddOptions = false
    @State private var showingPhotoPicker = false
    @State private var showingDocumentPicker = false
    @State private var selectedVideoForInfo: VideoItem?
    @State private var selectedVideoForPlay: VideoItem?
    @State private var searchText = ""
    @State private var videoToRename: VideoItem?
    @State private var renameText = ""
    @State private var videoToDelete: VideoItem?
    @State private var isSelecting = false
    @State private var selectedVideos: Set<UUID> = []
    @State private var showBatchDeleteConfirm = false

    var filteredVideos: [VideoItem] {
        if searchText.isEmpty { return videoStore.videos }
        return videoStore.videos.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if videoStore.videos.isEmpty {
                    ContentUnavailableView(
                        "No Videos",
                        systemImage: "film",
                        description: Text("Tap + to add videos from your library or files.")
                    )
                } else if filteredVideos.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                } else {
                    List {
                        ForEach(filteredVideos) { video in
                            HStack(spacing: 12) {
                                if isSelecting {
                                    Image(systemName: selectedVideos.contains(video.id) ? "checkmark.circle.fill" : "circle")
                                        .font(.title3)
                                        .foregroundStyle(selectedVideos.contains(video.id) ? .blue : .secondary)
                                        .transition(.move(edge: .leading).combined(with: .opacity))
                                }

                                VideoThumbnailView(url: video.fileURL)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(video.name)
                                        .font(.body)
                                        .lineLimit(1)
                                        .foregroundStyle(.primary)
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
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if isSelecting {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        toggleSelection(video)
                                    }
                                } else {
                                    selectedVideoForPlay = video
                                }
                            }
                            .simultaneousGesture(
                                LongPressGesture(minimumDuration: 0.5)
                                    .onEnded { _ in
                                        guard !isSelecting else { return }
                                        withAnimation(.easeInOut(duration: 0.25)) {
                                            isSelecting = true
                                            selectedVideos = [video.id]
                                        }
                                    }
                            )
                            .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                if !isSelecting {
                                    Button(role: .destructive) {
                                        videoToDelete = video
                                    } label: {
                                        Image(systemName: "trash")
                                    }
                                }
                            }
                            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                if !isSelecting {
                                    Button {
                                        selectedVideoForInfo = video
                                    } label: {
                                        Image(systemName: "info.circle")
                                    }
                                    .tint(.blue)
                                    Button {
                                        renameText = video.name
                                        videoToRename = video
                                    } label: {
                                        Image(systemName: "pencil.and.outline")
                                    }
                                    .tint(.orange)
                                }
                            }
                        }
                    }
                }
            }
            .animation(.easeInOut(duration: 0.25), value: isSelecting)
            .searchable(text: $searchText, prompt: "Search videos")
            .navigationDestination(item: $selectedVideoForPlay) { video in
                VideoPlayerView(video: video)
            }
            .navigationTitle("TheHaptic Player")
            .toolbar {
                if isSelecting {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Cancel") {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                isSelecting = false
                                selectedVideos.removeAll()
                            }
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showBatchDeleteConfirm = true
                        } label: {
                            Image(systemName: "trash")
                                .foregroundStyle(.red)
                        }
                        .disabled(selectedVideos.isEmpty)
                    }
                } else {
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
            .alert("Delete \(selectedVideos.count) Video\(selectedVideos.count == 1 ? "" : "s")?", isPresented: $showBatchDeleteConfirm) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        let indices = IndexSet(selectedVideos.compactMap { id in
                            videoStore.videos.firstIndex(where: { $0.id == id })
                        })
                        videoStore.deleteVideo(at: indices)
                        selectedVideos.removeAll()
                        isSelecting = false
                    }
                }
            } message: {
                Text("\(selectedVideos.count) video\(selectedVideos.count == 1 ? "" : "s") will be permanently deleted.")
            }
            .alert("Delete Video", isPresented: Binding(
                get: { videoToDelete != nil },
                set: { if !$0 { videoToDelete = nil } }
            )) {
                Button("Cancel", role: .cancel) { videoToDelete = nil }
                Button("Delete", role: .destructive) {
                    if let video = videoToDelete,
                       let index = videoStore.videos.firstIndex(where: { $0.id == video.id }) {
                        videoStore.deleteVideo(at: IndexSet(integer: index))
                    }
                    videoToDelete = nil
                }
            } message: {
                if let video = videoToDelete {
                    Text("\"\(video.name)\" will be permanently deleted.")
                }
            }
            .alert("Rename Video", isPresented: Binding(
                get: { videoToRename != nil },
                set: { if !$0 { videoToRename = nil } }
            )) {
                TextField("Video name", text: $renameText)
                Button("Cancel", role: .cancel) { videoToRename = nil }
                Button("Save") {
                    if let video = videoToRename, !renameText.trimmingCharacters(in: .whitespaces).isEmpty {
                        videoStore.renameVideo(id: video.id, newName: renameText.trimmingCharacters(in: .whitespaces))
                    }
                    videoToRename = nil
                }
            }
        }
    }

    private func toggleSelection(_ video: VideoItem) {
        if selectedVideos.contains(video.id) {
            selectedVideos.remove(video.id)
        } else {
            selectedVideos.insert(video.id)
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
