import Accelerate
import AVFoundation
import Foundation

/// Cole's sound engine: audio as plain arrays of samples, with the effects, measurements and edits an audio editor
/// needs. Everything works on this Mac, offline, and is tested without the app.

/// Samples, one array per channel, at a sample rate.
struct SoundBuffer: Equatable, Sendable {
    var sampleRate: Double
    var channels: [[Float]]

    init(sampleRate: Double, channels: [[Float]]) {
        self.sampleRate = sampleRate
        self.channels = channels
    }

    init(sampleRate: Double, channelCount: Int, frames: Int) {
        self.init(sampleRate: sampleRate, channels: Array(repeating: [Float](repeating: 0, count: frames), count: max(1, channelCount)))
    }

    var frames: Int { channels.first?.count ?? 0 }
    var duration: Double { sampleRate > 0 ? Double(frames) / sampleRate : 0 }
    var channelCount: Int { channels.count }

    func frame(at seconds: Double) -> Int { max(0, min(frames, Int((seconds * sampleRate).rounded()))) }

    /// A slice, in seconds.
    func slice(_ start: Double, _ end: Double) -> SoundBuffer {
        let a = frame(at: start), b = max(a, frame(at: end))
        return SoundBuffer(sampleRate: sampleRate, channels: channels.map { Array($0[a..<b]) })
    }

    /// The same sound with a set number of channels (mono is copied to both sides; stereo is averaged down).
    func withChannels(_ count: Int) -> SoundBuffer {
        if count == channelCount { return self }
        if channelCount == 1 { return SoundBuffer(sampleRate: sampleRate, channels: Array(repeating: channels[0], count: count)) }
        if count == 1 {
            var sum = [Float](repeating: 0, count: frames)
            for channel in channels { sum = vDSP.add(sum, channel) }
            return SoundBuffer(sampleRate: sampleRate, channels: [vDSP.multiply(1 / Float(channelCount), sum)])
        }
        return SoundBuffer(sampleRate: sampleRate, channels: (0..<count).map { channels[min($0, channelCount - 1)] })
    }

    /// Linear-interpolated resample, good enough for editing (exports keep the project rate).
    func resampled(to rate: Double) -> SoundBuffer {
        guard rate != sampleRate, rate > 0, frames > 1 else { return SoundBuffer(sampleRate: rate, channels: channels) }
        let count = max(1, Int((Double(frames) * rate / sampleRate).rounded()))
        let step = sampleRate / rate
        let resampledChannels = channels.map { channel -> [Float] in
            var output = [Float](repeating: 0, count: count)
            for index in 0..<count {
                let position = Double(index) * step
                let base = min(Int(position), channel.count - 1)
                let next = min(base + 1, channel.count - 1)
                let fraction = Float(position - Double(base))
                output[index] = channel[base] + (channel[next] - channel[base]) * fraction
            }
            return output
        }
        return SoundBuffer(sampleRate: rate, channels: resampledChannels)
    }

    static func silence(seconds: Double, sampleRate: Double = 48_000, channels: Int = 2) -> SoundBuffer {
        SoundBuffer(sampleRate: sampleRate, channelCount: channels, frames: Int(seconds * sampleRate))
    }

    /// A sine tone, for tests and the sample project.
    static func tone(_ frequency: Double, seconds: Double, amplitude: Float = 0.5, sampleRate: Double = 48_000, channels: Int = 1) -> SoundBuffer {
        let count = Int(seconds * sampleRate)
        var samples = [Float](repeating: 0, count: count)
        for index in 0..<count { samples[index] = amplitude * Float(sin(2 * .pi * frequency * Double(index) / sampleRate)) }
        return SoundBuffer(sampleRate: sampleRate, channels: Array(repeating: samples, count: channels))
    }

    mutating func append(_ other: SoundBuffer) {
        let other = other.sampleRate == sampleRate ? other : other.resampled(to: sampleRate)
        let matched = other.withChannels(channelCount)
        for index in channels.indices { channels[index] += matched.channels[index] }
    }
}

// MARK: Files

enum SoundFormat: String, CaseIterable, Identifiable, Sendable {
    case wav, aiff, m4a, flac, caf

    var id: String { rawValue }

    var title: String {
        switch self {
        case .wav: return "WAV · 24-bit"
        case .aiff: return "AIFF · 24-bit"
        case .m4a: return "M4A · AAC 256 kbps"
        case .flac: return "FLAC · lossless"
        case .caf: return "CAF · 32-bit float"
        }
    }

    var fileExtension: String { rawValue }

    func settings(sampleRate: Double, channels: Int) -> [String: Any] {
        var settings: [String: Any] = [AVSampleRateKey: sampleRate, AVNumberOfChannelsKey: channels]
        switch self {
        case .wav, .aiff:
            settings[AVFormatIDKey] = kAudioFormatLinearPCM
            settings[AVLinearPCMBitDepthKey] = 24
            settings[AVLinearPCMIsFloatKey] = false
            settings[AVLinearPCMIsBigEndianKey] = self == .aiff
            settings[AVLinearPCMIsNonInterleaved] = false
        case .caf:
            settings[AVFormatIDKey] = kAudioFormatLinearPCM
            settings[AVLinearPCMBitDepthKey] = 32
            settings[AVLinearPCMIsFloatKey] = true
            settings[AVLinearPCMIsBigEndianKey] = false
            settings[AVLinearPCMIsNonInterleaved] = false
        case .m4a:
            settings[AVFormatIDKey] = kAudioFormatMPEG4AAC
            settings[AVEncoderBitRateKey] = 256_000 * channels / 2
        case .flac:
            settings[AVFormatIDKey] = kAudioFormatFLAC
            settings[AVEncoderBitDepthHintKey] = 24
        }
        return settings
    }
}

