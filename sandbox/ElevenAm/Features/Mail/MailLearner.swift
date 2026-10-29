import Accelerate
import Foundation

/// What happened to one email. Each one with an outcome is an example Marc learns from. Kept on this Mac only.
struct MailRecord: Codable, Sendable {
    var id: String
    var accountID: String
    var date: Date
    var sender: String
    var senderName: String
    var domain: String
    var traits: MailTraits
    var opened = false
    /// Seconds from arrival to the first open.
    var openDelay: Double?
    /// Seconds spent reading, in total.
    var dwell: Double = 0
    var replied = false
    var flagged = false
    /// Archived, deleted or unsubscribed without being opened.
    var removedUnread = false
    /// Still unread three days after it arrived.
    var ignored = false
    var snoozed = false
    /// You moved it to a lane: the strongest signal there is.
    var movedTo: MailLane?
    /// Read from the flags your mail server already keeps, when the account was added.
    var fromHistory = false

    init(message: MailMessage, traits: MailTraits) {
        id = message.id
        accountID = message.accountID
        date = message.date
        sender = message.senderKey
        senderName = message.fromName
        domain = message.senderDomain
        self.traits = traits
    }

    /// The lane this outcome points to, and how much it counts.
    var label: (lane: MailLane, weight: Double)? {
        if let movedTo { return (movedTo, 3) }
        if replied { return (.needsYou, 2) }
        if flagged { return (.needsYou, 1.5) }
        if snoozed { return (.needsYou, 0.8) }
        if removedUnread { return (.noise, 1.5) }
        if opened {
            if fromHistory { return (.fyi, 0.6) }
            return dwell >= 20 ? (.worthReading, 1) : (.fyi, 1)
        }
        if ignored { return (.noise, 0.7) }
        return nil
    }
}

/// Counts per sender (or per company domain) of what you did with their mail.
struct SenderStats: Sendable {
    var count = 0
    var opened = 0
    var replied = 0
    var flagged = 0
    var ignored = 0
    var readLong = 0
    var fastOpen = 0

    mutating func add(_ record: MailRecord, _ sign: Int = 1) {
        guard record.label != nil || record.fromHistory || record.opened else { return }
        count += sign
        if record.opened { opened += sign }
        if record.replied { replied += sign }
        if record.flagged { flagged += sign }
        if record.removedUnread || record.ignored { ignored += sign }
        if record.dwell >= 20 { readLong += sign }
        if let delay = record.openDelay, delay < 3_600 { fastOpen += sign }
    }
}

/// One reason Marc gives for a lane, with how much it weighed.
struct MailFactor: Identifiable, Hashable, Sendable {
    var id: String
    var text: String
    var weight: Double
}

struct MailVerdict: Sendable {
    var lane: MailLane
    var reason: String
    var factors: [MailFactor]
    var confidence: Double
    var learned: Bool
}

/// A tiny multinomial logistic regression: 26 features in, a score per lane out. Readable, fast, retrains in a moment.
struct LaneModel: Codable, Sendable {
    static let names = [
        "bias", "known", "replyRate", "openRate", "ignoreRate", "readRate", "flagRate", "domainReply", "domainIgnore",
        "wroteTo", "bulk", "automated", "question", "deadline", "receipt", "promo", "notice", "toMe", "ccOnly", "crowd",
        "colleague", "thread", "rule0", "rule1", "rule2", "rule3",
    ]
    static let features = names.count
    static let lanes = MailLane.allCases.count

    /// Row-major, features × lanes.
    var weights: [Double]

    /// Before any learning: trust the fixed rules.
    static let prior: LaneModel = {
        var weights = [Double](repeating: 0, count: features * lanes)
        for lane in 0..<lanes { weights[(22 + lane) * lanes + lane] = 2.5 }
        return LaneModel(weights: weights)
    }()

    func probabilities(_ x: [Double]) -> [Double] {
        var logits = [Double](repeating: 0, count: LaneModel.lanes)
        for f in 0..<LaneModel.features where x[f] != 0 {
            for c in 0..<LaneModel.lanes { logits[c] += x[f] * weights[f * LaneModel.lanes + c] }
        }
        return LaneModel.softmax(logits)
    }

