import SwiftUI

struct ContentView: View {
    @Environment(VideoStore.self) var videoStore
    @Environment(HapticAnalysisManager.self) var hapticManager
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
    @State private var showHapticError = false
    @State private var animatingVideos: Set<UUID> = []

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
                    videoList
                }
            }
            .animation(.easeInOut(duration: 0.25), value: isSelecting)
            .searchable(text: $searchText, prompt: "Search videos")
            .navigationDestination(item: $selectedVideoForPlay) { video in
                VideoPlayerView(video: video)
            }
            .navigationTitle("TheHaptic Player")
            .toolbar { toolbarContent }
            .sheet(item: $selectedVideoForInfo) { video in
                VideoInfoSheet(
                    video: video,
                    dismiss: { selectedVideoForInfo = nil }
                )
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
                    batchDelete()
                }
            } message: {
                Text("\(selectedVideos.count) video\(selectedVideos.count == 1 ? "" : "s") will be permanently deleted.")
            }
            .alert("Delete Video", isPresented: Binding(
                get: { videoToDelete != nil },
                set: { if !$0 { videoToDelete = nil } }
            )) {
                Button("Cancel", role: .cancel) { videoToDelete = nil }
                Button("Delete", role: .destructive) { deleteSingle() }
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
                Button("Save") { renameSave() }
            }
            .alert("Haptic Analysis Error", isPresented: $showHapticError) {
                Button("OK", role: .cancel) { hapticManager.activeError = nil }
            } message: {
                Text(hapticManager.activeError ?? "An unknown error occurred.")
            }
            .onChange(of: hapticManager.activeError) { _, newValue in
                if newValue != nil { showHapticError = true }
            }
            .onChange(of: videoStore.videos.count) { oldCount, newCount in
                if newCount > oldCount {
                    for video in videoStore.videos where video.hapticStatus == nil && !video.hasHaptics {
                        hapticManager.startAnalysis(for: video, in: videoStore)
                    }
                }
            }
        }
    }

    // MARK: - Video List

    private var videoList: some View {
        List {
            ForEach(filteredVideos) { video in
                VideoRowView(
                    video: video,
                    isSelecting: isSelecting,
                    isSelected: selectedVideos.contains(video.id),
                    isBlurred: video.isProcessingHaptics || animatingVideos.contains(video.id),
                    onTap: { handleTap(video) },
                    onLongPress: { handleLongPress(video) },
                    onAnimationStarted: { animatingVideos.insert(video.id) },
                    onAnimationFinished: {
                        let _ = withAnimation(.easeInOut(duration: 0.4)) {
                            animatingVideos.remove(video.id)
                        }
                    }
                )
                .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    if !isSelecting && !video.isProcessingHaptics {
                        Button(role: .destructive) { videoToDelete = video } label: {
                            Image(systemName: "trash")
                        }
                    }
                }
                .swipeActions(edge: .leading, allowsFullSwipe: false) {
                    if !isSelecting && !video.isProcessingHaptics {
                        Button { selectedVideoForInfo = video } label: {
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

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
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
                Button { showBatchDeleteConfirm = true } label: {
                    Image(systemName: "trash").foregroundStyle(.red)
                }
                .disabled(selectedVideos.isEmpty)
            }
        } else {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink(destination: SettingsView()) {
                    Image(systemName: "gearshape")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { showingPhotoPicker = true } label: {
                        Label("Photo Library", systemImage: "photo.on.rectangle")
                    }
                    Button { showingDocumentPicker = true } label: {
                        Label("Files", systemImage: "folder")
                    }
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
    }

    // MARK: - Actions

    private func handleTap(_ video: VideoItem) {
        guard !video.isProcessingHaptics, !animatingVideos.contains(video.id) else { return }
        if isSelecting {
            withAnimation(.easeInOut(duration: 0.2)) {
                if selectedVideos.contains(video.id) {
                    selectedVideos.remove(video.id)
                } else {
                    selectedVideos.insert(video.id)
                }
            }
        } else {
            selectedVideoForPlay = video
        }
    }

    private func handleLongPress(_ video: VideoItem) {
        guard !isSelecting, !video.isProcessingHaptics, !animatingVideos.contains(video.id) else { return }
        withAnimation(.easeInOut(duration: 0.25)) {
            isSelecting = true
            selectedVideos = [video.id]
        }
    }

    private func batchDelete() {
        withAnimation(.easeInOut(duration: 0.25)) {
            let indices = IndexSet(selectedVideos.compactMap { id in
                videoStore.videos.firstIndex(where: { $0.id == id })
            })
            videoStore.deleteVideo(at: indices)
            selectedVideos.removeAll()
            isSelecting = false
        }
    }

    private func deleteSingle() {
        if let video = videoToDelete,
           let index = videoStore.videos.firstIndex(where: { $0.id == video.id }) {
            videoStore.deleteVideo(at: IndexSet(integer: index))
        }
        videoToDelete = nil
    }

    private func renameSave() {
        if let video = videoToRename, !renameText.trimmingCharacters(in: .whitespaces).isEmpty {
            videoStore.renameVideo(id: video.id, newName: renameText.trimmingCharacters(in: .whitespaces))
        }
        videoToRename = nil
    }

    private func videoProgress(_ video: VideoItem) -> Double? {
        guard let position = video.lastPlaybackPosition, position > 0,
              let duration = video.duration, duration > 0 else { return nil }
        return position / duration
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        let secs = Int(seconds) % 60
        if hours > 0 { return String(format: "%d:%02d:%02d", hours, minutes, secs) }
        return String(format: "%d:%02d", minutes, secs)
    }

    private func fileSizeString(for video: VideoItem) -> String {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: video.fileURL.path),
              let size = attrs[.size] as? Int64 else { return "Unknown" }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }
}

// MARK: - Video Row

struct VideoRowView: View {
    let video: VideoItem
    let isSelecting: Bool
    let isSelected: Bool
    let isBlurred: Bool
    let onTap: () -> Void
    let onLongPress: () -> Void
    let onAnimationStarted: () -> Void
    let onAnimationFinished: () -> Void

    var body: some View {
        ZStack {
            rowContent
                .opacity(isBlurred ? 0.3 : 1.0)
                .blur(radius: isBlurred ? 2 : 0)

            if isBlurred {
                SmoothProgressOverlay(
                    targetProgress: video.hapticProgress ?? 0,
                    onFinished: onAnimationFinished
                )
                .onAppear { onAnimationStarted() }
            }
        }
        .animation(.easeInOut(duration: 0.4), value: isBlurred)
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.5)
                .onEnded { _ in onLongPress() }
        )
    }

    private var rowContent: some View {
        HStack(spacing: 12) {
            if isSelecting {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? .blue : .secondary)
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }

            VideoThumbnailView(
                url: video.fileURL,
                progress: videoProgress
            )

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
                    if video.hasHaptics {
                        Image(systemName: "waveform.path")
                            .foregroundStyle(.purple)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }

    private var videoProgress: Double? {
        guard let position = video.lastPlaybackPosition, position > 0,
              let duration = video.duration, duration > 0 else { return nil }
        return position / duration
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        let secs = Int(seconds) % 60
        if hours > 0 { return String(format: "%d:%02d:%02d", hours, minutes, secs) }
        return String(format: "%d:%02d", minutes, secs)
    }
}

// MARK: - Video Info Sheet

struct VideoInfoSheet: View {
    let video: VideoItem
    let dismiss: () -> Void
    @Environment(VideoStore.self) var videoStore
    @Environment(HapticAnalysisManager.self) var hapticManager

    var body: some View {
        NavigationStack {
            List {
                detailsSection
                hapticsSection
            }
            .navigationTitle("Video Info")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private var detailsSection: some View {
        Section("Details") {
            LabeledContent("Name", value: video.name)
            LabeledContent("Added", value: video.dateAdded, format: .dateTime)
            LabeledContent("File Size", value: fileSizeString)
            LabeledContent("Format", value: video.fileName.components(separatedBy: ".").last?.uppercased() ?? "Unknown")
            if let duration = video.duration {
                LabeledContent("Duration", value: formatDuration(duration))
            }
            if let position = video.lastPlaybackPosition, position > 0 {
                LabeledContent("Resume At", value: formatDuration(position))
            }
        }
    }

    private var hapticsSection: some View {
        Section("Haptics") {
            if video.hasHaptics {
                LabeledContent("Status", value: "Ready")
                Button("Regenerate Haptics", systemImage: "arrow.clockwise") {
                    videoStore.clearHapticData(for: video.id)
                    hapticManager.startAnalysis(for: video, in: videoStore)
                    dismiss()
                }
                Button("Delete Haptics", systemImage: "trash", role: .destructive) {
                    videoStore.clearHapticData(for: video.id)
                    dismiss()
                }
            } else if video.isProcessingHaptics {
                LabeledContent("Status", value: video.hapticStatus?.displayLabel ?? "Analysing")
                if let progress = video.hapticProgress {
                    ProgressView(value: progress, total: 100).tint(.gray)
                }
            } else if video.hapticStatus == .failed {
                LabeledContent("Status", value: "Failed")
                Button("Retry", systemImage: "arrow.clockwise") {
                    hapticManager.startAnalysis(for: video, in: videoStore)
                    dismiss()
                }
            } else {
                LabeledContent("Status", value: "Pending")
            }
        }
    }

    private var fileSizeString: String {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: video.fileURL.path),
              let size = attrs[.size] as? Int64 else { return "Unknown" }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        let secs = Int(seconds) % 60
        if hours > 0 { return String(format: "%d:%02d:%02d", hours, minutes, secs) }
        return String(format: "%d:%02d", minutes, secs)
    }
}

// MARK: - Smooth Progress Overlay

struct SmoothProgressOverlay: View {
    let targetProgress: Double
    var onFinished: (() -> Void)?

    @State private var displayedProgress: Double = 0
    @State private var currentStage: Int = 0
    @State private var timer: Timer?
    @State private var serverDone = false
    @State private var finishing = false
    @State private var completed = false

    private static let holdStages: Set<Int> = [5, 8]

    private static let stages: [(end: Double, label: String)] = [
        (8,   "Preparing your experience..."),
        (18,  "Listening to the soundtrack..."),
        (30,  "Feeling the frequencies..."),
        (42,  "Watching every frame..."),
        (54,  "Understanding the scene..."),
        (60,  "Learning the moments..."),
        (72,  "Crafting the vibrations..."),
        (82,  "Bringing it to life..."),
        (95,  "Final touches..."),
    ]

    private var stageLabel: String {
        if completed { return "Ready to feel" }
        let idx = min(currentStage, Self.stages.count - 1)
        return Self.stages[idx].label
    }

    var body: some View {
        VStack(spacing: 10) {
            ProgressView(value: displayedProgress, total: 100)
                .tint(.gray)
            HStack(spacing: 6) {
                if !completed {
                    ProgressView()
                        .controlSize(.mini)
                }
                Text(stageLabel)
                    .font(.caption)
                    .fontWeight(.medium)
                    .contentTransition(.numericText())
                Text("\(Int(displayedProgress))%")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .contentTransition(.numericText())
            }
            .foregroundStyle(.secondary)
            .animation(.easeInOut(duration: 0.3), value: currentStage)
            .animation(.easeInOut(duration: 0.3), value: completed)
        }
        .onAppear { advanceToNextStage() }
        .onChange(of: targetProgress) {
            if targetProgress >= 100 && !serverDone {
                serverDone = true
                if timer == nil && !finishing {
                    finishing = true
                    currentStage += 1
                    advanceToNextStage()
                }
            }
        }
        .onDisappear { timer?.invalidate() }
    }

    private func advanceToNextStage() {
        guard currentStage < Self.stages.count else {
            if serverDone { fillToComplete() }
            return
        }

        let stageEnd = Self.stages[currentStage].end
        let duration: TimeInterval = finishing ? 0.8 : 3.5
        let tickInterval: TimeInterval = 0.04
        let totalTicks = duration / tickInterval
        let progressNeeded = stageEnd - displayedProgress
        let stepPerTick = max(0.01, progressNeeded / totalTicks)

        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: tickInterval, repeats: true) { t in
            if displayedProgress < stageEnd {
                withAnimation(.linear(duration: tickInterval)) {
                    displayedProgress = min(displayedProgress + stepPerTick, stageEnd)
                }
            } else {
                t.invalidate()
                timer = nil

                if serverDone && !finishing {
                    finishing = true
                }

                if Self.holdStages.contains(currentStage) && !serverDone {
                    return
                }

                if currentStage < Self.stages.count - 1 {
                    currentStage += 1
                    advanceToNextStage()
                } else if serverDone {
                    fillToComplete()
                }
            }
        }
    }

    private func fillToComplete() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.03, repeats: true) { t in
            if displayedProgress < 100 {
                let step = max(0.4, (100 - displayedProgress) * 0.1)
                withAnimation(.linear(duration: 0.03)) {
                    displayedProgress = min(displayedProgress + step, 100)
                }
            } else {
                t.invalidate()
                timer = nil
                completed = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    onFinished?()
                }
            }
        }
    }
}
