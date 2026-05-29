import SwiftUI
import OrbitaCore

enum AgentBehavior: String, Codable, CaseIterable, Sendable {
    case agentsSource
    case codexSource
    case claudeSource
    case cursorSource
    case traeSource
    case codexLike
    case claudeLike
    case skillsAgent
    case generic
}

struct AgentSelection: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var displayName: String
    var behavior: AgentBehavior
    var skillsAgentID: String? = nil

    static let agents = AgentSelection(id: "built-in:agents", displayName: "Agents", behavior: .agentsSource)
    static let codex = AgentSelection(id: "built-in:codex", displayName: "Codex", behavior: .codexSource)
    static let claudeCode = AgentSelection(id: "built-in:claude-code", displayName: "Claude Code", behavior: .claudeSource)
    static let cursor = AgentSelection(id: "built-in:cursor", displayName: "Cursor", behavior: .cursorSource)
    static let trae = AgentSelection(id: "built-in:trae", displayName: "Trae", behavior: .traeSource)
    static let defaultAgents = [agents, codex, claudeCode, trae]

    var isBuiltIn: Bool {
        id.hasPrefix("built-in:")
    }

    var isDeleteProtected: Bool {
        id == Self.codex.id || id == Self.claudeCode.id
    }

    var skillsInstallAgentID: String? {
        if let skillsAgentID {
            return skillsAgentID
        }
        if id == Self.codex.id || behavior == .codexSource || behavior == .codexLike {
            return "codex"
        }
        if id == Self.claudeCode.id || behavior == .claudeSource || behavior == .claudeLike {
            return "claude-code"
        }
        if id == Self.cursor.id || behavior == .cursorSource {
            return "cursor"
        }
        if id == Self.trae.id || behavior == .traeSource {
            return "trae"
        }
        return nil
    }

    func visibleCapabilities(in graph: CapabilityGraph) -> [Capability] {
        let capabilities: [Capability]
        switch behavior {
        case .agentsSource:
            capabilities = sourceCapabilities(.agents, in: graph)
        case .codexSource:
            capabilities = AgentViewResolver().view(for: .codex, graph: graph).visibleCapabilities
        case .claudeSource:
            capabilities = AgentViewResolver().view(for: .claudeCode, graph: graph).visibleCapabilities
        case .cursorSource:
            capabilities = AgentViewResolver().view(for: .cursor, graph: graph).visibleCapabilities
        case .traeSource:
            capabilities = AgentViewResolver().view(for: .trae, graph: graph).visibleCapabilities
        case .codexLike:
            capabilities = AgentViewResolver().view(for: .codex, graph: graph).visibleCapabilities
        case .claudeLike:
            capabilities = AgentViewResolver().view(for: .claudeCode, graph: graph).visibleCapabilities
        case .skillsAgent:
            guard let skillsAgentID else {
                return []
            }
            capabilities = graph.capabilities
                .filter { capability in
                    !capability.statuses.contains(.broken)
                        && !capability.statuses.contains(.disabled)
                        && capability.installedThroughSkillsCLI(for: skillsAgentID)
                }
                .sorted { $0.id < $1.id }
        case .generic:
            capabilities = graph.capabilities
                .filter { capability in
                    !capability.statuses.contains(.broken)
                        && !capability.statuses.contains(.disabled)
                }
                .sorted { $0.id < $1.id }
        }

        guard let agentID = skillsInstallAgentID else {
            return capabilities
        }

        return deduplicatedCapabilities(
            capabilities + graph.capabilities.filter { capability in
                !capability.statuses.contains(.broken)
                    && !capability.statuses.contains(.disabled)
                    && capability.installedThroughSkillsCLI(for: agentID)
            }
        )
    }

    func visibleCapabilityIDs(in graph: CapabilityGraph) -> Set<String> {
        var ids: Set<String>
        switch behavior {
        case .agentsSource:
            ids = sourceCapabilityIDs(.agents, in: graph)
        case .codexSource:
            ids = Set(AgentViewResolver().view(for: .codex, graph: graph).visibleCapabilities.map(\.id))
        case .claudeSource:
            ids = Set(AgentViewResolver().view(for: .claudeCode, graph: graph).visibleCapabilities.map(\.id))
        case .cursorSource:
            ids = Set(AgentViewResolver().view(for: .cursor, graph: graph).visibleCapabilities.map(\.id))
        case .traeSource:
            ids = Set(AgentViewResolver().view(for: .trae, graph: graph).visibleCapabilities.map(\.id))
        case .codexLike:
            ids = Set(AgentViewResolver().view(for: .codex, graph: graph).visibleCapabilities.map(\.id))
        case .claudeLike:
            ids = Set(AgentViewResolver().view(for: .claudeCode, graph: graph).visibleCapabilities.map(\.id))
        case .skillsAgent:
            guard let skillsAgentID else {
                ids = []
                break
            }
            ids = Set(graph.capabilities.compactMap { capability in
                !capability.statuses.contains(.broken)
                    && !capability.statuses.contains(.disabled)
                    && capability.installedThroughSkillsCLI(for: skillsAgentID)
                    ? capability.id
                    : nil
            })
        case .generic:
            ids = Set(graph.capabilities.compactMap { capability in
                !capability.statuses.contains(.broken)
                    && !capability.statuses.contains(.disabled)
                    ? capability.id
                    : nil
            })
        }

        if let agentID = skillsInstallAgentID {
            ids.formUnion(graph.capabilities.compactMap { capability in
                capability.installedThroughSkillsCLI(for: agentID) ? capability.id : nil
            })
        }
        return ids
    }

    func includesCapability(_ capability: Capability, in graph: CapabilityGraph) -> Bool {
        visibleCapabilityIDs(in: graph).contains(capability.id)
    }

    func preferredCapability(from capabilities: [Capability], visibleCapabilityIDs: Set<String>? = nil) -> Capability? {
        let candidates = capabilities.filter { capability in
            visibleCapabilityIDs?.contains(capability.id) ?? true
        }
        guard !candidates.isEmpty else {
            return nil
        }

        if let agentID = skillsInstallAgentID,
           let installTargetMatch = candidates.first(where: { $0.hasSkillsInstallTarget(for: agentID) }) {
            return installTargetMatch
        }

        if let sourcePathComponent,
           let directMatch = candidates.first(where: { capability in
               URL(fileURLWithPath: capability.source.path).pathComponents.contains(sourcePathComponent)
           }) {
            return directMatch
        }

        return candidates.first
    }

    private func sourceCapabilities(
        _ sourceKind: CapabilitySourceClassifier.SourceKind,
        in graph: CapabilityGraph,
        plusSkillsAgentID skillsAgentID: String? = nil
    ) -> [Capability] {
        graph.capabilities
            .filter { capability in
                CapabilitySourceClassifier.sourceKind(for: capability) == sourceKind
                    || skillsAgentID.map { capability.installedThroughSkillsCLI(for: $0) } == true
            }
            .sorted { $0.id < $1.id }
    }

    private func sourceCapabilityIDs(
        _ sourceKind: CapabilitySourceClassifier.SourceKind,
        in graph: CapabilityGraph
    ) -> Set<String> {
        Set(graph.capabilities.compactMap { capability in
            CapabilitySourceClassifier.sourceKind(for: capability) == sourceKind ? capability.id : nil
        })
    }

    private func deduplicatedCapabilities(_ capabilities: [Capability]) -> [Capability] {
        var seenIDs = Set<String>()
        var result: [Capability] = []
        for capability in capabilities where seenIDs.insert(capability.id).inserted {
            result.append(capability)
        }
        return result.sorted { $0.id < $1.id }
    }

    var systemImage: String {
        if id == Self.agents.id {
            return "point.3.connected.trianglepath.dotted"
        }
        if id == Self.codex.id {
            return "command"
        }
        if id == Self.claudeCode.id {
            return "text.bubble"
        }
        if id == Self.cursor.id {
            return "cursorarrow.rays"
        }
        if id == Self.trae.id {
            return "sparkles"
        }
        switch behavior {
        case .agentsSource:
            return "point.3.connected.trianglepath.dotted"
        case .codexSource:
            return "command"
        case .claudeSource:
            return "text.bubble"
        case .cursorSource:
            return "cursorarrow.rays"
        case .traeSource:
            return "sparkles"
        case .codexLike:
            return "command"
        case .claudeLike:
            return "text.bubble"
        case .skillsAgent:
            return "wand.and.stars"
        case .generic:
            return "person.crop.circle"
        }
    }

    var brandIconAssetName: String? {
        if id == Self.codex.id || behavior == .codexSource || behavior == .codexLike || skillsAgentID == "codex" {
            return "codex"
        }
        if id == Self.claudeCode.id || behavior == .claudeSource || behavior == .claudeLike || skillsAgentID == "claude-code" {
            return "claude"
        }
        if id == Self.cursor.id || behavior == .cursorSource || skillsAgentID == "cursor" {
            return "cursor"
        }
        if id == Self.trae.id || behavior == .traeSource || skillsAgentID == "trae" || displayName.localizedCaseInsensitiveContains("trae") {
            return "trae"
        }
        return nil
    }

    private var sourcePathComponent: String? {
        switch skillsInstallAgentID {
        case "codex":
            return ".codex"
        case "claude-code":
            return ".claude"
        case "cursor":
            return ".cursor"
        case "trae":
            return ".trae"
        default:
            return nil
        }
    }
}

