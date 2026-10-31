import Foundation

/// Polish or translate a piece of text. Translation also polishes.
enum RewriteMode {
    case polish
    case translate(TranslateLanguage)
}

enum RewriteError: LocalizedError {
    case missingKey
    case tooLong
    case noChange
    case http(Int, String)
    case badResponse

    var errorDescription: String? {
        switch self {
        case .missingKey: L.needKey
        case .tooLong: L.tooLong
        case .noChange: L.noChange
        case .http(let code, let body):
            code == 400 || code == 401 || code == 403 ? L.keyRejected : L.requestFailed(code, body)
        case .badResponse: L.badResponse
        }
    }
}

/// Talks to Gemini's or DeepSeek's OpenAI-compatible endpoint, with the same prompts and JSON
/// contract as ZnKeyboard for Android.
struct AIClient {
    static let maxSourceCharacters = 5_000

    let provider: Provider
    let apiKey: String
    let model: String

    private var baseURL: URL { provider.baseURL }

    func rewrite(_ text: String, mode: RewriteMode) async throws -> String {
        guard !apiKey.isEmpty else { throw RewriteError.missingKey }
        guard text.count <= Self.maxSourceCharacters else { throw RewriteError.tooLong }
        do {
            return try await request(text, mode: mode, strictSchema: true)
        } catch RewriteError.http(let code, let body) where [400, 404, 422].contains(code) && Self.mentionsSchema(body) {
            // DeepSeek only takes plain JSON mode.
            return try await request(text, mode: mode, strictSchema: false)
        }
    }

    private func request(_ text: String, mode: RewriteMode, strictSchema: Bool) async throws -> String {
        let format: [String: Any] = strictSchema ? [
            "type": "json_schema",
            "json_schema": [
                "name": "znkeyboard_rewrite_response",
                "strict": true,
                "schema": [
                    "type": "object",
                    "additionalProperties": false,
                    "properties": [
                        "text": [
                            "type": "string",
                            "description": "The final rewritten text only, without labels, explanations, or prefaces.",
                        ],
                    ],
                    "required": ["text"],
                ],
            ],
        ] : ["type": "json_object"]
        var body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": Prompts.system(for: mode)],
                ["role": "user", "content": text],
            ],
            "temperature": 0.4,
            "max_tokens": Self.maxTokens(for: text),
            "response_format": format,
        ]
        // DeepSeek thinks by default, which only slows a rewrite down.
        if provider == .deepseek { body["thinking"] = ["type": "disabled"] }

        var request = URLRequest(url: baseURL.appendingPathComponent("chat/completions"))
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw RewriteError.http(status, String(decoding: data.prefix(300), as: UTF8.self))
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choice = (json["choices"] as? [[String: Any]])?.first else { throw RewriteError.badResponse }
        // A cut-off answer is half a JSON object; say why instead of reporting a parse error.
        if choice["finish_reason"] as? String == "length" { throw RewriteError.tooLong }
        guard let content = (choice["message"] as? [String: Any])?["content"] as? String,
              let payload = try? JSONSerialization.jsonObject(with: Data(Self.stripFences(content).utf8)) as? [String: Any],
              let result = (payload["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !result.isEmpty else { throw RewriteError.badResponse }
        if result == text.trimmingCharacters(in: .whitespacesAndNewlines) { throw RewriteError.noChange }
        return result
    }

    private static func mentionsSchema(_ body: String) -> Bool {
        let lower = body.lowercased()
        return ["response_format", "json_schema", "schema"].contains { lower.contains($0) }
    }

    /// Models this key can use: Flash-Lite only for Gemini, everything DeepSeek lists. Loading them
    /// also checks the key.
    func models() async throws -> [String] {
        guard !apiKey.isEmpty else { throw RewriteError.missingKey }
        var request = URLRequest(url: baseURL.appendingPathComponent("models"))
        request.timeoutInterval = 15
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw RewriteError.http(status, String(decoding: data.prefix(300), as: UTF8.self))
        }
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let ids = (json?["data"] as? [[String: Any]])?.compactMap { $0["id"] as? String } ?? []
        return provider == .gemini ? GeminiModels.liteModels(from: ids) : Array(Set(ids)).sorted()
    }

    /// A CJK character can cost a whole token while Latin text packs about three characters per
    /// token; translation can lengthen text, hence the margin. Same budget as on Android.
    static func maxTokens(for text: String) -> Int {
        let cjk = text.unicodeScalars.filter { $0.value >= 0x2E80 }.count
        let estimate = cjk + (text.unicodeScalars.count - cjk) / 3
        return min(max(estimate * 3 / 2 + 200, 2_000), 8_000)
    }

    /// Some models wrap JSON in ``` fences despite the schema.
    private static func stripFences(_ content: String) -> String {
        var text = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("```") {
            text = String(text.drop { $0 != "\n" }.dropFirst())
            if text.hasSuffix("```") { text = String(text.dropLast(3)) }
        }
        return text
    }
}

/// System prompts shipped in the app bundle, copied from ZnKeyboard for Android.
enum Prompts {
    static func system(for mode: RewriteMode) -> String {
        var parts = [load("rewrite_base") ?? fallback]
        if case .translate(let language) = mode, let translate = load("translate") {
            // Last, so it overrides the language-matching rules above.
            parts.append(translate.replacingOccurrences(of: "{language}", with: language.name))
        }
        return parts.joined(separator: "\n\n---\n\n")
    }

    private static func load(_ name: String) -> String? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "md", subdirectory: "prompts") else { return nil }
        return try? String(contentsOf: url, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static let fallback = """
        Polish the user's text while preserving its meaning, tone, and language. \
        Return a valid JSON object with exactly one field, `text`, containing only the rewritten text.
        """
}
