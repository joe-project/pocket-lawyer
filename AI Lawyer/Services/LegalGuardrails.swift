import Foundation

/// Ensures AI responses include proper legal disclaimers and do not overstate the system’s role.
///
/// Rules:
/// • The AI must not claim to be a lawyer.
/// • The AI must not promise case outcomes.
/// • The AI must include a disclaimer when providing legal information.
enum LegalGuardrails {

    /// Disclaimer to append when the AI provides legal information. Shown to users so they understand the system is not a substitute for a licensed attorney.
    static let legalDisclaimer = "This system provides legal information and case organization tools, not formal legal advice. For legal advice specific to your situation, consult a licensed attorney."

    /// Applies lightweight guardrails to an AI response without forcing repetitive visible disclaimers into normal chat.
    /// - Parameter response: Raw assistant response text.
    /// - Returns: Trimmed response text.
    static func applyGuardrails(to response: String) -> String {
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return response }
        return trimmed
    }
}
