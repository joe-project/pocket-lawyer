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

    /// Applies guardrails to an AI response: appends the standard legal disclaimer when appropriate so every user-facing response includes it. Call this on every AI response before displaying to the user.
    /// - Parameter response: Raw assistant response text.
    /// - Returns: The same response with the disclaimer appended (once) if it was not already present.
    static func applyGuardrails(to response: String) -> String {
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return response }
        if trimmed.localizedCaseInsensitiveContains(legalDisclaimer) {
            return response
        }
        return response.trimmingCharacters(in: .whitespacesAndNewlines)
            + "\n\n"
            + legalDisclaimer
    }
}
