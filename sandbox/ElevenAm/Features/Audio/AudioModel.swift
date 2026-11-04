import AppKit
import AVFoundation
import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct SoundProjectEntry: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var duration: Double
    var modified: Date
}

/// Cole's Audio: multitrack projects on this Mac, recorded or imported, edited, cleaned up and exported.
@MainActor
final class AudioModel: ObservableObject {
    @Published private(set) var entries: [SoundProjectEntry] = []
    @Published private(set) var project: SoundProject?
    @Published var selectedClip: UUID?
    @Published var selectedTrack: UUID?
    /// A time selection on the ruler, for editing a stretch.
    @Published var range: ClosedRange<Double>?
    @Published var playhead: Double = 0
    @Published private(set) var isPlaying = false
    @Published var zoom: Double = 60
    @Published var panelTab = 0
    /// Set by a launch flag: select the first clip once a project is open (the sample is made after launch).
    var selectFirstClip = false
    @Published var notice: String?
    @Published private(set) var working: String?
    @Published private(set) var loudness: Double?
    @Published private(set) var silences: [ClosedRange<Double>] = []
    @Published var notesRun: BrainRun?
    @Published private(set) var recordingKind: RecordingKind?
    @Published private(set) var recordingLevel: Double = -80
    @Published private(set) var canUndo = false
    @Published private(set) var canRedo = false
    /// Waveform peaks per asset, about 200 per second.
    @Published private(set) var peaks: [String: [(low: Float, high: Float)]] = [:]

    enum RecordingKind { case microphone, mac }

    let root = JSONStore.folder.appendingPathComponent("Audio", isDirectory: true)
    let mic = MicRecorder()
    private let macSound = MacSoundRecorder()
    private var recordingURL: URL?
    private var recordingStart: Double = 0
    private var sources: [String: SoundBuffer] = [:]
    private var undoStack: [SoundProject] = []
    private var redoStack: [SoundProject] = []
    private var saveTask: Task<Void, Never>?
    private let brain: Brain

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var playStart: Double = 0
    private var playTimer: Timer?

    static let peaksPerSecond = 200.0

    init(brain: Brain) {
        self.brain = brain
        engine.attach(player)
    }

    // MARK: Files

    private func folder(_ id: UUID) -> URL { root.appendingPathComponent(id.uuidString, isDirectory: true) }

