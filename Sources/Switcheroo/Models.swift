import AppKit
import UniformTypeIdentifiers
import ImageIO

enum SwitcherooError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self { case .message(let value): return value }
    }
}

enum FileAction: Equatable {
    case convert(String), crop, background, compress, edit, annotate, redact, metadata

    var title: String {
        switch self {
        case .convert(let value): return value.uppercased()
        case .crop: return "CROP"
        case .background: return "ADD BG"
        case .compress: return "COMPRESS"
        case .edit: return "EDIT"
        case .annotate: return "ANNOTATE"
        case .redact: return "REDACT"
        case .metadata: return "METADATA"
        }
    }
    var symbol: String? {
        switch self {
        case .convert: return nil
        case .crop: return "crop"
        case .background: return "photo.on.rectangle.angled"
        case .compress: return "arrow.down.right.and.arrow.up.left"
        case .edit: return "slider.horizontal.3"
        case .annotate: return "pencil.tip.crop.circle"
        case .redact: return "eye.slash"
        case .metadata: return "tag"
        }
    }
    static let editing: [FileAction] = [.compress, .metadata, .edit, .annotate, .background, .crop, .redact]

    static func conversions(for urls: [URL]) -> [FileAction] {
        if !urls.isEmpty && urls.allSatisfy({ $0.pathExtension.lowercased() == "pdf" }) {
            return ["docx", "jpg", "png", "txt"].map { .convert($0) }
        }
        let types = CGImageDestinationCopyTypeIdentifiers() as! [String]
        var formats = ["png", "jpg", "heic", "tiff", "bmp", "pdf", "docx", "txt"]
        for candidate in ["webp", "avif"] {
            if let uti = UTType(filenameExtension: candidate), types.contains(uti.identifier) {
                formats.insert(candidate, at: 1)
            }
        }
        return formats.map { .convert($0) }
    }
}

enum WheelGeometry {
    // Angles advance clockwise, with index zero centered at twelve o'clock.
    static func sector(point: CGPoint, center: CGPoint, inner: CGFloat, outer: CGFloat, count: Int) -> Int? {
        guard count > 0 else { return nil }
        let dx = point.x - center.x, dy = point.y - center.y
        let distance = hypot(dx, dy)
        guard distance >= inner, distance <= outer else { return nil }
        let step = 2 * Double.pi / Double(count)
        let angle = (atan2(Double(dx), Double(dy)) + step / 2 + 2 * Double.pi)
            .truncatingRemainder(dividingBy: 2 * Double.pi)
        return min(count - 1, Int(angle / step))
    }
}

struct BackgroundStyle {
    var palette = 0
    var padding: CGFloat = 140
    var radius: CGFloat = 36
    var shadow: CGFloat = 35
    var ratio: CGFloat = 0
    static let palettes: [[NSColor]] = [
        [.init(srgbRed: 1, green: 0.24, blue: 0.37, alpha: 1), .init(srgbRed: 1, green: 0.70, blue: 0.15, alpha: 1), .init(srgbRed: 0.38, green: 0.28, blue: 0.87, alpha: 1)],
        [.init(srgbRed: 0.32, green: 0.48, blue: 0.96, alpha: 1), .init(srgbRed: 0.79, green: 0.86, blue: 1, alpha: 1)],
        [.init(srgbRed: 0.09, green: 0.69, blue: 0.61, alpha: 1), .init(srgbRed: 0.77, green: 0.95, blue: 0.67, alpha: 1)],
        [.init(srgbRed: 0.82, green: 0.56, blue: 0.97, alpha: 1), .init(srgbRed: 1, green: 0.76, blue: 0.86, alpha: 1)],
        [.white], [.init(srgbRed: 1, green: 0.76, blue: 0.17, alpha: 1)],
        [.init(srgbRed: 0.17, green: 0.62, blue: 0.46, alpha: 1)],
        [.init(srgbRed: 0.16, green: 0.23, blue: 0.39, alpha: 1)],
        [.init(srgbRed: 0.10, green: 0.12, blue: 0.16, alpha: 1)],
        [.init(srgbRed: 0.92, green: 0.89, blue: 0.85, alpha: 1)]
    ]
}

struct Mark {
    // Coordinates use the full-resolution image, origin at bottom left.
    var rect: CGRect
    var text: String?
    var color: NSColor
}

extension NSImage {
    convenience init(cg: CGImage) {
        self.init(cgImage: cg, size: NSSize(width: CGFloat(cg.width), height: CGFloat(cg.height)))
    }
}