enum SoundIOError: LocalizedError {
    case unreadable, unwritable

    var errorDescription: String? {
        switch self {
        case .unreadable: return "That sound file couldn't be read."
        case .unwritable: return "That sound file couldn't be written."
        }
    }
}

enum SoundIO {
    /// Any file AVFoundation reads: WAV, AIFF, CAF, M4A, MP3, FLAC, and the sound from video files.
    static func read(_ url: URL) throws -> SoundBuffer {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let frames = AVAudioFrameCount(file.length)
        guard frames > 0 else { return SoundBuffer(sampleRate: format.sampleRate, channelCount: Int(format.channelCount), frames: 0) }
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { throw SoundIOError.unreadable }
        try file.read(into: buffer)
        return sound(from: buffer)
    }

    static func sound(from buffer: AVAudioPCMBuffer) -> SoundBuffer {
        let count = Int(buffer.frameLength)
        let channels = Int(buffer.format.channelCount)
        var result: [[Float]] = []
        if let data = buffer.floatChannelData {
            if buffer.format.isInterleaved {
                let interleaved = UnsafeBufferPointer(start: data[0], count: count * channels)
                for channel in 0..<channels { result.append(stride(from: channel, to: count * channels, by: channels).map { interleaved[$0] }) }
            } else {
                for channel in 0..<channels { result.append(Array(UnsafeBufferPointer(start: data[channel], count: count))) }
            }
        } else if let data = buffer.int16ChannelData {
            for channel in 0..<channels {
                result.append(UnsafeBufferPointer(start: data[channel], count: count).map { Float($0) / 32_768 })
            }
        }
        return SoundBuffer(sampleRate: buffer.format.sampleRate, channels: result.isEmpty ? [[]] : result)
    }

    static func pcmBuffer(_ sound: SoundBuffer) -> AVAudioPCMBuffer? {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sound.sampleRate, channels: AVAudioChannelCount(sound.channelCount)),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(max(sound.frames, 1))),
              let data = buffer.floatChannelData else { return nil }
        buffer.frameLength = AVAudioFrameCount(sound.frames)
        for (index, channel) in sound.channels.enumerated() {
            channel.withUnsafeBufferPointer { source in
                if let base = source.baseAddress { data[index].update(from: base, count: sound.frames) }
            }
        }
        return buffer
    }

    static func write(_ sound: SoundBuffer, to url: URL, format: SoundFormat) throws {
        try? FileManager.default.removeItem(at: url)
        guard let buffer = pcmBuffer(sound) else { throw SoundIOError.unwritable }
        let file = try AVAudioFile(forWriting: url, settings: format.settings(sampleRate: sound.sampleRate, channels: sound.channelCount),
                                   commonFormat: .pcmFormatFloat32, interleaved: false)
        // Write in chunks so long recordings don't need one giant encode call.
        let chunk = 1 << 16
        var start = 0
        while start < sound.frames {
            let length = min(chunk, sound.frames - start)
            guard let piece = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: AVAudioFrameCount(length)),
                  let source = buffer.floatChannelData, let target = piece.floatChannelData else { throw SoundIOError.unwritable }
            piece.frameLength = AVAudioFrameCount(length)
            for channel in 0..<sound.channelCount { target[channel].update(from: source[channel] + start, count: length) }
            try file.write(from: piece)
            start += length
        }
    }
}

// MARK: Measuring

enum SoundMeter {
    static func decibels(_ amplitude: Float) -> Double { amplitude > 0 ? 20 * log10(Double(amplitude)) : -.infinity }
    static func amplitude(_ decibels: Double) -> Float { Float(pow(10, decibels / 20)) }

    static func peak(_ sound: SoundBuffer) -> Float {
        sound.channels.map { $0.isEmpty ? 0 : vDSP.maximumMagnitude($0) }.max() ?? 0
    }

    static func rms(_ samples: ArraySlice<Float>) -> Float {
        guard !samples.isEmpty else { return 0 }
        return samples.withUnsafeBufferPointer { vDSP.rootMeanSquare($0) }
    }

    /// Integrated loudness in LUFS (ITU-R BS.1770-4, EBU R 128): K-weighted, 400 ms blocks overlapping by 75%,
    /// gated at −70 LUFS and 10 LU below the ungated level.
    static func loudness(_ sound: SoundBuffer) -> Double {
        let weighted = sound.channels.map { kWeighted($0, sampleRate: sound.sampleRate) }
        let block = Int(0.4 * sound.sampleRate), hop = Int(0.1 * sound.sampleRate)
        guard block > 0, sound.frames >= block else { return -.infinity }
        var powers: [Double] = []
        var start = 0
        while start + block <= sound.frames {
            var sum = 0.0
            for channel in weighted {
                channel[start..<(start + block)].withUnsafeBufferPointer { sum += Double(vDSP.meanSquare($0)) }
            }
            powers.append(sum)
            start += hop
        }
        func lufs(_ power: Double) -> Double { -0.691 + 10 * log10(max(power, 1e-20)) }
        let absolute = powers.filter { lufs($0) > -70 }
        guard !absolute.isEmpty else { return -.infinity }
        let relativeGate = lufs(absolute.reduce(0, +) / Double(absolute.count)) - 10
        let gated = absolute.filter { lufs($0) > relativeGate }
        guard !gated.isEmpty else { return -.infinity }
        return lufs(gated.reduce(0, +) / Double(gated.count))
    }

