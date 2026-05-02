import SwiftUI
import AVKit

struct PlayerPresenter: UIViewRepresentable {
    @Binding var video: VideoItem?
    let videoStore: VideoStore

    @AppStorage("autoResume") private var autoResume = false
    @AppStorage("defaultPlaybackSpeed") private var defaultPlaybackSpeed: Double = 1.0

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.videoStore = videoStore
        context.coordinator.autoResume = autoResume
        context.coordinator.defaultPlaybackSpeed = defaultPlaybackSpeed
        context.coordinator.onDismiss = { self.video = nil }

        if let video = self.video {
            DispatchQueue.main.async {
                context.coordinator.present(video: video, from: uiView)
            }
        } else if context.coordinator.playerVC != nil {
            DispatchQueue.main.async {
                context.coordinator.dismiss(userInitiated: false)
            }
        }
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        coordinator.dismiss(userInitiated: false)
    }

    final class Coordinator: NSObject, AVPlayerViewControllerDelegate {
        var videoStore: VideoStore?
        var autoResume: Bool = false
        var defaultPlaybackSpeed: Double = 1.0
        var onDismiss: (() -> Void)?

        weak var playerVC: AVPlayerViewController?
        var currentPlayer: AVPlayer?
        var currentVideoID: UUID?
        var hapticEngine = HapticEngineManager()
        var devOverlayHost: UIHostingController<HapticDevOverlay>?
        var devSession: HapticDevSession?

        func present(video: VideoItem, from sourceView: UIView) {
            guard playerVC == nil else { return }
            guard let presenter = Self.topMostViewController(from: sourceView) else { return }

            let defaultSpeed = self.defaultPlaybackSpeed

            if let position = video.lastPlaybackPosition, position > 0, !autoResume {
                let alert = UIAlertController(
                    title: "Resume Playback",
                    message: "Continue from \(Self.formatTime(position))?",
                    preferredStyle: .alert
                )
                alert.addAction(UIAlertAction(title: "Yes", style: .default) { [weak self] _ in
                    self?.startPlayback(video: video, seekTo: position, speed: defaultSpeed, presenter: presenter)
                })
                alert.addAction(UIAlertAction(title: "No", style: .cancel) { [weak self] _ in
                    self?.startPlayback(video: video, seekTo: nil, speed: defaultSpeed, presenter: presenter)
                })
                presenter.present(alert, animated: true)
                return
            }

            let seek = (autoResume ? video.lastPlaybackPosition : nil).flatMap { $0 > 0 ? $0 : nil }
            startPlayback(video: video, seekTo: seek, speed: defaultSpeed, presenter: presenter)
        }

        private func startPlayback(
            video: VideoItem,
            seekTo position: TimeInterval?,
            speed: Double,
            presenter: UIViewController
        ) {
            let item = AVPlayerItem(url: video.fileURL)
            item.externalMetadata = Self.externalMetadata(title: video.name)
            let avPlayer = AVPlayer(playerItem: item)

            let vc = AVPlayerViewController()
            vc.player = avPlayer
            vc.allowsPictureInPicturePlayback = true
            vc.canStartPictureInPictureAutomaticallyFromInline = true
            vc.delegate = self
            vc.modalPresentationStyle = .fullScreen
            vc.modalTransitionStyle = .coverVertical

            self.playerVC = vc
            self.currentPlayer = avPlayer
            self.currentVideoID = video.id

            if video.hasHaptics, video.isHapticsEnabled, let ahapURL = video.ahapFileURL {
                do {
                    try hapticEngine.loadAHAP(from: ahapURL)
                    hapticEngine.attachToPlayer(avPlayer)
                    setupDevOverlayIfEnabled(video: video, ahapURL: ahapURL, on: vc)
                } catch {
                    print("Failed to load haptics: \(error)")
                }
            }

            if let position {
                let time = CMTime(seconds: position, preferredTimescale: 600)
                avPlayer.seek(to: time)
            }

            presenter.present(vc, animated: true) {
                avPlayer.play()
                avPlayer.rate = Float(speed)
            }
        }

        private func setupDevOverlayIfEnabled(video: VideoItem, ahapURL: URL, on vc: AVPlayerViewController) {
            let defaults = UserDefaults.standard
            guard defaults.bool(forKey: "developerModeEnabled"),
                  defaults.bool(forKey: "hapticDevPanelEnabled") else { return }

            let parsed = AHAPParser.parse(url: ahapURL)
            guard !parsed.events.isEmpty else { return }

            let session = HapticDevSession()
            session.events = parsed.events
            session.totalDuration = parsed.totalDuration
            self.devSession = session

            hapticEngine.onEventFired = { [weak session] event in
                Task { @MainActor in session?.fire(event) }
            }
            hapticEngine.onTimeUpdated = { [weak session] t in
                Task { @MainActor in
                    session?.currentTime = t
                    session?.tickWaveform()
                }
            }
            hapticEngine.onSeekDetected = { [weak session] in
                Task { @MainActor in session?.resetForSeek() }
            }

            let host = UIHostingController(rootView: HapticDevOverlay(session: session))
            host.view.backgroundColor = .clear
            self.devOverlayHost = host

            vc.addChild(host)
            let overlayContainer = vc.contentOverlayView ?? vc.view!
            overlayContainer.addSubview(host.view)
            host.view.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                host.view.topAnchor.constraint(equalTo: overlayContainer.safeAreaLayoutGuide.topAnchor, constant: 12),
                host.view.leadingAnchor.constraint(equalTo: overlayContainer.safeAreaLayoutGuide.leadingAnchor, constant: 16),
                host.view.trailingAnchor.constraint(equalTo: overlayContainer.safeAreaLayoutGuide.trailingAnchor, constant: -16)
            ])
            host.didMove(toParent: vc)
        }

        private func teardownDevOverlay() {
            if let host = devOverlayHost {
                host.willMove(toParent: nil)
                host.view.removeFromSuperview()
                host.removeFromParent()
            }
            devOverlayHost = nil
            devSession = nil
            hapticEngine.onEventFired = nil
            hapticEngine.onTimeUpdated = nil
            hapticEngine.onSeekDetected = nil
        }

        func dismiss(userInitiated: Bool) {
            savePosition()
            teardownDevOverlay()
            hapticEngine.detach()
            currentPlayer?.pause()
            currentPlayer = nil
            currentVideoID = nil

            let vc = playerVC
            playerVC = nil

            if !userInitiated {
                vc?.dismiss(animated: true)
            }
        }

        private func savePosition() {
            guard let id = currentVideoID,
                  let time = currentPlayer?.currentTime() else { return }
            let seconds = CMTimeGetSeconds(time)
            if seconds.isFinite && seconds > 0 {
                videoStore?.updatePlaybackPosition(for: id, position: seconds)
            }
        }

        func playerViewController(
            _ playerViewController: AVPlayerViewController,
            willEndFullScreenPresentationWithAnimationCoordinator coordinator: UIViewControllerTransitionCoordinator
        ) {
            coordinator.animate(alongsideTransition: { _ in
                self.dismiss(userInitiated: true)
                self.onDismiss?()
            })
        }

        private static func externalMetadata(title: String) -> [AVMetadataItem] {
            let item = AVMutableMetadataItem()
            item.identifier = .commonIdentifierTitle
            item.value = title as NSString
            item.extendedLanguageTag = "und"
            return [item.copy() as! AVMetadataItem]
        }

        private static func formatTime(_ seconds: TimeInterval) -> String {
            let hours = Int(seconds) / 3600
            let minutes = (Int(seconds) % 3600) / 60
            let secs = Int(seconds) % 60
            if hours > 0 {
                return String(format: "%d:%02d:%02d", hours, minutes, secs)
            }
            return String(format: "%d:%02d", minutes, secs)
        }

        private static func topMostViewController(from view: UIView) -> UIViewController? {
            var responder: UIResponder? = view
            while let current = responder {
                if let vc = current as? UIViewController {
                    var top = vc
                    while let presented = top.presentedViewController {
                        top = presented
                    }
                    return top
                }
                responder = current.next
            }
            guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let root = scene.windows.first(where: \.isKeyWindow)?.rootViewController else {
                return nil
            }
            var top = root
            while let presented = top.presentedViewController {
                top = presented
            }
            return top
        }
    }
}
