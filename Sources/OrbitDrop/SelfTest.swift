import AppKit
import PDFKit
import ImageIO

enum SelfTest {
    static func run() throws {
        var checks = 0
        func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
            guard condition() else { throw OrbitError.message(message) }; checks += 1
        }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("OrbitDrop-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let ctx = try ImageEngine.context(width: 240, height: 160)
        ctx.setFillColor(NSColor.red.cgColor); ctx.fill(CGRect(x: 0, y: 0, width: 240, height: 160))
        ctx.setFillColor(NSColor.blue.cgColor); ctx.fill(CGRect(x: 0, y: 0, width: 120, height: 80))
        let sourceImage = ctx.makeImage()!
        let source = folder.appendingPathComponent("Fixture.png")
        let originalData = try ImageEngine.encoded(sourceImage, format: "png")
        try originalData.write(to: source)
        let decoded = try ImageEngine.load(source)
        try check(decoded.width == 240 && decoded.height == 160, "PNG decoding changed dimensions")
        let crop = try ImageEngine.crop(decoded, rect: CGRect(x: 0, y: 0, width: 120, height: 80))
        try check(crop.width == 120 && crop.height == 80, "Crop dimensions are incorrect")
        let sample = try ImageEngine.context(width: 1, height: 1)
        sample.draw(crop, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        let pixel = sample.data!.assumingMemoryBound(to: UInt8.self)
        try check(pixel[2] > 200 && pixel[0] < 30, "Crop vertical origin is incorrect")
        let resized = try ImageEngine.resized(decoded, maxEdge: 120)
        try check(resized.width == 120 && resized.height == 80, "Resizing changed aspect ratio")
        var style = BackgroundStyle(); style.padding = 20; style.ratio = 1
        let background = try ImageEngine.background(decoded, style: style)
        try check(background.width == 280 && background.height == 280, "Background ratio/padding is incorrect")
        let rotated = try ImageEngine.adjusted(decoded, brightness: 0, contrast: 1, saturation: 1, turns: 1)
        try check(rotated.width == 160 && rotated.height == 240, "Rotation dimensions are incorrect")
        let redacted = try ImageEngine.marked(decoded, marks: [Mark(rect: CGRect(x: 0, y: 0, width: 240, height: 160), text: nil, color: .black)], redacting: true)
        sample.draw(redacted, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        try check(pixel[0] == 0 && pixel[1] == 0 && pixel[2] == 0 && pixel[3] == 255, "Redaction did not replace pixels")
        let one = try ImageEngine.convert(source, format: "jpg", folder: folder)
        let two = try ImageEngine.convert(source, format: "jpg", folder: folder)
        try check(one[0] != two[0], "Name collision overwrote output")
        let sourceAfter = try Data(contentsOf: source)
        try check(sourceAfter == originalData, "Source file was changed")
        let pdf = PDFDocument(); pdf.insert(PDFPage(image: NSImage(cg: sourceImage))!, at: 0)
        pdf.insert(PDFPage(image: NSImage(cg: crop))!, at: 1)
        let pdfURL = folder.appendingPathComponent("Pages.pdf")
        try check(pdf.write(to: pdfURL), "PDF fixture write failed")
        let pdfBefore = try Data(contentsOf: pdfURL)
        let pages = try ImageEngine.convert(pdfURL, format: "png", folder: folder)
        try check(pages.count == 2, "Multi-page PDF did not produce all pages")
        try check(pages[0].lastPathComponent.contains("001") && pages[1].lastPathComponent.contains("002"), "PDF page names are incorrect")
        let docx = DocxWriter.make("A & B <test>\nSecond paragraph")
        let docxURL = folder.appendingPathComponent("Text.docx"); try docx.write(to: docxURL)
        let zipCheck = Process(); zipCheck.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        zipCheck.arguments = ["-t", docxURL.path]; zipCheck.standardOutput = FileHandle.nullDevice
        try zipCheck.run(); zipCheck.waitUntilExit()
        try check(zipCheck.terminationStatus == 0, "DOCX archive has invalid ZIP records")
        let text = String(data: docx, encoding: .isoLatin1) ?? ""
        try check(text.contains("&amp;") && text.contains("&lt;test&gt;"), "DOCX XML escaping failed")
        let center = CGPoint(x: 200, y: 200)
        try check(WheelGeometry.sector(point: CGPoint(x: 200, y: 320), center: center, inner: 65, outer: 180, count: 4) == 0, "Top sector is incorrect")
        try check(WheelGeometry.sector(point: CGPoint(x: 320, y: 200), center: center, inner: 65, outer: 180, count: 4) == 1, "Right sector is incorrect")
        try check(WheelGeometry.sector(point: center, center: center, inner: 65, outer: 180, count: 4) == nil, "Center must not run an action")
        try check(WheelGeometry.sector(point: CGPoint(x: 0, y: 0), center: center, inner: 65, outer: 180, count: 4) == nil, "Outside wheel must not run an action")
        // Exercise saved bytes as well as in-memory render results.
        let croppedData = try ImageEngine.encoded(crop, format: "png")
        let croppedURL = try ImageEngine.save(croppedData, source: source, suffix: " Cropped", ext: "png", folder: folder)
        let savedCrop = try ImageEngine.load(croppedURL)
        try check(savedCrop.width == 120 && savedCrop.height == 80, "Saved crop dimensions are incorrect")
        let existingData = Data("keep this output".utf8)
        let existingURL = folder.appendingPathComponent("Fixture Existing.png")
        try existingData.write(to: existingURL)
        let collisionURL = try ImageEngine.save(croppedData, source: source, suffix: " Existing", ext: "png", folder: folder)
        let preservedOutput = try Data(contentsOf: existingURL)
        try check(collisionURL != existingURL && preservedOutput == existingData,
                  "Existing output was overwritten")
        let outputPDF = PDFDocument(data: try ImageEngine.encoded(decoded, format: "pdf"))
        try check(outputPDF?.pageCount == 1 && outputPDF?.page(at: 0) != nil, "Image to PDF is invalid")
        let pdfAfter = try Data(contentsOf: pdfURL)
        try check(pdfAfter == pdfBefore, "PDF source changed during conversion")
        let firstPage = try ImageEngine.load(pages[0])
        let secondPage = try ImageEngine.load(pages[1])
        try check(firstPage.width > 0 && firstPage.height > 0 && secondPage.width > 0 && secondPage.height > 0,
                  "Converted PDF pages cannot be decoded")
        for quarterTurns in 0..<4 {
            let frame = try ImageEngine.adjusted(decoded, brightness: 0, contrast: 1, saturation: 1, turns: quarterTurns)
            let expected = quarterTurns.isMultiple(of: 2) ? (240, 160) : (160, 240)
            try check(frame.width == expected.0 && frame.height == expected.1,
                      "Rotation \(quarterTurns * 90)° has wrong dimensions")
        }
        var wideStyle = BackgroundStyle(); wideStyle.padding = 20; wideStyle.ratio = 16.0 / 9.0
        let wideBG = try ImageEngine.background(decoded, style: wideStyle)
        try check(abs(Double(wideBG.width) / Double(wideBG.height) - 16.0 / 9.0) < 0.01,
                  "16:9 background ratio is incorrect")
        var fourThreeStyle = BackgroundStyle(); fourThreeStyle.padding = 20; fourThreeStyle.ratio = 4.0 / 3.0
        let fourThreeBG = try ImageEngine.background(decoded, style: fourThreeStyle)
        try check(abs(Double(fourThreeBG.width) / Double(fourThreeBG.height) - 4.0 / 3.0) < 0.01,
                  "4:3 background ratio is incorrect")
        let alphaContext = try ImageEngine.context(width: 4, height: 4)
        let transparentImage = alphaContext.makeImage()!
        let jpegURL = folder.appendingPathComponent("Transparent.jpg")
        try ImageEngine.encoded(transparentImage, format: "jpg").write(to: jpegURL)
        let jpeg = try ImageEngine.load(jpegURL)
        let jpegSample = try ImageEngine.context(width: 1, height: 1)
        jpegSample.draw(jpeg, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        let white = jpegSample.data!.assumingMemoryBound(to: UInt8.self)
        try check(white[0] > 240 && white[1] > 240 && white[2] > 240,
                  "Transparent JPEG background is not white")
        let archiveBase = folder.appendingPathComponent("OrbitDrop history", isDirectory: true)
        let session = try OutputStore.makeSession(sources: [source], base: archiveBase)
        let beforeURL = session.before.appendingPathComponent(source.lastPathComponent)
        let beforeData = try Data(contentsOf: beforeURL)
        try check(beforeData == originalData, "Before copy differs from source")
        let afterURL = try ImageEngine.save(croppedData, source: source, suffix: " Cropped", ext: "png", folder: session.after)
        try check(afterURL.deletingLastPathComponent() == session.after && FileManager.default.fileExists(atPath: afterURL.path),
                  "After copy was not stored in the timestamped session")
        try check(session.root.lastPathComponent.count >= 20, "History folder is not timestamped")
        let finalSource = try Data(contentsOf: source)
        try check(finalSource == originalData, "Source changed after all checks")
        print("OrbitDrop: \(checks) checks passed.")
    }
}
