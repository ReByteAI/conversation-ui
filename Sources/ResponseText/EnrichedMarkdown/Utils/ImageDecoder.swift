import ImageIO
import UIKit

enum ImageDecoder {
    /// Decodes image data downsampled so its longer side is at most
    /// `maxPixelSize` (largest screen side in pixels by default), so large images never
    /// decode at full size. Never upscales.
    /// The result carries the screen scale so point-size math downstream is
    /// unchanged, and EXIF orientation is baked in.
    static func decodeDownsampled(
        _ data: Data,
        maxPixelSize: CGFloat = largestScreenSide() * largestScreenScale(),
        scale: CGFloat = largestScreenScale()
    ) -> UIImage? {
        guard !data.isEmpty else { return nil }

        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else {
            return nil
        }

        let thumbnailOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ] as CFDictionary
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions) else {
            return nil
        }

        return UIImage(cgImage: cgImage, scale: scale, orientation: .up)
    }

    /// Largest hosting screen, cached because decoding runs off the main
    /// thread. iPhone Duo has two displays and UIScreen.main may be the
    /// smaller one, so images are sized for the largest to stay sharp after
    /// unfolding. Refreshed on the main thread by `refreshScreenMetrics()`.
    private static let metricsLock = NSLock()
    nonisolated(unsafe) private static var metrics = (side: CGFloat(1024), scale: CGFloat(3))

    static func largestScreenSide() -> CGFloat {
        metricsLock.withLock { metrics.side }
    }

    static func largestScreenScale() -> CGFloat {
        metricsLock.withLock { metrics.scale }
    }

    @MainActor
    static func refreshScreenMetrics() {
        let screens = UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.screen }
        guard let side = screens.map({ max($0.bounds.width, $0.bounds.height) }).max(),
              let scale = screens.map(\.scale).max() else { return }
        metricsLock.withLock { metrics = (side, scale) }
    }
}
