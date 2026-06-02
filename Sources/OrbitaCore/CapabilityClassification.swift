import Foundation

/// Shared capability-classification predicates consumed by BOTH `AgentViewResolver` (per-agent
/// visibility) and `AdapterPreviewBuilder` (per-agent mapping). Each layer previously carried its own
/// private copies, and they had drifted: `isClaudeNative` recognized `claude-plugin` and every
/// `claude-plugin-*` kind in the view, but only `claude-plugin-agent` in the adapter — so a Claude
/// plugin could be reported visible by the view yet `supported: false` in
/// `.orbita/adapters/<agent>/capabilities.json`. Centralizing the predicates here keeps view-visible
/// and preview-supported in agreement by construction.
enum CapabilityClassifier {
    static func sourcePathComponents(for capability: Capability) -> [String] {
        URL(fileURLWithPath: capability.source.path).pathComponents
    }

    static func isClaudeNative(_ capability: Capability) -> Bool {
        let kind = capability.source.kind
        return kind == "claude-skill"
            || kind == "claude-agent"
            || kind == "claude-plugin"
            || kind.hasPrefix("claude-plugin-")
            || sourcePathComponents(for: capability).contains(".claude")
    }

    static func isCodexSkill(_ capability: Capability) -> Bool {
        let kind = capability.source.kind
        if kind == "codex-skill" || kind == "agents-skill" || kind == "user-skill" {
            return true
        }
        if kind == "claude-skill" || kind.hasPrefix("claude-plugin-") {
            return false
        }
        if kind.hasPrefix("agents-") || sourcePathComponents(for: capability).contains(".agents") {
            return true
        }
        return kind == "skill" || sourcePathComponents(for: capability).contains(".codex")
    }

    static func isCodexPluginBundled(_ capability: Capability) -> Bool {
        guard capability.pluginID != nil else { return false }
        return capability.metadata["manager"] == "codex"
            || capability.pluginID?.hasPrefix("plugin:codex-cache:") == true
    }

    /// Whether a `.plugin` capability is one Codex itself loads, as opposed to a Claude Code plugin
    /// group (`claude-plugin` / `claude-plugin-*`), which Codex does not load. Backs both
    /// `AgentViewResolver` codex visibility and `AdapterPreviewBuilder` codex mapping, so a Claude
    /// plugin is never shown on the Codex tab yet reported "Codex loads it" in the preview.
    static func isCodexNativePlugin(_ capability: Capability) -> Bool {
        let kind = capability.source.kind
        return kind != "claude-plugin" && !kind.hasPrefix("claude-plugin-")
    }

    /// A capability that lives in the shared `.agents` workspace. Codex reads these in place,
    /// but the generic SKILL.md hosts (Trae, Cursor) and Claude Code do NOT auto-load `.agents`
    /// — they only see it once it's been synced into their own agent dir or installed for that
    /// agent via the skills CLI.
    static func isAgentsShared(_ capability: Capability) -> Bool {
        // A host-dir symlink the scanner flagged as pointing back into `.agents` counts as shared,
        // so the generic-host view gates it even though its own path is under `.trae`/`.cursor`.
        if capability.metadata["mirrorsAgentsWorkspace"] == "true" { return true }
        let kind = capability.source.kind
        return kind == "agents-skill"
            || kind.hasPrefix("agents-")
            || sourcePathComponents(for: capability).contains(".agents")
    }

    /// Whether the skills CLI recorded this capability as installed for `agentID`
    /// (i.e. the user explicitly synced it to that agent).
    static func isInstalledForSkillsAgent(_ capability: Capability, agentID: String) -> Bool {
        capability.metadata["skillsInstalledAgentIDs"]?
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .contains(agentID) == true
    }

    /// Visibility for the two generic SKILL.md hosts (Trae, Cursor) that read their OWN agent dir
    /// but not the shared `.agents` workspace. A capability is visible when it's been synced/installed
    /// to that agent (a skills-CLI target, or a file physically under the agent dir); shared `.agents`
    /// capabilities of every type are gated out until then. Non-`.agents` skills (generic `user-skill`
    /// / `skill`), MCP servers, instructions and rules keep their prior visibility. Shared by
    /// `AgentViewResolver` (view) and `AdapterPreviewBuilder` (preview) so view-visible and
    /// preview-supported agree by construction.
    static func isVisibleToGenericAgent(_ capability: Capability, agentID: String, agentDirComponent: String) -> Bool {
        // Directory ownership: a record physically under the host's OWN dir is the host's own — even
        // when it is a symlink mirroring `.agents` (`npx skills` bridge, `mirrorsAgentsWorkspace`). The
        // host loads it THROUGH that directory, so it belongs in the host's tab and brand, distinct from
        // the `.agents` canonical that Codex reads in place. Checked first so an own-dir bridge wins over
        // the agents-shared gate below.
        if sourcePathComponents(for: capability).contains(agentDirComponent) { return true }
        // Shared `.agents` content the host does NOT physically hold is managed in the `.agents` tab and
        // is NOT surfaced here — even if a skills-CLI lock lists this agent (that just means the bridge
        // above exists; the canonical itself stays in `.agents`).
        if isAgentsShared(capability) { return false }
        if isInstalledForSkillsAgent(capability, agentID: agentID) { return true }
        switch capability.type {
        case .skill:
            let kind = capability.source.kind
            if isCodexPluginBundled(capability) { return false }
            if kind == "codex-skill" || kind == "claude-skill" || kind.hasPrefix("claude-plugin-") { return false }
            return kind == "user-skill" || kind == "skill"
        case .mcpServer, .instruction, .rule:
            return true
        case .plugin, .agent, .hook, .command, .unknown:
            return false
        }
    }
}
