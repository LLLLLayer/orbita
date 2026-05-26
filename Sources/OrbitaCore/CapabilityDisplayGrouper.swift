import Foundation

public struct CapabilityGroup: Hashable, Sendable, Identifiable {
    public enum Kind: String, Hashable, Sendable {
        case plugin
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
            type: .plugin,
            scope: groupScope(),
            statuses: statuses.isEmpty ? [.discovered] : statuses,
            risks: risks.isEmpty ? [.info] : risks,
            source: CapabilitySource(
                kind: "virtual-plugin",
                path: sourcePath,
                packageName: packageNames.count == 1 ? packageNames.first : nil,
                inferred: true
            ),
            pluginID: pluginIDs.count == 1 ? pluginIDs.first : nil,
            summary: "Virtual plugin group containing \(capabilities.count) capabilities",
            metadata: [
                "childIDs": capabilities.map(\.id).joined(separator: "\n"),
                "childCount": String(capabilities.count),
                "groupKind": kind.rawValue,
                "sourcePath": sourcePath
            ].filter { !$0.value.isEmpty }
        )
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
}

public final class CapabilityDisplayGrouper {
    public init() {}

    public func items(
        for capabilities: [Capability],
        minimumGroupSize: Int = 3,
        preservesInputOrder: Bool = false
    ) -> [CapabilityDisplayItem] {
        let sorted = preservesInputOrder ? capabilities : capabilities.sorted(by: sortByName)
        let pluginCapabilities = Dictionary(uniqueKeysWithValues: sorted.compactMap { capability in
            capability.type == .plugin ? (capability.id, capability) : nil
        })
        let pluginChildren = Dictionary(grouping: sorted.filter { capability in
            capability.type != .plugin && capability.pluginID != nil
        }, by: { $0.pluginID ?? "" })

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
            values.count >= minimumGroupSize ? key : nil
        })

        var emittedGroups = Set<String>()
        var items: [CapabilityDisplayItem] = []
        for capability in sorted {
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

            if capability.type == .plugin {
                items.append(.capability(capability))
                continue
            }

            if capability.type == .hook {
                items.append(.capability(capability))
                continue
            }

            let key = groupKey(for: capability)
            if prefixGroupKeys.contains(key) {
                guard !emittedGroups.contains(key), let groupCapabilities = grouped[key] else {
                    continue
                }
                emittedGroups.insert(key)
                items.append(.group(CapabilityGroup(
                    id: "group:\(key)",
                    name: key,
                    capabilities: groupCapabilities,
                    kind: .prefix
                )))
            } else {
                items.append(.capability(capability))
            }
        }
        return items
    }

    private func groupKey(for capability: Capability) -> String {
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
            return groupKey(for: capability)
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
}
