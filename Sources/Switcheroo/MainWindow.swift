import AppKit
import PDFKit
import ImageIO
import UniformTypeIdentifiers

/// One thing Switcheroo did: the files as they were, and what they were switched into.
struct HistoryRun {
    let root: URL
    let before: [URL]
    let after: [URL]
    let date: Date
}

enum HistoryStore {
    static func runs(in base: URL) -> [HistoryRun] {
        let manager = FileManager.default
        let folders = (try? manager.contentsOfDirectory(at: base, includingPropertiesForKeys: [.creationDateKey], options: [.skipsHiddenFiles])) ?? []
        func files(_ folder: URL) -> [URL] {
            ((try? manager.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? [])
                .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        }
        return folders.compactMap { folder -> HistoryRun? in
            let after = files(folder.appendingPathComponent("After", isDirectory: true))
            guard !after.isEmpty else { return nil }
            let date = (try? folder.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            return HistoryRun(root: folder, before: files(folder.appendingPathComponent("Before", isDirectory: true)), after: after, date: date)
        }.sorted { $0.date > $1.date }
    }
}

/// What a file is, in words a person would use: "HEIC image · 4032 × 3024 · 2.1 MB".
enum FileDescriber {
    static func describe(_ url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        var parts: [String] = []
        parts.append(UTType(filenameExtension: ext)?.localizedDescription?.capitalizedFirst ?? (ext.isEmpty ? "File" : "\(ext.uppercased()) file"))
        if ext == "pdf" {
            if let pages = PDFDocument(url: url)?.pageCount { parts.append(pages == 1 ? "1 page" : "\(pages) pages") }
        } else if let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                  let width = properties[kCGImagePropertyPixelWidth] as? Int, let height = properties[kCGImagePropertyPixelHeight] as? Int {
            parts.append("\(width) × \(height)")
        }
        if let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize {
            parts.append(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))
        }
        return parts.joined(separator: " · ")
    }
}

private extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}

/// Where a file is dropped. It lights up while a file is held over it.
final class DropZoneView: NSView {
    var onDrop: (([URL]) -> Void)?
    private var over = false { didSet { needsDisplay = true } }

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Drop a file here to switch it")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 2), xRadius: 16, yRadius: 16)
        (over ? WheelTheme.accent.withAlphaComponent(0.16) : NSColor.labelColor.withAlphaComponent(0.04)).setFill()
        path.fill()
        path.lineWidth = 2
        path.setLineDash([7, 5], count: 2, phase: 0)
        (over ? WheelTheme.accent : NSColor.tertiaryLabelColor).setStroke()
        path.stroke()
    }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        over = !WheelView.urls(sender.draggingPasteboard).isEmpty
        return over ? .copy : []
    }
    override func draggingExited(_ sender: NSDraggingInfo?) { over = false }
    override func draggingEnded(_ sender: NSDraggingInfo) { over = false }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = WheelView.urls(sender.draggingPasteboard)
        over = false
        guard !urls.isEmpty else { return false }
        onDrop?(urls)
        return true
    }
}

/// The app's face: drop a file, see what it is, choose what to switch it to, and find every earlier
/// switch below, with the original beside the result.
final class MainWindowController: NSObject, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate {
    var perform: ((FileAction, [URL]) -> Void)?
    var chooseFiles: (() -> Void)?
    var baseFolder: (() -> URL)?

    private var window: NSWindow?
    private var files: [URL] = []
    private var runs: [HistoryRun] = []
    private let dropZone = DropZoneView(frame: .zero)
    private let dropTitle = NSTextField(labelWithString: "Drop a file to switch it")
    private let dropNote = NSTextField(labelWithString: "Images and PDFs. Nothing leaves your Mac.")
    private let fileBox = NSStackView()
    private let fileIcon = NSImageView()
    private let fileName = NSTextField(labelWithString: "")
    private let fileDetail = NSTextField(labelWithString: "")
    private let formats = NSStackView()
    private let tools = NSStackView()
    private let status = NSTextField(labelWithString: "")
    private let table = NSTableView()
    private let emptyHistory = NSTextField(labelWithString: "Nothing yet. What you switch shows up here, original and result together.")
    private let revealButton = NSButton(title: "Show in Finder", target: nil, action: nil)
    private let deleteButton = NSButton(title: "Delete", target: nil, action: nil)
    private var actions: [FileAction] = []
    private static let dates: DateFormatter = {
        let formatter = DateFormatter(); formatter.dateStyle = .medium; formatter.timeStyle = .short
        formatter.doesRelativeDateFormatting = true
        return formatter
    }()

