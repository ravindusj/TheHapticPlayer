import ActivityKit
import Foundation

@Observable
final class LiveActivityManager {
    static let shared = LiveActivityManager()

    private var activities: [UUID: Activity<HapticProcessingAttributes>] = [:]
    private var pendingCompletion: Set<UUID> = []
    private var completionFallbackTasks: [UUID: Task<Void, Never>] = [:]

    private init() {}

    func start(for video: VideoItem) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        if activities[video.id] != nil { return }

        let attributes = HapticProcessingAttributes(
            videoId: video.id,
            videoName: video.name
        )
        let initialState = HapticProcessingAttributes.ContentState(
            statusRaw: HapticStatus.queued.rawValue,
            statusLabel: HapticStatus.queued.displayLabel,
            progress: 0
        )

        do {
            let activity = try Activity.request(
                attributes: attributes,
                content: .init(state: initialState, staleDate: nil),
                pushType: nil
            )
            activities[video.id] = activity
        } catch {
            print("Failed to start Live Activity: \(error)")
        }
    }

    func update(videoId: UUID, status: HapticStatus, progress: Double?) {
        guard let activity = activities[videoId] else { return }
        let normalized = max(0, min(1, (progress ?? 0) / 100))
        let state = HapticProcessingAttributes.ContentState(
            statusRaw: status.rawValue,
            statusLabel: status.displayLabel,
            progress: normalized
        )
        Task {
            await activity.update(.init(state: state, staleDate: nil))
        }
    }

    /// Mirrors the in-app SmoothProgressOverlay's animated progress + stage label
    /// to the Live Activity so both UIs show identical values.
    func updateFromUI(videoId: UUID, progress: Double, label: String) {
        guard let activity = activities[videoId] else { return }
        let normalized = max(0, min(1, progress / 100))
        let state = HapticProcessingAttributes.ContentState(
            statusRaw: "",
            statusLabel: label,
            progress: normalized
        )
        Task {
            await activity.update(.init(state: state, staleDate: nil))
        }

        if pendingCompletion.contains(videoId), progress >= 100 {
            finalizeCompletion(videoId: videoId)
        }
    }

    /// Marks the activity as ready to end with a `.completed` final state once
    /// the in-app fake-progress driver reaches 100%. Falls back to ending after
    /// 6 seconds in case the UI never reports 100 (e.g., row not visible).
    func scheduleEndOnUICatchUp(videoId: UUID) {
        guard activities[videoId] != nil else { return }
        guard !pendingCompletion.contains(videoId) else { return }
        pendingCompletion.insert(videoId)

        completionFallbackTasks[videoId]?.cancel()
        completionFallbackTasks[videoId] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.finalizeCompletion(videoId: videoId)
            }
        }
    }

    private func finalizeCompletion(videoId: UUID) {
        guard pendingCompletion.contains(videoId) else { return }
        guard let activity = activities[videoId] else { return }
        pendingCompletion.remove(videoId)
        completionFallbackTasks[videoId]?.cancel()
        completionFallbackTasks[videoId] = nil
        activities[videoId] = nil

        let completedState = HapticProcessingAttributes.ContentState(
            statusRaw: HapticStatus.completed.rawValue,
            statusLabel: HapticStatus.completed.displayLabel,
            progress: 1.0
        )

        Task {
            // First push the completed state while the activity is still active —
            // this is what makes the Dynamic Island show the green tick (ended
            // activities are dropped from the island immediately regardless of
            // dismissalPolicy).
            await activity.update(.init(state: completedState, staleDate: nil))
            try? await Task.sleep(for: .seconds(2.5))
            await activity.end(
                .init(state: completedState, staleDate: nil),
                dismissalPolicy: .after(Date().addingTimeInterval(2))
            )
        }
    }

    func end(videoId: UUID, finalStatus: HapticStatus) {
        guard let activity = activities[videoId] else { return }
        activities[videoId] = nil
        pendingCompletion.remove(videoId)
        completionFallbackTasks[videoId]?.cancel()
        completionFallbackTasks[videoId] = nil
        let state = HapticProcessingAttributes.ContentState(
            statusRaw: finalStatus.rawValue,
            statusLabel: finalStatus.displayLabel,
            progress: finalStatus == .completed ? 1.0 : 0
        )
        Task {
            await activity.end(
                .init(state: state, staleDate: nil),
                dismissalPolicy: .after(Date().addingTimeInterval(4))
            )
        }
    }

    func endStaleActivities(activeVideoIds: Set<UUID>) {
        let stale = activities.keys.filter { !activeVideoIds.contains($0) }
        for id in stale {
            end(videoId: id, finalStatus: .completed)
        }
    }

    func hasActivity(for videoId: UUID) -> Bool {
        activities[videoId] != nil
    }
}
