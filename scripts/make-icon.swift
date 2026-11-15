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
    let rect = CGRect(x: 32, y: 32, width: 960, height: 960)
    let rounded = NSBezierPath(roundedRect: rect, xRadius: 210, yRadius: 210)
    let gradient = NSGradient(starting: NSColor(srgbRed: 1, green: 0.76, blue: 0.42, alpha: 1),
                              ending: NSColor(srgbRed: 0.94, green: 0.28, blue: 0.22, alpha: 1))!
    gradient.draw(in: rounded, angle: -60)
    let center = CGPoint(x: 512, y: 512)
    for index in 0..<6 {
        let angle = CGFloat(index) * 60
        let path = NSBezierPath()
        path.appendArc(withCenter: center, radius: 309, startAngle: angle + 6, endAngle: angle + 54)
        path.lineWidth = 134; path.lineCapStyle = .round
        NSColor.white.withAlphaComponent(0.9).setStroke(); path.stroke()
    }
    NSColor.white.setFill()
    NSBezierPath(ovalIn: CGRect(x: 415, y: 415, width: 194, height: 194)).fill()
    return rep.representation(using: .png, properties: [:])!
}
for size in [16, 32, 128, 256, 512] {
    try makeIcon(size).write(to: directory.appendingPathComponent("icon_\(size)x\(size).png"))
    try makeIcon(size * 2).write(to: directory.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}
