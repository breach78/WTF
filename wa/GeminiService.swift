import Foundation

struct GeminiSuggestion: Decodable {
    let title: String
    let content: String
    let rationale: String?
}

enum GeminiServiceError: LocalizedError {
    case missingAPIKey
    case invalidURL
    case apiFailure(String)
    case blocked(String)
    case invalidResponse
    case invalidJSON
    case insufficientSuggestions

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Gemini API 키가 설정되지 않았습니다."
        case .invalidURL:
            return "Gemini 요청 URL을 만들 수 없습니다."
        case .apiFailure(let message):
            return message
        case .blocked(let reason):
            return "요청이 차단되었습니다. \(reason)"
        case .invalidResponse:
            return "Gemini 응답 형식을 읽을 수 없습니다."
        case .invalidJSON:
            return "Gemini가 JSON 형식으로 응답하지 않았습니다."
        case .insufficientSuggestions:
            return "충분한 제안(5개)을 받지 못했습니다."
        }
    }
}

struct GeminiService {
    private static let defaultModelID = "gemini-3-pro-preview"
    private static let apiVersions = ["v1", "v1beta"]

    static func generateSuggestions(
        prompt: String,
        model: String,
        apiKey: String
    ) async throws -> [GeminiSuggestion] {
        let text = try await generateRawText(
            prompt: prompt,
            model: model,
            apiKey: apiKey,
            responseMimeType: "application/json",
            temperature: 0.9,
            topP: 0.95
        )

        let suggestions = try decodeSuggestions(from: text)
        guard suggestions.count >= 5 else {
            throw GeminiServiceError.insufficientSuggestions
        }
        return Array(suggestions.prefix(5))
    }

