import AppKit

final class ImageCanvas: NSView {
    var image: CGImage { didSet { needsDisplay = true } }
    var action: FileAction
    var selection: CGRect { didSet { needsDisplay = true; changed?() } }
    var ratio: CGFloat = 0
    var marks: [Mark] = [] { didSet { needsDisplay = true; changed?() } }
    var markText: () -> String = { "" }
    var markColor: () -> NSColor = { .systemRed }
    var changed: (() -> Void)?
    private var start = CGPoint.zero
    private var initial = CGRect.zero
    private var dragging = false
    private var mode = -1
    private var pending: CGRect?

    init(image: CGImage, action: FileAction, frame: CGRect) {
        self.image = image; self.action = action
        selection = CGRect(x: 0, y: 0, width: CGFloat(image.width), height: CGFloat(image.height))
        super.init(frame: frame)
        setAccessibilityLabel("Image preview. Drag to select an area.")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var acceptsFirstResponder: Bool { true }

    var imageRect: CGRect {
        let area = bounds.insetBy(dx: 18, dy: 18)
        let scale = min(area.width / CGFloat(image.width), area.height / CGFloat(image.height))
        let size = CGSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
        return CGRect(x: area.midX - size.width / 2, y: area.midY - size.height / 2, width: size.width, height: size.height)
    }
    var fullRect: CGRect { CGRect(x: 0, y: 0, width: CGFloat(image.width), height: CGFloat(image.height)) }
    private func displayRect(_ rect: CGRect) -> CGRect {
        let display = imageRect, scale = display.width / CGFloat(image.width)
        return CGRect(x: display.minX + rect.minX * scale, y: display.minY + rect.minY * scale,
                      width: rect.width * scale, height: rect.height * scale)
    }
    private func imagePoint(_ event: NSEvent) -> CGPoint {
        let point = convert(event.locationInWindow, from: nil), display = imageRect
        let scale = CGFloat(image.width) / display.width
        return CGPoint(x: min(CGFloat(image.width), max(0, (point.x - display.minX) * scale)),
                       y: min(CGFloat(image.height), max(0, (point.y - display.minY) * scale)))
    }
    private func corners(_ rect: CGRect) -> [CGPoint] {
        [CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
         CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.maxY)]
    }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.controlBackgroundColor.withAlphaComponent(0.8).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 14, yRadius: 14).fill()
        // Checkerboard makes alpha visible.
        let display = imageRect
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: display).addClip()
        for x in stride(from: display.minX, to: display.maxX, by: 12) {
            for y in stride(from: display.minY, to: display.maxY, by: 12) {
                let odd = (Int((x - display.minX) / 12) + Int((y - display.minY) / 12)) % 2 == 0
                (odd ? NSColor(white: 0.87, alpha: 1) : NSColor(white: 0.95, alpha: 1)).setFill()
                NSBezierPath(rect: CGRect(x: x, y: y, width: 12, height: 12)).fill()
            }
        }
        NSImage(cg: image).draw(in: display)
        NSGraphicsContext.restoreGraphicsState()
        if action == .crop {
            let selected = displayRect(selection)
            let outside = NSBezierPath(rect: display); outside.appendRect(selected); outside.windingRule = .evenOdd
            NSColor.black.withAlphaComponent(0.48).setFill(); outside.fill()
            let border = NSBezierPath(rect: selected); border.lineWidth = 2
            NSColor.systemOrange.setStroke(); border.stroke()
            let grid = NSBezierPath()
            for i in 1...2 {
                let fraction = CGFloat(i) / 3
                grid.move(to: CGPoint(x: selected.minX + selected.width * fraction, y: selected.minY))
                grid.line(to: CGPoint(x: selected.minX + selected.width * fraction, y: selected.maxY))
                grid.move(to: CGPoint(x: selected.minX, y: selected.minY + selected.height * fraction))
                grid.line(to: CGPoint(x: selected.maxX, y: selected.minY + selected.height * fraction))
            }
            NSColor.white.withAlphaComponent(0.5).setStroke(); grid.lineWidth = 0.5; grid.stroke()
            for corner in corners(selected) {
                NSColor.systemOrange.setFill()
                NSBezierPath(roundedRect: CGRect(x: corner.x - 4, y: corner.y - 4, width: 8, height: 8), xRadius: 2, yRadius: 2).fill()
            }
        }
        for mark in marks { drawMark(mark) }
        if let pending { drawMark(Mark(rect: pending, text: nil, color: markColor())) }
    }
    private func drawMark(_ mark: Mark) {
        let rect = displayRect(mark.rect)
        if action == .redact { NSColor.black.setFill(); NSBezierPath(rect: rect).fill() }
        else if let text = mark.text, !text.isEmpty {
            let fontSize = max(16, min(120, mark.rect.height * 0.7)) * imageRect.width / CGFloat(image.width)
            (text as NSString).draw(in: rect, withAttributes: [.font: NSFont.systemFont(ofSize: fontSize, weight: .semibold), .foregroundColor: mark.color])
        } else {
            mark.color.setStroke(); let border = NSBezierPath(rect: rect)
            border.lineWidth = 2; border.stroke()
        }
    }
    override func mouseDown(with event: NSEvent) {
        guard [.crop, .redact, .annotate].contains(action), imageRect.contains(convert(event.locationInWindow, from: nil)) else { return }
        window?.makeFirstResponder(self)
        start = imagePoint(event); initial = selection; dragging = true; mode = -1
        if action == .crop {
            let tolerance = 12 * CGFloat(image.width) / imageRect.width
            if let corner = corners(selection).firstIndex(where: { hypot($0.x - start.x, $0.y - start.y) < tolerance }) { mode = corner }
            else if selection != fullRect && selection.contains(start) { mode = 4 }
        }
    }
    private func constrained(from anchor: CGPoint, to point: CGPoint) -> CGRect {
        var dx = point.x - anchor.x, dy = point.y - anchor.y
        if action == .crop && ratio > 0 {
            let signX: CGFloat = dx < 0 ? -1 : 1, signY: CGFloat = dy < 0 ? -1 : 1
            var width = abs(dx), height = abs(dy)
            if width / max(1, height) > ratio { height = width / ratio } else { width = height * ratio }
            let maxW = signX > 0 ? CGFloat(image.width) - anchor.x : anchor.x
            let maxH = signY > 0 ? CGFloat(image.height) - anchor.y : anchor.y
            let factor = min(1, min(maxW / max(1, width), maxH / max(1, height)))
            dx = width * factor * signX; dy = height * factor * signY
        }
        return CGRect(x: min(anchor.x, anchor.x + dx), y: min(anchor.y, anchor.y + dy), width: abs(dx), height: abs(dy)).intersection(fullRect)
    }
    override func mouseDragged(with event: NSEvent) {
        guard dragging else { return }
        let point = imagePoint(event)
        if action == .crop {
            if mode == 4 {
                selection = CGRect(x: max(0, min(CGFloat(image.width) - initial.width, initial.minX + point.x - start.x)),
                                   y: max(0, min(CGFloat(image.height) - initial.height, initial.minY + point.y - start.y)),
                                   width: initial.width, height: initial.height)
            } else {
                let anchor = mode >= 0 ? corners(initial)[(mode + 2) % 4] : start
                let rect = constrained(from: anchor, to: point)
                if rect.width >= 1 && rect.height >= 1 { selection = rect }
            }
        } else { pending = constrained(from: start, to: point); needsDisplay = true }
    }
    override func mouseUp(with event: NSEvent) {
        guard dragging else { return }
        dragging = false
        if action != .crop, let pending, pending.width >= 2, pending.height >= 2 {
            marks.append(Mark(rect: pending.integral, text: action == .annotate ? markText() : nil, color: markColor()))
        }
        pending = nil; needsDisplay = true
    }
    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "z" { undoMark() }
        else { super.keyDown(with: event) }
    }
    func undoMark() { if !marks.isEmpty { marks.removeLast() } }
    func fitRatio(_ ratio: CGFloat) {
        self.ratio = ratio
        var rect = fullRect
        if ratio > 0 {
            if rect.width / rect.height > ratio { rect.size.width = rect.height * ratio }
            else { rect.size.height = rect.width / ratio }
            rect.origin = CGPoint(x: (CGFloat(image.width) - rect.width) / 2, y: (CGFloat(image.height) - rect.height) / 2)
        }
        selection = rect
    }
}
