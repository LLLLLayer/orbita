import Foundation

public struct CapabilityExplanation: Codable, Sendable {
    public var schemaVersion: Int
    public var capability: Capability
    public var visibleAgents: [AgentID]
    public var hiddenAgents: [AgentID]

    public init(
        schemaVersion: Int = 1,
        capability: Capability,
        visibleAgents: [AgentID],
        hiddenAgents: [AgentID]
    ) {
        self.schemaVersion = schemaVersion
        self.capability = capability
        self.visibleAgents = visibleAgents
        self.hiddenAgents = hiddenAgents
    }
}

public final class CapabilityExplainer {
    public init() {}

    public func explain(capabilityID: String, graph: CapabilityGraph) throws -> CapabilityExplanation {
        guard let capability = graph.capabilities.first(where: { $0.id == capabilityID }) else {
            throw OrbitaError.capabilityNotFound(capabilityID)
        }

        var visibleAgents: [AgentID] = []
        var hiddenAgents: [AgentID] = []
        let resolver = AgentViewResolver()

        for agent in AgentID.allCases {
            let view = resolver.view(for: agent, graph: graph)
            if view.visibleCapabilities.contains(capability) {
                visibleAgents.append(agent)
            } else {
                hiddenAgents.append(agent)
            }
        }

        return CapabilityExplanation(
            capability: capability,
            visibleAgents: visibleAgents,
            hiddenAgents: hiddenAgents
        )
    }
}
