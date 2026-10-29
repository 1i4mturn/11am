import AppKit
import AVFoundation
import CoreImage
import Foundation
import UniformTypeIdentifiers

/// One clip on the timeline. Nothing here changes the source file; trims, cuts and colour are applied when it plays or exports.
struct VideoClip: Identifiable, Equatable {
    var id = UUID()
    var url: URL
    var name: String
    /// Length of the source file, in seconds.
    var duration: Double
    /// Upright size, after the camera's rotation.
    var size: CGSize
    var orientation: CGImagePropertyOrientation
    var hasAudio: Bool
    var inPoint: Double = 0
    var outPoint: Double
    var speed: Double = 1
    var volume: Double = 1
    var muted = false
    var grade = GradeSettings()
    /// Which part stays in shot when the frame shape crops: -1 left or top, 1 right or bottom.
    var reframe: Double = 0
    /// Transcript in source time; struck lines are cut.
    var lines: [TranscriptLine] = []
    var cleanAudio: URL?
    var useCleanAudio = false

    /// The source spans that play: the trimmed clip minus struck lines.
    var keptRanges: [ClosedRange<Double>] {
        var ranges: [ClosedRange<Double>] = [inPoint...max(outPoint, inPoint)]
        for line in lines where line.cut {
            ranges = ranges.flatMap { range -> [ClosedRange<Double>] in
                let start = max(line.start, range.lowerBound)
                let end = min(line.end, range.upperBound)
                guard start < end else { return [range] }
                var parts: [ClosedRange<Double>] = []
                if start - range.lowerBound > 0.04 { parts.append(range.lowerBound...start) }
                if range.upperBound - end > 0.04 { parts.append(end...range.upperBound) }
                return parts
            }
        }
        return ranges
    }

    /// How long the clip runs on the timeline.
    var editedDuration: Double {
        keptRanges.reduce(0) { $0 + ($1.upperBound - $1.lowerBound) } / speed
    }

    var cutCount: Int { lines.filter(\.cut).count }

    /// Timeline seconds from the clip's start to a source time, snapping forward out of cuts.
    func localTime(forSource source: Double) -> Double {
        var elapsed = 0.0
        for range in keptRanges {
            if source <= range.lowerBound { return elapsed / speed }
            if source <= range.upperBound { return (elapsed + source - range.lowerBound) / speed }
            elapsed += range.upperBound - range.lowerBound
        }
        return elapsed / speed
    }

    /// Source time at a point measured in timeline seconds from the clip's start.
    func sourceTime(atLocal local: Double) -> Double {
        var remaining = max(local, 0) * speed
        for range in keptRanges {
            let length = range.upperBound - range.lowerBound
            if remaining <= length { return range.lowerBound + remaining }
            remaining -= length
        }
        return outPoint
    }
}

enum VideoAspect: String, CaseIterable, Identifiable {
    case original, vertical, square, portrait, wide

    var id: String { rawValue }

    var title: String {
        switch self {
        case .original: return "Original"
        case .vertical: return "9:16 · Reels, TikTok"
        case .square: return "1:1 · Square"
        case .portrait: return "4:5 · Feed"
        case .wide: return "16:9 · YouTube"
        }
    }

    func renderSize(original: CGSize) -> CGSize {
        switch self {
        case .original:
            // Encoders want even numbers.
            return CGSize(width: max(2, (original.width / 2).rounded() * 2), height: max(2, (original.height / 2).rounded() * 2))
        case .vertical: return CGSize(width: 1080, height: 1920)
        case .square: return CGSize(width: 1080, height: 1080)
        case .portrait: return CGSize(width: 1080, height: 1350)
        case .wide: return CGSize(width: 1920, height: 1080)
        }
    }
}

enum VideoTransition: String, CaseIterable, Identifiable {
    case cut, dipBlack, dipWhite

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cut: return "Straight cut"
        case .dipBlack: return "Dip to black"
        case .dipWhite: return "Dip to white"
        }
    }
}

