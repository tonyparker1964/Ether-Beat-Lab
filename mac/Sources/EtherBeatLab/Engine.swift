import AppKit
import AVFoundation
import AudioToolbox
import CoreAudioKit
import CoreMIDI
import WebKit

/// Phase 2: the native side of the audio engine.
/// - Plug-ins: Audio Unit instruments (Kontakt, Massive, …) hosted in an AVAudioEngine, one per sound slot
///   (Chords A, Chords B, Melody, Bass), played by the sequencer and rendered offline for the export.
/// - MIDI: every connected MIDI keyboard or controller is passed to the page.
/// - Audio: the plug-ins' output device, and recording from an input when the page can't.
/// Everything runs on this Mac; nothing goes online.
/// Mirrors Apple's AUCocoaUIBase (the window factory older AUv2 plug-ins provide).
@objc protocol CocoaUIFactory {
    @objc(uiViewForAudioUnit:withSize:)
    func uiView(forAudioUnit unit: UnsafeMutableRawPointer, with size: NSSize) -> NSView?
}

final class Engine: NSObject {
    static let shared = Engine()
    weak var webView: WKWebView?

    static var rendersDir: URL { sub("Renders") }
    static var recordingsDir: URL { sub("Recordings") }
    private static func sub(_ name: String) -> URL {
        let d = AppFiles.dir.appendingPathComponent(name, isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    // MARK: Plug-ins

    struct Plugin: Encodable { var id: String; var name: String; var maker: String }

    private let engine = AVAudioEngine()
    private var slots: [String: AVAudioUnit] = [:]
    private var slotComp: [String: String] = [:]
    private var windows: [String: NSWindow] = [:]

    static func compID(_ d: AudioComponentDescription) -> String {
        String(format: "%08x-%08x-%08x", d.componentType, d.componentSubType, d.componentManufacturer)
    }
    static func desc(_ id: String) -> AudioComponentDescription? {
        let p = id.split(separator: "-").compactMap { UInt32($0, radix: 16) }
        guard p.count == 3 else { return nil }
        return AudioComponentDescription(componentType: p[0], componentSubType: p[1], componentManufacturer: p[2], componentFlags: 0, componentFlagsMask: 0)
    }

    /// Every instrument plug-in installed on this Mac.
    func plugins() -> [Plugin] {
        let all = AudioComponentDescription(componentType: kAudioUnitType_MusicDevice, componentSubType: 0, componentManufacturer: 0,
                                            componentFlags: 0, componentFlagsMask: 0)
        var found = AVAudioUnitComponentManager.shared().components(matching: all)
            .map { Plugin(id: Self.compID($0.audioComponentDescription), name: $0.name, maker: $0.manufacturerName) }
        // Also ask Core Audio directly, which sees every registered instrument (some older plug-ins only show up here).
        var desc = all
        var comp: AudioComponent? = AudioComponentFindNext(nil, &desc)
        while let c = comp {
            var d = AudioComponentDescription()
            if AudioComponentGetDescription(c, &d) == noErr {
                let id = Self.compID(d)
                if !found.contains(where: { $0.id == id }) {
                    var cfName: Unmanaged<CFString>?
                    var full = "Plug-in"
                    if AudioComponentCopyName(c, &cfName) == noErr, let cf = cfName?.takeRetainedValue() { full = cf as String }
                    let parts = full.components(separatedBy: ": ")
                    found.append(Plugin(id: id, name: parts.count > 1 ? parts.dropFirst().joined(separator: ": ") : full, maker: parts.count > 1 ? parts[0] : ""))
                }
            }
            comp = AudioComponentFindNext(c, &desc)
        }
        return found.sorted { ($0.maker, $0.name) < ($1.maker, $1.name) }
    }

    private func startEngine() {
        guard !engine.isRunning else { return }
        engine.prepare()
        try? engine.start()
    }

    /// Loads a plug-in into a slot (replacing what was there), optionally with a saved sound.
    func load(slot: String, comp: String, state: String?, done: @escaping (String?) -> Void) {
        if slotComp[slot] == comp, let unit = slots[slot] {
            if let state { Self.apply(state, to: unit) }
            return done(nil)
        }
        guard let d = Self.desc(comp) else { return done("That plug-in isn't installed.") }
        unload(slot: slot)
        AVAudioUnit.instantiate(with: d, options: []) { unit, error in
            DispatchQueue.main.async {
                guard let unit else { return done("The plug-in couldn't be opened: \(error?.localizedDescription ?? "unknown error")") }
                self.engine.attach(unit)
                self.engine.connect(unit, to: self.engine.mainMixerNode, format: nil)
                self.slots[slot] = unit
                self.slotComp[slot] = comp
                if let state { Self.apply(state, to: unit) }
                self.startEngine()
                done(nil)
            }
        }
    }

    func unload(slot: String) {
        windows[slot]?.close(); windows[slot] = nil
        guard let unit = slots[slot] else { return }
        allNotesOff(unit)
        engine.disconnectNodeOutput(unit)
        engine.detach(unit)
        slots[slot] = nil; slotComp[slot] = nil
    }

    /// A note from the sequencer, `delay` seconds from now (the page schedules a little ahead).
    func note(slot: String, note: Int, velocity: Int, delay: Double, length: Double) {
        guard let unit = slots[slot], let send = unit.auAudioUnit.scheduleMIDIEventBlock else { return }
        let sr = unit.outputFormat(forBus: 0).sampleRate > 0 ? unit.outputFormat(forBus: 0).sampleRate : 44100
        let ch = UInt8(0)
        let on = AUEventSampleTimeImmediate + AUEventSampleTime(max(0, delay) * sr)
        var a: [UInt8] = [0x90 | ch, UInt8(clamping: note), UInt8(clamping: max(1, min(127, velocity)))]
        send(on, 0, 3, &a)
        if length > 0 {
            let off = on + AUEventSampleTime(max(0.02, length) * sr)
            var b: [UInt8] = [0x80 | ch, UInt8(clamping: note), 0]
            send(off, 0, 3, &b)
        }
    }

    /// Live keys from a MIDI keyboard: note on now, note off later.
    func noteNow(slot: String, note: Int, velocity: Int) {
        guard let unit = slots[slot], let send = unit.auAudioUnit.scheduleMIDIEventBlock else { return }
        var a: [UInt8] = [velocity > 0 ? 0x90 : 0x80, UInt8(clamping: note), UInt8(clamping: max(0, min(127, velocity)))]
        send(AUEventSampleTimeImmediate, 0, 3, &a)
    }

    func allNotesOff(_ unit: AVAudioUnit? = nil) {
        let units = unit.map { [$0] } ?? Array(slots.values)
        for u in units {
            guard let send = u.auAudioUnit.scheduleMIDIEventBlock else { continue }
            var a: [UInt8] = [0xB0, 123, 0]
            send(AUEventSampleTimeImmediate, 0, 3, &a)
        }
    }

    func setVolume(_ v: Float) { engine.mainMixerNode.outputVolume = max(0, min(1.5, v)) }

    /// The plug-in's own window, where you pick its sound.
    func show(slot: String, title: String) {
        guard let unit = slots[slot] else { return }
        if let w = windows[slot] { w.makeKeyAndOrderFront(nil); return }
        unit.auAudioUnit.requestViewController { vc in
            DispatchQueue.main.async {
                var view: NSView? = vc?.view
                if view == nil { view = Self.cocoaView(unit) }
                guard let view else {
                    let a = NSAlert(); a.messageText = "\(title) doesn't have a window to show."; a.runModal(); return
                }
                let size = view.frame.size.width > 10 ? view.frame.size : NSSize(width: 640, height: 420)
                let w = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .closable, .miniaturizable],
                                 backing: .buffered, defer: false)
                w.title = title
                w.isReleasedWhenClosed = false
                if let vc { w.contentViewController = vc } else { w.contentView = view }
                w.center()
                w.makeKeyAndOrderFront(nil)
                self.windows[slot] = w
            }
        }
    }