    func load() {
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let folders = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        var found: [SoundProjectEntry] = []
        for folder in folders {
            guard let data = try? Data(contentsOf: folder.appendingPathComponent("project.json")),
                  let project = try? Self.decoder.decode(SoundProject.self, from: data) else { continue }
            found.append(SoundProjectEntry(id: project.id, name: project.name, duration: project.duration, modified: project.modified))
        }
        entries = found.sorted { $0.modified > $1.modified }
        // Earlier versions could save the sample empty; make it again.
        if let empty = entries.first(where: { $0.name == Self.sampleName && $0.duration == 0 }) {
            try? FileManager.default.removeItem(at: folder(empty.id))
            entries.removeAll { $0.id == empty.id }
            UserDefaults.standard.set(false, forKey: "audio.seeded")
        }
        if entries.isEmpty && !UserDefaults.standard.bool(forKey: "audio.seeded") {
            Task { await makeSample() }
        } else if project == nil, let first = entries.first {
            open(first.id)
        }
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private func write(_ project: SoundProject) {
        let directory = folder(project.id)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let data = try? Self.encoder.encode(project) { try? data.write(to: directory.appendingPathComponent("project.json"), options: .atomic) }
        let entry = SoundProjectEntry(id: project.id, name: project.name, duration: project.duration, modified: project.modified)
        if let index = entries.firstIndex(where: { $0.id == project.id }) { entries[index] = entry } else { entries.insert(entry, at: 0) }
    }

    func flushSave() {
        saveTask?.cancel()
        if let project { write(project) }
    }

    func open(_ id: UUID) {
        flushSave()
        stop()
        guard let data = try? Data(contentsOf: folder(id).appendingPathComponent("project.json")),
              let loaded = try? Self.decoder.decode(SoundProject.self, from: data) else { return }
        sources = [:]
        peaks = [:]
        undoStack = []
        redoStack = []
        project = loaded
        selectedTrack = loaded.tracks.first?.id
        selectedClip = nil
        range = nil
        playhead = 0
        silences = []
        loadAssets()
        updateHistoryFlags()
        selectFirstClipIfAsked()
    }

    func selectFirstClipIfAsked() {
        guard selectFirstClip, let project, let first = project.tracks.first?.clips.first else { return }
        selectFirstClip = false
        selectedClip = first.id
        selectedTrack = project.tracks.first?.id
    }

    func open(named name: String) {
        if let entry = entries.first(where: { $0.name.localizedCaseInsensitiveContains(name) }) { open(entry.id) }
    }

    func newProject() {
        flushSave()
        let fresh = SoundProject(name: "Untitled recording", tracks: [SoundTrack(name: "Voice"), SoundTrack(name: "Music")])
        write(fresh)
        open(fresh.id)
    }

    func delete(_ id: UUID) {
        NSWorkspace.shared.recycle([folder(id)]) { _, _ in }
        entries.removeAll { $0.id == id }
        if project?.id == id {
            project = nil
            if let first = entries.first { open(first.id) }
        }
    }

    func rename(_ name: String) {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        change { $0.name = name }
    }

    /// Decodes every sound the project uses, off the main thread, and makes the waveforms.
    private func loadAssets() {
        guard let project else { return }
        let assets = Set(project.tracks.flatMap(\.clips).map(\.asset)).filter { sources[$0] == nil }
        let directory = folder(project.id)
        for asset in assets {
            let url = directory.appendingPathComponent(asset)
            Task.detached(priority: .userInitiated) {
                guard let sound = try? SoundIO.read(url) else { return }
                let buckets = max(1, Int(sound.duration * AudioModel.peaksPerSecond))
                let waveform = SoundMeter.peaks(sound, buckets: buckets)
                await MainActor.run { [weak self] in
                    self?.sources[asset] = sound
                    self?.peaks[asset] = waveform
                    self?.measure()
                }
            }
        }
    }

    func source(_ asset: String) -> SoundBuffer? { sources[asset] }

    /// Saves a sound into the project's folder and returns its asset name.
    private func store(_ sound: SoundBuffer, name: String = "sound") -> String? {
        guard let project else { return nil }
        let asset = "\(name.replacingOccurrences(of: "/", with: "-"))-\(UUID().uuidString.prefix(8)).caf"
        let directory = folder(project.id)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        do {
            try SoundIO.write(sound, to: directory.appendingPathComponent(asset), format: .caf)
        } catch {
            notice = "Couldn't save the sound: \(error.localizedDescription)"
            return nil
        }
        sources[asset] = sound
        peaks[asset] = SoundMeter.peaks(sound, buckets: max(1, Int(sound.duration * Self.peaksPerSecond)))
        return asset
    }

    // MARK: Changing

    func change(_ edit: (inout SoundProject) -> Void) {
        guard var current = project else { return }
        let before = current
        edit(&current)
        guard current != before else { return }
        current.modified = Date()
        undoStack.append(before)
        if undoStack.count > 60 { undoStack.removeFirst() }
        redoStack.removeAll()
        project = current
        afterChange()
    }

    private func afterChange() {
        updateHistoryFlags()
        if isPlaying { play(from: playhead) }
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            guard (try? await Task.sleep(for: .milliseconds(600))) != nil else { return }
            self?.flushSave()
            self?.measure()
        }
    }

    private func updateHistoryFlags() {
        canUndo = !undoStack.isEmpty
        canRedo = !redoStack.isEmpty
    }