struct TimelineSettings: Equatable {
    var aspect: VideoAspect
    var transition: VideoTransition
    var fades: Bool
}

enum VideoExportPreset: String, CaseIterable, Identifiable {
    case high, hevc, small, prores, audio

    var id: String { rawValue }

    var title: String {
        switch self {
        case .high: return "High quality · H.264"
        case .hevc: return "Smaller file · HEVC"
        case .small: return "Quick share · 720p"
        case .prores: return "ProRes 422 · for more editing"
        case .audio: return "Sound only · M4A"
        }
    }

    var presetName: String {
        switch self {
        case .high: return AVAssetExportPresetHighestQuality
        case .hevc: return AVAssetExportPresetHEVCHighestQuality
        case .small: return AVAssetExportPreset1280x720
        case .prores: return AVAssetExportPresetAppleProRes422LPCM
        case .audio: return AVAssetExportPresetAppleM4A
        }
    }

    var fileType: AVFileType {
        switch self {
        case .high, .small: return .mp4
        case .hevc, .prores: return .mov
        case .audio: return .m4a
        }
    }

    var contentType: UTType {
        switch self {
        case .high, .small: return .mpeg4Movie
        case .hevc, .prores: return .quickTimeMovie
        case .audio: return .mpeg4Audio
        }
    }
}

/// The playhead, kept apart so ticking thirty times a second only redraws what shows the time.
@MainActor
final class PlaybackClock: ObservableObject {
    @Published var time: Double = 0
    @Published var isPlaying = false
}

private struct VideoSnapshot: Equatable {
    var clips: [VideoClip]
    var settings: TimelineSettings
}

/// Cole's Video: a timeline of clips you trim, split, reorder, speed up, grade and clean up, then export.
@MainActor
final class VideoModel: ObservableObject {
    @Published private(set) var clips: [VideoClip] = []
    @Published var selection: UUID? { didSet { if selection != oldValue { grabGradeFrame() } } }
    @Published var aspect: VideoAspect = .original { didSet { if aspect != oldValue { edited() } } }
    @Published var transition: VideoTransition = .dipBlack { didSet { if transition != oldValue { edited() } } }
    @Published var fades = true { didSet { if fades != oldValue { edited() } } }
    @Published private(set) var thumbnails: [UUID: [CGImage]] = [:]
    @Published private(set) var status = "Add clips to start, or try the samples. Everything runs on this Mac."
    @Published private(set) var isWorking = false
    @Published private(set) var exportProgress: Double?
    @Published private(set) var insightRun: BrainRun?
    @Published private(set) var canUndo = false
    @Published private(set) var canRedo = false
    @Published private(set) var renderSize = CGSize(width: 16, height: 9)

    let player = AVPlayer()
    let clock = PlaybackClock()

    private let brain: Brain
    private let looks: LookLibrary
    private var plan: CompositionPlan?
    private var rebuildTask: Task<Void, Never>?
    private var history: [VideoSnapshot] = []
    private var future: [VideoSnapshot] = []
    private var historyTask: Task<Void, Never>?
    private var restoring = false
    private var timeObserver: Any?
    /// A frame of the selected clip, for Auto in the colour panel.
    private(set) var gradeFrame: CIImage?

