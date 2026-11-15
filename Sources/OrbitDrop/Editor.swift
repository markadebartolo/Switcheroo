import AppKit
import QuartzCore

final class EditorController: NSWindowController, NSWindowDelegate {
    let source: URL
    let action: FileAction
    var original: CGImage
    let folder: URL?
    let canvas: ImageCanvas
    var onSaved: ((URL) -> Void)?
    var onClose: (() -> Void)?
    private var body: NSView
    private let info = NSTextField(labelWithString: "")
    private let instruction = NSTextField(wrappingLabelWithString: "")
    private let saveButton = NSButton(title: "Save copy", target: nil, action: nil)
    private let widthField = NSTextField(), heightField = NSTextField()
    private let textField = NSTextField()
    private let colorWell = NSColorWell()
    private var sliders: [String: NSSlider] = [:]
    private var values: [String: NSTextField] = [:]
    private var style = BackgroundStyle()
    private var turns = 0
    private var page = 0
    private var preview: CGImage
    private var ratioControl: NSSegmentedControl?

    init(source: URL, action: FileAction, image: CGImage, folder: URL?) throws {
        self.source = source; self.action = action; original = image; self.folder = folder
        preview = try ImageEngine.resized(image, maxEdge: 1000)
        canvas = ImageCanvas(image: image, action: action, frame: NSRect(x: 22, y: 255, width: 516, height: 430))
        body = NSView(frame: NSRect(x: 0, y: 0, width: 560, height: 744))
        let window = NSWindow(contentRect: body.bounds, styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "\(action.title.capitalized) — OrbitDrop"
        window.isReleasedWhenClosed = false
        window.contentView = body
        super.init(window: window)
        window.delegate = self
        let glass = NSVisualEffectView(frame: body.bounds)
        glass.material = .underWindowBackground; glass.blendingMode = .behindWindow; glass.state = .active
        body.addSubview(glass)
        body.addSubview(canvas)
        let name = NSTextField(labelWithString: source.lastPathComponent)
        name.frame = NSRect(x: 24, y: 706, width: 360, height: 21)
        name.font = .systemFont(ofSize: 13, weight: .semibold)
        name.lineBreakMode = .byTruncatingMiddle
        body.addSubview(name)
        let pageCount = ImageEngine.pageCount(source)
        if source.pathExtension.lowercased() == "pdf" {
            let pages = NSPopUpButton(frame: NSRect(x: 400, y: 702, width: 138, height: 28))
            pages.addItems(withTitles: (1...max(1, pageCount)).map { "Page \($0) of \(pageCount)" })
            pages.target = self; pages.action = #selector(pageChanged(_:)); body.addSubview(pages)
        }
        info.frame = NSRect(x: 24, y: 227, width: 512, height: 20)
        info.textColor = .secondaryLabelColor; info.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        body.addSubview(info)
        instruction.frame = NSRect(x: 24, y: 55, width: 512, height: 36)
        instruction.textColor = .secondaryLabelColor; instruction.font = .systemFont(ofSize: 11)
        body.addSubview(instruction)
        let reset = button("Reset", x: 24, y: 18, width: 75, selector: #selector(resetEditor))
        reset.keyEquivalent = "r"; reset.keyEquivalentModifierMask = [.command]
        saveButton.frame = NSRect(x: 345, y: 18, width: 191, height: 30)
        saveButton.bezelStyle = .rounded; saveButton.bezelColor = .systemOrange
        saveButton.keyEquivalent = "\r"; saveButton.target = self; saveButton.action = #selector(save)
        body.addSubview(saveButton)
        configure()
        canvas.changed = { [weak self] in self?.updateInfo() }
        updateInfo()
        window.center()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func windowWillClose(_ notification: Notification) { onClose?() }

    @discardableResult private func button(_ title: String, x: CGFloat, y: CGFloat, width: CGFloat, selector: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: selector)
        button.frame = CGRect(x: x, y: y, width: width, height: 28); button.bezelStyle = .rounded
        body.addSubview(button); return button
    }
    private func label(_ title: String, x: CGFloat = 24, y: CGFloat, width: CGFloat = 92) {
        let label = NSTextField(labelWithString: title)
        label.frame = CGRect(x: x, y: y, width: width, height: 19)
        label.font = .systemFont(ofSize: 12); body.addSubview(label)
    }
    private func slider(_ key: String, title: String, y: CGFloat, value: Double, min: Double, max: Double) {
        label(title, y: y + 3)
        let slider = NSSlider(value: value, minValue: min, maxValue: max, target: self, action: #selector(controlsChanged))
        slider.frame = CGRect(x: 120, y: y, width: 326, height: 24); slider.isContinuous = true
        slider.setAccessibilityLabel(title)
        body.addSubview(slider); sliders[key] = slider
        let output = NSTextField(labelWithString: "")
        output.frame = CGRect(x: 453, y: y + 3, width: 82, height: 19)
        output.alignment = .right; output.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        body.addSubview(output); values[key] = output
    }
    private func ratios(y: CGFloat, background: Bool) {
        label("Aspect ratio", y: y + 4)
        let titles = background ? ["Auto", "1:1", "16:9", "4:3"] : ["Free", "1:1", "16:9", "9:16", "4:3", "3:4"]
        let control = NSSegmentedControl(labels: titles, trackingMode: .selectOne, target: self, action: #selector(ratioChanged(_:)))
        control.frame = CGRect(x: 120, y: y, width: 414, height: 27); control.selectedSegment = 0
        body.addSubview(control); ratioControl = control
    }
    private func configure() {
        switch action {
        case .crop:
            ratios(y: 185, background: false)
            label("Width", y: 143); label("Height", x: 288, y: 143)
            widthField.frame = CGRect(x: 120, y: 139, width: 138, height: 26)
            heightField.frame = CGRect(x: 370, y: 139, width: 164, height: 26)
            for field in [widthField, heightField] {
                field.target = self; field.action = #selector(dimensionsChanged(_:)); body.addSubview(field)
            }
            instruction.stringValue = "Drag across the image to crop. Move the selection or drag a corner to resize. Dimensions are in pixels."
            saveButton.title = "Save cropped PNG"
        case .background:
            label("Background", y: 199)
            for index in BackgroundStyle.palettes.indices {
                let swatch = NSButton(frame: CGRect(x: 120 + CGFloat(index) * 41, y: 191, width: 34, height: 30))
                swatch.tag = index; swatch.title = ""; swatch.isBordered = false
                swatch.wantsLayer = true; swatch.layer?.cornerRadius = 7
                swatch.layer?.backgroundColor = BackgroundStyle.palettes[index][0].cgColor
                if BackgroundStyle.palettes[index].count > 1 {
                    let gradient = CAGradientLayer(); gradient.frame = swatch.bounds
                    gradient.colors = BackgroundStyle.palettes[index].map { $0.cgColor }; gradient.cornerRadius = 7
                    gradient.startPoint = CGPoint(x: 0, y: 0); gradient.endPoint = CGPoint(x: 1, y: 1)
                    swatch.layer?.addSublayer(gradient)
                }
                swatch.target = self; swatch.action = #selector(paletteChanged(_:))
                swatch.setAccessibilityLabel("Background \(index + 1)"); body.addSubview(swatch)
            }
            slider("padding", title: "Padding", y: 161, value: 140, min: 0, max: 1000)
            slider("radius", title: "Corners", y: 134, value: 36, min: 0, max: 250)
            slider("shadow", title: "Shadow", y: 107, value: 35, min: 0, max: 180)
            ratios(y: 76, background: true)
            instruction.stringValue = ""; saveButton.title = "Save with background"
            controlsChanged()
        case .compress:
            slider("quality", title: "JPEG quality", y: 182, value: 80, min: 10, max: 100)
            slider("edge", title: "Max edge", y: 142, value: Double(min(2400, max(original.width, original.height))), min: 320, max: 8000)
            instruction.stringValue = "Saves a JPEG copy. Transparency becomes white. Smaller dimensions and lower quality usually reduce file size."
            saveButton.title = "Save compressed JPG"
            controlsChanged()
        case .edit:
            slider("brightness", title: "Brightness", y: 190, value: 0, min: -0.5, max: 0.5)
            slider("contrast", title: "Contrast", y: 155, value: 1, min: 0.5, max: 2)
            slider("saturation", title: "Saturation", y: 120, value: 1, min: 0, max: 2)
            button("Rotate 90°", x: 120, y: 85, width: 125, selector: #selector(rotateImageClockwise))
            instruction.stringValue = "Adjustments are applied to a new PNG copy."
            saveButton.title = "Save edited PNG"; controlsChanged()
        case .annotate:
            label("Text", y: 185)
            textField.frame = CGRect(x: 120, y: 179, width: 414, height: 28)
            textField.placeholderString = "Leave blank to draw a rectangle"; body.addSubview(textField)
            label("Color", y: 141)
            colorWell.frame = CGRect(x: 120, y: 133, width: 66, height: 30); colorWell.color = .systemRed
            body.addSubview(colorWell)
            button("Undo last", x: 212, y: 133, width: 112, selector: #selector(undoMark))
            canvas.markText = { [weak self] in self?.textField.stringValue ?? "" }
            canvas.markColor = { [weak self] in self?.colorWell.color ?? .systemRed }
            instruction.stringValue = "Enter text, then drag a box to place it. Leave text blank to outline an area. ⌘Z removes the last annotation."
            saveButton.title = "Save annotated PNG"
        case .redact:
            label("Cover sensitive content", y: 184, width: 400)
            button("Undo last", x: 120, y: 138, width: 112, selector: #selector(undoMark))
            instruction.stringValue = "Drag over each area to replace its pixels with solid black. Exports only the visible page as a flattened PNG, without source metadata."
            saveButton.title = "Save redacted PNG"
        default: break
        }
    }
    private func updateInfo() {
        if action == .crop {
            widthField.integerValue = Int(canvas.selection.width.rounded())
            heightField.integerValue = Int(canvas.selection.height.rounded())
            info.stringValue = "\(original.width) × \(original.height) px   →   \(widthField.integerValue) × \(heightField.integerValue) px"
        } else {
            info.stringValue = "\(original.width) × \(original.height) px" + (canvas.marks.isEmpty ? "" : "   ·   \(canvas.marks.count) mark(s)")
        }
        if source.pathExtension.lowercased() == "pdf" { info.stringValue += "   ·   Exports page \(page + 1) only" }
    }
    @objc private func dimensionsChanged(_ sender: NSTextField) {
        var width = CGFloat(max(1, min(widthField.integerValue, original.width)))
        var height = CGFloat(max(1, min(heightField.integerValue, original.height)))
        if canvas.ratio > 0 {
            if sender === widthField { height = width / canvas.ratio } else { width = height * canvas.ratio }
            let factor = min(1, min(CGFloat(original.width) / width, CGFloat(original.height) / height))
            width *= factor; height *= factor
        }
        canvas.selection = CGRect(x: max(0, min(CGFloat(original.width) - width, canvas.selection.midX - width / 2)),
                                  y: max(0, min(CGFloat(original.height) - height, canvas.selection.midY - height / 2)),
                                  width: width, height: height)
    }
    @objc private func ratioChanged(_ sender: NSSegmentedControl) {
        let wide = CGFloat(16) / CGFloat(9)
        let portrait = CGFloat(9) / CGFloat(16)
        let landscape = CGFloat(4) / CGFloat(3)
        let tall = CGFloat(3) / CGFloat(4)
        let ratios: [CGFloat]
        if action == .background {
            ratios = [0, 1, wide, landscape]
        } else {
            ratios = [0, 1, wide, portrait, landscape, tall]
        }
        let index = sender.selectedSegment
        guard ratios.indices.contains(index) else { return }
        if action == .background { style.ratio = ratios[index]; renderPreview() }
        else { canvas.fitRatio(ratios[index]) }
    }
    @objc private func paletteChanged(_ sender: NSButton) { style.palette = sender.tag; renderPreview() }
    @objc private func controlsChanged() {
        for (key, slider) in sliders {
            let value = slider.doubleValue
            values[key]?.stringValue = ["brightness", "contrast", "saturation"].contains(key)
                ? String(format: "%.2f", value) : "\(Int(value))\(key == "quality" ? "%" : " px")"
        }
        style.padding = CGFloat(sliders["padding"]?.doubleValue ?? 140)
        style.radius = CGFloat(sliders["radius"]?.doubleValue ?? 36)
        style.shadow = CGFloat(sliders["shadow"]?.doubleValue ?? 35)
        renderPreview()
    }
    private func renderPreview() {
        do {
            if action == .background {
                var scaled = style
                let factor = CGFloat(preview.width) / CGFloat(original.width)
                scaled.padding *= factor; scaled.radius *= factor; scaled.shadow *= factor
                canvas.image = try ImageEngine.background(preview, style: scaled)
            } else if action == .edit {
                canvas.image = try ImageEngine.adjusted(preview, brightness: sliders["brightness"]?.doubleValue ?? 0,
                                                        contrast: sliders["contrast"]?.doubleValue ?? 1,
                                                        saturation: sliders["saturation"]?.doubleValue ?? 1, turns: turns)
            }
        } catch { info.stringValue = error.localizedDescription }
    }
    @objc private func rotateImageClockwise() { turns = (turns + 1) % 4; renderPreview() }
    @objc private func undoMark() { canvas.undoMark() }
    @objc private func pageChanged(_ sender: NSPopUpButton) {
        do {
            original = try ImageEngine.load(source, page: sender.indexOfSelectedItem)
            preview = try ImageEngine.resized(original, maxEdge: 1000)
            page = sender.indexOfSelectedItem; resetEditor()
        } catch {
            sender.selectItem(at: page); present(error)
        }
    }
    @objc private func resetEditor() {
        canvas.image = original; canvas.marks = []; canvas.fitRatio(0)
        turns = 0; style = BackgroundStyle(); ratioControl?.selectedSegment = 0
        let defaults: [String: Double] = ["padding": 140, "radius": 36, "shadow": 35,
                                         "quality": 80, "edge": Double(min(2400, max(original.width, original.height))),
                                         "brightness": 0, "contrast": 1, "saturation": 1]
        for (key, slider) in sliders { slider.doubleValue = defaults[key] ?? 0 }
        controlsChanged(); updateInfo()
    }
    @objc private func save() {
        // Commit edits in width/height fields before taking the render snapshot.
        let heightWasEditing = heightField.currentEditor() != nil
        window?.makeFirstResponder(nil)
        if action == .crop { dimensionsChanged(heightWasEditing ? heightField : widthField) }
        let image = original, selection = canvas.selection, marks = canvas.marks, style = self.style, turns = self.turns
        let quality = (sliders["quality"]?.doubleValue ?? 90) / 100
        let edge = Int(sliders["edge"]?.doubleValue ?? 2400)
        let brightness = sliders["brightness"]?.doubleValue ?? 0
        let contrast = sliders["contrast"]?.doubleValue ?? 1
        let saturation = sliders["saturation"]?.doubleValue ?? 1
        let pageSuffix = source.pathExtension.lowercased() == "pdf" ? " - Page \(page + 1)" : ""
        saveButton.isEnabled = false; info.stringValue = "Saving…"
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            do {
                let result: CGImage
                let suffix: String, ext: String
                switch action {
                case .crop: result = try ImageEngine.crop(image, rect: selection); suffix = " Cropped"; ext = "png"
                case .background: result = try ImageEngine.background(image, style: style); suffix = " Background"; ext = "png"
                case .compress: result = try ImageEngine.resized(image, maxEdge: edge); suffix = " Compressed"; ext = "jpg"
                case .edit: result = try ImageEngine.adjusted(image, brightness: brightness, contrast: contrast, saturation: saturation, turns: turns); suffix = " Edited"; ext = "png"
                case .annotate, .redact:
                    result = try ImageEngine.marked(image, marks: marks, redacting: action == .redact)
                    suffix = action == .redact ? " Redacted" : " Annotated"; ext = "png"
                default: throw OrbitError.message("Unsupported editor action.")
                }
                let data = try ImageEngine.encoded(result, format: ext, quality: quality)
                let session = try OutputStore.makeSession(sources: [source], base: folder)
                let output: URL
                do {
                    output = try ImageEngine.save(data, source: source, suffix: pageSuffix + suffix, ext: ext, folder: session.after)
                } catch {
                    try? FileManager.default.removeItem(at: session.root)
                    throw error
                }
                DispatchQueue.main.async { [self] in onSaved?(output); close() }
            } catch { DispatchQueue.main.async { [self] in saveButton.isEnabled = true; updateInfo(); present(error) } }
        }
    }
    private func present(_ error: Error) {
        let alert = NSAlert(error: error)
        if let window { alert.beginSheetModal(for: window) } else { alert.runModal() }
    }
}
