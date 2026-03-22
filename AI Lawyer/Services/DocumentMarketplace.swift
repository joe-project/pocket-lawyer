import Foundation

/// A legal document offered in the marketplace that users can generate. Some require premium access.
struct MarketplaceDocument: Identifiable {
    let id: UUID
    let name: String
    let description: String
    let premiumRequired: Bool

    init(id: UUID = UUID(), name: String, description: String, premiumRequired: Bool) {
        self.id = id
        self.name = name
        self.description = description
        self.premiumRequired = premiumRequired
    }
}

/// Provides the list of premium legal documents users can generate. Use `shouldPromptUpgrade(for:hasPremium:)` before generating to prompt the user to upgrade when required.
enum DocumentMarketplace {

    /// All marketplace documents available for generation. Use this to drive the document picker or list UI.
    static let documents: [MarketplaceDocument] = [
        MarketplaceDocument(
            name: "Demand Letter",
            description: "A formal letter demanding compensation or corrective action before filing a lawsuit. Often required before litigation.",
            premiumRequired: true
        ),
        MarketplaceDocument(
            name: "Civil Complaint",
            description: "The initial court filing that starts a civil lawsuit, stating your claims and requested relief.",
            premiumRequired: true
        ),
        MarketplaceDocument(
            name: "Insurance Appeal Letter",
            description: "A letter appealing a denied or underpaid insurance claim, with supporting facts and policy references.",
            premiumRequired: true
        ),
        MarketplaceDocument(
            name: "Settlement Offer Letter",
            description: "A letter proposing settlement terms to the other party, often used to resolve a dispute without trial.",
            premiumRequired: true
        ),
    ]

    /// Returns whether the user should be prompted to upgrade before generating this document. When `true`, show paywall or upgrade prompt instead of generating.
    static func shouldPromptUpgrade(for document: MarketplaceDocument, hasPremium: Bool) -> Bool {
        document.premiumRequired && !hasPremium
    }

    /// Returns the marketplace document for a given name, if any (e.g. to resolve from DocumentEngine or UI selection).
    static func document(named name: String) -> MarketplaceDocument? {
        documents.first { $0.name == name }
    }
}
