import Foundation

struct MoneyTransaction: Identifiable, Codable, Hashable {
    var id = UUID()
    var date: Date
    var description: String
    /// Negative is money out.
    var amount: Double
    var category: String
}

struct MonthTotals: Identifiable {
    var id: Date { month }
    let month: Date
    let income: Double
    let spend: Double
    var net: Double { income - spend }
}

/// George in the sandbox: cash, burn and runway from your own transactions, sorted by rules that learn from you.
/// He answers questions from the computed numbers only, so he never invents one.
@MainActor
final class MoneyModel: ObservableObject {
    static let categories = ["Revenue", "Payroll", "Contractors", "Software", "Marketing", "Travel", "Office", "Fees", "Other"]

    @Published private(set) var transactions: [MoneyTransaction] = []
    @Published var cash: Double { didSet { UserDefaults.standard.set(cash, forKey: "money.cash") } }
    @Published private(set) var source = "Sample books"
    @Published private(set) var askRun: BrainRun?
    @Published var notice: String?

    private let brain: Brain
    private var rules: [String: String]
    /// What the books add when George is asked something (set by the app).
    var extraFacts: (@MainActor () -> String)?

    init(brain: Brain) {
        self.brain = brain
        cash = UserDefaults.standard.object(forKey: "money.cash") as? Double ?? 182_000
        rules = UserDefaults.standard.dictionary(forKey: "money.rules") as? [String: String] ?? [:]
        if let saved = JSONStore.load([MoneyTransaction].self, from: "money-transactions"), !saved.isEmpty {
            transactions = saved
            source = UserDefaults.standard.string(forKey: "money.source") ?? "Imported"
        } else {
            transactions = MoneySamples.transactions()
        }
    }

    // MARK: Numbers

    /// The last six calendar months, oldest first.
    var months: [MonthTotals] {
        let calendar = Calendar.current
        guard let thisMonth = calendar.dateInterval(of: .month, for: Date())?.start else { return [] }
        return (0..<6).reversed().compactMap { offset -> MonthTotals? in
            guard let start = calendar.date(byAdding: .month, value: -offset, to: thisMonth),
                  let end = calendar.date(byAdding: .month, value: 1, to: start) else { return nil }
            let inMonth = transactions.filter { $0.date >= start && $0.date < end }
            let income = inMonth.filter { $0.amount > 0 }.reduce(0) { $0 + $1.amount }
            let spend = inMonth.filter { $0.amount < 0 }.reduce(0) { $0 - $1.amount }
            return MonthTotals(month: start, income: income, spend: spend)
        }
    }

    /// The last three complete months: the current month is still filling up.
    private var recentFullMonths: [MonthTotals] { Array(months.dropLast().suffix(3)) }

    var monthlyRevenue: Double { average(recentFullMonths.map(\.income)) }
    var grossBurn: Double { average(recentFullMonths.map(\.spend)) }
    var netBurn: Double { max(0, grossBurn - monthlyRevenue) }
    var runwayMonths: Double? { netBurn > 0 ? cash / netBurn : nil }

    /// Spend by category over the last three full months, biggest first.
    var spendByCategory: [(category: String, amount: Double)] {
        guard let first = recentFullMonths.first?.month, let last = recentFullMonths.last?.month,
              let end = Calendar.current.date(byAdding: .month, value: 1, to: last) else { return [] }
        var totals: [String: Double] = [:]
        for item in transactions where item.amount < 0 && item.date >= first && item.date < end {
            totals[item.category, default: 0] -= item.amount
        }
        return totals.map { (category: $0.key, amount: $0.value) }.sorted { $0.amount > $1.amount }
    }

    var recent: [MoneyTransaction] { Array(transactions.sorted { $0.date > $1.date }.prefix(60)) }

    private func average(_ values: [Double]) -> Double {
        values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
    }

    // MARK: Categories

    /// Rules you taught George win; then sensible defaults.
    func categorise(_ description: String, amount: Double) -> String {
        let key = MoneyModel.ruleKey(description)
        if let rule = rules[key] { return rule }
        let text = description.lowercased()
        let defaults: [(String, [String])] = [
            ("Payroll", ["payroll", "salary", "wages", "superannuation", "super "]),
            ("Contractors", ["upwork", "contractor", "freelance", "design work", "kim design"]),
            ("Software", ["aws", "google workspace", "github", "figma", "notion", "slack", "vercel", "openai", "anthropic", "linear", "apple.com"]),
            ("Marketing", ["ads", "linkedin", "meta ", "facebook", "sponsor"]),
            ("Travel", ["uber", "qantas", "virgin", "airbnb", "hotel", "taxi"]),
            ("Office", ["rent", "cowork", "officeworks", "wework"]),
            ("Fees", ["fee", "interest", "merchant"]),
        ]
        if amount > 0 { return "Revenue" }
        for (category, words) in defaults where words.contains(where: { text.contains($0) }) {
            return category
        }
        return "Other"
    }

