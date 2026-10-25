import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Marc's app: what needs you, why, and a reply already drafted in your voice.
struct MailView: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var mail: MailModel
    @Environment(\.colorScheme) private var scheme
    @State private var importing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(title: "mail", subtitle: subtitle) {
                HStack(spacing: 8) {
                    if mail.isLoading {
                        ProgressView().controlSize(.small)
                    }
                    Menu {
                        Button("Sample inbox") { mail.useSample() }
                        Button("Read Apple Mail on this Mac") { mail.readAppleMail() }
                        Button("Open a mailbox file…") { importing = true }
                    } label: {
                        Label(mail.source.title, systemImage: "tray.2")
                    }
                    .menuStyle(.button)
                    .buttonStyle(.borderless)
                    .fixedSize()
                    .foregroundStyle(theme.inkSecondary(scheme))
                }
            }

            LaneBar()

            if let notice = mail.notice {
                MailNotice(error: notice)
                    .transition(.rise(theme.rise))
            }

            HStack(alignment: .top, spacing: 14) {
                MessageList()
                    .frame(width: 280)
                MessageReader()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(24)
        .animation(theme.spring, value: mail.notice == nil)
        .fileImporter(isPresented: $importing, allowedContentTypes: [.item, .folder], allowsMultipleSelection: true) { result in
            if case .success(let urls) = result { mail.importFiles(urls) }
        }
    }

    private var subtitle: String {
        let needs = mail.count(.needsYou)
        switch needs {
        case 0: return "Nothing needs you. Marc sorted the rest."
        case 1: return "1 email needs you. Marc sorted the rest."
        default: return "\(needs) emails need you. Marc sorted the rest."
        }
    }
}

/// Needs you · FYI · Later · Noise, with one highlight that slides between them.
private struct LaneBar: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var mail: MailModel
    @Environment(\.colorScheme) private var scheme
    @Namespace private var highlight

    var body: some View {
        HStack(spacing: 6) {
            ForEach(MailLane.allCases) { lane in
                let selected = mail.lane == lane
                Button {
                    withAnimation(theme.spring) { mail.show(lane) }
                } label: {
                    HStack(spacing: 6) {
                        Text(lane.title)
                            .font(.system(size: 12.5, weight: .semibold))
                        Text("\(mail.count(lane))")
                            .font(.system(size: 11.5, weight: .medium).monospacedDigit())
                            .contentTransition(.numericText())
                            .opacity(0.6)
                    }
                    .foregroundStyle(selected ? theme.paper(scheme) : theme.ink(scheme))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background {
                        if selected {
                            Capsule()
                                .fill(theme.ink(scheme))
                                .matchedGeometryEffect(id: "lane", in: highlight)
                        } else {
                            Capsule().strokeBorder(theme.edge(scheme).opacity(1.6), lineWidth: 0.75)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
    }
}

private struct MailNotice: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var mail: MailModel
    @Environment(\.colorScheme) private var scheme
    var error: MailLoadError

    var body: some View {
        Card {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: error == .noAccess ? "lock" : "tray")
                    .font(.system(size: 16))
                    .foregroundStyle(theme.inkSecondary(scheme))
                VStack(alignment: .leading, spacing: 8) {
                    Text(error.message)
                        .font(.system(size: 12.5))
                        .foregroundStyle(theme.ink(scheme))
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 8) {
                        if error == .noAccess {
                            Button("Open Full Disk Access") {
                                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                                    NSWorkspace.shared.open(url)
                                }
                            }
                            .buttonStyle(.vellumPrimary)
                        }
                        Button("Dismiss") { mail.notice = nil }
                            .buttonStyle(.vellumSecondary)
                    }
                }
            }
        }
    }
}

private struct MessageList: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var mail: MailModel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 3) {
                ForEach(Array(mail.inLane.enumerated()), id: \.element.id) { index, message in
                    MessageRow(message: message, selected: mail.selectedID == message.id)
                        .entrance(index)
                }
                if mail.inLane.isEmpty {
                    Text("Nothing here. New mail lands in the right lane, with a reason.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(theme.inkTertiary(scheme))
                        .padding(12)
                }
            }
            .id(mail.lane)
        }
        .scrollContentBackground(.hidden)
    }
}

private struct MessageRow: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var mail: MailModel
    @Environment(\.colorScheme) private var scheme
    var message: MailMessage
    var selected: Bool
    @State private var hovering = false

    var body: some View {
        Button {
            withAnimation(theme.spring) { mail.selectedID = message.id }
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Text(message.fromName)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    Spacer(minLength: 6)
                    Text(MailDates.short(message.date))
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(theme.inkTertiary(scheme))
                }
                Text(message.subject)
                    .font(.system(size: 12.5))
                    .lineLimit(1)
                Text(message.reason)
                    .font(.system(size: 11))
                    .foregroundStyle(theme.inkTertiary(scheme))
                    .lineLimit(1)
            }
            .foregroundStyle(theme.ink(scheme))
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: max(theme.radius - 3, 7), style: .continuous)
                    .fill(selected ? theme.raised(scheme) : (hovering ? theme.well(scheme).opacity(0.7) : Color.clear))
            }
            .overlay {
                RoundedRectangle(cornerRadius: max(theme.radius - 3, 7), style: .continuous)
                    .strokeBorder(selected ? theme.edge(scheme) : Color.clear, lineWidth: 0.5)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { inside in
            withAnimation(theme.motionEnabled ? .easeOut(duration: 0.12) : nil) { hovering = inside }
        }
        .contextMenu {
            ForEach(MailLane.allCases.filter { $0 != message.lane }) { lane in
                Button("Move to \(lane.title)") { withAnimation(theme.spring) { mail.move(message, to: lane) } }
            }
        }
    }
}

