import AppKit

final class OrbitPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class WheelController {
    let panel: OrbitPanel
    let view: WheelView
    var automatic = false

    init() {
        panel = OrbitPanel(contentRect: NSRect(x: 0, y: 0, width: 320, height: 354),
                           styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        view = WheelView(frame: NSRect(x: 0, y: 0, width: 320, height: 354))
        let root = NSView(frame: view.frame)
        let glass = NSVisualEffectView(frame: NSRect(x: 16, y: 31, width: 288, height: 288))
        glass.material = .popover; glass.blendingMode = .behindWindow; glass.state = .active
        glass.wantsLayer = true; glass.layer?.cornerRadius = 144; glass.layer?.masksToBounds = true
        root.addSubview(glass); root.addSubview(view)
        panel.contentView = root
        view.dismiss = { [weak self] in self?.hide() }
    }

    func show(files: [URL], at point: NSPoint, automatic: Bool) {
        self.automatic = automatic
        view.files = files
        view.editing = NSEvent.modifierFlags.contains(.option)
        let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }) ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        var origin = NSPoint(x: point.x - 160, y: point.y - 177)
        origin.x = max(visible.minX, min(origin.x, visible.maxX - 320))
        origin.y = max(visible.minY, min(origin.y, visible.maxY - 354))
        panel.setFrameOrigin(origin)
        if automatic { panel.orderFrontRegardless() }
        else { NSApp.activate(ignoringOtherApps: true); panel.makeKeyAndOrderFront(nil); panel.makeFirstResponder(view) }
    }

    func hide() { panel.orderOut(nil); view.hovered = nil; automatic = false }
}

