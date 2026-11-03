import AVKit
import SwiftUI
import UniformTypeIdentifiers

/// Cole's Video: a timeline you trim and split, with colour, sound clean-up and editing by the words.
struct VideoView: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var video: VideoModel
    @Environment(\.colorScheme) private var scheme
    @State private var importing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "video", subtitle: "Cole · cut, colour and clean up") {
                HStack(spacing: 6) {
                    Button { video.undo() } label: { Image(systemName: "arrow.uturn.backward") }
                        .buttonStyle(.vellumSecondary)
                        .disabled(!video.canUndo)
                        .keyboardShortcut("z", modifiers: .command)
                        .help("Undo")
                    Button { video.redo() } label: { Image(systemName: "arrow.uturn.forward") }
                        .buttonStyle(.vellumSecondary)
                        .disabled(!video.canRedo)
                        .keyboardShortcut("z", modifiers: [.command, .shift])
                        .help("Redo")
                    Menu {
                        ForEach(VideoExportPreset.allCases) { preset in
                            Menu(preset.title) {
                                ForEach(VideoLoudness.allCases) { target in
                                    Button(target.title) { video.export(preset, loudness: target) }
                                }
                            }
                        }
                        Divider()
                        Button("Captions (.srt)") { video.exportCaptions() }
                    } label: {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }
                    .menuStyle(.button)
                    .buttonStyle(.borderless)
                    .fixedSize()
                    .foregroundStyle(theme.inkSecondary(scheme))
                    .disabled(video.clips.isEmpty || video.isWorking)
                    Button {
                        importing = true
                    } label: {
                        Label("Add clips…", systemImage: "film")
                    }
                    .buttonStyle(.vellumPrimary)
                }
            }

            if video.clips.isEmpty {
                EmptyVideo(importing: $importing)
                    .transition(.rise(theme.rise))
            } else {
                HStack(alignment: .top, spacing: 14) {
                    VStack(alignment: .leading, spacing: 10) {
                        PlayerStage()
                        TransportBar(clock: video.clock)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    VideoInspector()
                        .frame(width: 300)
                        .frame(maxHeight: .infinity)
                        .vellum(level: 3, radius: max(theme.radius - 2, 8))
                }
                .frame(maxHeight: .infinity)
                VideoTimeline()
                    .transition(.rise(theme.rise))
            }
        }
        .padding(24)
        .animation(theme.spring, value: video.clips.isEmpty)
        .fileImporter(isPresented: $importing, allowedContentTypes: [.movie], allowsMultipleSelection: true) { result in
            if case .success(let urls) = result { video.add(urls) }
        }
    }
}

private struct EmptyVideo: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var video: VideoModel
    @Environment(\.colorScheme) private var scheme
    @Binding var importing: Bool

    var body: some View {
        VStack(spacing: 14) {
            AgentLogo(code: "co", size: 56, color: theme.inkTertiary(scheme))
            Text("Put clips on the timeline, trim them by their edges, grade them, clean up the sound.")
                .font(.system(size: 13))
                .foregroundStyle(theme.inkSecondary(scheme))
                .multilineTextAlignment(.center)
            HStack(spacing: 8) {
                Button("Add clips…") { importing = true }
                    .buttonStyle(.vellumPrimary)
                Button("Try two sample clips") { video.loadSamples() }
                    .buttonStyle(.vellumSecondary)
                    .disabled(video.isWorking)
            }
            Text(video.status)
                .font(.system(size: 11.5))
                .foregroundStyle(theme.inkTertiary(scheme))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            RoundedRectangle(cornerRadius: max(theme.radius - 2, 8), style: .continuous).fill(theme.well(scheme))
        }
    }
}

// MARK: Player

private struct PlayerStage: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var video: VideoModel

    var body: some View {
        let ratio = video.renderSize.height > 0 ? video.renderSize.width / video.renderSize.height : 16 / 9
        ZStack {
            RoundedRectangle(cornerRadius: max(theme.radius - 2, 8), style: .continuous)
                .fill(Color.black)
            PlayerSurface(player: video.player)
                .aspectRatio(ratio, contentMode: .fit)
                .animation(theme.spring, value: ratio)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: max(theme.radius - 2, 8), style: .continuous))
    }
}