    func undo() {
        guard let previous = undoStack.popLast(), let current = project else { return }
        redoStack.append(current)
        project = previous
        loadAssets()
        afterChange()
    }

    func redo() {
        guard let next = redoStack.popLast(), let current = project else { return }
        undoStack.append(current)
        project = next
        loadAssets()
        afterChange()
    }

    var clip: SoundClip? {
        guard let id = selectedClip, let project, let found = project.clip(id) else { return nil }
        return project.tracks[found.track].clips[found.index]
    }

    var trackIndex: Int {
        guard let project else { return 0 }
        return project.tracks.firstIndex { $0.id == selectedTrack } ?? 0
    }

    // MARK: Measuring

    func mixdown(_ range: ClosedRange<Double>? = nil) -> SoundBuffer? {
        guard let project else { return nil }
        return SoundMixer.render(project, sources: { [sources] in sources[$0] }, range: range)
    }

    /// Loudness of the whole mix, and the silences on the selected track.
    func measure() {
        guard let project, project.duration > 0.5 else {
            loudness = nil
            return
        }
        let sources = sources
        let trackOnly = project.tracks.indices.contains(trackIndex) ? {
            var solo = project
            for index in solo.tracks.indices { solo.tracks[index].solo = index == trackIndex }
            return solo
        }() : project
        Task.detached(priority: .utility) {
            let mix = SoundMixer.render(project, sources: { sources[$0] })
            let value = SoundMeter.loudness(mix)
            let quiet = SoundMeter.silences(SoundMixer.render(trackOnly, sources: { sources[$0] }), threshold: -42, minimum: 0.8)
            await MainActor.run { [weak self] in
                self?.loudness = value.isFinite ? value : nil
                self?.silences = quiet
            }
        }
    }

    // MARK: Playing

    func togglePlay() {
        if isPlaying { stop() } else { play(from: playhead >= (project?.duration ?? 0) - 0.05 ? 0 : playhead) }
    }

    func play(from time: Double) {
        guard let project, let mix = mixdown(time...max(time + 0.05, project.duration)), let buffer = SoundIO.pcmBuffer(mix) else { return }
        player.stop()
        engine.disconnectNodeOutput(player)
        engine.connect(player, to: engine.mainMixerNode, format: buffer.format)
        if !engine.isRunning { try? engine.start() }
        player.scheduleBuffer(buffer, at: nil)
        player.play()
        playStart = time
        playhead = time
        isPlaying = true
        playTimer?.invalidate()
        playTimer = Timer.scheduledTimer(withTimeInterval: 1 / 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    private func tick() {
        guard isPlaying, let nodeTime = player.lastRenderTime, let time = player.playerTime(forNodeTime: nodeTime) else { return }
        playhead = playStart + Double(time.sampleTime) / time.sampleRate
        if playhead >= (project?.duration ?? 0) { stop() }
    }

    func stop() {
        player.stop()
        playTimer?.invalidate()
        playTimer = nil
        isPlaying = false
    }

    func seek(_ time: Double) {
        let clamped = max(0, min(time, project?.duration ?? 0))
        if isPlaying { play(from: clamped) } else { playhead = clamped }
    }

    // MARK: Recording

    func record(_ kind: RecordingKind) {
        guard project != nil, recordingKind == nil else { return }
        stop()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("11am-recording-\(UUID().uuidString).caf")
        recordingURL = url
        recordingStart = playhead
        Task {
            do {
                switch kind {
                case .microphone:
                    guard await MicRecorder.permission() else {
                        notice = "11am needs the microphone. Turn it on in System Settings › Privacy & Security › Microphone."
                        return
                    }
                    try mic.start(to: url)
                case .mac:
                    macSound.onLevel = { [weak self] level in Task { @MainActor in self?.recordingLevel = level } }
                    macSound.onError = { [weak self] message in Task { @MainActor in self?.notice = message } }
                    try await macSound.start(to: url)
                }
                recordingKind = kind
            } catch {
                notice = kind == .mac
                    ? "Recording the Mac's sound needs Screen & System Audio Recording. Turn 11am on in System Settings › Privacy & Security, then try again."
                    : "Couldn't start recording: \(error.localizedDescription)"
            }
        }
    }

    func stopRecording() {
        guard let kind = recordingKind, let url = recordingURL else { return }
        Task {
            if kind == .microphone { mic.stop() } else { await macSound.stop() }
            recordingKind = nil
            recordingLevel = -80
            guard let sound = try? SoundIO.read(url), sound.frames > 0 else {
                notice = "Nothing was recorded."
                return
            }
            addClip(sound, name: kind == .microphone ? "Recording" : "Mac sound", at: recordingStart)
            try? FileManager.default.removeItem(at: url)
        }
    }

    var recordingElapsed: Double { mic.elapsed }

    // MARK: Adding

    func importFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.audio, .movie]
        guard panel.runModal() == .OK else { return }
        working = "Reading \(panel.urls.count == 1 ? panel.urls[0].lastPathComponent : "\(panel.urls.count) files")…"
        let urls = panel.urls
        Task {
            var at = playhead
            for url in urls {
                var source = url
                if !["wav", "aif", "aiff", "caf", "m4a", "mp3", "flac", "aac"].contains(url.pathExtension.lowercased()) {
                    source = (try? await Transcriber.audioFile(for: url)) ?? url
                }
                guard let sound = try? SoundIO.read(source) else {
                    notice = "Couldn't read \(url.lastPathComponent)."
                    continue
                }
                addClip(sound, name: url.deletingPathExtension().lastPathComponent, at: at)
                at += sound.duration
            }
            working = nil
        }
    }