    var isVisible: Bool { window?.isVisible ?? false }

    func show() {
        if window == nil { build() }
        reloadHistory()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    /// Puts files in front of the visitor, as if they had been dropped on the window.
    func load(_ urls: [URL]) {
        if window == nil { build() }
        files = urls
        status.stringValue = ""
        refreshFile()
    }

    /// Called when an action has finished, so the window can show the result.
    func finished(outputs: [URL], errors: [String]) {
        guard window != nil else { return }
        reloadHistory()
        if outputs.isEmpty {
            status.stringValue = errors.first ?? "Nothing was saved."
            status.textColor = .systemRed
        } else {
            let names = outputs.count == 1 ? outputs[0].lastPathComponent : "\(outputs.count) files"
            status.stringValue = errors.isEmpty ? "Saved \(names). It is at the top of your history." : "Saved \(names). \(errors.count) could not be switched."
            status.textColor = errors.isEmpty ? .secondaryLabelColor : .systemOrange
            if !runs.isEmpty { table.selectRowIndexes([0], byExtendingSelection: false); table.scrollRowToVisible(0) }
        }
    }

    // MARK: Building the window

    private func build() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 640), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Switcheroo"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.minSize = NSSize(width: 560, height: 520)
        window.setFrameAutosaveName("SwitcherooMain")

