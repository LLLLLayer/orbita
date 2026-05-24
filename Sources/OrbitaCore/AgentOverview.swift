import Foundation

public struct AgentCapabilitySummary: Codable, Hashable, Sendable {
    public var agent: AgentID
    public var visibleCount: Int
    public var hiddenCount: Int
    public var riskyCount: Int
    public var driftedCount: Int

    public init(agent: AgentID, visibleCount: Int, hiddenCount: Int, riskyCount: Int, driftedCount: Int) {
        self.agent = agent
        self.visibleCount = visibleCount
        self.hiddenCount = hiddenCount
        self.riskyCount = riskyCount
        self.driftedCount = driftedCount
    }
}

public struct AgentCapabilityDifference: Codable, Hashable, Sendable {
    public var capabilityID: String
    public var capabilityName: String
    public var capabilityType: CapabilityType
    public var visibleAgents: [AgentID]
    public var hiddenAgents: [AgentID]
    public var reasons: [String]

    public init(
        capabilityID: String,
        capabilityName: String,
        capabilityType: CapabilityType,
        visibleAgents: [AgentID],
        hiddenAgents: [AgentID],
        reasons: [String]
    ) {
        self.capabilityID = capabilityID
        self.capabilityName = capabilityName
        self.capabilityType = capabilityType
        self.visibleAgents = visibleAgents
        self.hiddenAgents = hiddenAgents
        self.reasons = reasons
    }
}

public struct AgentCapabilityOverview: Codable, Sendable {
    public var schemaVersion: Int
    public var projectRoot: String
    public var agentSummaries: [AgentCapabilitySummary]
    public var differences: [AgentCapabilityDifference]

    public init(
        schemaVersion: Int = 1,
        projectRoot: String,
        agentSummaries: [AgentCapabilitySummary],
        differences: [AgentCapabilityDifference]
    ) {
        self.schemaVersion = schemaVersion
        self.projectRoot = projectRoot
        self.agentSummaries = agentSummaries
        self.differences = differences
    }
}

public final class AgentOverviewBuilder {
    public init() {}

    public func overview(graph: CapabilityGraph) -> AgentCapabilityOverview {
        let resolver = AgentViewResolver()
        let capabilityTypes = Dictionary(uniqueKeysWithValues: graph.capabilities.map { ($0.id, $0.type) })
        let summaries = AgentID.allCases.map { agent in
            let view = resolver.view(for: agent, graph: graph)
            return AgentCapabilitySummary(
                agent: agent,
                visibleCount: view.visibleCapabilities.count,
                hiddenCount: view.hiddenCapabilities.count,
                riskyCount: view.visibleCapabilities.filter { $0.statuses.contains(.risky) }.count,
                driftedCount: view.visibleCapabilities.filter { $0.statuses.contains(.drifted) }.count
            )
        }

        let differences = DriftReportBuilder().report(graph: graph).items
            .filter { !$0.visibleAgents.isEmpty && !$0.hiddenAgents.isEmpty }
            .map { item in
                AgentCapabilityDifference(
                    capabilityID: item.capabilityID,
                    capabilityName: item.capabilityName,
                    capabilityType: capabilityTypes[item.capabilityID] ?? .unknown,
                    visibleAgents: item.visibleAgents,
                    hiddenAgents: item.hiddenAgents,
                    reasons: item.reasons
                )
            }
            .sorted { lhs, rhs in
                lhs.capabilityName.localizedCaseInsensitiveCompare(rhs.capabilityName) == .orderedAscending
            }

        return AgentCapabilityOverview(
            projectRoot: graph.projectRoot,
            agentSummaries: summaries,
            differences: differences
        )
    }
}