    /// The two-stage K-weighting filter, with coefficients worked out for any sample rate (as libebur128 does).
    static func kWeighted(_ samples: [Float], sampleRate: Double) -> [Float] {
        var f0 = 1681.974450955533, gain = 3.999843853973347, q = 0.7071752369554196
        var k = tan(Double.pi * f0 / sampleRate)
        let vh = pow(10, gain / 20), vb = pow(vh, 0.4996667741545416)
        var a0 = 1 + k / q + k * k
        let shelf = Biquad(b0: (vh + vb * k / q + k * k) / a0, b1: 2 * (k * k - vh) / a0, b2: (vh - vb * k / q + k * k) / a0,
                           a1: 2 * (k * k - 1) / a0, a2: (1 - k / q + k * k) / a0)
        f0 = 38.13547087602444
        q = 0.5003270373238773
        gain = 0
        k = tan(Double.pi * f0 / sampleRate)
        a0 = 1 + k / q + k * k
        let highPass = Biquad(b0: 1, b1: -2, b2: 1, a1: 2 * (k * k - 1) / a0, a2: (1 - k / q + k * k) / a0)
        return highPass.process(shelf.process(samples))
    }

    /// Quiet stretches (below a level for at least a while), in seconds.
    static func silences(_ sound: SoundBuffer, threshold: Double = -42, minimum: Double = 0.6) -> [ClosedRange<Double>] {
        let window = max(1, Int(0.02 * sound.sampleRate))
        let level = amplitude(threshold)
        var ranges: [ClosedRange<Double>] = []
        var quietStart: Int?
        var index = 0
        while index < sound.frames {
            let end = min(index + window, sound.frames)
            let loudest = sound.channels.map { rms($0[index..<end]) }.max() ?? 0
            if loudest < level {
                if quietStart == nil { quietStart = index }
            } else if let start = quietStart {
                if Double(index - start) / sound.sampleRate >= minimum { ranges.append(Double(start) / sound.sampleRate...Double(index) / sound.sampleRate) }
                quietStart = nil
            }
            index = end
        }
        if let start = quietStart, Double(sound.frames - start) / sound.sampleRate >= minimum {
            ranges.append(Double(start) / sound.sampleRate...sound.duration)
        }
        return ranges
    }

    /// Where someone is talking: the gaps between silences, for ducking music.
    static func speech(_ sound: SoundBuffer, threshold: Double = -38, minimumGap: Double = 0.4) -> [ClosedRange<Double>] {
        let quiet = silences(sound, threshold: threshold, minimum: minimumGap)
        var spans: [ClosedRange<Double>] = []
        var cursor = 0.0
        for gap in quiet {
            if gap.lowerBound - cursor > 0.05 { spans.append(cursor...gap.lowerBound) }
            cursor = gap.upperBound
        }
        if sound.duration - cursor > 0.05 { spans.append(cursor...sound.duration) }
        return spans
    }

    /// Lowest and highest sample in each of `buckets` slices, for drawing a waveform.
    static func peaks(_ sound: SoundBuffer, buckets: Int) -> [(low: Float, high: Float)] {
        guard buckets > 0, sound.frames > 0 else { return [] }
        let mono = sound.channelCount == 1 ? sound.channels[0] : sound.withChannels(1).channels[0]
        let size = Double(sound.frames) / Double(buckets)
        return (0..<buckets).map { bucket -> (low: Float, high: Float) in
            let start = Int(Double(bucket) * size), end = max(start + 1, min(sound.frames, Int(Double(bucket + 1) * size)))
            guard start < sound.frames else { return (low: 0, high: 0) }
            let slice = mono[start..<end]
            let low = slice.withUnsafeBufferPointer { vDSP.minimum($0) }
            let high = slice.withUnsafeBufferPointer { vDSP.maximum($0) }
            return (low: low, high: high)
        }
    }

    /// Magnitudes in decibels per frequency bin, one column per hop.
    static func spectrogram(_ sound: SoundBuffer, size: Int = 1024, hop: Int = 512) -> [[Float]] {
        let log2n = vDSP_Length(log2(Double(size)).rounded())
        guard sound.frames >= size, let fft = vDSP.FFT(log2n: log2n, radix: .radix2, ofType: DSPSplitComplex.self) else { return [] }
        let mono = sound.withChannels(1).channels[0]
        let window = vDSP.window(ofType: Float.self, usingSequence: .hanningDenormalized, count: size, isHalfWindow: false)
        var columns: [[Float]] = []
        var start = 0
        var real = [Float](repeating: 0, count: size / 2), imaginary = [Float](repeating: 0, count: size / 2)
        var magnitudes = [Float](repeating: 0, count: size / 2)
        while start + size <= mono.count {
            let frame = vDSP.multiply(Array(mono[start..<(start + size)]), window)
            real.withUnsafeMutableBufferPointer { realPointer in
                imaginary.withUnsafeMutableBufferPointer { imaginaryPointer in
                    var split = DSPSplitComplex(realp: realPointer.baseAddress!, imagp: imaginaryPointer.baseAddress!)
                    frame.withUnsafeBufferPointer { pointer in
                        pointer.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: size / 2) { complex in
                            vDSP_ctoz(complex, 2, &split, 1, vDSP_Length(size / 2))
                        }
                    }
                    let input = split
                    fft.forward(input: input, output: &split)
                    magnitudes.withUnsafeMutableBufferPointer { output in
                        vDSP_zvabs(&split, 1, output.baseAddress!, 1, vDSP_Length(size / 2))
                    }
                }
            }
            columns.append(magnitudes.map { Float(20 * log10(Double(max($0, 1e-9)) / Double(size))) })
            start += hop
        }
        return columns
    }
}