private extension Capability {
    func installedThroughSkillsCLI(for agentID: String) -> Bool {
        metadata["skillsInstalledAgentIDs"]?
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .contains(agentID) == true
    }

    func hasSkillsInstallTarget(for agentID: String) -> Bool {
        metadata["skillsInstallTargets"]?
            .split(separator: "\n", omittingEmptySubsequences: true)
            .contains { line in
                line.hasPrefix("\(agentID)=")
            } == true
    }
}

enum CapabilityCategory: String, CaseIterable, Identifiable {
    case all
    case plugin
    case skill
    case agent
    case command
    case mcp
    case hook
    case instruction

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            return "All"
        case .plugin:
            return "Plugins"
        case .skill:
            return "Skills"
        case .agent:
            return "Agents"
        case .command:
            return "Commands"
        case .mcp:
            return "MCP"
        case .hook:
            return "Hooks"
        case .instruction:
            return "Instructions"
        }
    }

    func matches(_ capability: Capability) -> Bool {
        switch self {
        case .all:
            return true
        case .plugin:
            return capability.type == .plugin
        case .skill:
            return capability.type == .skill && capability.pluginID == nil
        case .agent:
            return capability.type == .agent
        case .command:
            return capability.type == .command
        case .mcp:
            return capability.type == .mcpServer
        case .hook:
            return capability.type == .hook
        case .instruction:
            return capability.type == .instruction || capability.type == .rule
        }
    }
}

