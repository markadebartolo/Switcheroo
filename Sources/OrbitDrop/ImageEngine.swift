import AppKit
import PDFKit
import ImageIO
import UniformTypeIdentifiers
import Vision
import CoreImage

enum ImageEngine {
    static let maximumPixels = 64_000_000

    static func context(width: Int, height: Int) throws -> CGContext {
        guard width > 0, height > 0, width <= 16000, height <= 16000,
              width * height <= maximumPixels,
              let context = CGContext(data: nil, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw OrbitError.message("This image is too large. Use dimensions below 16,000 pixels and 64 megapixels.")
        }
        context.interpolationQuality = .high
        return context
    }

    static func pageCount(_ url: URL) -> Int {
        guard url.pathExtension.lowercased() == "pdf" else { return 1 }
        return PDFDocument(url: url)?.pageCount ?? 0
    }

    static func load(_ url: URL, page: Int = 0) throws -> CGImage {
        if url.pathExtension.lowercased() == "pdf" {
            guard let document = PDFDocument(url: url), !document.isLocked,
                  let pdfPage = document.page(at: page) else {
                throw OrbitError.message("Could not open this PDF. Encrypted PDFs must be unlocked first.")
            }
            let bounds = pdfPage.bounds(for: .mediaBox)
            guard bounds.width > 0, bounds.height > 0 else { throw OrbitError.message("This PDF page has no size.") }
            let scale = min(2, 8000 / max(bounds.width, bounds.height))
            let size = NSSize(width: max(1, bounds.width * scale), height: max(1, bounds.height * scale))
            let thumb = pdfPage.thumbnail(of: size, for: .mediaBox)
            var rect = CGRect(origin: .zero, size: thumb.size)
            guard let result = thumb.cgImage(forProposedRect: &rect, context: nil, hints: nil) else {
                throw OrbitError.message("Could not render this PDF page.")
            }
            return result
        }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = props[kCGImagePropertyPixelWidth] as? Int,
              let height = props[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width <= 16000, height <= 16000,
              width * height <= maximumPixels else {
            throw OrbitError.message("Use a PDF or an image under 64 megapixels. This file could not be decoded.")
        }
        // Bake EXIF orientation into pixels before editing or stripping metadata.
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(width, height),
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let result = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw OrbitError.message("macOS cannot decode this image.")
        }
        return result
    }

    static func resized(_ image: CGImage, maxEdge: Int) throws -> CGImage {
        guard max(image.width, image.height) > maxEdge else { return image }
        let factor = CGFloat(maxEdge) / CGFloat(max(image.width, image.height))
        let width = max(1, Int(CGFloat(image.width) * factor))
        let height = max(1, Int(CGFloat(image.height) * factor))
        let ctx = try context(width: width, height: height)
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()!
    }

