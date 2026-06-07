import Foundation

/// One physical location of a capability that participates in a drifted same-name group.
/// The resolver attaches the full list (serialised under the `driftLocationsJSON` metadata key)
/// to every member of the group, with `current` flagging the member it is attached to, so the
/// inspector can show "this copy vs. the others" and surface exactly which content diverged.
public struct DriftLocation: Codable, Hashable, Sendable {
    /// The capability's `source.kind` (e.g. `agents-skill`, `trae-skill`, `claude-skill`).
    public var kind: String
    /// The capability's scope raw value (`project` / `user` / `installed` / `environment`).
    public var scope: String
    /// Home-abbreviated display path of the real on-disk location.
    public var path: String
    /// Full content hash of this copy (empty when the scanner could not hash it).
    public var hash: String
    /// True for the location whose tile this list is attached to.
    public var current: Bool

    public init(kind: String, scope: String, path: String, hash: String, current: Bool) {
        self.kind = kind
        self.scope = scope
        self.path = path
        self.hash = hash
        self.current = current
    }
}

public struct DriftReportItem: Codable, Hashable, Sendable {
    public var capabilityID: String
    public var capabilityName: String
    public var visibleAgents: [AgentID]
    public var hiddenAgents: [AgentID]
    public var statuses: [CapabilityStatus]
    public var reasons: [String]

    public init(
        capabilityID: String,
        capabilityName: String,
        visibleAgents: [AgentID],
        hiddenAgents: [AgentID],
        statuses: [CapabilityStatus],
        reasons: [String]
    ) {
        self.capabilityID = capabilityID
        self.capabilityName = capabilityName
        self.visibleAgents = visibleAgents
        self.hiddenAgents = hiddenAgents
        self.statuses = statuses
        self.reasons = reasons
    }
}

public struct DriftReport: Codable, Sendable {
    public var schemaVersion: Int
    public var projectRoot: String
    public var items: [DriftReportItem]

    public init(schemaVersion: Int = 1, projectRoot: String, items: [DriftReportItem]) {
        self.schemaVersion = schemaVersion
        self.projectRoot = projectRoot
        self.items = items
    }
}

public final class DriftReportBuilder {
    public init() {}

    public func report(graph: CapabilityGraph) -> DriftReport {
        let resolver = AgentViewResolver()
        let views = Dictionary(uniqueKeysWithValues: AgentID.allCases.map { agent in
            (agent, resolver.view(for: agent, graph: graph))
        })
        let adapterPreviews = Dictionary(uniqueKeysWithValues: AgentID.allCases.map { agent in
            (agent, AdapterPreviewBuilder().preview(for: agent, graph: graph))
        })

        let items = graph.capabilities.compactMap { capability -> DriftReportItem? in
            let visibleAgents = AgentID.allCases.filter { agent in
                views[agent]?.visibleCapabilities.contains(capability) == true
            }
            let hiddenAgents = AgentID.allCases.filter { agent in
                !visibleAgents.contains(agent)
            }
            let hasStatusDrift = capability.statuses.contains(.drifted) || capability.statuses.contains(.shadowed)
            let hasVisibilityDrift = !visibleAgents.isEmpty && !hiddenAgents.isEmpty
            guard hasStatusDrift || hasVisibilityDrift else { return nil }

            var reasons: [String] = []
            if hasVisibilityDrift {
                reasons.append("visible to \(visibleAgents.map(\.rawValue).joined(separator: ", "))")
                reasons.append("hidden from \(hiddenAgents.map(\.rawValue).joined(separator: ", "))")
                reasons.append(contentsOf: adapterReasons(
                    for: capability,
                    visibleAgents: visibleAgents,
                    hiddenAgents: hiddenAgents,
                    previews: adapterPreviews
                ))
            }
            if capability.statuses.contains(.shadowed) {
                reasons.append("shadowed by higher-precedence scope")
            }
            if capability.statuses.contains(.drifted) {
                reasons.append("content hash differs across matching capabilities")
            }
            if let driftReason = capability.metadata["driftReason"] {
                reasons.append(driftReason)
            }

            return DriftReportItem(
                capabilityID: capability.id,
                capabilityName: capability.name,
                visibleAgents: visibleAgents,
                hiddenAgents: hiddenAgents,
                statuses: capability.statuses,
                reasons: reasons
            )
        }

        return DriftReport(projectRoot: graph.projectRoot, items: items.sorted { $0.capabilityID < $1.capabilityID })
    }

    private func adapterReasons(
        for capability: Capability,
        visibleAgents: [AgentID],
        hiddenAgents: [AgentID],
        previews: [AgentID: AdapterPreview]
    ) -> [String] {
        var reasons: [String] = []
        for agent in visibleAgents {
            guard let mapping = mapping(for: capability, agent: agent, previews: previews) else { continue }
            reasons.append("\(displayName(for: agent)) supports \(capability.source.kind): \(mapping.reason)")
        }
        for agent in hiddenAgents {
            guard let mapping = mapping(for: capability, agent: agent, previews: previews) else { continue }
            reasons.append("\(displayName(for: agent)) does not load \(capability.source.kind): \(mapping.reason)")
        }
        return reasons
    }

    private func mapping(for capability: Capability, agent: AgentID, previews: [AgentID: AdapterPreview]) -> AdapterCapabilityMapping? {
        previews[agent]?.capabilityMappings.first { $0.capabilityID == capability.id }
    }

    private func displayName(for agent: AgentID) -> String {
        switch agent {
        case .codex:
            return "Codex"
        case .claudeCode:
            return "Claude Code"
        case .cursor:
            return "Cursor"
        case .trae:
            return "Trae"
        case .traeCN:
            return "Trae CN"
        }
    }
}
