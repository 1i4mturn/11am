import AVFoundation
import Foundation
import Speech

struct TranscriptLine: Identifiable, Codable, Hashable {
    var id = UUID()
    /// Seconds in the source file.
    var start: Double
    var end: Double
    var text: String
    var cut = false
}

enum VideoError: LocalizedError {
    case noAudio, noVideo, export, noRecognizer, speechOff

    var errorDescription: String? {
        switch self {
        case .noAudio: return "That clip has no sound."
        case .noVideo: return "That file has no picture. Add a video file."
        case .export: return "The file couldn't be processed."
        case .noRecognizer: return "Speech recognition isn't available for this language on this Mac."
        case .speechOff: return "Speech recognition is off for 11am. Turn it on in System Settings › Privacy & Security › Speech Recognition."
        }
    }
}

/// Speech to timed lines, on this Mac whenever the language allows.
enum Transcriber {
    static func transcribe(_ url: URL) async throws -> [TranscriptLine] {
        let authorised: Bool = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0 == .authorized) }
        }
        guard authorised else { throw VideoError.speechOff }
        let audio = try await audioFile(for: url)
        return group(try await recognise(audio))
    }

    private struct Segment {
        let start: Double
        let duration: Double
        let text: String
    }

    /// Speech reads audio files, so a video's sound is pulled out first.
    static func audioFile(for url: URL) async throws -> URL {
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
            if start != nil, segment.start - end > 0.8 { flush() }
            if start == nil { start = segment.start }
            words.append(segment.text)
            end = segment.start + segment.duration
            if words.count >= 12 || [".", "?", "!"].contains(where: { segment.text.hasSuffix($0) }) { flush() }
        }
        flush()
        return lines
    }
}