    /// Older (AUv2) plug-ins give their window through the Cocoa UI property.
    private static func cocoaView(_ unit: AVAudioUnit) -> NSView? {
        let au = unit.audioUnit
        var size: UInt32 = 0
        var writable: DarwinBoolean = false
        guard AudioUnitGetPropertyInfo(au, kAudioUnitProperty_CocoaUI, kAudioUnitScope_Global, 0, &size, &writable) == noErr, size > 0 else { return nil }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioUnitCocoaViewInfo>.alignment)
        defer { raw.deallocate() }
        guard AudioUnitGetProperty(au, kAudioUnitProperty_CocoaUI, kAudioUnitScope_Global, 0, raw, &size) == noErr else { return nil }
        let info = raw.assumingMemoryBound(to: AudioUnitCocoaViewInfo.self).pointee
        let bundleURL = info.mCocoaAUViewBundleLocation.takeUnretainedValue() as URL
        let className = info.mCocoaAUViewClass.takeUnretainedValue() as String
        guard let bundle = Bundle(url: bundleURL), let cls = bundle.classNamed(className) as? NSObject.Type else { return nil }
        let factory = cls.init()
        let sel = NSSelectorFromString("uiViewForAudioUnit:withSize:")
        guard factory.responds(to: sel) else { return nil }
        // Apple's AUCocoaUIBase protocol isn't visible to Swift, so call its one method through the same selector.
        let ui = unsafeBitCast(factory, to: CocoaUIFactory.self)
        return ui.uiView(forAudioUnit: UnsafeMutableRawPointer(au), with: NSSize(width: 640, height: 420))
    }

    /// The plug-in's current sound, so a project can bring it back.
    func state(slot: String) -> String? {
        guard let unit = slots[slot], let full = unit.auAudioUnit.fullState,
              let data = try? PropertyListSerialization.data(fromPropertyList: full, format: .binary, options: 0) else { return nil }
        return data.base64EncodedString()
    }
    private static func apply(_ b64: String, to unit: AVAudioUnit) {
        guard let data = Data(base64Encoded: b64),
              let full = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { return }
        unit.auAudioUnit.fullState = full
    }

    /// Renders a slot's notes offline (faster than real time) into a WAV for the export.
    /// events: [[seconds, note, velocity, length]]
    func render(slot: String, events: [[Double]], seconds: Double, done: @escaping (String?, String?) -> Void) {
        guard let comp = slotComp[slot], let d = Self.desc(comp), let live = slots[slot] else { return done(nil, "No plug-in in that slot.") }
        let saved = live.auAudioUnit.fullState
        AVAudioUnit.instantiate(with: d, options: []) { unit, error in
            guard let unit else { return DispatchQueue.main.async { done(nil, error?.localizedDescription ?? "The plug-in couldn't be opened.") } }
            DispatchQueue.global(qos: .userInitiated).async {
                let sr = 44100.0
                let eng = AVAudioEngine()
                guard let fmt = AVAudioFormat(standardFormatWithSampleRate: sr, channels: 2) else { return DispatchQueue.main.async { done(nil, "Audio format error") } }
                do {
                    try eng.enableManualRenderingMode(.offline, format: fmt, maximumFrameCount: 1024)
                    eng.attach(unit)
                    eng.connect(unit, to: eng.mainMixerNode, format: fmt)
                    if let saved { unit.auAudioUnit.fullState = saved }
                    try eng.start()
                } catch { return DispatchQueue.main.async { done(nil, "Couldn't render the plug-in: \(error.localizedDescription)") } }
                // note on and note off messages, in sample time
                var msgs: [(Int64, [UInt8])] = []
                for e in events where e.count >= 4 {
                    let t = Int64(e[0] * sr), n = UInt8(clamping: Int(e[1])), v = UInt8(clamping: max(1, min(127, Int(e[2]))))
                    msgs.append((t, [0x90, n, v]))
                    msgs.append((t + Int64(max(0.02, e[3]) * sr), [0x80, n, 0]))
                }
                msgs.sort { $0.0 < $1.0 }
                let url = Self.rendersDir.appendingPathComponent("\(slot)-\(Int(Date().timeIntervalSince1970 * 1000)).wav")
                let settings: [String: Any] = [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: sr, AVNumberOfChannelsKey: 2,
                                               AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true]
                guard let file = try? AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false),
                      let buf = AVAudioPCMBuffer(pcmFormat: eng.manualRenderingFormat, frameCapacity: eng.manualRenderingMaximumFrameCount) else {
                    return DispatchQueue.main.async { done(nil, "Couldn't write the render.") }
                }
                let total = Int64((seconds + 2) * sr)
                var pos: Int64 = 0, k = 0
                let send = unit.auAudioUnit.scheduleMIDIEventBlock
                while pos < total {
                    let n = AVAudioFrameCount(min(Int64(eng.manualRenderingMaximumFrameCount), total - pos))
                    // events inside this block, at their exact sample
                    while k < msgs.count, msgs[k].0 < pos + Int64(n) {
                        var bytes = msgs[k].1
                        send?(AUEventSampleTimeImmediate + max(0, msgs[k].0 - pos), 0, 3, &bytes)
                        k += 1
                    }
                    guard (try? eng.renderOffline(n, to: buf)) == .success else { break }
                    try? file.write(from: buf)
                    pos += Int64(n)
                }
                eng.stop()
                DispatchQueue.main.async { done(url.path, nil) }
            }
        }
    }

    // MARK: Output device for the plug-ins

    struct Device: Encodable { var id: UInt32; var name: String; var current: Bool }

    func outputDevices() -> [Device] {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &ids) == noErr else { return [] }
        let current = engine.outputNode.auAudioUnit.deviceID
        return ids.compactMap { id -> Device? in
            var streams = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams, mScope: kAudioDevicePropertyScopeOutput,
                                                     mElement: kAudioObjectPropertyElementMain)
            var ss: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(id, &streams, 0, nil, &ss) == noErr, ss > 0 else { return nil }
            var nameAddr = AudioObjectPropertyAddress(mSelector: kAudioObjectPropertyName, mScope: kAudioObjectPropertyScopeGlobal,
                                                      mElement: kAudioObjectPropertyElementMain)
            var name: Unmanaged<CFString>?
            var ns = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            guard AudioObjectGetPropertyData(id, &nameAddr, 0, nil, &ns, &name) == noErr, let n = name?.takeRetainedValue() else { return nil }
            return Device(id: id, name: n as String, current: id == current)
        }
    }

    func setOutput(_ id: UInt32) -> String? {
        do { try engine.outputNode.auAudioUnit.setDeviceID(id); return nil }
        catch { return "Couldn't switch output: \(error.localizedDescription)" }
    }

    // MARK: Recording (when the page can't reach the microphone itself)

    private var recorder: AVAudioRecorder?

    func recordStart(done: @escaping (String?) -> Void) {
        AVCaptureDevice.requestAccess(for: .audio) { ok in
            DispatchQueue.main.async {
                guard ok else { return done("Beat Lab needs microphone access: System Settings → Privacy & Security → Microphone.") }
                let url = Self.recordingsDir.appendingPathComponent("rec-\(Int(Date().timeIntervalSince1970)).wav")
                let settings: [String: Any] = [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 44100.0, AVNumberOfChannelsKey: 2,
                                               AVLinearPCMBitDepthKey: 24, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false]
                do {
                    let r = try AVAudioRecorder(url: url, settings: settings)
                    guard r.record() else { return done("Recording couldn't start. Check the input in System Settings → Sound.") }
                    self.recorder = r
                    done(nil)
                } catch { done("Recording couldn't start: \(error.localizedDescription)") }
            }
        }
    }

    func recordStop() -> String? {
        guard let r = recorder else { return nil }
        r.stop(); recorder = nil
        return r.url.path
    }

    // MARK: MIDI in

    private var client = MIDIClientRef()
    private var port = MIDIPortRef()
    private(set) var midiNames: [String] = []

    func startMIDI() {
        guard client == 0 else { return }
        MIDIClientCreateWithBlock("Ether Beat Lab" as CFString, &client) { [weak self] note in
            if note.pointee.messageID == .msgSetupChanged { DispatchQueue.main.async { self?.connectSources() } }
        }
        MIDIInputPortCreateWithBlock(client, "Input" as CFString, &port) { [weak self] list, _ in
            self?.receive(list)
        }
        connectSources()
    }

    private func connectSources() {
        var names: [String] = []
        for i in 0..<MIDIGetNumberOfSources() {
            let src = MIDIGetSource(i)
            MIDIPortConnectSource(port, src, nil)
            var name: Unmanaged<CFString>?
            if MIDIObjectGetStringProperty(src, kMIDIPropertyDisplayName, &name) == noErr, let n = name?.takeRetainedValue() { names.append(n as String) }
        }
        midiNames = names
        send("midiDevices(\(Self.jsonString(names)))")
    }

    private func receive(_ list: UnsafePointer<MIDIPacketList>) {
        var out: [[Int]] = []
        let count = Int(list.pointee.numPackets)
        let first = UnsafeRawPointer(list) + MemoryLayout<MIDIPacketList>.offset(of: \MIDIPacketList.packet)!
        var p = first.assumingMemoryBound(to: MIDIPacket.self)
        let dataOffset = MemoryLayout<MIDIPacket>.offset(of: \MIDIPacket.data)!
        for _ in 0..<count {
            let len = Int(p.pointee.length)
            let bytes = (UnsafeRawPointer(p) + dataOffset).assumingMemoryBound(to: UInt8.self)
            var i = 0
            while i < len {
                let st = Int(bytes[i])
                if st & 0x80 == 0 { i += 1; continue }
                let kind = st & 0xF0
                let size = (kind == 0xC0 || kind == 0xD0) ? 2 : (st >= 0xF0 ? 1 : 3)
                if st < 0xF0, i + size <= len { out.append([st, size > 1 ? Int(bytes[i + 1]) : 0, size > 2 ? Int(bytes[i + 2]) : 0]) }
                i += size
            }
            p = UnsafePointer(MIDIPacketNext(p))
        }
        guard !out.isEmpty else { return }
        let js = out.map { "midiIn(\($0[0]),\($0[1]),\($0[2]))" }.joined(separator: ";")
        DispatchQueue.main.async { self.send(js) }
    }

    private func send(_ js: String) {
        webView?.evaluateJavaScript("try{\(js)}catch(e){}", completionHandler: nil)
    }

    static func jsonString(_ v: Any) -> String {
        guard let d = try? JSONSerialization.data(withJSONObject: v, options: [.fragmentsAllowed]) else { return "null" }
        return String(data: d, encoding: .utf8) ?? "null"
    }

    // MARK: Bridge

    /// Requests from the page that belong to the engine. Returns false when the action isn't one of these.
    func handle(_ action: String, _ body: [String: Any], reply: @escaping (Any?, String?) -> Void) -> Bool {
        let enc = { (v: Any) in reply(Self.jsonString(v), nil) }
        let result = { (err: String?) -> [String: Any] in err.map { ["error": $0] as [String: Any] } ?? ["ok": true] }
        switch action {
        case "auList":
            DispatchQueue.global(qos: .userInitiated).async {
                let list = self.plugins()
                let text = (try? JSONEncoder().encode(list)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
                DispatchQueue.main.async { reply(text, nil) }
            }
        case "auLoad":
            load(slot: body["slot"] as? String ?? "", comp: body["comp"] as? String ?? "", state: body["state"] as? String) { err in
                enc(result(err))
            }
        case "auUnload":
            unload(slot: body["slot"] as? String ?? ""); enc(["ok": true])
        case "auNote":
            note(slot: body["slot"] as? String ?? "", note: (body["n"] as? NSNumber)?.intValue ?? 60,
                 velocity: (body["v"] as? NSNumber)?.intValue ?? 100, delay: (body["delay"] as? NSNumber)?.doubleValue ?? 0,
                 length: (body["len"] as? NSNumber)?.doubleValue ?? 0.3)
            reply("{}", nil)
        case "auNoteNow":
            noteNow(slot: body["slot"] as? String ?? "", note: (body["n"] as? NSNumber)?.intValue ?? 60, velocity: (body["v"] as? NSNumber)?.intValue ?? 0)
            reply("{}", nil)
        case "auPanic":
            allNotesOff(); reply("{}", nil)
        case "auShow":
            show(slot: body["slot"] as? String ?? "", title: body["title"] as? String ?? "Plug-in"); reply("{}", nil)
        case "auState":
            enc(["state": state(slot: body["slot"] as? String ?? "") ?? ""])
        case "auVolume":
            setVolume((body["v"] as? NSNumber)?.floatValue ?? 1); reply("{}", nil)
        case "auRender":
            let events = (body["events"] as? [[Any]] ?? []).map { $0.compactMap { ($0 as? NSNumber)?.doubleValue } }
            render(slot: body["slot"] as? String ?? "", events: events, seconds: (body["seconds"] as? NSNumber)?.doubleValue ?? 10) { path, err in
                enc(path.map { ["path": $0] as [String: Any] } ?? ["error": err ?? "Render failed"])
            }
        case "audioDevices":
            enc(outputDevices().map { ["id": $0.id, "name": $0.name, "current": $0.current] as [String: Any] })
        case "audioOutput":
            enc(result(setOutput(UInt32((body["id"] as? NSNumber)?.intValue ?? 0))))
        case "midiDevices":
            startMIDI(); enc(midiNames)
        case "recStart":
            recordStart { err in enc(result(err)) }
        case "recStop":
            enc(recordStop().map { ["path": $0] as [String: Any] } ?? ["error": "Nothing was recorded."])
        default:
            return false
        }
        return true
    }
}
