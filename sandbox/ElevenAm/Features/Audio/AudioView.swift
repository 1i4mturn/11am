import AppKit
import SwiftUI

/// Cole's Audio: record, cut, clean up and export, with every track's waveform in front of you.
struct AudioView: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var audio: AudioModel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "audio", subtitle: subtitle) {
                HStack(spacing: 8) {
                    recordControl
                    Button {
                        audio.importFiles()
                    } label: {
                        Label("Import", systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(.vellumSecondary)
                    .help("Sound files, or the sound from a video")
                    exportMenu
                    Menu {
                        Button("New project") { audio.newProject() }
                        Divider()
                        ForEach(audio.entries) { entry in
                            Button("\(entry.name) · \(SoundChapters.clock(entry.duration))") { audio.open(entry.id) }
                        }
                        if let project = audio.project {
                            Divider()
                            Button("Move \u{201C}\(project.name)\u{201D} to the Trash") { audio.delete(project.id) }
                        }
                    } label: {
                        Label("Projects", systemImage: "rectangle.stack")
                    }
                    .menuStyle(.button)
                    .buttonStyle(.vellumSecondary)
                    .fixedSize()
                }
            }

            if let message = audio.working ?? audio.notice {
                HStack(spacing: 10) {
                    if audio.working != nil { ProgressView().controlSize(.small) } else { AgentLogo(code: "co", size: 18, color: theme.inkSecondary(scheme)) }
                    Text(message).font(.system(size: 12.5)).foregroundStyle(theme.ink(scheme)).lineLimit(2)
                    Spacer()
                    if audio.working == nil {
                        Button { audio.notice = nil } label: { Image(systemName: "xmark").font(.system(size: 10, weight: .bold)) }
                            .buttonStyle(.plain)
                            .foregroundStyle(theme.inkTertiary(scheme))
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .vellum(level: 3, radius: max(theme.radius - 4, 8))
            }

            if audio.project != nil {
                VStack(spacing: 10) {
                    AudioToolbar()
                    AudioTimeline()
                        .frame(minHeight: 220, maxHeight: .infinity)
                        .vellum(level: 3, radius: max(theme.radius - 4, 8))
                    AudioPanel()
                        .frame(height: 200)
                }
            } else {
                VStack(spacing: 10) {
                    AgentLogo(code: "co", size: 44, color: theme.inkTertiary(scheme))
                    Text("Making the sample episode…")
                        .font(.system(size: 12.5))
                        .foregroundStyle(theme.inkTertiary(scheme))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(24)
        .task(id: audio.notice) {
            guard audio.notice != nil, (try? await Task.sleep(for: .seconds(10))) != nil else { return }
            audio.notice = nil
        }
        .onDisappear {
            audio.stop()
            audio.flushSave()
        }
    }

    private var subtitle: String {
        guard let project = audio.project else { return "Cole · record, cut, clean up" }
        let loudness = audio.loudness.map { String(format: " · %.1f LUFS", $0) } ?? ""
        return "\(project.name) · \(SoundChapters.clock(project.duration)) · \(project.tracks.count) tracks\(loudness)"
    }

    @ViewBuilder
    private var recordControl: some View {
        if let kind = audio.recordingKind {
            HStack(spacing: 8) {
                Group {
                    if kind == .microphone { MicMeter(recorder: audio.mic) } else { LevelMeter(level: audio.recordingLevel) }
                }
                .frame(width: 80, height: 8)
                Button {
                    audio.stopRecording()
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                }
                .buttonStyle(.vellumPrimary)
            }
        } else {
            Menu {
                Button("From the microphone") { audio.record(.microphone) }
                Button("This Mac's sound (a call, a video)") { audio.record(.mac) }
            } label: {
                Label("Record", systemImage: "record.circle")
            }
            .menuStyle(.button)
            .buttonStyle(.vellumPrimary)
            .fixedSize()
            .disabled(audio.project == nil)
        }
    }

    private var exportMenu: some View {
        Menu {
            ForEach(SoundFormat.allCases.filter { $0 != .caf }) { format in
                Menu(format.title) {
                    ForEach(AudioModel.Target.allCases) { target in
                        Button(target.title) { audio.export(format, target: target) }
                    }
                }
            }
        } label: {
            Label("Export", systemImage: "square.and.arrow.up")
        }
        .menuStyle(.button)
        .buttonStyle(.vellumSecondary)
        .fixedSize()
        .disabled(audio.project == nil)
    }
}

/// Follows the microphone's level directly, so the meter moves while you talk.
private struct MicMeter: View {
    @ObservedObject var recorder: MicRecorder
    var body: some View { LevelMeter(level: recorder.level) }
}

private struct LevelMeter: View {
    var level: Double

    var body: some View {
        GeometryReader { proxy in
            let fraction = max(0, min(1, (level + 60) / 60))
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.12))
                Capsule().fill(level > -3 ? Color.red : Color.primary.opacity(0.7))
                    .frame(width: proxy.size.width * fraction)
            }
        }
    }
}

// MARK: Toolbar

private struct AudioToolbar: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var audio: AudioModel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                ToolButton(symbol: "backward.end.fill", help: "Back to the start") { audio.seek(0) }
                ToolButton(symbol: audio.isPlaying ? "pause.fill" : "play.fill", help: "Play or pause (space)", on: audio.isPlaying) { audio.togglePlay() }
                    .keyboardShortcut(.space, modifiers: [])
                Text("\(clock(audio.playhead)) / \(clock(audio.project?.duration ?? 0))")
                    .font(.system(size: 12, weight: .medium).monospacedDigit())
                    .foregroundStyle(theme.inkSecondary(scheme))
                    .padding(.horizontal, 8)
                    .fixedSize()
                divider
                ToolButton(symbol: "arrow.uturn.backward", help: "Undo (⌘Z)") { audio.undo() }
                    .keyboardShortcut("z", modifiers: .command)
                    .disabled(!audio.canUndo)
                ToolButton(symbol: "arrow.uturn.forward", help: "Redo (⇧⌘Z)") { audio.redo() }
                    .keyboardShortcut("z", modifiers: [.command, .shift])
                    .disabled(!audio.canRedo)
                ToolButton(symbol: "scissors", help: "Split at the playhead (⌘B)") { audio.split() }
                    .keyboardShortcut("b", modifiers: .command)
                ToolButton(symbol: "trash", help: "Delete the selection or clip (⌫)") { audio.delete() }
                    .keyboardShortcut(.delete, modifiers: [])
                ToolButton(symbol: "plus.square.on.square", help: "Duplicate the clip (⌘D)") { audio.duplicate() }
                    .keyboardShortcut("d", modifiers: .command)
                    .disabled(audio.selectedClip == nil)
                ToolButton(symbol: "flag", help: "Add a chapter marker (M)") { audio.addMarker() }
                    .keyboardShortcut("m", modifiers: [])
                divider
                effectsMenu
                cleanupMenu
                divider
                Image(systemName: "minus.magnifyingglass").font(.system(size: 11)).foregroundStyle(theme.inkTertiary(scheme))
                Slider(value: $audio.zoom, in: 10...400)
                    .frame(width: 110)
                    .controlSize(.small)
                Image(systemName: "plus.magnifyingglass").font(.system(size: 11)).foregroundStyle(theme.inkTertiary(scheme))
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
        }
        .fixedSize(horizontal: false, vertical: true)
        .background { RoundedRectangle(cornerRadius: 9, style: .continuous).fill(theme.well(scheme)) }
        .overlay { RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(theme.edge(scheme), lineWidth: 0.5) }
    }

    private func clock(_ seconds: Double) -> String {
        let tenths = Int((seconds * 10).rounded(.down))
        return String(format: "%d:%02d.%d", tenths / 600, tenths / 10 % 60, tenths % 10)
    }

    private var divider: some View {
        Rectangle().fill(theme.edge(scheme)).frame(width: 1, height: 16).padding(.horizontal, 4)
    }

    private var effectsMenu: some View {
        Menu {
            Section("Level") {
                Button("Louder by 3 dB") { audio.apply(.amplify(decibels: 3)) }
                Button("Quieter by 3 dB") { audio.apply(.amplify(decibels: -3)) }
                Button("Normalise to −1 dB") { audio.apply(.normalise(peak: -1)) }
                Menu("Loudness") {
                    ForEach([-14.0, -16, -19, -23], id: \.self) { target in
                        Button("\(Int(target)) LUFS") { audio.apply(.loudness(target: target, ceiling: -1)) }
                    }
                }
                Button("Fade in") { audio.apply(.fadeIn(seconds: 1)) }
                Button("Fade out") { audio.apply(.fadeOut(seconds: 2)) }
            }
            Section("Tone") {
                Button("Rumble filter") { audio.apply(.highPass(frequency: 80)) }
                Button("Voice presence") {
                    audio.apply(.eq([EQBand(kind: .highPass, frequency: 80), EQBand(kind: .peak, frequency: 250, gain: -2, q: 1),
                                     EQBand(kind: .peak, frequency: 3_200, gain: 3, q: 0.8)]))
                }
                Button("Warmer") { audio.apply(.eq([EQBand(kind: .lowShelf, frequency: 200, gain: 2.5), EQBand(kind: .highShelf, frequency: 8_000, gain: -2)])) }
                Button("Brighter") { audio.apply(.eq([EQBand(kind: .highShelf, frequency: 6_000, gain: 3)])) }
                Button("Telephone") { audio.apply(.eq([EQBand(kind: .highPass, frequency: 400), EQBand(kind: .lowPass, frequency: 3_200)])) }
            }
            Section("Dynamics") {
                Button("Gentle compressor") { audio.apply(.compressor(threshold: -20, ratio: 2, attack: 0.01, release: 0.2, makeup: 2)) }
                Button("Voice compressor") { audio.apply(.compressor(threshold: -24, ratio: 3.5, attack: 0.006, release: 0.15, makeup: 4)) }
                Button("Limiter at −1 dB") { audio.apply(.limiter(ceiling: -1)) }
                Button("Noise gate") { audio.apply(.gate(threshold: -45, reduction: -30)) }
            }
            Section("Time and pitch") {
                Button("Tempo × 0.9") { audio.apply(.speed(rate: 0.9, keepPitch: true)) }
                Button("Tempo × 1.1") { audio.apply(.speed(rate: 1.1, keepPitch: true)) }
                Button("Tempo × 1.25") { audio.apply(.speed(rate: 1.25, keepPitch: true)) }
                Button("Pitch up a semitone") { audio.apply(.pitch(semitones: 1)) }
                Button("Pitch down a semitone") { audio.apply(.pitch(semitones: -1)) }
                Button("Reverse") { audio.apply(.reverse) }
                Button("Silence") { audio.apply(.silence) }
            }
        } label: {
            Label("Effects", systemImage: "slider.vertical.3")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(theme.inkSecondary(scheme))
        }
        .menuStyle(.button)
        .buttonStyle(.borderless)
        .fixedSize()
        .padding(.horizontal, 4)
        .help("On the selected clip, or the selected stretch of it")
    }

    private var cleanupMenu: some View {
        Menu {
            Button("Studio sound") { audio.apply(.studioSound) }
            Divider()
            Button("Remove long silences") { audio.removeSilences() }
            Button("Transcribe") { audio.transcribe() }
            Button("Remove ums and uhs") { audio.removeFillers() }
        } label: {
            Label("Clean up", systemImage: "wand.and.stars")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(theme.inkSecondary(scheme))
        }
        .menuStyle(.button)
        .buttonStyle(.borderless)
        .fixedSize()
        .padding(.horizontal, 4)
    }
}