    static func generateText(
        prompt: String,
        model: String,
        apiKey: String
    ) async throws -> String {
        let text = try await generateRawText(
            prompt: prompt,
            model: model,
            apiKey: apiKey,
            responseMimeType: "text/plain",
            temperature: 0.7,
            topP: 0.9
        )
        let cleaned = stripCodeFence(from: text).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            throw GeminiServiceError.invalidResponse
        }
        return cleaned
    }

    private static func generateRawText(
        prompt: String,
        model: String,
        apiKey: String,
        responseMimeType: String,
        temperature: Double,
        topP: Double
    ) async throws -> String {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            throw GeminiServiceError.missingAPIKey
        }

        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedModel = normalizeModelID(trimmedModel.isEmpty ? defaultModelID : trimmedModel)

        var lastError: Error?

        for (index, version) in apiVersions.enumerated() {
            do {
                let (data, response) = try await performGenerateContentRequest(
                    prompt: prompt,
                    model: resolvedModel,
                    apiKey: trimmedKey,
                    apiVersion: version,
                    responseMimeType: responseMimeType,
                    temperature: temperature,
                    topP: topP
                )

                if !(200...299).contains(response.statusCode) {
                    let message = parseAPIErrorMessage(from: data)
                    if shouldRetryWithNextVersion(
                        statusCode: response.statusCode,
                        message: message,
                        attemptIndex: index,
                        totalAttempts: apiVersions.count
                    ) {
                        continue
                    }
                    throw GeminiServiceError.apiFailure(
                        buildAPIErrorMessage(statusCode: response.statusCode, message: message)
                    )
                }

                let decoded = try JSONDecoder().decode(GeminiGenerateResponse.self, from: data)
                if let blockReason = decoded.promptFeedback?.blockReason,
                   !blockReason.isEmpty {
                    throw GeminiServiceError.blocked(blockReason)
                }

                let text = decoded.candidates?
                    .first?
                    .content?
                    .parts?
                    .compactMap { $0.text }
                    .joined(separator: "\n")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard let text, !text.isEmpty else {
                    throw GeminiServiceError.invalidResponse
                }
                return text
            } catch {
                lastError = error
            }
        }

        throw lastError ?? GeminiServiceError.invalidResponse
    }

    private static func performGenerateContentRequest(
        prompt: String,
        model: String,
        apiKey: String,
        apiVersion: String,
        responseMimeType: String,
        temperature: Double,
        topP: Double
    ) async throws -> (Data, HTTPURLResponse) {
        guard let encodedModel = model.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            throw GeminiServiceError.invalidURL
        }
        var components = URLComponents(
            string: "https://generativelanguage.googleapis.com/\(apiVersion)/models/\(encodedModel):generateContent"
        )
        components?.queryItems = [
            URLQueryItem(name: "key", value: apiKey)
        ]
        guard let url = components?.url else {
            throw GeminiServiceError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 70
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = GeminiGenerateRequest(
            contents: [
                GeminiRequestContent(
                    role: "user",
                    parts: [GeminiRequestPart(text: prompt)]
                )
            ],
            generationConfig: GeminiGenerationConfig(
                temperature: temperature,
                topP: topP,
                responseMimeType: responseMimeType
            )
        )
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GeminiServiceError.invalidResponse
        }
        return (data, httpResponse)
    }

    private static func normalizeModelID(_ raw: String) -> String {
        let lowered = raw.lowercased()
        switch lowered {
        case "gemini-3-pro", "gemini-3.0-pro", "gemini-3-pro-latest":
            return "gemini-3-pro-preview"
        case "gemini-3-flash-latest":
            return "gemini-3-flash"
        default:
            return raw
        }
    }

    private static func shouldRetryWithNextVersion(
        statusCode: Int,
        message: String,
        attemptIndex: Int,
        totalAttempts: Int
    ) -> Bool {
        guard attemptIndex < totalAttempts - 1 else { return false }
        if statusCode == 404 {
            if message.localizedCaseInsensitiveContains("not found") { return true }
            if message.localizedCaseInsensitiveContains("not supported") { return true }
            return true
        }
        if statusCode == 400,
           message.localizedCaseInsensitiveContains("unsupported") {
            return true
        }
        if message.localizedCaseInsensitiveContains("api version") {
            return true
        }
        return false
    }

    private static func buildAPIErrorMessage(statusCode: Int, message: String) -> String {
        if statusCode == 404 {
            return "Gemini API 오류 (404): \(message) 설정에서 다른 모델을 선택해 보세요."
        }
        return "Gemini API 오류 (\(statusCode)): \(message)"
    }

    private static func parseAPIErrorMessage(from data: Data) -> String {
        if let envelope = try? JSONDecoder().decode(GeminiAPIErrorEnvelope.self, from: data),
           let message = envelope.error?.message,
           !message.isEmpty {
            return message
        }
        if let raw = String(data: data, encoding: .utf8), !raw.isEmpty {
            return raw
        }
        return "알 수 없는 오류"
    }

    private static func decodeSuggestions(from rawText: String) throws -> [GeminiSuggestion] {
        let cleaned = stripCodeFence(from: rawText)
        if let envelope: GeminiSuggestionEnvelope = decodeJSON(from: cleaned) {
            return normalizeSuggestions(envelope.suggestions)
        }
        if let directArray: [GeminiSuggestion] = decodeJSON(from: cleaned) {
            return normalizeSuggestions(directArray)
        }
        if let objectJSON = extractFirstJSONObject(from: cleaned),
           let envelope: GeminiSuggestionEnvelope = decodeJSON(from: objectJSON) {
            return normalizeSuggestions(envelope.suggestions)
        }
        if let arrayJSON = extractFirstJSONArray(from: cleaned),
           let directArray: [GeminiSuggestion] = decodeJSON(from: arrayJSON) {
            return normalizeSuggestions(directArray)
        }
        throw GeminiServiceError.invalidJSON
    }

    private static func decodeJSON<T: Decodable>(from text: String) -> T? {
        guard let data = text.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private static func normalizeSuggestions(_ suggestions: [GeminiSuggestion]) -> [GeminiSuggestion] {
        suggestions.enumerated().compactMap { index, item in
            let title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let content = item.content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !content.isEmpty else { return nil }
            let fallbackTitle = "제안 \(index + 1)"
            let normalizedTitle = title.isEmpty ? fallbackTitle : title
            let rationale = item.rationale?.trimmingCharacters(in: .whitespacesAndNewlines)
            return GeminiSuggestion(title: normalizedTitle, content: content, rationale: rationale)
        }
    }

    private static func stripCodeFence(from text: String) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if result.hasPrefix("```") {
            if let firstNewline = result.firstIndex(of: "\n") {
                result = String(result[result.index(after: firstNewline)...])
            }
            if let closingRange = result.range(of: "```", options: .backwards) {
                result.removeSubrange(closingRange.lowerBound..<result.endIndex)
            }
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func extractFirstJSONObject(from text: String) -> String? {
        guard let start = text.firstIndex(of: "{"),
              let end = text.lastIndex(of: "}") else {
            return nil
        }
        return String(text[start...end])
    }

    private static func extractFirstJSONArray(from text: String) -> String? {
        guard let start = text.firstIndex(of: "["),
              let end = text.lastIndex(of: "]") else {
            return nil
        }
        return String(text[start...end])
    }
}

private struct GeminiGenerateRequest: Encodable {
    let contents: [GeminiRequestContent]
    let generationConfig: GeminiGenerationConfig
}

private struct GeminiRequestContent: Encodable {
    let role: String
    let parts: [GeminiRequestPart]
}

private struct GeminiRequestPart: Encodable {
    let text: String
}

private struct GeminiGenerationConfig: Encodable {
    let temperature: Double
    let topP: Double
    let responseMimeType: String
}

private struct GeminiGenerateResponse: Decodable {
    let candidates: [GeminiCandidate]?
    let promptFeedback: GeminiPromptFeedback?
}

private struct GeminiCandidate: Decodable {
    let content: GeminiCandidateContent?
}

private struct GeminiCandidateContent: Decodable {
    let parts: [GeminiCandidatePart]?
}

private struct GeminiCandidatePart: Decodable {
    let text: String?
}

private struct GeminiPromptFeedback: Decodable {
    let blockReason: String?
}

private struct GeminiSuggestionEnvelope: Decodable {
    let suggestions: [GeminiSuggestion]
}

private struct GeminiAPIErrorEnvelope: Decodable {
    let error: GeminiAPIErrorPayload?
}

private struct GeminiAPIErrorPayload: Decodable {
    let message: String?
}