    func addClip(_ sound: SoundBuffer, name: String, at start: Double, track: Int? = nil) {
        guard let asset = store(sound, name: "clip") else { return }
        let clip = SoundClip(name: name, asset: asset, start: start, outPoint: sound.duration)
        let target = track ?? trackIndex
        change { project in
            if project.tracks.isEmpty { project.tracks.append(SoundTrack(name: "Voice")) }
            let index = min(target, project.tracks.count - 1)
            // If it would overlap another clip, it goes on a new track instead.
            let clash = project.tracks[index].clips.contains { $0.start < clip.end && $0.end > clip.start }
            if clash {
                project.tracks.append(SoundTrack(name: name, clips: [clip]))
            } else {
                project.tracks[index].clips.append(clip)
                project.tracks[index].clips.sort { $0.start < $1.start }
            }
        }
        selectedClip = clip.id
    }

    func addTrack() {
        change { $0.tracks.append(SoundTrack(name: "Track \($0.tracks.count + 1)")) }
    }

    func updateTrack(_ id: UUID, _ edit: (inout SoundTrack) -> Void) {
        change { project in
            if let index = project.tracks.firstIndex(where: { $0.id == id }) { edit(&project.tracks[index]) }
        }
    }

    func deleteTrack(_ id: UUID) {
        change { $0.tracks.removeAll { $0.id == id } }
    }

    // MARK: Editing

    func split() {
        guard let project else { return }
        let target = selectedClip.flatMap { id in project.clip(id) != nil ? id : nil }
            ?? project.tracks[trackIndex].clips.first { $0.start < playhead && $0.end > playhead }?.id
        guard let id = target else { return }
        let time = playhead
        var right: UUID?
        change { right = SoundEdit.split(&$0, clip: id, at: time) }
        if let right { selectedClip = right }
    }

    /// Deletes the selected stretch (closing the gap on every track) or the selected clip.
    func delete() {
        if let range {
            change { SoundEdit.delete(&$0, range: range) }
            self.range = nil
            playhead = range.lowerBound
        } else if let id = selectedClip {
            change { project in
                if let found = project.clip(id) { project.tracks[found.track].clips.remove(at: found.index) }
            }
            selectedClip = nil
        }
    }