// MARK: Timeline

private struct AudioTimeline: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var audio: AudioModel
    @Environment(\.colorScheme) private var scheme
    @State private var dragStart: Double?

    static let headerWidth: CGFloat = 148
    static let laneHeight: CGFloat = 78
    static let rulerHeight: CGFloat = 26

    var body: some View {
        let tracks = audio.project?.tracks ?? []
        let pps = audio.zoom
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Color.clear.frame(height: Self.rulerHeight)
                ForEach(tracks) { track in
                    TrackHeader(track: track)
                        .frame(height: Self.laneHeight)
                }
                Button {
                    audio.addTrack()
                } label: {
                    Label("Add a track", systemImage: "plus").font(.system(size: 11.5))
                }
                .buttonStyle(.plain)
                .foregroundStyle(theme.inkTertiary(scheme))
                .padding(10)
            }
            .frame(width: Self.headerWidth)
            Rectangle().fill(theme.edge(scheme)).frame(width: 1)
            GeometryReader { proxy in
                ScrollView(.horizontal, showsIndicators: true) {
                    let width = max(proxy.size.width, CGFloat((audio.project?.duration ?? 0) + 8) * CGFloat(pps))
                    ZStack(alignment: .topLeading) {
                        VStack(alignment: .leading, spacing: 0) {
                            Ruler(width: width)
                                .frame(width: width, height: Self.rulerHeight)
                            ForEach(tracks) { track in
                                Lane(track: track)
                                    .frame(width: width, height: Self.laneHeight)
                            }
                        }
                        if let range = audio.range {
                            Rectangle()
                                .fill(theme.ink(scheme).opacity(0.08))
                                .overlay(alignment: .leading) { Rectangle().fill(theme.ink(scheme).opacity(0.35)).frame(width: 1) }
                                .overlay(alignment: .trailing) { Rectangle().fill(theme.ink(scheme).opacity(0.35)).frame(width: 1) }
                                .frame(width: max(1, CGFloat(range.upperBound - range.lowerBound) * CGFloat(pps)),
                                       height: Self.rulerHeight + Self.laneHeight * CGFloat(tracks.count))
                                .offset(x: CGFloat(range.lowerBound) * CGFloat(pps))
                                .allowsHitTesting(false)
                        }
                        Rectangle()
                            .fill(Color.red.opacity(0.85))
                            .frame(width: 1.5, height: Self.rulerHeight + Self.laneHeight * CGFloat(tracks.count))
                            .offset(x: CGFloat(audio.playhead) * CGFloat(pps))
                            .allowsHitTesting(false)
                    }
                    .frame(width: width, alignment: .topLeading)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: max(theme.radius - 4, 8), style: .continuous))
    }
}

