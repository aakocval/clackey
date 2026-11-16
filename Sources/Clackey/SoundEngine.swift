import AudioToolbox
import AVFoundation

/// Low-latency polyphonic sample player.
///
///   16 × AVAudioPlayerNode ─▶ voice mixer ─▶ tone EQ ─▶ main mixer ─▶ output (128-frame buffer)
///
/// Voices are allocated round-robin so fast typing overlaps instead of cutting off. Pitch
/// variation is pre-rendered (see `SoundPack.pitchRates`), so the render thread only mixes.
/// The engine pauses itself after a short idle period and resumes on the next key.
@MainActor
final class SoundEngine {
    static let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
    static let ioBufferFrames: UInt32 = 128          // ≈ 3 ms at 44.1/48 kHz
    static let idleSeconds: TimeInterval = 30

    private let engine = AVAudioEngine()
    private let voiceMixer = AVAudioMixerNode()
    private let eq = AVAudioUnitEQ(numberOfBands: 2)
    private var players: [AVAudioPlayerNode] = []
    private var nextVoice = 0
    private var pack: SoundPack?
    /// Shared mouse sounds, used when the pack has no mousedown/mouseup of its own.
    var mouseSounds: SoundPack?
    private var lastVariant: [KeySound: Int] = [:]
    private var enabled = true
    private var lastPlay = Date.distantPast
    private var idleTimer: Timer?

    /// How far left/right keys are panned (0 = mono, 1 = hard left/right).
    var spatialWidth: Float = 0.6

    var volume: Float {
        get { engine.mainMixerNode.outputVolume }
        set { engine.mainMixerNode.outputVolume = max(0, min(1, newValue)) }
    }

    /// -1 = deep/thocky, 0 = as recorded, +1 = bright/clacky.
    var tone: Float = 0 {
        didSet {
            let t = max(-1, min(1, tone))
            eq.bands[0].gain = -4 * t      // low shelf
            eq.bands[1].gain = 6 * t       // high shelf
        }
    }

    init(voiceCount: Int = 16) throws {
        let low = eq.bands[0], high = eq.bands[1]
        low.filterType = .lowShelf;  low.frequency = 250;  low.gain = 0; low.bypass = false
        high.filterType = .highShelf; high.frequency = 3000; high.gain = 0; high.bypass = false

        engine.attach(voiceMixer)
        engine.attach(eq)
        let stereo = AVAudioFormat(standardFormatWithSampleRate: Self.format.sampleRate, channels: 2)!
        engine.connect(voiceMixer, to: eq, format: stereo)
        engine.connect(eq, to: engine.mainMixerNode, format: stereo)
        for _ in 0..<voiceCount {
            let p = AVAudioPlayerNode()
            engine.attach(p)
            engine.connect(p, to: voiceMixer, format: Self.format)   // mono in; .pan places it
            players.append(p)
        }
        engine.prepare()
        try start()

        // Output device changed (headphones, AirPods, display audio): the engine stops itself.
        NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.enabled else { return }
                try? self.start()
            }
        }
        idleTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.engine.isRunning,
                      Date().timeIntervalSince(self.lastPlay) > Self.idleSeconds else { return }
                self.engine.pause()     // no render callbacks while nobody is typing
            }
        }
    }

    private func start() throws {
        if !engine.isRunning {
            setLowLatencyBuffer()
            try engine.start()
        }
        for p in players where !p.isPlaying { p.play() }
    }

    /// Ask the output device for a small I/O buffer so a keypress reaches the speaker fast.
    private func setLowLatencyBuffer() {
        guard let unit = engine.outputNode.audioUnit else { return }
        var frames = Self.ioBufferFrames
        AudioUnitSetProperty(unit, kAudioDevicePropertyBufferFrameSize, kAudioUnitScope_Global, 0,
                             &frames, UInt32(MemoryLayout<UInt32>.size))
    }

    /// Off releases the audio hardware entirely.
    func setEnabled(_ on: Bool) {
        enabled = on
        if on { try? start() } else { engine.stop() }
    }

    func load(_ pack: SoundPack) {
        self.pack = pack
        lastVariant = [:]
    }

    /// - Parameter pan: -1 (left) … +1 (right), scaled by `spatialWidth`.
    func play(_ sound: KeySound, pan: Float = 0) {
        guard enabled, let pack else { return }
        let options = pack.samples[sound]
            ?? (sound.isMouse ? mouseSounds?.samples[sound] : nil)
            ?? sound.fallback.flatMap { pack.samples[$0] }
        guard let options, !options.isEmpty else { return }

        // Random variant, never the same one twice in a row.
        var i = Int.random(in: 0..<options.count)
        if options.count > 1, i == lastVariant[sound] { i = (i + 1) % options.count }
        lastVariant[sound] = i
        guard let buffer = options[i].pitched.randomElement() else { return }

        lastPlay = Date()
        if !engine.isRunning { try? start() }
        let player = players[nextVoice]
        nextVoice = (nextVoice + 1) % players.count
        player.volume = Float.random(in: 0.8...1.0)
        player.pan = max(-1, min(1, pan * spatialWidth))
        // .interrupts: if this voice is still ringing from 16 presses ago, cut it and reuse.
        player.scheduleBuffer(buffer, at: nil, options: .interrupts, completionHandler: nil)
        if !player.isPlaying { player.play() }
    }
}
