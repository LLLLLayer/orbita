import Foundation

public struct CapabilityGroup: Hashable, Sendable, Identifiable {
    public enum Kind: String, Hashable, Sendable {
        case plugin
        case mirror
        case prefix
    }

    public var id: String
    public var name: String
    public var capabilities: [Capability]
    public var kind: Kind
    public var representative: Capability?

    public var inspectionCapability: Capability {
        representative ?? synthesizedInspectionCapability()
    }

    public init(
        id: String,
        name: String,
        capabilities: [Capability],
        kind: Kind = .prefix,
        representative: Capability? = nil
    ) {
        self.id = id
        self.name = name
        self.capabilities = capabilities
        self.kind = kind
        self.representative = representative
    }

    private func synthesizedInspectionCapability() -> Capability {
        let risks = uniqueRisks(capabilities.flatMap(\.risks))
        let statuses = uniqueStatuses(capabilities.flatMap(\.statuses))
        let sourcePath = commonSourcePath()
        let packageNames = Set(capabilities.compactMap(\.source.packageName))
        let pluginIDs = Set(capabilities.compactMap(\.pluginID))

        return Capability(
            id: id,
            name: name,
            type: groupType(),
            scope: groupScope(),
            statuses: statuses.isEmpty ? [.discovered] : statuses,
            risks: risks.isEmpty ? [.info] : risks,
            source: CapabilitySource(
                kind: virtualSourceKind,
                path: sourcePath,
                packageName: packageNames.count == 1 ? packageNames.first : nil,
                inferred: true
            ),
            pluginID: pluginIDs.count == 1 ? pluginIDs.first : nil,
            summary: groupSummary,
            metadata: [
                "childIDs": capabilities.map(\.id).joined(separator: "\n"),
                "childCount": String(capabilities.count),
                "groupKind": kind.rawValue,
                "sourcePath": sourcePath
            ].filter { !$0.value.isEmpty }
        )
    }

    private func groupType() -> CapabilityType {
        switch kind {
        case .plugin, .prefix:
            return .plugin
        case .mirror:
            let types = Set(capabilities.map(\.type))
            return types.count == 1 ? (types.first ?? .unknown) : .unknown
        }
    }

    private var virtualSourceKind: String {
        switch kind {
        case .plugin, .prefix:
            return "virtual-plugin"
        case .mirror:
            return "virtual-mirror"
        }
    }

    private var groupSummary: String {
        switch kind {
        case .plugin, .prefix:
            return "Virtual plugin group containing \(capabilities.count) capabilities"
        case .mirror:
            return "Mirrored capability group containing \(capabilities.count) matching sources"
        }
    }

    private func groupScope() -> CapabilityScope {
        capabilities
            .map(\.scope)
            .min { scopeRank($0) < scopeRank($1) } ?? .project
    }

    private func commonSourcePath() -> String {
        let paths = capabilities
            .map(\.source.path)
            .filter { !$0.isEmpty }
        guard let firstPath = paths.first else {
            return ""
        }
        guard paths.count > 1 else {
            return parentPath(for: firstPath)
        }

        let componentLists = paths.map { parentPath(for: $0).split(separator: "/", omittingEmptySubsequences: false).map(String.init) }
        var commonComponents: [String] = []
        for index in componentLists[0].indices {
            let component = componentLists[0][index]
            guard componentLists.allSatisfy({ index < $0.count && $0[index] == component }) else {
                break
            }
            commonComponents.append(component)
        }

        let common = commonComponents.joined(separator: "/")
        return common.isEmpty ? parentPath(for: firstPath) : common
    }

    private func parentPath(for path: String) -> String {
        let url = URL(fileURLWithPath: path)
        let lastComponent = url.lastPathComponent
        if lastComponent.contains(".") {
            return url.deletingLastPathComponent().path
        }
        return path
    }

    private func uniqueRisks(_ risks: [RiskLevel]) -> [RiskLevel] {
        Array(Set(risks)).sorted { $0.rawValue < $1.rawValue }
    }

    private func uniqueStatuses(_ statuses: [CapabilityStatus]) -> [CapabilityStatus] {
        Array(Set(statuses)).sorted { $0.rawValue < $1.rawValue }
    }

    private func scopeRank(_ scope: CapabilityScope) -> Int {
        switch scope {
        case .project:
            return 0
        case .user:
            return 1
        case .installed:
            return 2
        case .environment:
            return 3
        }
    }
}

public enum CapabilityDisplayItem: Hashable, Sendable, Identifiable {
    case capability(Capability)
    case group(CapabilityGroup)

    public var id: String {
        switch self {
        case let .capability(capability):
            return capability.id
        case let .group(group):
            return group.id
        }
    }

    public var inspectionCapability: Capability {
        switch self {
        case let .capability(capability):
            return capability
        case let .group(group):
            return group.inspectionCapability
        }
    }

    public var capabilities: [Capability] {
        switch self {
        case let .capability(capability):
            return [capability]
        case let .group(group):
            return group.capabilities
        }
    }
}

