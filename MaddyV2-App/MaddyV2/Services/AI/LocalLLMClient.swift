//
//  LocalLLMClient.swift
//  MaddyV2
//
//  Created by Arber on 03.03.26.
//

import Foundation

// =====================================================
// MARK: - LocalLLMClient
// [TAG: V2_AI_LOCAL_CLIENT]
// =====================================================

final class LocalLLMClient {
    private let jsonDecoder = JSONDecoder()
    private let jsonEncoder = JSONEncoder()

    func testConnection(settings: AISettingsModel) async throws -> AIConnectionTestResult {
        switch settings.localProvider {
        case .ollama:
            return try await testOllama(baseURLString: settings.localBaseURL)
        case .lmStudio:
            return try await testLMStudio(baseURLString: settings.localBaseURL)
        }
    }

    func send(request: AIChatRequest, settings: AISettingsModel) async throws -> AIChatResponse {
        switch settings.localProvider {
        case .ollama:
            return try await sendToOllama(request: request, baseURLString: settings.localBaseURL)
        case .lmStudio:
            return try await sendToLMStudio(request: request, baseURLString: settings.localBaseURL)
        }
    }

    // =====================================================
    // MARK: - Ollama
    // =====================================================

    private func testOllama(baseURLString: String) async throws -> AIConnectionTestResult {
        let baseURL = try resolveBaseURL(baseURLString, fallback: "http://127.0.0.1:11434")
        let url = endpoint(baseURL: baseURL, path: "api/tags")

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 6

        let (data, response) = try await data(for: request)
        try validate(response: response, data: data)

        let decoded = try jsonDecoder.decode(OllamaTagsResponse.self, from: data)
        let models = decoded.models.map(\.name)

        let message = models.isEmpty
            ? "Local endpoint reachable (Ollama), no models listed."
            : "Local connected (Ollama): \(models.prefix(4).joined(separator: ", "))"

        return AIConnectionTestResult(success: true, message: message, models: models)
    }

    private func sendToOllama(request input: AIChatRequest, baseURLString: String) async throws -> AIChatResponse {
        let baseURL = try resolveBaseURL(baseURLString, fallback: "http://127.0.0.1:11434")
        let url = endpoint(baseURL: baseURL, path: "api/chat")

        let payload = OllamaChatRequest(
            model: input.model,
            messages: input.messages.map { .init(role: $0.role.rawValue, content: $0.content) },
            stream: false,
            options: .init(temperature: input.temperature)
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try jsonEncoder.encode(payload)

        let (data, response) = try await data(for: request)
        try validate(response: response, data: data)

        let decoded = try jsonDecoder.decode(OllamaChatResponse.self, from: data)
        let text = decoded.message?.content ?? decoded.response ?? ""

        guard text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            throw AIError.invalidResponse
        }

        return AIChatResponse(text: text, model: decoded.model ?? input.model)
    }

    // =====================================================
    // MARK: - LM Studio (OpenAI-compatible)
    // =====================================================

    private func testLMStudio(baseURLString: String) async throws -> AIConnectionTestResult {
        let baseURL = try resolveBaseURL(baseURLString, fallback: "http://127.0.0.1:1234")
        let url = endpoint(baseURL: baseURL, path: "v1/models")

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 6

        let (data, response) = try await data(for: request)
        try validate(response: response, data: data)

        let decoded = try jsonDecoder.decode(OpenAIModelsResponse.self, from: data)
        let models = decoded.data.map(\.id)

        let message = models.isEmpty
            ? "Local endpoint reachable (LM Studio), no models listed."
            : "Local connected (LM Studio): \(models.prefix(4).joined(separator: ", "))"

        return AIConnectionTestResult(success: true, message: message, models: models)
    }

    private func sendToLMStudio(request input: AIChatRequest, baseURLString: String) async throws -> AIChatResponse {
        let baseURL = try resolveBaseURL(baseURLString, fallback: "http://127.0.0.1:1234")
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
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
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

    private func resolveBaseURL(_ raw: String, fallback: String) throws -> URL {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = trimmed.isEmpty ? fallback : trimmed
        guard let url = URL(string: value) else {
            throw AIError.invalidURL(value)
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
            if let detail = envelope.error, let text = detail.detail, text.isEmpty == false {
                return text
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
// [TAG: V2_AI_LOCAL_CLIENT_MODELS]
// =====================================================

private struct OllamaTagsResponse: Decodable {
    struct Model: Decodable {
        let name: String
    }

    let models: [Model]
}

private struct OllamaChatRequest: Encodable {
    struct Message: Encodable {
        let role: String
        let content: String
    }

    struct Options: Encodable {
        let temperature: Double
    }

    let model: String
    let messages: [Message]
    let stream: Bool
    let options: Options
}

private struct OllamaChatResponse: Decodable {
    struct Message: Decodable {
        let content: String
    }

    let model: String?
    let message: Message?
    let response: String?
}

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