// MARK: Filters

/// One biquad section (Robert Bristow-Johnson's cookbook), normalised so a0 is 1.
struct Biquad: Codable, Hashable, Sendable {
    var b0: Double, b1: Double, b2: Double, a1: Double, a2: Double

    init(b0: Double, b1: Double, b2: Double, a1: Double, a2: Double) {
        self.b0 = b0; self.b1 = b1; self.b2 = b2; self.a1 = a1; self.a2 = a2
    }

    enum Kind: String, Codable, CaseIterable, Identifiable, Sendable {
        case highPass, lowPass, peak, lowShelf, highShelf
        var id: String { rawValue }
        var title: String {
            switch self {
            case .highPass: return "High-pass"
            case .lowPass: return "Low-pass"
            case .peak: return "Bell"
            case .lowShelf: return "Low shelf"
            case .highShelf: return "High shelf"
            }
        }
    }

    init(_ kind: Kind, frequency: Double, gain: Double = 0, q: Double = 0.707, sampleRate: Double) {
        let w0 = 2 * Double.pi * min(frequency, sampleRate * 0.49) / sampleRate
        let cosine = cos(w0), alpha = sin(w0) / (2 * q)
        let a = pow(10, gain / 40)
        var b = (0.0, 0.0, 0.0), c = (1.0, 0.0, 0.0)
        switch kind {
        case .lowPass:
            b = ((1 - cosine) / 2, 1 - cosine, (1 - cosine) / 2)
            c = (1 + alpha, -2 * cosine, 1 - alpha)
        case .highPass:
            b = ((1 + cosine) / 2, -(1 + cosine), (1 + cosine) / 2)
            c = (1 + alpha, -2 * cosine, 1 - alpha)
        case .peak:
            b = (1 + alpha * a, -2 * cosine, 1 - alpha * a)
            c = (1 + alpha / a, -2 * cosine, 1 - alpha / a)
        case .lowShelf:
            let root = 2 * sqrt(a) * alpha
            b = (a * ((a + 1) - (a - 1) * cosine + root), 2 * a * ((a - 1) - (a + 1) * cosine), a * ((a + 1) - (a - 1) * cosine - root))
            c = ((a + 1) + (a - 1) * cosine + root, -2 * ((a - 1) + (a + 1) * cosine), (a + 1) + (a - 1) * cosine - root)
        case .highShelf:
            let root = 2 * sqrt(a) * alpha
            b = (a * ((a + 1) + (a - 1) * cosine + root), -2 * a * ((a - 1) + (a + 1) * cosine), a * ((a + 1) + (a - 1) * cosine - root))
            c = ((a + 1) - (a - 1) * cosine + root, 2 * ((a - 1) - (a + 1) * cosine), (a + 1) - (a - 1) * cosine - root)
        }
        self.init(b0: b.0 / c.0, b1: b.1 / c.0, b2: b.2 / c.0, a1: c.1 / c.0, a2: c.2 / c.0)
    }

    func process(_ input: [Float]) -> [Float] {
        var output = [Float](repeating: 0, count: input.count)
        var x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0
        for index in input.indices {
            let x = Double(input[index])
            let y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
            x2 = x1; x1 = x; y2 = y1; y1 = y
            output[index] = Float(y)
        }
        return output
    }

    /// Gain in decibels at a frequency, for drawing the EQ curve.
    func response(at frequency: Double, sampleRate: Double) -> Double {
        let w = 2 * Double.pi * frequency / sampleRate
        let cos1 = cos(w), sin1 = sin(w), cos2 = cos(2 * w), sin2 = sin(2 * w)
        let numeratorReal = b0 + b1 * cos1 + b2 * cos2, numeratorImaginary = -(b1 * sin1 + b2 * sin2)
        let denominatorReal = 1 + a1 * cos1 + a2 * cos2, denominatorImaginary = -(a1 * sin1 + a2 * sin2)
        let numerator = numeratorReal * numeratorReal + numeratorImaginary * numeratorImaginary
        let denominator = denominatorReal * denominatorReal + denominatorImaginary * denominatorImaginary
        return 10 * log10(max(numerator, 1e-20) / max(denominator, 1e-20))
    }
}

struct EQBand: Codable, Hashable, Identifiable, Sendable {
    var id = UUID()
    var kind: Biquad.Kind
    var frequency: Double
    var gain: Double = 0
    var q: Double = 0.9
}

// MARK: Effects

