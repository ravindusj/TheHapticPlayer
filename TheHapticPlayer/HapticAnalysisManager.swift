import SwiftUI
import UIKit

@Observable
class HapticAnalysisManager {
    var activeError: String?

    private var pollingTasks: [UUID: Task<Void, Never>] = [:]
    private var uploadTasks: [UUID: Task<Void, Never>] = [:]
    private var bgTaskIds: [UUID: UIBackgroundTaskIdentifier] = [:]
    private let apiClient = HapticAPIClient.shared
    private let maxRetries = 5

    func startAnalysis(
        for video: VideoItem,
        in store: VideoStore,
        sensitivity: Float = 0.5,
        style: String = "auto",
        bassBoost: Float = 1.0
    ) {
        uploadTasks[video.id]?.cancel()
        pollingTasks[video.id]?.cancel()

        let videoId = video.id
        beginBackgroundTask(for: videoId)
        LiveActivityManager.shared.start(for: video)

        uploadTasks[videoId] = Task {
            do {
                let response = try await apiClient.analyzeVideo(
                    fileURL: video.fileURL,
                    sensitivity: sensitivity,
                    style: style,
                    bassBoost: bassBoost
                )

                if Task.isCancelled {
                    uploadTasks[videoId] = nil
                    return
                }

                await MainActor.run {
                    store.updateHapticStatus(
                        for: videoId,
                        jobId: response.jobId,
                        status: .queued,
                        progress: 0
                    )
                }

                uploadTasks[videoId] = nil
                startPolling(videoId: videoId, jobId: response.jobId, store: store)
            } catch {
                uploadTasks[videoId] = nil
                if Task.isCancelled { return }
                await MainActor.run {
                    self.activeError = error.localizedDescription
                    store.clearHapticData(for: videoId)
                    LiveActivityManager.shared.end(videoId: videoId, finalStatus: .failed)
                }
                endBackgroundTask(for: videoId)
            }
        }
    }

    func cancelAnalysis(for videoId: UUID) {
        uploadTasks[videoId]?.cancel()
        uploadTasks[videoId] = nil
        pollingTasks[videoId]?.cancel()
        pollingTasks[videoId] = nil
        LiveActivityManager.shared.end(videoId: videoId, finalStatus: .failed)
        endBackgroundTask(for: videoId)
    }

    func isUploading(_ videoId: UUID) -> Bool {
        uploadTasks[videoId] != nil
    }

    func resumeIncompleteJobs(in store: VideoStore) {
        for video in store.videos {
            if video.isProcessingHaptics, let jobId = video.hapticJobId {
                beginBackgroundTask(for: video.id)
                if !LiveActivityManager.shared.hasActivity(for: video.id) {
                    LiveActivityManager.shared.start(for: video)
                }
                startPolling(videoId: video.id, jobId: jobId, store: store)
            }
        }
    }

    func isAnalyzing(_ videoId: UUID) -> Bool {
        pollingTasks[videoId] != nil
    }

    /// Performs a single status check for every active job — used by BGAppRefreshTask
    /// when the app is suspended. Updates Live Activity, downloads AHAP if completed,
    /// and does NOT loop (the system gives us a short, finite window).
    func refreshActiveJobs(in store: VideoStore) async {
        let activeVideos = await MainActor.run {
            store.videos.filter { $0.isProcessingHaptics && $0.hapticJobId != nil }
        }

        for video in activeVideos {
            guard let jobId = video.hapticJobId else { continue }
            do {
                let status = try await apiClient.checkStatus(jobId: jobId)
                let hapticStatus = HapticStatus(rawValue: status.status) ?? .queued

                await MainActor.run {
                    store.updateHapticStatus(
                        for: video.id,
                        jobId: jobId,
                        status: hapticStatus,
                        progress: status.progress
                    )
                }

                if status.status == "completed" {
                    await downloadAndSave(videoId: video.id, jobId: jobId, store: store)
                } else if status.status == "failed" {
                    await MainActor.run {
                        store.clearHapticData(for: video.id)
                        LiveActivityManager.shared.end(videoId: video.id, finalStatus: .failed)
                    }
                    endBackgroundTask(for: video.id)
                }
            } catch {
                // Swallow — next refresh tick (or app foregrounding) will retry.
            }
        }
    }

    private func startPolling(videoId: UUID, jobId: String, store: VideoStore) {
        pollingTasks[videoId]?.cancel()
        pollingTasks[videoId] = Task {
            var failCount = 0

            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled else { break }

                do {
                    let status = try await apiClient.checkStatus(jobId: jobId)
                    failCount = 0

                    await MainActor.run {
                        let hapticStatus = HapticStatus(rawValue: status.status) ?? .queued
                        store.updateHapticStatus(
                            for: videoId,
                            jobId: jobId,
                            status: hapticStatus,
                            progress: status.progress
                        )
                    }

                    if status.status == "completed" {
                        await downloadAndSave(videoId: videoId, jobId: jobId, store: store)
                        break
                    } else if status.status == "failed" {
                        await MainActor.run {
                            self.activeError = status.error ?? "Analysis failed"
                            store.clearHapticData(for: videoId)
                            LiveActivityManager.shared.end(videoId: videoId, finalStatus: .failed)
                        }
                        endBackgroundTask(for: videoId)
                        break
                    }
                } catch {
                    failCount += 1
                    if failCount >= maxRetries {
                        await MainActor.run {
                            self.activeError = "Server unreachable. Analysis cancelled."
                            store.clearHapticData(for: videoId)
                            LiveActivityManager.shared.end(videoId: videoId, finalStatus: .failed)
                        }
                        endBackgroundTask(for: videoId)
                        break
                    }
                }
            }
            pollingTasks[videoId] = nil
        }
    }

    private func downloadAndSave(videoId: UUID, jobId: String, store: VideoStore) async {
        let fileName = "\(videoId.uuidString).ahap"
        let destinationURL = VideoItem.hapticsDirectory.appendingPathComponent(fileName)

        do {
            try await apiClient.downloadAHAP(jobId: jobId, destinationURL: destinationURL)
            await MainActor.run {
                store.setAHAPFile(for: videoId, fileName: fileName)
                LiveActivityManager.shared.scheduleEndOnUICatchUp(videoId: videoId)
            }
            endBackgroundTask(for: videoId)
        } catch {
            await MainActor.run {
                self.activeError = "Failed to download haptic data: \(error.localizedDescription)"
                store.clearHapticData(for: videoId)
                LiveActivityManager.shared.end(videoId: videoId, finalStatus: .failed)
            }
            endBackgroundTask(for: videoId)
        }
    }

    private func beginBackgroundTask(for videoId: UUID) {
        if let existing = bgTaskIds[videoId], existing != .invalid {
            UIApplication.shared.endBackgroundTask(existing)
        }
        let id = UIApplication.shared.beginBackgroundTask(withName: "haptic-\(videoId)") { [weak self] in
            self?.endBackgroundTask(for: videoId)
        }
        bgTaskIds[videoId] = id
    }

    private func endBackgroundTask(for videoId: UUID) {
        guard let id = bgTaskIds[videoId], id != .invalid else { return }
        UIApplication.shared.endBackgroundTask(id)
        bgTaskIds[videoId] = nil
    }
}
