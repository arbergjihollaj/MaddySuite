//
//  CloudLLMClient.swift
//  MaddyV2
//
//  Created by Arber on 03.03.26.
//

import Foundation

// =====================================================
// MARK: - CloudLLMClient
// [TAG: V2_AI_CLOUD_CLIENT]
// =====================================================

final class CloudLLMClient {
    private let jsonDecoder = JSONDecoder()
    private let jsonEncoder = JSONEncoder()

    func testConnection(settings: AISettingsModel, apiKey: String) async throws -> AIConnectionTestResult {
        guard settings.cloudEnabled else {
            throw AIError.cloudNotConfigured
        }

        let baseURL = try resolveBaseURL(settings.cloudBaseURL)
        let url = endpoint(baseURL: baseURL, path: "v1/models")

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = max(4, settings.cloudTimeout)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await data(for: request)
        try validate(response: response, data: data)

        let decoded = try jsonDecoder.decode(OpenAIModelsResponse.self, from: data)
        let models = decoded.data.map(\.id)

        let message = models.isEmpty
            ? "Cloud endpoint reachable, no models listed."
            : "Cloud connected: \(models.prefix(4).joined(separator: ", "))"

        return AIConnectionTestResult(success: true, message: message, models: models)
    }

    func send(request input: AIChatRequest, settings: AISettingsModel, apiKey: String) async throws -> AIChatResponse {
        guard settings.cloudEnabled else {
            throw AIError.cloudNotConfigured
        }

        let baseURL = try resolveBaseURL(settings.cloudBaseURL)
        let url = endpoint(baseURL: baseURL, path: "v1/chat/completions")

        let payload = OpenAIChatRequest(
            model: input.model,
            messages: input.messages.map { .init(role: $0.role.rawValue, content: $0.content) },
            temperature: input.temperature,
            maxTokens: input.maxTokens,
            stream: false
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = max(8, settings.cloudTimeout)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try jsonEncoder.encode(payload)

        let (data, response) = try await data(for: request)
        try validate(response: response, data: data)

        let decoded = try jsonDecoder.decode(OpenAIChatResponse.self, from: data)
        guard let content = decoded.choices.first?.message.content,
              content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            throw AIError.invalidResponse
        }

        return AIChatResponse(text: content, model: decoded.model ?? input.model)
    }

    // =====================================================
    // MARK: - Helpers
    // =====================================================

    private func resolveBaseURL(_ raw: String) throws -> URL {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false, let url = URL(string: trimmed) else {
            throw AIError.invalidURL(raw)
        }
        return url
    }

    private func endpoint(baseURL: URL, path: String) -> URL {
        let normalizedPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let currentPath = baseURL.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        if currentPath.lowercased().hasSuffix(normalizedPath.lowercased()) {
            return baseURL
        }

        return normalizedPath
            .split(separator: "/")
            .reduce(baseURL) { partial, segment in
                partial.appendingPathComponent(String(segment))
            }
    }

    private func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await URLSession.shared.data(for: request)
        } catch {
            throw AIError.mapTransport(error)
        }
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw AIError.invalidResponse
        }

        guard (200...299).contains(http.statusCode) else {
            throw AIError.server(statusCode: http.statusCode, message: decodeServerMessage(data))
        }
    }

    private func decodeServerMessage(_ data: Data) -> String {
        if let envelope = try? jsonDecoder.decode(ServerErrorEnvelope.self, from: data) {
            if let message = envelope.error?.message, message.isEmpty == false {
                return message
            }
            if let detail = envelope.error?.detail, detail.isEmpty == false {
                return detail
            }
        }

        if let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
           text.isEmpty == false {
            return text
        }

        return ""
    }
}

// =====================================================
// MARK: - Decoding
// [TAG: V2_AI_CLOUD_CLIENT_MODELS]
// =====================================================

private struct OpenAIModelsResponse: Decodable {
    struct Item: Decodable {
        let id: String
    }

    let data: [Item]
}

private struct OpenAIChatRequest: Encodable {
    struct Message: Encodable {
        let role: String
        let content: String
    }

    let model: String
    let messages: [Message]
    let temperature: Double
    let maxTokens: Int
    let stream: Bool

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case temperature
        case maxTokens = "max_tokens"
        case stream
    }
}

private struct OpenAIChatResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            let role: String?
            let content: String
        }

        let message: Message
    }

    let model: String?
    let choices: [Choice]
}

private struct ServerErrorEnvelope: Decodable {
    struct ErrorInfo: Decodable {
        let message: String?
        let detail: String?
    }

    let error: ErrorInfo?
}