private struct TrackHeader: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var audio: AudioModel
    @Environment(\.colorScheme) private var scheme
    var track: SoundTrack
    @State private var renaming = false
    @State private var name = ""

    var body: some View {
        let selected = audio.selectedTrack == track.id
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Text(track.name)
                    .font(.system(size: 12, weight: selected ? .semibold : .medium))
                    .foregroundStyle(theme.ink(scheme))
                    .lineLimit(1)
                Spacer(minLength: 2)
                toggle("M", on: track.muted, help: "Mute") { audio.updateTrack(track.id) { $0.muted.toggle() } }
                toggle("S", on: track.solo, help: "Solo") { audio.updateTrack(track.id) { $0.solo.toggle() } }
            }
            HStack(spacing: 4) {
                Image(systemName: "speaker.wave.2").font(.system(size: 9)).foregroundStyle(theme.inkTertiary(scheme))
                Slider(value: Binding(get: { track.volume }, set: { value in audio.updateTrack(track.id) { $0.volume = value } }), in: -30...6)
                    .controlSize(.mini)
                Text(String(format: "%+.0f", track.volume)).font(.system(size: 9.5).monospacedDigit()).foregroundStyle(theme.inkTertiary(scheme)).frame(width: 22)
            }
            HStack(spacing: 4) {
                Text("L").font(.system(size: 9)).foregroundStyle(theme.inkTertiary(scheme))
                Slider(value: Binding(get: { track.pan }, set: { value in audio.updateTrack(track.id) { $0.pan = abs(value) < 0.05 ? 0 : value } }), in: -1...1)
                    .controlSize(.mini)
                Text("R").font(.system(size: 9)).foregroundStyle(theme.inkTertiary(scheme))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxHeight: .infinity)
        .background { if selected { theme.raised(scheme).opacity(0.7) } }
        .overlay(alignment: .bottom) { Rectangle().fill(theme.edge(scheme)).frame(height: 0.5) }
        .contentShape(Rectangle())
        .onTapGesture { audio.selectedTrack = track.id; audio.measure() }
        .contextMenu {
            Button("Rename…") {
                name = track.name
                renaming = true
            }
            Button("Delete track") { audio.deleteTrack(track.id) }
        }
        .alert("Rename track", isPresented: $renaming) {
            TextField("Name", text: $name)
            Button("Rename") { audio.updateTrack(track.id) { $0.name = name } }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func toggle(_ letter: String, on: Bool, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(letter)
                .font(.system(size: 9.5, weight: .bold))
                .frame(width: 18, height: 16)
                .foregroundStyle(on ? theme.paper(scheme) : theme.inkSecondary(scheme))
                .background { RoundedRectangle(cornerRadius: 4).fill(on ? theme.ink(scheme) : theme.well(scheme)) }
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

private struct Ruler: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var audio: AudioModel
    @Environment(\.colorScheme) private var scheme
    var width: CGFloat
    @State private var dragFrom: Double?

    var body: some View {
        let pps = audio.zoom
        let ink = theme.inkTertiary(scheme)
        let markers = audio.project?.markers ?? []
        ZStack(alignment: .topLeading) {
            Canvas { context, size in
                let step: Double = pps > 120 ? 1 : (pps > 40 ? 5 : (pps > 15 ? 10 : 30))
                var second = 0.0
                while second * pps < Double(size.width) {
                    let x = CGFloat(second * pps)
                    context.fill(Path(CGRect(x: x, y: size.height - 8, width: 1, height: 8)), with: .color(ink))
                    context.draw(Text(SoundChapters.clock(second)).font(.system(size: 9).monospacedDigit()).foregroundColor(ink),
                                 at: CGPoint(x: x + 3, y: 7), anchor: .leading)
                    for minor in 1..<5 {
                        let mx = CGFloat((second + step * Double(minor) / 5) * pps)
                        context.fill(Path(CGRect(x: mx, y: size.height - 4, width: 1, height: 4)), with: .color(ink.opacity(0.6)))
                    }
                    second += step
                }
            }
            ForEach(markers) { marker in
                HStack(spacing: 3) {
                    Image(systemName: "flag.fill").font(.system(size: 8))
                    Text(marker.name).font(.system(size: 9.5, weight: .medium)).lineLimit(1)
                }
                .foregroundStyle(theme.ink(scheme))
                .padding(.horizontal, 4)
                .background { RoundedRectangle(cornerRadius: 3).fill(theme.raised(scheme)) }
                .offset(x: CGFloat(marker.time * pps), y: 12)
                .onTapGesture { audio.seek(marker.time) }
            }
        }
        .frame(width: width)
        .background(theme.well(scheme))
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let start = Double(value.startLocation.x) / pps
                    let now = Double(value.location.x) / pps
                    if abs(value.translation.width) < 3 { return }
                    audio.range = min(start, now)...max(start, now)
                }
                .onEnded { value in
                    if abs(value.translation.width) < 3 {
                        audio.range = nil
                        audio.seek(Double(value.location.x) / pps)
                    } else if let range = audio.range {
                        audio.playhead = range.lowerBound
                    }
                }
        )
        .help("Click to move the playhead; drag to select a stretch")
    }
}

