import Foundation

// MARK: - Model

/// Legal jurisdiction for a case (country, state, county). Used to scope laws and venue.
struct Jurisdiction: Codable, Equatable {
    let country: String
    let state: String?
    let county: String?

    /// Default when jurisdiction cannot be determined; use to trigger clarifying questions.
    static let unknown: Jurisdiction = Jurisdiction(country: "United States", state: nil, county: nil)

    var isDetermined: Bool {
        !country.isEmpty && (state != nil && !state!.isEmpty || country != "United States")
    }
}

/// Result of jurisdiction determination: the best-effort jurisdiction plus whether the system should ask a clarifying question.
struct JurisdictionResult {
    let jurisdiction: Jurisdiction
    /// When true, jurisdiction was inferred from messages or device; when false, the system should ask a clarifying question.
    let isDetermined: Bool
    /// Suggested question to ask the user when jurisdiction cannot be determined (e.g. "Where did the incident occur? Please provide the state or country.")
    let suggestedClarifyingQuestion: String?
}

// MARK: - Engine

/// Determines the legal jurisdiction for a case from user answers during intake, device location (if provided), and addresses or place names in messages and documents.
final class JurisdictionEngine {

    private static let suggestedQuestion = "Where did the incident occur? Please provide the state (e.g. California, NY) or country so we can tailor the analysis to the right jurisdiction."

    /// US state full name -> two-letter abbreviation (for normalization).
    private static let usStateAbbrev: [String: String] = [
        "alabama": "AL", "alaska": "AK", "arizona": "AZ", "arkansas": "AR", "california": "CA",
        "colorado": "CO", "connecticut": "CT", "delaware": "DE", "florida": "FL", "georgia": "GA",
        "hawaii": "HI", "idaho": "ID", "illinois": "IL", "indiana": "IN", "iowa": "IA",
        "kansas": "KS", "kentucky": "KY", "louisiana": "LA", "maine": "ME", "maryland": "MD",
        "massachusetts": "MA", "michigan": "MI", "minnesota": "MN", "mississippi": "MS",
        "missouri": "MO", "montana": "MT", "nebraska": "NE", "nevada": "NV", "new hampshire": "NH",
        "new jersey": "NJ", "new mexico": "NM", "new york": "NY", "north carolina": "NC",
        "north dakota": "ND", "ohio": "OH", "oklahoma": "OK", "oregon": "OR", "pennsylvania": "PA",
        "rhode island": "RI", "south carolina": "SC", "south dakota": "SD", "tennessee": "TN",
        "texas": "TX", "utah": "UT", "vermont": "VT", "virginia": "VA", "washington": "WA",
        "west virginia": "WV", "wisconsin": "WI", "wyoming": "WY", "district of columbia": "DC"
    ]

    /// Two-letter state abbreviations (for detection).
    private static let usStateCodes = Set(usStateAbbrev.values)

    // MARK: - Determine from messages only

    /// Determines jurisdiction from conversation messages (intake answers, documents, transcripts). Use when device location is not available. Returns a best-effort Jurisdiction; when nothing is found, returns a default so the system can ask clarifying questions.
    func determineJurisdiction(from messages: [Message]) -> Jurisdiction {
        let result = determineJurisdictionResult(from: messages, devicePlace: nil)
        return result.jurisdiction
    }

    // MARK: - Determine with optional device place and clarification hint

    /// Determines jurisdiction from messages and optional device-derived place (e.g. from reverse-geocoding the user's location). Returns a result with jurisdiction, whether it was determined, and a suggested clarifying question when the system should ask the user.
    func determineJurisdictionResult(
        from messages: [Message],
        devicePlace: Jurisdiction?
    ) -> JurisdictionResult {
        let fromMessages = extractFromMessages(messages)
        let fromDevice = devicePlace

        let country: String
        let state: String?
        let county: String?

        if let m = fromMessages {
            country = m.country
            state = m.state ?? fromDevice?.state
            county = m.county ?? fromDevice?.county
        } else if let d = fromDevice {
            country = d.country
            state = d.state
            county = d.county
        } else {
            return JurisdictionResult(
                jurisdiction: .unknown,
                isDetermined: false,
                suggestedClarifyingQuestion: Self.suggestedQuestion
            )
        }

        let jurisdiction = Jurisdiction(country: country, state: state, county: county)
        let isDetermined = !country.isEmpty && (state != nil && !state!.isEmpty || country.lowercased() != "united states")
        return JurisdictionResult(
            jurisdiction: jurisdiction,
            isDetermined: isDetermined,
            suggestedClarifyingQuestion: isDetermined ? nil : Self.suggestedQuestion
        )
    }

