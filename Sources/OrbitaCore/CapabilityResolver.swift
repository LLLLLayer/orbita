import Foundation

public final class CapabilityResolver {
    public init() {}

    public func resolve(scanResult: ScanResult) -> CapabilityGraph {
        var capabilities = scanResult.capabilities.filter { $0.source.kind != "agents-intent" }
        applyAgentsIntent(from: scanResult.capabilities, to: &capabilities)
        capabilities.append(contentsOf: inferredPlugins(from: capabilities))
        capabilities = deduplicatedCapabilities(capabilities)
        capabilities = ClaudePluginResolution.effectiveCapabilities(from: capabilities)
        markDuplicates(in: &capabilities)
        markShadowedAndDrifted(in: &capabilities)

        return CapabilityGraph(
            projectRoot: scanResult.projectRoot,
            capabilities: capabilities.sorted { $0.id < $1.id },
            issues: scanResult.issues
        )
    }

    private func applyAgentsIntent(from scannedCapabilities: [Capability], to capabilities: inout [Capability]) {
        let intents = scannedCapabilities.filter { $0.source.kind == "agents-intent" }
        guard !intents.isEmpty else { return }

        for intent in intents {
            guard let capabilityID = intent.metadata["capabilityID"],
                  let manifestStatus = intent.metadata["manifestStatus"] else {
                continue
            }
            guard let status = CapabilityStatus(rawValue: manifestStatus) else {
                continue
            }

            let sourcePath = intent.metadata["sourcePath"]
            if let index = capabilities.firstIndex(where: { $0.id == capabilityID || $0.source.path == sourcePath }) {
                appendStatus(status, to: &capabilities[index])
                capabilities[index].metadata["manifestStatus"] = manifestStatus
                if status == .disabled {
                    appendStatus(.drifted, to: &capabilities[index])
                    capabilities[index].metadata["driftReason"] = "disabled in .agents but source remains discoverable"
                }
            } else {
                var missingIntent = intent
                missingIntent.id = capabilityID
                missingIntent.statuses = status == .disabled ? [.disabled] : [status, .broken]
                missingIntent.source = CapabilitySource(kind: "agents-intent-missing-source", path: intent.source.path)
                missingIntent.metadata["manifestStatus"] = manifestStatus
                capabilities.append(missingIntent)
            }
        }
    }

    private func inferredPlugins(from capabilities: [Capability]) -> [Capability] {
        let existingPluginIDs = Set(capabilities.filter { $0.type == .plugin }.map(\.id))
        let grouped = Dictionary(grouping: capabilities.compactMap { capability -> (String, Capability)? in
            guard let pluginID = capability.pluginID, let packageName = capability.source.packageName else {
                return nil
            }
            guard !existingPluginIDs.contains(pluginID) else {
                return nil
            }
            return (pluginID + "|" + packageName, capability)
        }, by: { $0.0 })

        return grouped.map { key, values in
            let parts = key.split(separator: "|", maxSplits: 1).map(String.init)
            let pluginID = parts[0]
            let packageName = parts.count > 1 ? parts[1] : pluginID
            let children = values.map(\.1)
            let risks = uniqueRisks(children.flatMap(\.risks))
            let displayName = pluginDisplayName(packageName)
            let sourcePath = children.first?.source.path ?? packageName
            let scope = children.map(\.scope).min { lhs, rhs in
                scopeRank(lhs) < scopeRank(rhs)
            } ?? .project

            return Capability(
                id: pluginID,
                name: displayName,
                type: .plugin,
                scope: scope,
                statuses: [.discovered],
                risks: risks.isEmpty ? [.info] : risks,
                source: CapabilitySource(kind: "package", path: packageRootPath(from: sourcePath, packageName: packageName), packageName: packageName, inferred: true),
                summary: "Inferred plugin from \(children.count) capabilities",
                metadata: ["childCount": String(children.count)]
            )
        }
    }

    private enum DuplicateRelationship: String {
        case linkedMirror = "linked-mirror"
        case copiedMirror = "copied-mirror"
        case conflicting = "conflicting"
    }

    /// Grouping key for duplicate / shadow detection. Codex and Claude Code run
    /// independent native plugin systems, so the same marketplace plugin
    /// installed for each agent is expected — not a conflict. Native plugins are
    /// therefore scoped by ecosystem, so a `codex-plugin` and a `claude-plugin`
    /// sharing a name are never treated as duplicates/shadows of each other.
    /// Skills are genuinely shared across agents via `.agents` (linked/copied
    /// mirrors), so every non-plugin type keeps cross-agent grouping.
    private func duplicateGroupingKey(for capability: Capability) -> String {
        let base = "\(capability.type.rawValue):\(normalized(capability.name))"
        guard capability.type == .plugin else { return base }
        return "\(pluginEcosystem(for: capability)):\(base)"
    }

