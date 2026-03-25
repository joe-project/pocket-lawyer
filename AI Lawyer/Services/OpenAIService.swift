import Foundation

/// Cloudflare Worker proxy URL. Replace with your Worker URL (e.g. https://your-worker.workers.dev).
/// The OpenAI API key is stored only on the Worker; never in the client.
private let workerBaseURL = "https://ai-lawyer-server.ailawyer.workers.dev"

/// System prompt so the AI acts as a legal case intake assistant.
private let legalCaseIntakeSystemPrompt = """
You are a legal case intake assistant. When the user describes a story or incident, you must:

1. Identify the possible legal claim(s).
2. Estimate potential damages if appropriate.
3. Extract timeline events (key dates and sequence).
4. Identify evidence needed.
5. Suggest next legal steps.
6. Identify relevant courts or agencies.
7. Suggest legal documents that may need to be prepared.

Structure your response using exactly these section headers (all caps, on their own line). Under each header, provide the relevant content. Use bullet points or numbered lists where helpful.

CASE SUMMARY
[Brief overview of the situation and what the user described.]

POTENTIAL CLAIMS
[One or more possible legal claims, e.g. wrongful eviction, breach of contract, negligence, discrimination.]

ESTIMATED DAMAGES
[Range when applicable, e.g. $300k – $500k, or "N/A" / "To be assessed" if not applicable.]

EVIDENCE NEEDED
[List documents, witnesses, photos, records, or other evidence the user should gather.]

TIMELINE OF EVENTS
[Key dates and sequence of events. Use bullet points or numbered lines; include dates when known (e.g. "Jan 15 – Incident occurred").]

NEXT STEPS
[Concrete legal steps, e.g. 1. Preserve evidence 2. Send demand letter 3. File complaint 4. Consult an attorney.]

DOCUMENTS TO PREPARE
[Forms, complaints, motions, or other documents that may be required.]

WHERE TO FILE
[Relevant courts, agencies (e.g. EEOC, state AG, small claims), or venues to file with.]

Keep responses clear, structured, and actionable. Do not provide legal advice; recommend consulting a licensed attorney for advice specific to their case. If the user's message is too vague, ask clarifying questions before providing the structured response.
"""

struct OpenAIService {
    /// Send chat to the Cloudflare Worker proxy with optional conversation context; returns (assistant text, whether response offers to generate a document, parsed timeline events).
    /// Uses workerBaseURL only; no API key is sent from the client.
    func sendChat(messages: [ChatMessage], previousMessages: [Message]? = nil) async throws -> (String, Bool, [CaseTimelineEvent]) {
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
        request.timeoutInterval = 30
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await performRequest(request, label: "sendChat")

        guard let http = response as? HTTPURLResponse else {
            throw WorkerError.invalidResponse
        }

        if http.statusCode != 200 {
            let errorMessage = (try? JSONDecoder().decode(WorkerErrorResponse.self, from: data))?.error ?? String(data: data, encoding: .utf8) ?? "Unknown error"
            throw WorkerError.serverError(statusCode: http.statusCode, message: errorMessage)
        }

        let raw = try parseAssistantContent(from: data)
        let content = LegalGuardrails.applyGuardrails(to: raw)
        let offerDocument = content.lowercased().contains("generate that document") || content.lowercased().contains("want me to generate")
        let timelineEvents = Self.parseTimelineEvents(from: content)
        return (content, offerDocument, timelineEvents)
    }

