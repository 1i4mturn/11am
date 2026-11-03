import AVFoundation
import CoreImage
import Foundation

/// A music bed under the whole movie, turned down while someone talks.
struct VideoMusic: Equatable {
    var url: URL
    var name: String
    var volume: Double = 0.5
    var ducking = true
    /// How far down it goes under speech, as a share of its volume.
    var duckLevel: Double = 0.22
}

/// A title drawn over the picture, from the brand kit.
struct VideoTitle: Identifiable, Equatable {
    enum Kind: String, CaseIterable, Identifiable {
        case lowerThird, titleCard, endCard

        var id: String { rawValue }

        var title: String {
            switch self {
            case .lowerThird: return "Lower third"
            case .titleCard: return "Title card"
            case .endCard: return "End card"
            }
        }
    }

    var id = UUID()
    var kind: Kind
    var text: String
    var detail: String
    /// Timeline seconds.
    var start: Double
    var duration: Double

    var end: Double { start + duration }
}

/// Something drawn over the movie for a while: a title or a caption, already placed in the frame.
struct VideoOverlay {
    let start: Double
    let end: Double
    let image: CIImage
    static let fade = 0.25

    func alpha(at time: Double) -> Double {
        guard time >= start, time <= end else { return 0 }
        return max(0, min(1, (time - start) / Self.fade, (end - time) / Self.fade))
    }
}

/// Titles and captions drawn with the canvas engine, each only as big as it needs to be.
enum VideoOverlays {
    static func build(titles: [VideoTitle], captions: [(start: Double, end: Double, text: String)], size: CGSize, brand: CanvasBrand) -> [VideoOverlay] {
        var overlays: [VideoOverlay] = []
        for title in titles {
            if let drawn = draw(titleDocument(title, size: size, brand: brand), in: size) {
                overlays.append(VideoOverlay(start: title.start, end: title.end, image: drawn))
            }
        }
        for caption in captions where caption.end - caption.start > 0.15 {
            if let drawn = draw(captionDocument(caption.text, size: size), in: size) {
                overlays.append(VideoOverlay(start: caption.start, end: caption.end, image: drawn))
            }
        }
        return overlays
    }

    /// A canvas document and where its top-left corner sits in the frame.
    typealias Placed = (document: CanvasDocument, origin: CGPoint)

    static func titleDocument(_ title: VideoTitle, size: CGSize, brand: CanvasBrand) -> Placed {
        let w = Double(size.width), h = Double(size.height), unit = min(w, h)
        var heading = TextStyle()
        heading.font = brand.headingFont
        heading.weight = .bold
        heading.color = .white
        var detail = TextStyle()
        detail.font = brand.bodyFont
        detail.weight = .medium
        detail.color = CanvasColor.white.withAlpha(0.82)
        switch title.kind {
        case .lowerThird:
            heading.size = unit * 0.05
            detail.size = unit * 0.032
            let textWidth = max(Double(CanvasRenderer.textSize(title.text, heading, width: w).width),
                                Double(CanvasRenderer.textSize(title.detail, detail, width: w).width))
            let boxWidth = min(w * 0.8, textWidth + unit * 0.09)
            let boxHeight = unit * (title.detail.isEmpty ? 0.1 : 0.15)
            var document = CanvasDocument(name: "Lower third", size: CanvasSize(width: boxWidth, height: boxHeight), background: .none)
            document.layers = [
                .shapeLayer(.rectangle, frame: CanvasRect(x: 0, y: 0, width: boxWidth, height: boxHeight), fill: .solid(brand.primary.withAlpha(0.88)), radius: unit * 0.012),
                .shapeLayer(.rectangle, frame: CanvasRect(x: 0, y: 0, width: unit * 0.012, height: boxHeight), fill: .solid(brand.accent)),
                .textLayer(title.text, heading, frame: CanvasRect(x: unit * 0.04, y: unit * 0.018, width: boxWidth - unit * 0.06, height: unit * 0.07)),
            ]
            if !title.detail.isEmpty {
                document.layers.append(.textLayer(title.detail, detail, frame: CanvasRect(x: unit * 0.04, y: unit * 0.085, width: boxWidth - unit * 0.06, height: unit * 0.05)))
            }
            return (document, CGPoint(x: w * 0.06, y: h - unit * 0.08 - boxHeight))
        case .titleCard, .endCard:
            heading.size = unit * 0.09
            heading.alignment = .center
            heading.tracking = -unit * 0.0015
            detail.size = unit * 0.04
            detail.alignment = .center
            let background: CanvasFill = title.kind == .titleCard ? .solid(brand.primary.withAlpha(0.72)) : .linear(brand.primary, brand.accent, angle: 45)
            var document = CanvasDocument(name: title.kind.title, size: CanvasSize(width: w, height: h), background: background)
            let headingHeight = Double(CanvasRenderer.textSize(title.text, heading, width: w * 0.8).height)
            document.layers = [.textLayer(title.text, heading, frame: CanvasRect(x: w * 0.1, y: h / 2 - headingHeight / 2 - unit * 0.03, width: w * 0.8, height: headingHeight + 4))]
            if !title.detail.isEmpty {
                document.layers.append(.textLayer(title.detail, detail, frame: CanvasRect(x: w * 0.1, y: h / 2 + headingHeight / 2, width: w * 0.8, height: unit * 0.12)))
            }
            return (document, .zero)
        }
    }

