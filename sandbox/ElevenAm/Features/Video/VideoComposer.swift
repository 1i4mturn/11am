import AVFoundation
import CoreImage
import Foundation

/// Turns the clips on the timeline into one playable, exportable movie: trims, transcript cuts and speed in the composition,
/// colour, reframing and dips in a Core Image pass per frame, volume and fades in the audio mix.
enum VideoComposer {
    static let dipLength = 0.6
    static let fadeLength = 0.8

    struct Built {
        let composition: AVMutableComposition
        let videoComposition: AVMutableVideoComposition
        let audioMix: AVMutableAudioMix
        let plan: CompositionPlan
    }

    static func build(_ clips: [VideoClip], settings: TimelineSettings, renderers: [UUID: GradeRenderer]) async throws -> Built {
        let composition = AVMutableComposition()
        guard let videoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
              let audioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw VideoError.export
        }
        var segments: [CompositionPlan.Segment] = []
        var blocks: [(start: Double, end: Double, volume: Float)] = []
        var cursor = CMTime.zero

        for clip in clips {
            let asset = AVURLAsset(url: clip.url)
            guard let sourceVideo = try await asset.loadTracks(withMediaType: .video).first else { continue }
            var sourceAudio: AVAssetTrack?
            if clip.hasAudio { sourceAudio = try await asset.loadTracks(withMediaType: .audio).first }
            if clip.useCleanAudio, let clean = clip.cleanAudio,
               let cleaned = try? await AVURLAsset(url: clean).loadTracks(withMediaType: .audio).first {
                sourceAudio = cleaned
            }
            let audioSpan = try await sourceAudio?.load(.timeRange)
            let blockStart = cursor
            var pieces: [(start: Double, end: Double)] = []
            for range in clip.keptRanges {
                let source = CMTimeRange(start: time(range.lowerBound), end: time(range.upperBound))
                try videoTrack.insertTimeRange(source, of: sourceVideo, at: cursor)
                if let sourceAudio, let audioSpan {
                    let overlap = source.intersection(audioSpan)
                    if overlap.duration > .zero {
                        let at = cursor + (overlap.start - source.start)
                        pad(audioTrack, to: at)
                        try audioTrack.insertTimeRange(overlap, of: sourceAudio, at: at)
                    }
                }
                var length = source.duration
                if abs(clip.speed - 1) > 0.001 {
                    let scaled = CMTimeMultiplyByFloat64(length, multiplier: 1 / clip.speed)
                    composition.scaleTimeRange(CMTimeRange(start: cursor, duration: length), toDuration: scaled)
                    length = scaled
                }
                pieces.append((cursor.seconds, (cursor + length).seconds))
                cursor = cursor + length
            }
            guard !pieces.isEmpty else { continue }
            for piece in pieces {
                segments.append(CompositionPlan.Segment(
                    clipID: clip.id, start: piece.start, end: piece.end,
                    blockStart: blockStart.seconds, blockEnd: cursor.seconds,
                    orientation: clip.orientation, reframe: clip.reframe
                ))
            }
            blocks.append((blockStart.seconds, cursor.seconds, clip.muted ? 0 : Float(clip.volume)))
        }
        guard !segments.isEmpty else { throw VideoError.noVideo }

        let plan = CompositionPlan(
            segments: segments,
            renderSize: settings.aspect.renderSize(original: clips.first?.size ?? CGSize(width: 1920, height: 1080)),
            total: cursor.seconds,
            transition: settings.transition,
            fades: settings.fades,
            fill: settings.aspect != .original,
            renderers: renderers
        )
        let videoComposition = AVMutableVideoComposition(asset: composition) { request in
            request.finish(with: plan.frame(request.sourceImage, at: request.compositionTime.seconds), context: nil)
        }
        videoComposition.renderSize = plan.renderSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)

        let parameters = AVMutableAudioMixInputParameters(track: audioTrack)
        parameters.audioTimePitchAlgorithm = .spectral
        let dipRamp = settings.transition == .cut ? 0 : dipLength / 2
        for (index, block) in blocks.enumerated() {
            let rampIn = index == 0 ? (settings.fades ? fadeLength : 0) : dipRamp
            let rampOut = index == blocks.count - 1 ? (settings.fades ? fadeLength : 0) : dipRamp
            let fits = rampIn + rampOut < block.end - block.start
            var steady = block.start
            if fits, rampIn > 0 {
                parameters.setVolumeRamp(fromStartVolume: 0, toEndVolume: block.volume, timeRange: CMTimeRange(start: time(block.start), duration: time(rampIn)))
                steady += rampIn
            }
            parameters.setVolume(block.volume, at: time(steady))
            if fits, rampOut > 0 {
                parameters.setVolumeRamp(fromStartVolume: block.volume, toEndVolume: 0, timeRange: CMTimeRange(start: time(block.end - rampOut), duration: time(rampOut)))
            }
        }
        let audioMix = AVMutableAudioMix()
        audioMix.inputParameters = [parameters]
        return Built(composition: composition, videoComposition: videoComposition, audioMix: audioMix, plan: plan)
    }

    /// Leaves silence up to a time, for clips with no sound or sound that starts late.
    private static func pad(_ track: AVMutableCompositionTrack, to time: CMTime) {
        let end = track.segments.isEmpty ? .zero : track.timeRange.end
        if time > end { track.insertEmptyTimeRange(CMTimeRange(start: end, end: time)) }
    }

    static func time(_ seconds: Double) -> CMTime {
        CMTime(seconds: seconds, preferredTimescale: 600)
    }

    /// Which way to turn a camera's frames so they stand upright.
    static func orientation(for t: CGAffineTransform) -> CGImagePropertyOrientation {
        if t.a == 0 && t.b == 1 && t.c == -1 && t.d == 0 { return .right }
        if t.a == 0 && t.b == -1 && t.c == 1 && t.d == 0 { return .left }
        if t.a == -1 && t.b == 0 && t.c == 0 && t.d == -1 { return .down }
        return .up
    }
}

