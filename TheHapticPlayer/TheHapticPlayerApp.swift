import SwiftUI

@main
struct TheHapticPlayerApp: App {
    @State private var videoStore = VideoStore()
    @State private var hapticAnalysisManager = HapticAnalysisManager()
    @AppStorage("appTheme") private var appTheme: Int = AppTheme.system.rawValue

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(videoStore)
                .environment(hapticAnalysisManager)
                .preferredColorScheme(AppTheme(rawValue: appTheme)?.colorScheme)
                .task {
                    hapticAnalysisManager.resumeIncompleteJobs(in: videoStore)
                }
        }
    }
}