    // MARK: - Extract from message content

    private func extractFromMessages(_ messages: [Message]) -> Jurisdiction? {
        let combined = messages
            .filter { $0.role == "user" }
            .map { $0.content.trimmingCharacters(in: .whitespacesAndNewlines) }
            .joined(separator: " ")
            .lowercased()
        guard !combined.isEmpty else { return nil }
        return parseTextForJurisdiction(combined)
    }

    /// Parses free text for country, state, and county. Used for messages and can be reused for document/transcript text.
    func parseTextForJurisdiction(_ text: String) -> Jurisdiction? {
        let lower = text.lowercased()
        var country = "United States"
        var state: String?
        var county: String?

        // Country mentions
        if lower.contains("canada") || lower.contains(" ontario") || lower.contains(" quebec") { country = "Canada" }
        else if lower.contains("united kingdom") || lower.contains(" u.k.") || lower.contains(" uk ") || lower.contains("england") || lower.contains("wales") || lower.contains("scotland") { country = "United Kingdom" }
        else if lower.contains("australia") { country = "Australia" }
        else if lower.contains("germany") || lower.contains("deutschland") { country = "Germany" }
        else if lower.contains("france") { country = "France" }
        else if lower.contains("mexico") && !lower.contains("new mexico") { country = "Mexico" }

        // US state: full name or two-letter code (standalone or after comma)
        for (fullName, code) in Self.usStateAbbrev {
            if lower.contains(fullName) {
                state = code
                break
            }
        }
        if state == nil {
            for code in Self.usStateCodes {
                let pattern = "\\b\(code)\\b"
                if lower.range(of: pattern, options: .regularExpression) != nil {
                    state = code
                    break
                }
            }
        }

        // County: "X County" or "County of X"
        let countyPattern = #"(?:(\w+(?:\s+\w+)*)\s+county|county\s+of\s+(\w+(?:\s+\w+)*))"#
        if let regex = try? NSRegularExpression(pattern: countyPattern, options: .caseInsensitive),
           let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) {
            let range1 = Range(match.range(at: 1), in: text)
            let range2 = Range(match.range(at: 2), in: text)
            if let r = range1 ?? range2, r.lowerBound != r.upperBound {
                county = String(text[r]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        // If we found at least country (non-default) or state, return
        if state != nil || county != nil || country != "United States" {
            return Jurisdiction(country: country, state: state, county: county)
        }
        // Check for generic "in [state]" or "[state]" mention we might have missed
        if lower.contains(" in ") || lower.contains(" state of ") {
            for (fullName, code) in Self.usStateAbbrev {
                if lower.contains(" in \(fullName)") || lower.contains(" state of \(fullName)") {
                    return Jurisdiction(country: "United States", state: code, county: nil)
                }
            }
        }
        return nil
    }

    /// Call when jurisdiction is also inferrable from document or transcript text (e.g. evidence content). Combines with message-derived jurisdiction; document text can supply county or state if messages did not.
    func determineJurisdiction(
        from messages: [Message],
        documentText: String?,
        devicePlace: Jurisdiction?
    ) -> JurisdictionResult {
        var fromMessages = extractFromMessages(messages)
        if let doc = documentText?.trimmingCharacters(in: .whitespacesAndNewlines), !doc.isEmpty,
           let fromDoc = parseTextForJurisdiction(doc) {
            if fromMessages == nil {
                fromMessages = fromDoc
            } else {
                fromMessages = Jurisdiction(
                    country: fromMessages!.country,
                    state: fromMessages!.state ?? fromDoc.state,
                    county: fromMessages!.county ?? fromDoc.county
                )
            }
        }
        let combinedMessages = fromMessages
        let fromDevice = devicePlace
        let country: String
        let state: String?
        let county: String?
        if let m = combinedMessages {
            country = m.country
            state = m.state ?? fromDevice?.state
            county = m.county ?? fromDevice?.county
        } else if let d = fromDevice {
            country = d.country
            state = d.state
            county = d.county
        } else {
            return JurisdictionResult(
                jurisdiction: .unknown,
                isDetermined: false,
                suggestedClarifyingQuestion: Self.suggestedQuestion
            )
        }
        let jurisdiction = Jurisdiction(country: country, state: state, county: county)
        let isDetermined = !country.isEmpty && (state != nil && !state!.isEmpty || country.lowercased() != "united states")
        return JurisdictionResult(
            jurisdiction: jurisdiction,
            isDetermined: isDetermined,
            suggestedClarifyingQuestion: isDetermined ? nil : Self.suggestedQuestion
        )
    }
}
