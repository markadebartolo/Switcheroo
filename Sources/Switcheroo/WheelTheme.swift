import AppKit

/// The color of the wheel. One color is chosen in Settings; the resting sectors, the highlighted sector
/// and the label in the middle are all drawn from it, so any choice stays readable.
enum WheelTheme {
    static let changed = Notification.Name("WheelThemeChanged")
    private static let key = "wheelColor"
    static let standard = NSColor(srgbRed: 0.95, green: 0.30, blue: 0.16, alpha: 1)
    static let presets: [(name: String, color: NSColor)] = [
        ("Ember", standard),
        ("Sun", NSColor(srgbRed: 0.96, green: 0.68, blue: 0.10, alpha: 1)),
        ("Mint", NSColor(srgbRed: 0.13, green: 0.68, blue: 0.48, alpha: 1)),
        ("Sky", NSColor(srgbRed: 0.16, green: 0.52, blue: 0.96, alpha: 1)),
        ("Violet", NSColor(srgbRed: 0.52, green: 0.36, blue: 0.94, alpha: 1)),
        ("Rose", NSColor(srgbRed: 0.93, green: 0.27, blue: 0.53, alpha: 1)),
        ("Graphite", NSColor(srgbRed: 0.32, green: 0.34, blue: 0.38, alpha: 1)),
    ]

    static var accent: NSColor {
        get {
            guard let parts = UserDefaults.standard.array(forKey: key) as? [Double], parts.count == 3 else { return standard }
            return NSColor(srgbRed: parts[0], green: parts[1], blue: parts[2], alpha: 1)
        }
        set {
            let c = newValue.usingColorSpace(.sRGB) ?? standard
            UserDefaults.standard.set([Double(c.redComponent), Double(c.greenComponent), Double(c.blueComponent)], forKey: key)
            NotificationCenter.default.post(name: changed, object: nil)
        }
    }
    static func reset() {
        UserDefaults.standard.removeObject(forKey: key)
        NotificationCenter.default.post(name: changed, object: nil)
    }

    /// The sector under the pointer.
    static var highlighted: NSColor { accent.withAlphaComponent(0.95) }
    /// Every other sector: the same color, let down with white.
    static var resting: NSColor { tint(0.62).withAlphaComponent(0.78) }
    /// The label in the middle of the wheel.
    static var pill: NSColor { tint(0.55).withAlphaComponent(0.92) }
    static var iconOnHighlighted: NSColor { readable(on: accent) }
    static var iconOnResting: NSColor { readable(on: tint(0.62)) }
    static var textOnPill: NSColor { readable(on: tint(0.55)) }

    private static func tint(_ white: CGFloat) -> NSColor {
        accent.blended(withFraction: white, of: .white) ?? accent
    }
    /// Near-black or white, whichever stands out more against `color`.
    private static func readable(on color: NSColor) -> NSColor {
        let c = color.usingColorSpace(.sRGB) ?? color
        func linear(_ v: CGFloat) -> CGFloat { v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        let luminance = 0.2126 * linear(c.redComponent) + 0.7152 * linear(c.greenComponent) + 0.0722 * linear(c.blueComponent)
        return luminance > 0.36 ? NSColor(srgbRed: 0.12, green: 0.10, blue: 0.10, alpha: 1) : .white
    }
}

/// The Settings window: the wheel's color, as a row of ready-made colors and a well for any other.
final class SettingsController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let well = NSColorWell()
    private let preview = WheelSwatch()

    func show() {
        if window == nil { build() }
        well.color = WheelTheme.accent
        preview.needsDisplay = true
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    private func build() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 250), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Switcheroo Settings"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()

        let heading = NSTextField(labelWithString: "Wheel color")
        heading.font = .systemFont(ofSize: 13, weight: .semibold)
        let note = NSTextField(wrappingLabelWithString: "Pick a color for the action wheel. The lighter sectors and the label in the middle follow it.")
        note.font = .systemFont(ofSize: 11); note.textColor = .secondaryLabelColor

        let swatches = NSStackView(); swatches.orientation = .horizontal; swatches.spacing = 8
        for (index, preset) in WheelTheme.presets.enumerated() {
            let button = NSButton(title: "", target: self, action: #selector(pick(_:)))
            button.tag = index; button.isBordered = false; button.wantsLayer = true
            button.layer?.backgroundColor = preset.color.cgColor
            button.layer?.cornerRadius = 14
            button.layer?.borderWidth = 1; button.layer?.borderColor = NSColor.separatorColor.cgColor
            button.toolTip = preset.name
            button.setAccessibilityLabel("\(preset.name) wheel color")
            button.widthAnchor.constraint(equalToConstant: 28).isActive = true
            button.heightAnchor.constraint(equalToConstant: 28).isActive = true
            swatches.addArrangedSubview(button)
        }

        well.target = self; well.action = #selector(custom(_:))
        well.setAccessibilityLabel("Custom wheel color")
        well.widthAnchor.constraint(equalToConstant: 44).isActive = true
        well.heightAnchor.constraint(equalToConstant: 28).isActive = true
        let customLabel = NSTextField(labelWithString: "Custom")
        customLabel.font = .systemFont(ofSize: 12)
        let reset = NSButton(title: "Use the standard color", target: self, action: #selector(restore))
        reset.bezelStyle = .rounded
        let customRow = NSStackView(views: [customLabel, well, NSView(), reset]); customRow.orientation = .horizontal; customRow.spacing = 8

        preview.widthAnchor.constraint(equalToConstant: 84).isActive = true
        preview.heightAnchor.constraint(equalToConstant: 84).isActive = true
        let left = NSStackView(views: [heading, note, swatches, customRow]); left.orientation = .vertical; left.alignment = .leading; left.spacing = 12
        let row = NSStackView(views: [left, preview]); row.orientation = .horizontal; row.alignment = .top; row.spacing = 18
        row.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        row.translatesAutoresizingMaskIntoConstraints = false
        let content = NSView(); content.addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: content.leadingAnchor), row.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            row.topAnchor.constraint(equalTo: content.topAnchor), row.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            customRow.widthAnchor.constraint(equalTo: left.widthAnchor),
        ])
        window.contentView = content
        self.window = window
    }

    @objc private func pick(_ sender: NSButton) { apply(WheelTheme.presets[sender.tag].color) }
    @objc private func custom(_ sender: NSColorWell) { apply(sender.color) }
    @objc private func restore() { WheelTheme.reset(); well.color = WheelTheme.accent; preview.needsDisplay = true }
    private func apply(_ color: NSColor) { WheelTheme.accent = color; well.color = WheelTheme.accent; preview.needsDisplay = true }
    func windowWillClose(_ notification: Notification) { NSColorPanel.shared.close() }
}

/// A small picture of the wheel in the chosen color.
private final class WheelSwatch: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let radius = min(bounds.width, bounds.height) / 2 - 10
        for index in 0..<6 {
            let start = CGFloat(index) * 60 + 5
            let path = NSBezierPath()
            path.appendArc(withCenter: center, radius: radius, startAngle: start, endAngle: start + 50)
            path.lineWidth = 15; path.lineCapStyle = .round
            (index == 1 ? WheelTheme.highlighted : WheelTheme.resting).setStroke()
            path.stroke()
        }
        WheelTheme.pill.setFill()
        NSBezierPath(ovalIn: CGRect(x: center.x - 9, y: center.y - 9, width: 18, height: 18)).fill()
    }
}