final class WheelView: NSView {
    var files: [URL] = [] { didSet { rebuild() } }
    var editing = false { didSet { if oldValue != editing { rebuild() } } }
    var hovered: Int? { didSet { needsDisplay = true } }
    var perform: ((FileAction, [URL]) -> Void)?
    var chooseFiles: (() -> Void)?
    var dismiss: (() -> Void)?
    private var tracking: NSTrackingArea?
    private var actionButtons: [NSButton] = []
    private let toggle = NSButton(title: "⇥  Convert / Tools", target: nil, action: nil)
    private let closeButton = NSButton()
    let center = CGPoint(x: 160, y: 176)
    let outer: CGFloat = 139
    let inner: CGFloat = 51
    var actions: [FileAction] { editing ? FileAction.editing : FileAction.conversions(for: files) }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
        toggle.frame = NSRect(x: 70, y: 5, width: 180, height: 24)
        toggle.bezelStyle = .rounded
        toggle.font = .systemFont(ofSize: 11, weight: .medium)
        toggle.target = self; toggle.action = #selector(toggleMode)
        addSubview(toggle)
        closeButton.frame = NSRect(x: 286, y: 326, width: 22, height: 22)
        closeButton.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Close wheel")
        closeButton.isBordered = false
        closeButton.target = self; closeButton.action = #selector(closeWheel)
        addSubview(closeButton)
        setAccessibilityLabel("OrbitDrop action wheel")
        rebuild()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var acceptsFirstResponder: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        if toggle.frame.contains(local) { return toggle }
        if closeButton.frame.contains(local) { return closeButton }
        // Keep the entire wheel as the drag destination, including its labels.
        return bounds.contains(local) ? self : nil
    }

    private func rebuild() {
        for button in actionButtons { button.removeFromSuperview() }
        actionButtons.removeAll()
        for (index, action) in actions.enumerated() {
            let angle = CGFloat(index) * 2 * .pi / CGFloat(actions.count)
            let radius: CGFloat = 94
            let position = CGPoint(x: center.x + sin(angle) * radius, y: center.y + cos(angle) * radius)
            let button = NSButton(title: action.title, target: self, action: #selector(accessibleAction(_:)))
            button.tag = index
            button.frame = CGRect(x: position.x - 38, y: position.y - 18, width: 76, height: 36)
            button.isBordered = false
            button.font = .systemFont(ofSize: actions.count > 8 ? 9 : 10, weight: .bold)
            button.contentTintColor = .labelColor
            if let symbol = action.symbol {
                button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
                button.imagePosition = .imageAbove
            }
            button.setAccessibilityLabel(action.title)
            button.setAccessibilityHelp("Action \(index + 1). Choose a file, then activate, or drop a file on this sector.")
            addSubview(button); actionButtons.append(button)
        }
        hovered = nil
        toggle.title = editing ? "⇥  Tools  ·  Switch to Convert" : "⇥  Convert  ·  Switch to Tools"
        needsDisplay = true
    }

    @objc private func accessibleAction(_ sender: NSButton) { activate(sender.tag) }
    @objc private func toggleMode() { editing.toggle() }
    @objc private func closeWheel() { dismiss?() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        tracking = NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways], owner: self)
        addTrackingArea(tracking!)
    }

    private func sector(_ point: CGPoint) -> Int? {
        WheelGeometry.sector(point: point, center: center, inner: inner, outer: outer, count: actions.count)
    }

    private func path(index: Int, count: Int) -> NSBezierPath {
        let step = 360 / CGFloat(count)
        let middle = 90 - CGFloat(index) * step
        let start = middle - step / 2 + 1.7, end = middle + step / 2 - 1.7
        let path = NSBezierPath()
        func point(_ radius: CGFloat, _ angle: CGFloat) -> CGPoint {
            CGPoint(x: center.x + cos(angle * .pi / 180) * radius,
                    y: center.y + sin(angle * .pi / 180) * radius)
        }
        path.move(to: point(inner + 5, start))
        path.line(to: point(outer - 5, start))
        path.appendArc(withCenter: center, radius: outer - 5, startAngle: start, endAngle: end)
        path.line(to: point(inner + 5, end))
        path.appendArc(withCenter: center, radius: inner + 5, startAngle: end, endAngle: start, clockwise: true)
        path.close()
        path.lineJoinStyle = .round
        path.lineWidth = 5
        return path
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        for index in actions.indices {
            let p = path(index: index, count: actions.count)
            let color = hovered == index
                ? NSColor(srgbRed: 0.95, green: 0.30, blue: 0.16, alpha: 0.95)
                : NSColor(srgbRed: 1, green: 0.79, blue: 0.59, alpha: 0.78)
            color.setFill(); color.setStroke(); p.fill(); p.stroke()
            actionButtons[index].contentTintColor = hovered == index ? .white : NSColor(srgbRed: 0.23, green: 0.16, blue: 0.12, alpha: 1)
        }
        let title = files.isEmpty ? "Drop a file" : files.count == 1 ? files[0].lastPathComponent : "\(files.count) files"
        drawText(title, rect: CGRect(x: 35, y: 326, width: 250, height: 18), size: 12, color: .labelColor)
        let centerTitle = hovered.map { actions[$0].title } ?? (editing ? "TOOLS" : "CONVERT")
        let pill = NSBezierPath(roundedRect: CGRect(x: center.x - 46, y: center.y - 15, width: 92, height: 30), xRadius: 15, yRadius: 15)
        NSColor(srgbRed: 1, green: 0.83, blue: 0.64, alpha: 0.92).setFill(); pill.fill()
        drawText(centerTitle, rect: CGRect(x: center.x - 46, y: center.y - 8, width: 92, height: 18), size: 10, color: .black)
        drawText("Hold ⌥ for tools", rect: CGRect(x: center.x - 62, y: center.y - 35, width: 124, height: 15), size: 9, color: .secondaryLabelColor)
    }

    private func drawText(_ text: String, rect: CGRect, size: CGFloat, color: NSColor) {
        let paragraph = NSMutableParagraphStyle(); paragraph.alignment = .center; paragraph.lineBreakMode = .byTruncatingMiddle
        (text as NSString).draw(in: rect, withAttributes: [.font: NSFont.systemFont(ofSize: size, weight: .semibold),
                                                         .foregroundColor: color, .paragraphStyle: paragraph])
    }

    override func mouseMoved(with event: NSEvent) { hovered = sector(convert(event.locationInWindow, from: nil)) }
    override func mouseExited(with event: NSEvent) { hovered = nil }
    override func mouseDown(with event: NSEvent) {
        if let index = sector(convert(event.locationInWindow, from: nil)) { activate(index) }
        else if files.isEmpty { chooseFiles?() }
        else { editing.toggle() }
    }
    override func rightMouseDown(with event: NSEvent) { editing.toggle() }
    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: dismiss?()
        case 48: editing.toggle()
        case 123, 126: hovered = ((hovered ?? 0) - 1 + actions.count) % actions.count
        case 124, 125: hovered = ((hovered ?? -1) + 1) % actions.count
        case 36: if let hovered { activate(hovered) }
        default:
            if let value = Int(event.charactersIgnoringModifiers ?? ""), value > 0, value <= actions.count { activate(value - 1) }
            else { super.keyDown(with: event) }
        }
    }

    private func activate(_ index: Int) {
        guard actions.indices.contains(index) else { return }
        guard !files.isEmpty else { chooseFiles?(); return }
        perform?(actions[index], files)
    }

    static func urls(_ pasteboard: NSPasteboard) -> [URL] {
        let objects = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) ?? []
        return objects.compactMap { ($0 as? NSURL).map { $0 as URL } }.filter {
            var isDirectory: ObjCBool = false
            return FileManager.default.fileExists(atPath: $0.path, isDirectory: &isDirectory) && !isDirectory.boolValue
        }
    }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let incoming = Self.urls(sender.draggingPasteboard)
        guard !incoming.isEmpty else { return [] }
        if files != incoming { files = incoming }
        return draggingUpdated(sender)
    }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        editing = NSEvent.modifierFlags.contains(.option)
        hovered = sector(convert(sender.draggingLocation, from: nil))
        return hovered == nil ? [] : .copy
    }
    override func draggingExited(_ sender: NSDraggingInfo?) { hovered = nil }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { hovered != nil }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = Self.urls(sender.draggingPasteboard)
        guard let index = sector(convert(sender.draggingLocation, from: nil)), !urls.isEmpty else { return false }
        let action = actions[index]
        DispatchQueue.main.async { [weak self] in self?.perform?(action, urls) }
        return true
    }
}
