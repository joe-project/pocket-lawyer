import Foundation

// MARK: - Invitation (secure link for case access)

/// A secure invitation that allows an invited user to access a specific case (upload evidence, record statements). Token is used in the invitation URL.
struct CaseInvitation: Identifiable, Codable {
    let id: UUID
    let caseId: UUID
    /// Secure token included in the invitation link (e.g. ai-lawyer://invite/TOKEN).
    let token: String
    let createdAt: Date
    var expiresAt: Date?

    init(id: UUID = UUID(), caseId: UUID, token: String, createdAt: Date = Date(), expiresAt: Date? = nil) {
        self.id = id
        self.caseId = caseId
        self.token = token
        self.createdAt = createdAt
        self.expiresAt = expiresAt
    }
}

// MARK: - Model

/// A participant contributing to a case. Roles: owner, witness, participant, attorney. Linked by caseId.
struct CaseParticipant: Identifiable, Codable, Equatable {
    let id: UUID
    let caseId: UUID
    let name: String
    let role: String

    init(id: UUID = UUID(), caseId: UUID, name: String, role: String) {
        self.id = id
        self.caseId = caseId
        self.name = name
        self.role = role
    }
}

/// Supported participant roles for case collaboration.
enum CaseParticipantRole: String, CaseIterable, Codable {
    case owner
    case witness
    case participant
    case attorney

    var displayName: String {
        rawValue.capitalized
    }
}

// MARK: - Engine

/// Allows multiple participants to contribute to a case. Add participants by role (owner, witness, participant, attorney) and list them per case. Generates secure invitation links so invited users can access a specific case (upload evidence, record statements) with restricted access.
final class CaseCollaborationEngine {

    /// URL scheme for invitation deep links. Invited user opens: ai-lawyer://invite/{token}
    static let inviteURLScheme = "ai-lawyer"
    static let inviteURLHost = "invite"

    private var participantsByCase: [UUID: [CaseParticipant]] = [:]
    private var invitationsByToken: [String: CaseInvitation] = [:]
    private let queue = DispatchQueue(label: "CaseCollaborationEngine", qos: .userInitiated)

    /// Valid role values for addParticipant.
    static let validRoles: Set<String> = Set(CaseParticipantRole.allCases.map(\.rawValue))

    /// Adds a participant to the case and returns the created participant. Role must be one of: owner, witness, participant, attorney.
    func addParticipant(caseId: UUID, name: String, role: String) -> CaseParticipant {
        let normalizedRole = role.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let validRole = Self.validRoles.contains(normalizedRole) ? normalizedRole : CaseParticipantRole.participant.rawValue
        let participant = CaseParticipant(caseId: caseId, name: name, role: validRole)
        queue.async { [weak self] in
            guard let self = self else { return }
            var list = self.participantsByCase[caseId] ?? []
            list.append(participant)
            self.participantsByCase[caseId] = list
        }
        return participant
    }

    /// Returns all participants for the case.
    func participants(for caseId: UUID) -> [CaseParticipant] {
        queue.sync { participantsByCase[caseId] ?? [] }
    }

    /// Removes a participant from the case by id.
    func removeParticipant(caseId: UUID, participantId: UUID) {
        queue.async { [weak self] in
            self?.participantsByCase[caseId]?.removeAll { $0.id == participantId }
        }
    }

    // MARK: - Secure invitation link

    /// Creates a secure invitation for the case. Returns the invitation and a shareable link. Invited user can open the link to access only this case (upload evidence, record statements).
    func createInvitation(caseId: UUID) -> CaseInvitation {
        let token = UUID().uuidString
        let invitation = CaseInvitation(caseId: caseId, token: token)
        queue.async { [weak self] in
            self?.invitationsByToken[token] = invitation
        }
        return invitation
    }

    /// Returns the shareable invitation URL for the token. Invited user opens this to get restricted access to the case.
    func invitationURL(for token: String) -> String {
        "\(Self.inviteURLScheme)://\(Self.inviteURLHost)/\(token)"
    }

    /// Resolves an invitation token to the case id. Returns nil if token is unknown or expired.
    func resolveInvitation(token: String) -> UUID? {
        queue.sync {
            guard let inv = invitationsByToken[token] else { return nil }
            if let exp = inv.expiresAt, exp < Date() { return nil }
            return inv.caseId
        }
    }
}
