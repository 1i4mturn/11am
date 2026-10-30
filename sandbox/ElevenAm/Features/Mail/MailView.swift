import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Marc's app: every account in one inbox, sorted by what you actually do with mail, with replies in your voice.
struct MailView: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var mail: MailModel
    @EnvironmentObject private var brain: Brain
    @Environment(\.colorScheme) private var scheme
    @State private var importing = false
    // -mailSheet add|learning opens a sheet at launch, for screenshots.
    @State private var addingAccount = UserDefaults.standard.string(forKey: "mailSheet") == "add"
    @State private var showingLearning = UserDefaults.standard.string(forKey: "mailSheet") == "learning"
    @State private var keyMonitor: Any?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "mail", subtitle: subtitle) {
                HStack(spacing: 8) {
                    if !mail.syncing.isEmpty || mail.isLoading || mail.isTraining {
                        ProgressView().controlSize(.small)
                    }
                    MailSearchField(text: $mail.search)
                        .frame(width: 180)
                    Button {
                        Task { await mail.syncAll() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.vellumSecondary)
                    .disabled(mail.source == .sample || !mail.syncing.isEmpty)
                    .help("Check for new mail")
                    accountsMenu
                    Button {
                        showingLearning = true
                    } label: {
                        Image(systemName: "brain")
                    }
                    .buttonStyle(.vellumSecondary)
                    .help("How Marc sorts your mail")
                    Button {
                        mail.compose()
                    } label: {
                        Label("Compose", systemImage: "square.and.pencil")
                    }
                    .buttonStyle(.vellumPrimary)
                    .keyboardShortcut("n", modifiers: [.command, .shift])
                }
            }

            HStack(spacing: 10) {
                LaneBar()
                Spacer(minLength: 8)
                AccountChips()
            }

            if let progress = mail.progress {
                MailBanner(text: progress, symbol: "brain", dismiss: nil)
                    .transition(.rise(theme.rise))
            } else if let notice = mail.notice {
                MailBanner(text: notice, symbol: "info.circle") { mail.notice = nil }
                    .transition(.rise(theme.rise))
            }
            if let error = mail.loadError {
                MailLoadNotice(error: error)
                    .transition(.rise(theme.rise))
            }

            HStack(alignment: .top, spacing: 14) {
                MessageList()
                    .frame(width: 300)
                MessageReader()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(24)
        .overlay(alignment: .bottom) {
            if let pending = mail.pendingSend {
                SendingToast(pending: pending)
                    .padding(.bottom, 28)
                    .transition(.rise(theme.rise))
            }
        }
        .animation(theme.spring, value: mail.notice)
        .animation(theme.spring, value: mail.progress)
        .animation(theme.spring, value: mail.pendingSend)
        .fileImporter(isPresented: $importing, allowedContentTypes: [.item, .folder], allowsMultipleSelection: true) { result in
            if case .success(let urls) = result { mail.importFiles(urls) }
        }
        .sheet(item: $mail.composer) { draft in
            ComposeView(draft: draft)
                .withSheetEnvironment(from: mail, theme: theme, brain: brain)
        }
        .sheet(isPresented: $addingAccount) {
            AddAccountView()
                .withSheetEnvironment(from: mail, theme: theme, brain: brain)
        }
        .sheet(isPresented: $showingLearning) {
            LearningView()
                .withSheetEnvironment(from: mail, theme: theme, brain: brain)
        }
        .onAppear {
            installKeys()
            if mail.addAccountRequest != nil { addingAccount = true }
        }
        .onDisappear {
            removeKeys()
            mail.finishReading()
        }
    }

    private var accountsMenu: some View {
        Menu {
            Button("Add an account…") { addingAccount = true }
            Button("Read Apple Mail on this Mac") { mail.readAppleMail() }
            Button("Open a mailbox file…") { importing = true }
            if mail.source == .live {
                Divider()
                ForEach(mail.accounts) { account in
                    Menu(account.address.isEmpty ? account.name : "\(account.name) · \(account.address)") {
                        if account.kind == .imap {
                            Button("Check now") { Task { await mail.sync(account) } }
                        }
                        if account.microsoft != nil {
                            Button("Sign in again with Microsoft") { mail.signInAgain(account) }
                        }
                        Button("Remove from 11am", role: .destructive) { mail.removeAccount(account) }
                    }
                }
            }
            Divider()
            Button(mail.source == .sample ? "Showing the sample inbox" : "Show the sample inbox") { mail.useSample() }
                .disabled(mail.source == .sample)
        } label: {
            Label("Accounts", systemImage: "person.crop.circle")
        }
        .menuStyle(.button)
        .buttonStyle(.borderless)
        .fixedSize()
        .foregroundStyle(theme.inkSecondary(scheme))
    }

    private var subtitle: String {
        let needs = mail.count(.needsYou)
        let accounts = mail.accounts.count
        if accounts > 1 {
            return "\(needs == 0 ? "Nothing" : "\(needs)") \(needs == 1 ? "needs" : "need") you · \(accounts) accounts"
        }
        switch needs {
        case 0: return "Nothing needs you. Marc sorted the rest."
        case 1: return "1 email needs you. Marc sorted the rest."
        default: return "\(needs) emails need you. Marc sorted the rest."
        }
    }

    /// j/k move, e archives, ⌫ deletes, u read/unread, s flags, r reply, a reply all, f forward.
    /// Only while Mail is on screen, and never while you're typing.
    private func installKeys() {
        guard keyMonitor == nil else { return }
        let model = mail
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let key = event.charactersIgnoringModifiers ?? ""
            let code = event.keyCode
            let plain = event.modifierFlags.intersection([.command, .control, .option]).isEmpty
            let handled = MainActor.assumeIsolated { () -> Bool in
                guard plain, !(NSApp.keyWindow?.firstResponder is NSText), NSApp.keyWindow?.attachedSheet == nil else { return false }
                return MailView.handle(key: key, code: code, model: model)
            }
            return handled ? nil : event
        }
    }

    private static func handle(key: String, code: UInt16, model: MailModel) -> Bool {
        if key == "j" {
            model.selectNext(1)
            return true
        }
        if key == "k" {
            model.selectNext(-1)
            return true
        }
        guard let selected = model.selected else { return false }
        switch key {
        case "e": model.archive(selected)
        case "#": model.delete(selected)
        case "u": model.setSeen(selected, !selected.seen)
        case "s": model.toggleFlag(selected)
        case "r": model.reply(to: selected)
        case "a": model.reply(to: selected, all: true)
        case "f": model.forward(selected)
        default:
            guard code == 51 else { return false } // delete key
            model.delete(selected)
        }
        return true
    }

    private func removeKeys() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }
}

