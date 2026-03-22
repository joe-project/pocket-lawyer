import Foundation

/// A feature that may require premium access. Free users have limited access; premium users have full access.
enum PremiumFeature: String, CaseIterable {
    /// Unlimited document generation (Demand Letter, Civil Complaint, etc.). Free: limited per case.
    case documentGeneration = "Document generation"
    /// Advanced litigation strategy (AI strategy, evidence gaps, confidence). Free: basic only or hidden.
    case advancedLitigationStrategy = "Advanced litigation strategy"
    /// Using the "Connect with Attorney" referral flow. Free: button hidden or shows upgrade.
    case attorneyReferralConnections = "Attorney referral connections"
    /// Unlimited evidence uploads per case. Free: limited per case.
    case evidenceUploads = "Evidence uploads"
}

/// Usage counts for the current case, used to enforce free-tier limits.
struct PremiumUsage {
    var documentCountInCase: Int
    var evidenceCountInCase: Int

    static let zero = PremiumUsage(documentCountInCase: 0, evidenceCountInCase: 0)
}

/// Controls which features require premium access. Free users get limited access; when they try to use a premium feature, the app should display an upgrade prompt using `upgradePrompt(for:)`.
enum PremiumAccessManager {

    // MARK: - Free tier limits

    /// Maximum documents (generated) per case for free users. Premium = unlimited.
    static let freeDocumentLimitPerCase = 2
    /// Maximum evidence uploads per case for free users. Premium = unlimited.
    static let freeEvidenceLimitPerCase = 5

    // MARK: - Access checks

    /// Returns whether the user can use the feature. Use `usage` for per-case limits (document/evidence count); pass `.zero` or omit for features that only depend on `hasFullAccess`.
    static func canAccess(
        _ feature: PremiumFeature,
        hasFullAccess: Bool,
        usage: PremiumUsage = .zero
    ) -> Bool {
        if hasFullAccess { return true }
        switch feature {
        case .documentGeneration:
            return usage.documentCountInCase < freeDocumentLimitPerCase
        case .evidenceUploads:
            return usage.evidenceCountInCase < freeEvidenceLimitPerCase
        case .advancedLitigationStrategy, .attorneyReferralConnections:
            return false
        }
    }

    /// Returns the upgrade prompt to show when the user tries to use a premium feature they don’t have access to. Display this (e.g. alert or sheet) and offer a button to open the paywall or subscription screen.
    static func upgradePrompt(for feature: PremiumFeature) -> UpgradePrompt {
        switch feature {
        case .documentGeneration:
            return UpgradePrompt(
                title: "Document generation limit",
                message: "Free accounts can generate up to \(freeDocumentLimitPerCase) documents per case. Upgrade for unlimited document generation."
            )
        case .evidenceUploads:
            return UpgradePrompt(
                title: "Evidence upload limit",
                message: "Free accounts can upload up to \(freeEvidenceLimitPerCase) evidence items per case. Upgrade for unlimited evidence uploads."
            )
        case .advancedLitigationStrategy:
            return UpgradePrompt(
                title: "Premium feature",
                message: "Advanced litigation strategy is available with a premium subscription. Upgrade to unlock strategy insights and evidence gap analysis."
            )
        case .attorneyReferralConnections:
            return UpgradePrompt(
                title: "Connect with an attorney",
                message: "Attorney referral connections are available with a premium subscription. Upgrade to connect with licensed attorneys."
            )
        }
    }

    /// Call when the user attempts a premium action. Returns `true` if allowed, `false` if not (caller should then show `upgradePrompt(for: feature)` and not perform the action).
    static func requestAccess(
        _ feature: PremiumFeature,
        hasFullAccess: Bool,
        usage: PremiumUsage = .zero
    ) -> Bool {
        canAccess(feature, hasFullAccess: hasFullAccess, usage: usage)
    }
}

/// Copy for the upgrade prompt shown when a user hits a premium gate.
struct UpgradePrompt: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}