    private func pluginEcosystem(for capability: Capability) -> String {
        let kind = capability.source.kind
        if kind.hasPrefix("codex") { return "codex" }
        if kind.hasPrefix("claude") { return "claude" }
        if let manager = capability.metadata["manager"], !manager.isEmpty { return manager }
        return "plugin"
    }

    private func markDuplicates(in capabilities: inout [Capability]) {
        let grouped = Dictionary(grouping: capabilities.indices) { index in
            duplicateGroupingKey(for: capabilities[index])
        }

        for indices in grouped.values where indices.count > 1 {
            let group = indices.map { capabilities[$0] }
            let relationship = duplicateRelationship(for: group)
            // A shared name alone is not enough to call two capabilities "conflicting duplicates":
            // two unrelated skills both named "helper" from different packages legitimately coexist.
            // Only flag a conflicting group when there is corroborating evidence of a real relationship
            // (same package, shared resolved path, or shared content hash). Linked/copied mirrors are
            // corroborated by construction (same path / same hash) and are never suppressed here.
            if relationship == .conflicting, groupLikelyUnrelated(group) {
                continue
            }
            for index in indices {
                if relationship != .linkedMirror, !capabilities[index].statuses.contains(.duplicate) {
                    capabilities[index].statuses.append(.duplicate)
                }
                let duplicates = indices
                    .filter { $0 != index }
                    .map { capabilities[$0] }
                capabilities[index].metadata["duplicateCount"] = String(indices.count)
                capabilities[index].metadata["duplicateRelationship"] = relationship.rawValue
                capabilities[index].metadata["duplicateSources"] = duplicates
                    .map(duplicateSourceDescription)
                    .joined(separator: "\n")
                capabilities[index].metadata["duplicateDetail"] = duplicateDetail(
                    for: capabilities[index],
                    duplicates: duplicates,
                    relationship: relationship
                )
            }
        }
    }

    private func duplicateRelationship(for capabilities: [Capability]) -> DuplicateRelationship {
        let resolvedPaths = Set(capabilities.map { resolvedSourcePath($0.source.path) })
        if resolvedPaths.count == 1 {
            return .linkedMirror
        }

        let knownHashes = capabilities.compactMap { $0.metadata["contentHash"] }.filter { !$0.isEmpty }
        if knownHashes.count == capabilities.count, Set(knownHashes).count == 1 {
            return .copiedMirror
        }

        return .conflicting
    }

    /// True when a same-name group is most likely a coincidental name clash rather than a real
    /// duplicate/mirror: its members come from two or more distinct packages (pluginIDs) AND share
    /// neither a resolved source path nor a content hash. Same-package or standalone (no pluginID)
    /// groups, and any group with a shared path/hash, are treated as genuinely related.
    private func groupLikelyUnrelated(_ capabilities: [Capability]) -> Bool {
        let distinctPluginIDs = Set(capabilities.compactMap { $0.pluginID })
        guard distinctPluginIDs.count >= 2 else { return false }
        let paths = capabilities.map { resolvedSourcePath($0.source.path) }
        if Set(paths).count < paths.count { return false }
        let hashes = capabilities.compactMap { $0.metadata["contentHash"] }.filter { !$0.isEmpty }
        if Set(hashes).count < hashes.count { return false }
        return true
    }

    private func duplicateDetail(
        for capability: Capability,
        duplicates: [Capability],
        relationship: DuplicateRelationship
    ) -> String {
        let sourceList = duplicates.map(duplicateSourceDescription)
        switch relationship {
        case .linkedMirror:
            return "Linked mirror: \(sourceList.joined(separator: "; ")) resolves to the same source. This is expected for symlink-based installs."
        case .copiedMirror:
            if capability.source.kind == "claude-skill",
               duplicates.contains(where: { $0.source.kind == "agents-skill" }) {
                return "Copied mirror: Claude Code has a separate copy of the shared .agents skill at \(sourceList.joined(separator: "; ")). Updates can drift because these files are not linked."
            }
            if capability.source.kind == "agents-skill",
               duplicates.contains(where: { $0.source.kind == "claude-skill" }) {
                return "Copied mirror: this shared .agents skill was also copied into Claude Code at \(sourceList.joined(separator: "; ")). Prefer a symlink or a single source of truth to avoid drift."
            }
            return "Copied mirror: also found at \(sourceList.joined(separator: "; ")). Updates can drift because these files are separate copies."
        case .conflicting:
            break
        }

        if capability.source.kind == "claude-skill",
           duplicates.contains(where: { $0.source.kind == "agents-skill" }) {
            return "Conflicting duplicate: Claude Code also sees a .agents skill named the same at \(sourceList.joined(separator: "; ")), but the content differs."
        }
        if capability.source.kind == "agents-skill",
           duplicates.contains(where: { $0.source.kind == "claude-skill" }) {
            return "Conflicting duplicate: this .agents skill shares a name with a Claude Code skill at \(sourceList.joined(separator: "; ")), but the content differs."
        }
        return "Conflicting duplicate: also found at \(sourceList.joined(separator: "; "))."
    }