    static func encoded(_ image: CGImage, format: String, quality: Double = 0.9) throws -> Data {
        if format == "pdf" {
            let data = NSMutableData()
            var bounds = CGRect(x: 0, y: 0, width: CGFloat(image.width), height: CGFloat(image.height))
            guard let consumer = CGDataConsumer(data: data as CFMutableData),
                  let ctx = CGContext(consumer: consumer, mediaBox: &bounds, nil) else {
                throw OrbitError.message("Could not create a PDF.")
            }
            ctx.beginPDFPage(nil)
            ctx.draw(image, in: bounds)
            ctx.endPDFPage()
            ctx.closePDF()
            return data as Data
        }
        guard let type = UTType(filenameExtension: format),
              (CGImageDestinationCopyTypeIdentifiers() as! [String]).contains(type.identifier) else {
            throw OrbitError.message("This macOS version cannot encode \(format.uppercased()).")
        }
        var output = image
        if ["jpg", "jpeg", "bmp"].contains(format) {
            let ctx = try context(width: image.width, height: image.height)
            let rect = CGRect(x: 0, y: 0, width: CGFloat(image.width), height: CGFloat(image.height))
            ctx.setFillColor(NSColor.white.cgColor)
            ctx.fill(rect)
            ctx.draw(image, in: rect)
            output = ctx.makeImage()!
        }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data as CFMutableData, type.identifier as CFString, 1, nil) else {
            throw OrbitError.message("Could not create the destination image.")
        }
        CGImageDestinationAddImage(destination, output, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw OrbitError.message("Image encoding failed.") }
        return data as Data
    }

    static func save(_ data: Data, source: URL, suffix: String, ext: String, folder: URL?) throws -> URL {
        let directory = folder ?? source.deletingLastPathComponent()
        let stem = source.deletingPathExtension().lastPathComponent + suffix
        let temporary = directory.appendingPathComponent(".orbitdrop-\(UUID().uuidString)")
        try data.write(to: temporary, options: .atomic)
        defer { try? FileManager.default.removeItem(at: temporary) }
        // Moving a temporary file never overwrites an existing destination.
        for index in 0..<10000 {
            let number = index == 0 ? "" : " \(index + 1)"
            let destination = directory.appendingPathComponent("\(stem)\(number).\(ext)")
            if FileManager.default.fileExists(atPath: destination.path) { continue }
            do {
                try FileManager.default.moveItem(at: temporary, to: destination)
                return destination
            } catch {
                if FileManager.default.fileExists(atPath: destination.path) { continue }
                throw error
            }
        }
        throw OrbitError.message("Too many files with the same name in this folder.")
    }

    static func convert(_ url: URL, format: String, folder: URL?) throws -> [URL] {
        if format == "txt" || format == "docx" {
            let text = try extractText(url)
            let data = format == "txt" ? Data(text.utf8) : DocxWriter.make(text)
            return [try save(data, source: url, suffix: "", ext: format, folder: folder)]
        }
        let count = pageCount(url)
        guard count > 0 else { throw OrbitError.message("This PDF has no readable pages.") }
        var outputs: [URL] = []
        // A failed multi-page conversion rolls back only the files it created.
        do {
            for index in 0..<count {
                let image = try load(url, page: index)
                let suffix = count == 1 ? "" : String(format: " - Page %03d", index + 1)
                outputs.append(try save(encoded(image, format: format), source: url, suffix: suffix, ext: format, folder: folder))
            }
            return outputs
        } catch {
            for output in outputs { try? FileManager.default.removeItem(at: output) }
            throw error
        }
    }

    static func recognize(_ image: CGImage) throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
    }

    static func extractText(_ url: URL) throws -> String {
        var pages: [String] = []
        if url.pathExtension.lowercased() == "pdf" {
            guard let document = PDFDocument(url: url), !document.isLocked else {
                throw OrbitError.message("Could not read this PDF.")
            }
            for index in 0..<document.pageCount {
                let embedded = document.page(at: index)?.string ?? ""
                pages.append(embedded.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                             ? try recognize(load(url, page: index)) : embedded)
            }
        } else { pages = [try recognize(load(url))] }
        let result = pages.joined(separator: "\n\n")
        guard !result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw OrbitError.message("No readable text was found in this file.")
        }
        return result
    }

    static func crop(_ image: CGImage, rect: CGRect) throws -> CGImage {
        let requested = CGRect(x: rect.minX.rounded(), y: rect.minY.rounded(),
                               width: rect.width.rounded(), height: rect.height.rounded())
        let clamped = requested.intersection(CGRect(x: 0, y: 0, width: CGFloat(image.width), height: CGFloat(image.height)))
        guard !clamped.isNull, clamped.width >= 1, clamped.height >= 1 else {
            throw OrbitError.message("Select an area to crop.")
        }
        let ctx = try context(width: Int(clamped.width), height: Int(clamped.height))
        ctx.draw(image, in: CGRect(x: -clamped.minX, y: -clamped.minY, width: CGFloat(image.width), height: CGFloat(image.height)))
        return ctx.makeImage()!
    }

    static func background(_ image: CGImage, style: BackgroundStyle) throws -> CGImage {
        let padding = max(0, style.padding)
        var width = CGFloat(image.width) + 2 * padding
        var height = CGFloat(image.height) + 2 * padding
        if style.ratio > 0 {
            if width / height < style.ratio { width = height * style.ratio }
            else { height = width / style.ratio }
        }
        let ctx = try context(width: Int(ceil(width)), height: Int(ceil(height)))
        width = CGFloat(ctx.width); height = CGFloat(ctx.height)
        let colors = BackgroundStyle.palettes[style.palette % BackgroundStyle.palettes.count]
        if colors.count == 1 {
            ctx.setFillColor(colors[0].cgColor)
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        } else {
            let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                                      colors: colors.map { $0.cgColor } as CFArray, locations: nil)!
            ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: height),
                                   end: CGPoint(x: width, y: 0), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        }
        let imageRect = CGRect(x: (width - CGFloat(image.width)) / 2,
                               y: (height - CGFloat(image.height)) / 2,
                               width: CGFloat(image.width), height: CGFloat(image.height))
        let radius = min(style.radius, min(imageRect.width, imageRect.height) / 2)
        let path = CGPath(roundedRect: imageRect, cornerWidth: radius, cornerHeight: radius, transform: nil)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -style.shadow / 3), blur: style.shadow,
                      color: NSColor.black.withAlphaComponent(0.35).cgColor)
        ctx.addPath(path); ctx.setFillColor(NSColor.white.cgColor); ctx.fillPath()
        ctx.restoreGState()
        ctx.addPath(path); ctx.clip(); ctx.draw(image, in: imageRect)
        return ctx.makeImage()!
    }

    static func adjusted(_ image: CGImage, brightness: Double, contrast: Double, saturation: Double, turns: Int) throws -> CGImage {
        let filter = CIFilter(name: "CIColorControls")!
        filter.setValue(CIImage(cgImage: image), forKey: kCIInputImageKey)
        filter.setValue(brightness, forKey: kCIInputBrightnessKey)
        filter.setValue(contrast, forKey: kCIInputContrastKey)
        filter.setValue(saturation, forKey: kCIInputSaturationKey)
        guard var output = filter.outputImage else { throw OrbitError.message("Could not adjust this image.") }
        let orientation: Int32 = [1, 6, 3, 8][((turns % 4) + 4) % 4]
        output = output.oriented(forExifOrientation: orientation)
        guard let cg = CIContext().createCGImage(output, from: output.extent) else {
            throw OrbitError.message("Could not render these adjustments.")
        }
        return cg
    }

    static func marked(_ image: CGImage, marks: [Mark], redacting: Bool) throws -> CGImage {
        let ctx = try context(width: image.width, height: image.height)
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: CGFloat(image.width), height: CGFloat(image.height)))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        defer { NSGraphicsContext.restoreGraphicsState() }
        for mark in marks {
            if redacting {
                ctx.setFillColor(NSColor.black.cgColor); ctx.fill(mark.rect)
            } else if let text = mark.text, !text.isEmpty {
                (text as NSString).draw(in: mark.rect, withAttributes: [
                    .font: NSFont.systemFont(ofSize: max(16, min(120, mark.rect.height * 0.7)), weight: .semibold),
                    .foregroundColor: mark.color
                ])
            } else {
                ctx.setStrokeColor(mark.color.cgColor)
                ctx.setLineWidth(max(3, CGFloat(image.width) / 240))
                ctx.stroke(mark.rect.insetBy(dx: 2, dy: 2))
            }
        }
        return ctx.makeImage()!
    }

    static func metadata(_ url: URL) -> String {
        var lines = [url.lastPathComponent, ""]
        if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path), let bytes = attrs[.size] as? NSNumber {
            lines.append("Size: \(ByteCountFormatter.string(fromByteCount: bytes.int64Value, countStyle: .file))")
        }
        if let source = CGImageSourceCreateWithURL(url as CFURL, nil),
           let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) {
            lines.append("\n\(properties)")
        } else if let document = PDFDocument(url: url) {
            lines.append("Pages: \(document.pageCount)")
            lines.append("\n\(document.documentAttributes ?? [:])")
        }
        return lines.joined(separator: "\n")
    }
}
