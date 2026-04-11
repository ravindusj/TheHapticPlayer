import SwiftUI
import AVKit

struct VideoPlayerView: View {
    let video: VideoItem
    @Environment(VideoStore.self) var videoStore
    @State private var player: AVPlayer?
    @State private var showResumeAlert = false
    @State private var resumePosition: TimeInterval = 0

    var body: some View {
        PlayerViewController(player: $player)
            .ignoresSafeArea()
            .navigationTitle(video.name)
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                let avPlayer = AVPlayer(url: video.fileURL)
                player = avPlayer

                // Check if there's a saved position
                if let position = video.lastPlaybackPosition, position > 0 {
                    resumePosition = position
                    showResumeAlert = true
                } else {
                    avPlayer.play()
                }

                // Fetch duration if not stored yet
                if video.duration == nil {
                    Task {
                        if let duration = try? await avPlayer.currentItem?.asset.load(.duration) {
                            let seconds = CMTimeGetSeconds(duration)
                            if seconds.isFinite {
                                videoStore.updateDuration(for: video.id, duration: seconds)
                            }
                        }
                    }
                }
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
            .onDisappear {
                // Save current position
                if let currentTime = player?.currentTime() {
                    let seconds = CMTimeGetSeconds(currentTime)
                    if seconds.isFinite && seconds > 0 {
                        videoStore.updatePlaybackPosition(for: video.id, position: seconds)
                    }
                }
                player?.pause()
                player = nil
            }
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

struct PlayerViewController: UIViewControllerRepresentable {
    @Binding var player: AVPlayer?

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.allowsPictureInPicturePlayback = true
        controller.entersFullScreenWhenPlaybackBegins = false
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        controller.player = player
    }

    // Support landscape auto-rotation
    static func dismantleUIViewController(_ uiViewController: AVPlayerViewController, coordinator: ()) {
        uiViewController.player = nil
    }
}
