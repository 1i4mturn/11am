import Foundation

/// The Claude models a user can pick. Prices are US$ per million tokens (Anthropic API rates, Oct 2026).
struct ClaudeModel: Identifiable, Hashable {
    let id: String
    let name: String
    let note: String
    let inputPerMillion: Double
    let outputPerMillion: Double
    /// Opus and Sonnet support server-side refusal fallbacks; Haiku doesn't.
    let supportsDefaultFallback: Bool

    static let defaultID = "claude-opus-5-5"

    static let all: [ClaudeModel] = [
        ClaudeModel(id: "claude-opus-5-5", name: "Claude Opus 5.5", note: "Best quality", inputPerMillion: 4, outputPerMillion: 20, supportsDefaultFallback: true),
        ClaudeModel(id: "claude-sonnet-5-5", name: "Claude Sonnet 5.5", note: "Balanced", inputPerMillion: 2, outputPerMillion: 10, supportsDefaultFallback: true),
        ClaudeModel(id: "claude-haiku-5-5", name: "Claude Haiku 5.5", note: "Fastest, cheapest", inputPerMillion: 0.10, outputPerMillion: 0.50, supportsDefaultFallback: false),
    ]

    static func find(_ id: String) -> ClaudeModel? {
        all.first { id.hasPrefix($0.id) }
    }
}

enum Pricing {
    static func cost(model: String, inputTokens: Int, outputTokens: Int) -> Double {
        guard let entry = ClaudeModel.find(model) else { return 0 }
        return Double(inputTokens) / 1_000_000 * entry.inputPerMillion
            + Double(outputTokens) / 1_000_000 * entry.outputPerMillion
    }

    static func format(_ usd: Double) -> String {
        if usd == 0 { return "US$0.00" }
        if usd < 0.01 { return String(format: "US$%.4f", usd) }
        return String(format: "US$%.2f", usd)
    }
}

/// Calls the Claude Messages API directly with the user's own key, streaming the answer.
/// Swift has no official Anthropic SDK, so this is raw HTTPS.
struct ClaudeProvider: BrainProvider {
    let kind = ProviderKind.claude
    let apiKey: String
    let model: String

    var label: String { ClaudeModel.find(model)?.name ?? model }

    private static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    private static let apiVersion = "2026-10-21"

    func stream(_ request: BrainRequest) -> AsyncThrowingStream<BrainChunk, Error> {
        let urlRequest: URLRequest
        do {
            urlRequest = try makeRequest(request)
        } catch {
            return AsyncThrowingStream { $0.finish(throwing: error) }
        }

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let (bytes, response) = try await URLSession.shared.bytes(for: urlRequest)
                    guard let http = response as? HTTPURLResponse else { throw BrainError.badResponse }
                    guard http.statusCode == 200 else {
                        var body = Data()
                        for try await byte in bytes { body.append(byte) }
                        throw BrainError.http(http.statusCode, ClaudeProvider.errorMessage(from: body))
                    }

                    var inputTokens = 0
                    for try await line in bytes.lines {
                        guard line.hasPrefix("data:") else { continue }
                        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        guard let data = payload.data(using: .utf8),
                              let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                              let type = event["type"] as? String else { continue }

                        switch type {
                        case "message_start":
                            if let message = event["message"] as? [String: Any] {
                                if let name = message["model"] as? String { continuation.yield(.model(name)) }
                                if let usage = message["usage"] as? [String: Any] {
                                    inputTokens = ClaudeProvider.inputTokens(usage)
                                    continuation.yield(.usage(input: inputTokens, output: 0))
                                }
                            }
                        case "content_block_delta":
                            // Only visible text is shown; thinking blocks stream with empty text by default.
                            if let delta = event["delta"] as? [String: Any],
                               delta["type"] as? String == "text_delta",
                               let text = delta["text"] as? String {
                                continuation.yield(.delta(text))
                            }
                        case "message_delta":
                            if let usage = event["usage"] as? [String: Any] {
                                let output = usage["output_tokens"] as? Int ?? 0
                                continuation.yield(.usage(input: inputTokens, output: output))
                            }
                            if let delta = event["delta"] as? [String: Any],
                               delta["stop_reason"] as? String == "refusal" {
                                continuation.yield(.refusal)
                            }
                        case "error":
                            let message = (event["error"] as? [String: Any])?["message"] as? String ?? "Unknown error"
                            throw BrainError.http(0, message)
                        default:
                            break
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func makeRequest(_ request: BrainRequest) throws -> URLRequest {
        var urlRequest = URLRequest(url: ClaudeProvider.endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = 300
        urlRequest.setValue("application/json", forHTTPHeaderField: "content-type")
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        urlRequest.setValue(ClaudeProvider.apiVersion, forHTTPHeaderField: "anthropic-version")

        var body: [String: Any] = [
            "model": model,
            "max_tokens": request.maxTokens,
            "stream": true,
            "system": request.system,
            "messages": [["role": "user", "content": request.prompt]],
            // Effort keeps spend proportional to the job: quick work thinks briefly.
            "output_config": ["effort": request.weight == .quick ? "low" : "medium"],
        ]

        // If a safety classifier declines, the API retries on Anthropic's recommended fallback model.
        if ClaudeModel.find(model)?.supportsDefaultFallback == true {
            urlRequest.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
            body["fallbacks"] = "default"
        }

        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)
        return urlRequest
    }

    private static func inputTokens(_ usage: [String: Any]) -> Int {
        let plain = usage["input_tokens"] as? Int ?? 0
        let cacheWrite = usage["cache_creation_input_tokens"] as? Int ?? 0
        let cacheRead = usage["cache_read_input_tokens"] as? Int ?? 0
        return plain + cacheWrite + cacheRead
    }

    private static func errorMessage(from data: Data) -> String {
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let error = object["error"] as? [String: Any],
           let message = error["message"] as? String {
            return message
        }
        return String(data: data, encoding: .utf8) ?? "Unknown error"
    }

    /// A tiny request to check the key works. Costs a fraction of a cent.
    static func testKey(_ key: String, model: String) async -> String {
        let provider = ClaudeProvider(apiKey: key, model: model)
        let request = BrainRequest(system: "Reply with one short sentence.", prompt: "Say hello to 11am.", weight: .quick)
        var text = ""
        do {
            for try await chunk in provider.stream(request) {
                if case .delta(let piece) = chunk { text += piece }
            }
            return text.isEmpty ? "Connected." : "Connected: \(text)"
        } catch {
            return error.localizedDescription
        }
    }
}
