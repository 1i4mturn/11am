import AppKit
import AVFoundation
import Foundation
import Speech
import UniformTypeIdentifiers

struct TranscriptLine: Identifiable, Codable, Hashable {
    var id = UUID()
    var start: Double
    var end: Double
    var text: String
    var cut = false
}

/// Cole in the sandbox: transcribe on this Mac, cut by striking lines, export the cut video and captions.
@MainActor
final class VideoModel: ObservableObject {
    @Published private(set) var mediaURL: URL?
    @Published private(set) var player: AVPlayer?
    @Published private(set) var lines: [TranscriptLine] = VideoSamples.lines
    @Published private(set) var isSample = true
    @Published private(set) var status = "Sample transcript. Open a video or audio file to work on your own."
    @Published private(set) var isWorking = false
    @Published private(set) var insightRun: BrainRun?

    private let brain: Brain

    init(brain: Brain) {
        self.brain = brain
    }

    var cutCount: Int { lines.filter(\.cut).count }

    var cutSeconds: Double { lines.filter(\.cut).reduce(0) { $0 + ($1.end - $1.start) } }

    // MARK: Media

    func open(_ url: URL) {
        player?.pause()
        mediaURL = url
        player = AVPlayer(url: url)
        lines = []
        isSample = false
        insightRun = nil
        status = "Ready. Transcribe it on this Mac to start editing."
    }

    func seek(to line: TranscriptLine) {
        guard let player else { return }
        player.seek(to: CMTime(seconds: line.start, preferredTimescale: 600))
        player.play()
    }

    func toggleCut(_ line: TranscriptLine) {
        guard let index = lines.firstIndex(where: { $0.id == line.id }) else { return }
        lines[index].cut.toggle()
    }

    // MARK: Transcription

