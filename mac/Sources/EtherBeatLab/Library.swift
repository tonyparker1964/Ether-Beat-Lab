import Foundation

/// One drum one-shot.
struct DrumFile: Codable {
    var path: String
    var name: String
    var role: String
    var kit: String
}

/// One note of a playable instrument: the file and the MIDI note it was recorded at (C3 = 60, as NI names them).
struct Zone: Codable {
    var path: String
    var root: Int
}

/// A playable instrument made of one or more notes, like "Velvet Rhodes" from an expansion.
struct Instrument: Codable {
    var id: String
    var name: String
    var kit: String
    var category: String
    var zones: [Zone]
}

/// Everything usable found on the drives the person chose. Saved so the next launch doesn't rescan.
struct LibraryIndex: Codable {
    var roots: [String] = []
    var drums: [DrumFile] = []
    var instruments: [Instrument] = []
    var locked = 0
    var scannedAt = Date()

    var allowedPaths: Set<String> {
        Set(drums.map(\.path) + instruments.flatMap { $0.zones.map(\.path) })
    }
}

enum LibraryScanner {
    /// caf: Logic Pro's sound library (Drum Machine Designer, Drum Kit Designer and Sampler instruments) uses Core Audio files.
    static let audioExtensions: Set<String> = ["wav", "wave", "aif", "aiff", "flac", "caf"]
    /// Native Instruments' locked containers (Kontakt and others). They only play inside NI's own plug-ins.
    static let lockedExtensions: Set<String> = ["ncw", "nkx", "nkc", "nkr", "nicnt"]