    func duplicate() {
        guard let clip else { return }
        var copy = clip
        copy.id = UUID()
        copy.start = clip.end
        change { project in
            if let found = project.clip(clip.id) {
                project.tracks[found.track].clips.append(copy)
                project.tracks[found.track].clips.sort { $0.start < $1.start }
            }
        }
        selectedClip = copy.id
    }

    func move(_ id: UUID, to start: Double) {
        change { SoundEdit.move(&$0, clip: id, to: start) }
    }

    func setFades(fadeIn: Double? = nil, fadeOut: Double? = nil) {
        guard let id = selectedClip else { return }
        change { project in
            guard let found = project.clip(id) else { return }
            if let fadeIn { project.tracks[found.track].clips[found.index].fadeIn = fadeIn }
            if let fadeOut { project.tracks[found.track].clips[found.index].fadeOut = fadeOut }
        }
    }

    func setClipGain(_ gain: Double) {
        guard let id = selectedClip else { return }
        change { project in
            if let found = project.clip(id) { project.tracks[found.track].clips[found.index].gain = gain }
        }
    }

    func addMarker() {
        let time = playhead
        change { project in
            project.markers.append(SoundMarker(time: time, name: "Chapter \(project.markers.count + 1)"))
            project.markers.sort { $0.time < $1.time }
        }
    }

    func renameMarker(_ id: UUID, _ name: String) {
        change { project in
            if let index = project.markers.firstIndex(where: { $0.id == id }) { project.markers[index].name = name }
        }
    }

    func deleteMarker(_ id: UUID) {
        change { $0.markers.removeAll { $0.id == id } }
    }

    // MARK: Effects

    /// Runs an effect on the selected clip (or the selected stretch of it), keeping the original for undo.
    func apply(_ effect: SoundEffect) {
        guard let project else { return }
        var targetID = selectedClip
        // A time selection inside one clip: split it out first.
        if let range, let id = targetID ?? project.tracks[trackIndex].clips.first(where: { $0.start < range.upperBound && $0.end > range.lowerBound })?.id {
            var working = project
            if let right = SoundEdit.split(&working, clip: id, at: range.lowerBound) { targetID = right } else { targetID = id }
            if let target = targetID { _ = SoundEdit.split(&working, clip: target, at: range.upperBound) }
            self.project = working
            undoStack.append(project)
        }
        guard let id = targetID, let found = self.project?.clip(id), let clip = self.project?.tracks[found.track].clips[found.index],
              let source = sources[clip.asset] else {
            notice = "Pick a clip first."
            return
        }
        working = "\(effect.title)…"
        let piece = source.slice(clip.inPoint, clip.outPoint)
        Task {
            var processed: SoundBuffer?
            if effect == .studioSound {
                processed = await studioSound(piece)
            } else {
                processed = await Task.detached(priority: .userInitiated) { try? SoundDSP.apply(effect, to: piece) }.value
            }
            working = nil
            guard let processed, let asset = store(processed, name: "fx") else {
                notice = "\(effect.title) didn't work on that clip."
                return
            }
            change { project in
                guard let found = project.clip(id) else { return }
                project.tracks[found.track].clips[found.index].asset = asset
                project.tracks[found.track].clips[found.index].inPoint = 0
                project.tracks[found.track].clips[found.index].outPoint = processed.duration
            }
            selectedClip = id
            range = nil
            notice = "\(effect.title) done. Undo brings the original back."
        }
    }

