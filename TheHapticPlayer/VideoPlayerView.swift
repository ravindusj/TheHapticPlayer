import SwiftUI
import AVKit

struct VideoPlayerView: View {
    let video: VideoItem
    @State private var player: AVPlayer?

    var body: some View {
        PlayerViewController(player: $player)
            .ignoresSafeArea()
            .navigationTitle(video.name)
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                let avPlayer = AVPlayer(url: video.fileURL)
                player = avPlayer
                avPlayer.play()
            }
            .onDisappear {
                player?.pause()
                player = nil
            }
    }
}

struct PlayerViewController: UIViewControllerRepresentable {
    @Binding var player: AVPlayer?

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.allowsPictureInPicturePlayback = true
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        controller.player = player
    }
}
