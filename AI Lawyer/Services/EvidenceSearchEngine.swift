import Foundation

// MARK: - Model

/// A single evidence item with searchable metadata: description, case reference, and evidence category.
struct EvidenceSearchItem: Identifiable {
    let id: UUID
    let fileId: UUID
    let name: String
    /// Searchable description (e.g. content preview or file name).
    let description: String
    let caseId: UUID
    let caseTitle: String
    let evidenceCategory: String
}

// MARK: - Engine

/// Enables semantic-style search over evidence: by keyword, by case, and by description. Evidence items carry searchable metadata (description, case reference, category).
final class EvidenceSearchEngine {
    private let categorizationEngine = EvidenceCategorizationEngine()

    /// Maximum length of content used as description for search (avoids indexing huge documents).
    private static let descriptionPreviewLength = 2000

    /// Builds searchable items from all evidence files across cases. Call with the current case tree to index evidence (name, content preview, case, category).
    func buildSearchableItems(from caseTreeViewModel: CaseTreeViewModel) -> [EvidenceSearchItem] {
        var items: [EvidenceSearchItem] = []
        for caseFolder in caseTreeViewModel.cases {
            let files = caseTreeViewModel.files(for: caseFolder.id, subfolder: .evidence)
            for file in files {
                let description = (file.content?.trimmingCharacters(in: .whitespacesAndNewlines))
                    .map { $0.count > Self.descriptionPreviewLength ? String($0.prefix(Self.descriptionPreviewLength)) + "…" : $0 }
                    ?? file.name
                let category = categorizationEngine.categorize(fileName: file.name)
                items.append(EvidenceSearchItem(
                    id: file.id,
                    fileId: file.id,
                    name: file.name,
                    description: description,
                    caseId: caseFolder.id,
                    caseTitle: caseFolder.title,
                    evidenceCategory: category
                ))
            }
            let recordings = caseTreeViewModel.files(for: caseFolder.id, subfolder: .recordings)
            for file in recordings {
                let description = (file.content?.trimmingCharacters(in: .whitespacesAndNewlines))
                    .map { $0.count > Self.descriptionPreviewLength ? String($0.prefix(Self.descriptionPreviewLength)) + "…" : $0 }
                    ?? file.name
                let category = "recordings"
                items.append(EvidenceSearchItem(
                    id: file.id,
                    fileId: file.id,
                    name: file.name,
                    description: description,
                    caseId: caseFolder.id,
                    caseTitle: caseFolder.title,
                    evidenceCategory: category
                ))
            }
        }
        return items
    }

    /// Search by keyword: matches against name, description, case title, and evidence category (case-insensitive).
    func searchByKeyword(_ keyword: String, in items: [EvidenceSearchItem]) -> [EvidenceSearchItem] {
        let q = keyword.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return items }
        return items.filter { item in
            item.name.lowercased().contains(q)
                || item.description.lowercased().contains(q)
                || item.caseTitle.lowercased().contains(q)
                || item.evidenceCategory.lowercased().contains(q)
        }
    }

    /// Search by case: returns all evidence items for the given case id.
    func searchByCase(_ caseId: UUID, in items: [EvidenceSearchItem]) -> [EvidenceSearchItem] {
        items.filter { $0.caseId == caseId }
    }

    /// Search by description: matches query against the description (and name) text (case-insensitive).
    func searchByDescription(_ query: String, in items: [EvidenceSearchItem]) -> [EvidenceSearchItem] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return items }
        return items.filter { item in
            item.description.lowercased().contains(q) || item.name.lowercased().contains(q)
        }
    }

    /// Combined search: applies keyword, case, and description filters when provided. All non-nil criteria must match.
    func search(
        keyword: String? = nil,
        caseId: UUID? = nil,
        descriptionQuery: String? = nil,
        in items: [EvidenceSearchItem]
    ) -> [EvidenceSearchItem] {
        var result = items
        if let k = keyword, !k.isEmpty {
            result = searchByKeyword(k, in: result)
        }
        if let cid = caseId {
            result = searchByCase(cid, in: result)
        }
        if let d = descriptionQuery, !d.isEmpty {
            result = searchByDescription(d, in: result)
        }
        return result
    }
}
