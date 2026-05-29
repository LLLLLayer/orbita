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
}