    /// A correction becomes a rule for that payee.
    func setCategory(_ category: String, for transaction: MoneyTransaction) {
        let key = MoneyModel.ruleKey(transaction.description)
        rules[key] = category
        UserDefaults.standard.set(rules, forKey: "money.rules")
        for index in transactions.indices where MoneyModel.ruleKey(transactions[index].description) == key {
            transactions[index].category = category
        }
        save()
    }

    private static func ruleKey(_ description: String) -> String {
        description.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty && $0.rangeOfCharacter(from: .decimalDigits) == nil }
            .prefix(2)
            .joined(separator: " ")
    }

    // MARK: Import

    func useSample() {
        transactions = MoneySamples.transactions()
        source = "Sample books"
        UserDefaults.standard.removeObject(forKey: "money.source")
        JSONStore.save([MoneyTransaction](), to: "money-transactions")
        notice = nil
    }

    /// Reads a bank CSV export: finds the date, description and amount (or debit/credit) columns by their headers.
    func importCSV(_ url: URL) {
        guard let text = (try? String(contentsOf: url, encoding: .utf8)) ?? (try? String(contentsOf: url, encoding: .isoLatin1)) else {
            notice = "That file couldn't be read."
            return
        }
        let rows = CSV.parse(text)
        guard let header = rows.first?.map({ $0.lowercased() }), rows.count > 1 else {
            notice = "That file has no rows."
            return
        }
        func column(_ names: [String]) -> Int? {
            header.firstIndex { cell in names.contains { cell.contains($0) } }
        }
        guard let dateColumn = column(["date"]),
              let descriptionColumn = column(["description", "details", "narrative", "payee", "memo", "reference", "name"]) else {
            notice = "Couldn't find date and description columns. Export from your bank as CSV with headers."
            return
        }
        let amountColumn = column(["amount", "value"])
        let debitColumn = column(["debit", "withdrawal", "money out"])
        let creditColumn = column(["credit", "deposit", "money in"])
        guard amountColumn != nil || debitColumn != nil || creditColumn != nil else {
            notice = "Couldn't find an amount column."
            return
        }
        var imported: [MoneyTransaction] = []
        for row in rows.dropFirst() {
            func cell(_ index: Int?) -> String { index.flatMap { $0 < row.count ? row[$0] : nil } ?? "" }
            guard let date = CSV.date(cell(dateColumn)) else { continue }
            var amount: Double?
            if let value = CSV.number(cell(amountColumn)) { amount = value }
            else {
                let debit = CSV.number(cell(debitColumn)) ?? 0
                let credit = CSV.number(cell(creditColumn)) ?? 0
                if debit != 0 || credit != 0 { amount = credit - abs(debit) }
            }
            guard let amount, amount != 0 else { continue }
            let description = cell(descriptionColumn).trimmingCharacters(in: .whitespaces)
            imported.append(MoneyTransaction(date: date, description: description, amount: amount, category: categorise(description, amount: amount)))
        }
        guard !imported.isEmpty else {
            notice = "No transactions could be read from that file."
            return
        }
        transactions = imported
        source = url.lastPathComponent
        UserDefaults.standard.set(source, forKey: "money.source")
        save()
        notice = nil
    }

    private func save() {
        guard source != "Sample books" else { return }
        JSONStore.save(transactions, to: "money-transactions")
    }

    // MARK: Asking

    func ask(_ question: String) {
        let question = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else { return }
        let monthLines = months.map { month in
            "\(month.month.formatted(.dateTime.month(.abbreviated).year())): in \(Money.format(month.income)), out \(Money.format(month.spend)), net \(Money.format(month.net))"
        }.joined(separator: "\n")
        let categoryLines = spendByCategory.map { "\($0.category): \(Money.format($0.amount)) over 3 months" }.joined(separator: "\n")
        let facts = """
        Cash in the bank: \(Money.format(cash))
        Average monthly revenue (last 3 full months): \(Money.format(monthlyRevenue))
        Average gross burn: \(Money.format(grossBurn))
        Net burn: \(Money.format(netBurn))
        Runway: \(runwayMonths.map { String(format: "%.1f months", $0) } ?? "not burning cash")

        By month:
        \(monthLines)

        Spend by category:
        \(categoryLines)

        \(extraFacts?() ?? "")
        """
        let system = """
        You are George, the finance agent inside 11am. Answer using only the numbers given. Never invent a number. \
        Show the arithmetic briefly when you calculate. Keep it short and plain. This is not financial or tax advice.
        """
        askRun = brain.run(BrainRequest(system: system, prompt: "\(facts)\n\nQuestion: \(question)", weight: .quick))
    }
}

