import AppKit

let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
func makeIcon(_ pixels: Int) throws -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                              bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                              isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: pixels * 4, bitsPerPixel: 32)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    defer { NSGraphicsContext.restoreGraphicsState() }
    let scale = CGFloat(pixels) / 1024
    NSGraphicsContext.current!.cgContext.scaleBy(x: scale, y: scale)
    // A dark tile with two arrows passing each other: one thing switched for another.
    let rect = CGRect(x: 64, y: 64, width: 896, height: 896)
    let rounded = NSBezierPath(roundedRect: rect, xRadius: 200, yRadius: 200)
    let gradient = NSGradient(starting: NSColor(srgbRed: 0.17, green: 0.17, blue: 0.21, alpha: 1),
                              ending: NSColor(srgbRed: 0.07, green: 0.07, blue: 0.09, alpha: 1))!
    gradient.draw(in: rounded, angle: -90)
    NSColor.white.withAlphaComponent(0.10).setStroke()
    rounded.lineWidth = 6; rounded.stroke()
    /// A thick arrow along a horizontal line, pointing right when `direction` is 1 and left when -1.
    func arrow(y: CGFloat, direction: CGFloat, color: NSColor) {
        let tail = 512 - direction * 250, head = 512 + direction * 250
        let path = NSBezierPath()
        path.move(to: CGPoint(x: tail, y: y))
        path.line(to: CGPoint(x: head, y: y))
        path.move(to: CGPoint(x: head - direction * 120, y: y + 120))
        path.line(to: CGPoint(x: head, y: y))
        path.line(to: CGPoint(x: head - direction * 120, y: y - 120))
        path.lineWidth = 78; path.lineCapStyle = .round; path.lineJoinStyle = .round
        color.setStroke(); path.stroke()
    }
    arrow(y: 640, direction: 1, color: .white)
    arrow(y: 384, direction: -1, color: NSColor(srgbRed: 0.98, green: 0.42, blue: 0.20, alpha: 1))
    return rep.representation(using: .png, properties: [:])!
}
for size in [16, 32, 128, 256, 512] {
    try makeIcon(size).write(to: directory.appendingPathComponent("icon_\(size)x\(size).png"))
    try makeIcon(size * 2).write(to: directory.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}