private extension View {
    /// Sheets don't inherit environment objects on every macOS version; pass the ones Mail needs.
    func withSheetEnvironment(from mail: MailModel, theme: Theme, brain: Brain) -> some View {
        environmentObject(mail).environmentObject(theme).environmentObject(brain)
    }
}

private struct MailSearchField: View {
    @EnvironmentObject private var theme: Theme
    @Environment(\.colorScheme) private var scheme
    @Binding var text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(theme.inkTertiary(scheme))
            TextField("Search mail", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
            if !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain)
                    .foregroundStyle(theme.inkTertiary(scheme))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background { Capsule().fill(theme.well(scheme)) }
        .overlay { Capsule().strokeBorder(theme.edge(scheme), lineWidth: 0.5) }
    }
}

/// Needs you · Worth reading · FYI · Noise, with one highlight that slides between them.
private struct LaneBar: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var mail: MailModel
    @Environment(\.colorScheme) private var scheme
    @Namespace private var highlight

    var body: some View {
        HStack(spacing: 6) {
            ForEach(MailLane.allCases) { lane in
                let selected = mail.lane == lane && mail.search.isEmpty
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
                    .fixedSize()
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
            if !mail.snoozed.isEmpty {
                Menu {
                    ForEach(mail.snoozed) { message in
                        Button("\(message.fromName) · \(message.subject)") { mail.unsnooze(message) }
                    }
                } label: {
                    Label("\(mail.snoozed.count) snoozed", systemImage: "moon.zzz")
                        .font(.system(size: 12))
                }
                .menuStyle(.button)
                .buttonStyle(.borderless)
                .fixedSize()
                .foregroundStyle(theme.inkSecondary(scheme))
                .help("Choose one to bring it back now")
            }
        }
    }
}