    /// Sends a single user message with a custom system prompt (e.g. for evidence analysis). Returns the raw assistant response text. Use for tasks that expect a specific format (e.g. JSON).
    func sendWithCustomPrompt(systemPrompt: String, userMessage: String) async throws -> String {
        if workerBaseURL.contains("YOUR_WORKER") {
            throw WorkerError.serverError(statusCode: 0, message: "Set your Cloudflare Worker URL in OpenAIService.swift (workerBaseURL).")
        }
        let body = WorkerRequest(
            systemPrompt: systemPrompt,
            context: [],
            messages: [WorkerMessage(role: "user", content: userMessage)]
        )
        guard let url = URL(string: workerBaseURL) else {
            throw WorkerError.serverError(statusCode: 0, message: "Invalid Worker URL.")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await performRequest(request, label: "sendWithCustomPrompt")

        guard let http = response as? HTTPURLResponse else {
            throw WorkerError.invalidResponse
        }

        if http.statusCode != 200 {
            let errorMessage = (try? JSONDecoder().decode(WorkerErrorResponse.self, from: data))?.error ?? String(data: data, encoding: .utf8) ?? "Unknown error"
            throw WorkerError.serverError(statusCode: http.statusCode, message: errorMessage)
        }

        let raw = try parseAssistantContent(from: data)
        return LegalGuardrails.applyGuardrails(to: raw)
    }

    /// Parses the "TIMELINE OF EVENTS" section from an AI response into CaseTimelineEvent objects (e.g. "Jan 3 – landlord threatened eviction").
    static func parseTimelineEvents(from response: String) -> [CaseTimelineEvent] {
        let markers = ["TIMELINE OF EVENTS", "**timeline of events**", "timeline of events", "• **timeline of events**"]
        guard let range = markers.lazy.compactMap({ response.range(of: $0, options: .caseInsensitive) }).first else {
            return []
        }
        let afterMarker = String(response[range.upperBound...])
        let sectionEndMarkers = ["NEXT STEPS", "**recommended", "**evidence", "**case summary", "**legal forms", "**agencies", "• **", "DOCUMENTS TO PREPARE", "WHERE TO FILE"]
        var endIndex = afterMarker.endIndex
        for endMarker in sectionEndMarkers {
            if let endRange = afterMarker.range(of: endMarker, options: .caseInsensitive), endRange.lowerBound < endIndex {
                endIndex = endRange.lowerBound
            }
        }
        let sectionText = String(afterMarker[..<endIndex])
        return CaseAnalysisParser.parseTimelineLines(sectionText)
    }

    private func buildRequestBody(messages: [ChatMessage], previousMessages: [Message]) -> WorkerRequest {
        let context: [WorkerMessage] = previousMessages.map { WorkerMessage(role: $0.role, content: $0.content) }
        let newMessages: [WorkerMessage] = messages.map { msg in
            let role = msg.sender == .user ? "user" : "assistant"
            return WorkerMessage(role: role, content: msg.text)
        }
        return WorkerRequest(systemPrompt: legalCaseIntakeSystemPrompt, context: context, messages: newMessages)
    }

    private func performRequest(_ request: URLRequest, label: String) async throws -> (Data, URLResponse) {
        logRequest(request, label: label)
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            logResponse(data: data, response: response, label: label)
            return (data, response)
        } catch {
            logError(error, request: request, label: label)
            throw error
        }
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

    private func logRequest(_ request: URLRequest, label: String) {
        let bodyText: String
        if let body = request.httpBody, let string = String(data: body, encoding: .utf8) {
            bodyText = string
        } else {
            bodyText = "<empty>"
        }

        print("🌐 [OpenAIService:\(label)] Request URL: \(request.url?.absoluteString ?? "<nil>")")
        print("🌐 [OpenAIService:\(label)] Timeout: \(request.timeoutInterval)s")
        print("🌐 [OpenAIService:\(label)] Request Body: \(bodyText)")
    }

    private func logResponse(data: Data, response: URLResponse, label: String) {
        let rawText = String(data: data, encoding: .utf8) ?? "<non-utf8 \(data.count) bytes>"
        if let http = response as? HTTPURLResponse {
            print("🌐 [OpenAIService:\(label)] Response Status: \(http.statusCode)")
        } else {
            print("🌐 [OpenAIService:\(label)] Response Status: <non-http>")
        }
        print("🌐 [OpenAIService:\(label)] Raw Response: \(rawText)")
    }

    private func logError(_ error: Error, request: URLRequest, label: String) {
        print("❌ [OpenAIService:\(label)] Request Failed: \(error.localizedDescription)")
        print("❌ [OpenAIService:\(label)] URL: \(request.url?.absoluteString ?? "<nil>")")
    }
}

// MARK: - Request/response DTOs (no API key; Worker holds the key)

private struct WorkerRequest: Encodable {
    let systemPrompt: String
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
