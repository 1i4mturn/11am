import Foundation

/// A believable founder's morning across two accounts, plus a few months of made-up history,
/// so the lanes and Marc's reasons make sense before any real mail is connected.
enum MailSamples {
    static let work: MailAccount = {
        var account = MailAccount(kind: .sample, name: "Work", address: "you@elevenam.app")
        account.id = "sample-work"
        account.colorIndex = 0
        return account
    }()

    static let personal: MailAccount = {
        var account = MailAccount(kind: .sample, name: "Personal", address: "you@icloud.com")
        account.id = "sample-personal"
        account.colorIndex = 1
        return account
    }()

    static var accounts: [MailAccount] { [work, personal] }

    static func inbox() -> [MailMessage] {
        let now = Date()
        func ago(_ minutes: Double) -> Date { now.addingTimeInterval(-minutes * 60) }
        func mail(_ id: String, _ account: MailAccount, _ name: String, _ address: String, _ subject: String, _ minutes: Double,
                  _ body: String, bulk: Bool = false, cc: [String] = []) -> MailMessage {
            var message = MailMessage(id: id, accountID: account.id, fromName: name, fromAddress: address, subject: subject, date: ago(minutes), body: body)
            message.to = [account.address]
            message.cc = cc
            message.messageID = "<\(id)@sample.11am>"
            message.isBulk = bulk
            if bulk, let domain = address.split(separator: "@").last {
                message.unsubscribe = MailUnsubscribe(url: URL(string: "https://\(domain)/unsubscribe"), mailto: nil, oneClick: true)
            }
            return message
        }
        return [
            mail("s1", work, "Priya Shah", "priya@northwind.vc", "Quick question on the round", 14,
                 "Hi,\n\nThanks for the update last week. Before our partner meeting on Thursday, could you confirm how much of the round is already committed, and whether the angel allocation is still open?\n\nAlso keen to hear how the pilot with Acme is tracking.\n\nBest,\nPriya"),
            mail("s2", work, "Tom Becker", "tom@acme.co", "Deck for the board", 52,
                 "Hey,\n\nGreat call yesterday. Can you send through the deck by Friday so I can share it with the board ahead of Monday? A one-page summary would help too if you have one.\n\nCheers,\nTom"),
            mail("s3", work, "Jess Wong", "jess@studiowong.com", "Intro: Jess and you (design partner)", 95,
                 "Hi there,\n\nSam suggested we connect. I run a small product studio and we've been looking for a design partner project in the productivity space. Would you be open to a 20 minute call next week?\n\nJess"),
            mail("s4", personal, "Mum", "mum@family.net", "Sunday", 130,
                 "Are you free for dinner Sunday night? Your brother is coming. Let me know so I can plan.\n\nLove, Mum"),
            mail("s5", work, "Sam Ortiz", "sam@elevenam.app", "Notes from the Acme call", 180,
                 "Dropping my notes here so they're somewhere.\n\n- They want SSO before rollout\n- Pilot is 40 seats, starts the 3rd\n- Tom is the champion, CFO signs\n\nNothing needed from you yet."),
            mail("s6", work, "Alex Kim", "alex@kimdesign.co", "Invoice #0042 for October", 210,
                 "Hi, attached is the invoice for October's design work. Terms are 14 days as usual. Thanks!"),
            mail("s7", work, "Stripe", "receipts@stripe.com", "Your receipt from Vercel Inc.", 260,
                 "Receipt #2241-0093\nAmount paid: US$20.00\nPro plan, monthly."),
            mail("s8", work, "Linear", "notifications@linear.app", "3 issues were assigned to you", 300,
                 "ENG-412 Notch flickers on external display\nENG-415 Brief cuts off long titles\nENG-418 Overnight job log shows twice"),
            mail("s9", personal, "Google", "no-reply@accounts.google.com", "Security alert: new sign-in on Mac", 340,
                 "We noticed a new sign-in to your Google Account on a Mac device. If this was you, you don't need to do anything."),
            mail("s10", work, "Figma", "news@figma.com", "Config 2026: the recap", 400,
                 "Everything we announced, in one place. Read the recap.", bulk: true),
            mail("s11", personal, "Qantas", "offers@qantas.com.au", "Last chance: 20% off flights to Tokyo", 460,
                 "Sale ends midnight. Book now.", bulk: true),
            mail("s12", personal, "Lenny's Newsletter", "lenny@substack.com", "How the best founders price their first product", 520,
                 "This week: pricing your first product, with examples from 30 founders.", bulk: true),
            mail("s13", personal, "Mia Chen", "mia.chen@gmail.com", "Photos from Saturday", 600,
                 "Here are the photos from Saturday. That sunset was unreal."),
        ]
    }