    /// Voice Isolation (Apple's, on this Mac) and then the studio chain.
    private func studioSound(_ sound: SoundBuffer) async -> SoundBuffer? {
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("11am-studio-\(UUID().uuidString).caf")
        try? SoundIO.write(sound, to: temporary, format: .caf)
        var isolated = sound
        if let result = try? await VoiceCleanup.clean(temporary), let cleaned = try? SoundIO.read(result.url) {
            isolated = cleaned.sampleRate == sound.sampleRate ? cleaned : cleaned.resampled(to: sound.sampleRate)
        }
        try? FileManager.default.removeItem(at: temporary)
        let input = isolated
        return await Task.detached(priority: .userInitiated) { try? SoundDSP.apply(.studioSound, to: input) }.value
    }

    // MARK: Clean-up

    /// Cuts the long silences on the selected track, closing the gaps on every track so they stay in sync.
    func removeSilences() {
        guard !silences.isEmpty, let project else {
            notice = "No long silences on this track."
            return
        }
        let keep = 0.25
        let cuts = silences.compactMap { gap -> ClosedRange<Double>? in
            let start = gap.lowerBound <= 0.001 ? 0 : gap.lowerBound + keep / 2
            let end = gap.upperBound >= project.duration - 0.001 ? project.duration : gap.upperBound - keep / 2
            return end - start > 0.05 ? start...end : nil
        }
        let total = cuts.reduce(0) { $0 + ($1.upperBound - $1.lowerBound) }
        change { SoundEdit.delete(&$0, ranges: cuts) }
        notice = "Took out \(cuts.count) \(cuts.count == 1 ? "silence" : "silences"), \(String(format: "%.1f", total)) seconds in all."
        measure()
    }

    func transcribe() {
        guard let project, project.duration > 0.5 else { return }
        working = "Transcribing on this Mac…"
        var voice = project
        for index in voice.tracks.indices { voice.tracks[index].solo = index == trackIndex }
        let mix = SoundMixer.render(voice, sources: { [sources] in sources[$0] })
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("11am-transcribe-\(UUID().uuidString).m4a")
        Task {
            defer { working = nil }
            do {
                try SoundIO.write(mix, to: url, format: .m4a)
                let words = try await Transcriber.words(url)
                change { $0.words = words }
                let fillers = words.filter(\.isFiller).count
                notice = "Transcribed \(words.count) words\(fillers > 0 ? ", \(fillers) of them fillers (um, uh)" : "")."
            } catch {
                notice = error.localizedDescription
            }
            try? FileManager.default.removeItem(at: url)
        }
    }

    func removeFillers() {
        guard let project else { return }
        let ranges = SoundEdit.fillerRanges(project)
        guard !ranges.isEmpty else {
            notice = project.words.isEmpty ? "Transcribe first, so Cole can find the ums." : "No fillers left."
            return
        }
        change { SoundEdit.delete(&$0, ranges: ranges) }
        notice = "Took out \(ranges.count) \(ranges.count == 1 ? "filler" : "fillers")."
    }

    /// Show notes from the transcript: a summary, chapters and the main points.
    func showNotes() {
        guard let project, !project.words.isEmpty else {
            notice = "Transcribe first, so Cole has the words."
            return
        }
        let transcript = Transcriber.lines(from: project.words).map { "[\(SoundChapters.clock($0.start))] \($0.text)" }.joined(separator: "\n")
        let system = """
        You are Cole, the media agent inside 11am. Write show notes for this recording: a two-sentence summary, \
        chapters as "MM:SS Title" using the timestamps given, and three to five key points. Use only what was said.
        """
        notesRun = brain.run(BrainRequest(system: system, prompt: String(transcript.prefix(24_000)), weight: .deep))
    }

    // MARK: Export

    enum Target: Double, CaseIterable, Identifiable {
        case none = 0, streaming = -14, podcast = -16, apple = -19, broadcast = -23
        var id: Double { rawValue }
        var title: String {
            switch self {
            case .none: return "As it is"
            case .streaming: return "−14 LUFS · YouTube and Spotify"
            case .podcast: return "−16 LUFS · podcasts"
            case .apple: return "−19 LUFS · spoken word"
            case .broadcast: return "−23 LUFS · broadcast (EBU R 128)"
            }
        }
    }

