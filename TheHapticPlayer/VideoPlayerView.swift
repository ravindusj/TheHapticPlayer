import SwiftUI
import AVKit

struct VideoPlayerView: View {
    let video: VideoItem
    @Environment(VideoStore.self) var videoStore
    @State private var player: AVPlayer?
    @State private var showResumeAlert = false
    @State private var resumePosition: TimeInterval = 0
    @State private var isFullscreen = false

    var body: some View {
        PlayerViewController(player: $player)
            .ignoresSafeArea()
            .navigationTitle(video.name)
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                UIDevice.current.beginGeneratingDeviceOrientationNotifications()
                let avPlayer = AVPlayer(url: video.fileURL)
                player = avPlayer

                if let position = video.lastPlaybackPosition, position > 0 {
                    resumePosition = position
                    showResumeAlert = true
                } else {
                    avPlayer.play()
                }
            }
            .onDisappear {
                savePosition()
                UIDevice.current.endGeneratingDeviceOrientationNotifications()
            }
            .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
                let orientation = UIDevice.current.orientation
                if orientation.isLandscape && !isFullscreen {
                    isFullscreen = true
                }
            }
            .fullScreenCover(isPresented: $isFullscreen) {
                FullscreenPlayerView(player: $player, isFullscreen: $isFullscreen)
            }
            .alert("Resume Playback", isPresented: $showResumeAlert) {
                Button("Yes") {
                    let time = CMTime(seconds: resumePosition, preferredTimescale: 600)
                    player?.seek(to: time)
                    player?.play()
                }
                Button("No", role: .cancel) {
                    player?.play()
                }
            } message: {
                Text("Continue from \(formatTime(resumePosition))?")
            }
    }

    private func savePosition() {
        if let currentTime = player?.currentTime() {
            let seconds = CMTimeGetSeconds(currentTime)
            if seconds.isFinite && seconds > 0 {
                videoStore.updatePlaybackPosition(for: video.id, position: seconds)
            }
        }
        player?.pause()
        player = nil
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        let secs = Int(seconds) % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }
}

// Full screen player presented on landscape rotation
struct FullscreenPlayerView: View {
    @Binding var player: AVPlayer?
    @Binding var isFullscreen: Bool

    var body: some View {
        PlayerViewController(player: $player)
            .ignoresSafeArea()
            .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
                if UIDevice.current.orientation.isPortrait {
                    isFullscreen = false
                }
            }
    }
}

struct PlayerViewController: UIViewControllerRepresentable {
    @Binding var player: AVPlayer?

    func makeUIViewController(context: Context) -> RotatablePlayerViewController {
        let controller = RotatablePlayerViewController()
        controller.allowsPictureInPicturePlayback = true
        return controller
    }

    func updateUIViewController(_ controller: RotatablePlayerViewController, context: Context) {
        controller.player = player
    }

    static func dismantleUIViewController(_ uiViewController: RotatablePlayerViewController, coordinator: ()) {
        uiViewController.player = nil
    }
}

final class RotatablePlayerViewController: AVPlayerViewController {
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .all }
    override var shouldAutorotate: Bool { true }
}