/// The movie without AVKit's own controls; the timeline is the scrubber.
private struct PlayerSurface: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .none
        view.videoGravity = .resizeAspect
        view.player = player
        return view
    }

    func updateNSView(_ view: AVPlayerView, context: Context) {
        if view.player !== player { view.player = player }
    }
}

private struct TransportBar: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var video: VideoModel
    @Environment(\.colorScheme) private var scheme
    @ObservedObject var clock: PlaybackClock

    var body: some View {
        HStack(spacing: 8) {
            Button { video.step(-1) } label: { Image(systemName: "backward.frame") }
                .buttonStyle(.vellumSecondary)
                .help("Back one frame")
            Button { video.togglePlay() } label: {
                Image(systemName: clock.isPlaying ? "pause.fill" : "play.fill")
                    .frame(width: 14)
            }
            .buttonStyle(.vellumPrimary)
            .keyboardShortcut(.return, modifiers: .command)
            .help("Play or pause (⌘↩)")
            Button { video.step(1) } label: { Image(systemName: "forward.frame") }
                .buttonStyle(.vellumSecondary)
                .help("Forward one frame")
            Text("\(VideoModel.timecode(clock.time)) / \(VideoModel.timecode(video.totalDuration))")
                .font(.system(size: 12).monospacedDigit())
                .foregroundStyle(theme.inkSecondary(scheme))
                .fixedSize()
            Button { video.splitAtPlayhead() } label: { Label("Split", systemImage: "scissors") }
                .buttonStyle(.vellumSecondary)
                .keyboardShortcut("b", modifiers: .command)
                .help("Split the clip at the playhead (⌘B)")
            Spacer(minLength: 8)
            if let progress = video.exportProgress {
                ProgressView(value: progress)
                    .frame(width: 90)
                    .controlSize(.small)
            } else if video.isWorking {
                ProgressView().controlSize(.small)
            }
        }
        Text(video.status)
            .font(.system(size: 11.5))
            .foregroundStyle(theme.inkTertiary(scheme))
            .lineLimit(1)
            .truncationMode(.tail)
            .help(video.status)
    }
}

// MARK: Inspector

private enum InspectorTab: String, CaseIterable, Identifiable {
    case clip, colour, sound, words, titles

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

private struct VideoInspector: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var video: VideoModel
    @Environment(\.colorScheme) private var scheme
    @State private var tab = InspectorTab(rawValue: UserDefaults.standard.string(forKey: "videoTab") ?? "") ?? .clip

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("", selection: $tab) {
                ForEach(InspectorTab.allCases) { tab in Text(tab.title).tag(tab) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            if tab == .titles {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        TitlesPanel()
                    }
                    .padding(.trailing, 2)
                }
                .scrollContentBackground(.hidden)
            } else if let clip = video.selectedClip {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        switch tab {
                        case .clip: ClipPanel(clip: clip)
                        case .colour: ColourPanel()
                        case .sound: SoundPanel(clip: clip)
                        case .words: WordsPanel(clip: clip)
                        case .titles: EmptyView()
                        }
                    }
                    .padding(.trailing, 2)
                }
                .scrollContentBackground(.hidden)
            } else {
                Text("Select a clip on the timeline.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(theme.inkTertiary(scheme))
                Spacer()
            }
        }
        .padding(14)
    }
}

