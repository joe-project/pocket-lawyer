import Foundation

// MARK: - Models

/// An anonymized case brief suitable for sharing with attorneys or funders. Generated only after the user has opted in to sharing.
struct AnonymizedCaseBrief: Identifiable {
    let id: UUID
    let caseId: UUID
    /// Anonymized summary text (no names, addresses, or other PII).
    let anonymizedSummary: String
    let createdAt: Date

    init(id: UUID = UUID(), caseId: UUID, anonymizedSummary: String, createdAt: Date = Date()) {
        self.id = id
        self.caseId = caseId
        self.anonymizedSummary = anonymizedSummary
        self.createdAt = createdAt
    }
}

/// Source of interest in the case (attorney or funder).
enum InterestSource: String, Codable, CaseIterable {
    case attorney
    case funder
}

/// Interest expressed by an attorney or funder in a case shared via the marketplace.
struct MarketplaceInterest: Identifiable {
    let id: UUID
    let caseId: UUID
    let source: InterestSource
    /// Short message or summary of interest (e.g. "We may be able to assist with litigation funding.").
    let message: String
    let receivedAt: Date
    /// Whether the user has requested contact for this interest.
    var contactRequested: Bool

    init(id: UUID = UUID(), caseId: UUID, source: InterestSource, message: String, receivedAt: Date = Date(), contactRequested: Bool = false) {
        self.id = id
        self.caseId = caseId
        self.source = source
        self.message = message
        self.receivedAt = receivedAt
        self.contactRequested = contactRequested
    }
}

/// User’s request to be contacted regarding a specific interest. Created only after opt-in.
struct ContactRequest: Identifiable {
    let id: UUID
    let caseId: UUID
    let interestId: UUID
    let requestedAt: Date

    init(id: UUID = UUID(), caseId: UUID, interestId: UUID, requestedAt: Date = Date()) {
        self.id = id
        self.caseId = caseId
        self.interestId = interestId
        self.requestedAt = requestedAt
    }
}

// MARK: - Marketplace

/// Allows users to optionally share anonymized case summaries with attorneys or funders. Users must explicitly opt-in before any case information is shared. Generates anonymized briefs, surfaces interest from attorneys/funders, and lets the user request contact.
final class SettlementMarketplace {

    private let optInKeyPrefix = "SettlementMarketplace.optIn."
    private var interestsByCase: [UUID: [MarketplaceInterest]] = [:]
    private var contactRequests: [ContactRequest] = []
    private let queue = DispatchQueue(label: "SettlementMarketplace", qos: .userInitiated)

    // MARK: - Opt-in (required before sharing)

    /// Records that the user has opted in to sharing this case’s anonymized information with attorneys or funders.
    func optInForSharing(caseId: UUID) {
        UserDefaults.standard.set(true, forKey: optInKeyPrefix + caseId.uuidString)
    }

    /// Records that the user has opted out of sharing for this case.
    func optOutFromSharing(caseId: UUID) {
        UserDefaults.standard.removeObject(forKey: optInKeyPrefix + caseId.uuidString)
    }

    /// Returns whether the user has explicitly opted in to sharing this case.
    func hasOptedIn(caseId: UUID) -> Bool {
        UserDefaults.standard.bool(forKey: optInKeyPrefix + caseId.uuidString)
    }

    // MARK: - Anonymized brief

    /// Generates an anonymized case brief for sharing. Returns nil if the user has not opted in for this case.
    func generateAnonymizedBrief(caseId: UUID, caseAnalysis: CaseAnalysis) -> AnonymizedCaseBrief? {
        guard hasOptedIn(caseId: caseId) else { return nil }
        let text = buildAnonymizedBriefText(caseAnalysis)
        return AnonymizedCaseBrief(caseId: caseId, anonymizedSummary: text)
    }

    /// Builds anonymized brief text from case analysis (no PII). In production, run additional redaction for names, addresses, etc.
    private func buildAnonymizedBriefText(_ analysis: CaseAnalysis) -> String {
        var parts: [String] = []
        if !analysis.summary.isEmpty {
            parts.append("Summary: \(redactPII(analysis.summary))")
        }
        if !analysis.claims.isEmpty {
            parts.append("Potential claims: \(analysis.claims.map { redactPII($0) }.joined(separator: "; "))")
        }
        if !analysis.estimatedDamages.isEmpty {
            parts.append("Estimated damages: \(analysis.estimatedDamages)")
        }
        if !analysis.nextSteps.isEmpty {
            parts.append("Next steps: \(analysis.nextSteps.prefix(5).map { redactPII($0) }.joined(separator: "; "))")
        }
        if !analysis.filingLocations.isEmpty {
            parts.append("Filing locations: \(analysis.filingLocations.joined(separator: ", "))")
        }
        return parts.isEmpty ? "Case summary (anonymized)." : parts.joined(separator: "\n\n")
    }

    /// Placeholder PII redaction: replace common patterns. Replace with full NER/redaction in production.
    private func redactPII(_ text: String) -> String {
        var result = text
        // Simple placeholder: redact email-like and phone-like substrings
        if let emailRegex = try? NSRegularExpression(pattern: "[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}") {
            result = emailRegex.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: "[redacted]")
        }
        if let phoneRegex = try? NSRegularExpression(pattern: "\\b\\d{3}[-.]?\\d{3}[-.]?\\d{4}\\b") {
            result = phoneRegex.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: "[redacted]")
        }
        return result
    }

    // MARK: - Interest and contact

    /// Returns interest from attorneys or funders for this case. Only populated after opt-in and when interest exists (e.g. from backend).
    func interests(for caseId: UUID) -> [MarketplaceInterest] {
        queue.sync { interestsByCase[caseId] ?? [] }
    }

    /// Adds a placeholder interest (e.g. for demo or backend webhook). In production, replace with API-driven updates.
    func addInterest(_ interest: MarketplaceInterest) {
        queue.async { [weak self] in
            guard let self = self else { return }
            var list = self.interestsByCase[interest.caseId] ?? []
            list.append(interest)
            self.interestsByCase[interest.caseId] = list
        }
    }

    /// User requests contact for a specific interest. Succeeds only if the user has opted in for this case.
    func requestContact(caseId: UUID, interestId: UUID) -> ContactRequest? {
        guard hasOptedIn(caseId: caseId) else { return nil }
        let request = ContactRequest(caseId: caseId, interestId: interestId)
        queue.async { [weak self] in
            guard let self = self else { return }
            self.contactRequests.append(request)
            guard var list = self.interestsByCase[caseId],
                  let idx = list.firstIndex(where: { $0.id == interestId }) else { return }
            list[idx] = MarketplaceInterest(
                id: list[idx].id,
                caseId: list[idx].caseId,
                source: list[idx].source,
                message: list[idx].message,
                receivedAt: list[idx].receivedAt,
                contactRequested: true
            )
            self.interestsByCase[caseId] = list
        }
        return request
    }

    /// Returns contact requests for the case (e.g. for display in UI).
    func contactRequests(for caseId: UUID) -> [ContactRequest] {
        queue.sync { contactRequests.filter { $0.caseId == caseId } }
    }
}