    init(brain: Brain, looks: LookLibrary) {
        self.brain = brain
        self.looks = looks
        history = [snapshot]
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 30), queue: .main) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self else { return }
                let seconds = time.seconds
                if seconds.isFinite, abs(self.clock.time - seconds) > 0.001 { self.clock.time = seconds }
                let playing = self.player.rate != 0
                if self.clock.isPlaying != playing { self.clock.isPlaying = playing }
            }
        }
    }

    var settings: TimelineSettings { TimelineSettings(aspect: aspect, transition: transition, fades: fades) }

    var selectedIndex: Int? { clips.firstIndex { $0.id == selection } }

    var selectedClip: VideoClip? { selectedIndex.map { clips[$0] } }

    var totalDuration: Double { clips.reduce(0) { $0 + $1.editedDuration } }

    /// Where each clip starts on the timeline.
    var starts: [Double] {
        var time = 0.0
        return clips.map { clip in
            defer { time += clip.editedDuration }
            return time
        }
    }

    private var snapshot: VideoSnapshot { VideoSnapshot(clips: clips, settings: settings) }

    // MARK: Adding clips

    func add(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        isWorking = true
        status = "Adding \(urls.count == 1 ? "a clip" : "\(urls.count) clips")…"
        Task {
            var added: [VideoClip] = []
            var failed = 0
            for url in urls {
                if let clip = try? await VideoModel.loadClip(url) { added.append(clip) } else { failed += 1 }
            }
            isWorking = false
            guard !added.isEmpty else {
                status = "That file couldn't be added. Cole works with video files (MOV, MP4, M4V)."
                return
            }
            clips.append(contentsOf: added)
            if selection == nil { selection = added.first?.id }
            added.forEach(makeThumbnails(for:))
            status = failed > 0 ? "\(added.count) added; \(failed) couldn't be read." : "Drag a clip's edges to trim. Split at the playhead with ⌘B."
            edited()
        }
    }

    func loadSamples() {
        isWorking = true
        status = "Making two sample clips…"
        Task {
            do {
                let urls = try await SampleMedia.makeClips()
                isWorking = false
                add(urls)
            } catch {
                isWorking = false
                status = error.localizedDescription
            }
        }
    }

    nonisolated private static func loadClip(_ url: URL) async throws -> VideoClip {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration).seconds
        guard let track = try await asset.loadTracks(withMediaType: .video).first else { throw VideoError.noVideo }
        let (natural, transform) = try await track.load(.naturalSize, .preferredTransform)
        let hasAudio = !(try await asset.loadTracks(withMediaType: .audio)).isEmpty
        let orientation = VideoComposer.orientation(for: transform)
        let turned = orientation == .left || orientation == .right
        return VideoClip(
            url: url,
            name: url.deletingPathExtension().lastPathComponent,
            duration: duration,
            size: turned ? CGSize(width: natural.height, height: natural.width) : natural,
            orientation: orientation,
            hasAudio: hasAudio,
            outPoint: duration
        )
    }

    private func makeThumbnails(for clip: VideoClip) {
        let url = clip.url
        let duration = clip.duration
        let id = clip.id
        Task {
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 220, height: 220)
            generator.requestedTimeToleranceBefore = CMTime(seconds: 0.4, preferredTimescale: 600)
            generator.requestedTimeToleranceAfter = CMTime(seconds: 0.4, preferredTimescale: 600)
            var images: [CGImage] = []
            for index in 0..<12 {
                let time = CMTime(seconds: duration * (Double(index) + 0.5) / 12, preferredTimescale: 600)
                if let result = try? await generator.image(at: time) { images.append(result.image) }
            }
            // Split and duplicated clips share their source's thumbnails.
            for clip in clips where clip.url == url { thumbnails[clip.id] = images }
            thumbnails[id] = images
        }
    }

    /// Thumbnail of a source time in a clip, picked from the dozen made when it was added.
    func thumbnail(for clip: VideoClip, at source: Double) -> CGImage? {
        guard let images = thumbnails[clip.id], !images.isEmpty, clip.duration > 0 else { return nil }
        let index = Int(source / clip.duration * Double(images.count))
        return images[min(max(index, 0), images.count - 1)]
    }

    private func grabGradeFrame() {
        gradeFrame = nil
        guard let clip = selectedClip else { return }
        let id = clip.id
        let url = clip.url
        let time = CMTime(seconds: (clip.inPoint + clip.outPoint) / 2, preferredTimescale: 600)
        Task {
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 960, height: 960)
            if let result = try? await generator.image(at: time), selection == id {
                gradeFrame = CIImage(cgImage: result.image)
            }
        }
    }

    // MARK: Editing

    func updateSelected(_ change: (inout VideoClip) -> Void) {
        guard let selection else { return }
        update(selection, change)
    }

    func update(_ id: UUID, _ change: (inout VideoClip) -> Void) {
        guard let index = clips.firstIndex(where: { $0.id == id }) else { return }
        let before = clips[index]
        change(&clips[index])
        guard clips[index] != before else { return }
        // Colour alone is swapped into the running movie; anything else rebuilds it.
        var other = before
        other.grade = clips[index].grade
        if other == clips[index] {
            applyGrade(at: index)
        } else {
            edited()
        }
    }

    /// The colour panel's binding for the selected clip.
    func setGrade(_ grade: GradeSettings) {
        updateSelected { $0.grade = grade }
    }

    func applyGradeToAll() {
        guard let grade = selectedClip?.grade else { return }
        for index in clips.indices { clips[index].grade = grade }
        clips.indices.forEach(applyGrade(at:))
        status = "Same colour on all \(clips.count) clips."
    }

    private func applyGrade(at index: Int) {
        plan?.setRenderer(looks.renderer(for: clips[index].grade), for: clips[index].id)
        refreshFrame()
        scheduleHistory()
    }

    /// Trim from either edge. Times are in the source; the clip keeps at least a fifth of a second.
    func trim(_ id: UUID, inPoint: Double? = nil, outPoint: Double? = nil) {
        update(id) { clip in
            if let inPoint { clip.inPoint = min(max(inPoint, 0), clip.outPoint - 0.2) }
            if let outPoint { clip.outPoint = max(min(outPoint, clip.duration), clip.inPoint + 0.2) }
        }
    }

    func splitAtPlayhead() {
        let time = clock.time
        let starts = self.starts
        guard let index = clips.indices.last(where: { starts[$0] <= time }) else { return }
        let clip = clips[index]
        let source = clip.sourceTime(atLocal: time - starts[index])
        guard source > clip.inPoint + 0.1, source < clip.outPoint - 0.1 else {
            status = "Move the playhead inside a clip to split it."
            return
        }
        var first = clip
        first.outPoint = source
        var second = clip
        second.id = UUID()
        second.inPoint = source
        clips[index] = first
        clips.insert(second, at: index + 1)
        thumbnails[second.id] = thumbnails[clip.id]
        selection = second.id
        edited()
    }

    func deleteSelected() {
        guard let index = selectedIndex else { return }
        clips.remove(at: index)
        selection = clips.indices.contains(index) ? clips[index].id : clips.last?.id
        edited()
    }

    func duplicateSelected() {
        guard let index = selectedIndex else { return }
        var copy = clips[index]
        copy.id = UUID()
        clips.insert(copy, at: index + 1)
        thumbnails[copy.id] = thumbnails[clips[index].id]
        selection = copy.id
        edited()
    }

    func moveSelected(by offset: Int) {
        guard let index = selectedIndex else { return }
        let target = index + offset
        guard clips.indices.contains(target) else { return }
        clips.swapAt(index, target)
        edited()
    }

    private func edited() {
        guard !restoring else { return }
        rebuild()
        scheduleHistory()
    }

    // MARK: Playback

    func togglePlay() {
        guard player.currentItem != nil else { return }
        if player.rate != 0 {
            player.pause()
        } else {
            if clock.time >= totalDuration - 0.05 { seek(to: 0) }
            player.play()
        }
        clock.isPlaying = player.rate != 0
    }

    func seek(to time: Double) {
        let target = min(max(time, 0), max(totalDuration - 0.01, 0))
        clock.time = target
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func step(_ frames: Int) {
        player.pause()
        seek(to: clock.time + Double(frames) / 30)
    }

    /// Selects a clip and puts the playhead at its start.
    func select(_ id: UUID, at local: Double? = nil) {
        selection = id
        guard let index = clips.firstIndex(where: { $0.id == id }) else { return }
        seek(to: starts[index] + (local ?? 0))
    }

    private func rebuild() {
        rebuildTask?.cancel()
        rebuildTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard !Task.isCancelled else { return }
            await performRebuild()
        }
    }

    private func performRebuild() async {
        guard !clips.isEmpty else {
            player.replaceCurrentItem(with: nil)
            plan = nil
            clock.time = 0
            return
        }
        let renderers = Dictionary(clips.map { ($0.id, looks.renderer(for: $0.grade)) }, uniquingKeysWith: { first, _ in first })
        let wasPlaying = player.rate != 0
        let time = clock.time
        do {
            let built = try await VideoComposer.build(clips, settings: settings, renderers: renderers)
            guard !Task.isCancelled else { return }
            let item = AVPlayerItem(asset: built.composition)
            item.videoComposition = built.videoComposition
            item.audioMix = built.audioMix
            item.audioTimePitchAlgorithm = .spectral
            plan = built.plan
            renderSize = built.plan.renderSize
            player.replaceCurrentItem(with: item)
            seek(to: min(time, max(built.plan.total - 0.05, 0)))
            if wasPlaying { player.play() }
        } catch {
            status = error.localizedDescription
        }
    }

    /// Shows a new grade on the paused frame straight away.
    private func refreshFrame() {
        guard player.rate == 0, let item = player.currentItem,
              let composition = item.videoComposition?.mutableCopy() as? AVVideoComposition else { return }
        item.videoComposition = composition
    }

    // MARK: History

    private func scheduleHistory() {
        historyTask?.cancel()
        historyTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 450_000_000)
            guard !Task.isCancelled else { return }
            self.commitHistory()
        }
    }

    private func commitHistory() {
        let current = snapshot
        guard history.last != current else { return }
        history.append(current)
        if history.count > 80 { history.removeFirst() }
        future = []
        updateUndoState()
    }

    func undo() {
        historyTask?.cancel()
        commitHistory()
        guard history.count > 1, let last = history.popLast() else { return }
        future.append(last)
        restore(history[history.count - 1])
    }

    func redo() {
        guard let next = future.popLast() else { return }
        history.append(next)
        restore(next)
    }

    private func restore(_ state: VideoSnapshot) {
        restoring = true
        clips = state.clips
        aspect = state.settings.aspect
        transition = state.settings.transition
        fades = state.settings.fades
        restoring = false
        if let selection, !clips.contains(where: { $0.id == selection }) { self.selection = clips.first?.id }
        updateUndoState()
        rebuild()
    }

    private func updateUndoState() {
        canUndo = history.count > 1
        canRedo = !future.isEmpty
    }

    // MARK: Sound

    func cleanVoice() {
        guard let clip = selectedClip else { return }
        guard clip.hasAudio else {
            status = "This clip has no sound to clean up."
            return
        }
        isWorking = true
        status = "Cleaning up the voice in \(clip.name) on this Mac…"
        Task {
            defer { isWorking = false }
            do {
                let result = try await VoiceCleanup.clean(clip.url)
                update(clip.id) { clip in
                    clip.cleanAudio = result.url
                    clip.useCleanAudio = true
                }
                status = result.isolated
                    ? "Voice isolated, rumble taken out and levelled."
                    : "Rumble taken out and levelled. Voice Isolation isn't available on this Mac."
            } catch {
                status = error.localizedDescription
            }
        }
    }

    // MARK: Words

    func transcribeSelected() {
        guard let clip = selectedClip else { return }
        guard clip.hasAudio else {
            status = "This clip has no sound to transcribe."
            return
        }
        isWorking = true
        status = "Transcribing \(clip.name) on this Mac…"
        Task {
            defer { isWorking = false }
            do {
                let lines = try await Transcriber.transcribe(clip.url)
                update(clip.id) { $0.lines = lines }
                status = lines.isEmpty ? "No speech found." : "\(lines.count) lines. Strike a line to cut it from the video and the captions."
            } catch {
                status = error.localizedDescription
            }
        }
    }

    func toggleCut(_ line: TranscriptLine) {
        updateSelected { clip in
            guard let index = clip.lines.firstIndex(where: { $0.id == line.id }) else { return }
            clip.lines[index].cut.toggle()
        }
    }

    func jump(to line: TranscriptLine) {
        guard let index = selectedIndex else { return }
        seek(to: starts[index] + clips[index].localTime(forSource: line.start))
    }

    /// Captions for the edited movie: struck and trimmed lines are dropped, the rest moved to where they now play.
    func exportCaptions() {
        var output = ""
        var number = 0
        for (clip, start) in zip(clips, starts) {
            for line in clip.lines where !line.cut {
                let from = start + clip.localTime(forSource: max(line.start, clip.inPoint))
                let to = start + clip.localTime(forSource: min(line.end, clip.outPoint))
                guard to - from > 0.2 else { continue }
                number += 1
                output += "\(number)\n\(VideoModel.srtTime(from)) --> \(VideoModel.srtTime(to))\n\(line.text)\n\n"
            }
        }
        guard number > 0 else {
            status = "Transcribe a clip first; captions come from the words."
            return
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "srt") ?? .plainText]
        panel.nameFieldStringValue = "\(clips.first?.name ?? "captions").srt"
        if panel.runModal() == .OK, let url = panel.url {
            try? output.write(to: url, atomically: true, encoding: .utf8)
            status = "Saved \(url.lastPathComponent)."
        }
    }

    func insights() {
        var transcript: [String] = []
        for (clip, start) in zip(clips, starts) {
            for line in clip.lines where !line.cut && line.end > clip.inPoint && line.start < clip.outPoint {
                transcript.append("[\(VideoModel.clock(start + clip.localTime(forSource: line.start)))] \(line.text)")
            }
        }
        guard !transcript.isEmpty else {
            status = "Transcribe a clip first; titles and chapters come from the words."
            return
        }
        let system = """
        You are Cole, the video agent inside 11am. From the transcript, write: a title (under 60 characters), \
        a two-sentence description, and chapters as lines starting with a timestamp like 0:00. Use only what's said.
        """
        insightRun = brain.run(BrainRequest(system: system, prompt: String(transcript.joined(separator: "\n").prefix(8_000)), weight: .quick))
    }

    // MARK: Export

    func export(_ preset: VideoExportPreset) {
        guard !clips.isEmpty else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [preset.contentType]
        panel.nameFieldStringValue = "\(clips.first?.name ?? "Video") (edited).\(preset.contentType.preferredFilenameExtension ?? "mov")"
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        player.pause()
        let renderers = Dictionary(clips.map { ($0.id, looks.renderer(for: $0.grade)) }, uniquingKeysWith: { first, _ in first })
        let clips = self.clips
        let settings = self.settings
        isWorking = true
        exportProgress = 0
        status = "Exporting \(destination.lastPathComponent)…"
        Task {
            defer {
                isWorking = false
                exportProgress = nil
            }
            do {
                let built = try await VideoComposer.build(clips, settings: settings, renderers: renderers)
                try? FileManager.default.removeItem(at: destination)
                guard let session = AVAssetExportSession(asset: built.composition, presetName: preset.presetName) else { throw VideoError.export }
                session.outputURL = destination
                session.outputFileType = preset.fileType
                session.audioMix = built.audioMix
                if preset != .audio { session.videoComposition = built.videoComposition }
                let progress = Task { @MainActor in
                    while !Task.isCancelled {
                        exportProgress = Double(session.progress)
                        try? await Task.sleep(nanoseconds: 200_000_000)
                    }
                }
                await session.export()
                progress.cancel()
                guard session.status == .completed else { throw session.error ?? VideoError.export }
                status = "Saved \(destination.lastPathComponent)."
            } catch {
                status = error.localizedDescription
            }
        }
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

    /// Minutes, seconds and frames, like an editor shows them.
    static func timecode(_ seconds: Double) -> String {
        let total = max(0, seconds)
        let frames = Int((total - floor(total)) * 30)
        return String(format: "%d:%02d:%02d", Int(total) / 60, Int(total) % 60, frames)
    }
}
