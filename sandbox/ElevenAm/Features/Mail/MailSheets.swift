import AppKit
import SwiftUI

// MARK: Compose

/// Write or reply. Sends from the account the mail came to, with a few seconds to undo.
struct ComposeView: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var mail: MailModel
    @EnvironmentObject private var brain: Brain
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss
    @State private var draft: MailDraft

    init(draft: MailDraft) {
        _draft = State(initialValue: draft)
    }

    private var original: MailMessage? {
        draft.replyingTo.flatMap { id in mail.messages.first { $0.id == id } }
    }

    private var canSend: Bool {
        mail.sendingAccounts.contains { $0.id == draft.accountID } && !MailModel.split(draft.to).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(draft.replyingTo == nil ? "New email" : "Reply")
                    .font(theme.display(22))
                Spacer()
                if mail.sendingAccounts.isEmpty {
                    Text(mail.source == .sample ? "Sample accounts open your Mail app to send" : "Add an IMAP account to send from 11am")
                        .font(.system(size: 11.5))
                        .foregroundStyle(theme.inkTertiary(scheme))
                } else {
                    Picker("From", selection: $draft.accountID) {
                        ForEach(mail.sendingAccounts) { account in
                            Text("\(account.name) · \(account.address)").tag(account.id)
                        }
                    }
                    .fixedSize()
                }
            }
            field("To", text: $draft.to, placeholder: "name@example.com")
            field("Cc", text: $draft.cc, placeholder: "")
            field("Subject", text: $draft.subject, placeholder: "")
            TextEditor(text: $draft.body)
                .font(.system(size: 13.5))
                .scrollContentBackground(.hidden)
                .padding(10)
                .background {
                    RoundedRectangle(cornerRadius: 10, style: .continuous).fill(theme.well(scheme))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(theme.edge(scheme), lineWidth: 0.5)
                }
                .frame(minHeight: 240)

            if let original, let run = mail.drafts[original.id] {
                MarcDraftStrip(run: run) { text in
                    draft.body = text + "\n\n" + quoted(from: draft.body)
                }
            }

            HStack(spacing: 8) {
                if let original {
                    Button {
                        mail.draftReply(to: original)
                    } label: {
                        Label("Draft with Marc", systemImage: "sparkles")
                    }
                    .buttonStyle(.vellumSecondary)
                    .disabled(brain.isBusy)
                }
                Spacer()
                Button("Cancel") {
                    mail.composer = nil
                    dismiss()
                }
                .buttonStyle(.vellumSecondary)
                .keyboardShortcut(.cancelAction)
                if mail.sendingAccounts.isEmpty {
                    Button("Open in Mail") { mail.openInMail(draft) }
                        .buttonStyle(.vellumPrimary)
                } else {
                    Button("Send") { mail.send(draft) }
                        .buttonStyle(.vellumPrimary)
                        .disabled(!canSend)
                        .keyboardShortcut(.return, modifiers: .command)
                        .help("Send (⌘↩). You'll have a few seconds to undo.")
                }
            }
        }
        .padding(22)
        .frame(width: 640)
        .frame(minHeight: 520)
    }

    /// Keeps the quoted original under a fresh draft.
    private func quoted(from body: String) -> String {
        guard let range = body.range(of: "\nOn ") else { return "" }
        return String(body[range.lowerBound...]).trimmingCharacters(in: .newlines)
    }

    private func field(_ label: String, text: Binding<String>, placeholder: String) -> some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(theme.inkTertiary(scheme))
                .frame(width: 54, alignment: .leading)
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
        }
        .padding(.vertical, 6)
        .overlay(alignment: .bottom) { Rectangle().fill(theme.edge(scheme)).frame(height: 0.5) }
    }
}

private struct MarcDraftStrip: View {
    @EnvironmentObject private var theme: Theme
    @Environment(\.colorScheme) private var scheme
    @ObservedObject var run: BrainRun
    var use: (String) -> Void

    var body: some View {
        HStack(spacing: 10) {
            AgentLogo(code: "mc", size: 18, color: theme.inkSecondary(scheme))
            switch run.status {
            case .done:
                Text("Marc's draft is ready.")
                    .font(.system(size: 12))
                Spacer()
                Button("Use it") { use(run.text) }
                    .buttonStyle(.vellumSecondary)
            case .failed(let message):
                Text(message).font(.system(size: 12)).lineLimit(2)
                Spacer()
            default:
                ThinkingLine(text: "Marc is drafting in your voice…")
                Spacer()
            }
        }
        .foregroundStyle(theme.ink(scheme))
    }
}