public final class CapabilityDisplayGrouper {
    public init() {}

    public func items(
        for capabilities: [Capability],
        minimumGroupSize: Int = 3,
        preservesInputOrder: Bool = false,
        groupsPluginChildren: Bool = true
    ) -> [CapabilityDisplayItem] {
        let sorted = preservesInputOrder ? capabilities : capabilities.sorted(by: sortByName)
        let mirrorGroups = mirrorDisplayGroups(in: sorted, preservesInputOrder: preservesInputOrder)
        let mirroredCapabilityIDs = Set(mirrorGroups.values.flatMap(\.capabilities).map(\.id))
        let pluginCapabilities = groupsPluginChildren ? Dictionary(uniqueKeysWithValues: sorted.compactMap { capability in
            capability.type == .plugin ? (capability.id, capability) : nil
        }) : [:]
        let pluginChildren = groupsPluginChildren ? Dictionary(grouping: sorted.filter { capability in
            capability.type != .plugin && capability.pluginID != nil
        }, by: { $0.pluginID ?? "" }) : [:]

        let pluginGroupIDs = Set(pluginChildren.compactMap { pluginID, children in
            pluginCapabilities[pluginID] != nil || children.count >= minimumGroupSize ? pluginID : nil
        })
        let groupedChildIDs = Set(pluginGroupIDs.flatMap { pluginChildren[$0]?.map(\.id) ?? [] })

        let prefixCandidates = sorted.filter { capability in
            capability.type != .plugin
                && capability.type != .hook
                && !groupedChildIDs.contains(capability.id)
        }
        let grouped = Dictionary(grouping: prefixCandidates, by: groupKey(for:))
        let prefixGroupKeys = Set(grouped.compactMap { key, values in
            Set(values.map(\.name)).count >= minimumGroupSize ? key : nil
        })

        var emittedGroups = Set<String>()
        var items: [CapabilityDisplayItem] = []
        for capability in sorted {
            if capability.type != .plugin,
               capability.type != .hook,
               !groupedChildIDs.contains(capability.id) {
                let key = groupKey(for: capability)
                if prefixGroupKeys.contains(key) {
                    let groupID = "group:\(key)"
                    guard !emittedGroups.contains(groupID), let groupCapabilities = grouped[key] else {
                        continue
                    }
                    emittedGroups.insert(groupID)
                    items.append(.group(CapabilityGroup(
                        id: groupID,
                        name: prefixToken(for: capability),
                        capabilities: groupCapabilities,
                        kind: .prefix
                    )))
                    continue
                }
            }

            if capability.type == .plugin,
               pluginGroupIDs.contains(capability.id),
               let groupCapabilities = pluginChildren[capability.id] {
                let groupID = "plugin-group:\(capability.id)"
                guard !emittedGroups.contains(groupID) else {
                    continue
                }
                emittedGroups.insert(groupID)
                items.append(.group(CapabilityGroup(
                    id: groupID,
                    name: capability.name,
                    capabilities: ordered(groupCapabilities, preservesInputOrder: preservesInputOrder),
                    kind: .plugin,
                    representative: capability
                )))
                continue
            }

            if let pluginID = capability.pluginID,
               pluginGroupIDs.contains(pluginID),
               pluginCapabilities[pluginID] == nil,
               let groupCapabilities = pluginChildren[pluginID] {
                let groupID = "plugin-group:\(pluginID)"
                guard !emittedGroups.contains(groupID) else {
                    continue
                }
                emittedGroups.insert(groupID)
                items.append(.group(CapabilityGroup(
                    id: groupID,
                    name: pluginDisplayName(for: capability),
                    capabilities: ordered(groupCapabilities, preservesInputOrder: preservesInputOrder),
                    kind: .plugin
                )))
                continue
            }

            if groupedChildIDs.contains(capability.id) {
                continue
            }

            if let mirrorGroup = mirrorGroups[capability.id] {
                guard !emittedGroups.contains(mirrorGroup.id) else {
                    continue
                }
                emittedGroups.insert(mirrorGroup.id)
                items.append(.group(mirrorGroup))
                continue
            }

            if mirroredCapabilityIDs.contains(capability.id) {
                continue
            }

            if capability.type == .plugin {
                items.append(.capability(capability))
                continue
            }

            if capability.type == .hook {
                items.append(.capability(capability))
                continue
            }

            items.append(.capability(capability))
        }
        return items
    }