    static func softmax(_ logits: [Double]) -> [Double] {
        let top = logits.max() ?? 0
        let exps = logits.map { exp($0 - top) }
        let sum = exps.reduce(0, +)
        return exps.map { $0 / sum }
    }

    /// How much each feature pushed towards `lane`, compared with the other lanes.
    func contributions(_ x: [Double], lane: Int) -> [Double] {
        (0..<LaneModel.features).map { f in
            let row = (0..<LaneModel.lanes).map { weights[f * LaneModel.lanes + $0] }
            let mean = row.reduce(0, +) / Double(LaneModel.lanes)
            return x[f] * (row[lane] - mean)
        }
    }

    /// Weighted cross-entropy, pulled gently back towards the rules so a handful of examples can't swing it.
    static func train(_ x: [Double], labels: [Int], weights sampleWeights: [Double], iterations: Int = 300) -> LaneModel {
        let n = labels.count
        let f = features
        let c = lanes
        var model = prior
        guard n > 0 else { return model }
        // Xᵀ, for the gradient.
        var xt = [Double](repeating: 0, count: f * n)
        for i in 0..<n { for j in 0..<f { xt[j * n + i] = x[i * f + j] } }
        let denominator = sampleWeights.reduce(0, +) + 30
        let lambda = 0.02
        let rate = 1.5
        var logits = [Double](repeating: 0, count: n * c)
        var delta = [Double](repeating: 0, count: n * c)
        var gradient = [Double](repeating: 0, count: f * c)
        for _ in 0..<iterations {
            vDSP_mmulD(x, 1, model.weights, 1, &logits, 1, vDSP_Length(n), vDSP_Length(c), vDSP_Length(f))
            for i in 0..<n {
                var top = -Double.infinity
                for k in 0..<c { top = max(top, logits[i * c + k]) }
                var sum = 0.0
                for k in 0..<c {
                    let value = exp(logits[i * c + k] - top)
                    delta[i * c + k] = value
                    sum += value
                }
                for k in 0..<c {
                    let p = delta[i * c + k] / sum
                    delta[i * c + k] = sampleWeights[i] * (p - (labels[i] == k ? 1 : 0))
                }
            }
            vDSP_mmulD(xt, 1, delta, 1, &gradient, 1, vDSP_Length(f), vDSP_Length(c), vDSP_Length(n))
            for index in 0..<(f * c) {
                model.weights[index] -= rate * (gradient[index] / denominator + lambda * (model.weights[index] - prior.weights[index]))
            }
        }
        return model
    }
}

/// Marc's memory of how you handle mail, and the model learned from it.
struct MailLearner: Codable, Sendable {
    var records: [String: MailRecord] = [:]
    /// How often you've written to each address.
    var wroteTo: [String: Int] = [:]
    /// Senders you've moved to a lane yourself. Always obeyed.
    var senderRules: [String: MailLane] = [:]
    var blocked: Set<String> = []
    var unsubscribed: Set<String> = []
    var model = LaneModel.prior
    var trainedAt: Date?
    var accuracy: Double?
    var examples = 0

    private var senders: [String: SenderStats] = [:]
    private var domains: [String: SenderStats] = [:]

    enum CodingKeys: String, CodingKey {
        case records, wroteTo, senderRules, blocked, unsubscribed, model, trainedAt, accuracy, examples
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        records = (try? c.decode([String: MailRecord].self, forKey: .records)) ?? [:]
        wroteTo = (try? c.decode([String: Int].self, forKey: .wroteTo)) ?? [:]
        senderRules = (try? c.decode([String: MailLane].self, forKey: .senderRules)) ?? [:]
        blocked = (try? c.decode(Set<String>.self, forKey: .blocked)) ?? []
        unsubscribed = (try? c.decode(Set<String>.self, forKey: .unsubscribed)) ?? []
        model = (try? c.decode(LaneModel.self, forKey: .model)) ?? LaneModel.prior
        if model.weights.count != LaneModel.features * LaneModel.lanes { model = LaneModel.prior }
        trainedAt = try? c.decode(Date.self, forKey: .trainedAt)
        accuracy = try? c.decode(Double.self, forKey: .accuracy)
        examples = (try? c.decode(Int.self, forKey: .examples)) ?? 0
        rebuildStats()
    }