/// A forgiving CSV reader: quoted fields, embedded commas and quotes, common bank date and number formats.
enum CSV {
    static func parse(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var quoted = false
        var iterator = text.makeIterator()
        var pending: Character?
        while let character = pending ?? iterator.next() {
            pending = nil
            if quoted {
                if character == "\"" {
                    if let next = iterator.next() {
                        if next == "\"" { field.append("\"") } else { quoted = false; pending = next }
                    } else { quoted = false }
                } else {
                    field.append(character)
                }
            } else {
                switch character {
                case "\"": quoted = true
                case ",": row.append(field); field = ""
                case "\n", "\r\n", "\r":
                    row.append(field); field = ""
                    if !(row.count == 1 && row[0].isEmpty) { rows.append(row) }
                    row = []
                default: field.append(character)
                }
            }
        }
        if !field.isEmpty || !row.isEmpty {
            row.append(field)
            rows.append(row)
        }
        return rows
    }

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    private static let dateFormats = ["yyyy-MM-dd", "dd/MM/yyyy", "d/M/yyyy", "dd/MM/yy", "MM/dd/yyyy", "d MMM yyyy", "dd MMM yyyy", "yyyy/MM/dd", "dd-MM-yyyy"]

    static func date(_ text: String) -> Date? {
        let value = text.trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty else { return nil }
        for format in dateFormats {
            formatter.dateFormat = format
            if let date = formatter.date(from: value) { return date }
        }
        return nil
    }

    /// "$1,234.50", "-12.00", "(45.00)" and "1 234,50" style amounts.
    static func number(_ text: String) -> Double? {
        var value = text.trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty else { return nil }
        var negative = false
        if value.hasPrefix("(") && value.hasSuffix(")") { negative = true; value = String(value.dropFirst().dropLast()) }
        if value.hasPrefix("-") || value.hasPrefix("−") { negative = true; value = String(value.dropFirst()) }
        value = value.filter { $0.isNumber || $0 == "." }
        guard let number = Double(value) else { return nil }
        return negative ? -number : number
    }
}

/// Six months of a small startup's books, matching the sample investor update: about 38k out, revenue growing.
enum MoneySamples {
    static func transactions() -> [MoneyTransaction] {
        let calendar = Calendar.current
        guard let thisMonth = calendar.dateInterval(of: .month, for: Date())?.start else { return [] }
        var items: [MoneyTransaction] = []
        func add(_ monthOffset: Int, _ day: Int, _ description: String, _ amount: Double, _ category: String) {
            guard let month = calendar.date(byAdding: .month, value: -monthOffset, to: thisMonth),
                  let date = calendar.date(byAdding: .day, value: day - 1, to: month), date <= Date() else { return }
            items.append(MoneyTransaction(date: date, description: description, amount: amount, category: category))
        }
        let revenue: [Double] = [19_200, 21_000, 22_700, 24_500, 26_400, 27_900]
        for offset in 0..<6 {
            let index = 5 - offset
            add(offset, 3, "Stripe payout", revenue[index] * 0.55, "Revenue")
            add(offset, 17, "Stripe payout", revenue[index] * 0.45, "Revenue")
            add(offset, 15, "Payroll", -28_000, "Payroll")
            add(offset, 2, "Kim Design Studio", -4_000, "Contractors")
            add(offset, 1, "AWS", -910 - Double(index) * 40, "Software")
            add(offset, 1, "Google Workspace", -216, "Software")
            add(offset, 4, "GitHub", -84, "Software")
            add(offset, 6, "Figma", -135, "Software")
            add(offset, 8, "Linear", -96, "Software")
            add(offset, 9, "Vercel", -30, "Software")
            add(offset, 11, "Anthropic API", -140 - Double(index) * 25, "Software")
            add(offset, 12, "LinkedIn Ads", -1_200, "Marketing")
            add(offset, 20, "Meta ads", -800, "Marketing")
            add(offset, 1, "Rent · Fitzroy cowork", -1_050, "Office")
            add(offset, 28, "Bank fee", -18, "Fees")
            if index % 2 == 0 { add(offset, 22, "Qantas", -640, "Travel") }
            if index % 3 == 1 { add(offset, 23, "Uber", -86, "Travel") }
        }
        return items.sorted { $0.date > $1.date }
    }
}