/// What each moment of the movie needs: which clip, its grade, its framing, how far into a dip. Read on the video thread.
final class CompositionPlan: @unchecked Sendable {
    struct Segment {
        let clipID: UUID
        let start: Double
        let end: Double
        /// Where the whole clip starts and ends on the timeline, for dips between clips.
        let blockStart: Double
        let blockEnd: Double
        let orientation: CGImagePropertyOrientation
        let reframe: Double
    }

    let segments: [Segment]
    let renderSize: CGSize
    let total: Double
    let transition: VideoTransition
    let fades: Bool
    let fill: Bool
    private var renderers: [UUID: GradeRenderer]
    private let lock = NSLock()

    init(segments: [Segment], renderSize: CGSize, total: Double, transition: VideoTransition, fades: Bool, fill: Bool, renderers: [UUID: GradeRenderer]) {
        self.segments = segments
        self.renderSize = renderSize
        self.total = total
        self.transition = transition
        self.fades = fades
        self.fill = fill
        self.renderers = renderers
    }

    /// Swaps one clip's grade while the movie plays, without rebuilding anything.
    func setRenderer(_ renderer: GradeRenderer, for id: UUID) {
        lock.lock()
        renderers[id] = renderer
        lock.unlock()
    }

    private func renderer(for id: UUID) -> GradeRenderer? {
        lock.lock()
        defer { lock.unlock() }
        return renderers[id]
    }

    private func segment(at time: Double) -> Segment? {
        segments.first { time >= $0.start && time < $0.end } ?? segments.last
    }

    func frame(_ source: CIImage, at time: Double) -> CIImage {
        let bounds = CGRect(origin: .zero, size: renderSize)
        guard let segment = segment(at: time) else { return source.cropped(to: bounds) }
        var image = source.oriented(segment.orientation)
        image = image.transformed(by: CGAffineTransform(translationX: -image.extent.minX, y: -image.extent.minY))
        if let renderer = renderer(for: segment.clipID) {
            image = renderer.apply(to: image, frame: image.extent, seed: time).cropped(to: image.extent)
        }
        image = place(image, reframe: segment.reframe)
        if transition != .cut {
            let half = VideoComposer.dipLength / 2
            var amount = 1.0
            if segment.blockStart > 0.001 { amount = min(amount, (time - segment.blockStart) / half) }
            if segment.blockEnd < total - 0.001 { amount = min(amount, (segment.blockEnd - time) / half) }
            if amount < 1 { image = CompositionPlan.dissolve(image, white: transition == .dipWhite, amount: max(amount, 0)) }
        }
        if fades {
            let amount = min(time / VideoComposer.fadeLength, (total - time) / VideoComposer.fadeLength)
            if amount < 1 { image = CompositionPlan.dissolve(image, white: false, amount: max(amount, 0)) }
        }
        return image.cropped(to: bounds)
    }

    /// Fills the frame (cropping, with the reframe slider choosing what stays) or fits it with black bars.
    private func place(_ image: CIImage, reframe: Double) -> CIImage {
        let size = image.extent.size
        guard size.width > 0, size.height > 0 else { return image }
        let sx = renderSize.width / size.width
        let sy = renderSize.height / size.height
        let scale = fill ? max(sx, sy) : min(sx, sy)
        let w = size.width * scale
        let h = size.height * scale
        let overflowX = w - renderSize.width
        let overflowY = h - renderSize.height
        // Reframe runs from -1 (left or top) to 1 (right or bottom).
        let x = overflowX > 0 ? -overflowX / 2 * (1 + reframe) : -overflowX / 2
        let y = overflowY > 0 ? -overflowY / 2 * (1 - reframe) : -overflowY / 2
        let placed = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale).concatenating(CGAffineTransform(translationX: x, y: y)))
        return fill ? placed : placed.composited(over: CIImage(color: .black).cropped(to: CGRect(origin: .zero, size: renderSize)))
    }

    private static func dissolve(_ image: CIImage, white: Bool, amount a: Double) -> CIImage {
        let bias = white ? 1 - a : 0
        return image.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: a, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: a, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: a, w: 0),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
            "inputBiasVector": CIVector(x: bias, y: bias, z: bias, w: 0),
        ])
    }
}
