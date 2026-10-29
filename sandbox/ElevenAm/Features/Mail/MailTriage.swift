import Foundation

/// What an email is like, read from its headers and opening lines. These are the inputs to Marc's lanes.
struct MailTraits: Codable, Hashable, Sendable {
    var bulk = false
    var automated = false
    var question = false
    var deadline = false
    var receipt = false
    var promo = false
    var notice = false
    var toMe = true
    var ccOnly = false
    var crowd = false
    var colleague = false
    var thread = false
    /// The fixed rules' lane and reason: the starting point before Marc has learned anything about you.
    var ruleLane: MailLane = .fyi
    var ruleReason = ""
}

/// Fixed rules, instant and free. They're where Marc starts; what you do teaches him the rest.
enum MailTriage {
    private static let automatedSenders = [
        "noreply", "no-reply", "donotreply", "do-not-reply", "notifications@", "notification@",
        "mailer", "newsletter", "news@", "marketing", "updates@", "receipts@", "billing@", "alerts@", "info@",
    ]
    private static let receiptWords = [
        "receipt", "invoice", "your order", "order confirmation", "payment", "statement",
        "shipped", "delivery", "renewal", "tax invoice",
    ]
    private static let promoWords = ["% off", "sale", "deal", "webinar", "last chance", "new arrivals", "discount", "offer", "free shipping"]
    private static let noticeWords = ["security", "sign-in", "sign in", "password", "verify", "verification", "code", "alert"]
    private static let askWords = [
        "can you", "could you", "would you", "are you free", "let me know", "do you have",
        "when can", "what do you think", "are you open", "would love your", "please confirm", "can we",
    ]
    private static let deadlineWords = ["by friday", "by monday", "by tomorrow", "end of day", "eod", "asap", "urgent", "deadline", "by today", "by thursday", "by wednesday", "by tuesday"]

    static func traits(of message: MailMessage, myAddresses: Set<String>) -> MailTraits {
        var traits = MailTraits()
        let from = (message.fromAddress + " " + message.fromName).lowercased()
        let subject = message.subject.lowercased()
        let opening = String(message.body.prefix(800)).lowercased()
        traits.bulk = message.isBulk
        traits.automated = automatedSenders.contains { from.contains($0) }
        traits.receipt = receiptWords.contains { subject.contains($0) }
        traits.promo = promoWords.contains { subject.contains($0) }
        traits.notice = noticeWords.contains { subject.contains($0) }
        traits.deadline = deadlineWords.contains { opening.contains($0) || subject.contains($0) }
        traits.question = opening.contains("?") || askWords.contains { opening.contains($0) }

        let to = Set(message.to.map { SMTPClient.bareAddress($0).lowercased() })
        let cc = Set(message.cc.map { SMTPClient.bareAddress($0).lowercased() })
        if !myAddresses.isEmpty, !(to.isEmpty && cc.isEmpty) {
            traits.toMe = !to.isDisjoint(with: myAddresses)
            traits.ccOnly = !traits.toMe && !cc.isDisjoint(with: myAddresses)
        }
        traits.crowd = to.count + cc.count > 5
        let myDomains = Set(myAddresses.compactMap { $0.split(separator: "@").last.map(String.init) }).subtracting(MailDomains.shared)
        traits.colleague = myDomains.contains(message.senderDomain)
        traits.thread = message.inReplyTo != nil || subject.hasPrefix("re:")
        (traits.ruleLane, traits.ruleReason) = rule(traits)
        return traits
    }

    private static func rule(_ t: MailTraits) -> (MailLane, String) {
        if t.receipt { return (.fyi, "Receipt or invoice, nothing to reply to. George would file it") }
        if t.bulk || t.automated {
            if t.promo { return (.noise, "Promotion with an unsubscribe link") }
            if t.notice { return (.fyi, "Account notice. Worth a glance, no reply") }
            return t.bulk ? (.noise, "Newsletter or bulk mail") : (.fyi, "Automated notification, no reply needed")
        }
        if t.deadline { return (.needsYou, "Has a deadline") }
        if t.question && !t.crowd { return (.needsYou, "Asks you something directly") }
        if t.ccOnly { return (.fyi, "You're copied in") }
        return (.worthReading, "From a person, no question spotted")
    }
}
