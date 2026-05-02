import SwiftUI

@main
struct TheHapticPlayerApp: App {
    @State private var videoStore = VideoStore()
    @State private var hapticAnalysisManager = HapticAnalysisManager()
    @AppStorage("appTheme") private var appTheme: Int = AppTheme.system.rawValue
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let store = VideoStore()
        let manager = HapticAnalysisManager()
        BackgroundRefreshScheduler.register(manager: manager, store: store)
        _videoStore = State(initialValue: store)
        _hapticAnalysisManager = State(initialValue: manager)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(videoStore)
                .environment(hapticAnalysisManager)
                .preferredColorScheme(AppTheme(rawValue: appTheme)?.colorScheme)
                .task {
                    hapticAnalysisManager.resumeIncompleteJobs(in: videoStore)
                }
                .onChange(of: scenePhase) { _, phase in
                    switch phase {
                    case .background:
                        BackgroundRefreshScheduler.schedule()
                    case .active:
                        let activeIds = Set(
                            videoStore.videos
                                .filter { $0.isProcessingHaptics }
                                .map(\.id)
                        )
                        LiveActivityManager.shared.endStaleActivities(activeVideoIds: activeIds)
                    default:
                        break
                    }
                }
        }
    }
}
