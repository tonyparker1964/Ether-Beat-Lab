import AppKit

/// Beat Scripts you load are kept as text files in Music/Ether Beat Lab Projects/Beat Scripts,
/// so you can load them again, open them in any text editor, or share them. Also reads the clipboard for Paste.
enum ScriptsStore {
    static var dir: URL {
        let d = AppFiles.projectsDir.appendingPathComponent("Beat Scripts", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    private static func encode(_ v: Any) -> String {
        (try? JSONSerialization.data(withJSONObject: v)).flatMap { String(data: $0, encoding: .utf8) } ?? "null"
    }

    /// The kept scripts, newest (or most recently used) first.
    static func list() -> [[String: Any]] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey],
                                                                  options: [.skipsHiddenFiles])) ?? []
        var items: [[String: Any]] = []
        for u in urls where u.pathExtension.lowercased() == "txt" {
            guard let text = try? String(contentsOf: u, encoding: .utf8) else { continue }
            let date = (try? u.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date.distantPast
            items.append(["id": u.lastPathComponent, "text": text, "time": date.timeIntervalSince1970 * 1000])
        }
        return items.sorted { (($0["time"] as? Double) ?? 0) > (($1["time"] as? Double) ?? 0) }
    }

    private static func safeName(_ s: String) -> String {
        let bad = CharacterSet(charactersIn: "/\\:?*\"<>|\n\r\t")
        let cleaned = s.components(separatedBy: bad).joined(separator: " ").trimmingCharacters(in: .whitespaces)
        let short = String(cleaned.prefix(60))
        return short.isEmpty ? "Beat Script" : short
    }

    /// A file inside the scripts folder, or nil if the name tries to leave it.
    private static func file(_ id: String) -> URL? {
        guard !id.isEmpty, !id.contains("/"), !id.hasPrefix(".") else { return nil }
        return dir.appendingPathComponent(id)
    }

    static func handle(_ action: String, _ body: [String: Any], reply: @escaping (Any?, String?) -> Void) -> Bool {
        switch action {
        case "clipText":
            reply(encode(["text": NSPasteboard.general.string(forType: .string) ?? ""]), nil)
        case "scriptsList":
            DispatchQueue.global(qos: .userInitiated).async {
                let text = encode(list())
                DispatchQueue.main.async { reply(text, nil) }
            }
        case "scriptSave":
            let text = body["text"] as? String ?? ""
            let name = safeName(body["name"] as? String ?? "Beat Script")
            // The same script again: keep one copy and move it to the top.
            if let same = list().first(where: { ($0["text"] as? String) == text }), let id = same["id"] as? String, let url = file(id) {
                try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)
                reply(encode(["id": id]), nil)
                return true
            }
            var url = dir.appendingPathComponent(name + ".txt")
            var n = 2
            while FileManager.default.fileExists(atPath: url.path) {
                url = dir.appendingPathComponent("\(name) \(n).txt")
                n += 1
            }
            do {
                try text.write(to: url, atomically: true, encoding: .utf8)
                reply(encode(["id": url.lastPathComponent]), nil)
            } catch {
                reply(encode(["error": "Couldn't keep the script: \(error.localizedDescription)"]), nil)
            }
        case "scriptDelete":
            guard let url = file(body["id"] as? String ?? "") else { reply(encode(["error": "That script isn't in the folder."]), nil); break }
            do {
                try FileManager.default.trashItem(at: url, resultingItemURL: nil)
                reply(encode(["ok": true]), nil)
            } catch {
                reply(encode(["error": "Couldn't move it to the Trash: \(error.localizedDescription)"]), nil)
            }
        case "scriptsReveal":
            NSWorkspace.shared.open(dir)
            reply("{}", nil)
        default:
            return false
        }
        return true
    }
}