private struct Lane: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var audio: AudioModel
    @Environment(\.colorScheme) private var scheme
    var track: SoundTrack

    var body: some View {
        let pps = audio.zoom
        let selectedTrack = audio.selectedTrack == track.id
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(selectedTrack ? theme.ink(scheme).opacity(0.03) : Color.clear)
                .contentShape(Rectangle())
                .onTapGesture(coordinateSpace: .local) { location in
                    audio.selectedTrack = track.id
                    audio.selectedClip = nil
                    audio.range = nil
                    audio.seek(Double(location.x) / pps)
                }
            if selectedTrack {
                ForEach(Array(audio.silences.enumerated()), id: \.offset) { item in
                    Rectangle()
                        .fill(Color.orange.opacity(0.12))
                        .frame(width: CGFloat(item.element.upperBound - item.element.lowerBound) * CGFloat(pps), height: AudioTimeline.laneHeight)
                        .offset(x: CGFloat(item.element.lowerBound) * CGFloat(pps))
                        .allowsHitTesting(false)
                }
            }
            ForEach(track.clips) { clip in
                ClipView(clip: clip, pps: pps)
            }
        }
        .overlay(alignment: .bottom) { Rectangle().fill(theme.edge(scheme)).frame(height: 0.5) }
    }
}

private struct ClipView: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var audio: AudioModel
    @Environment(\.colorScheme) private var scheme
    var clip: SoundClip
    var pps: Double
    @State private var drag: CGFloat = 0

    var body: some View {
        let selected = audio.selectedClip == clip.id
        let width = max(2, CGFloat(clip.length * pps))
        let height = AudioTimeline.laneHeight - 10
        let peaks = audio.peaks[clip.asset] ?? []
        let ink = theme.ink(scheme)
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(ink.opacity(selected ? 0.14 : 0.07))
            Canvas { context, size in
                guard !peaks.isEmpty else { return }
                let middle = size.height / 2 + 6
                let scale = (size.height - 18) / 2 * CGFloat(SoundMeter.amplitude(clip.gain))
                let perSecond = AudioModel.peaksPerSecond
                let first = clip.inPoint * perSecond, last = clip.outPoint * perSecond
                let columns = max(1, Int(size.width))
                var path = Path()
                for column in 0..<columns {
                    let a = Int(first + (last - first) * Double(column) / Double(columns))
                    let b = max(a + 1, Int(first + (last - first) * Double(column + 1) / Double(columns)))
                    var low: Float = 0, high: Float = 0
                    for index in a..<min(b, peaks.count) where index >= 0 {
                        low = min(low, peaks[index].low)
                        high = max(high, peaks[index].high)
                    }
                    let x = CGFloat(column) + 0.5
                    path.move(to: CGPoint(x: x, y: middle - CGFloat(high) * scale))
                    path.addLine(to: CGPoint(x: x, y: middle - CGFloat(low) * scale + 0.5))
                }
                context.stroke(path, with: .color(ink.opacity(selected ? 0.85 : 0.6)), lineWidth: 1)
                // Fades drawn as ramps.
                if clip.fadeIn > 0 {
                    var ramp = Path()
                    ramp.move(to: CGPoint(x: 0, y: size.height))
                    ramp.addLine(to: CGPoint(x: CGFloat(clip.fadeIn * pps), y: 12))
                    context.stroke(ramp, with: .color(ink.opacity(0.5)), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                }
                if clip.fadeOut > 0 {
                    var ramp = Path()
                    ramp.move(to: CGPoint(x: size.width - CGFloat(clip.fadeOut * pps), y: 12))
                    ramp.addLine(to: CGPoint(x: size.width, y: size.height))
                    context.stroke(ramp, with: .color(ink.opacity(0.5)), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                }
            }
            Text(clip.name)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(ink.opacity(0.75))
                .lineLimit(1)
                .padding(.horizontal, 6)
                .padding(.top, 3)
        }
        .frame(width: width, height: height)
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(selected ? ink : ink.opacity(0.2), lineWidth: selected ? 1.5 : 0.5)
        }
        .offset(x: CGFloat(clip.start * pps) + drag, y: 5)
        .onTapGesture {
            audio.selectedClip = clip.id
            if let project = audio.project, let found = project.clip(clip.id) { audio.selectedTrack = project.tracks[found.track].id }
        }
        .gesture(
            DragGesture(minimumDistance: 4)
                .onChanged { value in drag = value.translation.width }
                .onEnded { value in
                    drag = 0
                    audio.selectedClip = clip.id
                    audio.move(clip.id, to: max(0, clip.start + Double(value.translation.width) / pps))
                }
        )
        .help("\(clip.name) · \(SoundChapters.clock(clip.length)) · drag to move")
    }
}