// MARK: Add an account

/// Connect an account with an app password. The password goes to the Keychain; mail comes straight from the provider.
struct AddAccountView: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var mail: MailModel
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss
    // -mailProvider outlook preselects a provider, for screenshots.
    @State private var provider = MailProvider(rawValue: UserDefaults.standard.string(forKey: "mailProvider") ?? "") ?? .icloud
    @State private var name = ""
    @State private var address = ""
    @State private var password = ""
    @State private var imapHost = ""
    @State private var smtpHost = ""
    @State private var checking = false
    @State private var error: String?
    @State private var clientID = UserDefaults.standard.string(forKey: "mail.microsoft.clientID") ?? ""
    @State private var tenant = UserDefaults.standard.string(forKey: "mail.microsoft.tenant") ?? "common"
    @State private var showingSteps = UserDefaults.standard.string(forKey: "mail.microsoft.clientID") == nil

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Add an account")
                .font(theme.display(24))
            Text("Marc reads it straight from your provider over an encrypted connection, and learns from what you've already done with it. Nothing goes through anyone else's servers.")
                .font(.system(size: 12.5))
                .foregroundStyle(theme.inkSecondary(scheme))
                .fixedSize(horizontal: false, vertical: true)

            Picker("Provider", selection: $provider) {
                ForEach(MailProvider.allCases) { provider in Text(provider.title).tag(provider) }
            }

            if provider.needsMicrosoftSignIn {
                microsoftSetup
            } else {
                labelled("Name") {
                    TextField("Work, Personal…", text: $name)
                        .textFieldStyle(.roundedBorder)
                }
                labelled("Email") {
                    TextField("you@example.com", text: $address)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: address) { _, value in
                            let guess = MailProvider.guess(for: value)
                            if guess != .other, !guess.needsMicrosoftSignIn { provider = guess }
                        }
                }
                labelled("App password") {
                    SecureField("xxxx-xxxx-xxxx-xxxx", text: $password)
                        .textFieldStyle(.roundedBorder)
                }
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(provider.passwordHelp)
                        .font(.system(size: 11.5))
                        .foregroundStyle(theme.inkTertiary(scheme))
                        .fixedSize(horizontal: false, vertical: true)
                    if let page = provider.passwordPage {
                        Button("Open") { NSWorkspace.shared.open(page) }
                            .buttonStyle(.plain)
                            .font(.system(size: 11.5, weight: .semibold))
                    }
                }
                if provider == .other {
                    labelled("IMAP server") {
                        TextField("imap.example.com (port 993)", text: $imapHost)
                            .textFieldStyle(.roundedBorder)
                    }
                    labelled("SMTP server") {
                        TextField("smtp.example.com (port 465)", text: $smtpHost)
                            .textFieldStyle(.roundedBorder)
                    }
                }
            }

            if let error {
                Text(error)
                    .font(.system(size: 12))
                    .foregroundStyle(theme.ink(scheme))
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 8).fill(theme.well(scheme)))
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 8) {
                Text(provider.needsMicrosoftSignIn ? "11am never sees your Microsoft password." : "The password is kept in your Mac's Keychain.")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.inkTertiary(scheme))
                Spacer()
                if checking { ProgressView().controlSize(.small) }
                Button("Cancel") { dismiss() }
                    .buttonStyle(.vellumSecondary)
                    .keyboardShortcut(.cancelAction)
                if provider.needsMicrosoftSignIn {
                    Button(checking ? "Signing in…" : "Sign in with Microsoft") { signInWithMicrosoft() }
                        .buttonStyle(.vellumPrimary)
                        .disabled(checking || clientID.trimmingCharacters(in: .whitespaces).isEmpty)
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button(checking ? "Checking…" : "Add account") { add() }
                        .buttonStyle(.vellumPrimary)
                        .disabled(checking || address.isEmpty || password.isEmpty)
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(24)
        .frame(width: 560)
        .animation(theme.spring, value: provider)
        .animation(theme.spring, value: error)
    }

    private var microsoftSetup: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Microsoft only lets apps it knows sign in to mail, so 11am needs its own registration with Microsoft. It's free, takes about five minutes, and you do it once.")
                .font(.system(size: 12.5))
                .foregroundStyle(theme.inkSecondary(scheme))
                .fixedSize(horizontal: false, vertical: true)
            labelled("Name") {
                TextField("Personal, Work…", text: $name)
                    .textFieldStyle(.roundedBorder)
            }
            labelled("Client ID") {
                TextField("Application (client) ID", text: $clientID)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12.5).monospaced())
            }
            labelled("Directory") {
                TextField("common", text: $tenant)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12.5).monospaced())
            }
            Text("Leave Directory as common unless you registered 11am for your organisation only; then paste its Directory (tenant) ID.")
                .font(.system(size: 11))
                .foregroundStyle(theme.inkTertiary(scheme))
                .fixedSize(horizontal: false, vertical: true)
            DisclosureGroup("How to get a client ID", isExpanded: $showingSteps) {
                VStack(alignment: .leading, spacing: 7) {
                    step(1, "Open Microsoft Entra and sign in with your Microsoft 365 account.") {
                        Button("Open Entra") {
                            if let url = URL(string: "https://entra.microsoft.com/#view/Microsoft_AAD_RegisteredApps/ApplicationsListBlade") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                        .buttonStyle(.vellumSecondary)
                    }
                    step(2, "App registrations › New registration. Name it 11am.") { EmptyView() }
                    step(3, "Supported account types: the option that includes personal Microsoft accounts (any organisation and personal).") { EmptyView() }
                    step(4, "Redirect URI: choose Public client/native (mobile & desktop), paste this, then Register:") {
                        HStack(spacing: 6) {
                            Text(MicrosoftAuth.redirectURI)
                                .font(.system(size: 12).monospaced())
                                .textSelection(.enabled)
                            Button("Copy") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(MicrosoftAuth.redirectURI, forType: .string)
                            }
                            .buttonStyle(.vellumSecondary)
                        }
                    }
                    step(5, "Copy the Application (client) ID into the box above and choose Sign in with Microsoft.") { EmptyView() }
                    Text("If your organisation needs an admin to approve apps: in the registration, API permissions › Add a permission › APIs my organisation uses › Office 365 Exchange Online › IMAP.AccessAsUser.All, and Microsoft Graph › Mail.Send and offline_access, then Grant admin consent.")
                        .font(.system(size: 11))
                        .foregroundStyle(theme.inkTertiary(scheme))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 6)
            }
            .font(.system(size: 12.5, weight: .medium))
        }
    }

    private func step<Accessory: View>(_ number: Int, _ text: String, @ViewBuilder accessory: () -> Accessory) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(number)")
                .font(.system(size: 11, weight: .bold).monospacedDigit())
                .foregroundStyle(theme.inkTertiary(scheme))
                .frame(width: 12)
            VStack(alignment: .leading, spacing: 5) {
                Text(text)
                    .font(.system(size: 12))
                    .foregroundStyle(theme.ink(scheme))
                    .fixedSize(horizontal: false, vertical: true)
                accessory()
            }
        }
    }

    private func signInWithMicrosoft() {
        checking = true
        error = nil
        Task {
            let problem = await mail.addMicrosoftAccount(app: MicrosoftApp(clientID: clientID, tenant: tenant), name: name)
            checking = false
            if let problem {
                error = problem
            } else {
                dismiss()
            }
        }
    }

    private func add() {
        checking = true
        error = nil
        Task {
            let problem = await mail.addAccount(provider: provider, name: name, address: address, password: password,
                                                imapHost: provider == .other ? imapHost : nil, smtpHost: provider == .other ? smtpHost : nil)
            checking = false
            if let problem {
                error = problem
            } else {
                dismiss()
            }
        }
    }

    private func labelled<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.system(size: 12.5))
                .foregroundStyle(theme.inkSecondary(scheme))
                .frame(width: 100, alignment: .leading)
            content()
        }
    }
}