        // the drop zone
        dropTitle.font = .systemFont(ofSize: 17, weight: .semibold)
        dropNote.font = .systemFont(ofSize: 12); dropNote.textColor = .secondaryLabelColor
        let symbol = NSImageView(image: NSImage(systemSymbolName: "arrow.left.arrow.right", accessibilityDescription: nil) ?? NSImage())
        symbol.symbolConfiguration = .init(pointSize: 26, weight: .semibold); symbol.contentTintColor = .secondaryLabelColor
        let choose = NSButton(title: "Choose a file…", target: self, action: #selector(choose))
        choose.bezelStyle = .rounded
        let dropStack = NSStackView(views: [symbol, dropTitle, dropNote, choose])
        dropStack.orientation = .vertical; dropStack.alignment = .centerX; dropStack.spacing = 8
        dropStack.translatesAutoresizingMaskIntoConstraints = false
        dropZone.addSubview(dropStack)
        dropZone.onDrop = { [weak self] urls in self?.load(urls) }
        dropZone.translatesAutoresizingMaskIntoConstraints = false

        // the file that was dropped, and what it can become
        fileIcon.imageScaling = .scaleProportionallyUpOrDown
        fileName.font = .systemFont(ofSize: 14, weight: .semibold); fileName.lineBreakMode = .byTruncatingMiddle
        fileDetail.font = .systemFont(ofSize: 12); fileDetail.textColor = .secondaryLabelColor
        let names = NSStackView(views: [fileName, fileDetail]); names.orientation = .vertical; names.alignment = .leading; names.spacing = 2
        let clear = NSButton(title: "Clear", target: self, action: #selector(clearFile)); clear.bezelStyle = .rounded; clear.controlSize = .small
        let header = NSStackView(views: [fileIcon, names, NSView(), clear]); header.orientation = .horizontal; header.spacing = 10
        fileIcon.widthAnchor.constraint(equalToConstant: 40).isActive = true
        fileIcon.heightAnchor.constraint(equalToConstant: 40).isActive = true
        let switchLabel = caption("SWITCH IT TO")
        let toolLabel = caption("OR CHANGE IT")
        for row in [formats, tools] { row.orientation = .horizontal; row.spacing = 6; row.alignment = .centerY }
        fileBox.orientation = .vertical; fileBox.alignment = .leading; fileBox.spacing = 8
        for view in [header, switchLabel, formats, toolLabel, tools] as [NSView] { fileBox.addArrangedSubview(view) }
        header.widthAnchor.constraint(equalTo: fileBox.widthAnchor).isActive = true
        fileBox.setCustomSpacing(14, after: header)
        fileBox.setCustomSpacing(12, after: formats)
        fileBox.isHidden = true

        status.font = .systemFont(ofSize: 12); status.textColor = .secondaryLabelColor; status.lineBreakMode = .byTruncatingTail

        // history
        let historyTitle = NSTextField(labelWithString: "History")
        historyTitle.font = .systemFont(ofSize: 13, weight: .semibold)
        let historyNote = NSTextField(labelWithString: "Kept inside Switcheroo. Drag a row out to put the result anywhere.")
        historyNote.font = .systemFont(ofSize: 11); historyNote.textColor = .secondaryLabelColor
        revealButton.target = self; revealButton.action = #selector(reveal); revealButton.bezelStyle = .rounded; revealButton.controlSize = .small
        deleteButton.target = self; deleteButton.action = #selector(deleteRun); deleteButton.bezelStyle = .rounded; deleteButton.controlSize = .small
        let historyHeader = NSStackView(views: [historyTitle, historyNote, NSView(), revealButton, deleteButton])
        historyHeader.orientation = .horizontal; historyHeader.spacing = 8

        let column = NSTableColumn(identifier: .init("run")); column.resizingMask = .autoresizingMask
        table.addTableColumn(column); table.headerView = nil; table.rowHeight = 52
        table.dataSource = self; table.delegate = self
        table.style = .inset; table.usesAlternatingRowBackgroundColors = false
        table.doubleAction = #selector(open); table.target = self
        table.setDraggingSourceOperationMask(.copy, forLocal: false)
        table.setAccessibilityLabel("History of switched files")
        let scroll = NSScrollView(); scroll.documentView = table; scroll.hasVerticalScroller = true
        scroll.borderType = .noBorder; scroll.drawsBackground = false
        scroll.wantsLayer = true; scroll.layer?.cornerRadius = 12; scroll.layer?.borderWidth = 1
        scroll.layer?.borderColor = NSColor.separatorColor.cgColor
        emptyHistory.font = .systemFont(ofSize: 12); emptyHistory.textColor = .tertiaryLabelColor; emptyHistory.alignment = .center
        emptyHistory.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(emptyHistory)

        let column0 = NSStackView(views: [dropZone, fileBox, status, historyHeader, scroll])
        column0.orientation = .vertical; column0.alignment = .leading; column0.spacing = 14
        column0.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        column0.translatesAutoresizingMaskIntoConstraints = false
        let content = NSView(); content.addSubview(column0)
        NSLayoutConstraint.activate([
            column0.leadingAnchor.constraint(equalTo: content.leadingAnchor), column0.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            column0.topAnchor.constraint(equalTo: content.topAnchor), column0.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            dropZone.widthAnchor.constraint(equalTo: column0.widthAnchor, constant: -40),
            dropZone.heightAnchor.constraint(equalToConstant: 170),
            dropStack.centerXAnchor.constraint(equalTo: dropZone.centerXAnchor), dropStack.centerYAnchor.constraint(equalTo: dropZone.centerYAnchor),
            fileBox.widthAnchor.constraint(equalTo: column0.widthAnchor, constant: -40),
            status.widthAnchor.constraint(equalTo: column0.widthAnchor, constant: -40),
            historyHeader.widthAnchor.constraint(equalTo: column0.widthAnchor, constant: -40),
            scroll.widthAnchor.constraint(equalTo: column0.widthAnchor, constant: -40),
            scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 150),
            emptyHistory.centerXAnchor.constraint(equalTo: scroll.centerXAnchor), emptyHistory.centerYAnchor.constraint(equalTo: scroll.centerYAnchor),
            emptyHistory.widthAnchor.constraint(lessThanOrEqualTo: scroll.widthAnchor, constant: -30),
        ])
        scroll.setContentHuggingPriority(.defaultLow, for: .vertical)
        window.contentView = content
        if !window.setFrameUsingName("SwitcherooMain") { window.center() }
        self.window = window
        refreshFile()
    }

