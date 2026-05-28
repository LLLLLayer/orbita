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
    static let defaultAgents = [agents, codex, claudeCode, cursor, trae]

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
        switch behavior {
        case .agentsSource:
            return sourceCapabilities(.agents, in: graph)
        case .codexSource:
            return AgentViewResolver().view(for: .codex, graph: graph).visibleCapabilities
        case .claudeSource:
            return AgentViewResolver().view(for: .claudeCode, graph: graph).visibleCapabilities
        case .cursorSource:
            return AgentViewResolver().view(for: .cursor, graph: graph).visibleCapabilities
        case .traeSource:
            return AgentViewResolver().view(for: .trae, graph: graph).visibleCapabilities
        case .codexLike:
            return AgentViewResolver().view(for: .codex, graph: graph).visibleCapabilities
        case .claudeLike:
            return AgentViewResolver().view(for: .claudeCode, graph: graph).visibleCapabilities
        case .skillsAgent:
            guard let skillsAgentID else {
                return []
            }
            return graph.capabilities
                .filter { capability in
                    !capability.statuses.contains(.broken)
                        && !capability.statuses.contains(.disabled)
                        && capability.installedThroughSkillsCLI(for: skillsAgentID)
                }
                .sorted { $0.id < $1.id }
        case .generic:
            return graph.capabilities
                .filter { capability in
                    !capability.statuses.contains(.broken)
                        && !capability.statuses.contains(.disabled)
                }
                .sorted { $0.id < $1.id }
        }
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
}

private extension Capability {
    func installedThroughSkillsCLI(for agentID: String) -> Bool {
        metadata["skillsInstalledAgentIDs"]?
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .contains(agentID) == true
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
