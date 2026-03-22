import Foundation

// MARK: - Node kinds

/// Kind of node in the case knowledge graph.
enum GraphNodeKind: String, Codable, CaseIterable {
    case person
    case evidence
    case event
    case legalClaim
}

// MARK: - Nodes

/// A node in the case knowledge graph (person, evidence, event, or legal claim). Linked by caseId.
struct GraphNode: Identifiable, Codable, Equatable {
    let id: UUID
    let caseId: UUID
    let kind: GraphNodeKind
    var label: String
    /// Optional reference to the source entity (e.g. CaseFile.id, CaseParticipant.id, Claim.id).
    var entityId: UUID?

    init(id: UUID = UUID(), caseId: UUID, kind: GraphNodeKind, label: String, entityId: UUID? = nil) {
        self.id = id
        self.caseId = caseId
        self.kind = kind
        self.label = label
        self.entityId = entityId
    }
}

// MARK: - Relationships

/// A directed relationship between two nodes (e.g. Witness → observed → Eviction Event). Linked by caseId.
struct GraphRelationship: Identifiable, Codable, Equatable {
    let id: UUID
    let caseId: UUID
    let sourceNodeId: UUID
    let relationshipType: String
    let targetNodeId: UUID

    init(id: UUID = UUID(), caseId: UUID, sourceNodeId: UUID, relationshipType: String, targetNodeId: UUID) {
        self.id = id
        self.caseId = caseId
        self.sourceNodeId = sourceNodeId
        self.relationshipType = relationshipType
        self.targetNodeId = targetNodeId
    }
}

// MARK: - Common relationship types (for AI reasoning)

extension GraphRelationship {
    /// Example: Witness → observed → Event
    static let typeObserved = "observed"
    /// Example: Photo → supports → Claim
    static let typeSupports = "supports"
    /// Example: Document → describes → Event
    static let typeDescribes = "describes"
    /// Example: Person → witnessed → Event
    static let typeWitnessed = "witnessed"
    /// Example: Event → ledTo → Event
    static let typeLedTo = "ledTo"
    /// Example: Evidence → contradicts → Claim
    static let typeContradicts = "contradicts"
}

// MARK: - Knowledge graph

/// Represents relationships between case entities (people, evidence, events, legal claims) so the AI can reason about how evidence supports or relates to claims and events.
final class CaseKnowledgeGraph {

    private var nodesByCase: [UUID: [GraphNode]] = [:]
    private var relationshipsByCase: [UUID: [GraphRelationship]] = [:]
    private let queue = DispatchQueue(label: "CaseKnowledgeGraph", qos: .userInitiated)

    // MARK: - Nodes

    func addNode(_ node: GraphNode) {
        queue.async { [weak self] in
            guard let self = self else { return }
            var list = self.nodesByCase[node.caseId] ?? []
            if !list.contains(where: { $0.id == node.id }) {
                list.append(node)
                self.nodesByCase[node.caseId] = list
            }
        }
    }

    func nodes(for caseId: UUID, kind: GraphNodeKind? = nil) -> [GraphNode] {
        queue.sync {
            let list = nodesByCase[caseId] ?? []
            guard let k = kind else { return list }
            return list.filter { $0.kind == k }
        }
    }

    func node(id: UUID, caseId: UUID) -> GraphNode? {
        queue.sync { nodesByCase[caseId]?.first(where: { $0.id == id }) }
    }

    // MARK: - Relationships

    func addRelationship(_ relationship: GraphRelationship) {
        queue.async { [weak self] in
            guard let self = self else { return }
            var list = self.relationshipsByCase[relationship.caseId] ?? []
            if !list.contains(where: { $0.id == relationship.id }) {
                list.append(relationship)
                self.relationshipsByCase[relationship.caseId] = list
            }
        }
    }

    /// Relationships where the given node is the source (e.g. Witness → observed → Event).
    func relationships(from sourceNodeId: UUID, caseId: UUID) -> [GraphRelationship] {
        queue.sync { (relationshipsByCase[caseId] ?? []).filter { $0.sourceNodeId == sourceNodeId } }
    }

    /// Relationships where the given node is the target (e.g. Photo → supports → Claim).
    func relationships(to targetNodeId: UUID, caseId: UUID) -> [GraphRelationship] {
        queue.sync { (relationshipsByCase[caseId] ?? []).filter { $0.targetNodeId == targetNodeId } }
    }

    /// All relationships for the case (e.g. for serialization or AI context).
    func relationships(for caseId: UUID) -> [GraphRelationship] {
        queue.sync { relationshipsByCase[caseId] ?? [] }
    }

    /// Relationships of a given type (e.g. "supports") for the case.
    func relationships(for caseId: UUID, type: String) -> [GraphRelationship] {
        queue.sync { (relationshipsByCase[caseId] ?? []).filter { $0.relationshipType == type } }
    }

    // MARK: - Snapshot for AI

    /// Returns a textual representation of the graph for the case (nodes and edges) so the AI can reason about relationships between evidence and claims.
    func snapshot(for caseId: UUID) -> String {
        queue.sync {
            let nodes = nodesByCase[caseId] ?? []
            let rels = relationshipsByCase[caseId] ?? []
            if nodes.isEmpty && rels.isEmpty { return "No knowledge graph data for this case." }
            var lines: [String] = ["Knowledge graph (caseId: \(caseId.uuidString))"]
            lines.append("Nodes: \(nodes.count)")
            for n in nodes {
                lines.append("  - [\(n.kind.rawValue)] \(n.label) (id: \(n.id.uuidString))")
            }
            lines.append("Relationships: \(rels.count)")
            for r in rels {
                let src = nodes.first(where: { $0.id == r.sourceNodeId })?.label ?? r.sourceNodeId.uuidString
                let tgt = nodes.first(where: { $0.id == r.targetNodeId })?.label ?? r.targetNodeId.uuidString
                lines.append("  - \(src) --[\(r.relationshipType)]--> \(tgt)")
            }
            return lines.joined(separator: "\n")
        }
    }

    /// Clears all nodes and relationships for the case (e.g. before rebuilding from case state).
    func clear(caseId: UUID) {
        queue.async { [weak self] in
            self?.nodesByCase[caseId] = []
            self?.relationshipsByCase[caseId] = []
        }
    }
}