    static func scan(roots: [URL]) -> LibraryIndex {
        var drums: [DrumFile] = []
        var groups: [String: Instrument] = [:]
        var locked = 0
        let fm = FileManager.default
        // Logic keeps its sounds inside a package ("Logic Pro Library.bundle"); look inside sound library packages too.
        var queue = roots
        var seen = Set<String>()
        while !queue.isEmpty {
            let root = queue.removeFirst()
            guard seen.insert(root.standardizedFileURL.path).inserted else { continue }
            let rootPath = root.standardizedFileURL.path
            guard let walker = fm.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
                                             options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }
            for case let url as URL in walker {
                let ext = url.pathExtension.lowercased()
                if ext == "bundle", url.lastPathComponent.lowercased().contains("library") { queue.append(url); continue }
                if lockedExtensions.contains(ext) { locked += 1; continue }
                guard audioExtensions.contains(ext), !url.lastPathComponent.hasPrefix("._") else { continue }
                let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
                if values?.isRegularFile == false { continue }
                if let size = values?.fileSize, size > 60_000_000 { continue }
                let full = url.standardizedFileURL.path
                let relative = full.hasPrefix(rootPath + "/") ? String(full.dropFirst(rootPath.count + 1)) : url.lastPathComponent
                let parts = relative.split(separator: "/").map(String.init)
                let allTokens = Set(parts.flatMap { tokens($0) })
                if !allTokens.isDisjoint(with: skipWords) { continue }
                let kit = group(parts, rootName: root.lastPathComponent)
                let stem = (url.lastPathComponent as NSString).deletingPathExtension

                let (noteInName, _) = noteAndBase(stem)
                if !allTokens.isDisjoint(with: vocalWords), noteInName == nil {
                    drums.append(DrumFile(path: full, name: stem, role: "vocal", kit: kit))
                    continue
                }
                if let role = drumRole(parts) {
                    drums.append(DrumFile(path: full, name: stem, role: role, kit: kit))
                    continue
                }
                guard let category = melodicCategory(parts) else { continue }
                let (note, base) = noteAndBase(stem)
                let folder = parts.count > 1 ? parts[parts.count - 2] : kit
                let name = base.isEmpty ? folder : base
                let key = kit + "|" + folder + "|" + name.lowercased()
                var inst = groups[key] ?? Instrument(id: stableID(key), name: name, kit: kit, category: category, zones: [])
                inst.zones.append(Zone(path: full, root: note ?? 60))
                groups[key] = inst
            }
        }
        // Ids come from the kit, folder and name, so they stay the same after a rescan.
        var instruments = Array(groups.values)
        for i in instruments.indices { instruments[i].zones.sort { $0.root < $1.root } }
        instruments.sort { ($0.kit, $0.name) < ($1.kit, $1.name) }
        drums.sort { $0.path < $1.path }
        return LibraryIndex(roots: roots.map { $0.standardizedFileURL.path }, drums: drums, instruments: instruments,
                            locked: locked, scannedAt: Date())
    }

    static func stableID(_ s: String) -> String {
        var h: UInt64 = 0xcbf29ce484222325
        for b in s.utf8 { h ^= UInt64(b); h = h &* 0x100000001b3 }
        return String(h, radix: 36)
    }

    /// Lowercase words, split at punctuation, letter/digit changes and camelCase.
    static func tokens(_ text: String) -> [String] {
        var out: [String] = []
        var current = ""
        var lastKind = 0
        var lastWasLower = false
        for ch in text {
            let kind = ch.isLetter ? 1 : (ch.isNumber ? 2 : 0)
            let breakHere = kind == 0 || (kind != lastKind && !current.isEmpty) || (kind == 1 && ch.isUppercase && lastWasLower)
            if breakHere, !current.isEmpty {
                out.append(current.lowercased())
                current = ""
            }
            if kind != 0 { current.append(ch) }
            lastKind = kind
            lastWasLower = ch.isLetter && ch.isLowercase
        }
        if !current.isEmpty { out.append(current.lowercased()) }
        return out
    }

    static let skipWords: Set<String> = ["loop", "loops", "bpm", "fx", "sfx", "riser", "risers", "impact", "impacts", "speech",
                                         "phrase", "phrases", "texture", "textures", "stem", "stems", "sweep", "sweeps", "downlifter"]
    static let vocalWords: Set<String> = ["vox", "vocal", "vocals", "voice", "voices", "choir", "choirs", "chant", "chants", "ooh", "aah", "ahh", "adlib", "adlibs"]
    static let kickWords: Set<String> = ["kick", "kicks", "kik", "bd", "bassdrum", "kck"]
    static let hatWords: Set<String> = ["hat", "hats", "hihat", "hihats", "hh", "chh", "ohh", "closedhat", "openhat", "hhc", "hho"]
    static let openWords: Set<String> = ["open", "ohh", "openhat", "hho", "oh"]
    static let clapWords: Set<String> = ["clap", "claps", "clp"]
    static let snapWords: Set<String> = ["snap", "snaps", "finger", "fingers"]
    static let rimWords: Set<String> = ["rim", "rims", "rimshot", "rimshots", "sidestick", "stick"]
    static let snareWords: Set<String> = ["snare", "snares", "snr", "sd"]
    static let rideWords: Set<String> = ["ride", "rides"]
    static let crashWords: Set<String> = ["crash", "crashes", "cymbal", "cymbals", "cym", "splash", "china"]
    static let shakerWords: Set<String> = ["shaker", "shakers", "tamb", "tambourine", "tambourines", "cabasa", "maraca", "maracas"]
    static let tomWords: Set<String> = ["tom", "toms"]
    static let percWords: Set<String> = ["perc", "percs", "percussion", "conga", "congas", "bongo", "bongos", "cowbell", "clave", "claves",
                                         "block", "guiro", "triangle", "timbale", "timbales", "agogo", "djembe", "tabla", "woodblock"]

    static let categories: [(String, Set<String>)] = [
        ("bass", ["bass", "basses", "bassline", "808", "sub", "subs", "reese"]),
        ("organ", ["organ", "organs", "hammond", "b3"]),
        ("keys", ["piano", "pianos", "keys", "key", "rhodes", "epiano", "ep", "wurli", "wurlitzer", "clav", "clavinet"]),
        ("voice", ["choir", "choirs", "voice", "voices", "vocal", "vocals", "vox"]),
        ("lead", ["lead", "leads", "mono"]),
        ("pad", ["pad", "pads", "drone", "drones", "atmos", "ambient"]),
        ("pluck", ["pluck", "plucks"]),
        ("bell", ["bell", "bells", "mallet", "mallets", "marimba", "vibes", "vibraphone", "kalimba", "glock", "glockenspiel", "celesta", "xylophone"]),
        ("strings", ["string", "strings", "violin", "violins", "cello", "cellos", "viola", "orchestra", "orchestral", "harp"]),
        ("brass", ["brass", "horn", "horns", "trumpet", "trumpets", "sax", "saxophone", "trombone", "flute", "woodwind", "woodwinds", "clarinet"]),
        ("guitar", ["guitar", "guitars", "gtr"]),
        ("synth", ["synth", "synths", "saw", "square", "poly", "arp", "chord", "chords", "stab", "stabs"])
    ]

    /// Drum role from the file name first, then the nearest folder that says.
    static func drumRole(_ parts: [String]) -> String? {
        guard let file = parts.last else { return nil }
        let nameTokens = tokens((file as NSString).deletingPathExtension)
        var role = drumRole(tokens: nameTokens)
        if role == nil {
            for folder in parts.dropLast().reversed() {
                // A melodic folder ("Instruments/Bass") means this isn't a drum.
                if melodicCategory(tokens: tokens(folder)) != nil { return nil }
                if let r = drumRole(tokens: tokens(folder)) { role = r; break }
            }
        }
        if role == "closedHat" {
            let nearby = Set(nameTokens + (parts.count > 1 ? tokens(parts[parts.count - 2]) : []))
            if !nearby.isDisjoint(with: openWords) { role = "openHat" }
        }
        return role
    }

    static func drumRole(tokens t: [String]) -> String? {
        let s = Set(t)
        if !s.isDisjoint(with: kickWords) || (s.contains("bass") && s.contains("drum")) { return "kick" }
        if !s.isDisjoint(with: hatWords) || (s.contains("hi") && s.contains("hat")) { return s.isDisjoint(with: openWords) ? "closedHat" : "openHat" }
        if !s.isDisjoint(with: clapWords) { return "clap" }
        if !s.isDisjoint(with: snareWords) { return "snare" }
        if !s.isDisjoint(with: rimWords) { return "rim" }
        if !s.isDisjoint(with: snapWords) { return "snap" }
        if !s.isDisjoint(with: rideWords) { return "ride" }
        if !s.isDisjoint(with: crashWords) { return "crash" }
        if !s.isDisjoint(with: tomWords) { return "tom" }
        if !s.isDisjoint(with: shakerWords) { return "shaker" }
        if !s.isDisjoint(with: percWords) { return "perc" }
        return nil
    }

    static func melodicCategory(_ parts: [String]) -> String? {
        if let file = parts.last, let c = melodicCategory(tokens: tokens((file as NSString).deletingPathExtension)) { return c }
        for folder in parts.dropLast().reversed() {
            if let c = melodicCategory(tokens: tokens(folder)) { return c }
        }
        return nil
    }

    static func melodicCategory(tokens t: [String]) -> String? {
        let s = Set(t)
        for (name, words) in categories where !s.isDisjoint(with: words) { return name }
        return nil
    }

    static let containerFolders: Set<String> = ["samples", "sample", "drums", "drum", "one shots", "oneshots", "one-shots",
                                                "sounds", "kits", "kit", "instruments", "instrument", "audio"]

    /// The kit or expansion: the folder just above "Samples" (or "Drums"), otherwise the first folder.
    static func group(_ parts: [String], rootName: String) -> String {
        let folders = Array(parts.dropLast())
        if let i = folders.firstIndex(where: { containerFolders.contains($0.lowercased()) }) {
            return i > 0 ? folders[i - 1] : rootName
        }
        return folders.first ?? rootName
    }

    static let noteRegex = try? NSRegularExpression(pattern: "(?:^|[ _\\-])([A-Ga-g])([#b]?)(-?[0-9])(?=$|[ _\\-])")

    /// The note in a file name ("Velvet Rhodes C#3" → 61) and the name without it ("Velvet Rhodes").
    static func noteAndBase(_ stem: String) -> (Int?, String) {
        guard let re = noteRegex else { return (nil, stem) }
        let ns = stem as NSString
        let matches = re.matches(in: stem, range: NSRange(location: 0, length: ns.length))
        guard let m = matches.last else { return (nil, stem.trimmingCharacters(in: .whitespaces)) }
        let letter = ns.substring(with: m.range(at: 1)).uppercased()
        let accidental = ns.substring(with: m.range(at: 2))
        let octave = Int(ns.substring(with: m.range(at: 3))) ?? 3
        let pcs: [String: Int] = ["C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11]
        var pc = pcs[letter] ?? 0
        if accidental == "#" { pc += 1 }
        if accidental == "b" { pc -= 1 }
        let midi = (octave + 2) * 12 + pc
        var base = ns.replacingCharacters(in: m.range, with: " ")
        base = base.components(separatedBy: CharacterSet(charactersIn: " _-")).filter { !$0.isEmpty }.joined(separator: " ")
        return (min(127, max(0, midi)), base)
    }
}
