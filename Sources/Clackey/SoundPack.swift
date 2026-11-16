import AVFoundation

/// What a key sounds like. Packs provide one or more audio files per category.
enum KeySound: String, CaseIterable {
    case down, up, space, back, `return`
    case mousedown, mouseup           // mouse buttons and trackpad clicks/taps

    var isMouse: Bool { self == .mousedown || self == .mouseup }

    /// Wide keys borrow the regular key sound when a pack has none of their own.
    var fallback: KeySound? {
        switch self {
        case .space, .back, .return: return .down
        default: return nil
        }
    }
}

/// One recorded keystroke, pre-rendered at a few slightly different pitches so playback
/// needs no real-time pitch shifting.
struct Sample {
    let pitched: [AVAudioPCMBuffer]
}

/// A folder of audio files named `<category>.wav` or `<category>-<n>.wav`
/// (e.g. `down-1.wav`, `down-2.wav`, `space.wav`, `mousedown-1.wav`). Missing wide-key
/// categories fall back to `down`; a missing `up` just means key releases are silent.
/// Packs without `mousedown`/`mouseup` use the shared built-in mouse sounds.
struct SoundPack {
    let name: String
    let samples: [KeySound: [Sample]]

    static let audioExtensions: Set<String> = ["wav", "aif", "aiff", "caf", "mp3", "m4a"]

    // Limits for untrusted user packs: keep memory bounded no matter what is dropped in.
    static let maxFileBytes = 10 * 1024 * 1024
    static let maxSeconds = 2.0
    static let maxFilesPerCategory = 16

    /// Playback rates baked in at load time (≈ ±3% pitch).
    static let pitchRates: [Double] = [0.97, 0.985, 1.0, 1.015, 1.03]

    static func category(forFileNamed file: String) -> KeySound? {
        let stem = (file as NSString).deletingPathExtension.lowercased()
        return KeySound.allCases.first { c in
            stem == c.rawValue || stem.hasPrefix(c.rawValue + "-") || stem.hasPrefix(c.rawValue + "_")
        }
    }

    init(url: URL, format: AVAudioFormat, requireKeys: Bool = true) throws {
        name = url.lastPathComponent
        let keys: [URLResourceKey] = [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
        let files = try FileManager.default.contentsOfDirectory(
            at: url, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])
            .filter { Self.audioExtensions.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        var samples: [KeySound: [Sample]] = [:]
        for file in files {
            guard let cat = Self.category(forFileNamed: file.lastPathComponent),
                  (samples[cat]?.count ?? 0) < Self.maxFilesPerCategory,
                  let v = try? file.resourceValues(forKeys: Set(keys)),
                  v.isRegularFile == true, v.isSymbolicLink != true,   // no symlinks out of the pack
                  (v.fileSize ?? .max) <= Self.maxFileBytes
            else { continue }
            let buffer = try loadBuffer(file, as: format, maxSeconds: Self.maxSeconds)
            let pitched = Self.pitchRates.compactMap { $0 == 1 ? buffer : resample(buffer, rate: $0) }
            samples[cat, default: []].append(Sample(pitched: pitched))
        }
        guard !requireKeys || samples[.down]?.isEmpty == false else {
            throw ClackeyError("Pack “\(name)” has no down.wav / down-1.wav")
        }
        self.samples = samples
    }
}

struct ClackeyError: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
}

/// Reads up to `maxSeconds` of an audio file into memory, converted to `format`
/// so every voice in the engine can share one connection format.
func loadBuffer(_ url: URL, as format: AVAudioFormat, maxSeconds: Double) throws -> AVAudioPCMBuffer {
    let file = try AVAudioFile(forReading: url)
    let src = file.processingFormat
    let frames = AVAudioFrameCount(min(Double(file.length), maxSeconds * src.sampleRate))
    guard frames > 0, let raw = AVAudioPCMBuffer(pcmFormat: src, frameCapacity: frames) else {
        throw ClackeyError("Could not read \(url.lastPathComponent)")
    }
    try file.read(into: raw, frameCount: frames)
    if src == format { return raw }

    guard let converter = AVAudioConverter(from: src, to: format) else {
        throw ClackeyError("Unsupported audio format in \(url.lastPathComponent)")
    }
    let capacity = AVAudioFrameCount(Double(raw.frameLength) * format.sampleRate / src.sampleRate) + 1024
    guard let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else {
        throw ClackeyError("Could not allocate buffer for \(url.lastPathComponent)")
    }
    var fed = false
    var error: NSError?
    converter.convert(to: out, error: &error) { _, status in
        if fed { status.pointee = .endOfStream; return nil }
        fed = true
        status.pointee = .haveData
        return raw
    }
    if let error { throw error }
    return out
}

/// Linear-interpolation resample: rate > 1 = shorter and higher-pitched.
func resample(_ buffer: AVAudioPCMBuffer, rate: Double) -> AVAudioPCMBuffer? {
    let n = Int(buffer.frameLength)
    let outN = Int(Double(n) / rate)
    guard n > 1, outN > 0,
          let src = buffer.floatChannelData,
          let out = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: AVAudioFrameCount(outN)),
          let dst = out.floatChannelData else { return nil }
    for ch in 0..<Int(buffer.format.channelCount) {
        let s = src[ch], d = dst[ch]
        for i in 0..<outN {
            let x = Double(i) * rate
            let i0 = min(Int(x), n - 1), i1 = min(i0 + 1, n - 1)
            let f = Float(x - Double(i0))
            d[i] = s[i0] + (s[i1] - s[i0]) * f
        }
    }
    out.frameLength = AVAudioFrameCount(outN)
    return out
}

/// Where packs live: built-in ones inside the app bundle, user ones in Application Support
/// (inside the app's sandbox container when sandboxed).
enum PackLibrary {
    /// Shared mouse-click sounds, used when a pack has none of its own.
    static var mouseSoundsURL: URL? {
        guard let url = Bundle.main.resourceURL?.appendingPathComponent("Mouse"),
              FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }

    static var userPacksURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Clackey/Packs", isDirectory: true)
    }

    static var builtInPacksURL: URL? {
        let fm = FileManager.default
        if let res = Bundle.main.resourceURL?.appendingPathComponent("Packs"), fm.fileExists(atPath: res.path) {
            return res
        }
        #if DEBUG
        // `swift run` from the repo root
        let dev = URL(fileURLWithPath: fm.currentDirectoryPath).appendingPathComponent("Resources/Packs")
        if fm.fileExists(atPath: dev.path) { return dev }
        #endif
        return nil
    }

    /// Pack folders, built-in first. A user pack with the same name as a built-in one wins.
    static func discover() -> [URL] {
        var byName: [String: URL] = [:]
        var order: [String] = []
        for root in [builtInPacksURL, userPacksURL].compactMap({ $0 }) {
            let dirs = (try? FileManager.default.contentsOfDirectory(
                at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? []
            for dir in dirs.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                guard (try? dir.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else { continue }
                let name = dir.lastPathComponent
                if byName[name] == nil { order.append(name) }
                byName[name] = dir
            }
        }
        return order.compactMap { byName[$0] }
    }
}
