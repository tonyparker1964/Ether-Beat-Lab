import AppKit
import WebKit
import UniformTypeIdentifiers

/// Where Beat Lab keeps its own files (the scanned library), on this Mac only.
enum AppFiles {
    static var dir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let d = base.appendingPathComponent("Ether Beat Lab", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }
    static var libraryURL: URL { dir.appendingPathComponent("library.json") }
    static var autosaveURL: URL { dir.appendingPathComponent("Autosave.etherbeat") }
    /// Where projects are saved unless you pick somewhere else.
    static var projectsDir: URL {
        let music = FileManager.default.urls(for: .musicDirectory, in: .userDomainMask)[0]
        let d = music.appendingPathComponent("Ether Beat Lab Projects", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }
    static var projectType: UTType { UTType(filenameExtension: "etherbeat") ?? .json }

    /// The Beat Lab page: inside the app when installed, or the repository's index.html when run with `swift run`.
    static var webPage: URL? {
        if let bundled = Bundle.main.resourceURL?.appendingPathComponent("Web/index.html"),
           FileManager.default.fileExists(atPath: bundled.path) { return bundled }
        let repo = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("index.html")
        return FileManager.default.fileExists(atPath: repo.path) ? repo : nil
    }
}

/// The scanned library, shared by the bridge (which answers the page) and the sound server.
final class LibraryStore {
    static let shared = LibraryStore()
    private let lock = NSLock()
    private var index = LibraryIndex()
    private var allowed = Set<String>()

    init() {
        if let d = try? Data(contentsOf: AppFiles.libraryURL), let idx = try? JSONDecoder().decode(LibraryIndex.self, from: d) {
            set(idx)
        }
    }

    func set(_ idx: LibraryIndex) {
        let paths = idx.allowedPaths
        lock.lock()
        index = idx
        allowed = paths
        lock.unlock()
    }

    var current: LibraryIndex {
        lock.lock(); defer { lock.unlock() }
        return index
    }

    /// Only files the scan found (and voice chops the app made) can be served to the page.
    func isAllowed(_ path: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return allowed.contains(path) || path.hasPrefix(Voices.dir.path + "/")
            || path.hasPrefix(Engine.recordingsDir.path + "/") || path.hasPrefix(Engine.rendersDir.path + "/")
    }

    var folders: [String] {
        get { UserDefaults.standard.stringArray(forKey: "soundFolders") ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: "soundFolders") }
    }

    func scan() -> LibraryIndex {
        let roots = folders.filter { FileManager.default.fileExists(atPath: $0) }.map { URL(fileURLWithPath: $0) }
        let idx = LibraryScanner.scan(roots: roots)
        if let d = try? JSONEncoder().encode(idx) { try? d.write(to: AppFiles.libraryURL, options: .atomic) }
        set(idx)
        return idx
    }
}

/// Serves the page and the sound files under ether://app/, so the page loads them like any web resource.
final class SchemeHandler: NSObject, WKURLSchemeHandler {
    private var active = Set<ObjectIdentifier>()

    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        active.insert(ObjectIdentifier(task))
        guard let url = task.request.url else { return fail(task) }
        if url.path == "/sound" {
            let path = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "p" }?.value ?? ""
            guard LibraryStore.shared.isAllowed(path) else { return fail(task, status: 403) }
            DispatchQueue.global(qos: .userInitiated).async {
                let data = try? Data(contentsOf: URL(fileURLWithPath: path))
                DispatchQueue.main.async {
                    guard let data else { return self.fail(task, status: 404) }
                    self.respond(task, url: url, data: data, type: Self.mime(path))
                }
            }
            return
        }
        guard let page = AppFiles.webPage, let data = try? Data(contentsOf: page) else { return fail(task, status: 404) }
        respond(task, url: url, data: data, type: "text/html; charset=utf-8")
    }

    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {
        active.remove(ObjectIdentifier(task))
    }

    private func respond(_ task: WKURLSchemeTask, url: URL, data: Data, type: String) {
        guard active.contains(ObjectIdentifier(task)) else { return }
        let headers = ["Content-Type": type, "Content-Length": String(data.count), "Cache-Control": "no-store"]
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: headers)!
        task.didReceive(response)
        task.didReceive(data)
        task.didFinish()
        active.remove(ObjectIdentifier(task))
    }

    private func fail(_ task: WKURLSchemeTask, status: Int = 400) {
        guard active.contains(ObjectIdentifier(task)), let url = task.request.url else { return }
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Length": "0"])!
        task.didReceive(response)
        task.didFinish()
        active.remove(ObjectIdentifier(task))
    }

    static func mime(_ path: String) -> String {
        switch (path as NSString).pathExtension.lowercased() {
        case "wav", "wave": return "audio/wav"
        case "aif", "aiff": return "audio/aiff"
        case "flac": return "audio/flac"
        default: return "application/octet-stream"
        }
    }
}

