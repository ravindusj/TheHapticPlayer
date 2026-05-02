import BackgroundTasks
import Foundation

enum BackgroundRefreshScheduler {
    static let taskIdentifier = "fromravindusj.TheHapticPlayer.haptic-refresh"

    static func register(manager: HapticAnalysisManager, store: VideoStore) {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: taskIdentifier,
            using: nil
        ) { task in
            handle(task: task, manager: manager, store: store)
        }
    }

    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = Date().addingTimeInterval(5 * 60)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            print("Failed to schedule background refresh: \(error)")
        }
    }

    private static func handle(
        task: BGTask,
        manager: HapticAnalysisManager,
        store: VideoStore
    ) {
        schedule()

        let work = Task {
            await manager.refreshActiveJobs(in: store)
        }

        task.expirationHandler = {
            work.cancel()
        }

        Task {
            await work.value
            task.setTaskCompleted(success: !work.isCancelled)
        }
    }
}