/// All accounts, or one: a letter for each, with its unread count.
private struct AccountChips: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var mail: MailModel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        if mail.accounts.count > 1 {
            HStack(spacing: 6) {
                chip(title: "All", initial: nil, selected: mail.accountFilter == nil) { mail.accountFilter = nil }
                ForEach(mail.accounts) { account in
                    chip(title: account.name, initial: account.initial, selected: mail.accountFilter == account.id, unread: mail.unread(in: account)) {
                        mail.accountFilter = account.id
                    }
                    .help(account.address)
                }
            }
        }
    }

    private func chip(title: String, initial: String?, selected: Bool, unread: Int = 0, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(theme.spring) { action() }
        } label: {
            HStack(spacing: 5) {
                if let initial { AccountBadge(initial: initial, size: 15) }
                Text(title).font(.system(size: 12, weight: .medium))
                if unread > 0 {
                    Text("\(unread)").font(.system(size: 11).monospacedDigit()).opacity(0.55)
                }
            }
            .fixedSize()
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .foregroundStyle(theme.ink(scheme))
            .background { Capsule().fill(selected ? theme.raised(scheme) : Color.clear) }
            .overlay { Capsule().strokeBorder(theme.edge(scheme).opacity(selected ? 2 : 1), lineWidth: 0.75) }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct AccountBadge: View {
    @EnvironmentObject private var theme: Theme
    @Environment(\.colorScheme) private var scheme
    var initial: String
    var size: CGFloat = 16

    var body: some View {
        Text(initial)
            .font(.system(size: size * 0.55, weight: .bold))
            .foregroundStyle(theme.paper(scheme))
            .frame(width: size, height: size)
            .background(Circle().fill(theme.ink(scheme).opacity(0.75)))
    }
}

private struct MailBanner: View {
    @EnvironmentObject private var theme: Theme
    @Environment(\.colorScheme) private var scheme
    var text: String
    var symbol: String
    var dismiss: (() -> Void)?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(theme.inkSecondary(scheme))
            Text(text)
                .font(.system(size: 12.5))
                .foregroundStyle(theme.ink(scheme))
                .lineLimit(2)
            Spacer()
            if let dismiss {
                Button { dismiss() } label: { Image(systemName: "xmark").font(.system(size: 10, weight: .bold)) }
                    .buttonStyle(.plain)
                    .foregroundStyle(theme.inkTertiary(scheme))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background {
            RoundedRectangle(cornerRadius: max(theme.radius - 4, 8), style: .continuous).fill(theme.well(scheme))
        }
        .overlay {
            RoundedRectangle(cornerRadius: max(theme.radius - 4, 8), style: .continuous).strokeBorder(theme.edge(scheme), lineWidth: 0.5)
        }
    }
}

private struct MailLoadNotice: View {
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
                        Button("Dismiss") { mail.loadError = nil }
                            .buttonStyle(.vellumSecondary)
                    }
                }
            }
        }
    }
}

private struct SendingToast: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var mail: MailModel
    @Environment(\.colorScheme) private var scheme
    var pending: PendingSend

    var body: some View {
        HStack(spacing: 12) {
            ProgressView().controlSize(.small)
            Text(pending.secondsLeft > 0 ? "Sending to \(pending.draft.to) in \(pending.secondsLeft)s" : "Sending to \(pending.draft.to)…")
                .font(.system(size: 12.5, weight: .medium))
                .monospacedDigit()
            Button("Undo") { mail.undoSend() }
                .buttonStyle(.vellumSecondary)
                .disabled(pending.secondsLeft == 0)
                .keyboardShortcut("z", modifiers: .command)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .foregroundStyle(theme.ink(scheme))
        .vellum(level: 1, radius: 22)
    }
}

// MARK: List

private struct MessageList: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var mail: MailModel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 3) {
                if !mail.search.isEmpty {
                    SectionLabel(text: "\(mail.inLane.count) found in every lane")
                        .padding(.horizontal, 12)
                        .padding(.bottom, 4)
                }
                ForEach(Array(mail.inLane.enumerated()), id: \.element.id) { index, message in
                    MessageRow(message: message, selected: mail.selectedID == message.id)
                        .entrance(index)
                }
                if mail.inLane.isEmpty {
                    Text(mail.search.isEmpty ? "Nothing here. New mail lands in the right lane, with a reason." : "No mail matches that.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(theme.inkTertiary(scheme))
                        .padding(12)
                }
            }
            .id("\(mail.lane.rawValue)-\(mail.accountFilter ?? "all")")
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
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    if !message.seen {
                        Circle().fill(theme.ink(scheme)).frame(width: 6, height: 6)
                    }
                    Text(message.fromName)
                        .font(.system(size: 13, weight: message.seen ? .medium : .semibold))
                        .lineLimit(1)
                    if message.flagged { Image(systemName: "flag.fill").font(.system(size: 9)) }
                    if message.answered { Image(systemName: "arrowshape.turn.up.left.fill").font(.system(size: 9)).opacity(0.5) }
                    Spacer(minLength: 6)
                    if mail.accounts.count > 1, mail.accountFilter == nil, let account = mail.account(for: message) {
                        AccountBadge(initial: account.initial, size: 14)
                    }
                    Text(MailDates.short(message.date))
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(theme.inkTertiary(scheme))
                }
                Text(message.subject)
                    .font(.system(size: 12.5))
                    .lineLimit(1)
                HStack(spacing: 4) {
                    if mail.verdicts[message.id]?.learned == true {
                        AgentLogo(code: "mc", size: 11, color: theme.inkTertiary(scheme))
                    }
                    Text(mail.search.isEmpty ? message.reason : "\(message.lane.title) · \(message.reason)")
                        .font(.system(size: 11))
                        .foregroundStyle(theme.inkTertiary(scheme))
                        .lineLimit(1)
                }
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
            Divider()
            Button("Archive") { mail.archive(message) }
            Button(message.seen ? "Mark as unread" : "Mark as read") { mail.setSeen(message, !message.seen) }
            Button(message.flagged ? "Unflag" : "Flag") { mail.toggleFlag(message) }
            Divider()
            Button("Delete", role: .destructive) { mail.delete(message) }
        }
    }
}

