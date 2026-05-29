import Foundation

/// Whether a capability can be force-installed ("forked") into a given agent's directory, and via which
/// file types. This is product policy shared by the Apply planner — which enforces it and throws on a
/// violation — and the App, which greys out incompatible agents in the sync sheet. It previously existed
/// as two independent copies (`ApplyPlanBuilder.isDirectSyncCompatible` and the App's
/// `syncCapability(_:isCompatibleWith:)`) that had already drifted in their extension lists; this is the
/// single definition both now call.
public enum AgentSyncPolicy {
    public static func isCompatible(capability: Capability, agentID: String) -> Bool {
        switch capability.type {
        case .skill:
            return true
        case .command, .agent:
            let sourcePath = capability.metadata["sourcePath"] ?? capability.source.path
            let ext = URL(fileURLWithPath: sourcePath).pathExtension.lowercased()
            if agentID == "claude-code" {
                return ext == "md"
            }
            if agentID == "codex" {
                return ["md", "json", "toml"].contains(ext)
            }
            return false
        case .plugin, .mcpServer, .rule, .instruction, .hook, .unknown:
            return false
        }
    }
}
