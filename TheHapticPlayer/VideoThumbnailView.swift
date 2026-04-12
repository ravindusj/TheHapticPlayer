import SwiftUI
import AVFoundation

struct VideoThumbnailView: View {
    let url: URL
    @State private var thumbnail: UIImage?

    var body: some View {
        Group {
            if let thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Color(.tertiarySystemFill)
                    .overlay {
                        Image(systemName: "film")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
            }
        }
        .frame(width: 80, height: 50)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .task(id: url) {
            guard thumbnail == nil else { return }
            thumbnail = await generateThumbnail(url: url)
        }
    }

    private func generateThumbnail(url: URL) async -> UIImage? {
        let asset = AVAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 160, height: 100)

        let time = CMTime(seconds: 1, preferredTimescale: 600)
        return try? await withCheckedThrowingContinuation { continuation in
            generator.generateCGImageAsynchronously(for: time) { cgImage, _, error in
                if let cgImage {
                    continuation.resume(returning: UIImage(cgImage: cgImage))
                } else {
                    continuation.resume(throwing: error ?? NSError(domain: "thumbnail", code: -1))
                }
            }
        }
    }
}
