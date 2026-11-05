import Foundation

/// A small Melbourne studio's books, four months deep, built through the same calls the app makes,
/// with a few bank lines left for you to reconcile.
enum LedgerSamples {
    private enum Treatment {
        case code(String, GSTCode)
        case invoice(String)
        case transfer(String)
        case leave
    }

    static func book(now: Date = Date()) -> LedgerBook {
        var book = LedgerBook()
        book.settings.businessName = "Northside Studio"
        book.settings.abn = "51 824 753 556"
        book.settings.email = "accounts@northside.studio"
        book.settings.address = "Level 2, 18 Smith Street\nFitzroy VIC 3065"
        book.settings.bsb = "063-000"
        book.settings.accountNumber = "1234 5678"
        book.settings.accountName = "Northside Studio Pty Ltd"

        let calendar = book.calendar
        let today = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: now) ?? now
        func day(_ ago: Int) -> Date { calendar.date(byAdding: .day, value: -ago, to: today) ?? today }

        func contact(_ name: String, _ email: String = "", abn: String = "", address: String = "") -> UUID {
            let person = Contact(name: name, email: email, abn: abn, address: address)
            book.contacts.append(person)
            return person.id
        }
        let acme = contact("Acme Pty Ltd", "accounts@acme.example", abn: "12 345 678 901", address: "100 Collins Street\nMelbourne VIC 3000")
        let northwind = contact("Northwind Traders", "ap@northwind.example", address: "4 Market Lane\nGeelong VIC 3220")
        let bluegum = contact("Bluegum Health", "finance@bluegum.example")
        let kestrel = contact("Kestrel Studio", "hello@kestrel.example")
        let kim = contact("Kim Design Studio", "kim@kimdesign.example")
        let harper = contact("Harper Accounting", "office@harper.example")

        try? book.post(JournalEntry(date: day(120), memo: "Opening balance", source: .opening, lines: [
            JournalLine(account: "090", amount: 4_800_000),
            JournalLine(account: "880", amount: -4_800_000),
        ]))

        func invoice(_ kind: Invoice.Kind, _ who: UUID, _ ago: Int, days: Int = 14, _ lines: [InvoiceLine], approve: Bool = true, reference: String = "") -> String {
            book.clock = day(ago)
            let number = kind == .sale ? book.takeInvoiceNumber() : reference
            let item = Invoice(kind: kind, number: number, contact: who, issued: day(ago), due: day(ago - days), reference: reference, lines: lines)
            book.invoices.append(item)
            if approve { try? book.approve(item.id) }
            return number
        }
        func line(_ description: String, _ quantity: Double = 1, _ price: Cents, _ account: String = "200", _ gst: GSTCode = .gst) -> InvoiceLine {
            InvoiceLine(description: description, quantity: quantity, unitPrice: price, account: account, gst: gst)
        }

        let first = invoice(.sale, acme, 100, [line("Brand strategy workshop", 1, 450_000)])
        let second = invoice(.sale, northwind, 80, [line("Website design, phase 1", 1, 620_000)])
        let third = invoice(.sale, bluegum, 60, [line("Monthly retainer, September", 1, 300_000)])
        _ = invoice(.sale, acme, 45, [line("Campaign design", 12, 15_000), line("Stock images", 1, 18_000)])
        let fifth = invoice(.sale, kestrel, 25, [line("Photography day", 1, 240_000), line("Image licence, 12 months", 1, 60_000)])
        let retainer = invoice(.sale, bluegum, 10, [line("Monthly retainer, October", 1, 300_000)])
        let illustration = invoice(.bill, kim, 50, [line("Illustration set", 1, 200_000, "410")], reference: "KDS-2207")
        _ = invoice(.bill, harper, 20, days: 30, [line("Year-end accounts and tax return", 1, 150_000, "412")], reference: "HA-1189")

