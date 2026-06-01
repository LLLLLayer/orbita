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
                // A quarantine tile (reconstructed from the disabled store) is cleanly disabled — its source
                // was moved aside, so the "source remains discoverable" drift does NOT apply. Only mark drift
                // when the matched capability is a live, still-discoverable source.
                if status == .disabled, capabilities[index].source.kind != "orbita-quarantine" {
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
            // A broken/dangling member (e.g. a project `.trae/skills/x → ../../.agents/skills/x` whose
            // target is missing because the repo has no project-level `.agents/skills`) carries no real
            // second copy — only an unresolved path. Letting it into the comparison flips an otherwise
            // clean linked mirror into a "conflicting duplicate" and pins duplicate/shadowed badges on its
            // healthy siblings. Decide the relationship over the live members only; the broken tile stays
            // surfaced as [.broken] on its own, just unflagged.
            let liveIndices = indices.filter { !capabilities[$0].statuses.contains(.broken) }
            guard liveIndices.count > 1 else { continue }
            let group = liveIndices.map { capabilities[$0] }
            let relationship = duplicateRelationship(for: group)
            // A shared name alone is not enough to call two capabilities "conflicting duplicates":
            // two unrelated skills both named "helper" from different packages legitimately coexist.
            // Only flag a conflicting group when there is corroborating evidence of a real relationship
            // (same package, shared resolved path, or shared content hash). Linked/copied mirrors are
            // corroborated by construction (same path / same hash) and are never suppressed here.
            if relationship == .conflicting, groupLikelyUnrelated(group) {
                continue
            }
            for index in liveIndices {
                if relationship != .linkedMirror, !capabilities[index].statuses.contains(.duplicate) {
                    capabilities[index].statuses.append(.duplicate)
                }
                let duplicates = liveIndices
                    .filter { $0 != index }
                    .map { capabilities[$0] }
                capabilities[index].metadata["duplicateCount"] = String(liveIndices.count)
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
            // Broken/dangling members neither shadow nor drift their healthy siblings — a missing
            // symlink target is not a competing copy. Decide over live members only (mirrors the
            // same carve-out in `markDuplicates`), so the broken tile can't become the scope "winner"
            // or manufacture a phantom second location.
            let liveIndices = indices.filter { !capabilities[$0].statuses.contains(.broken) }
            guard liveIndices.count > 1 else { continue }

            let winner = liveIndices.min { lhs, rhs in
                scopeRank(capabilities[lhs].scope) < scopeRank(capabilities[rhs].scope)
            }
            let ranks = Set(liveIndices.map { scopeRank(capabilities[$0].scope) })
            let resolvedPaths = Set(liveIndices.map { resolvedSourcePath(capabilities[$0].source.path) })
            let isLinkedMirror = resolvedPaths.count == 1
            let shouldMarkShadowed = ranks.count > 1 && resolvedPaths.count > 1

            for index in liveIndices where index != winner && shouldMarkShadowed {
                appendStatus(.shadowed, to: &capabilities[index])
            }

            // A linked mirror is the SAME real file reached through several agent dirs, so a content-hash
            // difference between its members is a scanner artifact — e.g. the `agents-skill` whole-directory
            // hash vs the `claude-skill`/`trae-skill` hash of the symlinked-to dir — not real drift. Only
            // genuinely separate copies (distinct resolved paths) can drift.
            guard !isLinkedMirror else { continue }

            let hashes = Set(liveIndices.compactMap { capabilities[$0].metadata["contentHash"] }.filter { !$0.isEmpty })
            if hashes.count > 1, !groupLikelyUnrelated(liveIndices.map { capabilities[$0] }) {
                for index in liveIndices {
                    appendStatus(.drifted, to: &capabilities[index])
                }
                annotateDriftLocations(forGroup: liveIndices, in: &capabilities)
            }
        }
    }

    /// One serialised location record per member of a drifted same-name group. The
    /// resolver already knows every conflicting copy here; without this the App can only
    /// say "exists in multiple locations" without naming *where* or showing *which content
    /// differs*. Each member carries the full list (with `current` flagging itself) so the
    /// inspector can render a side-by-side "this copy vs. the others" comparison and point
    /// the user at the divergence. Stored as JSON because metadata values are `String`.
    private func annotateDriftLocations(forGroup indices: [Int], in capabilities: inout [Capability]) {
        let ordered = indices.sorted { lhs, rhs in
            let lScope = scopeRank(capabilities[lhs].scope)
            let rScope = scopeRank(capabilities[rhs].scope)
            if lScope != rScope { return lScope < rScope }
            return locationPath(for: capabilities[lhs]) < locationPath(for: capabilities[rhs])
        }
        for index in indices {
            let records = ordered.map { member -> DriftLocation in
                let capability = capabilities[member]
                return DriftLocation(
                    kind: capability.source.kind,
                    scope: capability.scope.rawValue,
                    path: displayPath(locationPath(for: capability)),
                    hash: capability.metadata["contentHash"] ?? "",
                    current: member == index
                )
            }
            guard let json = encodeDriftLocations(records) else { continue }
            capabilities[index].metadata["driftLocationsJSON"] = json
            capabilities[index].metadata["driftLocationCount"] = String(records.count)
        }
    }

    /// The real on-disk location to show for a capability: the scanner-recorded `sourcePath`
    /// when present (the SKILL.md / config the user can actually open), falling back to the
    /// structural `source.path`. Orbita's own internal index paths are never surfaced.
    private func locationPath(for capability: Capability) -> String {
        if let path = capability.metadata["sourcePath"],
           !path.isEmpty,
           !path.contains("/.orbita/") {
            return path
        }
        return capability.source.path
    }

    private func encodeDriftLocations(_ records: [DriftLocation]) -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(records) else { return nil }
        return String(decoding: data, as: UTF8.self)
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