// MARK: How Marc sorts

/// What Marc has learned from you, in plain words, with every rule you've set and a way to undo it.
struct LearningView: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var mail: MailModel
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss
    @State private var confirmingForget = false

    var body: some View {
        let learner = mail.learner
        let highlights = learner.highlights()
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text("How Marc sorts your mail")
                    .font(theme.display(24))
                Spacer()
                if mail.source == .sample { Chip(text: "Sample history") }
            }
            HStack(spacing: 12) {
                stat("\(learner.examples)", "emails learned from", detail: learner.historyCount > 0 ? "\(learner.historyCount) from before 11am" : nil)
                stat(learner.accuracy.map { "\(Int($0 * 100))%" } ?? "–", "matches what you did", detail: nil)
                stat(learner.trainedAt.map { $0.formatted(date: .omitted, time: .shortened) } ?? "Not yet", "last retrained", detail: nil)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if !highlights.attention.isEmpty {
                        senderList("Gets your attention", highlights.attention)
                    }
                    if !highlights.ignored.isEmpty {
                        senderList("You rarely open", highlights.ignored)
                    }
                    rules
                    VStack(alignment: .leading, spacing: 6) {
                        SectionLabel(text: "What Marc watches")
                        Text("Which emails you open and how soon, how long you read, what you reply to and how fast, flags and snoozes, what you archive or delete without opening, what you leave unread for days, unsubscribes and blocks, and every time you move an email to another lane, which counts most. When you add an account, he starts from the read, replied and flagged marks your provider already keeps, so the lanes are yours from day one.")
                            .font(.system(size: 12.5))
                            .foregroundStyle(theme.inkSecondary(scheme))
                            .fixedSize(horizontal: false, vertical: true)
                        Text("It's a small model on this Mac that retrains in a moment, overnight and after each correction. Nothing about your reading habits leaves the Mac.")
                            .font(.system(size: 12))
                            .foregroundStyle(theme.inkTertiary(scheme))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .scrollContentBackground(.hidden)

            HStack(spacing: 8) {
                Button("Retrain now") { mail.retrainNow() }
                    .buttonStyle(.vellumSecondary)
                    .disabled(mail.isTraining)
                Button("Forget everything…") { confirmingForget = true }
                    .buttonStyle(.vellumSecondary)
                if mail.isTraining { ProgressView().controlSize(.small) }
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.vellumPrimary)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 620, height: 640)
        .confirmationDialog("Forget what Marc has learned?", isPresented: $confirmingForget) {
            Button("Forget everything", role: .destructive) { mail.forgetEverything() }
        } message: {
            Text("Your rules, blocks and his model are cleared. Your mail isn't touched.")
        }
    }

    private func stat(_ value: String, _ label: String, detail: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(theme.display(26))
                .foregroundStyle(theme.ink(scheme))
            Text(label)
                .font(.system(size: 11.5))
                .foregroundStyle(theme.inkSecondary(scheme))
            if let detail {
                Text(detail)
                    .font(.system(size: 10.5))
                    .foregroundStyle(theme.inkTertiary(scheme))
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(theme.well(scheme)))
    }

    private func senderList(_ title: String, _ senders: [MailLearner.Sender]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(text: title)
            ForEach(senders) { sender in
                HStack {
                    Text(sender.name).font(.system(size: 12.5, weight: .medium))
                    Text(sender.address).font(.system(size: 11)).foregroundStyle(theme.inkTertiary(scheme)).lineLimit(1)
                    Spacer()
                    Text(sender.detail).font(.system(size: 11.5).monospacedDigit()).foregroundStyle(theme.inkSecondary(scheme))
                }
            }
        }
    }

    private struct RuleEntry: Identifiable {
        var id: String { sender + text }
        var sender: String
        var text: String
    }

    private var ruleEntries: [RuleEntry] {
        let learner = mail.learner
        var entries: [RuleEntry] = []
        for (sender, lane) in learner.senderRules { entries.append(RuleEntry(sender: sender, text: "Always \(lane.title)")) }
        for sender in learner.blocked { entries.append(RuleEntry(sender: sender, text: "Blocked")) }
        for sender in learner.unsubscribed { entries.append(RuleEntry(sender: sender, text: "Unsubscribed")) }
        return entries.sorted { $0.sender < $1.sender }
    }

    private var rules: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(text: "Your rules")
            if ruleEntries.isEmpty {
                Text("None yet. Move an email to another lane and Marc keeps that sender there.")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.inkTertiary(scheme))
            }
            ForEach(ruleEntries) { entry in
                HStack {
                    Text(entry.sender).font(.system(size: 12.5))
                    Spacer()
                    Text(entry.text).font(.system(size: 11.5)).foregroundStyle(theme.inkSecondary(scheme))
                    Button("Forget") { mail.forgetRule(for: entry.sender) }
                        .buttonStyle(.plain)
                        .font(.system(size: 11.5, weight: .semibold))
                }
            }
        }
    }
}
