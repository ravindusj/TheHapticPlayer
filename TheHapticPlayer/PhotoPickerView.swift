import SwiftUI
import PhotosUI

struct PhotoPickerView: UIViewControllerRepresentable {
    @Environment(VideoStore.self) var videoStore
    @Environment(\.dismiss) var dismiss

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .videos
        config.selectionLimit = 1
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: PhotoPickerView

        init(_ parent: PhotoPickerView) {
            self.parent = parent
        }

        nonisolated func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            guard let provider = results.first?.itemProvider else {
                MainActor.assumeIsolated {
                    parent.dismiss()
                }
                return
            }

            if provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
                provider.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { url, error in
                    guard let url else {
                        Task { @MainActor in
                            self.parent.dismiss()
                        }
                        return
                    }

                    // Copy to a temp location since the provided URL is only valid during this callback
                    let tempURL = FileManager.default.temporaryDirectory
                        .appendingPathComponent(url.lastPathComponent)
                    try? FileManager.default.removeItem(at: tempURL)
                    try? FileManager.default.copyItem(at: url, to: tempURL)

                    let originalName = url.deletingPathExtension().lastPathComponent

                    Task { @MainActor in
                        await self.parent.videoStore.addVideo(from: tempURL, originalName: originalName)
                        try? FileManager.default.removeItem(at: tempURL)
                        self.parent.dismiss()
                    }
                }
            } else {
                MainActor.assumeIsolated {
                    parent.dismiss()
                }
            }
        }
    }
}