private struct ClipPanel: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var video: VideoModel
    @Environment(\.colorScheme) private var scheme
    var clip: VideoClip

    private static let speeds: [(Double, String)] = [(0.25, "¼×"), (0.5, "½×"), (1, "1×"), (1.5, "1½×"), (2, "2×"), (4, "4×")]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(clip.name)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(theme.ink(scheme))
                .lineLimit(1)
            Text("\(VideoModel.clock(clip.editedDuration)) on the timeline · \(VideoModel.clock(clip.duration)) source · \(Int(clip.size.width))×\(Int(clip.size.height))")
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(theme.inkTertiary(scheme))
        }

        SectionLabel(text: "Trim")
        TimeSlider(title: "Starts at", value: clip.inPoint, range: 0...clip.duration) { video.trim(clip.id, inPoint: $0) }
        TimeSlider(title: "Ends at", value: clip.outPoint, range: 0...clip.duration) { video.trim(clip.id, outPoint: $0) }
        Text("Or drag the clip's edges on the timeline.")
            .font(.system(size: 11))
            .foregroundStyle(theme.inkTertiary(scheme))

        SectionLabel(text: "Speed")
        Picker("Speed", selection: Binding(get: { clip.speed }, set: { speed in video.updateSelected { $0.speed = speed } })) {
            ForEach(ClipPanel.speeds.indices, id: \.self) { index in
                Text(ClipPanel.speeds[index].1).tag(ClipPanel.speeds[index].0)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()

        if video.aspect != .original {
            SectionLabel(text: "Framing")
            Slider(value: Binding(get: { clip.reframe }, set: { value in video.updateSelected { $0.reframe = value } }), in: -1...1)
                .controlSize(.small)
            HStack {
                Text("Left or top")
                Spacer()
                Text("Right or bottom")
            }
            .font(.system(size: 9.5))
            .foregroundStyle(theme.inkTertiary(scheme))
        }

        SectionLabel(text: "Clip")
        FlowLayout(spacing: 6) {
            Button { video.splitAtPlayhead() } label: { Label("Split", systemImage: "scissors") }
                .buttonStyle(.vellumSecondary)
            Button("Duplicate") { video.duplicateSelected() }
                .buttonStyle(.vellumSecondary)
            Button { video.moveSelected(by: -1) } label: { Image(systemName: "arrow.left") }
                .buttonStyle(.vellumSecondary)
                .disabled(video.selectedIndex == 0)
                .help("Move earlier")
            Button { video.moveSelected(by: 1) } label: { Image(systemName: "arrow.right") }
                .buttonStyle(.vellumSecondary)
                .disabled(video.selectedIndex == video.clips.count - 1)
                .help("Move later")
            Button("Delete", role: .destructive) { video.deleteSelected() }
                .buttonStyle(.vellumSecondary)
                .keyboardShortcut(.delete, modifiers: .command)
                .help("Remove from the timeline (⌘⌫). The file stays where it is.")
        }
    }
}

private struct TimeSlider: View {
    @EnvironmentObject private var theme: Theme
    @Environment(\.colorScheme) private var scheme
    var title: String
    var value: Double
    var range: ClosedRange<Double>
    var onChange: (Double) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack {
                Text(title)
                    .font(.system(size: 12))
                    .foregroundStyle(theme.ink(scheme))
                Spacer()
                Text(VideoModel.timecode(value))
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(theme.inkSecondary(scheme))
            }
            Slider(value: Binding(get: { value }, set: onChange), in: range)
                .controlSize(.small)
        }
    }
}

private struct ColourPanel: View {
    @EnvironmentObject private var video: VideoModel

    var body: some View {
        Button("Use this colour on every clip") { video.applyGradeToAll() }
            .buttonStyle(.vellumSecondary)
            .disabled(video.clips.count < 2)
        GradePanel(
            settings: Binding(get: { video.selectedClip?.grade ?? GradeSettings() }, set: { video.setGrade($0) }),
            autoSource: { video.gradeFrame }
        )
    }
}