/// The effects Cole applies, each a plain description so it can be saved, undone and tested.
enum SoundEffect: Codable, Hashable, Sendable {
    case amplify(decibels: Double)
    case normalise(peak: Double)
    case loudness(target: Double, ceiling: Double)
    case fadeIn(seconds: Double)
    case fadeOut(seconds: Double)
    case reverse
    case silence
    case eq([EQBand])
    case highPass(frequency: Double)
    case compressor(threshold: Double, ratio: Double, attack: Double, release: Double, makeup: Double)
    case limiter(ceiling: Double)
    case gate(threshold: Double, reduction: Double)
    case speed(rate: Double, keepPitch: Bool)
    case pitch(semitones: Double)
    case removeSilences(threshold: Double, minimum: Double, keep: Double)
    /// Apple's Voice Isolation, a rumble filter, gentle compression and podcast loudness in one go.
    case studioSound

    var title: String {
        switch self {
        case .amplify(let db): return db >= 0 ? "Louder by \(Int(db)) dB" : "Quieter by \(Int(-db)) dB"
        case .normalise: return "Normalise"
        case .loudness(let target, _): return "Loudness to \(Int(target)) LUFS"
        case .fadeIn: return "Fade in"
        case .fadeOut: return "Fade out"
        case .reverse: return "Reverse"
        case .silence: return "Silence"
        case .eq: return "EQ"
        case .highPass: return "Rumble filter"
        case .compressor: return "Compressor"
        case .limiter: return "Limiter"
        case .gate: return "Noise gate"
        case .speed(let rate, let keep): return keep ? "Tempo × \(String(format: "%.2g", rate))" : "Speed × \(String(format: "%.2g", rate))"
        case .pitch(let semitones): return "Pitch \(semitones > 0 ? "+" : "")\(String(format: "%.3g", semitones))"
        case .removeSilences: return "Remove silences"
        case .studioSound: return "Studio sound"
        }
    }
}

enum SoundDSP {
    static func gain(_ sound: SoundBuffer, decibels: Double) -> SoundBuffer {
        let factor = SoundMeter.amplitude(decibels)
        return SoundBuffer(sampleRate: sound.sampleRate, channels: sound.channels.map { vDSP.multiply(factor, $0) })
    }

    static func normalise(_ sound: SoundBuffer, peak target: Double = -1) -> SoundBuffer {
        let peak = SoundMeter.peak(sound)
        guard peak > 0 else { return sound }
        return gain(sound, decibels: target - SoundMeter.decibels(peak))
    }

    /// To a loudness target, then limited so peaks stay under the ceiling.
    static func loudness(_ sound: SoundBuffer, target: Double = -16, ceiling: Double = -1) -> SoundBuffer {
        let measured = SoundMeter.loudness(sound)
        guard measured.isFinite else { return sound }
        let raised = gain(sound, decibels: target - measured)
        return SoundMeter.peak(raised) > SoundMeter.amplitude(ceiling) ? limiter(raised, ceiling: ceiling) : raised
    }

    static func fade(_ sound: SoundBuffer, in fadeIn: Double = 0, out fadeOut: Double = 0) -> SoundBuffer {
        var result = sound
        let inFrames = min(sound.frames, Int(fadeIn * sound.sampleRate)), outFrames = min(sound.frames, Int(fadeOut * sound.sampleRate))
        for channel in result.channels.indices {
            for index in 0..<inFrames {
                let t = Float(index) / Float(max(inFrames, 1))
                result.channels[channel][index] *= t * t
            }
            for index in 0..<outFrames {
                let t = Float(index) / Float(max(outFrames, 1))
                result.channels[channel][sound.frames - 1 - index] *= t * t
            }
        }
        return result
    }

    static func reverse(_ sound: SoundBuffer) -> SoundBuffer {
        SoundBuffer(sampleRate: sound.sampleRate, channels: sound.channels.map { Array($0.reversed()) })
    }

    static func filter(_ sound: SoundBuffer, _ sections: [Biquad]) -> SoundBuffer {
        SoundBuffer(sampleRate: sound.sampleRate, channels: sound.channels.map { channel in
            sections.reduce(channel) { $1.process($0) }
        })
    }

    static func eq(_ sound: SoundBuffer, _ bands: [EQBand]) -> SoundBuffer {
        filter(sound, bands.map { Biquad($0.kind, frequency: $0.frequency, gain: $0.gain, q: $0.q, sampleRate: sound.sampleRate) })
    }

    /// A feed-forward compressor with a 6 dB soft knee, its channels linked so the stereo picture holds.
    static func compressor(_ sound: SoundBuffer, threshold: Double = -20, ratio: Double = 3, attack: Double = 0.01, release: Double = 0.15,
                           makeup: Double = 0) -> SoundBuffer {
        let attackCoefficient = exp(-1 / (max(attack, 0.0001) * sound.sampleRate))
        let releaseCoefficient = exp(-1 / (max(release, 0.0001) * sound.sampleRate))
        let knee = 6.0
        var reduction = 0.0
        var result = sound
        for index in 0..<sound.frames {
            var loudest: Float = 0
            for channel in sound.channels { loudest = max(loudest, abs(channel[index])) }
            let level = SoundMeter.decibels(loudest)
            let over = level - threshold
            var target = 0.0
            if over > knee / 2 { target = over * (1 - 1 / ratio) }
            else if over > -knee / 2 { target = (1 - 1 / ratio) * pow(over + knee / 2, 2) / (2 * knee) }
            let coefficient = target > reduction ? attackCoefficient : releaseCoefficient
            reduction = coefficient * reduction + (1 - coefficient) * target
            let factor = SoundMeter.amplitude(makeup - reduction)
            for channel in result.channels.indices { result.channels[channel][index] *= factor }
        }
        return result
    }