private struct MessageReader: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var mail: MailModel
    @EnvironmentObject private var brain: Brain
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            if let message = mail.selected {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        Text(message.subject)
                            .font(theme.display(22))
                            .foregroundStyle(theme.ink(scheme))
                            .fixedSize(horizontal: false, vertical: true)
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(message.fromName)
                                .font(.system(size: 13, weight: .semibold))
                            Text(message.fromAddress)
                                .font(.system(size: 12))
                                .foregroundStyle(theme.inkTertiary(scheme))
                                .lineLimit(1)
                            Spacer()
                            Text(message.date.formatted(date: .abbreviated, time: .shortened))
                                .font(.system(size: 11.5))
                                .foregroundStyle(theme.inkTertiary(scheme))
                        }
                        .foregroundStyle(theme.ink(scheme))

                        HStack(spacing: 6) {
                            AgentLogo(code: "mc", size: 20, color: theme.inkSecondary(scheme))
                            Text(message.reason)
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundStyle(theme.inkSecondary(scheme))
                            Spacer()
                            Button("Summarise") { mail.summarise(message) }
                                .buttonStyle(.vellumSecondary)
                                .disabled(brain.isBusy)
                        }

                        if let run = mail.summaries[message.id] {
                            Card { RunView(run: run) }
                                .transition(.rise(theme.rise))
                        }

                        Text(message.body)
                            .font(.system(size: 13.5))
                            .lineSpacing(3.5)
                            .foregroundStyle(theme.ink(scheme))
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)

                        DraftCard(message: message)
                            .padding(.top, 4)
                    }
                    .padding(20)
                }
                .scrollContentBackground(.hidden)
                .id(message.id)
                .transition(.rise(theme.rise))
            } else {
                VStack(spacing: 10) {
                    AgentLogo(code: "mc", size: 44, color: theme.inkTertiary(scheme))
                    Text("Pick an email to read it here.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(theme.inkTertiary(scheme))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .vellum(level: 3, radius: max(theme.radius - 2, 8))
        .animation(theme.spring, value: mail.selectedID)
        .animation(theme.spring, value: mail.selected.map { mail.summaries[$0.id] != nil } ?? false)
    }
}

/// The reply Marc drafted, in your voice. Nothing sends from here: it opens in your Mail app for a last look.
private struct DraftCard: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var mail: MailModel
    @EnvironmentObject private var brain: Brain
    @Environment(\.colorScheme) private var scheme
    var message: MailMessage

    private let directions = ["Say yes", "Decline politely", "Ask for a call", "Shorter", "Warmer"]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionLabel(text: "Reply · in your voice")
                Spacer()
                if mail.drafts[message.id] == nil {
                    Button("Draft reply") { mail.draftReply(to: message) }
                        .buttonStyle(.vellumPrimary)
                        .disabled(brain.isBusy)
                }
            }
            if let run = mail.drafts[message.id] {
                DraftText(run: run, message: message)
            } else {
                Text(message.lane == .needsYou
                     ? "Marc writes the first draft so you only review. Overnight, every \"needs you\" email gets one."
                     : "No reply needed, by Marc's reading. You can still draft one.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(theme.inkTertiary(scheme))
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 6) {
                ForEach(directions, id: \.self) { direction in
                    Button(direction) { mail.draftReply(to: message, direction: direction) }
                        .buttonStyle(.vellumSecondary)
                        .controlSize(.small)
                        .disabled(brain.isBusy)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: max(theme.radius - 4, 8), style: .continuous).fill(theme.well(scheme))
        }
        .overlay {
            RoundedRectangle(cornerRadius: max(theme.radius - 4, 8), style: .continuous).strokeBorder(theme.edge(scheme), lineWidth: 0.5)
        }
    }
}

private struct DraftText: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var mail: MailModel
    @Environment(\.colorScheme) private var scheme
    @ObservedObject var run: BrainRun
    var message: MailMessage

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            RunView(run: run)
            if run.status == .done {
                HStack(spacing: 8) {
                    Button("Open in Mail") { mail.openInMail(message, body: run.text) }
                        .buttonStyle(.vellumPrimary)
                    Button("Copy") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(run.text, forType: .string)
                    }
                    .buttonStyle(.vellumSecondary)
                }
                .transition(.rise(theme.rise))
            }
        }
        .animation(theme.spring, value: run.status == .done)
    }
}

enum MailDates {
    static func short(_ date: Date) -> String {
        if date == .distantPast { return "" }
        if Calendar.current.isDateInToday(date) { return date.formatted(date: .omitted, time: .shortened) }
        if Calendar.current.isDateInYesterday(date) { return "Yesterday" }
        return date.formatted(.dateTime.day().month(.abbreviated))
    }
}
