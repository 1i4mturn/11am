import AppKit
import SwiftUI

/// The strip along the bottom: a ruler you scrub, clips laid end to end with trim handles, and the playhead.
struct VideoTimeline: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var video: VideoModel
    @Environment(\.colorScheme) private var scheme
    /// 0 fits the whole edit; 1 is eight times closer.
    @State private var zoom = 0.0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                SectionLabel(text: "Timeline")
                Text("\(video.clips.count) \(video.clips.count == 1 ? "clip" : "clips") · \(VideoModel.clock(video.totalDuration))")
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(theme.inkTertiary(scheme))
                Spacer(minLength: 8)
                Picker("Shape", selection: $video.aspect) {
                    ForEach(VideoAspect.allCases) { aspect in Text(aspect.title).tag(aspect) }
                }
                .labelsHidden()
                .fixedSize()
                .help("Frame shape. Clips are reframed to fill it; choose what stays in shot in Clip › Framing.")
                Picker("Between clips", selection: $video.transition) {
                    ForEach(VideoTransition.allCases) { transition in Text(transition.title).tag(transition) }
                }
                .labelsHidden()
                .fixedSize()
                Toggle("Fade in and out", isOn: $video.fades)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 12))
                Image(systemName: "minus.magnifyingglass")
                    .foregroundStyle(theme.inkTertiary(scheme))
                Slider(value: $zoom, in: 0...1)
                    .controlSize(.mini)
                    .frame(width: 80)
                Image(systemName: "plus.magnifyingglass")
                    .foregroundStyle(theme.inkTertiary(scheme))
            }

            GeometryReader { proxy in
                let total = max(video.totalDuration, 0.1)
                let fit = max((proxy.size.width - 16) / CGFloat(total), 2)
                let scale = fit * CGFloat(pow(8, zoom))
                let width = CGFloat(total) * scale
                ScrollView(.horizontal, showsIndicators: zoom > 0) {
                    ZStack(alignment: .topLeading) {
                        VStack(alignment: .leading, spacing: 6) {
                            TimelineRuler(total: total, scale: scale) { video.seek(to: $0) }
                                .frame(width: width, height: 16)
                            HStack(spacing: 0) {
                                ForEach(Array(video.clips.enumerated()), id: \.element.id) { index, clip in
                                    ClipBlock(clip: clip, scale: scale, selected: clip.id == video.selection, joined: index > 0 && video.transition != .cut)
                                }
                            }
                        }
                        PlayheadLine(clock: video.clock, scale: scale)
                    }
                    .frame(width: width + 16, alignment: .leading)
                    .padding(.trailing, 4)
                }
                .scrollContentBackground(.hidden)
            }
            .frame(height: 92)
        }
        .padding(12)
        .vellum(level: 3, radius: max(theme.radius - 2, 8))
    }
}

private struct TimelineRuler: View {
    @EnvironmentObject private var theme: Theme
    @Environment(\.colorScheme) private var scheme
    var total: Double
    var scale: CGFloat
    var onScrub: (Double) -> Void

    var body: some View {
        let ink = theme.ink(scheme)
        // Labels at least 56 points apart.
        let step = [1.0, 2, 5, 10, 15, 30, 60, 120, 300, 600].first { CGFloat($0) * scale >= 56 } ?? 600
        Canvas { context, size in
            var time = 0.0
            while time <= total + 0.001 {
                let x = CGFloat(time) * scale
                context.fill(Path(CGRect(x: x, y: size.height - 7, width: 0.75, height: 7)), with: .color(ink.opacity(0.4)))
                context.draw(
                    Text(VideoModel.clock(time)).font(.system(size: 9.5).monospacedDigit()).foregroundColor(ink.opacity(0.46)),
                    at: CGPoint(x: x + 3, y: 5), anchor: .leading
                )
                for minor in 1..<5 {
                    let mx = x + CGFloat(step) * scale * CGFloat(minor) / 5
                    guard mx <= CGFloat(total) * scale else { break }
                    context.fill(Path(CGRect(x: mx, y: size.height - 3, width: 0.5, height: 3)), with: .color(ink.opacity(0.25)))
                }
                time += step
            }
        }
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
            onScrub(Double(max(drag.location.x, 0) / scale))
        })
        .help("Drag to scrub")
    }
}