// MARK: Bottom panel

private struct AudioPanel: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var audio: AudioModel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("", selection: $audio.panelTab) {
                Text("Clip").tag(0)
                Text("Transcript").tag(1)
                Text("Silences").tag(2)
                Text("Chapters").tag(3)
                Text("Show notes").tag(4)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 520)
            Group {
                switch audio.panelTab {
                case 0: clipTab
                case 1: transcriptTab
                case 2: silencesTab
                case 3: chaptersTab
                default: notesTab
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(12)
        .vellum(level: 3, radius: max(theme.radius - 4, 8))
    }

    @ViewBuilder
    private var clipTab: some View {
        if let clip = audio.clip {
            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(clip.name).font(.system(size: 13, weight: .semibold)).foregroundStyle(theme.ink(scheme))
                    Text("Starts \(SoundChapters.clock(clip.start)) · \(String(format: "%.1f", clip.length)) s")
                        .font(.system(size: 11.5).monospacedDigit()).foregroundStyle(theme.inkTertiary(scheme))
                }
                .frame(width: 180, alignment: .leading)
                VStack(alignment: .leading, spacing: 8) {
                    slider("Gain", value: clip.gain, range: -24...12, unit: "dB") { audio.setClipGain($0) }
                    slider("Fade in", value: clip.fadeIn, range: 0...min(10, clip.length / 2), unit: "s") { audio.setFades(fadeIn: $0) }
                    slider("Fade out", value: clip.fadeOut, range: 0...min(10, clip.length / 2), unit: "s") { audio.setFades(fadeOut: $0) }
                }
                .frame(maxWidth: 360)
            }
        } else {
            Text("Click a clip to change its level and fades. Drag on the ruler to select a stretch; effects then apply to just that part.")
                .font(.system(size: 12))
                .foregroundStyle(theme.inkTertiary(scheme))
        }
    }

    private func slider(_ title: String, value: Double, range: ClosedRange<Double>, unit: String, apply: @escaping (Double) -> Void) -> some View {
        HStack {
            Text(title).font(.system(size: 11.5)).foregroundStyle(theme.inkSecondary(scheme)).frame(width: 56, alignment: .leading)
            Slider(value: Binding(get: { value }, set: apply), in: range).controlSize(.small)
            Text(String(format: unit == "dB" ? "%+.1f dB" : "%.1f s", value)).font(.system(size: 11).monospacedDigit()).foregroundStyle(theme.inkTertiary(scheme)).frame(width: 56)
        }
    }

    @ViewBuilder
    private var transcriptTab: some View {
        let words = audio.project?.words ?? []
        if words.isEmpty {
            HStack {
                Text("Transcribe the selected track on this Mac to find the ums and uhs, and to write show notes.")
                    .font(.system(size: 12)).foregroundStyle(theme.inkTertiary(scheme))
                Button("Transcribe") { audio.transcribe() }.buttonStyle(.vellumSecondary)
            }
        } else {
            HStack(alignment: .top) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Transcriber.lines(from: words)) { line in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(SoundChapters.clock(line.start)).font(.system(size: 10.5).monospacedDigit()).foregroundStyle(theme.inkTertiary(scheme))
                                transcriptText(line, words: words)
                            }
                            .contentShape(Rectangle())
                            .onTapGesture { audio.seek(line.start) }
                        }
                    }
                }
                VStack(alignment: .trailing, spacing: 6) {
                    let fillers = words.filter(\.isFiller).count
                    Text("\(fillers) \(fillers == 1 ? "filler" : "fillers")").font(.system(size: 12, weight: .semibold)).foregroundStyle(theme.ink(scheme))
                    Button("Remove them") { audio.removeFillers() }.buttonStyle(.vellumSecondary).disabled(fillers == 0)
                }
            }
        }
    }

    private func transcriptText(_ line: TranscriptLine, words: [SoundWord]) -> Text {
        let inLine = words.filter { $0.start >= line.start - 0.01 && $0.end <= line.end + 0.01 }
        var result = Text("")
        for word in inLine {
            let piece = Text(word.text + " ")
            result = result + (word.isFiller ? piece.foregroundColor(.orange).bold() : piece.foregroundColor(theme.ink(scheme)))
        }
        return result.font(.system(size: 12.5))
    }

    @ViewBuilder
    private var silencesTab: some View {
        let total = audio.silences.reduce(0) { $0 + ($1.upperBound - $1.lowerBound) }
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("\(audio.silences.count) long \(audio.silences.count == 1 ? "silence" : "silences") on this track")
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(theme.ink(scheme))
                Text(String(format: "%.1f seconds in all, shaded orange on the track. Removing them keeps a quarter-second breath.", total))
                    .font(.system(size: 11.5)).foregroundStyle(theme.inkTertiary(scheme))
                Button("Remove them") { audio.removeSilences() }
                    .buttonStyle(.vellumPrimary)
                    .disabled(audio.silences.isEmpty)
            }
            .frame(width: 280, alignment: .leading)
            ScrollView {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(Array(audio.silences.enumerated()), id: \.offset) { item in
                        Text("\(SoundChapters.clock(item.element.lowerBound)) · \(String(format: "%.1f", item.element.upperBound - item.element.lowerBound)) s")
                            .font(.system(size: 11.5).monospacedDigit())
                            .foregroundStyle(theme.inkSecondary(scheme))
                            .onTapGesture { audio.seek(item.element.lowerBound) }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var chaptersTab: some View {
        let markers = audio.project?.markers ?? []
        HStack(alignment: .top) {
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(markers) { marker in
                        HStack {
                            Text(SoundChapters.clock(marker.time)).font(.system(size: 11.5).monospacedDigit()).foregroundStyle(theme.inkTertiary(scheme))
                            TextField("", text: Binding(get: { marker.name }, set: { audio.renameMarker(marker.id, $0) }))
                                .textFieldStyle(.plain)
                                .font(.system(size: 12.5))
                            Button { audio.deleteMarker(marker.id) } label: { Image(systemName: "minus.circle") }
                                .buttonStyle(.plain)
                                .foregroundStyle(theme.inkTertiary(scheme))
                        }
                    }
                    if markers.isEmpty {
                        Text("Press M to drop a chapter marker at the playhead. Chapters go with the export as a text file.")
                            .font(.system(size: 12)).foregroundStyle(theme.inkTertiary(scheme))
                    }
                }
            }
            Button("Copy chapters") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(audio.project.map(SoundChapters.text) ?? "", forType: .string)
                audio.notice = "Copied the chapters."
            }
            .buttonStyle(.vellumSecondary)
            .disabled(markers.isEmpty)
        }
    }

    @ViewBuilder
    private var notesTab: some View {
        HStack(alignment: .top) {
            ScrollView {
                if let run = audio.notesRun {
                    RunView(run: run)
                } else {
                    Text("Cole writes a summary, chapters and the key points from the transcript.")
                        .font(.system(size: 12)).foregroundStyle(theme.inkTertiary(scheme))
                }
            }
            Button("Write show notes") { audio.showNotes() }
                .buttonStyle(.vellumSecondary)
        }
    }
}
