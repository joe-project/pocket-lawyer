import Foundation

// MARK: - Models

/// A single legal reference from CourtListener, GovInfo, LII, or similar.
struct LegalCitation: Identifiable, Equatable {
    let id: UUID
    let source: LegalSource
    let title: String
    let snippet: String?
    let url: URL?
    /// Formal citation text when available (e.g. "123 F. Supp. 2d 456").
    let citationText: String?

    init(
        id: UUID = UUID(),
        source: LegalSource,
        title: String,
        snippet: String? = nil,
        url: URL? = nil,
        citationText: String? = nil
    ) {
        self.id = id
        self.source = source
        self.title = title
        self.snippet = snippet
        self.url = url
        self.citationText = citationText
    }
}

enum LegalSource: String, CaseIterable {
    case courtListener = "CourtListener"
    case govInfo = "GovInfo"
    case lii = "Legal Information Institute"
}

/// Result of legal research: citations and a formatted string to attach to AI context or responses.
struct LegalResearchResponse {
    let citations: [LegalCitation]
    /// Formatted text to include in prompts or append to AI responses so answers include citations where possible.
    let promptAppendix: String
}

// MARK: - Service

/// Retrieves relevant laws and case references from public online legal sources (CourtListener, GovInfo, LII) for use when analyzing a case. Detects topics from CaseAnalysis, queries sources, and returns citations and summaries that can be attached to AI responses.
final class LegalResearchService {

    private let session: URLSession
    /// Optional CourtListener API token (see https://www.courtlistener.com/help/api/rest/). If nil, requests may be rate-limited or limited.
    var courtListenerToken: String?
    /// Optional GovInfo API key (see https://api.govinfo.gov/docs/). If nil, GovInfo queries are skipped.
    var govInfoAPIKey: String?

    private static let courtListenerSearchBase = "https://www.courtlistener.com/api/rest/v4/search/"
    private static let govInfoSearchURL = "https://api.govinfo.gov/search"
    private static let liiSearchBase = "https://www.law.cornell.edu/search/site"

    init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: - Topic detection

    /// Detects relevant legal topics and search phrases from case analysis (claims, summary, filing locations, document types).
    func detectTopics(from analysis: CaseAnalysis) -> [String] {
        var topics: [String] = []
        if !analysis.summary.isEmpty {
            let trimmed = analysis.summary.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.count > 10 {
                topics.append(trimmed.count > 120 ? String(trimmed.prefix(120)) + "…" : trimmed)
            }
        }
        for claim in analysis.claims {
            let t = claim.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty, !topics.contains(t) { topics.append(t) }
        }
        for loc in analysis.filingLocations {
            let t = loc.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty, !topics.contains(t) { topics.append(t) }
        }
        for doc in analysis.documents {
            let t = doc.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty, !topics.contains(t) { topics.append(t) }
        }
        return topics.isEmpty ? ["legal claim"] : topics
    }

    // MARK: - Research entry point

    /// Runs legal research from case analysis: detects topics, queries CourtListener, GovInfo, and LII, returns citations and a formatted appendix for AI context.
    func research(analysis: CaseAnalysis) async -> LegalResearchResponse {
        let topics = detectTopics(from: analysis)
        var allCitations: [LegalCitation] = []
        let maxPerSource = 5
        let maxQueries = 3
        let queries = Array(topics.prefix(maxQueries))

        for query in queries where !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            async let cl = queryCourtListener(query: query, limit: maxPerSource)
            async let gov = queryGovInfo(query: query, limit: maxPerSource)
            let lii = queryLII(query: query, limit: maxPerSource)
            let (clResults, govResults) = await (cl, gov)
            allCitations.append(contentsOf: clResults)
            allCitations.append(contentsOf: govResults)
            allCitations.append(contentsOf: lii)
        }

