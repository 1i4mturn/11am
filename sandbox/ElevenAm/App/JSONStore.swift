import Foundation

/// Small JSON files in Application Support, one per app. Plenty for a sandbox; the real thing uses the Rust core's store.
enum JSONStore {
    static var folder: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("11am-sandbox", isDirectory: true)
    }

    static func load<T: Decodable>(_ type: T.Type, from name: String) -> T? {
        let url = folder.appendingPathComponent("\(name).json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(type, from: data)
    }

    static func save<T: Encodable>(_ value: T, to name: String) {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(value) else { return }
        try? data.write(to: folder.appendingPathComponent("\(name).json"), options: .atomic)
    }
}

/// Money in the user's own currency, without cents unless they matter.
enum Money {
    static var currencyCode: String { Locale.current.currency?.identifier ?? "USD" }

    static func format(_ value: Double, cents: Bool = false) -> String {
        value.formatted(.currency(code: currencyCode).precision(.fractionLength(cents ? 2 : 0)))
    }

    static func short(_ value: Double) -> String {
        let magnitude = abs(value)
        let sign = value < 0 ? "−" : ""
        let symbol = Locale.current.currencySymbol ?? "$"
        if magnitude >= 1_000_000 { return "\(sign)\(symbol)\(String(format: "%.1f", magnitude / 1_000_000))m" }
        if magnitude >= 1_000 { return "\(sign)\(symbol)\(String(format: "%.0f", magnitude / 1_000))k" }
        return "\(sign)\(symbol)\(Int(magnitude))"
    }
}