private struct ClipBlock: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var video: VideoModel
    @Environment(\.colorScheme) private var scheme
    var clip: VideoClip
    var scale: CGFloat
    var selected: Bool
    /// A dip leads into this clip.
    var joined: Bool
    @State private var trimStart: (inPoint: Double, outPoint: Double)?
    @State private var hovering = false

    var body: some View {
        let width = max(CGFloat(clip.editedDuration) * scale, 8)
        let height: CGFloat = 64
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        ZStack(alignment: .bottomLeading) {
            filmstrip(width: width, height: height)
            LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .center, endPoint: .bottom)
            HStack(spacing: 4) {
                Text(clip.name)
                    .lineLimit(1)
                if abs(clip.speed - 1) > 0.001 { Text(String(format: "%g×", clip.speed)) }
                if clip.muted { Image(systemName: "speaker.slash.fill") }
                if clip.useCleanAudio && clip.cleanAudio != nil { Image(systemName: "waveform") }
                if clip.cutCount > 0 { Image(systemName: "scissors") }
                if clip.grade != GradeSettings() { Image(systemName: "camera.filters") }
            }
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(Color.white)
            .padding(.horizontal, 7)
            .padding(.bottom, 5)
            .opacity(width > 50 ? 1 : 0)
        }
        .frame(width: width, height: height)
        .clipShape(shape)
        .overlay {
            shape.strokeBorder(selected ? theme.ink(scheme) : Color.white.opacity(0.5), lineWidth: selected ? 2 : 0.5)
        }
        .overlay(alignment: .leading) { handle(leading: true).opacity(selected || hovering ? 1 : 0) }
        .overlay(alignment: .trailing) { handle(leading: false).opacity(selected || hovering ? 1 : 0) }
        .overlay(alignment: .leading) {
            if joined {
                Image(systemName: "circle.lefthalf.filled")
                    .font(.system(size: 9))
                    .foregroundStyle(theme.paper(scheme))
                    .padding(2)
                    .background(Circle().fill(theme.ink(scheme)))
                    .offset(x: -7, y: -height / 2 + 8)
                    .help("Dip between clips")
            }
        }
        .padding(.horizontal, 1)
        .contentShape(Rectangle())
        .onTapGesture(coordinateSpace: .local) { location in
            video.select(clip.id, at: Double(max(location.x, 0) / scale))
        }
        .onHover { inside in
            withAnimation(theme.motionEnabled ? .easeOut(duration: 0.12) : nil) { hovering = inside }
        }
        .contextMenu {
            Button("Split at playhead") { video.splitAtPlayhead() }
            Button("Duplicate") {
                video.selection = clip.id
                video.duplicateSelected()
            }
            Divider()
            Button("Remove from timeline", role: .destructive) {
                video.selection = clip.id
                video.deleteSelected()
            }
        }
    }

    private func filmstrip(width: CGFloat, height: CGFloat) -> some View {
        let count = max(1, Int((width / 72).rounded(.up)))
        let tile = width / CGFloat(count)
        return HStack(spacing: 0) {
            ForEach(0..<count, id: \.self) { index in
                let source = clip.inPoint + (Double(index) + 0.5) / Double(count) * (clip.outPoint - clip.inPoint)
                ZStack {
                    Rectangle().fill(Color(white: 0.2))
                    if let image = video.thumbnail(for: clip, at: source) {
                        Image(decorative: image, scale: 1)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    }
                }
                .frame(width: tile, height: height)
                .clipped()
            }
        }
    }

    /// Drag an edge to trim; the drag is measured against the window so the clip can change width underneath it.
    private func handle(leading: Bool) -> some View {
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(theme.paper(scheme))
            .overlay {
                RoundedRectangle(cornerRadius: 1).fill(theme.ink(scheme).opacity(0.5)).frame(width: 1.5, height: 18)
            }
            .frame(width: 9, height: 40)
            .shadow(color: .black.opacity(0.25), radius: 2)
            .padding(.horizontal, 3)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .global)
                .onChanged { drag in
                    if trimStart == nil {
                        trimStart = (clip.inPoint, clip.outPoint)
                        video.selection = clip.id
                    }
                    guard let start = trimStart else { return }
                    let delta = Double(drag.translation.width / scale) * clip.speed
                    if leading {
                        video.trim(clip.id, inPoint: start.inPoint + delta)
                    } else {
                        video.trim(clip.id, outPoint: start.outPoint + delta)
                    }
                }
                .onEnded { _ in trimStart = nil }
            )
            .onHover { inside in
                if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
            .help(leading ? "Drag to trim the start" : "Drag to trim the end")
    }
}

private struct PlayheadLine: View {
    @EnvironmentObject private var theme: Theme
    @Environment(\.colorScheme) private var scheme
    @ObservedObject var clock: PlaybackClock
    var scale: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: "arrowtriangle.down.fill")
                .font(.system(size: 9))
            Rectangle()
                .frame(width: 1.5)
        }
        .foregroundStyle(theme.ink(scheme))
        .frame(width: 10)
        .frame(maxHeight: .infinity)
        .offset(x: CGFloat(clock.time) * scale - 5)
        .allowsHitTesting(false)
    }
}
