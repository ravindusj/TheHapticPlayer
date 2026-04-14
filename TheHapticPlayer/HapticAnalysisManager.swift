import SwiftUI

@Observable
class HapticAnalysisManager {
    var activeError: String?

    private var pollingTasks: [UUID: Task<Void, Never>] = [:]
    private let apiClient = HapticAPIClient.shared
    private let maxRetries = 5

    func startAnalysis(
        for video: VideoItem,
        in store: VideoStore,
        sensitivity: Float = 0.5,
        style: String = "auto",
        bassBoost: Float = 1.0
    ) {
        pollingTasks[video.id]?.cancel()

        Task {
            do {
                let response = try await apiClient.analyzeVideo(
                    fileURL: video.fileURL,
                    sensitivity: sensitivity,
                    style: style,
                    bassBoost: bassBoost
                )

                await MainActor.run {
                    store.updateHapticStatus(
                        for: video.id,
                        jobId: response.jobId,
                        status: .queued,
                        progress: 0
                    )
                }

                startPolling(videoId: video.id, jobId: response.jobId, store: store)
            } catch {
                await MainActor.run {
                    self.activeError = error.localizedDescription
                    store.clearHapticData(for: video.id)
                }
            }
        }
    }

    func cancelAnalysis(for videoId: UUID) {
        pollingTasks[videoId]?.cancel()
        pollingTasks[videoId] = nil
    }

    func resumeIncompleteJobs(in store: VideoStore) {
        for video in store.videos {
            if video.isProcessingHaptics, let jobId = video.hapticJobId {
                // Try to resume — if server is down, it will auto-clear after retries
                startPolling(videoId: video.id, jobId: jobId, store: store)
            }
        }
    }

    func isAnalyzing(_ videoId: UUID) -> Bool {
        pollingTasks[videoId] != nil
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
                    failCount = 0 // Reset on success

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
                        }
                        break
                    }
                } catch {
                    failCount += 1
                    if failCount >= maxRetries {
                        await MainActor.run {
                            self.activeError = "Server unreachable. Analysis cancelled."
                            store.clearHapticData(for: videoId)
                        }
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
            }
        } catch {
            await MainActor.run {
                self.activeError = "Failed to download haptic data: \(error.localizedDescription)"
                store.clearHapticData(for: videoId)
            }
        }
    }
}
