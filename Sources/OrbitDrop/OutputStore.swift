import Foundation

struct OutputSession {
    let root: URL
    let before: URL
    let after: URL
}

enum OutputStore {
    static var defaultFolder: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("OrbitDrop", isDirectory: true)
    }

    static func makeSession(sources: [URL], base: URL?) throws -> OutputSession {
        let manager = FileManager.default
        let destination = base ?? defaultFolder
        try manager.createDirectory(at: destination, withIntermediateDirectories: true)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH-mm-ss-SSS"
        let name = "\(formatter.string(from: Date()))-\(UUID().uuidString.prefix(6))"
        let root = destination.appendingPathComponent(name, isDirectory: true)
        let before = root.appendingPathComponent("Before", isDirectory: true)
        let after = root.appendingPathComponent("After", isDirectory: true)
        try manager.createDirectory(at: before, withIntermediateDirectories: true)
        do {
            try manager.createDirectory(at: after, withIntermediateDirectories: true)
            for source in sources {
                let stem = source.deletingPathExtension().lastPathComponent
                let ext = source.pathExtension
                var copy = before.appendingPathComponent(source.lastPathComponent)
                var index = 2
                while manager.fileExists(atPath: copy.path) {
                    let filename = ext.isEmpty ? "\(stem) \(index)" : "\(stem) \(index).\(ext)"
                    copy = before.appendingPathComponent(filename)
                    index += 1
                }
                try manager.copyItem(at: source, to: copy)
            }
            return OutputSession(root: root, before: before, after: after)
        } catch {
            try? manager.removeItem(at: root)
            throw error
        }
    }
}
