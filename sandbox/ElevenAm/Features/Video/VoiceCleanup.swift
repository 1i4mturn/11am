import AudioToolbox
import AVFoundation
import Foundation

/// Cleans a clip's sound on this Mac: Apple's Voice Isolation (the same one FaceTime uses) where available,
/// a high-pass to take out rumble and handling noise, then levelled so the loudest moment sits just under full scale.
/// The result keeps the source's timing exactly, so it drops back onto the clip in sync.
enum VoiceCleanup {
    struct Result {
        let url: URL
        let isolated: Bool
    }

    static func clean(_ source: URL) async throws -> Result {
        let audio = try await Transcriber.audioFile(for: source)
        let file = try AVAudioFile(forReading: audio)
        let format = file.processingFormat
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("11am-voice", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let rendered = folder.appendingPathComponent("\(UUID().uuidString)-raw.caf")
        let output = folder.appendingPathComponent("\(source.deletingPathExtension().lastPathComponent)-\(UUID().uuidString.prefix(6)).caf")

        var isolation: AVAudioUnit?
        if format.channelCount <= 2 { isolation = try? await isolationUnit() }
        var peak = try render(file, through: isolation, to: rendered)
        if isolation != nil && peak < 0.001 {
            // Silence back means the isolation model isn't usable on this Mac; clean up without it.
            isolation = nil
            file.framePosition = 0
            try? FileManager.default.removeItem(at: rendered)
            peak = try render(file, through: nil, to: rendered)
        }
        try normalise(rendered, peak: peak, to: output)
        try? FileManager.default.removeItem(at: rendered)
        return Result(url: output, isolated: isolation != nil)
    }

    private static func pcmSettings(_ format: AVAudioFormat, bits: Int, float: Bool) -> [String: Any] {
        [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: format.channelCount,
            AVLinearPCMBitDepthKey: bits,
            AVLinearPCMIsFloatKey: float,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]
    }

    /// Apple's AUSoundIsolation ('vois'), macOS 13 and later.
    private static func isolationUnit() async throws -> AVAudioUnit? {
        var description = AudioComponentDescription(
            componentType: kAudioUnitType_Effect,
            componentSubType: 0x766F_6973, // 'vois'
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        )
        guard AudioComponentFindNext(nil, &description) != nil else { return nil }
        let unit = try await AVAudioUnit.instantiate(with: description, options: [])
        let parameters = unit.auAudioUnit.parameterTree
        // Isolate voice (kAUSoundIsolationParam_SoundToIsolate, macOS 14), fully wet so only the voice comes through.
        parameters?.parameter(withAddress: 95782)?.value = 1
        parameters?.parameter(withAddress: 0)?.value = 100
        return unit
    }

    /// Renders offline as fast as the Mac allows and returns the peak level.
    private static func render(_ file: AVAudioFile, through isolation: AVAudioUnit?, to url: URL) throws -> Float {
        let format = file.processingFormat
        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        let highPass = AVAudioUnitEQ(numberOfBands: 1)
        highPass.bands[0].filterType = .highPass
        highPass.bands[0].frequency = 80
        highPass.bands[0].bypass = false
        engine.attach(player)
        engine.attach(highPass)
        if let isolation {
            engine.attach(isolation)
            engine.connect(player, to: isolation, format: format)
            engine.connect(isolation, to: highPass, format: format)
        } else {
            engine.connect(player, to: highPass, format: format)
        }
        engine.connect(highPass, to: engine.mainMixerNode, format: format)

        try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 4096)
        try engine.start()
        player.scheduleFile(file, at: nil)
        player.play()
        defer {
            player.stop()
            engine.stop()
        }

        // Voice Isolation looks ahead a little; skip that lead-in so the voice lines up with the picture.
        let latency = AVAudioFramePosition(((isolation?.auAudioUnit.latency ?? 0) + highPass.auAudioUnit.latency) * format.sampleRate)
        let total = file.length + latency
        let writer = try AVAudioFile(forWriting: url, settings: pcmSettings(format, bits: 32, float: true), commonFormat: .pcmFormatFloat32, interleaved: false)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: engine.manualRenderingMaximumFrameCount) else {
            throw VideoError.export
        }
        var peak: Float = 0
        var skip = latency
        while engine.manualRenderingSampleTime < total {
            let frames = AVAudioFrameCount(min(AVAudioFramePosition(buffer.frameCapacity), total - engine.manualRenderingSampleTime))
            switch try engine.renderOffline(frames, to: buffer) {
            case .success:
                let length = Int(buffer.frameLength)
                let start = Int(min(skip, AVAudioFramePosition(length)))
                skip -= AVAudioFramePosition(start)
                guard start < length, let channels = buffer.floatChannelData else { continue }
                for channel in 0..<Int(buffer.format.channelCount) {
                    for frame in start..<length { peak = max(peak, abs(channels[channel][frame])) }
                }
                if start == 0 {
                    try writer.write(from: buffer)
                } else if let tail = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: AVAudioFrameCount(length - start)),
                          let target = tail.floatChannelData {
                    tail.frameLength = AVAudioFrameCount(length - start)
                    for channel in 0..<Int(buffer.format.channelCount) {
                        target[channel].update(from: channels[channel] + start, count: length - start)
                    }
                    try writer.write(from: tail)
                }
            case .insufficientDataFromInputNode, .cannotDoInCurrentContext:
                continue
            case .error:
                throw VideoError.export
            @unknown default:
                throw VideoError.export
            }
        }
        return peak
    }

    /// Brings the loudest moment to about -1 dB, never boosting more than 12 dB, and writes 16-bit audio.
    private static func normalise(_ url: URL, peak: Float, to output: URL) throws {
        let input = try AVAudioFile(forReading: url)
        let format = input.processingFormat
        let gain = peak > 0.0001 ? min(0.89 / peak, 4) : 1
        let writer = try AVAudioFile(forWriting: output, settings: pcmSettings(format, bits: 16, float: false), commonFormat: .pcmFormatFloat32, interleaved: false)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 16_384) else { throw VideoError.export }
        while input.framePosition < input.length {
            try input.read(into: buffer)
            guard buffer.frameLength > 0 else { break }
            if let channels = buffer.floatChannelData {
                for channel in 0..<Int(format.channelCount) {
                    for frame in 0..<Int(buffer.frameLength) {
                        channels[channel][frame] = min(max(channels[channel][frame] * gain, -1), 1)
                    }
                }
            }
            try writer.write(from: buffer)
        }
    }
}