    private func caption(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 10, weight: .semibold); label.textColor = .tertiaryLabelColor
        return label
    }

    // MARK: The dropped file

    private func refreshFile() {
        guard window != nil else { return }
        fileBox.isHidden = files.isEmpty
        dropTitle.stringValue = files.isEmpty ? "Drop a file to switch it" : "Drop another file"
        guard let first = files.first else { return }
        fileIcon.image = NSWorkspace.shared.icon(forFile: first.path)
        fileName.stringValue = files.count == 1 ? first.lastPathComponent : "\(files.count) files"
        fileDetail.stringValue = files.count == 1 ? FileDescriber.describe(first) : files.prefix(3).map { $0.lastPathComponent }.joined(separator: ", ") + (files.count > 3 ? "…" : "")

        // every format this file can become, leaving out the one it already is
        let current = Set(files.map { $0.pathExtension.lowercased() }.map { $0 == "jpeg" ? "jpg" : $0 == "tif" ? "tiff" : $0 })
        let conversions = FileAction.conversions(for: files).filter { action in
            if case .convert(let format) = action, current.count == 1, current.contains(format) { return false }
            return true
        }
        actions = conversions + FileAction.editing
        fill(formats, with: conversions, offset: 0)
        fill(tools, with: FileAction.editing, offset: conversions.count)
    }

    private func fill(_ row: NSStackView, with list: [FileAction], offset: Int) {
        row.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for (index, action) in list.enumerated() {
            let title: String
            if case .convert = action { title = action.title } else { title = action.title.capitalized.replacingOccurrences(of: "Bg", with: "background") }
            let button = NSButton(title: title, target: self, action: #selector(run(_:)))
            button.bezelStyle = .rounded; button.tag = offset + index
            if case .convert = action { button.font = .systemFont(ofSize: 12, weight: .semibold) }
            row.addArrangedSubview(button)
        }
    }

    @objc private func run(_ sender: NSButton) {
        guard actions.indices.contains(sender.tag), !files.isEmpty else { return }
        status.stringValue = ""
        perform?(actions[sender.tag], files)
    }
    @objc private func choose() { chooseFiles?() }
    @objc private func clearFile() { files = []; status.stringValue = ""; refreshFile() }

    // MARK: History

    func reloadHistory() {
        guard window != nil, let base = baseFolder?() else { return }
        runs = HistoryStore.runs(in: base)
        table.reloadData()
        emptyHistory.isHidden = !runs.isEmpty
        updateButtons()
    }
    private func updateButtons() {
        let chosen = runs.indices.contains(table.selectedRow)
        revealButton.isEnabled = chosen; deleteButton.isEnabled = chosen
    }
    func numberOfRows(in tableView: NSTableView) -> Int { runs.count }
    func tableViewSelectionDidChange(_ notification: Notification) { updateButtons() }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let run = runs[row]
        let cell = NSTableCellView()
        let icon = NSImageView(image: NSWorkspace.shared.icon(forFile: run.after[0].path))
        let before = run.before.first?.lastPathComponent ?? "Original"
        let after = run.after[0].lastPathComponent + (run.after.count > 1 ? " and \(run.after.count - 1) more" : "")
        let title = NSTextField(labelWithString: "\(before)  →  \(after)")
        title.font = .systemFont(ofSize: 13, weight: .medium); title.lineBreakMode = .byTruncatingMiddle
        let detail = NSTextField(labelWithString: Self.dates.string(from: run.date))
        detail.font = .systemFont(ofSize: 11); detail.textColor = .secondaryLabelColor
        let text = NSStackView(views: [title, detail]); text.orientation = .vertical; text.alignment = .leading; text.spacing = 2
        let line = NSStackView(views: [icon, text]); line.orientation = .horizontal; line.spacing = 10
        line.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(line)
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 32), icon.heightAnchor.constraint(equalToConstant: 32),
            line.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 6), line.trailingAnchor.constraint(lessThanOrEqualTo: cell.trailingAnchor, constant: -6),
            line.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        cell.setAccessibilityLabel("\(before) switched to \(after), \(Self.dates.string(from: run.date))")
        return cell
    }
    /// A row can be dragged out of the window: what is dragged is the result.
    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
        runs.indices.contains(row) ? runs[row].after[0] as NSURL : nil
    }
    @objc private func open() {
        guard runs.indices.contains(table.clickedRow) else { return }
        NSWorkspace.shared.open(runs[table.clickedRow].after[0])
    }
    @objc private func reveal() {
        guard runs.indices.contains(table.selectedRow) else { return }
        let run = runs[table.selectedRow]
        NSWorkspace.shared.activateFileViewerSelecting(run.after + run.before)
    }
    @objc private func deleteRun() {
        guard runs.indices.contains(table.selectedRow), let window else { return }
        let run = runs[table.selectedRow]
        let alert = NSAlert()
        alert.messageText = "Delete this from your history?"
        alert.informativeText = "The saved original and result go to the Trash. The file you dropped is not touched."
        alert.addButton(withTitle: "Move to Trash"); alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            try? FileManager.default.trashItem(at: run.root, resultingItemURL: nil)
            self?.reloadHistory()
        }
    }
}