    /// Keeps peaks under a ceiling: a fast compressor with a very high ratio, then a hard stop for anything left.
    static func limiter(_ sound: SoundBuffer, ceiling: Double = -1) -> SoundBuffer {
        let squashed = compressor(sound, threshold: ceiling - 1, ratio: 50, attack: 0.0005, release: 0.08)
        let limit = SoundMeter.amplitude(ceiling)
        return SoundBuffer(sampleRate: sound.sampleRate, channels: squashed.channels.map { vDSP.clip($0, to: -limit...limit) })
    }

    /// Turns quiet stretches down (background hiss between phrases) and leaves speech alone.
    static func gate(_ sound: SoundBuffer, threshold: Double = -45, reduction: Double = -30, attack: Double = 0.002, release: Double = 0.12, hold: Double = 0.08) -> SoundBuffer {
        let attackCoefficient = exp(-1 / (attack * sound.sampleRate)), releaseCoefficient = exp(-1 / (release * sound.sampleRate))
        let holdFrames = Int(hold * sound.sampleRate)
        let floor = SoundMeter.amplitude(reduction), level = SoundMeter.amplitude(threshold)
        var envelope: Float = 0, gainNow: Float = 1
        var held = 0
        var result = sound
        let follower = Float(exp(-1 / (0.005 * sound.sampleRate)))
        for index in 0..<sound.frames {
            var loudest: Float = 0
            for channel in sound.channels { loudest = max(loudest, abs(channel[index])) }
            envelope = max(loudest, envelope * follower)
            var target: Float = floor
            if envelope >= level { target = 1; held = holdFrames } else if held > 0 { target = 1; held -= 1 }
            let coefficient = Float(target > gainNow ? attackCoefficient : releaseCoefficient)
            gainNow = coefficient * gainNow + (1 - coefficient) * target
            for channel in result.channels.indices { result.channels[channel][index] *= gainNow }
        }
        return result
    }

    /// Cuts the given spans out, with a short crossfade at each join so there's no click.
    static func remove(_ sound: SoundBuffer, ranges: [ClosedRange<Double>], crossfade: Double = 0.008) -> SoundBuffer {
        let sorted = ranges.sorted { $0.lowerBound < $1.lowerBound }
        var kept: [SoundBuffer] = []
        var cursor = 0.0
        for range in sorted where range.upperBound > cursor {
            if range.lowerBound > cursor { kept.append(sound.slice(cursor, range.lowerBound)) }
            cursor = max(cursor, range.upperBound)
        }
        if cursor < sound.duration { kept.append(sound.slice(cursor, sound.duration)) }
        guard var result = kept.first else { return SoundBuffer(sampleRate: sound.sampleRate, channelCount: sound.channelCount, frames: 0) }
        let fadeFrames = Int(crossfade * sound.sampleRate)
        for piece in kept.dropFirst() {
            let overlap = min(fadeFrames, result.frames, piece.frames)
            for channel in result.channels.indices {
                let start = result.frames - overlap
                for index in 0..<overlap {
                    let t = Float(index) / Float(max(overlap, 1))
                    result.channels[channel][start + index] = result.channels[channel][start + index] * (1 - t) + piece.channels[channel][index] * t
                }
                result.channels[channel] += piece.channels[channel][overlap...]
            }
        }
        return result
    }

    /// The silences to cut, leaving `keep` seconds of each so speech keeps its breath.
    static func silenceCuts(_ sound: SoundBuffer, threshold: Double = -42, minimum: Double = 0.8, keep: Double = 0.25) -> [ClosedRange<Double>] {
        SoundMeter.silences(sound, threshold: threshold, minimum: minimum).compactMap { gap in
            let start = gap.lowerBound + (gap.lowerBound <= 0.001 ? 0 : keep / 2)
            let end = gap.upperBound - (gap.upperBound >= sound.duration - 0.001 ? 0 : keep / 2)
            return end - start > 0.05 ? start...end : nil
        }
    }

