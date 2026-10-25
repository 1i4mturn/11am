import Foundation

/// Any local model server that speaks the OpenAI-style chat API on localhost:
/// Ollama (http://localhost:11434/v1) or LM Studio (http://localhost:1234/v1).
/// Optional: on an 8 GB Mac, Apple's on-device model is usually the better choice.
struct LocalServerProvider: BrainProvider {
    let kind = ProviderKind.localServer
    let baseURL: String
    let model: String

    var label: String { "Local · \(model)" }

    func isReachable() async -> Bool {
        guard let url = URL(string: baseURL + "/models") else { return false }
        var request = URLRequest(url: url)
        request.timeoutInterval = 1.5
        guard let result = try? await URLSession.shared.data(for: request),
              let http = result.1 as? HTTPURLResponse else { return false }
        return http.statusCode == 200
    }

    func stream(_ request: BrainRequest) -> AsyncThrowingStream<BrainChunk, Error> {
        let baseURL = self.baseURL
        let model = self.model
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard let url = URL(string: baseURL + "/chat/completions") else { throw BrainError.badResponse }
                    var urlRequest = URLRequest(url: url)
                    urlRequest.httpMethod = "POST"
                    urlRequest.timeoutInterval = 300
                    urlRequest.setValue("application/json", forHTTPHeaderField: "content-type")
                    let body: [String: Any] = [
                        "model": model,
                        "stream": false,
                        "messages": [
                            ["role": "system", "content": request.system],
                            ["role": "user", "content": request.prompt],
                        ],
                    ]
                    urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)
                    let (data, _) = try await URLSession.shared.data(for: urlRequest)
                    guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                          let choices = object["choices"] as? [[String: Any]],
                          let message = choices.first?["message"] as? [String: Any],
                          let content = message["content"] as? String else {
                        throw BrainError.badResponse
                    }
                    continuation.yield(.model(model))
                    continuation.yield(.delta(content))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
