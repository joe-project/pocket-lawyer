import Foundation

/// Cloudflare Worker proxy URL. Replace with your Worker URL (e.g. https://your-worker.workers.dev).
/// The OpenAI API key is stored only on the Worker; never in the client.
private let workerBaseURL = "https://ai-lawyer-server.ailawyer.workers.dev"

struct OpenAIService {
    /// Send chat to the Cloudflare Worker proxy with optional conversation context; returns (assistant text, whether response offers to generate a document).
    /// Uses workerBaseURL only; no API key is sent from the client.
    func sendChat(messages: [ChatMessage], previousMessages: [Message]? = nil) async throws -> (String, Bool) {
        if workerBaseURL.contains("YOUR_WORKER") {
            throw WorkerError.serverError(statusCode: 0, message: "Set your Cloudflare Worker URL in OpenAIService.swift (workerBaseURL).")
        }
        let body = buildRequestBody(messages: messages, previousMessages: previousMessages ?? [])
        guard let url = URL(string: workerBaseURL) else {
            throw WorkerError.serverError(statusCode: 0, message: "Invalid Worker URL.")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw WorkerError.invalidResponse
        }

        if http.statusCode != 200 {
            let errorMessage = (try? JSONDecoder().decode(WorkerErrorResponse.self, from: data))?.error ?? String(data: data, encoding: .utf8) ?? "Unknown error"
            throw WorkerError.serverError(statusCode: http.statusCode, message: errorMessage)
        }

        let content = try parseAssistantContent(from: data)
        let offerDocument = content.lowercased().contains("generate that document") || content.lowercased().contains("want me to generate")
        return (content, offerDocument)
    }

    private func buildRequestBody(messages: [ChatMessage], previousMessages: [Message]) -> WorkerRequest {
        let context: [WorkerMessage] = previousMessages.map { WorkerMessage(role: $0.role, content: $0.content) }
        let newMessages: [WorkerMessage] = messages.map { msg in
            let role = msg.sender == .user ? "user" : "assistant"
            return WorkerMessage(role: role, content: msg.text)
        }
        return WorkerRequest(context: context, messages: newMessages)
    }

    private func parseAssistantContent(from data: Data) throws -> String {
        if let openAI = try? JSONDecoder().decode(OpenAICompatibilityResponse.self, from: data),
           let content = openAI.choices?.first?.message?.content {
            return content.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let simple = try? JSONDecoder().decode(SimpleContentResponse.self, from: data), !simple.content.isEmpty {
            return simple.content.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let alt = try? JSONDecoder().decode(AltResponse.self, from: data), !alt.response.isEmpty {
            return alt.response.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        throw WorkerError.invalidResponse
    }
}

// MARK: - Request/response DTOs (no API key; Worker holds the key)

private struct WorkerRequest: Encodable {
    let context: [WorkerMessage]
    let messages: [WorkerMessage]
}

private struct WorkerMessage: Encodable {
    let role: String
    let content: String
}

private struct OpenAICompatibilityResponse: Decodable {
    let choices: [Choice]?
    struct Choice: Decodable {
        let message: Message?
        struct Message: Decodable {
            let content: String?
        }
    }
}

private struct SimpleContentResponse: Decodable {
    let content: String
}

private struct AltResponse: Decodable {
    let response: String
}

private struct WorkerErrorResponse: Decodable {
    let error: String?
}

enum WorkerError: LocalizedError {
    case invalidResponse
    case serverError(statusCode: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from server."
        case .serverError(let code, let message):
            return "Server error (\(code)): \(message)"
        }
    }
}
