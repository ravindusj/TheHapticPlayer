import SwiftUI

struct ContentView: View {
    @Environment(VideoStore.self) var videoStore
    @Environment(HapticAnalysisManager.self) var hapticManager
    @State private var showingPhotoPicker = false
    @State private var showingDocumentPicker = false
    @State private var selectedVideoForInfo: VideoItem?
    @State private var selectedVideoForPlay: VideoItem?
    @State private var searchText = ""
    @State private var videoToDelete: VideoItem?
    @State private var isSelecting = false
    @State private var selectedVideos: Set<UUID> = []
    @State private var showBatchDeleteConfirm = false
    @State private var showHapticError = false
    @State private var animatingVideos: Set<UUID> = []
    @State private var shimmeringVideos: Set<UUID> = []
    @State private var videoToCancel: VideoItem?
    @State private var showCancelConfirm = false
    @State private var cancelMode: CancelMode = .analysis
    @State private var knownVideoIds: Set<UUID> = []

    enum CancelMode {
        case upload, analysis
    }

    var filteredVideos: [VideoItem] {
        if searchText.isEmpty { return videoStore.videos }
        return videoStore.videos.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var processingVideoIds: Set<UUID> {
        Set(videoStore.videos.filter(\.isProcessingHaptics).map(\.id))
    }

    var body: some View {
        NavigationStack {
            mainContent
                .animation(.easeInOut(duration: 0.25), value: isSelecting)
                .searchable(text: $searchText, prompt: "TheHaptic Player")
                .background(
                    PlayerPresenter(video: $selectedVideoForPlay, videoStore: videoStore)
                        .frame(width: 0, height: 0)
                )
                .navigationTitle("TheHaptic Player")
                .toolbar { toolbarContent }
                .sheet(item: $selectedVideoForInfo) { video in
                    VideoInfoSheet(videoID: video.id, dismiss: { selectedVideoForInfo = nil })
                }
                .sheet(isPresented: $showingPhotoPicker) { PhotoPickerView() }
                .sheet(isPresented: $showingDocumentPicker) { DocumentPickerView() }
        }
        .modifier(ContentViewAlerts(
            selectedVideos: $selectedVideos,
            showBatchDeleteConfirm: $showBatchDeleteConfirm,
            videoToDelete: $videoToDelete,
            showCancelConfirm: $showCancelConfirm,
            videoToCancel: $videoToCancel,
            showHapticError: $showHapticError,
            shimmeringVideos: $shimmeringVideos,
            cancelMode: cancelMode,
            batchDelete: batchDelete,
            deleteSingle: deleteSingle,
            cancelAnalysis: cancelAnalysis
        ))
        .onChange(of: videoStore.videos.count) { oldCount, newCount in
            if newCount > oldCount { handleNewVideos() }
        }
        .onChange(of: processingVideoIds) { _, _ in
            fadeOutShimmers()
        }
        .onAppear {
            knownVideoIds = Set(videoStore.videos.map(\.id))
        }
    }

    private var mainContent: some View {
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
    }

    // MARK: - Video List

    private var videoList: some View {
        List {
            ForEach(Array(filteredVideos.enumerated()), id: \.element.id) { index, video in
                VideoRowView(
                    video: video,
                    isSelecting: isSelecting,
                    isSelected: selectedVideos.contains(video.id),
                    isBlurred: video.isProcessingHaptics || animatingVideos.contains(video.id),
                    isShimmering: shimmeringVideos.contains(video.id),
                    isFirst: index == 0,
                    isLast: index == filteredVideos.count - 1,
                    onTap: { handleTap(video) },
                    onLongPress: { handleLongPress(video) },
                    onAnimationStarted: { animatingVideos.insert(video.id) },
                    onAnimationFinished: {
                        let _ = withAnimation(.easeInOut(duration: 0.4)) {
                            animatingVideos.remove(video.id)
                        }
                    }
                )
                .listRowInsets(EdgeInsets())
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
                        if video.hasHaptics {
                            Button {
                                videoStore.toggleHapticsEnabled(for: video.id)
                            } label: {
                                Image(systemName: video.isHapticsEnabled ? "waveform.slash" : "waveform")
                            }
                            .tint(video.isHapticsEnabled ? .orange : .green)
                        }
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
                HStack(spacing: 16) {
                    Button("Cancel") {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            isSelecting = false
                            selectedVideos.removeAll()
                        }
                    }
                    Button("Select All") {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedVideos = Set(filteredVideos.map(\.id))
                        }
                    }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showBatchDeleteConfirm = true } label: {
                    Image(systemName: "trash").foregroundStyle(.red)
                }
                .disabled(selectedVideos.isEmpty)
            }
        } else if videoToCancel != nil {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        videoToCancel = nil
                    }
                } label: {
                    Image(systemName: "xmark")
                        
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .destructive) {
                    showCancelConfirm = true
                } label: {
                    Text("Cancel")
                        .foregroundStyle(.red)
                }
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

    private func handleNewVideos() {
        let newVideos = videoStore.videos.filter { !knownVideoIds.contains($0.id) }
        guard !newVideos.isEmpty else { return }

        for video in newVideos {
            knownVideoIds.insert(video.id)
            shimmeringVideos.insert(video.id)
        }

        // Start upload immediately — shimmer runs until server responds
        Task {
            let serverUp = (try? await HapticAPIClient.shared.healthCheck()) ?? false
            await MainActor.run {
                if serverUp {
                    for video in newVideos {
                        hapticManager.startAnalysis(for: video, in: videoStore)
                    }
                } else {
                    withAnimation(.easeInOut(duration: 0.4)) {
                        for video in newVideos {
                            shimmeringVideos.remove(video.id)
                        }
                    }
                    for video in newVideos {
                        if let index = videoStore.videos.firstIndex(where: { $0.id == video.id }) {
                            videoStore.deleteVideo(at: IndexSet(integer: index))
                        }
                    }
                    hapticManager.activeError = "Cannot connect to haptic server. Video was not added."
                }
            }
        }
    }

    private func handleTap(_ video: VideoItem) {
        guard !video.isProcessingHaptics,
              !animatingVideos.contains(video.id),
              !shimmeringVideos.contains(video.id) else { return }
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
        guard !isSelecting else { return }
        let isUploading = shimmeringVideos.contains(video.id) && !video.isProcessingHaptics
        let isAnalysing = video.isProcessingHaptics || animatingVideos.contains(video.id)
        if isUploading {
            cancelMode = .upload
            withAnimation(.easeInOut(duration: 0.25)) {
                videoToCancel = video
            }
        } else if isAnalysing {
            cancelMode = .analysis
            withAnimation(.easeInOut(duration: 0.25)) {
                videoToCancel = video
            }
        } else {
            withAnimation(.easeInOut(duration: 0.25)) {
                isSelecting = true
                selectedVideos = [video.id]
            }
        }
    }

    private func fadeOutShimmers() {
        let started = shimmeringVideos.intersection(processingVideoIds)
        guard !started.isEmpty else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            withAnimation(.easeInOut(duration: 0.5)) {
                shimmeringVideos.subtract(started)
            }
        }
    }

    private func cancelAnalysis() {
        guard let video = videoToCancel else { return }
        let mode = cancelMode
        hapticManager.cancelAnalysis(for: video.id)
        withAnimation(.easeInOut(duration: 0.4)) {
            animatingVideos.remove(video.id)
            shimmeringVideos.remove(video.id)
            videoToCancel = nil
        }
        if mode == .upload {
            // Upload cancelled — remove video entirely
            knownVideoIds.remove(video.id)
            if let index = videoStore.videos.firstIndex(where: { $0.id == video.id }) {
                videoStore.deleteVideo(at: IndexSet(integer: index))
            }
        } else {
            // Analysis cancelled — keep video, just clear haptic data
            videoStore.clearHapticData(for: video.id)
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
    let isShimmering: Bool
    let isFirst: Bool
    let isLast: Bool
    let onTap: () -> Void
    let onLongPress: () -> Void
    let onAnimationStarted: () -> Void
    let onAnimationFinished: () -> Void

    private var shimmerShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: isFirst ? 10 : 0,
            bottomLeadingRadius: isLast ? 10 : 0,
            bottomTrailingRadius: isLast ? 10 : 0,
            topTrailingRadius: isFirst ? 10 : 0
        )
    }

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
        .padding(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
        .overlay {
            if isShimmering {
                ShimmerView()
                    .id(video.id)
                    .clipShape(shimmerShape)
                    .allowsHitTesting(false)
            }
        }
        .animation(.easeInOut(duration: 0.4), value: isBlurred)
        .animation(.easeInOut(duration: 0.3), value: isShimmering)
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
                HStack(spacing: 6) {
                    Text(video.dateAdded, style: .date)
                    if let duration = video.duration {
                        Text("·")
                        Text(formatDuration(duration))
                    }
                    if video.hasHaptics {
                        Text("·")
                        Text("HAPTIC")
                            .font(.system(size: 8, weight: .semibold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .overlay(
                                RoundedRectangle(cornerRadius: 3)
                                    .stroke(.secondary, lineWidth: 0.8)
                            )
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
    let videoID: UUID
    let dismiss: () -> Void
    @Environment(VideoStore.self) var videoStore
    @Environment(HapticAnalysisManager.self) var hapticManager
    @State private var showingRename = false
    @State private var renameText = ""

    private var video: VideoItem? {
        videoStore.videos.first { $0.id == videoID }
    }

    var body: some View {
        NavigationStack {
            Group {
                if let video {
                    List {
                        detailsSection(video)
                        hapticsSection(video)
                    }
                } else {
                    ContentUnavailableView("Video Unavailable", systemImage: "film")
                }
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
        .alert("Rename Video", isPresented: $showingRename) {
            TextField("Video name", text: $renameText)
            Button("Cancel", role: .cancel) {}
            Button("Save") { saveRename() }
        }
    }

    private func detailsSection(_ video: VideoItem) -> some View {
        Section("Details") {
            LabeledContent("Name", value: video.name)
            LabeledContent("Added", value: video.dateAdded, format: .dateTime)
            LabeledContent("File Size", value: fileSizeString(video))
            LabeledContent("Format", value: video.fileName.components(separatedBy: ".").last?.uppercased() ?? "Unknown")
            if let duration = video.duration {
                LabeledContent("Duration", value: formatDuration(duration))
            }
            if let position = video.lastPlaybackPosition, position > 0 {
                LabeledContent("Resume At", value: formatDuration(position))
            }
            Button("Rename", systemImage: "pencil") {
                renameText = video.name
                showingRename = true
            }
        }
    }

    private func hapticsSection(_ video: VideoItem) -> some View {
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

    private func saveRename() {
        let trimmed = renameText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        videoStore.renameVideo(id: videoID, newName: trimmed)
    }

    private func fileSizeString(_ video: VideoItem) -> String {
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
    @State private var stageTargets: [Double] = []
    @State private var holdStageIndices: Set<Int> = []

    private static let labels: [String] = [
        "Preparing your experience...",
        "Listening to the soundtrack...",
        "Feeling the frequencies...",
        "Watching every frame...",
        "Understanding the scene...",
        "Learning the moments...",
        "Crafting the vibrations...",
        "Bringing it to life...",
        "Final touches...",
    ]

    /// Generates randomized stage endpoints so each run feels different
    private static func generateStageTargets() -> [Double] {
        // Base ranges for each stage — randomize within these bands
        let bands: [(low: Double, high: Double)] = [
            (5, 12),      // stage 0: ~5-12%
            (14, 22),     // stage 1: ~14-22%
            (25, 38),     // stage 2: ~25-38%
            (36, 48),     // stage 3: ~36-48%
            (46, 58),     // stage 4: ~46-58%
            (55, 68),     // stage 5: ~55-68%
            (65, 78),     // stage 6: ~65-78%
            (76, 88),     // stage 7: ~76-88%
            (90, 97),     // stage 8: ~90-97%
        ]
        var targets: [Double] = []
        var prev: Double = 0
        for band in bands {
            let clamped = max(prev + 3, Double.random(in: band.low...band.high))
            targets.append(min(clamped, 98))
            prev = clamped
        }
        return targets
    }

    /// Pick 2–3 random stages to pause at (waiting for server)
    private static func generateHoldStages() -> Set<Int> {
        let count = Int.random(in: 2...3)
        // Pick from middle stages (1–7) to hold at
        var holds: Set<Int> = []
        let candidates = Array(1...7)
        while holds.count < count {
            holds.insert(candidates.randomElement()!)
        }
        return holds
    }

    private var stageLabel: String {
        if completed { return "Ready to feel" }
        let idx = min(currentStage, Self.labels.count - 1)
        return Self.labels[idx]
    }

    @Environment(\.colorScheme) private var colorScheme

    private var progressColor: Color {
        colorScheme == .light ? .black : .gray
    }

    var body: some View {
        VStack(spacing: 10) {
            ProgressView(value: displayedProgress, total: 100)
                .tint(progressColor)
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
            .foregroundStyle(progressColor)
            .animation(.easeInOut(duration: 0.3), value: currentStage)
            .animation(.easeInOut(duration: 0.3), value: completed)
        }
        .onAppear {
            stageTargets = Self.generateStageTargets()
            holdStageIndices = Self.generateHoldStages()
            advanceToNextStage()
        }
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
        guard currentStage < stageTargets.count else {
            if serverDone { fillToComplete() }
            return
        }

        let stageEnd = stageTargets[currentStage]
        // Randomize duration per stage so speed feels organic
        let baseDuration: TimeInterval = finishing ? Double.random(in: 0.5...1.0) : Double.random(in: 2.0...5.0)
        let tickInterval: TimeInterval = 0.04
        let totalTicks = baseDuration / tickInterval
        let progressNeeded = stageEnd - displayedProgress
        let stepPerTick = max(0.01, progressNeeded / totalTicks)

        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: tickInterval, repeats: true) { t in
            if displayedProgress < stageEnd {
                // Add slight jitter to step size for realism
                let jitter = Double.random(in: 0.7...1.3)
                withAnimation(.linear(duration: tickInterval)) {
                    displayedProgress = min(displayedProgress + stepPerTick * jitter, stageEnd)
                }
            } else {
                t.invalidate()
                timer = nil

                if serverDone && !finishing {
                    finishing = true
                }

                // Hold at random stages until server finishes
                if holdStageIndices.contains(currentStage) && !serverDone {
                    return
                }

                // Random micro-pause between stages (0.3–1.5s) to feel natural
                let pause = finishing ? 0.15 : Double.random(in: 0.3...1.5)
                DispatchQueue.main.asyncAfter(deadline: .now() + pause) {
                    if currentStage < stageTargets.count - 1 {
                        currentStage += 1
                        advanceToNextStage()
                    } else if serverDone {
                        fillToComplete()
                    }
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

// MARK: - Shimmer

struct ShimmerView: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var startPoint: UnitPoint = .init(x: -0.8, y: 0.35)
    @State private var endPoint: UnitPoint = .init(x: -0.1, y: 0.65)

    private var peakOpacity: Double {
        colorScheme == .dark ? 0.32 : 0.8
    }

    private var glowOpacity: Double {
        colorScheme == .dark ? 0.16 : 0.42
    }

    private var softOpacity: Double {
        colorScheme == .dark ? 0.06 : 0.16
    }

    var body: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    stops: [
                        .init(color: .white.opacity(0), location: 0.0),
                        .init(color: .white.opacity(softOpacity), location: 0.2),
                        .init(color: .white.opacity(glowOpacity), location: 0.4),
                        .init(color: .white.opacity(peakOpacity), location: 0.5),
                        .init(color: .white.opacity(glowOpacity), location: 0.6),
                        .init(color: .white.opacity(softOpacity), location: 0.8),
                        .init(color: .white.opacity(0), location: 1.0),
                    ],
                    startPoint: startPoint,
                    endPoint: endPoint
                )
            )
            .onAppear {
                withAnimation(
                    .easeInOut(duration: 1.2).repeatForever(autoreverses: false)
                ) {
                    startPoint = .init(x: 1.1, y: 0.35)
                    endPoint = .init(x: 1.8, y: 0.65)
                }
            }
    }
}

// MARK: - Alerts Modifier

struct ContentViewAlerts: ViewModifier {
    @Binding var selectedVideos: Set<UUID>
    @Binding var showBatchDeleteConfirm: Bool
    @Binding var videoToDelete: VideoItem?
    @Binding var showCancelConfirm: Bool
    @Binding var videoToCancel: VideoItem?
    @Binding var showHapticError: Bool
    @Binding var shimmeringVideos: Set<UUID>
    var cancelMode: ContentView.CancelMode
    var batchDelete: () -> Void
    var deleteSingle: () -> Void
    var cancelAnalysis: () -> Void
    @Environment(HapticAnalysisManager.self) var hapticManager

    func body(content: Content) -> some View {
        content
            .alert("Delete \(selectedVideos.count) Video\(selectedVideos.count == 1 ? "" : "s")?", isPresented: $showBatchDeleteConfirm) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) { batchDelete() }
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
            .alert(cancelMode == .upload ? "Cancel Upload?" : "Cancel Analysis?", isPresented: $showCancelConfirm) {
                Button(cancelMode == .upload ? "Keep Uploading" : "Keep Analysing", role: .cancel) {}
                Button("Cancel", role: .destructive) { cancelAnalysis() }
            } message: {
                if let video = videoToCancel {
                    if cancelMode == .upload {
                        Text("Stop uploading \"\(video.name)\"? The video will be removed.")
                    } else {
                        Text("Stop haptic analysis for \"\(video.name)\"? The video will be kept.")
                    }
                }
            }
            .alert("Haptic Analysis Error", isPresented: $showHapticError) {
                Button("OK", role: .cancel) { hapticManager.activeError = nil }
            } message: {
                Text(hapticManager.activeError ?? "An unknown error occurred.")
            }
            .onChange(of: hapticManager.activeError) { _, newValue in
                if newValue != nil {
                    showHapticError = true
                    withAnimation(.easeInOut(duration: 0.4)) {
                        shimmeringVideos.removeAll()
                    }
                }
            }
    }
}
