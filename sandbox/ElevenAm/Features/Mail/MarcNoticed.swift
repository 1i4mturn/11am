import SwiftUI

/// Under the reason line: what Marc thinks this email is, and the one thing to do with it.
struct MarcNoticed: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var mail: MailModel
    @EnvironmentObject private var tasks: TasksModel
    @EnvironmentObject private var ledger: LedgerModel
    @EnvironmentObject private var theme: Theme
    @Environment(\.colorScheme) private var scheme
    var message: MailMessage

    var body: some View {
        if let route = MailRouter.route(subject: message.subject, body: message.body, fromName: message.fromName, fromAddress: message.fromAddress) {
            HStack(spacing: 10) {
                AgentLogo(code: "mc", size: 16, color: theme.inkSecondary(scheme))
                Text(text(for: route))
                    .font(.system(size: 12.5))
                    .foregroundStyle(theme.ink(scheme))
                    .lineLimit(2)
                Spacer(minLength: 8)
                action(for: route)
                    .buttonStyle(.vellumSecondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(theme.well(scheme)))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(theme.edge(scheme), lineWidth: 0.5))
        }
    }

    private func text(for route: MailRouter.Route) -> String {
        switch route {
        case .receipt(let vendor, let total):
            return "Looks like a receipt from \(vendor)" + (total.map { " for \(LedgerMoney.text(LedgerMoney.cents($0)))" } ?? "") + "."
        case .meeting:
            return "\(message.fromName.split(separator: " ").first.map(String.init) ?? message.fromName) wants to find a time."
        case .agreement:
            return "Looks like an agreement to read or sign."
        }
    }

    @ViewBuilder private func action(for route: MailRouter.Route) -> some View {
        switch route {
        case .receipt(let vendor, let total):
            Button("Add to Money") {
                let cents = LedgerMoney.cents(total ?? 0)
                let lower = message.body.lowercased()
                // An invoice still to pay becomes a bill; a receipt for something paid is kept and matched to the bank.
                if ["amount due", "due date", "please pay", "payment due", "due by", "balance due"].contains(where: { lower.contains($0) }) {
                    ledger.draftBill(from: vendor, total: cents, description: message.subject, date: message.date,
                                     reference: String(message.messageID.prefix(60)))
                } else {
                    ledger.addMailReceipt(vendor: vendor, total: cents, date: message.date, subject: message.subject, body: message.body)
                }
                model.go(to: .money)
            }
        case .meeting:
            Button("Reply with times") {
                mail.reply(to: message)
                let times = mail.freeTimes?() ?? ""
                if !times.isEmpty, var draft = mail.composer {
                    let first = Snippets.firstName(fromRecipients: draft.to)
                    draft.body = "Hi \(first.isEmpty ? "there" : first),\n\nHere are some times that work for me:\n\n\(times)\n\n" + draft.body
                    mail.composer = draft
                }
            }
        case .agreement:
            Button("Remind me to sign it") {
                let origin = TaskOrigin(kind: .mail, monogram: "mc", label: "Email from \(message.fromName) · \(message.subject)", reference: message.id)
                _ = tasks.add("Read and sign: \(message.subject) tomorrow", in: .inbox, origin: origin, select: false)
                tasks.notice = nil
                mail.notice = "Added to Tasks for tomorrow: read and sign \(message.subject)."
            }
        }
    }
}
