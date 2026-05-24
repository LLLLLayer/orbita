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
            switch capability.type {
            case .plugin, .skill, .mcpServer, .instruction:
                return true
            case .hook:
                return capability.source.kind == "codex-hook"
            case .command:
                return capability.source.kind == "codex-command"
            case .rule, .unknown:
                return false
            }
        case .claudeCode:
            switch capability.type {
            case .plugin, .skill:
                return isClaudeNativeCapability(capability) || isSharedAgentsCapability(capability)
            case .mcpServer, .instruction:
                return true
            case .command:
                return capability.source.kind == "claude-command"
            case .hook:
                return capability.source.kind == "claude-settings"
            case .rule, .unknown:
                return false
            }
        case .cursor:
            return [.rule, .mcpServer, .instruction].contains(capability.type)
        }
    }

    private func isClaudeNativeCapability(_ capability: Capability) -> Bool {
        capability.source.kind == "claude-skill" || sourcePathComponents(for: capability).contains(".claude")
    }

    private func isSharedAgentsCapability(_ capability: Capability) -> Bool {
        capability.source.kind.hasPrefix("agents-") || sourcePathComponents(for: capability).contains(".agents")
    }

    private func sourcePathComponents(for capability: Capability) -> [String] {
        URL(fileURLWithPath: capability.source.path).pathComponents
    }
}
