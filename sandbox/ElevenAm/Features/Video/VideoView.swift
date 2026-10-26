import AVKit
import SwiftUI
import UniformTypeIdentifiers

/// Cole's app: edit video by editing the words.
struct VideoView: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var video: VideoModel
    @EnvironmentObject private var brain: Brain
    @Environment(\.colorScheme) private var scheme
    @State private var importing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(title: "video", subtitle: "Cole · edit video by editing the words") {
                Button {
                    importing = true
                } label: {
                    Label("Open video…", systemImage: "film")
                }
                .buttonStyle(.vellumPrimary)
            }

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 14) {
                    stage.frame(minWidth: 360)
                    TranscriptList().frame(width: 360)
                }
                VStack(spacing: 14) {
                    stage
                    TranscriptList()
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .padding(24)
        .fileImporter(isPresented: $importing, allowedContentTypes: [.movie, .audio]) { result in
            if case .success(let url) = result { withAnimation(theme.spring) { video.open(url) } }
        }
    }

    private var stage: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: max(theme.radius - 2, 8), style: .continuous)
                    .fill(Color.black)
                if let player = video.player {
                    VideoPlayer(player: player)
                        .clipShape(RoundedRectangle(cornerRadius: max(theme.radius - 2, 8), style: .continuous))
                } else {
                    VStack(spacing: 10) {
                        AgentLogo(code: "co", size: 52, color: Color.white.opacity(0.85))
                        Text("Open a video or audio file. It's transcribed on this Mac.")
                            .font(.system(size: 12.5))
                            .foregroundStyle(Color.white.opacity(0.6))
                    }
                }
            }
            .aspectRatio(16 / 9, contentMode: .fit)

            Text(video.status)
                .font(.system(size: 12))
                .foregroundStyle(theme.inkSecondary(scheme))
                .fixedSize(horizontal: false, vertical: true)

            FlowLayout(spacing: 6) {
                Button("Transcribe on this Mac") { video.transcribe() }
                    .buttonStyle(.vellumPrimary)
                    .disabled(video.mediaURL == nil || video.isWorking)
                Button("Export cut video") { video.exportCut() }
                    .buttonStyle(.vellumSecondary)
                    .disabled(video.mediaURL == nil || video.cutCount == 0 || video.isWorking)
                Button("Export captions") { video.exportCaptions() }
                    .buttonStyle(.vellumSecondary)
                    .disabled(video.lines.isEmpty)
                Button("Title & chapters") { video.insights() }
                    .buttonStyle(.vellumSecondary)
                    .disabled(video.lines.isEmpty || brain.isBusy)
                if video.isWorking { ProgressView().controlSize(.small) }
            }

            if let run = video.insightRun {
                Card { RunView(run: run) }
                    .transition(.rise(theme.rise))
            }
        }
        .animation(theme.spring, value: video.insightRun?.id)
    }
}

private struct TranscriptList: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var video: VideoModel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionLabel(text: video.isSample ? "Transcript · sample" : "Transcript")
                Spacer()
                if video.cutCount > 0 {
                    Text("\(video.cutCount) cut · \(VideoModel.clock(video.cutSeconds)) shorter")
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(theme.inkTertiary(scheme))
                        .contentTransition(.numericText())
                }
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(video.lines.enumerated()), id: \.element.id) { index, line in
                        TranscriptRow(line: line)
                            .entrance(index)
                    }
                    if video.lines.isEmpty {
                        Text("Transcribe the file to see every word here.")
                            .font(.system(size: 12.5))
                            .foregroundStyle(theme.inkTertiary(scheme))
                            .padding(10)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            Text("Click a line to jump there. Strike a line to cut it from the video and the captions.")
                .font(.system(size: 11))
                .foregroundStyle(theme.inkTertiary(scheme))
        }
        .padding(14)
        .frame(maxHeight: .infinity, alignment: .top)
        .vellum(level: 3, radius: max(theme.radius - 2, 8))
    }
}

private struct TranscriptRow: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var video: VideoModel
    @Environment(\.colorScheme) private var scheme
    var line: TranscriptLine
    @State private var hovering = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(VideoModel.clock(line.start))
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(theme.inkTertiary(scheme))
                .frame(width: 34, alignment: .leading)
            Text(line.text)
                .font(.system(size: 13))
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
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(hovering ? theme.well(scheme) : Color.clear)
        }
        .contentShape(Rectangle())
        .onTapGesture { video.seek(to: line) }
        .onHover { inside in
            withAnimation(theme.motionEnabled ? .easeOut(duration: 0.12) : nil) { hovering = inside }
        }
    }
}
