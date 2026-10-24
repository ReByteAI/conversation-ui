#if canImport(UIKit)
import UIKit
import MathJaxSwift
import SwiftDraw

/// Reuses the offline math engine for atomic attachments in a native document.
enum NativeMathAttachmentRenderer {
    public struct Result {
        public let image: UIImage
        public let descent: CGFloat
    }
    private static let lock = NSLock()
    private static var engine: MathJax?
    private static let cache = NSCache<NSString, Box>()
    private final class Box: NSObject {
        let value: Result
        init(_ value: Result) { self.value = value }
    }

    public static func render(_ source: String, display: Bool, fontSize: CGFloat, color: UIColor) -> Result? {
        lock.lock()
        defer { lock.unlock() }
        let key = "\(display)|\(fontSize)|\(color.cgColor.components ?? [])|\(source)" as NSString
        if let cached = cache.object(forKey: key) { return cached.value }
        if engine == nil { engine = try? MathJax(preferredOutputFormat: .svg) }
        guard let engine else { return nil }
        var error: Error?
        // Keep decimal dots literal; the upstream 3.5.0 default otherwise
        // consumes a closing brace in expressions such as x^{n-1}.
        let input = TeXInputProcessorOptions(digits: #"^(?:[0-9]+(?:{,}[0-9]{3})*(?:\.[0-9]*)?|\.[0-9]+)"#)
        input.processEscapes = true
        input.loadPackages = TeXInputProcessorOptions.Packages.all.filter {
            $0 != TeXInputProcessorOptions.Packages.noerrors && $0 != TeXInputProcessorOptions.Packages.noundefined
        }
        input.inlineMath = [["$", "$"]]
        let raw = engine.tex2svg(source, styles: false,
            conversionOptions: ConversionOptions(display: display),
            inputOptions: input, error: &error)
        guard error == nil, let svg = try? SVG(svgString: raw) else { return nil }
        let xHeight = UIFont.systemFont(ofSize: fontSize).xHeight
        let size = svg.size(for: xHeight)
        guard size.width > 0, size.height > 0, size.width * size.height < 4_000_000,
              let image = SwiftDraw.SVG(data: svg.data)?.rasterize(size: size, scale: 2) else { return nil }
        let result = Result(image: image.withTintColor(color, renderingMode: .alwaysOriginal),
            descent: max(0, -svg.geometry.verticalAlignment.toPoints(xHeight)))
        cache.countLimit = 200
        cache.totalCostLimit = 24 * 1024 * 1024
        cache.setObject(Box(result), forKey: key, cost: image.cgImage.map { $0.bytesPerRow * $0.height } ?? 0)
        return result
    }
}
#endif