    func export(_ format: SoundFormat, target: Target) {
        guard let project, let mix = mixdown() else { return }
        flushSave()
        let panel = NSSavePanel()
        panel.nameFieldStringValue = project.name.replacingOccurrences(of: "/", with: "-") + "." + format.fileExtension
        if let type = UTType(filenameExtension: format.fileExtension) { panel.allowedContentTypes = [type] }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        working = "Exporting…"
        Task {
            let result = await Task.detached(priority: .userInitiated) { () -> Error? in
                let final = target == .none ? SoundDSP.limiter(mix, ceiling: -0.3) : SoundDSP.loudness(mix, target: target.rawValue, ceiling: -1)
                do {
                    try SoundIO.write(final, to: url, format: format)
                    return nil
                } catch {
                    return error
                }
            }.value
            working = nil
            if let result {
                notice = "Couldn't export: \(result.localizedDescription)"
            } else {
                notice = "Saved \(url.lastPathComponent)\(target == .none ? "" : " at \(Int(target.rawValue)) LUFS")."
                if !project.markers.isEmpty {
                    try? SoundChapters.text(project).write(to: url.deletingPathExtension().appendingPathExtension("chapters.txt"), atomically: true, encoding: .utf8)
                }
            }
        }
    }

    // MARK: Sample

    /// A short episode: two voices from the Mac's speech synthesiser (with an "um" and a long pause), and a music bed.
    static let sampleName = "Founders' hour · episode 12"

    private func makeSample() async {
        // Saved only once it's whole, so quitting halfway doesn't leave an empty sample behind.
        var project = SoundProject(name: Self.sampleName, tracks: [SoundTrack(name: "Voice"), SoundTrack(name: "Music", volume: -14)])
        self.project = project
        let lines = [
            "Welcome back to Founders' hour. Today, um, we're talking about the software bill.",
            "Most founders pay for eleven subscriptions. None of them talk to each other.",
            "So here's the question. What if they all lived on your Mac?",
        ]
        var voice = SoundBuffer(sampleRate: 48_000, channelCount: 1, frames: 0)
        let began = Date()
        // All the speech gets one budget; a Mac without voices (or a slow one) gets the hummed stand-in instead.
        let deadline = began.addingTimeInterval(12)
        NSLog("11am audio sample: speaking")
        for (index, line) in lines.enumerated() {
            let left = deadline.timeIntervalSinceNow
            guard left > 1, let spoken = await AudioSamples.speak(line, voice: index == 1 ? 1 : 0, timeout: left) else {
                voice = SoundBuffer(sampleRate: 48_000, channelCount: 1, frames: 0)
                break
            }
            voice.append(spoken)
            voice.append(.silence(seconds: index == 0 ? 1.8 : 0.5, channels: 1))
        }
        if voice.duration < 1 { voice = AudioSamples.fallbackVoice() }
        NSLog("11am audio sample: voice %.1f s after %.1f s", voice.duration, Date().timeIntervalSince(began))
        let music = AudioSamples.musicBed(seconds: voice.duration + 2)
        NSLog("11am audio sample: music after %.1f s", Date().timeIntervalSince(began))
        if let voiceAsset = store(voice, name: "voice"), let musicAsset = store(music, name: "music") {
            project.tracks[0].clips = [SoundClip(name: "Interview", asset: voiceAsset, start: 1, outPoint: voice.duration)]
            project.tracks[1].clips = [SoundClip(name: "Bed", asset: musicAsset, start: 0, outPoint: music.duration, fadeIn: 1.5, fadeOut: 2.5)]
            project.markers = [SoundMarker(time: 0, name: "Intro"), SoundMarker(time: voice.duration * 0.45, name: "The software bill")]
        }
        project.modified = Date()
        // Opening saves what's in memory first, so memory must hold the finished project too.
        self.project = project
        write(project)
        UserDefaults.standard.set(true, forKey: "audio.seeded")
        NSLog("11am audio sample: saved after %.1f s", Date().timeIntervalSince(began))
        open(project.id)
    }
}

