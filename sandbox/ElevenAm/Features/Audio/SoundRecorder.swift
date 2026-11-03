import AVFoundation
import CoreMedia
import Foundation
import ScreenCaptureKit

/// Records from a microphone into a file, with a level meter.
@MainActor
final class MicRecorder: ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var level: Double = -80
    @Published private(set) var elapsed: Double = 0

    private let engine = AVAudioEngine()
    private var file: AVAudioFile?
    private var started = Date()
    private var ticker: Timer?

    static func permission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .audio)
        default: return false
        }
    }

    func start(to url: URL) throws {
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw SoundIOError.unwritable }
        let output = try AVAudioFile(forWriting: url, settings: SoundFormat.caf.settings(sampleRate: format.sampleRate, channels: Int(format.channelCount)),
                                     commonFormat: .pcmFormatFloat32, interleaved: false)
        file = output
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { @Sendable [weak self] buffer, _ in
            try? output.write(from: buffer)
            let sound = SoundIO.sound(from: buffer)
            let peak = SoundMeter.decibels(SoundMeter.peak(sound))
            Task { @MainActor in self?.level = max(-80, peak) }
        }
        try engine.start()
        started = Date()
        isRecording = true
        ticker = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.elapsed = Date().timeIntervalSince(self.started)
            }
        }
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        ticker?.invalidate()
        ticker = nil
        file = nil
        isRecording = false
        level = -80
    }
}

/// Records what the Mac is playing (a call, a video) through ScreenCaptureKit, leaving 11am's own sound out.
/// Needs Screen & System Audio Recording permission, which macOS asks for the first time.
final class MacSoundRecorder: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    private var stream: SCStream?
    private var file: AVAudioFile?
    private let queue = DispatchQueue(label: "11am.mac-sound")
    private(set) var url: URL?
    var onLevel: ((Double) -> Void)?
    var onError: ((String) -> Void)?

    func start(to url: URL) async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first else { throw SoundIOError.unwritable }
        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
        let configuration = SCStreamConfiguration()
        configuration.capturesAudio = true
        configuration.excludesCurrentProcessAudio = true
        configuration.sampleRate = 48_000
        configuration.channelCount = 2
        // A tiny, slow picture: only the sound is wanted.
        configuration.width = 2
        configuration.height = 2
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        self.url = url
        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: queue)
        try await stream.startCapture()
        self.stream = stream
    }

    func stop() async {
        try? await stream?.stopCapture()
        stream = nil
        queue.sync { file = nil }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, sampleBuffer.isValid, let description = sampleBuffer.formatDescription,
              let url else { return }
        let format = AVAudioFormat(cmAudioFormatDescription: description)
        let frames = AVAudioFrameCount(sampleBuffer.numSamples)
        guard frames > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return }
        buffer.frameLength = frames
        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(sampleBuffer, at: 0, frameCount: Int32(frames), into: buffer.mutableAudioBufferList)
        guard status == noErr else { return }
        if file == nil {
            file = try? AVAudioFile(forWriting: url, settings: SoundFormat.caf.settings(sampleRate: format.sampleRate, channels: Int(format.channelCount)),
                                    commonFormat: .pcmFormatFloat32, interleaved: false)
        }
        try? file?.write(from: buffer)
        let peak = SoundMeter.decibels(SoundMeter.peak(SoundIO.sound(from: buffer)))
        onLevel?(max(-80, peak))
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        onError?(error.localizedDescription)
    }
}