    private func duplicateSourceDescription(_ capability: Capability) -> String {
        "\(duplicateSourceLabel(for: capability.source.kind)) \(displayPath(capability.source.path))"
    }

    private func duplicateSourceLabel(for sourceKind: String) -> String {
        switch sourceKind {
        case "agents-skill":
            return ".agents skill"
        case "claude-skill":
            return "Claude Code skill"
        case "codex-plugin":
            return "Codex plugin"
        case "claude-plugin":
            return "Claude Code plugin"
        default:
            return sourceKind
        }
    }

    private func displayPath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(home + "/") {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }

    private func resolvedSourcePath(_ path: String) -> String {
        URL(fileURLWithPath: path)
            .standardizedFileURL
            .resolvingSymlinksInPath()
            .path
    }

    private func deduplicatedCapabilities(_ capabilities: [Capability]) -> [Capability] {
        var seenIDs: Set<String> = []
        var result: [Capability] = []
        for capability in capabilities.sorted(by: { lhs, rhs in
            if lhs.id == rhs.id {
                return statusRank(lhs) < statusRank(rhs)
            }
            return lhs.id < rhs.id
        }) {
            guard !seenIDs.contains(capability.id) else { continue }
            seenIDs.insert(capability.id)
            result.append(capability)
        }
        return result
    }

    private func statusRank(_ capability: Capability) -> Int {
        if capability.statuses.contains(.enabled) { return 0 }
        if capability.statuses.contains(.disabled) { return 1 }
        return 2
    }

    private func markShadowedAndDrifted(in capabilities: inout [Capability]) {
        let grouped = Dictionary(grouping: capabilities.indices) { index in
            duplicateGroupingKey(for: capabilities[index])
        }

        for indices in grouped.values where indices.count > 1 {
            let winner = indices.min { lhs, rhs in
                scopeRank(capabilities[lhs].scope) < scopeRank(capabilities[rhs].scope)
            }
            let ranks = Set(indices.map { scopeRank(capabilities[$0].scope) })
            let resolvedPaths = Set(indices.map { resolvedSourcePath(capabilities[$0].source.path) })
            let shouldMarkShadowed = ranks.count > 1 && resolvedPaths.count > 1

            for index in indices where index != winner && shouldMarkShadowed {
                appendStatus(.shadowed, to: &capabilities[index])
            }

            let hashes = Set(indices.compactMap { capabilities[$0].metadata["contentHash"] }.filter { !$0.isEmpty })
            if hashes.count > 1, !groupLikelyUnrelated(indices.map { capabilities[$0] }) {
                for index in indices {
                    appendStatus(.drifted, to: &capabilities[index])
                }
            }
        }
    }

    private func appendStatus(_ status: CapabilityStatus, to capability: inout Capability) {
        if !capability.statuses.contains(status) {
            capability.statuses.append(status)
        }
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

    private func uniqueRisks(_ risks: [RiskLevel]) -> [RiskLevel] {
        Array(Set(risks)).sorted { $0.rawValue < $1.rawValue }
    }

    private func pluginDisplayName(_ packageName: String) -> String {
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

    private func packageRootPath(from sourcePath: String, packageName: String) -> String {
        if let range = sourcePath.range(of: "/node_modules/\(packageName)") {
            return String(sourcePath[..<range.upperBound])
        }

        if let range = sourcePath.range(of: "/.codex/plugins/cache/") {
            let prefix = sourcePath[..<range.upperBound]
            let suffix = sourcePath[range.upperBound...].split(separator: "/")
            guard suffix.count >= 2 else {
                return sourcePath
            }
            return String(prefix) + String(suffix[0]) + "/" + String(suffix[1])
        }

        return sourcePath
    }
}
