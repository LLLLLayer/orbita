import Foundation

public final class AgentViewResolver {
    public init() {}

    public func view(for agent: AgentID, graph: CapabilityGraph) -> AgentView {
        let visible = visibleCapabilities(for: agent, graph: graph)
        let visibleIDs = Set(visible.map(\.id))
        let hidden = graph.capabilities
            .filter { !visibleIDs.contains($0.id) }
            .sorted { $0.id < $1.id }
        return AgentView(
            projectRoot: graph.projectRoot,
            agent: agent,
            visibleCapabilities: visible,
            hiddenCapabilities: hidden
        )
    }

    /// Visible-only fast path. The App's per-agent tabs only ever consume the
    /// visible list, so this skips computing and sorting the (unused) hidden
    /// set — roughly halving the per-call cost on the tab-switch hot path.
    /// `view(for:graph:)` reuses this for the visible half.
    public func visibleCapabilities(for agent: AgentID, graph: CapabilityGraph) -> [Capability] {
        var visible = graph.capabilities.filter { capability in
            isVisible(capability, to: agent)
        }
        if agent == .claudeCode {
            visible = ClaudePluginResolution.effectiveCapabilities(from: visible)
        }
        return visible.sorted { $0.id < $1.id }
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
            case .plugin:
                return isCodexNativePluginCapability(capability)
            case .mcpServer, .instruction:
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
            return isVisibleToCursor(capability)
        case .trae:
            return isVisibleToTrae(capability)
        }
    }

    /// Cursor loads SKILL.md-based skills, MCP servers, Instructions and Rules. Like Trae, it additionally
    /// surfaces anything installed via `npx skills` for the cursor agent ID and anything physically under
    /// `.cursor/`, so its view matches the SkillsAgentCatalog claim (and the App's skills-CLI union) that
    /// Cursor loads `.agents/skills` / `~/.cursor/skills` — keeping core and App in agreement after a fork.
    private func isVisibleToCursor(_ capability: Capability) -> Bool {
        if capability.metadata["skillsInstalledAgentIDs"]?
            .split(separator: ",")
            .map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) })
            .contains("cursor") == true {
            return true
        }
        if sourcePathComponents(for: capability).contains(".cursor") {
            return true
        }
        switch capability.type {
        case .skill:
            let kind = capability.source.kind
            if isCodexPluginBundledCapability(capability) {
                return false
            }
            if kind == "codex-skill" || kind == "claude-skill" || kind.hasPrefix("claude-plugin-") {
                return false
            }
            return kind == "agents-skill"
                || kind == "user-skill"
                || kind == "skill"
                || sourcePathComponents(for: capability).contains(".agents")
        case .mcpServer, .instruction, .rule:
            return true
        case .plugin, .agent, .hook, .command, .unknown:
            return false
        }
    }

    /// Trae reads SKILL.md-based skills, MCP servers and Instructions like
    /// Cursor does. We additionally surface anything explicitly installed via
    /// `npx skills` for the trae agent ID, plus capabilities physically
    /// living under `.trae/` (project or global), so Trae's view tracks
    /// what its CLI actually touches.
    private func isVisibleToTrae(_ capability: Capability) -> Bool {
        if capability.metadata["skillsInstalledAgentIDs"]?
            .split(separator: ",")
            .map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) })
            .contains("trae") == true {
            return true
        }
        if sourcePathComponents(for: capability).contains(".trae") {
            return true
        }
        switch capability.type {
        case .skill:
            // Trae picks up shared `.agents/skills` and user-scope skills the
            // way other generic agents do, but it does not get Codex- or
            // Claude-native ones.
            let kind = capability.source.kind
            if isCodexPluginBundledCapability(capability) {
                return false
            }
            if kind == "codex-skill" || kind == "claude-skill" || kind.hasPrefix("claude-plugin-") {
                return false
            }
            return kind == "agents-skill"
                || kind == "user-skill"
                || kind == "skill"
                || sourcePathComponents(for: capability).contains(".agents")
        case .mcpServer, .instruction, .rule:
            return true
        case .plugin, .agent, .hook, .command, .unknown:
            return false
        }
    }

    private func isClaudeNativeCapability(_ capability: Capability) -> Bool {
        CapabilityClassifier.isClaudeNative(capability)
    }

    /// Codex sees Codex-native plugins and inferred package plugins, but not
    /// Claude-native ones — even though Claude plugins are also `.plugin` type,
    /// they are not part of Codex's enable surface.
    private func isCodexNativePluginCapability(_ capability: Capability) -> Bool {
        let kind = capability.source.kind
        if kind == "claude-plugin" || kind.hasPrefix("claude-plugin-") {
            return false
        }
        return true
    }

    private func isCodexSkillCapability(_ capability: Capability) -> Bool {
        CapabilityClassifier.isCodexSkill(capability)
    }

    private func isCodexPluginBundledCapability(_ capability: Capability) -> Bool {
        CapabilityClassifier.isCodexPluginBundled(capability)
    }

    private func sourcePathComponents(for capability: Capability) -> [String] {
        CapabilityClassifier.sourcePathComponents(for: capability)
    }

}