        let lines: [(ago: Int, account: String, text: String, amount: Cents, treatment: Treatment)] = [
            (95, "090", "FITZROY COWORK RENT", -115_500, .code("469", .gst)),
            (92, "090", "AWS EMEA aws.amazon.com", -41_030, .code("485", .gst)),
            (91, "090", "GOOGLE*WORKSPACE", -3_300, .code("485", .gst)),
            (90, "090", "COMMBANK MONTHLY FEE", -1_000, .code("404", .free)),
            (88, "090", "ACME PTY LTD \(first)", 495_000, .invoice(first)),
            (80, "090", "WAGES SAM LEE", -480_000, .code("477", .excluded)),
            (78, "090", "SUPERANNUATION CLEARING", -55_200, .code("478", .excluded)),
            (75, "090", "OFFICEWORKS RICHMOND", -132_000, .code("710", .capital)),
            (70, "090", "LINKEDIN ADS", -88_000, .code("400", .gst)),
            (65, "090", "FITZROY COWORK RENT", -115_500, .code("469", .gst)),
            (62, "090", "AWS EMEA aws.amazon.com", -42_815, .code("485", .gst)),
            (62, "090", "NORTHWIND TRADERS", 682_000, .invoice(second)),
            (61, "090", "GOOGLE*WORKSPACE", -3_300, .code("485", .gst)),
            (60, "090", "COMMBANK MONTHLY FEE", -1_000, .code("404", .free)),
            (60, "090", "CREDIT INTEREST", 312, .code("270", .input)),
            (55, "090", "QANTAS AIRWAYS SYDNEY", -64_200, .code("493", .gst)),
            (50, "090", "WAGES SAM LEE", -480_000, .code("477", .excluded)),
            (48, "090", "SUPERANNUATION CLEARING", -55_200, .code("478", .excluded)),
            (40, "090", "BLUEGUM HEALTH", 330_000, .invoice(third)),
            (40, "090", "LINKEDIN ADS", -88_000, .code("400", .gst)),
            (38, "090", "TRANSFER TO SAVINGS", -500_000, .transfer("091")),
            (38, "091", "TRANSFER FROM BUSINESS", 500_000, .leave),
            (35, "090", "KIM DESIGN STUDIO KDS-2207", -220_000, .invoice(illustration)),
            (35, "090", "FITZROY COWORK RENT", -115_500, .code("469", .gst)),
            (32, "090", "AWS EMEA aws.amazon.com", -45_190, .code("485", .gst)),
            (31, "090", "GOOGLE*WORKSPACE", -3_300, .code("485", .gst)),
            (30, "090", "COMMBANK MONTHLY FEE", -1_000, .code("404", .free)),
            (30, "090", "CREDIT INTEREST", 287, .code("270", .input)),
            (20, "090", "WAGES SAM LEE", -480_000, .code("477", .excluded)),
            (18, "090", "SUPERANNUATION CLEARING", -55_200, .code("478", .excluded)),
            (10, "090", "LINKEDIN ADS", -88_000, .code("400", .gst)),
            (5, "090", "FITZROY COWORK RENT", -115_500, .leave),
            (3, "090", "UBER *TRIP HELP.UBER.COM", -3_850, .leave),
            (2, "090", "AWS EMEA aws.amazon.com", -46_320, .leave),
            (2, "090", "KESTREL STUDIO \(fifth)", 330_000, .leave),
        ]
        var statement: [BankLine] = []
        var treatments: [UUID: Treatment] = [:]
        for item in lines {
            let bankLine = BankLine(account: item.account, date: day(item.ago), description: item.text, amount: item.amount,
                                    bankID: "S\(item.ago)-\(abs(item.amount))")
            statement.append(bankLine)
            treatments[bankLine.id] = item.treatment
        }
        book.clock = day(96)
        book.importStatement(statement)
        for bankLine in statement {
            book.clock = calendar.date(byAdding: .hour, value: 30, to: bankLine.date)
            switch treatments[bankLine.id] ?? .leave {
            case .code(let account, let gst):
                try? book.code(bankLine.id, account: account, gst: gst)
            case .invoice(let number):
                if let target = book.invoices.first(where: { $0.number == number }) { try? book.match(bankLine.id, invoice: target.id) }
            case .transfer(let account):
                try? book.transfer(bankLine.id, to: account)
            case .leave:
                break
            }
        }

        // Quotes: one accepted and half invoiced, one waiting, one being written, one that lapsed.
        func quote(_ who: UUID, _ title: String, _ ago: Int, _ lines: [InvoiceLine], status: Quote.Status) -> UUID {
            book.clock = day(ago)
            let id = book.saveQuote(Quote(number: "", contact: who, title: title, issued: day(ago), expires: day(ago - book.settings.quoteDays), lines: lines))
            if status != .draft {
                book.clock = day(max(0, ago - 1))
                book.setQuote(id, status: .sent)
            }
            if status == .accepted || status == .declined {
                book.clock = day(max(0, ago - 6))
                book.setQuote(id, status: status)
            }
            return id
        }
        let phaseTwo = quote(northwind, "Website design, phase 2", 14, [line("Website design, phase 2", 1, 750_000), line("Content migration", 8, 15_000)], status: .accepted)
        book.clock = day(0)
        _ = try? book.invoice(fromQuote: phaseTwo, part: 0.5, issued: day(0))
        _ = quote(bluegum, "Annual report design", 5, [line("Annual report design, 48 pages", 1, 640_000), line("Print management", 1, 90_000)], status: .sent)
        _ = quote(kestrel, "Lookbook shoot", 1, [line("Shoot day", 2, 240_000), line("Retouching, per image", 40, 4_500)], status: .draft)
        _ = quote(acme, "Packaging refresh", 44, [line("Packaging design, three SKUs", 1, 380_000)], status: .sent)

        // Repeating: Bluegum's retainer every month, Acme's care plan every quarter from next week.
        book.clock = day(10)
        var monthly = RepeatingInvoice(contact: bluegum, lines: [line("Monthly retainer, [month]", 1, 300_000)], start: day(10))
        monthly.made = 1
        monthly.lastInvoice = book.invoices.first { $0.number == retainer }?.id
        book.saveSchedule(monthly)
        book.clock = day(3)
        book.saveSchedule(RepeatingInvoice(contact: acme, lines: [line("Website care plan, quarter from [month]", 1, 45_000)], every: 3, start: day(-12)))

        // Marc has chased Acme twice; the third reminder is the final one.
        if let campaign = book.invoices.first(where: { $0.number == "INV-0004" }) {
            book.clock = day(27)
            book.noteReminder(campaign.id, stage: 0)
            book.clock = day(16)
            book.noteReminder(campaign.id, stage: 1)
        }

        // Last quarter's BAS is in, so it's locked.
        book.clock = day(8)
        let quarter = book.quarter(containing: today)
        book.setLockDate(calendar.date(byAdding: .day, value: -1, to: quarter.start))
        book.clock = nil
        return book
    }
}