    /// Speed, tempo (speed with the pitch kept) or pitch, through Apple's time-pitch unit, rendered offline.
    static func timePitch(_ sound: SoundBuffer, rate: Double = 1, cents: Double = 0) throws -> SoundBuffer {
        guard sound.frames > 0, let input = SoundIO.pcmBuffer(sound) else { return sound }
        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        let unit = AVAudioUnitTimePitch()
        unit.rate = Float(rate)
        unit.pitch = Float(cents)
        engine.attach(player)
        engine.attach(unit)
        engine.connect(player, to: unit, format: input.format)
        engine.connect(unit, to: engine.mainMixerNode, format: input.format)
        try engine.enableManualRenderingMode(.offline, format: input.format, maximumFrameCount: 4096)
        try engine.start()
        player.scheduleBuffer(input, at: nil)
        player.play()
        let expected = Int(Double(sound.frames) / rate)
        var result = SoundBuffer(sampleRate: sound.sampleRate, channelCount: sound.channelCount, frames: 0)
        guard let output = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: 4096) else { return sound }
        while result.frames < expected {
            let wanted = AVAudioFrameCount(min(4096, expected - result.frames))
            let status = try engine.renderOffline(wanted, to: output)
            guard status == .success else { break }
            result.append(SoundIO.sound(from: output))
        }
        player.stop()
        engine.stop()
        return result.withChannels(sound.channelCount)
    }

    /// Plain speed: faster is higher, like a tape.
    static func varispeed(_ sound: SoundBuffer, rate: Double) -> SoundBuffer {
        var result = SoundBuffer(sampleRate: sound.sampleRate * rate, channels: sound.channels).resampled(to: sound.sampleRate)
        result.sampleRate = sound.sampleRate
        return result
    }

    static func apply(_ effect: SoundEffect, to sound: SoundBuffer) throws -> SoundBuffer {
        switch effect {
        case .amplify(let db): return gain(sound, decibels: db)
        case .normalise(let peak): return normalise(sound, peak: peak)
        case .loudness(let target, let ceiling): return loudness(sound, target: target, ceiling: ceiling)
        case .fadeIn(let seconds): return fade(sound, in: seconds)
        case .fadeOut(let seconds): return fade(sound, out: seconds)
        case .reverse: return reverse(sound)
        case .silence: return SoundBuffer(sampleRate: sound.sampleRate, channelCount: sound.channelCount, frames: sound.frames)
        case .eq(let bands): return eq(sound, bands)
        case .highPass(let frequency): return filter(sound, [Biquad(.highPass, frequency: frequency, sampleRate: sound.sampleRate)])
        case .compressor(let threshold, let ratio, let attack, let release, let makeup):
            return compressor(sound, threshold: threshold, ratio: ratio, attack: attack, release: release, makeup: makeup)
        case .limiter(let ceiling): return limiter(sound, ceiling: ceiling)
        case .gate(let threshold, let reduction): return gate(sound, threshold: threshold, reduction: reduction)
        case .speed(let rate, let keepPitch): return keepPitch ? try timePitch(sound, rate: rate) : varispeed(sound, rate: rate)
        case .pitch(let semitones): return try timePitch(sound, cents: semitones * 100)
        case .removeSilences(let threshold, let minimum, let keep): return remove(sound, ranges: silenceCuts(sound, threshold: threshold, minimum: minimum, keep: keep))
        case .studioSound:
            // Voice isolation runs in the app (it needs Apple's audio unit); here the chain that follows it.
            var result = filter(sound, [Biquad(.highPass, frequency: 80, sampleRate: sound.sampleRate),
                                        Biquad(.peak, frequency: 3_000, gain: 2, q: 0.8, sampleRate: sound.sampleRate)])
            result = compressor(result, threshold: -24, ratio: 3, attack: 0.008, release: 0.2)
            return loudness(result, target: -16, ceiling: -1)
        }
    }
}

// MARK: Projects

struct SoundClip: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var name: String
    /// The sound file in the project's folder.
    var asset: String
    /// Where it starts on the timeline, in seconds.
    var start: Double
    /// The part of the file that plays.
    var inPoint: Double = 0
    var outPoint: Double
    var gain: Double = 0
    var fadeIn: Double = 0
    var fadeOut: Double = 0

    var length: Double { max(0, outPoint - inPoint) }
    var end: Double { start + length }
}

struct SoundTrack: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var name: String
    var clips: [SoundClip] = []
    /// Decibels.
    var volume: Double = 0
    /// −1 left to 1 right.
    var pan: Double = 0
    var muted = false
    var solo = false
}

struct SoundMarker: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var time: Double
    var name: String
}

/// A word from the transcript, in timeline seconds.
struct SoundWord: Codable, Hashable, Sendable {
    var text: String
    var start: Double
    var end: Double

    static let fillers: Set<String> = ["um", "umm", "uh", "uhh", "er", "erm", "ah", "hmm", "mm", "like,", "you know"]

    var isFiller: Bool {
        let plain = text.lowercased().trimmingCharacters(in: .punctuationCharacters)
        return SoundWord.fillers.contains(plain) || SoundWord.fillers.contains(text.lowercased())
    }
}

struct SoundProject: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var name: String
    var sampleRate: Double = 48_000
    var tracks: [SoundTrack] = [SoundTrack(name: "Voice")]
    var markers: [SoundMarker] = []
    var words: [SoundWord] = []
    var modified = Date()

    var duration: Double { tracks.flatMap(\.clips).map(\.end).max() ?? 0 }

    func clip(_ id: UUID) -> (track: Int, index: Int)? {
        for (trackIndex, track) in tracks.enumerated() {
            if let index = track.clips.firstIndex(where: { $0.id == id }) { return (trackIndex, index) }
        }
        return nil
    }
}

enum SoundEdit {
    /// Splits a clip in two at a timeline time.
    @discardableResult
    static func split(_ project: inout SoundProject, clip id: UUID, at time: Double) -> UUID? {
        guard let found = project.clip(id) else { return nil }
        let clip = project.tracks[found.track].clips[found.index]
        guard time > clip.start + 0.01, time < clip.end - 0.01 else { return nil }
        var left = clip, right = clip
        left.outPoint = clip.inPoint + (time - clip.start)
        left.fadeOut = 0
        right.id = UUID()
        right.inPoint = left.outPoint
        right.start = time
        right.fadeIn = 0
        project.tracks[found.track].clips[found.index] = left
        project.tracks[found.track].clips.insert(right, at: found.index + 1)
        return right.id
    }

