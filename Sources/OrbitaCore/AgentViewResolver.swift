import Foundation

public final class AgentViewResolver {
    public init() {}

    public func view(for agent: AgentID, graph: CapabilityGraph) -> AgentView {
        var visible = graph.capabilities.filter { capability in
            isVisible(capability, to: agent)
        }
        if agent == .claudeCode {
            visible = claudeEffectiveCapabilities(from: visible)
        }
        let visibleIDs = Set(visible.map(\.id))
        let hidden = graph.capabilities.filter { capability in
            !visibleIDs.contains(capability.id)
        }
        return AgentView(
            projectRoot: graph.projectRoot,
            agent: agent,
            visibleCapabilities: visible.sorted { $0.id < $1.id },
            hiddenCapabilities: hidden.sorted { $0.id < $1.id }
        )
    }

    private func isVisible(_ capability: Capability, to agent: AgentID) -> Bool {
        guard !capability.statuses.contains(.broken) else { return false }
        guard !capability.statuses.contains(.disabled) else { return false }
        switch agent {
        case .codex:
            guard capability.metadata["codexSkillEnabled"] != "false" else { return false }
            switch capability.type {
            case .skill:
                return isCodexSkillCapability(capability)
            case .plugin, .mcpServer, .instruction:
                return true
            case .agent:
                return capability.source.kind == "codex-agent"
            case .hook:
                return capability.source.kind == "codex-hook"
                    || capability.source.kind == "codex-plugin-hook"
            case .command:
                return capability.source.kind == "codex-command"
            case .rule, .unknown:
                return false
            }
        case .claudeCode:
            switch capability.type {
            case .plugin, .skill, .agent:
                return isClaudeNativeCapability(capability)
            case .instruction:
                return true
            case .mcpServer:
                return capability.metadata["claudeMCPEnabled"] != "false"
            case .command:
                return capability.source.kind == "claude-command"
                    || capability.source.kind == "claude-plugin-command"
            case .hook:
                return capability.source.kind == "claude-settings"
                    || capability.source.kind == "claude-settings-hook"
                    || capability.source.kind == "claude-plugin-hook"
            case .rule, .unknown:
                return false
            }
        case .cursor:
            return [.rule, .mcpServer, .instruction].contains(capability.type)
        }
    }

    private func isClaudeNativeCapability(_ capability: Capability) -> Bool {
        capability.source.kind == "claude-skill"
            || capability.source.kind == "claude-agent"
            || capability.source.kind == "claude-plugin"
            || capability.source.kind.hasPrefix("claude-plugin-")
            || sourcePathComponents(for: capability).contains(".claude")
    }

    private func isCodexSkillCapability(_ capability: Capability) -> Bool {
        if capability.source.kind == "codex-skill"
            || capability.source.kind == "agents-skill"
            || capability.source.kind == "user-skill" {
            return true
        }
        if capability.source.kind == "claude-skill" || capability.source.kind.hasPrefix("claude-plugin-") {
            return false
        }
        if capability.source.kind.hasPrefix("agents-") || sourcePathComponents(for: capability).contains(".agents") {
            return true
        }
        return capability.source.kind == "skill" || sourcePathComponents(for: capability).contains(".codex")
    }

    private func sourcePathComponents(for capability: Capability) -> [String] {
        URL(fileURLWithPath: capability.source.path).pathComponents
    }

    private func claudeEffectiveCapabilities(from capabilities: [Capability]) -> [Capability] {
        let pluginInstalls = capabilities.filter(isClaudePluginInstall)
        guard !pluginInstalls.isEmpty else {
            return capabilities
        }

        // Keep the install Claude would resolve at runtime, not every cached copy.
        let effectivePlugins = Dictionary(grouping: pluginInstalls) { capability in
            capability.metadata["pluginSelector"] ?? capability.id
        }
        .compactMapValues { installs in
            installs.min(by: claudePluginPrecedence)
        }

        let effectivePluginIDs = Set(effectivePlugins.values.map(\.id))
        let installedPluginIDs = Set(pluginInstalls.map(\.id))
        let shadowedPluginIDs = installedPluginIDs.subtracting(effectivePluginIDs)

        return capabilities.filter { capability in
            if shadowedPluginIDs.contains(capability.id) {
                return false
            }
            if let pluginID = capability.pluginID,
               shadowedPluginIDs.contains(pluginID),
               isClaudePluginChild(capability) {
                return false
            }
            return true
        }
    }

    private func isClaudePluginInstall(_ capability: Capability) -> Bool {
        capability.type == .plugin
            && capability.metadata["manager"] == "claude-code"
            && capability.source.kind == "claude-plugin"
            && capability.metadata["pluginSelector"] != nil
    }

    private func isClaudePluginChild(_ capability: Capability) -> Bool {
        capability.metadata["manager"] == "claude-code"
            || capability.source.kind.hasPrefix("claude-plugin-")
    }

    private func claudePluginPrecedence(_ lhs: Capability, _ rhs: Capability) -> Bool {
        let lhsScopeRank = claudePluginScopeRank(lhs)
        let rhsScopeRank = claudePluginScopeRank(rhs)
        if lhsScopeRank != rhsScopeRank {
            return lhsScopeRank < rhsScopeRank
        }

        let versionComparison = claudePluginVersion(lhs).compare(
            claudePluginVersion(rhs),
            options: [.caseInsensitive, .numeric]
        )
        if versionComparison != .orderedSame {
            return versionComparison == .orderedDescending
        }

        let lhsUpdated = lhs.metadata["lastUpdated"] ?? lhs.metadata["installedAt"] ?? ""
        let rhsUpdated = rhs.metadata["lastUpdated"] ?? rhs.metadata["installedAt"] ?? ""
        if lhsUpdated != rhsUpdated {
            return lhsUpdated > rhsUpdated
        }

        return lhs.id < rhs.id
    }

    private func claudePluginScopeRank(_ capability: Capability) -> Int {
        switch capability.metadata["managerScope"] ?? capability.scope.rawValue {
        case "managed":
            return 0
        case "local":
            return 1
        case "project":
            return 2
        case "user":
            return 3
        default:
            return 4
        }
    }

    private func claudePluginVersion(_ capability: Capability) -> String {
        capability.metadata["installedVersion"] ?? ""
    }
}
