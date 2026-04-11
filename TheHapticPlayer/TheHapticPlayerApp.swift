import SwiftUI

@main
struct TheHapticPlayerApp: App {
    @State private var videoStore = VideoStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(videoStore)
        }
    }
}