    func transcribe() {
        guard let url = mediaURL else { return }
        isWorking = true
        status = "Transcribing on this Mac…"
        Task {
            defer { isWorking = false }
            do {
                let authorised: Bool = await withCheckedContinuation { continuation in
                    SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0 == .authorized) }
                }
                guard authorised else {
                    status = "Speech recognition is off for 11am. Turn it on in System Settings › Privacy & Security › Speech Recognition."
                    return
                }
                let audio = try await VideoModel.audioFile(for: url)
                let segments = try await VideoModel.recognise(audio)
                lines = VideoModel.group(segments)
                status = lines.isEmpty ? "No speech found." : "\(lines.count) lines. Click one to jump there; strike lines to cut them."
            } catch {
                status = error.localizedDescription
            }
        }
    }

    private struct Segment {
        let start: Double
        let duration: Double
        let text: String
    }

    /// Speech reads audio files, so a video's sound is pulled out first.
    private static func audioFile(for url: URL) async throws -> URL {
        let audioTypes: Set<String> = ["m4a", "mp3", "wav", "aiff", "aif", "caf", "aac"]
        if audioTypes.contains(url.pathExtension.lowercased()) { return url }
        let asset = AVURLAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        guard !tracks.isEmpty else { throw VideoError.noAudio }
        guard let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else { throw VideoError.export }
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("11am-\(UUID().uuidString).m4a")
        export.outputURL = output
        export.outputFileType = .m4a
        await export.export()
        guard export.status == .completed else { throw export.error ?? VideoError.export }
        return output
    }

    private static func recognise(_ url: URL) async throws -> [Segment] {
        guard let recognizer = SFSpeechRecognizer(locale: Locale.current) ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US")),
              recognizer.isAvailable else { throw VideoError.noRecognizer }
        let request = SFSpeechURLRecognitionRequest(url: url)
        request.shouldReportPartialResults = false
        request.addsPunctuation = true
        // Stay on this Mac whenever the language supports it.
        if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }
        let result: SFSpeechRecognitionResult = try await withCheckedThrowingContinuation { continuation in
            var finished = false
            _ = recognizer.recognitionTask(with: request) { result, error in
                guard !finished else { return }
                if let error {
                    finished = true
                    continuation.resume(throwing: error)
                } else if let result, result.isFinal {
                    finished = true
                    continuation.resume(returning: result)
                }
            }
        }
        return result.bestTranscription.segments.map {
            Segment(start: $0.timestamp, duration: $0.duration, text: $0.substring)
        }
    }

    /// Words become lines at sentence ends, pauses, or about a dozen words.
    private static func group(_ segments: [Segment]) -> [TranscriptLine] {
        var lines: [TranscriptLine] = []
        var words: [String] = []
        var start: Double?
        var end: Double = 0
        func flush() {
            if let start, !words.isEmpty {
                lines.append(TranscriptLine(start: start, end: end, text: words.joined(separator: " ")))
            }
            words = []
            start = nil
        }
        for segment in segments {
            if let _ = start, segment.start - end > 0.8 { flush() }
            if start == nil { start = segment.start }
            words.append(segment.text)
            end = segment.start + segment.duration
            if words.count >= 12 || [".", "?", "!"].contains(where: { segment.text.hasSuffix($0) }) { flush() }
        }
        flush()
        return lines
    }

    // MARK: Export

    /// Captions for what you'll publish: struck lines are dropped and later lines shift earlier.
    func exportCaptions() {
        var shift: Double = 0
        var index = 0
        var output = ""
        for line in lines {
            if line.cut {
                shift += line.end - line.start
                continue
            }
            index += 1
            output += "\(index)\n\(VideoModel.srtTime(line.start - shift)) --> \(VideoModel.srtTime(line.end - shift))\n\(line.text)\n\n"
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "srt") ?? .plainText]
        panel.nameFieldStringValue = "\(mediaURL?.deletingPathExtension().lastPathComponent ?? "captions").srt"
        if panel.runModal() == .OK, let url = panel.url {
            try? output.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    /// Removes every struck line from the video and saves the result.
    func exportCut() {
        guard let source = mediaURL else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.quickTimeMovie]
        panel.nameFieldStringValue = "\(source.deletingPathExtension().lastPathComponent) (cut).mov"
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        let ranges = lines.filter(\.cut).map { (start: $0.start, end: $0.end) }
        isWorking = true
        status = "Exporting the cut…"
        Task {
            defer { isWorking = false }
            do {
                try await VideoModel.export(source, removing: ranges, to: destination)
                status = "Saved \(destination.lastPathComponent)."
            } catch {
                status = error.localizedDescription
            }
        }
    }

    private static func export(_ source: URL, removing ranges: [(start: Double, end: Double)], to destination: URL) async throws {
        let asset = AVURLAsset(url: source)
        let duration = try await asset.load(.duration)
        let composition = AVMutableComposition()
        let whole = CMTimeRange(start: .zero, duration: duration)
        // Copy each video and audio track in, keeping the video's rotation.
        for type in [AVMediaType.video, .audio] {
            for sourceTrack in try await asset.loadTracks(withMediaType: type) {
                guard let track = composition.addMutableTrack(withMediaType: type, preferredTrackID: kCMPersistentTrackID_Invalid) else { continue }
                try track.insertTimeRange(whole, of: sourceTrack, at: .zero)
                if type == .video {
                    track.preferredTransform = try await sourceTrack.load(.preferredTransform)
                }
            }
        }
        // Remove from the end backwards so earlier times stay valid.
        for range in ranges.sorted(by: { $0.start > $1.start }) {
            let start = CMTime(seconds: range.start, preferredTimescale: 600)
            let end = CMTime(seconds: range.end, preferredTimescale: 600)
            composition.removeTimeRange(CMTimeRange(start: start, end: end))
        }
        try? FileManager.default.removeItem(at: destination)
        guard let export = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else { throw VideoError.export }
        export.outputURL = destination
        export.outputFileType = .mov
        await export.export()
        guard export.status == .completed else { throw export.error ?? VideoError.export }
    }

    private static func srtTime(_ seconds: Double) -> String {
        let total = max(0, seconds)
        let hours = Int(total) / 3600
        let minutes = Int(total) % 3600 / 60
        let secs = Int(total) % 60
        let millis = Int((total - floor(total)) * 1000)
        return String(format: "%02d:%02d:%02d,%03d", hours, minutes, secs, millis)
    }

    static func clock(_ seconds: Double) -> String {
        String(format: "%d:%02d", Int(seconds) / 60, Int(seconds) % 60)
    }

    // MARK: Asking

    func insights() {
        let transcript = lines.filter { !$0.cut }.map { "[\(VideoModel.clock($0.start))] \($0.text)" }.joined(separator: "\n")
        guard !transcript.isEmpty else { return }
        let system = """
        You are Cole, the video agent inside 11am. From the transcript, write: a title (under 60 characters), \
        a two-sentence description, and chapters as lines starting with a timestamp like 0:00. Use only what's said.
        """
        insightRun = brain.run(BrainRequest(system: system, prompt: String(transcript.prefix(8_000)), weight: .quick))
    }
}

enum VideoError: LocalizedError {
    case noAudio, export, noRecognizer

    var errorDescription: String? {
        switch self {
        case .noAudio: return "That file has no sound to transcribe."
        case .export: return "The file couldn't be processed."
        case .noRecognizer: return "Speech recognition isn't available for this language on this Mac."
        }
    }
}

/// A short product update, so the transcript editor has something in it before you open a file.
enum VideoSamples {
    static let lines: [TranscriptLine] = {
        let script = [
            "Hi everyone, quick update on where 11am is this month.",
            "Um, so, let me just, let me get my notes up.",
            "The big one: Acme signed, and they're rolling out to forty people.",
            "They need single sign-on first, so that's what we're building next.",
            "Revenue is up about half since May, and burn is flat.",
            "We've got fourteen months of runway at the current rate.",
            "Sorry, that's my phone, give me a second.",
            "On the product side, the notch and the overnight brief are the two things people mention most.",
            "Next month we're shipping Mail and Write to the pilot group.",
            "If you know anyone who'd be a great first designer, please send them our way.",
            "That's it. Thanks for watching, and talk next month.",
        ]
        var time = 0.0
        return script.map { text in
            let length = Double(text.split(separator: " ").count) * 0.38 + 0.6
            defer { time += length + 0.4 }
            return TranscriptLine(start: time, end: time + length, text: text)
        }
    }()
}