/// Answers the page's requests: the NI library, choosing folders, and the AI Producer.
final class Bridge: NSObject, WKScriptMessageHandlerWithReply {
    weak var window: NSWindow?

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage,
                               replyHandler: @escaping (Any?, String?) -> Void) {
        guard let body = message.body as? [String: Any], let action = body["action"] as? String else {
            return replyHandler(nil, "Unknown request")
        }
        switch action {
        case "library":
            replyHandler(Self.json(LibraryStore.shared.current, folders: LibraryStore.shared.folders), nil)
        case "addFolders":
            let panel = NSOpenPanel()
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.allowsMultipleSelection = true
            panel.prompt = "Add"
            panel.message = "Choose your Native Instruments drive or folders with samples (Maschine expansions, Battery kits)."
            guard panel.runModal() == .OK else { return replyHandler(nil, nil) }
            var folders = LibraryStore.shared.folders
            for url in panel.urls where !folders.contains(url.path) { folders.append(url.path) }
            LibraryStore.shared.folders = folders
            rescan(replyHandler)
        case "removeFolder":
            let path = body["path"] as? String ?? ""
            LibraryStore.shared.folders = LibraryStore.shared.folders.filter { $0 != path }
            rescan(replyHandler)
        case "rescan":
            rescan(replyHandler)
        case "saveProject":
            // Saves straight to the project's file, or asks where (Save As, or a project that's never been saved).
            let json = body["json"] as? String ?? ""
            let name = (body["name"] as? String ?? "Untitled beat").trimmingCharacters(in: .whitespacesAndNewlines)
            var target: URL?
            if let path = body["path"] as? String, !path.isEmpty { target = URL(fileURLWithPath: path) }
            if target == nil {
                let panel = NSSavePanel()
                panel.allowedContentTypes = [AppFiles.projectType]
                panel.directoryURL = AppFiles.projectsDir
                panel.nameFieldStringValue = (name.isEmpty ? "Untitled beat" : name) + ".etherbeat"
                panel.message = "Save your Ether Beat Lab project"
                guard panel.runModal() == .OK, let url = panel.url else { return replyHandler(Self.encode(["cancelled": "1"]), nil) }
                target = url
            }
            do {
                try Data(json.utf8).write(to: target!, options: .atomic)
                window?.representedURL = target
                replyHandler(Self.encode(["path": target!.path, "name": target!.deletingPathExtension().lastPathComponent]), nil)
            } catch {
                replyHandler(Self.encode(["error": "Couldn't save: \(error.localizedDescription)"]), nil)
            }
        case "openProject":
            let panel = NSOpenPanel()
            panel.allowedContentTypes = [AppFiles.projectType, .json]
            panel.directoryURL = AppFiles.projectsDir
            panel.message = "Open an Ether Beat Lab project"
            guard panel.runModal() == .OK, let url = panel.url else { return replyHandler(Self.encode(["cancelled": "1"]), nil) }
            guard let data = try? Data(contentsOf: url), let json = String(data: data, encoding: .utf8) else {
                return replyHandler(Self.encode(["error": "That file couldn't be read."]), nil)
            }
            window?.representedURL = url
            NSDocumentController.shared.noteNewRecentDocumentURL(url)
            replyHandler(Self.encode(["path": url.path, "name": url.deletingPathExtension().lastPathComponent, "json": json]), nil)
        case "autosave":
            // Kept quietly in the background so a crash or a closed window never loses the beat.
            let json = body["json"] as? String ?? ""
            let meta = ["path": body["path"] as? String ?? "", "name": body["name"] as? String ?? ""]
            DispatchQueue.global(qos: .utility).async {
                try? Data(json.utf8).write(to: AppFiles.autosaveURL, options: .atomic)
                UserDefaults.standard.set(meta, forKey: "autosaveMeta")
            }
            replyHandler("{}", nil)
        case "loadAutosave":
            guard let data = try? Data(contentsOf: AppFiles.autosaveURL), let json = String(data: data, encoding: .utf8) else {
                return replyHandler("{}", nil)
            }
            let meta = UserDefaults.standard.dictionary(forKey: "autosaveMeta") as? [String: String] ?? [:]
            replyHandler(Self.encode(["json": json, "path": meta["path"] ?? "", "name": meta["name"] ?? ""]), nil)
        case "clearAutosave":
            try? FileManager.default.removeItem(at: AppFiles.autosaveURL)
            UserDefaults.standard.removeObject(forKey: "autosaveMeta")
            window?.representedURL = nil
            replyHandler("{}", nil)
        case "title":
            let title = body["title"] as? String ?? "Ether Beat Lab"
            window?.title = title
            window?.isDocumentEdited = (body["edited"] as? Bool) ?? false
            replyHandler("{}", nil)
        case "getFavs":
            let favs = UserDefaults.standard.stringArray(forKey: "favorites") ?? []
            let text = (try? JSONSerialization.data(withJSONObject: favs)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
            replyHandler(text, nil)
        case "setFavs":
            let favs = (body["favs"] as? [Any] ?? []).compactMap { $0 as? String }
            UserDefaults.standard.set(Array(favs.prefix(5000)), forKey: "favorites")
            replyHandler("{}", nil)
        case "voices":
            DispatchQueue.global(qos: .userInitiated).async {
                let list = Voices.list()
                let text = (try? JSONEncoder().encode(list)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
                DispatchQueue.main.async { replyHandler(text, nil) }
            }
        case "speak":
            let text = body["text"] as? String ?? ""
            let voice = body["voice"] as? String ?? ""
            let rate = (body["rate"] as? NSNumber)?.intValue ?? 140
            DispatchQueue.global(qos: .userInitiated).async {
                let path = Voices.speak(text, voice: voice, rate: rate)
                DispatchQueue.main.async {
                    replyHandler(Self.encode(path.map { ["path": $0] } ?? ["error": "That voice couldn't speak. Pick another voice."]), nil)
                }
            }
        case "settings":
            replyHandler(Self.encode(["model": UserDefaults.standard.string(forKey: "producerModel") ?? "",
                                      "lmStudioURL": Producer.baseURL]), nil)
        case "produce":
            let system = body["system"] as? String ?? ""
            let user = body["user"] as? String ?? ""
            let model = (body["model"] as? String ?? "").trimmingCharacters(in: .whitespaces)
            UserDefaults.standard.set(model, forKey: "producerModel")
            Task {
                let result = await Producer.ask(system: system, user: user, model: model)
                await MainActor.run { replyHandler(Self.encode(result), nil) }
            }
        default:
            // plug-ins, MIDI, audio devices and recording
            if Engine.shared.handle(action, body, reply: replyHandler) { return }
            replyHandler(nil, "Unknown request: \(action)")
        }
    }

    private func rescan(_ reply: @escaping (Any?, String?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let idx = LibraryStore.shared.scan()
            let text = Self.json(idx, folders: LibraryStore.shared.folders)
            DispatchQueue.main.async { reply(text, nil) }
        }
    }

    static func json(_ idx: LibraryIndex, folders: [String]) -> String {
        struct Payload: Encodable {
            var folders: [String]
            var missing: [String]
            var drums: [DrumFile]
            var instruments: [Instrument]
            var locked: Int
        }
        let missing = folders.filter { !FileManager.default.fileExists(atPath: $0) }
        let p = Payload(folders: folders, missing: missing, drums: idx.drums, instruments: idx.instruments, locked: idx.locked)
        guard let d = try? JSONEncoder().encode(p) else { return "{}" }
        return String(data: d, encoding: .utf8) ?? "{}"
    }

    static func encode(_ dict: [String: String]) -> String {
        guard let d = try? JSONSerialization.data(withJSONObject: dict) else { return "{}" }
        return String(data: d, encoding: .utf8) ?? "{}"
    }
}

/// Natural vocal chops from the voices built into macOS (System Settings → Accessibility → Spoken Content).
/// Made on this Mac with the `say` tool; nothing goes online.
enum Voices {
    static var dir: URL {
        let d = AppFiles.dir.appendingPathComponent("Voices", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    struct Voice: Codable { var name: String; var locale: String }

    /// Installed voices, from `say -v ?`. Lines look like "Samantha            en_US    # Hello…".
    static func list() -> [Voice] {
        guard let out = run(["-v", "?"]) else { return [] }
        let re = try? NSRegularExpression(pattern: "^(.+?)\\s{2,}([a-z]{2,3}_[A-Za-z0-9]+)\\s+#")
        var voices: [Voice] = []
        for line in out.split(separator: "\n").map(String.init) {
            let ns = line as NSString
            guard let m = re?.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) else { continue }
            voices.append(Voice(name: ns.substring(with: m.range(at: 1)).trimmingCharacters(in: .whitespaces),
                                locale: ns.substring(with: m.range(at: 2))))
        }
        return voices
    }

    /// Speaks a short word into a WAV file and returns its path. Same voice and word reuse the file.
    static func speak(_ text: String, voice: String, rate: Int) -> String? {
        let clean = String(text.filter { $0.isLetter || $0 == " " || $0 == "'" }.prefix(40)).trimmingCharacters(in: .whitespaces)
        guard !clean.isEmpty, list().contains(where: { $0.name == voice }) else { return nil }
        let id = LibraryScanner.stableID(voice + "|" + clean + "|" + String(rate))
        let url = dir.appendingPathComponent("\(id).wav")
        if FileManager.default.fileExists(atPath: url.path) { return url.path }
        _ = run(["-v", voice, "-r", String(max(60, min(260, rate))), "--file-format=WAVE", "--data-format=LEI16@44100",
                 "-o", url.path, "--", clean])
        return FileManager.default.fileExists(atPath: url.path) ? url.path : nil
    }

    @discardableResult
    static func run(_ args: [String]) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(data: data, encoding: .utf8)
    }
}

/// Talks to LM Studio on this Mac. No API key; nothing leaves the computer.
enum Producer {
    static var baseURL: String { UserDefaults.standard.string(forKey: "lmStudioURL") ?? "http://127.0.0.1:1234" }

    static func ask(system: String, user: String, model: String) async -> [String: String] {
        var chosen = model
        if chosen.isEmpty { chosen = await loadedModel() ?? "" }
        if chosen.isEmpty {
            return ["error": "LM Studio isn't running, or it has no model. Open LM Studio, load a model and start its server."]
        }
        guard let url = URL(string: baseURL + "/v1/chat/completions") else { return ["error": "LM Studio's address isn't valid."] }
        let noThink = chosen.lowercased().contains("qwen3")
        let payload: [String: Any] = [
            "model": chosen,
            "messages": [["role": "system", "content": system],
                         ["role": "user", "content": noThink ? user + "\n/no_think" : user]],
            "max_tokens": 3000,
            "temperature": 0.6,
            "stream": false
        ]
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 600
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(status) else {
                let body = String(data: data, encoding: .utf8) ?? ""
                return ["error": "LM Studio answered with an error (\(status)). \(body.prefix(200))"]
            }
            let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let choices = obj?["choices"] as? [[String: Any]]
            let message = choices?.first?["message"] as? [String: Any]
            let text = message?["content"] as? String ?? ""
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return ["error": "The model answered with nothing. Try a different model in LM Studio."]
            }
            return ["text": text, "model": chosen]
        } catch {
            return ["error": "LM Studio isn't reachable at \(baseURL). Open LM Studio and start its server (Developer → Status: Running)."]
        }
    }

    /// The model LM Studio already has loaded, so there's nothing to set up.
    static func loadedModel() async -> String? {
        func list(_ path: String) async -> [[String: Any]] {
            guard let url = URL(string: baseURL + path),
                  let result = try? await URLSession.shared.data(from: url),
                  let obj = try? JSONSerialization.jsonObject(with: result.0) as? [String: Any],
                  let items = obj["data"] as? [[String: Any]] else { return [] }
            return items
        }
        // LM Studio's own list says which model is loaded right now.
        let llms = await list("/api/v0/models").filter { ($0["type"] as? String ?? "llm") != "embeddings" }
        if let loaded = llms.first(where: { ($0["state"] as? String) == "loaded" })?["id"] as? String { return loaded }
        if let any = llms.first?["id"] as? String { return any }
        return await list("/v1/models").compactMap { $0["id"] as? String }.first { !$0.lowercased().contains("embed") }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, WKNavigationDelegate, WKUIDelegate, WKDownloadDelegate {
    var window: NSWindow!
    var webView: WKWebView!
    let bridge = Bridge()
    let scheme = SchemeHandler()

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMenu()
        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(scheme, forURLScheme: "ether")
        config.userContentController.addScriptMessageHandler(bridge, contentWorld: .page, name: "ether")
        config.mediaTypesRequiringUserActionForPlayback = []
        config.preferences.isElementFullscreenEnabled = true // the visualizer's full screen button
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")

        webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.setValue(false, forKey: "drawsBackground")

        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1180, height: 900),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Ether Beat Lab"
        window.backgroundColor = NSColor(red: 0.04, green: 0.035, blue: 0.027, alpha: 1)
        window.contentView = webView
        window.setFrameAutosaveName("EtherBeatLabWindow")
        if !window.setFrameUsingName("EtherBeatLabWindow") { window.center() }
        window.makeKeyAndOrderFront(nil)
        bridge.window = window
        Engine.shared.webView = webView

        if AppFiles.webPage == nil {
            webView.loadHTMLString("<body style='background:#0a0907;color:#efe3c8;font:16px system-ui;padding:40px'>The Beat Lab page (index.html) wasn't found. Reinstall with install-mac-app.sh.</body>", baseURL: nil)
        } else {
            webView.load(URLRequest(url: URL(string: "ether://app/index.html")!))
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { Engine.shared.startMIDI() }

    // Recording from the microphone or an audio interface (macOS still asks you once).
    func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin, initiatedByFrame frame: WKFrameInfo,
                 type: WKMediaCaptureType, decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        decisionHandler(type == .microphone ? .grant : .deny)
    }

    // Links to other sites open in the browser.
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if navigationAction.shouldPerformDownload { return decisionHandler(.download) }
        if let url = navigationAction.request.url, let s = url.scheme, s == "http" || s == "https",
           navigationAction.navigationType == .linkActivated {
            NSWorkspace.shared.open(url)
            return decisionHandler(.cancel)
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
                 decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        decisionHandler(navigationResponse.canShowMIMEType ? .allow : .download)
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url, url.scheme == "http" || url.scheme == "https" { NSWorkspace.shared.open(url) }
        return nil
    }

    // Export: saves into Downloads and shows it in Finder.
    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) { download.delegate = self }
    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) { download.delegate = self }

    private var lastDownload: URL?

    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String,
                  completionHandler: @escaping (URL?) -> Void) {
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        let name = suggestedFilename.isEmpty ? "Ether Beat Lab export" : suggestedFilename
        var url = downloads.appendingPathComponent(name)
        let stem = (name as NSString).deletingPathExtension, ext = (name as NSString).pathExtension
        var n = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = downloads.appendingPathComponent(ext.isEmpty ? "\(stem) \(n)" : "\(stem) \(n).\(ext)")
            n += 1
        }
        lastDownload = url
        completionHandler(url)
    }

    func downloadDidFinish(_ download: WKDownload) {
        if let url = lastDownload { NSWorkspace.shared.activateFileViewerSelecting([url]) }
    }

    // The sampler's "load a file" button.
    func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters, initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping ([URL]?) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = parameters.allowsMultipleSelection
        panel.beginSheetModal(for: window) { completionHandler($0 == .OK ? panel.urls : nil) }
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping (Bool) -> Void) {
        let alert = NSAlert()
        alert.messageText = message
        alert.addButton(withTitle: "Continue")
        alert.addButton(withTitle: "Cancel")
        completionHandler(alert.runModal() == .alertFirstButtonReturn)
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping () -> Void) {
        let alert = NSAlert()
        alert.messageText = message
        alert.runModal()
        completionHandler()
    }

    func buildMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        main.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Ether Beat Lab", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide Ether Beat Lab", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "Quit Ether Beat Lab", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu

        let fileItem = NSMenuItem()
        main.addItem(fileItem)
        let file = NSMenu(title: "File")
        file.addItem(withTitle: "New Beat", action: #selector(fileNew), keyEquivalent: "n")
        file.addItem(withTitle: "Open…", action: #selector(fileOpen), keyEquivalent: "o")
        file.addItem(.separator())
        file.addItem(withTitle: "Save", action: #selector(fileSave), keyEquivalent: "s")
        file.addItem(withTitle: "Save As…", action: #selector(fileSaveAs), keyEquivalent: "S")
        file.addItem(.separator())
        file.addItem(withTitle: "Export…", action: #selector(fileExport), keyEquivalent: "e")
        fileItem.submenu = file

        let editItem = NSMenuItem()
        main.addItem(editItem)
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit

        let viewItem = NSMenuItem()
        main.addItem(viewItem)
        let view = NSMenu(title: "View")
        view.addItem(withTitle: "Reload", action: #selector(reload), keyEquivalent: "r")
        view.addItem(withTitle: "Enter Full Screen", action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f")
        viewItem.submenu = view

        let windowItem = NSMenuItem()
        main.addItem(windowItem)
        let win = NSMenu(title: "Window")
        win.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowItem.submenu = win
        NSApp.windowsMenu = win
        NSApp.mainMenu = main
    }

    @objc func reload() { webView.reload() }
    @objc func fileNew() { webView.evaluateJavaScript("projNew()") }
    @objc func fileOpen() { webView.evaluateJavaScript("projOpen()") }
    @objc func fileSave() { webView.evaluateJavaScript("projSave(false)") }
    @objc func fileSaveAs() { webView.evaluateJavaScript("projSave(true)") }
    @objc func fileExport() { webView.evaluateJavaScript("projExportShortcut()") }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