    mutating func rebuildStats() {
        senders = [:]
        domains = [:]
        for record in records.values { count(record, 1) }
    }

    private mutating func count(_ record: MailRecord, _ sign: Int) {
        senders[record.sender, default: SenderStats()].add(record, sign)
        if !MailDomains.shared.contains(record.domain) {
            domains[record.domain, default: SenderStats()].add(record, sign)
        }
    }

    func stats(for sender: String) -> SenderStats { senders[sender] ?? SenderStats() }

    // MARK: Recording

    /// Makes sure Marc has a record for this email, so what you do with it can teach him.
    /// Mail you'd already read or answered elsewhere arrives with that history.
    mutating func observe(_ message: MailMessage, traits: MailTraits) {
        guard records[message.id] == nil else { return }
        var record = MailRecord(message: message, traits: traits)
        if message.seen || message.answered || message.flagged {
            record.fromHistory = true
            record.opened = message.seen
            record.replied = message.answered
            record.flagged = message.flagged
        }
        records[message.id] = record
        count(record, 1)
    }

    mutating func update(_ id: String, _ change: (inout MailRecord) -> Void) {
        guard var record = records[id] else { return }
        count(record, -1)
        change(&record)
        records[id] = record
        count(record, 1)
    }

    /// Day one: what you already did with mail, read from the server's flags, plus who you write to.
    mutating func importHistory(_ history: [MailRecord], sentTo: [String: Int]) {
        for record in history where records[record.id] == nil {
            records[record.id] = record
            count(record, 1)
        }
        for (address, times) in sentTo { wroteTo[address, default: 0] += times }
    }

    /// Drops a correction, block or unsubscribe, so Marc decides about this sender from behaviour again.
    mutating func forgetRule(for sender: String) {
        senderRules[sender] = nil
        blocked.remove(sender)
        unsubscribed.remove(sender)
    }

    mutating func noteSent(to addresses: [String]) {
        for address in addresses { wroteTo[address.lowercased(), default: 0] += 1 }
    }

    /// Unread for three days counts as "not for you".
    mutating func markIgnored(now: Date = Date()) {
        let cutoff = now.addingTimeInterval(-3 * 86_400)
        for (id, record) in records where !record.opened && !record.ignored && !record.removedUnread && record.movedTo == nil && record.date < cutoff {
            update(id) { $0.ignored = true }
        }
    }

    /// Keeps the newest records so the file stays small.
    mutating func trim(to limit: Int = 6_000) {
        guard records.count > limit else { return }
        let keep = records.values.sorted { $0.date > $1.date }.prefix(limit)
        records = Dictionary(uniqueKeysWithValues: keep.map { ($0.id, $0) })
        rebuildStats()
    }

    // MARK: Features

    func features(sender: String, domain: String, traits: MailTraits, excluding record: MailRecord? = nil) -> [Double] {
        var s = senders[sender] ?? SenderStats()
        let companyDomain = !MailDomains.shared.contains(domain)
        var d = companyDomain ? (domains[domain] ?? SenderStats()) : SenderStats()
        var wrote = wroteTo[sender] ?? 0
        if let record {
            s.add(record, -1)
            if companyDomain { d.add(record, -1) }
            if record.replied { wrote = max(0, wrote - 1) }
        }
        func rate(_ k: Int, _ n: Int, _ prior: Double) -> Double { (Double(max(k, 0)) + prior * 2) / (Double(max(n, 0)) + 2) }
        var x = [Double](repeating: 0, count: LaneModel.features)
        x[0] = 1
        x[1] = min(1, log1p(Double(max(s.count, 0))) / log(30))
        x[2] = rate(s.replied, s.count, 0.1)
        x[3] = rate(s.opened, s.count, 0.6)
        x[4] = rate(s.ignored, s.count, 0.2)
        x[5] = rate(s.readLong, s.count, 0.1)
        x[6] = rate(s.flagged, s.count, 0.05)
        x[7] = companyDomain ? rate(d.replied, d.count, 0.1) : 0.1
        x[8] = companyDomain ? rate(d.ignored, d.count, 0.2) : 0.2
        x[9] = min(1, log1p(Double(wrote)) / log(10))
        let flags = [traits.bulk, traits.automated, traits.question, traits.deadline, traits.receipt, traits.promo,
                     traits.notice, traits.toMe, traits.ccOnly, traits.crowd, traits.colleague, traits.thread]
        for (offset, flag) in flags.enumerated() where flag { x[10 + offset] = 1 }
        x[22 + traits.ruleLane.index] = 1
        return x
    }

