import Foundation

/// Generates and manages legal documents for a case via `AIEngine`. Documents are versioned (v1, v2, v3); new evidence or facts trigger new versions instead of overwriting. Document history remains available.
class DocumentEngine {

    private let aiEngine: AIEngine

    init(aiEngine: AIEngine = .shared) {
        self.aiEngine = aiEngine
    }

    private static let documentTypePrefixForVersion = " v"

    // MARK: - Versioning

    /// Returns the current highest version number for a document type (e.g. "Demand Letter v1", "Demand Letter v2" → 2). Pass this as `existingVersion` to `generateDocument` so it creates the next version (v3) and history is preserved.
    func nextVersionNumber(for documentType: String, existingFiles: [CaseFile]) -> Int {
        let prefix = documentType + Self.documentTypePrefixForVersion
        var maxVersion = 0
        for file in existingFiles {
            guard file.name.hasPrefix(prefix) else { continue }
            let suffix = String(file.name.dropFirst(prefix.count))
            if let v = Int(suffix), v > maxVersion {
                maxVersion = v
            }
        }
        return maxVersion
    }

    /// Returns existing documents of this type sorted by version (v1, v2, v3) so document history remains available. Does not modify or delete anything.
    func documentHistory(documentType: String, existingFiles: [CaseFile]) -> [CaseFile] {
        let prefix = documentType + Self.documentTypePrefixForVersion
        return existingFiles
            .filter { $0.name.hasPrefix(prefix) }
            .sorted { file1, file2 in
                let v1 = versionNumber(from: file1.name, prefix: prefix)
                let v2 = versionNumber(from: file2.name, prefix: prefix)
                return v1 < v2
            }
    }

    private func versionNumber(from name: String, prefix: String) -> Int {
        let suffix = String(name.dropFirst(prefix.count))
        return Int(suffix) ?? 0
    }

    // MARK: - Suggest updates when new evidence or facts appear

    /// Document types that, when they already exist, may warrant an update when case analysis changes (e.g. new evidence).
    private static let updateableDocumentTypes: Set<String> = [
        "Demand Letter", "Civil Complaint", "Evidence Checklist", "Breach Notice", "Insurance Claim Letter", "EEOC Charge"
    ]

    /// Suggests document types that already exist for the case and are relevant to the current analysis, so the system can prompt the user to create a new version (e.g. "New evidence was added. Would you like to update your Demand Letter? (v2)").
    /// - Parameters:
    ///   - caseAnalysis: Current case analysis (may include new evidence or facts).
    ///   - existingFiles: Current documents in the case (e.g. from .documents subfolder).
    /// - Returns: Document types that have at least one existing version and are updateable; the system can suggest creating the next version.
    func suggestDocumentUpdates(
        caseAnalysis: CaseAnalysis,
        existingFiles: [CaseFile]
    ) -> [String] {
        let existingTypes = Set(existingFiles.compactMap { file -> String? in
            guard let idx = file.name.range(of: Self.documentTypePrefixForVersion)?.lowerBound else { return nil }
            return String(file.name[..<idx]).trimmingCharacters(in: .whitespaces)
        })
        let relevantTypes = DocumentSuggestionEngine().suggestedDocumentTypes(for: caseAnalysis)
        return relevantTypes
            .filter { Self.updateableDocumentTypes.contains($0) && existingTypes.contains($0) }
            .sorted()
    }

    // MARK: - Generate (always creates new version, never overwrites)

    /// Generates a professional legal document of the given type from the case analysis. Pass `existingVersion` (e.g. from `nextVersionNumber(for:existingFiles:)`) to create the next version (v1, v2, v3) so existing versions remain in history.
    func generateDocument(
        caseAnalysis: CaseAnalysis,
        documentType: String,
        existingVersion: Int? = nil
    ) async throws -> CaseDocument {
        let response = try await aiEngine.generateDocument(caseAnalysis: caseAnalysis, documentType: documentType)

        let nextVersion = (existingVersion ?? 0) + 1
        return CaseDocument(
            id: UUID(),
            title: documentType,
            version: nextVersion,
            content: response,
            createdAt: Date()
        )
    }

    /// Saves the generated document into the case's Documents folder with a versioned name (e.g. "Demand Letter v1"). Never overwrites; each save adds a new file so document history remains available.
    func saveToCase(
        caseId: UUID,
        document: CaseDocument,
        using caseTreeViewModel: CaseTreeViewModel
    ) -> (CaseFile, TimelineEvent)? {
        let versionedName = "\(document.title)\(Self.documentTypePrefixForVersion)\(document.version)"
        return caseTreeViewModel.addGeneratedDocument(
            caseId: caseId,
            subfolder: caseTreeViewModel.selectedSubfolder,
            name: versionedName,
            content: document.content
        )
    }
}