private struct SoundPanel: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var video: VideoModel
    @Environment(\.colorScheme) private var scheme
    var clip: VideoClip

    var body: some View {
        if !clip.hasAudio {
            Text("This clip has no sound.")
                .font(.system(size: 12.5))
                .foregroundStyle(theme.inkTertiary(scheme))
        }
        SectionLabel(text: "Level")
        HStack {
            Image(systemName: "speaker.fill").foregroundStyle(theme.inkTertiary(scheme))
            Slider(value: Binding(get: { clip.volume }, set: { value in video.updateSelected { $0.volume = value } }), in: 0...1)
                .controlSize(.small)
            Text("\(Int(clip.volume * 100))%")
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(theme.inkSecondary(scheme))
                .frame(width: 34, alignment: .trailing)
        }
        .font(.system(size: 11))
        Toggle("Mute", isOn: Binding(get: { clip.muted }, set: { value in video.updateSelected { $0.muted = value } }))
            .toggleStyle(.switch)
            .controlSize(.small)

        SectionLabel(text: "Clean up")
        Button {
            video.cleanVoice()
        } label: {
            Label(clip.cleanAudio == nil ? "Clean up the voice" : "Clean up again", systemImage: "waveform.badge.magnifyingglass")
        }
        .buttonStyle(.vellumPrimary)
        .disabled(!clip.hasAudio || video.isWorking)
        if clip.cleanAudio != nil {
            Toggle("Use the cleaned voice", isOn: Binding(get: { clip.useCleanAudio }, set: { value in video.updateSelected { $0.useCleanAudio = value } }))
                .toggleStyle(.switch)
                .controlSize(.small)
        }
        Text("Apple's Voice Isolation takes out background noise, a high-pass removes rumble and handling, then the level is evened out. On this Mac; the original file isn't touched.")
            .font(.system(size: 11))
            .foregroundStyle(theme.inkTertiary(scheme))
            .fixedSize(horizontal: false, vertical: true)

        Group {
            SectionLabel(text: "Pauses")
            FlowLayout(spacing: 6) {
                Button {
                    video.cutSilences(everyClip: false)
                } label: {
                    Label(clip.silenceCuts.isEmpty ? "Cut the pauses" : "Find them again", systemImage: "scissors")
                }
                .buttonStyle(.vellumSecondary)
                .disabled(!clip.hasAudio || video.isWorking)
                if video.clips.count > 1 {
                    Button("Every clip") { video.cutSilences(everyClip: true) }
                        .buttonStyle(.vellumSecondary)
                        .disabled(video.isWorking)
                }
                if !clip.silenceCuts.isEmpty {
                    Button("Put them back") { video.keepSilences() }
                        .buttonStyle(.vellumSecondary)
                }
            }
            if clip.silenceCount > 0 {
                Text("\(clip.silenceCount) \(clip.silenceCount == 1 ? "pause" : "pauses") cut · \(VideoModel.clock(clip.silenceSaved)) shorter")
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(theme.inkSecondary(scheme))
                    .contentTransition(.numericText())
            }
            Text("Gaps of more than 0.7 s below −40 dB are taken out, leaving 0.3 s of air so speech doesn't run together.")
                .font(.system(size: 11))
                .foregroundStyle(theme.inkTertiary(scheme))
                .fixedSize(horizontal: false, vertical: true)
        }

        MusicSection()
    }
}