    static func captionDocument(_ text: String, size: CGSize) -> Placed {
        let w = Double(size.width), h = Double(size.height), unit = min(w, h)
        var style = TextStyle()
        style.size = unit * 0.042
        style.weight = .semibold
        style.color = .white
        style.alignment = .center
        style.lineHeight = 1.2
        let maxWidth = w * 0.84
        let measured = CanvasRenderer.textSize(text, style, width: maxWidth - unit * 0.05)
        let boxWidth = min(maxWidth, Double(measured.width) + unit * 0.05), boxHeight = Double(measured.height) + unit * 0.03
        var document = CanvasDocument(name: "Caption", size: CanvasSize(width: boxWidth, height: boxHeight), background: .none)
        document.layers = [
            .shapeLayer(.rectangle, frame: CanvasRect(x: 0, y: 0, width: boxWidth, height: boxHeight), fill: .solid(CanvasColor.black.withAlpha(0.62)), radius: unit * 0.012),
            .textLayer(text, style, frame: CanvasRect(x: unit * 0.025, y: unit * 0.015, width: boxWidth - unit * 0.05, height: Double(measured.height) + 2)),
        ]
        // Above a lower third's usual spot in a tall frame, near the bottom in a wide one.
        let bottom = h > w ? h * 0.22 : unit * 0.07
        return (document, CGPoint(x: (w - boxWidth) / 2, y: h - bottom - boxHeight))
    }

    /// Renders a placed document and moves it to its spot in Core Image's bottom-up coordinates.
    static func draw(_ placed: Placed, in size: CGSize) -> CIImage? {
        guard let image = CanvasRenderer.cgImage(placed.document, images: { _ in nil }) else { return nil }
        let y = size.height - placed.origin.y - CGFloat(image.height)
        return CIImage(cgImage: image).transformed(by: CGAffineTransform(translationX: placed.origin.x, y: y))
    }
}

/// Sound measurements for the timeline: where people speak (for ducking), and the mix's loudness (for export).
enum VideoSound {
    static func speech(in url: URL) async -> [ClosedRange<Double>] {
        guard let audio = try? await Transcriber.audioFile(for: url), let sound = try? SoundIO.read(audio) else { return [] }
        return SoundMeter.speech(sound, threshold: -38, minimumGap: 0.5)
    }

    static func silenceCuts(in url: URL) async -> [ClosedRange<Double>] {
        guard let audio = try? await Transcriber.audioFile(for: url), let sound = try? SoundIO.read(audio) else { return [] }
        return SoundDSP.silenceCuts(sound, threshold: -40, minimum: 0.7, keep: 0.3)
    }

    /// The movie's sound as mixed (volumes, music, ducking and all), or nil when it's too long to hold in memory.
    static func mixdown(_ composition: AVMutableComposition, mix: AVAudioMix, limit: Double = maximumLevelled) async throws -> SoundBuffer? {
        let tracks = composition.tracks.filter { track in track.mediaType == .audio && track.segments.contains { !$0.isEmpty } }
        guard !tracks.isEmpty else { return SoundBuffer(sampleRate: 48_000, channelCount: 2, frames: 0) }
        guard composition.duration.seconds <= limit else { return nil }
        let reader = try AVAssetReader(asset: composition)
        let output = AVAssetReaderAudioMixOutput(audioTracks: tracks, audioSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: false, AVLinearPCMIsBigEndianKey: false, AVSampleRateKey: 48_000, AVNumberOfChannelsKey: 2,
        ])
        output.audioMix = mix
        output.audioTimePitchAlgorithm = .spectral
        reader.add(output)
        guard reader.startReading() else { throw reader.error ?? VideoError.export }
        let expected = Int(composition.duration.seconds * 48_000) + 4_800
        var left: [Float] = [], right: [Float] = []
        left.reserveCapacity(expected)
        right.reserveCapacity(expected)
        while let buffer = output.copyNextSampleBuffer() {
            guard let block = CMSampleBufferGetDataBuffer(buffer) else { continue }
            let length = CMBlockBufferGetDataLength(block)
            var bytes = [Float](repeating: 0, count: length / MemoryLayout<Float>.size)
            bytes.withUnsafeMutableBytes { pointer in
                _ = CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: pointer.baseAddress!)
            }
            for index in stride(from: 0, to: bytes.count - 1, by: 2) {
                left.append(bytes[index])
                right.append(bytes[index + 1])
            }
        }
        if reader.status == .failed { throw reader.error ?? VideoError.export }
        return SoundBuffer(sampleRate: 48_000, channels: [left, right])
    }

    /// Movies up to this long (in seconds) can have their sound brought to a loudness target.
    static let maximumLevelled = 20.0 * 60

    struct Levelled {
        let url: URL
        let before: Double
    }

    /// Mixes the movie's sound, brings it to a loudness target under a −1 dB ceiling and writes it to a file to put back under the picture.
    /// Nil when there's nothing to level or the movie is too long.
    static func levelled(_ composition: AVMutableComposition, mix: AVAudioMix, target: Double) async throws -> Levelled? {
        guard let sound = try await mixdown(composition, mix: mix), sound.frames > 0 else { return nil }
        let before = SoundMeter.loudness(sound)
        guard before.isFinite else { return nil }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("11am-levelled-\(UUID().uuidString).caf")
        try SoundIO.write(SoundDSP.loudness(sound, target: target, ceiling: -1), to: url, format: .caf)
        return Levelled(url: url, before: before)
    }
}

/// Loudness targets for export.
enum VideoLoudness: Double, CaseIterable, Identifiable {
    case asIs = 0, youtube = -14, podcast = -16

    var id: Double { rawValue }

    var title: String {
        switch self {
        case .asIs: return "Sound as it is"
        case .youtube: return "Sound at −14 LUFS (YouTube, Instagram)"
        case .podcast: return "Sound at −16 LUFS (podcast, LinkedIn)"
        }
    }
}
