import Foundation

/// Claude keeps potentially several cached installs of the same plugin, but a session resolves exactly
/// one install per selector. This collapses a capability list to the install Claude would actually load
/// (highest precedence per `pluginSelector`) and drops the shadowed installs and their children.
///
/// This logic was previously duplicated verbatim in `CapabilityResolver` (graph-wide) and
/// `AgentViewResolver` (Claude view). A one-sided edit silently desynced the resolved graph from the
/// Claude view; both now call this single definition.
enum ClaudePluginResolution {
    static func effectiveCapabilities(from capabilities: [Capability]) -> [Capability] {
        let pluginInstalls = capabilities.filter(isInstall)
        guard !pluginInstalls.isEmpty else {
            return capabilities
        }

        let effectivePlugins = Dictionary(grouping: pluginInstalls) { capability in
            capability.metadata["pluginSelector"] ?? capability.id
        }
        .compactMapValues { installs in
            installs.min(by: precedence)
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
               isChild(capability) {
                return false
            }
            return true
        }
    }

    static func isInstall(_ capability: Capability) -> Bool {
        capability.type == .plugin
            && capability.metadata["manager"] == "claude-code"
            && capability.source.kind == "claude-plugin"
            && capability.metadata["pluginSelector"] != nil
    }

    static func isChild(_ capability: Capability) -> Bool {
        capability.metadata["manager"] == "claude-code"
            || capability.source.kind.hasPrefix("claude-plugin-")
    }

    static func precedence(_ lhs: Capability, _ rhs: Capability) -> Bool {
        let lhsScopeRank = scopeRank(lhs)
        let rhsScopeRank = scopeRank(rhs)
        if lhsScopeRank != rhsScopeRank {
            return lhsScopeRank < rhsScopeRank
        }

        let versionComparison = version(lhs).compare(
            version(rhs),
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

    private static func scopeRank(_ capability: Capability) -> Int {
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

    private static func version(_ capability: Capability) -> String {
        capability.metadata["installedVersion"] ?? ""
    }
}