/// The music bed under the whole movie.
private struct MusicSection: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var video: VideoModel
    @Environment(\.colorScheme) private var scheme
    @State private var importing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "Music · whole movie")
            if let music = video.music {
                HStack(spacing: 8) {
                    Image(systemName: "music.note")
                        .foregroundStyle(theme.inkSecondary(scheme))
                    Text(music.name)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(theme.ink(scheme))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 4)
                    Button { importing = true } label: { Image(systemName: "arrow.triangle.2.circlepath") }
                        .buttonStyle(.plain)
                        .foregroundStyle(theme.inkSecondary(scheme))
                        .help("Use another file")
                    Button { video.removeMusic() } label: { Image(systemName: "xmark") }
                        .buttonStyle(.plain)
                        .foregroundStyle(theme.inkSecondary(scheme))
                        .help("Take the music out")
                }
                HStack {
                    Image(systemName: "speaker.fill").foregroundStyle(theme.inkTertiary(scheme))
                    Slider(value: Binding(get: { music.volume }, set: { value in video.updateMusic { $0.volume = value } }), in: 0...1)
                        .controlSize(.small)
                    Text("\(Int(music.volume * 100))%")
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(theme.inkSecondary(scheme))
                        .frame(width: 34, alignment: .trailing)
                }
                .font(.system(size: 11))
                Toggle("Turn it down while people talk", isOn: Binding(get: { music.ducking }, set: { value in video.updateMusic { $0.ducking = value } }))
                    .toggleStyle(.switch)
                    .controlSize(.small)
                if music.ducking {
                    HStack {
                        Text("Under speech")
                            .font(.system(size: 11))
                            .foregroundStyle(theme.inkSecondary(scheme))
                        Slider(value: Binding(get: { music.duckLevel }, set: { value in video.updateMusic { $0.duckLevel = value } }), in: 0.05...0.6)
                            .controlSize(.small)
                        Text("\(Int(music.duckLevel * 100))%")
                            .font(.system(size: 11).monospacedDigit())
                            .foregroundStyle(theme.inkSecondary(scheme))
                            .frame(width: 34, alignment: .trailing)
                    }
                    Text(video.ducked.isEmpty
                        ? "No speech heard yet, so the music stays up. It finds the talking in clips with sound."
                        : "Ducks \(video.ducked.count) \(video.ducked.count == 1 ? "time" : "times"), easing down a quarter-second before each line.")
                        .font(.system(size: 11))
                        .foregroundStyle(theme.inkTertiary(scheme))
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                FlowLayout(spacing: 6) {
                    Button { importing = true } label: { Label("Add music…", systemImage: "music.note") }
                        .buttonStyle(.vellumSecondary)
                    Button("Sample bed") { video.addSampleMusic() }
                        .buttonStyle(.vellumSecondary)
                }
                Text("Loops under the whole movie, fades in and out with it, and turns down whenever someone talks.")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.inkTertiary(scheme))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.audio]) { result in
            if case .success(let url) = result { video.addMusic(url) }
        }
    }
}

/// Lower thirds, title and end cards, and burned-in captions.
private struct TitlesPanel: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var video: VideoModel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        SectionLabel(text: "Add at the playhead")
        FlowLayout(spacing: 6) {
            ForEach(VideoTitle.Kind.allCases) { kind in
                Button(kind.title) { video.addTitle(kind) }
                    .buttonStyle(.vellumSecondary)
                    .disabled(video.clips.isEmpty)
            }
        }
        Text("Drawn in your brand kit's colours and fonts (Design › Brand). End cards go at the end.")
            .font(.system(size: 11))
            .foregroundStyle(theme.inkTertiary(scheme))
            .fixedSize(horizontal: false, vertical: true)
        ForEach(video.titles) { title in
            TitleEditor(title: title)
        }

        SectionLabel(text: "Captions")
        Toggle("Burn captions into the picture", isOn: $video.burnCaptions)
            .toggleStyle(.switch)
            .controlSize(.small)
            .disabled(!video.hasTranscript && !video.burnCaptions)
        Text(video.hasTranscript
            ? "From the transcript, timed to the edit; struck lines are left out. Captions (.srt) in Export saves them as a file."
            : "Transcribe a clip in Words first; captions come from the words.")
            .font(.system(size: 11))
            .foregroundStyle(theme.inkTertiary(scheme))
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct TitleEditor: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var video: VideoModel
    @Environment(\.colorScheme) private var scheme
    var title: VideoTitle

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(title.kind.title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(theme.ink(scheme))
                Text("\(VideoModel.clock(title.start))–\(VideoModel.clock(title.end))")
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(theme.inkTertiary(scheme))
                Spacer(minLength: 4)
                Button { video.seek(to: title.start + min(1, title.duration / 2)) } label: { Image(systemName: "eye") }
                    .buttonStyle(.plain)
                    .foregroundStyle(theme.inkSecondary(scheme))
                    .help("Show it")
                Button { video.deleteTitle(title.id) } label: { Image(systemName: "trash") }
                    .buttonStyle(.plain)
                    .foregroundStyle(theme.inkSecondary(scheme))
                    .help("Delete")
            }
            TextField("Text", text: Binding(get: { title.text }, set: { value in video.updateTitle(title.id) { $0.text = value } }))
                .textFieldStyle(.roundedBorder)
            TextField(title.kind == .lowerThird ? "Role, company" : "Second line", text: Binding(get: { title.detail }, set: { value in video.updateTitle(title.id) { $0.detail = value } }))
                .textFieldStyle(.roundedBorder)
            TimeSlider(title: "Starts at", value: title.start, range: 0...max(video.totalDuration - 0.5, 0.5)) { value in
                video.updateTitle(title.id) { $0.start = value }
            }
            Stepper(value: Binding(get: { title.duration }, set: { value in video.updateTitle(title.id) { $0.duration = value } }), in: 1...30, step: 0.5) {
                Text(String(format: "On screen for %.1f s", title.duration))
                    .font(.system(size: 12))
                    .foregroundStyle(theme.ink(scheme))
            }
            .controlSize(.small)
        }
        .padding(10)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous).fill(theme.well(scheme))
        }
    }
}