    // MARK: Deciding

    func classify(_ message: MailMessage, traits: MailTraits) -> MailVerdict {
        let sender = message.senderKey
        let name = MailLearner.shortName(message.fromName, sender)
        if blocked.contains(sender) {
            return MailVerdict(lane: .noise, reason: "You blocked \(name)", factors: [], confidence: 1, learned: true)
        }
        if unsubscribed.contains(sender) {
            return MailVerdict(lane: .noise, reason: "You unsubscribed from \(name)", factors: [], confidence: 1, learned: true)
        }
        if let lane = senderRules[sender] {
            return MailVerdict(lane: lane, reason: "You moved \(name) here. Marc remembers", factors: [], confidence: 1, learned: true)
        }
        let x = features(sender: sender, domain: message.senderDomain, traits: traits, excluding: records[message.id])
        let p = model.probabilities(x)
        let best = p.indices.max { p[$0] < p[$1] } ?? 0
        let lane = MailLane.allCases[best]
        let factors = explain(x, lane: best, sender: sender, name: name, domain: message.senderDomain, traits: traits, excluding: records[message.id])
        // Lead with what you did, then what the email is like.
        let behaviour = factors.first { MailLearner.behaviourFactors.contains($0.id) }
        let content = factors.first { !MailLearner.behaviourFactors.contains($0.id) }
        let reason = [behaviour?.text, content?.text].compactMap { $0 }.joined(separator: " · ")
        return MailVerdict(lane: lane, reason: reason.isEmpty ? traits.ruleReason : reason, factors: factors,
                           confidence: p[best], learned: trainedAt != nil && behaviour != nil)
    }

    static let behaviourFactors: Set<String> = ["replyRate", "openRate", "ignoreRate", "readRate", "flagRate", "domainReply", "domainIgnore", "wroteTo", "known"]

    private func explain(_ x: [Double], lane: Int, sender: String, name: String, domain: String, traits: MailTraits, excluding record: MailRecord?) -> [MailFactor] {
        var s = senders[sender] ?? SenderStats()
        let companyDomain = !MailDomains.shared.contains(domain)
        var d = companyDomain ? (domains[domain] ?? SenderStats()) : SenderStats()
        if let record {
            s.add(record, -1)
            if companyDomain { d.add(record, -1) }
        }
        let wrote = wroteTo[sender] ?? 0
        let contributions = model.contributions(x, lane: lane)
        var factors: [MailFactor] = []
        for (index, weight) in contributions.enumerated() where weight > 0.25 {
            let id = LaneModel.names[index]
            var text: String?
            switch id {
            case "replyRate" where s.replied > 0: text = "You've replied to \(name) \(s.replied) of \(s.count) times"
            case "openRate" where s.count >= 2: text = "You open \(s.opened) of \(s.count) from \(name)"
            case "ignoreRate" where s.ignored > 0: text = "You leave \(s.ignored) of \(s.count) from \(name) unopened"
            case "readRate" where s.readLong > 0: text = "You usually read \(name) properly (\(s.readLong) of \(s.count))"
            case "flagRate" where s.flagged > 0: text = "You've flagged \(s.flagged) from \(name)"
            case "domainReply" where d.replied > 0: text = "You often reply to people at \(domain)"
            case "domainIgnore" where d.ignored > 0: text = "You rarely open mail from \(domain)"
            case "wroteTo" where wrote > 0: text = "You've written to \(name) \(wrote) \(wrote == 1 ? "time" : "times")"
            case "known" where s.count == 0: text = "New sender"
            case "bulk": text = "Newsletter or bulk mail"
            case "automated": text = "Automated, no reply needed"
            case "question": text = "Asks you something directly"
            case "deadline": text = "Has a deadline"
            case "receipt": text = "Receipt or invoice. George would file it"
            case "promo": text = "A promotion"
            case "notice": text = "Account or security notice"
            case "toMe": text = "Sent to you directly"
            case "ccOnly": text = "You're only copied in"
            case "crowd": text = "Sent to a big group"
            case "colleague": text = "From someone at your company"
            case "thread": text = "Reply in a conversation you're part of"
            case "rule0", "rule1", "rule2", "rule3": text = traits.ruleReason
            default: break
            }
            if let text, !text.isEmpty { factors.append(MailFactor(id: id, text: text, weight: weight)) }
        }
        // The sender's own record says it better than their company's.
        let ids = Set(factors.map(\.id))
        factors.removeAll { ($0.id == "domainIgnore" && ids.contains("ignoreRate")) || ($0.id == "domainReply" && ids.contains("replyRate")) }
        return factors.sorted { $0.weight > $1.weight }
    }