    private func mirrorDisplayGroups(
        in capabilities: [Capability],
        preservesInputOrder: Bool
    ) -> [String: CapabilityGroup] {
        var remaining = capabilities
        var groups: [CapabilityGroup] = []

        for grouping in [mirrorPathKey(for:), mirrorHashKey(for:)] {
            let candidates = Dictionary(grouping: remaining, by: grouping)
                .filter { entry in
                    entry.key != nil && entry.value.count > 1
                }
            let emittedIDs = Set(candidates.values.flatMap { $0.map(\.id) })
            groups.append(contentsOf: candidates.compactMap { entry in
                guard let key = entry.key else { return nil }
                let values = entry.value
                let orderedValues = ordered(values, preservesInputOrder: preservesInputOrder)
                return CapabilityGroup(
                    id: "mirror-group:\(key)",
                    name: mirrorGroupName(for: orderedValues),
                    capabilities: orderedValues,
                    kind: .mirror
                )
            })
            remaining.removeAll { emittedIDs.contains($0.id) }
        }

        var byCapabilityID: [String: CapabilityGroup] = [:]
        for group in groups {
            for capability in group.capabilities {
                byCapabilityID[capability.id] = group
            }
        }
        return byCapabilityID
    }

    private func mirrorPathKey(for capability: Capability) -> String? {
        guard !capability.source.inferred, !capability.source.path.isEmpty else {
            return nil
        }
        let resolvedPath = URL(fileURLWithPath: capability.source.path)
            .standardizedFileURL
            .resolvingSymlinksInPath()
            .path
        return "path:\(capability.type.rawValue):\(hookHostMirrorComponent(for: capability)):\(resolvedPath)"
    }

    private func mirrorHashKey(for capability: Capability) -> String? {
        guard let hash = capability.metadata["contentHash"], !hash.isEmpty else {
            return nil
        }
        return "hash:\(capability.type.rawValue):\(hookHostMirrorComponent(for: capability)):\(hash)"
    }

    private func hookHostMirrorComponent(for capability: Capability) -> String {
        guard capability.type == .hook else { return "" }
        let host = capability.metadata["handlerHost"] ?? hookHostFromName(capability.name)
        return normalized(host)
    }

    private func hookHostFromName(_ name: String) -> String {
        guard let separator = name.range(of: " - ") else {
            return name
        }
        return String(name[..<separator.lowerBound])
    }

    private func mirrorGroupName(for capabilities: [Capability]) -> String {
        let names = uniquePreservingOrder(capabilities.map(\.name))
        guard let first = names.first else {
            return "Mirrored capability"
        }
        return names.count == 1 ? first : "\(first) + \(names.count - 1)"
    }

    /// Prefix groups never span agent directories. A skill that physically lives in `.agents/skills`
    /// and its `npx skills` symlink bridge under `.trae/skills` (or `.claude`/`.cursor`) are owned by
    /// different agents, so they form SEPARATE prefix tiles — each branded by its own directory's
    /// loader — instead of merging into one inflated "N copies" count (e.g. `lark` showing 50 in the
    /// Overview when it is really 25 canonical + 25 bridge). The group display name stays the bare
    /// prefix (`lark`); only the grouping/identity key carries the owner bucket.
    private func groupKey(for capability: Capability) -> String {
        "\(ownerBucket(for: capability))\u{1}\(prefixToken(for: capability))"
    }

    /// The agent-directory a capability physically lives under (`.agents`/`.codex`/`.claude`/`.cursor`
    /// /`.trae`), or `""` for anything outside a recognized agent dir — which keeps its prior grouping
    /// behavior untouched (one shared bucket).
    private func ownerBucket(for capability: Capability) -> String {
        guard !capability.source.path.isEmpty else { return "" }
        let components = Set(URL(fileURLWithPath: capability.source.path).pathComponents)
        for marker in [".agents", ".codex", ".claude", ".cursor", ".trae"] where components.contains(marker) {
            return marker
        }
        return ""
    }

    /// The shared name prefix (text before the first interior `-`), e.g. `lark` for `lark-doc`. This is
    /// the group's display name; the grouping key composes it with `ownerBucket`.
    private func prefixToken(for capability: Capability) -> String {
        let name = capability.name
        guard let separator = name.firstIndex(of: "-"), separator > name.startIndex else {
            return name
        }
        return String(name[..<separator])
    }

    private func sortByName(_ lhs: Capability, _ rhs: Capability) -> Bool {
        lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
    }

    private func ordered(_ capabilities: [Capability], preservesInputOrder: Bool) -> [Capability] {
        preservesInputOrder ? capabilities : capabilities.sorted(by: sortByName)
    }

    private func pluginDisplayName(for capability: Capability) -> String {
        guard let packageName = capability.source.packageName else {
            return prefixToken(for: capability)
        }
        let raw = packageName.split(separator: "/").last.map(String.init) ?? packageName
        let trimmed = raw
            .replacingOccurrences(of: "-skills", with: "")
            .replacingOccurrences(of: "-plugin", with: "")
            .replacingOccurrences(of: "agent-", with: "")
        return trimmed
            .split(separator: "-")
            .map { word in word.prefix(1).uppercased() + String(word.dropFirst()) }
            .joined(separator: " ")
    }

    private func uniquePreservingOrder(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for value in values where !seen.contains(value) {
            seen.insert(value)
            result.append(value)
        }
        return result
    }
}
