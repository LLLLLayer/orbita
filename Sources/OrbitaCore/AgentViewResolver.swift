import Foundation

public final class AgentViewResolver {
    public init() {}

    public func view(for agent: AgentID, graph: CapabilityGraph) -> AgentView {
        let visible = graph.capabilities.filter { capability in
            isVisible(capability, to: agent)
        }
        let hidden = graph.capabilities.filter { capability in
            !visible.contains(capability)
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
            || capability.source.kind == "claude-plugin-agent"
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
}