    /// Months of pretend behaviour: who you answer, what you read properly, what you never open.
    static func learner() -> MailLearner {
        struct Pattern {
            let account: MailAccount
            let name: String
            let address: String
            let count: Int
            let opened: Int
            let replied: Int
            let readLong: Int
            let removed: Int
            var question = false
            var bulk = false
            var subject = "Hello"
        }
        let patterns = [
            Pattern(account: work, name: "Priya Shah", address: "priya@northwind.vc", count: 10, opened: 10, replied: 9, readLong: 6, removed: 0, question: true),
            Pattern(account: work, name: "Tom Becker", address: "tom@acme.co", count: 6, opened: 6, replied: 5, readLong: 2, removed: 0, question: true),
            Pattern(account: personal, name: "Mum", address: "mum@family.net", count: 20, opened: 20, replied: 14, readLong: 4, removed: 0, question: true),
            Pattern(account: work, name: "Sam Ortiz", address: "sam@elevenam.app", count: 30, opened: 28, replied: 3, readLong: 24, removed: 0),
            Pattern(account: work, name: "Alex Kim", address: "alex@kimdesign.co", count: 8, opened: 8, replied: 0, readLong: 0, removed: 0, subject: "Invoice"),
            Pattern(account: work, name: "Stripe", address: "receipts@stripe.com", count: 30, opened: 2, replied: 0, readLong: 0, removed: 10, subject: "Your receipt"),
            Pattern(account: work, name: "Linear", address: "notifications@linear.app", count: 25, opened: 22, replied: 0, readLong: 1, removed: 0),
            Pattern(account: personal, name: "Google", address: "no-reply@accounts.google.com", count: 3, opened: 3, replied: 0, readLong: 0, removed: 0, subject: "Security alert"),
            Pattern(account: work, name: "Figma", address: "news@figma.com", count: 12, opened: 1, replied: 0, readLong: 0, removed: 4, bulk: true),
            Pattern(account: personal, name: "Qantas", address: "offers@qantas.com.au", count: 40, opened: 0, replied: 0, readLong: 0, removed: 25, bulk: true, subject: "20% off"),
            Pattern(account: personal, name: "Lenny's Newsletter", address: "lenny@substack.com", count: 20, opened: 18, replied: 0, readLong: 16, removed: 0, bulk: true),
            Pattern(account: personal, name: "Mia Chen", address: "mia.chen@gmail.com", count: 6, opened: 6, replied: 3, readLong: 3, removed: 0),
        ]
        var learner = MailLearner()
        var history: [MailRecord] = []
        let now = Date()
        for pattern in patterns {
            for index in 0..<pattern.count {
                let asks = pattern.question && index % 2 == 0
                var message = MailMessage(
                    id: "sample-history-\(pattern.address)-\(index)", accountID: pattern.account.id,
                    fromName: pattern.name, fromAddress: pattern.address, subject: pattern.subject,
                    date: now.addingTimeInterval(-Double(index + 4) * 3.5 * 86_400), body: asks ? "Could you let me know?" : "Here it is."
                )
                message.to = [pattern.account.address]
                message.isBulk = pattern.bulk
                var record = MailRecord(message: message, traits: MailTriage.traits(of: message, myAddresses: [pattern.account.address]))
                record.opened = index < pattern.opened
                record.openDelay = record.opened ? 600 : nil
                record.replied = index < pattern.replied
                record.dwell = index < pattern.readLong ? 90 : (record.opened ? 8 : 0)
                record.removedUnread = !record.opened && index >= pattern.count - pattern.removed
                record.ignored = !record.opened && !record.removedUnread
                history.append(record)
            }
        }
        var sentTo: [String: Int] = [:]
        for pattern in patterns where pattern.replied > 0 { sentTo[pattern.address] = pattern.replied + 2 }
        learner.importHistory(history, sentTo: sentTo)
        return learner
    }
}