enum AudioSamples {
    /// Speech from the Mac's own voices, written straight to a buffer (no speakers needed).
    @MainActor
    static func speak(_ text: String, voice index: Int, timeout: TimeInterval = 20) async -> SoundBuffer? {
        let synthesizer = AVSpeechSynthesizer()
        let utterance = AVSpeechUtterance(string: text)
        let voices = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix("en") }
        if !voices.isEmpty { utterance.voice = voices[min(index, voices.count - 1)] }
        utterance.rate = 0.5
        let result: SoundBuffer? = await withCheckedContinuation { continuation in
            var collected = SoundBuffer(sampleRate: 48_000, channelCount: 1, frames: 0)
            var finished = false
            var heard = false
            synthesizer.write(utterance) { buffer in
                guard !finished else { return }
                heard = true
                guard let pcm = buffer as? AVAudioPCMBuffer, pcm.frameLength > 0 else {
                    finished = true
                    continuation.resume(returning: collected.frames > 0 ? collected : nil)
                    return
                }
                var sound = SoundIO.sound(from: pcm).withChannels(1)
                if sound.sampleRate != 48_000 { sound = sound.resampled(to: 48_000) }
                collected.append(sound)
            }
            // If the synthesiser never answers (no voices installed), give up soon; if it's slow, after a while.
            DispatchQueue.main.asyncAfter(deadline: .now() + min(5, timeout)) {
                guard !finished, !heard else { return }
                finished = true
                continuation.resume(returning: nil)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + timeout) {
                guard !finished else { return }
                finished = true
                // Cut off partway through a line isn't worth keeping.
                continuation.resume(returning: nil)
            }
        }
        // The synthesiser has to live until it has finished speaking.
        withExtendedLifetime(synthesizer) {}
        return result
    }

    /// A stand-in voice: a hummed melody with a pause, so the sample works on any Mac.
    static func fallbackVoice() -> SoundBuffer {
        var voice = SoundBuffer(sampleRate: 48_000, channelCount: 1, frames: 0)
        for (index, frequency) in [196.0, 220, 247, 220, 196, 175].enumerated() {
            voice.append(SoundDSP.fade(.tone(frequency, seconds: 0.7, amplitude: 0.3), in: 0.05, out: 0.1))
            voice.append(.silence(seconds: index == 2 ? 1.8 : 0.15, channels: 1))
        }
        return voice
    }

    /// A soft chord pad: four chords of stacked sines with slow swells.
    static func musicBed(seconds: Double) -> SoundBuffer {
        let rate = 48_000.0
        let chords: [[Double]] = [[261.6, 329.6, 392.0], [220.0, 261.6, 329.6], [174.6, 220.0, 261.6], [196.0, 246.9, 293.7]]
        let chordLength = 4.0
        let frames = Int(seconds * rate)
        var left = [Float](repeating: 0, count: frames), right = [Float](repeating: 0, count: frames)
        for index in 0..<frames {
            let t = Double(index) / rate
            let chord = chords[Int(t / chordLength) % chords.count]
            let within = t.truncatingRemainder(dividingBy: chordLength) / chordLength
            let swell = Float(sin(.pi * within)) * 0.6 + 0.4
            var sample = 0.0
            for (voice, frequency) in chord.enumerated() { sample += sin(2 * .pi * frequency * t + Double(voice)) / Double(chord.count) }
            left[index] = Float(sample) * 0.18 * swell
            right[index] = Float(sin(2 * .pi * chord[0] / 2 * t)) * 0.08 * swell + left[index] * 0.8
        }
        return SoundBuffer(sampleRate: rate, channels: [left, right])
    }
}
