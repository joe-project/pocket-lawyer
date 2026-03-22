import Foundation

// MARK: - Model

/// An evidence file classified into a category (photos, documents, messages, witness statements, videos).
struct EvidenceItem: Identifiable, Codable, Equatable {
    let id: UUID
    let filename: String
    let category: String

    init(id: UUID = UUID(), filename: String, category: String) {
        self.id = id
        self.filename = filename
        self.category = category
    }
}

// MARK: - Engine

/// Automatically classifies uploaded evidence into categories: photos, documents, messages, witness statements, videos.
final class EvidenceCategorizationEngine {

    /// Categories returned by `categorize(fileName:)`.
    static let categoryPhotos = "photos"
    static let categoryDocuments = "documents"
    static let categoryMessages = "messages"
    static let categoryWitnessStatements = "witness statements"
    static let categoryVideos = "videos"

    /// Classifies a file by name into one of: photos, documents, messages, witness statements, videos.
    func categorize(fileName: String) -> String {
        let lower = fileName.lowercased()
        if lower.contains("photo") || lower.hasSuffix(".jpg") || lower.hasSuffix(".jpeg") || lower.hasSuffix(".png") || lower.hasSuffix(".heic") {
            return Self.categoryPhotos
        }
        if lower.contains("video") || lower.hasSuffix(".mp4") || lower.hasSuffix(".mov") || lower.hasSuffix(".m4v") {
            return Self.categoryVideos
        }
        if lower.contains("message") || lower.contains("text") && (lower.contains("sms") || lower.contains("imessage")) {
            return Self.categoryMessages
        }
        if lower.contains("witness") || lower.contains("statement") {
            return Self.categoryWitnessStatements
        }
        return Self.categoryDocuments
    }

    /// Returns an `EvidenceItem` for the file with the given name and a generated id, using `categorize(fileName:)` for the category.
    func evidenceItem(filename: String, id: UUID = UUID()) -> EvidenceItem {
        EvidenceItem(id: id, filename: filename, category: categorize(fileName: filename))
    }
}