    /// Removes a stretch of time from some tracks (all when nil); with `ripple`, what's after closes the gap.
    static func delete(_ project: inout SoundProject, range: ClosedRange<Double>, tracks: Set<UUID>? = nil, ripple: Bool = true) {
        let length = range.upperBound - range.lowerBound
        guard length > 0 else { return }
        for trackIndex in project.tracks.indices where tracks?.contains(project.tracks[trackIndex].id) ?? true {
            var clips: [SoundClip] = []
            for clip in project.tracks[trackIndex].clips {
                if clip.end <= range.lowerBound {
                    clips.append(clip)
                } else if clip.start >= range.upperBound {
                    var moved = clip
                    if ripple { moved.start -= length }
                    clips.append(moved)
                } else {
                    // Overlaps: keep what's before and after.
                    if clip.start < range.lowerBound {
                        var before = clip
                        before.outPoint = clip.inPoint + (range.lowerBound - clip.start)
                        before.fadeOut = 0
                        clips.append(before)
                    }
                    if clip.end > range.upperBound {
                        var after = clip
                        after.id = clip.start < range.lowerBound ? UUID() : clip.id
                        after.inPoint = clip.inPoint + (range.upperBound - clip.start)
                        after.start = ripple ? range.lowerBound : range.upperBound
                        after.fadeIn = 0
                        clips.append(after)
                    }
                }
            }
            project.tracks[trackIndex].clips = clips.sorted { $0.start < $1.start }
        }
        if ripple {
            project.markers = project.markers.compactMap { marker -> SoundMarker? in
                if marker.time >= range.upperBound { var moved = marker; moved.time -= length; return moved }
                return range.contains(marker.time) ? nil : marker
            }
            project.words = project.words.compactMap { word -> SoundWord? in
                if word.start >= range.upperBound { return SoundWord(text: word.text, start: word.start - length, end: word.end - length) }
                return word.end <= range.lowerBound ? word : nil
            }
        }
    }

    /// Several stretches at once (silences, fillers), latest first so earlier times stay put.
    static func delete(_ project: inout SoundProject, ranges: [ClosedRange<Double>], tracks: Set<UUID>? = nil) {
        for range in ranges.sorted(by: { $0.lowerBound > $1.lowerBound }) { delete(&project, range: range, tracks: tracks) }
    }

    static func move(_ project: inout SoundProject, clip id: UUID, to start: Double, track: Int? = nil) {
        guard let found = project.clip(id) else { return }
        var clip = project.tracks[found.track].clips.remove(at: found.index)
        clip.start = max(0, start)
        let target = track.map { min(max(0, $0), project.tracks.count - 1) } ?? found.track
        project.tracks[target].clips.append(clip)
        project.tracks[target].clips.sort { $0.start < $1.start }
    }

    /// The timeline spans of filler words ("um", "uh"), padded a little.
    static func fillerRanges(_ project: SoundProject, padding: Double = 0.03) -> [ClosedRange<Double>] {
        project.words.filter(\.isFiller).map { max(0, $0.start - padding)...($0.end + padding) }
    }
}

/// Renders a project to one stereo sound, the way it plays.
enum SoundMixer {
    static func render(_ project: SoundProject, sources: (String) -> SoundBuffer?, range: ClosedRange<Double>? = nil) -> SoundBuffer {
        let span = range ?? 0...max(project.duration, 0.01)
        let rate = project.sampleRate
        var output = SoundBuffer(sampleRate: rate, channelCount: 2, frames: Int((span.upperBound - span.lowerBound) * rate))
        let soloing = project.tracks.contains(where: \.solo)
        for track in project.tracks where !track.muted && (!soloing || track.solo) {
            let angle = (track.pan + 1) * .pi / 4
            let left = Float(cos(angle)) * SoundMeter.amplitude(track.volume) * Float(2.0.squareRoot())
            let right = Float(sin(angle)) * SoundMeter.amplitude(track.volume) * Float(2.0.squareRoot())
            for clip in track.clips where clip.end > span.lowerBound && clip.start < span.upperBound {
                guard let source = sources(clip.asset) else { continue }
                var piece = (source.sampleRate == rate ? source : source.resampled(to: rate)).slice(clip.inPoint, clip.outPoint).withChannels(2)
                piece = SoundDSP.fade(SoundDSP.gain(piece, decibels: clip.gain), in: clip.fadeIn, out: clip.fadeOut)
                let offset = Int(((clip.start - span.lowerBound) * rate).rounded())
                for index in 0..<piece.frames {
                    let target = offset + index
                    guard target >= 0 else { continue }
                    guard target < output.frames else { break }
                    output.channels[0][target] += piece.channels[0][index] * left
                    output.channels[1][target] += piece.channels[1][index] * right
                }
            }
        }
        return output
    }
}

/// Chapters for a podcast from the project's markers, as the text show notes use ("00:00 Intro").
enum SoundChapters {
    static func text(_ project: SoundProject) -> String {
        project.markers.sorted { $0.time < $1.time }.map { "\(clock($0.time)) \($0.name)" }.joined(separator: "\n")
    }

    static func clock(_ seconds: Double) -> String {
        let total = Int(seconds.rounded(.down))
        return total >= 3600 ? String(format: "%d:%02d:%02d", total / 3600, total % 3600 / 60, total % 60) : String(format: "%02d:%02d", total / 60, total % 60)
    }
}