enum CapabilitySortOrder: String, CaseIterable, Identifiable {
    case name
    case modifiedAt

    var id: String { rawValue }

    var title: String {
        switch self {
        case .name:
            return "Name"
        case .modifiedAt:
            return "Modified"
        }
    }

    var systemImage: String {
        switch self {
        case .name:
            return "textformat"
        case .modifiedAt:
            return "clock"
        }
    }
}

struct CapabilityDisplaySection: Identifiable {
    enum Kind: String, Identifiable {
        case enabled
        case disabled

        var id: String { rawValue }

        var title: String {
            switch self {
            case .enabled:
                return "Enabled"
            case .disabled:
                return "Disabled"
            }
        }
    }

    let kind: Kind
    let items: [CapabilityDisplayItem]
    let capabilityCount: Int

    var id: String { kind.rawValue }
}

enum CapabilityVisuals {
    static func iconName(for type: CapabilityType) -> String {
        switch type {
        case .plugin:
            return "shippingbox"
        case .skill:
            return "wand.and.stars"
        case .agent:
            return "person.2"
        case .mcpServer:
            return "server.rack"
        case .rule:
            return "doc.text"
        case .instruction:
            return "text.book.closed"
        case .hook:
            return "link"
        case .command:
            return "terminal"
        case .unknown:
            return "questionmark.square"
        }
    }

    static func statusColor(for capability: Capability) -> Color {
        if capability.statuses.contains(.broken) { return .red }
        if capability.statuses.contains(.drifted) || capability.statuses.contains(.shadowed) { return .orange }
        if capability.statuses.contains(.risky) { return .yellow }
        return .green
    }

    static func statusLabel(for capability: Capability) -> String {
        var labels: [String] = [
            capability.statuses.contains(.disabled) ? "Disabled" : "Enabled"
        ]

        if capability.statuses.contains(.broken) {
            labels.append("Broken")
        }
        if capability.statuses.contains(.drifted) || capability.statuses.contains(.shadowed) {
            labels.append("Needs attention")
        }
        if capability.statuses.contains(.risky) {
            labels.append("Review needed")
        }
        if capability.statuses.contains(.duplicate) {
            labels.append("Duplicate")
        }

        return labels.joined(separator: ", ")
    }
}

extension AgentID {
    var displayName: String {
        switch self {
        case .codex:
            return "Codex"
        case .claudeCode:
            return "Claude Code"
        case .cursor:
            return "Cursor"
        case .trae:
            return "Trae"
        }
    }
}

extension CapabilityType {
    var displayName: String {
        switch self {
        case .plugin:
            return "Plugin"
        case .skill:
            return "Skill"
        case .agent:
            return "Agent"
        case .mcpServer:
            return "MCP"
        case .rule:
            return "Rule"
        case .instruction:
            return "Instruction"
        case .hook:
            return "Hook"
        case .command:
            return "Command"
        case .unknown:
            return "Unknown"
        }
    }
}
