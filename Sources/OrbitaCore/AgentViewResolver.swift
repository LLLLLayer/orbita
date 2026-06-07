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

    /// The agent(s) whose ecosystem a capability BELONGS to, ignoring its current
    /// enabled/disabled/broken state. This is the structural classification used for the
    /// host **brand icon** — so a disabled or broken tile (e.g. a quarantined Trae skill,
    /// or a Codex skill turned off via `[[skills.config]]`) still shows its origin app
    /// icon, even though it is absent from every agent's *active* view. Distinct from
    /// `visibleCapabilities`, which intentionally excludes disabled/broken tiles.
    public func hostAgentIDs(for capability: Capability) -> [AgentID] {
        AgentID.allCases.filter { classifies(capability, to: $0) }
    }

    private func isVisible(_ capability: Capability, to agent: AgentID) -> Bool {
        guard !capability.statuses.contains(.broken) else { return false }
        guard !capability.statuses.contains(.disabled) else { return false }
        // Per-agent enable-state gates apply to the active view only; host classification
        // (`classifies`) ignores them so the brand icon survives a disabled state.
        switch agent {
        case .codex:
            if capability.metadata["codexSkillEnabled"] == "false" { return false }
        case .claudeCode:
            if capability.type == .mcpServer, capability.metadata["claudeMCPEnabled"] == "false" { return false }
        case .cursor, .trae, .traeCN:
            break
        }
        return classifies(capability, to: agent)
    }

    /// Pure type/source structural classification — no broken/disabled/enable-state gates.
    private func classifies(_ capability: Capability, to agent: AgentID) -> Bool {
        switch agent {
        case .codex:
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
                return true
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
        case .traeCN:
            return isVisibleToTraeCN(capability)
        }
    }

    /// Cursor reads SKILL.md skills, MCP servers, Instructions and Rules from its OWN dirs
    /// (`.cursor/…` / `~/.cursor/skills`) plus anything synced for the cursor agent via the skills
    /// CLI. It does NOT auto-load the shared `.agents` workspace — those appear in Cursor's view
    /// only once synced. See `CapabilityClassifier.isVisibleToGenericAgent`.
    private func isVisibleToCursor(_ capability: Capability) -> Bool {
        CapabilityClassifier.isVisibleToGenericAgent(capability, agentID: "cursor", agentDirComponent: ".cursor")
    }

    /// Trae reads SKILL.md skills, MCP servers and Instructions from its OWN dirs (`.trae/…` /
    /// `~/.trae/skills`) plus anything synced for the trae agent via the skills CLI. Like Cursor it
    /// does NOT auto-load the shared `.agents` workspace — those appear only once synced.
    private func isVisibleToTrae(_ capability: Capability) -> Bool {
        CapabilityClassifier.isVisibleToGenericAgent(capability, agentID: "trae", agentDirComponent: ".trae")
    }

    /// Trae CN (国内版): identical to Trae but reads its own `.traecn` dir. See `isVisibleToTrae`.
    private func isVisibleToTraeCN(_ capability: Capability) -> Bool {
        CapabilityClassifier.isVisibleToGenericAgent(capability, agentID: "trae-cn", agentDirComponent: ".traecn")
    }

    private func isClaudeNativeCapability(_ capability: Capability) -> Bool {
        CapabilityClassifier.isClaudeNative(capability)
    }

    /// Codex sees Codex-native plugins and inferred package plugins, but not
    /// Claude-native ones — even though Claude plugins are also `.plugin` type,
    /// they are not part of Codex's enable surface.
    private func isCodexNativePluginCapability(_ capability: Capability) -> Bool {
        CapabilityClassifier.isCodexNativePlugin(capability)
    }

    private func isCodexSkillCapability(_ capability: Capability) -> Bool {
        CapabilityClassifier.isCodexSkill(capability)
    }
}
