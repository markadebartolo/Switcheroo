import AppKit
import UniformTypeIdentifiers

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let wheel = WheelController()
    private var editors: [UUID: EditorController] = [:]
    private var dragMonitor: Any?
    private var timer: Timer?
    private var recentDrag: TimeInterval = 0
    private var seenDragCount = NSPasteboard(name: .drag).changeCount
    private var releasedAt: TimeInterval?
    private var working = false
    private var selected: [URL] = []
    private var lastOutputs: [URL] = []
    private var progressPanel: NSPanel?
    private var welcome: NSWindow?
    private var automatic: Bool {
        get { return (UserDefaults.standard.object(forKey: "automaticDragOptIn") as? Bool) ?? false }
        set { UserDefaults.standard.set(newValue, forKey: "automaticDragOptIn") }
    }
    private var folder: URL? {
        get { UserDefaults.standard.string(forKey: "outputFolder").map { URL(fileURLWithPath: $0, isDirectory: true) } }
        set { UserDefaults.standard.set(newValue?.path, forKey: "outputFolder") }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        createMainMenu()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "circle.hexagongrid.fill", accessibilityDescription: "Switcheroo")
        statusItem.button?.toolTip = "Switcheroo — file actions at your cursor"
        let menu = NSMenu(); menu.delegate = self; menu.autoenablesItems = false; statusItem.menu = menu
        wheel.view.chooseFiles = { [weak self] in self?.chooseFiles() }
        wheel.view.perform = { [weak self] action, files in self?.perform(action, files: files) }
        dragMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDragged]) { [weak self] _ in
            self?.recentDrag = Date.timeIntervalSinceReferenceDate
        }
        let timer = Timer(timeInterval: 0.08, repeats: true) { [weak self] _ in self?.checkDrag() }
        RunLoop.main.add(timer, forMode: .common); self.timer = timer
        if !UserDefaults.standard.bool(forKey: "hasLaunched") {
            UserDefaults.standard.set(true, forKey: "hasLaunched"); showWelcome()
        }
    }
    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
        if let dragMonitor { NSEvent.removeMonitor(dragMonitor) }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showWheel(); return true }
    func application(_ application: NSApplication, open urls: [URL]) {
        selected = urls.filter { $0.isFileURL }; showWheel()
    }
    private func createMainMenu() {
        let main = NSMenu()
        let app = NSMenuItem(); main.addItem(app); app.submenu = NSMenu(title: "Switcheroo")
        let quit = NSMenuItem(title: "Quit Switcheroo", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        app.submenu?.addItem(quit)
        let edit = NSMenuItem(title: "Edit", action: nil, keyEquivalent: ""); main.addItem(edit)
        edit.submenu = NSMenu(title: "Edit")
        for (title, key, action) in [("Cut", "x", "cut:"), ("Copy", "c", "copy:"), ("Paste", "v", "paste:"), ("Select All", "a", "selectAll:")] {
            edit.submenu?.addItem(NSMenuItem(title: title, action: Selector(action), keyEquivalent: key))
        }
        NSApp.mainMenu = main
    }
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        func add(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key); item.target = self
            menu.addItem(item); return item
        }
        _ = add("Show action wheel", #selector(showWheel), key: "d")
        _ = add("Choose files…", #selector(chooseFiles), key: "o")
        menu.addItem(.separator())
        let auto = add("Show wheel while dragging files", #selector(toggleAutomatic)); auto.state = automatic ? .on : .off
        let outputMenu = NSMenu(title: "History folder")
        let item = NSMenuItem(title: "History folder", action: nil, keyEquivalent: ""); item.submenu = outputMenu; menu.addItem(item)
        let alongside = NSMenuItem(title: "Documents/Switcheroo", action: #selector(useDefaultFolder), keyEquivalent: "")
        alongside.target = self; alongside.state = folder == nil ? .on : .off; outputMenu.addItem(alongside)
        let custom = NSMenuItem(title: folder.map { "Choose folder… (\($0.lastPathComponent))" } ?? "Choose folder…", action: #selector(chooseFolder), keyEquivalent: "")
        custom.target = self; custom.state = folder == nil ? .off : .on; outputMenu.addItem(custom)
        let recent = add("Reveal last saved files", #selector(revealLast)); recent.isEnabled = !lastOutputs.isEmpty
        menu.addItem(.separator())
        _ = add("How to use Switcheroo", #selector(showWelcome))
        _ = add("Quit Switcheroo", #selector(quit), key: "q")
    }
    @objc private func quit() { NSApp.terminate(nil) }
    @objc private func toggleAutomatic() { automatic.toggle(); if !automatic { wheel.hide() } }
    @objc private func useDefaultFolder() { folder = nil }
    @objc private func chooseFolder() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false
        panel.prompt = "Save copies here"; panel.canCreateDirectories = true
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK { folder = panel.url }
    }
    @objc private func revealLast() { NSWorkspace.shared.activateFileViewerSelecting(lastOutputs) }
    @objc func showWheel() {
        guard !working else { progressPanel?.makeKeyAndOrderFront(nil); return }
        wheel.show(files: selected, at: NSEvent.mouseLocation, automatic: false)
    }
    @objc func chooseFiles() {
        guard !working else { return }
        wheel.hide()
        let panel = NSOpenPanel(); panel.allowsMultipleSelection = true; panel.canChooseDirectories = false
        panel.allowedContentTypes = [.image, .pdf]; panel.prompt = "Choose"
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK { selected = panel.urls; showWheel() }
    }
    private func checkDrag() {
        let now = Date.timeIntervalSinceReferenceDate
        let mouseDown = NSEvent.pressedMouseButtons & 1 != 0
        if !mouseDown {
            if wheel.automatic {
                if releasedAt == nil { releasedAt = now }
                if now - (releasedAt ?? now) > 0.25 { wheel.hide() }
            }
            return
        }
        releasedAt = nil
        guard automatic, !working, now - recentDrag < 0.35 else { return }
        let pasteboard = NSPasteboard(name: .drag)
        guard pasteboard.changeCount != seenDragCount else { return }
        let urls = WheelView.urls(pasteboard)
        guard !urls.isEmpty else { return }
        seenDragCount = pasteboard.changeCount
        selected = urls
        wheel.show(files: urls, at: NSEvent.mouseLocation, automatic: true)
    }
    private func perform(_ action: FileAction, files: [URL]) {
        guard !working, !files.isEmpty else { return }
        wheel.hide(); selected = files
        switch action {
        case .convert(let format): convert(files, format: format)
        case .metadata: showMetadata(files[0])
        default:
            if files.count > 1 {
                let alert = NSAlert(); alert.messageText = "Edit one file at a time"
                alert.informativeText = "The editor will open \(files[0].lastPathComponent). Format conversion supports multiple files; interactive editing works on one file and one page at a time."
                alert.addButton(withTitle: "Open first file"); alert.addButton(withTitle: "Cancel")
                NSApp.activate(ignoringOtherApps: true)
                guard alert.runModal() == .alertFirstButtonReturn else { return }
            }
            do {
                let editor = try EditorController(source: files[0], action: action, image: ImageEngine.load(files[0]), folder: folder)
                let id = UUID(); editors[id] = editor
                editor.onClose = { [weak self] in self?.editors.removeValue(forKey: id) }
                editor.onSaved = { [weak self] url in self?.finish(outputs: [url], errors: []) }
                NSApp.activate(ignoringOtherApps: true); editor.showWindow(nil)
            } catch { showError(error) }
        }
    }
    private func beginProgress(_ text: String) {
        working = true
        let panel = NSPanel(contentRect: CGRect(x: 0, y: 0, width: 400, height: 115), styleMask: [.titled], backing: .buffered, defer: false)
        panel.title = "Switcheroo"; panel.isReleasedWhenClosed = false
        let label = NSTextField(labelWithString: text); label.frame = CGRect(x: 24, y: 62, width: 352, height: 26)
        label.font = .systemFont(ofSize: 13, weight: .medium); panel.contentView?.addSubview(label)
        let progress = NSProgressIndicator(frame: CGRect(x: 24, y: 30, width: 352, height: 15))
        progress.style = .bar; progress.isIndeterminate = true; progress.startAnimation(nil); panel.contentView?.addSubview(progress)
        panel.center(); panel.makeKeyAndOrderFront(nil); progressPanel = panel
    }
    private func convert(_ files: [URL], format: String) {
        beginProgress("Converting \(files.count) file(s) to \(format.uppercased())…")
        let outputFolder = folder
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var outputs: [URL] = [], errors: [String] = []
            do {
                let session = try OutputStore.makeSession(sources: files, base: outputFolder)
                for file in files {
                    do { outputs += try ImageEngine.convert(file, format: format, folder: session.after) }
                    catch { errors.append("\(file.lastPathComponent): \(error.localizedDescription)") }
                }
                if outputs.isEmpty { try? FileManager.default.removeItem(at: session.root) }
            } catch { errors.append(error.localizedDescription) }
            DispatchQueue.main.async { self?.finish(outputs: outputs, errors: errors) }
        }
    }
    private func finish(outputs: [URL], errors: [String]) {
        working = false; progressPanel?.close(); progressPanel = nil
        if !outputs.isEmpty { lastOutputs = outputs; selected = outputs }
        let alert = NSAlert()
        alert.messageText = outputs.isEmpty ? "No files saved" : "\(outputs.count) \(outputs.count == 1 ? "file" : "files") saved"
        var details = outputs.prefix(5).map { $0.lastPathComponent }.joined(separator: "\n")
        if outputs.count > 5 { details += "\n…and \(outputs.count - 5) more." }
        if !errors.isEmpty { details += "\n\n" + errors.joined(separator: "\n") }
        alert.informativeText = details
        if !outputs.isEmpty { alert.addButton(withTitle: "Reveal in Finder") }
        alert.addButton(withTitle: "Done")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn, !outputs.isEmpty { NSWorkspace.shared.activateFileViewerSelecting(outputs) }
    }
    private func showMetadata(_ url: URL) {
        let alert = NSAlert(); alert.messageText = "File metadata"
        alert.informativeText = url.pathExtension.lowercased() == "pdf"
            ? "PDF metadata is read-only here. Image tools export a selected page as a new image."
            : "A clean PNG copy omits the original EXIF, GPS, and camera metadata."
        let scroll = NSScrollView(frame: CGRect(x: 0, y: 0, width: 480, height: 300))
        scroll.hasVerticalScroller = true
        let text = NSTextView(frame: scroll.bounds); text.isEditable = false
        text.string = ImageEngine.metadata(url); text.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        text.isVerticallyResizable = true; text.autoresizingMask = [.width]
        text.textContainer?.widthTracksTextView = true; scroll.documentView = text; alert.accessoryView = scroll
        let image = url.pathExtension.lowercased() != "pdf"
        if image { alert.addButton(withTitle: "Save clean PNG copy") }
        alert.addButton(withTitle: "Done"); NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn, image {
            do {
                let data = try ImageEngine.encoded(ImageEngine.load(url), format: "png")
                let session = try OutputStore.makeSession(sources: [url], base: folder)
                do {
                    let output = try ImageEngine.save(data, source: url, suffix: " Clean", ext: "png", folder: session.after)
                    finish(outputs: [output], errors: [])
                } catch {
                    try? FileManager.default.removeItem(at: session.root)
                    throw error
                }
            } catch { showError(error) }
        }
    }
    private func showError(_ error: Error) { NSApp.activate(ignoringOtherApps: true); NSAlert(error: error).runModal() }

    @objc func showWelcome() {
        if let welcome, welcome.isVisible { welcome.makeKeyAndOrderFront(nil); return }
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 520, height: 365),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Welcome to Switcheroo"; window.isReleasedWhenClosed = false
        let title = NSTextField(labelWithString: "Your files. One quick switch.")
        title.font = .systemFont(ofSize: 24, weight: .bold); title.frame = CGRect(x: 30, y: 294, width: 465, height: 36)
        window.contentView?.addSubview(title)
        let detail = NSTextField(wrappingLabelWithString:
            "1. Choose a file below, or click the menu-bar icon and choose Show action wheel.\n\n2. Click a format to convert. Tab switches to Crop, Add BG, and editing tools. Optional Finder drag detection can be enabled in the menu.\n\n3. Each action saves Before and After copies in a timestamped Documents/Switcheroo folder. Change the history location from the menu-bar icon.\n\nYou can also choose files below, then click an action. Tab switches wheels; Escape closes. All processing stays on your Mac.")
        detail.font = .systemFont(ofSize: 13); detail.frame = CGRect(x: 30, y: 77, width: 460, height: 202)
        window.contentView?.addSubview(detail)
        let open = NSButton(title: "Choose a file…", target: self, action: #selector(welcomeChoose))
        open.bezelStyle = .rounded; open.keyEquivalent = "\r"; open.frame = CGRect(x: 318, y: 27, width: 172, height: 32)
        window.contentView?.addSubview(open)
        let done = NSButton(title: "Get started", target: self, action: #selector(welcomeDone))
        done.bezelStyle = .rounded; done.frame = CGRect(x: 30, y: 27, width: 156, height: 32)
        window.contentView?.addSubview(done)
        window.center(); NSApp.activate(ignoringOtherApps: true); window.makeKeyAndOrderFront(nil); welcome = window
    }
    @objc private func welcomeChoose() { welcome?.close(); chooseFiles() }
    @objc private func welcomeDone() { welcome?.close() }
}