        let deduped = deduplicateCitations(allCitations, limit: 15)
        let appendix = formatCitationsForPrompt(deduped)
        return LegalResearchResponse(citations: deduped, promptAppendix: appendix)
    }

    /// Returns formatted text to prepend or append to an AI prompt so the model can cite these sources. Include this in context when you want responses to reference laws and cases.
    func formatCitationsForPrompt(_ citations: [LegalCitation]) -> String {
        guard !citations.isEmpty else { return "" }
        var lines = ["--- RELEVANT LEGAL REFERENCES (cite where possible) ---"]
        for c in citations {
            var line = "[\(c.source.rawValue)] \(c.title)"
            if let snippet = c.snippet, !snippet.isEmpty {
                let short = snippet.count > 200 ? String(snippet.prefix(200)) + "…" : snippet
                line += "\n  \(short)"
            }
            if let cite = c.citationText, !cite.isEmpty { line += "\n  Citation: \(cite)" }
            if let url = c.url { line += "\n  URL: \(url.absoluteString)" }
            lines.append(line)
        }
        lines.append("")
        return lines.joined(separator: "\n")
    }

    private func deduplicateCitations(_ citations: [LegalCitation], limit: Int) -> [LegalCitation] {
        var seen = Set<String>()
        var out: [LegalCitation] = []
        for c in citations {
            let key = "\(c.source.rawValue):\(c.title)"
            if seen.contains(key) { continue }
            seen.insert(key)
            out.append(c)
            if out.count >= limit { break }
        }
        return out
    }

    // MARK: - CourtListener

    private func queryCourtListener(query: String, limit: Int) async -> [LegalCitation] {
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: Self.courtListenerSearchBase + "?q=\(encoded)&page_size=\(limit)") else {
            return []
        }
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token = courtListenerToken, !token.isEmpty {
            request.setValue("Token \(token)", forHTTPHeaderField: "Authorization")
        }
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return [] }
            return parseCourtListenerResults(data: data, limit: limit)
        } catch {
            return []
        }
    }

    private func parseCourtListenerResults(data: Data, limit: Int) -> [LegalCitation] {
        struct CLSearchResult: Decodable {
            let results: [CLHit]?
            struct CLHit: Decodable {
                let caseName: String?
                let caseNameFull: String?
                let court: String?
                let dateFiled: String?
                let absoluteUrl: String?
                let citation: [String]?
                let opinions: [CLOpinion]?
                struct CLOpinion: Decodable {
                    let snippet: String?
                }
            }
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let decoded = try? decoder.decode(CLSearchResult.self, from: data),
              let hits = decoded.results else { return [] }
        let base = "https://www.courtlistener.com"
        return hits.prefix(limit).compactMap { hit in
            let title = hit.caseNameFull ?? hit.caseName ?? "Case"
            let path = hit.absoluteUrl ?? ""
            let url = path.isEmpty ? nil : URL(string: path.hasPrefix("http") ? path : base + path)
            let snippet = hit.opinions?.first?.snippet?.trimmingCharacters(in: .whitespacesAndNewlines)
            let citationText = hit.citation?.joined(separator: "; ")
            return LegalCitation(
                source: .courtListener,
                title: title,
                snippet: snippet,
                url: url,
                citationText: citationText?.isEmpty == false ? citationText : nil
            )
        }
    }

    // MARK: - GovInfo

    private func queryGovInfo(query: String, limit: Int) async -> [LegalCitation] {
        guard let key = govInfoAPIKey, !key.isEmpty,
              let url = URL(string: Self.govInfoSearchURL) else {
            return []
        }
        let body: [String: Any] = [
            "query": query,
            "pageSize": limit,
            "offsetMark": "*",
            "sorts": [["field": "score", "sortOrder": "DESC"]]
        ]
        guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else { return [] }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(key, forHTTPHeaderField: "X-Api-Key")
        request.httpBody = bodyData
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return [] }
            return parseGovInfoResults(data: data, limit: limit)
        } catch {
            return []
        }
    }

    private func parseGovInfoResults(data: Data, limit: Int) -> [LegalCitation] {
        struct GovResult: Decodable {
            let results: [GovHit]?
            struct GovHit: Decodable {
                let title: String?
                let summary: String?
                let pdfLink: String?
                let docClass: String?
            }
        }
        guard let decoded = try? JSONDecoder().decode(GovResult.self, from: data),
              let hits = decoded.results else { return [] }
        return hits.prefix(limit).compactMap { hit in
            let title = hit.title ?? "Federal document"
            let url = (hit.pdfLink).flatMap { URL(string: $0) }
            return LegalCitation(
                source: .govInfo,
                title: title,
                snippet: hit.summary?.trimmingCharacters(in: .whitespacesAndNewlines),
                url: url,
                citationText: hit.docClass
            )
        }
    }

    // MARK: - Legal Information Institute (LII)

    /// LII does not expose a public search API; we return search links and static references so the AI can direct users to LII.
    private func queryLII(query: String, limit: Int) -> [LegalCitation] {
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let searchURL = URL(string: "\(Self.liiSearchBase)/\(encoded)") else {
            return []
        }
        var list: [LegalCitation] = []
        list.append(LegalCitation(
            source: .lii,
            title: "LII search: \(query)",
            snippet: "Search Cornell LII for statutes, regulations, and case law.",
            url: searchURL,
            citationText: nil
        ))
        return list
    }
}