    static func shortName(_ name: String, _ address: String) -> String {
        let clean = name.trimmingCharacters(in: .whitespaces)
        if clean.isEmpty || clean.contains("@") { return address }
        // People by first name; companies and newsletters by their whole name.
        let words = clean.split(separator: " ")
        if words.count == 2, words.allSatisfy({ $0.first?.isUppercase == true }), !clean.contains("'") { return String(words[0]) }
        return clean
    }

    // MARK: Training

    /// Everything needed to train, so the work can happen off the main thread.
    func trainingSet() -> (x: [Double], labels: [Int], weights: [Double]) {
        var x: [Double] = []
        var labels: [Int] = []
        var weights: [Double] = []
        let newest = records.values.filter { $0.label != nil }.sorted { $0.date > $1.date }.prefix(4_000)
        x.reserveCapacity(newest.count * LaneModel.features)
        for record in newest {
            guard let label = record.label else { continue }
            x += features(sender: record.sender, domain: record.domain, traits: record.traits, excluding: record)
            labels.append(label.lane.index)
            weights.append(label.weight)
        }
        return (x, labels, weights)
    }

    static func train(_ set: (x: [Double], labels: [Int], weights: [Double])) -> (model: LaneModel, accuracy: Double?) {
        let model = LaneModel.train(set.x, labels: set.labels, weights: set.weights)
        guard !set.labels.isEmpty else { return (model, nil) }
        var right = 0.0
        var total = 0.0
        for i in set.labels.indices {
            let row = Array(set.x[(i * LaneModel.features)..<((i + 1) * LaneModel.features)])
            let p = model.probabilities(row)
            let best = p.indices.max { p[$0] < p[$1] } ?? 0
            if best == set.labels[i] { right += set.weights[i] }
            total += set.weights[i]
        }
        return (model, total > 0 ? right / total : nil)
    }

    mutating func adopt(_ model: LaneModel, accuracy: Double?, examples: Int) {
        self.model = model
        self.accuracy = accuracy
        self.examples = examples
        trainedAt = Date()
    }

    // MARK: Summary

    struct Sender: Identifiable, Sendable {
        var id: String { address }
        var address: String
        var name: String
        var detail: String
    }

    /// The people you answer, and the senders you never open.
    func highlights(limit: Int = 6) -> (attention: [Sender], ignored: [Sender]) {
        var names: [String: String] = [:]
        for record in records.values { names[record.sender] = record.senderName }
        let attention = senders
            .filter { $0.value.count >= 2 && ($0.value.replied > 0 || $0.value.readLong > 0) }
            .sorted { Double($0.value.replied * 2 + $0.value.readLong) / Double($0.value.count) > Double($1.value.replied * 2 + $1.value.readLong) / Double($1.value.count) }
            .prefix(limit)
            .map { address, s in
                Sender(address: address, name: MailLearner.shortName(names[address] ?? address, address),
                       detail: s.replied > 0 ? "replied \(s.replied) of \(s.count)" : "read \(s.readLong) of \(s.count)")
            }
        let ignored = senders
            .filter { $0.value.count >= 3 && Double($0.value.ignored) / Double($0.value.count) >= 0.6 }
            .sorted { $0.value.ignored > $1.value.ignored }
            .prefix(limit)
            .map { address, s in
                Sender(address: address, name: MailLearner.shortName(names[address] ?? address, address), detail: "unopened \(s.ignored) of \(s.count)")
            }
        return (Array(attention), Array(ignored))
    }

    var historyCount: Int { records.values.filter(\.fromHistory).count }
}