private struct WordsPanel: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var video: VideoModel
    @EnvironmentObject private var brain: Brain
    @Environment(\.colorScheme) private var scheme
    var clip: VideoClip

    var body: some View {
        FlowLayout(spacing: 6) {
            Button(clip.lines.isEmpty ? "Transcribe this clip" : "Transcribe again") { video.transcribeSelected() }
                .buttonStyle(.vellumPrimary)
                .disabled(!clip.hasAudio || video.isWorking)
            Button("Title & chapters") { video.insights() }
                .buttonStyle(.vellumSecondary)
                .disabled(clip.lines.isEmpty || brain.isBusy)
        }
        if clip.cutCount > 0 {
            Text("\(clip.cutCount) cut · \(VideoModel.clock(clip.lines.filter(\.cut).reduce(0.0) { $0 + $1.end - $1.start })) shorter")
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(theme.inkTertiary(scheme))
                .contentTransition(.numericText())
        }
        if let run = video.insightRun {
            Card { RunView(run: run) }
                .transition(.rise(theme.rise))
        }
        LazyVStack(alignment: .leading, spacing: 2) {
            ForEach(Array(clip.lines.enumerated()), id: \.element.id) { index, line in
                TranscriptRow(line: line)
                    .entrance(index)
            }
        }
        Text(clip.hasAudio
            ? "Transcribed on this Mac. Click a line to jump there; strike it to cut it from the video and the captions."
            : "This clip has no sound to transcribe.")
            .font(.system(size: 11))
            .foregroundStyle(theme.inkTertiary(scheme))
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct TranscriptRow: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var video: VideoModel
    @Environment(\.colorScheme) private var scheme
    var line: TranscriptLine
    @State private var hovering = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(VideoModel.clock(line.start))
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(theme.inkTertiary(scheme))
                .frame(width: 30, alignment: .leading)
            Text(line.text)
                .font(.system(size: 12.5))
                .strikethrough(line.cut, color: theme.ink(scheme).opacity(0.5))
                .foregroundStyle(theme.ink(scheme).opacity(line.cut ? 0.35 : 1))
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                withAnimation(theme.spring) { video.toggleCut(line) }
            } label: {
                Image(systemName: line.cut ? "arrow.uturn.backward" : "scissors")
                    .font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .foregroundStyle(theme.inkSecondary(scheme))
            .opacity(hovering || line.cut ? 1 : 0)
            .help(line.cut ? "Keep this line" : "Cut this line")
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .background {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(hovering ? theme.well(scheme) : Color.clear)
        }
        .contentShape(Rectangle())
        .onTapGesture { video.jump(to: line) }
        .onHover { inside in
            withAnimation(theme.motionEnabled ? .easeOut(duration: 0.12) : nil) { hovering = inside }
        }
    }
}