// MARK: Reader

private struct MessageReader: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var mail: MailModel
    @EnvironmentObject private var brain: Brain
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            if let message = mail.selected {
                VStack(spacing: 0) {
                    ReaderActions(message: message)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                    Rectangle().fill(theme.edge(scheme)).frame(height: 0.5)
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
                                if let account = mail.account(for: message), mail.accounts.count > 1 {
                                    AccountBadge(initial: account.initial, size: 15)
                                    Text(account.name)
                                        .font(.system(size: 11.5))
                                        .foregroundStyle(theme.inkTertiary(scheme))
                                }
                                Text(message.date.formatted(.dateTime.day().month(.abbreviated).hour().minute()))
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(theme.inkTertiary(scheme))
                                    .fixedSize()
                            }
                            .lineLimit(1)
                            .foregroundStyle(theme.ink(scheme))

                            ReasonLine(message: message)

                            if let run = mail.summaries[message.id] {
                                Card { RunView(run: run) }
                                    .transition(.rise(theme.rise))
                            }

                            Text(message.body.isEmpty ? "The full text downloads on the next sync." : message.body)
                                .font(.system(size: 13.5))
                                .lineSpacing(3.5)
                                .foregroundStyle(theme.ink(scheme).opacity(message.body.isEmpty ? 0.5 : 1))
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)

                            DraftCard(message: message)
                                .padding(.top, 4)
                        }
                        .padding(20)
                    }
                    .scrollContentBackground(.hidden)
                }
                .id(message.id)
                .transition(.rise(theme.rise))
            } else {
                VStack(spacing: 10) {
                    AgentLogo(code: "mc", size: 44, color: theme.inkTertiary(scheme))
                    Text("Pick an email to read it here. j and k move, e archives.")
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

private struct ReaderActions: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var mail: MailModel
    @Environment(\.colorScheme) private var scheme
    var message: MailMessage
    @State private var confirmingUnsubscribe = false

    var body: some View {
        HStack(spacing: 4) {
            icon("arrowshape.turn.up.left", "Reply (r)") { mail.reply(to: message) }
            icon("arrowshape.turn.up.left.2", "Reply all (a)") { mail.reply(to: message, all: true) }
            icon("arrowshape.turn.up.right", "Forward (f)") { mail.forward(message) }
            Divider().frame(height: 16).padding(.horizontal, 4)
            icon("archivebox", "Archive (e)") { mail.archive(message) }
            icon("trash", "Delete (⌫)") { mail.delete(message) }
            icon(message.seen ? "envelope.badge" : "envelope.open", message.seen ? "Mark as unread (u)" : "Mark as read (u)") { mail.setSeen(message, !message.seen) }
            icon(message.flagged ? "flag.fill" : "flag", message.flagged ? "Unflag (s)" : "Flag (s)") { mail.toggleFlag(message) }
            Menu {
                Button("Later today") { mail.snooze(message, until: MailDates.laterToday()) }
                Button("Tomorrow morning") { mail.snooze(message, until: MailDates.tomorrowMorning()) }
                Button("Next week") { mail.snooze(message, until: MailDates.nextWeek()) }
            } label: {
                Image(systemName: "moon.zzz")
            }
            .menuStyle(.button)
            .buttonStyle(.borderless)
            .fixedSize()
            .help("Snooze")
            Spacer()
            Menu {
                ForEach(MailLane.allCases.filter { $0 != message.lane }) { lane in
                    Button("Move to \(lane.title)") { withAnimation(theme.spring) { mail.move(message, to: lane) } }
                }
                Divider()
                if message.unsubscribe != nil {
                    Button("Unsubscribe…") { confirmingUnsubscribe = true }
                }
                Button("Block \(message.fromName)") { mail.block(message) }
            } label: {
                Label("Lane", systemImage: "line.3.horizontal.decrease")
            }
            .menuStyle(.button)
            .buttonStyle(.borderless)
            .fixedSize()
            .help("Move to a lane, unsubscribe or block")
        }
        .foregroundStyle(theme.inkSecondary(scheme))
        .confirmationDialog("Unsubscribe from \(message.fromName)?", isPresented: $confirmingUnsubscribe) {
            Button("Unsubscribe") { mail.unsubscribe(message) }
        } message: {
            Text(message.unsubscribe?.oneClick == true
                 ? "Marc sends the standard one-click request. Nothing else is shared."
                 : "Marc uses the sender's own unsubscribe email or page.")
        }
    }

    private func icon(_ symbol: String, _ help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13))
                .frame(width: 28, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

/// Marc's reason, with the evidence behind it one click away.
private struct ReasonLine: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var mail: MailModel
    @EnvironmentObject private var brain: Brain
    @Environment(\.colorScheme) private var scheme
    var message: MailMessage
    @State private var showingWhy = false

    var body: some View {
        HStack(spacing: 6) {
            AgentLogo(code: "mc", size: 20, color: theme.inkSecondary(scheme))
            Text("\(message.lane.title) · \(message.reason)")
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(theme.inkSecondary(scheme))
                .lineLimit(2)
            Button("Why?") { showingWhy = true }
                .buttonStyle(.plain)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(theme.ink(scheme))
                .popover(isPresented: $showingWhy, arrowEdge: .bottom) {
                    WhyPopover(message: message)
                        .environmentObject(mail)
                        .environmentObject(theme)
                }
            Spacer()
            Button("Summarise") { mail.summarise(message) }
                .buttonStyle(.vellumSecondary)
                .disabled(brain.isBusy || message.body.isEmpty)
        }
    }
}

private struct WhyPopover: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var mail: MailModel
    @Environment(\.colorScheme) private var scheme
    var message: MailMessage

    var body: some View {
        let verdict = mail.verdicts[message.id]
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Why it's in \(message.lane.title)")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                if let confidence = verdict?.confidence {
                    Text("\(Int(confidence * 100))% sure")
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(theme.inkTertiary(scheme))
                }
            }
            if let factors = verdict?.factors, !factors.isEmpty {
                let top = factors.map(\.weight).max() ?? 1
                ForEach(factors.prefix(5)) { factor in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(factor.text).font(.system(size: 12))
                        Capsule()
                            .fill(theme.ink(scheme).opacity(MailLearner.behaviourFactors.contains(factor.id) ? 0.7 : 0.3))
                            .frame(width: max(6, 220 * factor.weight / max(top, 0.01)), height: 4)
                    }
                }
                Text("Dark bars are what you've done; light bars are what the email is like.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(theme.inkTertiary(scheme))
            } else {
                Text(message.reason).font(.system(size: 12))
            }
            Divider()
            Text("Wrong lane? Move it and Marc learns.")
                .font(.system(size: 11.5))
                .foregroundStyle(theme.inkSecondary(scheme))
            HStack(spacing: 6) {
                ForEach(MailLane.allCases.filter { $0 != message.lane }) { lane in
                    Button(lane.title) { withAnimation(theme.spring) { mail.move(message, to: lane) } }
                        .buttonStyle(.vellumSecondary)
                }
            }
        }
        .padding(16)
        .frame(width: 380)
    }
}

/// The reply Marc drafted, in your voice. It opens in the composer for a last look before anything sends.
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
                     ? "Marc writes the first draft in your voice, so you only review."
                     : "No reply needed, by Marc's reading. You can still draft one.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(theme.inkTertiary(scheme))
                    .fixedSize(horizontal: false, vertical: true)
            }
            FlowLayout(spacing: 6) {
                ForEach(directions, id: \.self) { direction in
                    Button(direction) { mail.draftReply(to: message, direction: direction) }
                        .buttonStyle(.vellumSecondary)
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
                    Button("Review and send") { mail.reply(to: message) }
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

    static func laterToday() -> Date {
        Date().addingTimeInterval(3 * 3_600)
    }

    static func tomorrowMorning() -> Date {
        let calendar = Calendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        return calendar.date(bySettingHour: 8, minute: 30, second: 0, of: tomorrow) ?? tomorrow
    }

    static func nextWeek() -> Date {
        let calendar = Calendar.current
        let next = calendar.nextDate(after: Date(), matching: DateComponents(hour: 8, minute: 30, weekday: 2), matchingPolicy: .nextTime)
        return next ?? Date().addingTimeInterval(7 * 86_400)
    }
}
