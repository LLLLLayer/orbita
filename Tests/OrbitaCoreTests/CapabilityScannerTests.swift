import CryptoKit
import XCTest
@testable import OrbitaCore

final class CapabilityScannerTests: XCTestCase {
    func testSnapshotStorePersistsGraphByProjectRoot() throws {
        let cacheRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("OrbitaSnapshotTests-\(UUID().uuidString)")
        let projectRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("OrbitaProject-\(UUID().uuidString)")
        defer {
            try? FileManager.default.removeItem(at: cacheRoot)
            try? FileManager.default.removeItem(at: projectRoot)
        }
        try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)
        let graph = CapabilityGraph(
            projectRoot: projectRoot.path,
            generatedAt: "2026-05-23T00:00:00Z",
            capabilities: [
                Capability(
                    id: "skill:lark-doc",
                    name: "lark-doc",
                    type: .skill,
                    scope: .project,
                    source: CapabilitySource(kind: "skill", path: projectRoot.appendingPathComponent("SKILL.md").path)
                )
            ],
            issues: []
        )

        let store = CapabilitySnapshotStore(root: cacheRoot)
        try store.save(graph)
        let loaded = try store.load(projectRoot: projectRoot)

        XCTAssertEqual(loaded?.graph.projectRoot, graph.projectRoot)
        XCTAssertEqual(loaded?.graph.capabilities.first?.name, "lark-doc")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: cacheRoot.appendingPathComponent("snapshots").path).count, 1)
    }

    func testSnapshotStoreRejectsOldSchemaSnapshots() throws {
        let cacheRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("OrbitaSnapshotSchemaTests-\(UUID().uuidString)")
        let projectRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("OrbitaProject-\(UUID().uuidString)")
        defer {
            try? FileManager.default.removeItem(at: cacheRoot)
            try? FileManager.default.removeItem(at: projectRoot)
        }
        try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)
        let graph = CapabilityGraph(
            projectRoot: projectRoot.path,
            generatedAt: "2026-05-23T00:00:00Z",
            capabilities: [],
            issues: []
        )
        let staleSnapshot = CapabilitySnapshot(
            schemaVersion: CapabilitySnapshot.currentSchemaVersion - 1,
            projectRoot: projectRoot.path,
            graph: graph
        )
        let snapshots = cacheRoot.appendingPathComponent("snapshots", isDirectory: true)
        try FileManager.default.createDirectory(at: snapshots, withIntermediateDirectories: true)
        let digest = SHA256.hash(data: Data(projectRoot.standardizedFileURL.resolvingSymlinksInPath().path.utf8))
        let key = digest.map { String(format: "%02x", $0) }.joined()
        let url = snapshots.appendingPathComponent("\(key).json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(staleSnapshot).write(to: url, options: .atomic)

        let store = CapabilitySnapshotStore(root: cacheRoot)
        XCTAssertNil(try store.load(projectRoot: projectRoot))
        // The stale snapshot is moved aside to a .bak instead of being silently discarded, so a buggy
        // schema migration stays recoverable.
        let backup = url.appendingPathExtension("bak")
        XCTAssertTrue(FileManager.default.fileExists(atPath: backup.path), "stale-schema snapshot should be quarantined to .bak")
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path), "stale snapshot should be moved out of the live slot")
    }

    func testSnapshotStoreQuarantinesCorruptSnapshot() throws {
        let cacheRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("OrbitaSnapshotCorruptTests-\(UUID().uuidString)")
        let projectRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("OrbitaProject-\(UUID().uuidString)")
        defer {
            try? FileManager.default.removeItem(at: cacheRoot)
            try? FileManager.default.removeItem(at: projectRoot)
        }
        try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)
        let snapshots = cacheRoot.appendingPathComponent("snapshots", isDirectory: true)
        try FileManager.default.createDirectory(at: snapshots, withIntermediateDirectories: true)
        let digest = SHA256.hash(data: Data(projectRoot.standardizedFileURL.resolvingSymlinksInPath().path.utf8))
        let key = digest.map { String(format: "%02x", $0) }.joined()
        let url = snapshots.appendingPathComponent("\(key).json")
        try Data("{ not valid snapshot json".utf8).write(to: url, options: .atomic)

        let store = CapabilitySnapshotStore(root: cacheRoot)
        // Corrupt JSON returns nil (re-scan) rather than throwing, and is moved aside.
        XCTAssertNil(try store.load(projectRoot: projectRoot))
        let backup = url.appendingPathExtension("bak")
        XCTAssertTrue(FileManager.default.fileExists(atPath: backup.path), "corrupt snapshot should be quarantined to .bak")
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path), "corrupt snapshot should be moved out of the live slot")
    }

    func testProjectLibraryPersistsLastProjectAndSupportsRemoval() throws {
        let libraryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("OrbitaProjectLibraryTests-\(UUID().uuidString)")
        let projectA = FileManager.default.temporaryDirectory.appendingPathComponent("ProjectA-\(UUID().uuidString)")
        let projectB = FileManager.default.temporaryDirectory.appendingPathComponent("ProjectB-\(UUID().uuidString)")
        defer {
            try? FileManager.default.removeItem(at: libraryRoot)
            try? FileManager.default.removeItem(at: projectA)
            try? FileManager.default.removeItem(at: projectB)
        }
        try FileManager.default.createDirectory(at: projectA, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: projectB, withIntermediateDirectories: true)

        let store = ProjectLibraryStore(root: libraryRoot)
        var library = try store.load()
        library.upsert(projectRoot: projectA)
        library.upsert(projectRoot: projectB)
        try store.save(library)

        var loaded = try store.load()
        XCTAssertEqual(loaded.projects.map(\.name), [projectA.lastPathComponent, projectB.lastPathComponent])
        XCTAssertEqual(loaded.lastProjectPath, projectB.standardizedFileURL.resolvingSymlinksInPath().path)

        loaded.upsert(projectRoot: projectA)
        XCTAssertEqual(loaded.projects.map(\.name), [projectA.lastPathComponent, projectB.lastPathComponent])

        loaded.moveProjects(fromOffsets: IndexSet(integer: 0), toOffset: 2)
        XCTAssertEqual(loaded.projects.map(\.name), [projectB.lastPathComponent, projectA.lastPathComponent])

        loaded.moveProjectToTop(projectPath: projectA.path)
        XCTAssertEqual(loaded.projects.map(\.name), [projectA.lastPathComponent, projectB.lastPathComponent])

        loaded.remove(projectPath: projectB.path)
        try store.save(loaded)
        let reloaded = try store.load()

        XCTAssertEqual(reloaded.projects.map(\.name), [projectA.lastPathComponent])
        XCTAssertEqual(reloaded.lastProjectPath, projectA.standardizedFileURL.resolvingSymlinksInPath().path)
    }

    func testProjectLibraryRecoversFromCorruptFile() throws {
        let libraryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("OrbitaProjectLibraryCorruptTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: libraryRoot) }
        try FileManager.default.createDirectory(at: libraryRoot, withIntermediateDirectories: true)

        let libraryURL = libraryRoot.appendingPathComponent("projects.json")
        let backupURL = libraryRoot.appendingPathComponent("projects.json.bak")
        try Data("{ this is not valid json".utf8).write(to: libraryURL, options: .atomic)

        let store = ProjectLibraryStore(root: libraryRoot)
        let recovered = try store.load()
        XCTAssertTrue(recovered.projects.isEmpty)
        XCTAssertNil(recovered.lastProjectPath)
        XCTAssertEqual(recovered.schemaVersion, ProjectLibrary.currentSchemaVersion)
        XCTAssertTrue(FileManager.default.fileExists(atPath: backupURL.path), "corrupt file should be moved aside to .bak")
        XCTAssertFalse(FileManager.default.fileExists(atPath: libraryURL.path), "corrupt projects.json should be removed after quarantine")

        // A subsequent save must not clobber the recovered data into the original slot blindly.
        var library = recovered
        let project = libraryRoot.appendingPathComponent("Proj-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        library.upsert(projectRoot: project)
        try store.save(library)
        let reloaded = try store.load()
        XCTAssertEqual(reloaded.projects.map(\.name), [project.lastPathComponent])
        XCTAssertTrue(FileManager.default.fileExists(atPath: backupURL.path), "backup of the corrupt file must remain after a save")
    }

    func testProjectLibraryRejectsAndQuarantinesWrongSchemaVersion() throws {
        let libraryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("OrbitaProjectLibrarySchemaTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: libraryRoot) }
        try FileManager.default.createDirectory(at: libraryRoot, withIntermediateDirectories: true)

        let libraryURL = libraryRoot.appendingPathComponent("projects.json")
        let backupURL = libraryRoot.appendingPathComponent("projects.json.bak")

        let project = libraryRoot.appendingPathComponent("Proj-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        var future = ProjectLibrary(schemaVersion: ProjectLibrary.currentSchemaVersion + 1)
        future.upsert(projectRoot: project)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(future).write(to: libraryURL, options: .atomic)

        let store = ProjectLibraryStore(root: libraryRoot)
        let recovered = try store.load()
        XCTAssertTrue(recovered.projects.isEmpty, "a mismatched-schema library must not be trusted")
        XCTAssertEqual(recovered.schemaVersion, ProjectLibrary.currentSchemaVersion)
        XCTAssertTrue(FileManager.default.fileExists(atPath: backupURL.path), "wrong-schema file should be moved aside to .bak")
        XCTAssertFalse(FileManager.default.fileExists(atPath: libraryURL.path))
    }

    func testCapabilityDisplayGrouperAggregatesSharedNamePrefixes() {
        let capabilities = [
            displayCapability(name: "lark-doc"),
            displayCapability(name: "lark-im"),
            displayCapability(name: "lark-calendar"),
            displayCapability(name: "obsidian-cli")
        ]

        let items = CapabilityDisplayGrouper().items(for: capabilities, minimumGroupSize: 3)

        XCTAssertEqual(items.count, 2)
        XCTAssertTrue(items.contains { item in
            guard case let .group(group) = item else { return false }
            return group.name == "lark"
                && group.capabilities.map(\.name) == ["lark-calendar", "lark-doc", "lark-im"]
                && group.inspectionCapability.type == .plugin
                && group.inspectionCapability.source.kind == "virtual-plugin"
                && group.inspectionCapability.metadata["childCount"] == "3"
        })
        XCTAssertTrue(items.contains { item in
            guard case let .capability(capability) = item else { return false }
            return capability.name == "obsidian-cli"
        })
    }

    func testCapabilityDisplayGrouperDoesNotPrefixGroupHooks() {
        let capabilities = [
            displayCapability(name: "Vibe Island - PermissionRequest (*)", type: .hook),
            displayCapability(name: "Vibe Island - SessionStart", type: .hook),
            displayCapability(name: "Vibe Island - Stop (*)", type: .hook)
        ]

        let items = CapabilityDisplayGrouper().items(for: capabilities, minimumGroupSize: 3)

        XCTAssertEqual(items.count, 3)
        XCTAssertTrue(items.allSatisfy { item in
            if case .capability = item {
                return true
            }
            return false
        })
    }

    func testCapabilityDisplayGrouperAggregatesPluginChildrenUnderPluginCell() {
        let plugin = Capability(
            id: "plugin:codex-cache:openai-curated:superpowers",
            name: "Superpowers",
            type: .plugin,
            scope: .user,
            source: CapabilitySource(kind: "package", path: "/tmp/superpowers", packageName: "superpowers", inferred: true)
        )
        let brainstorming = displayCapability(
            name: "brainstorming",
            pluginID: plugin.id,
            packageName: "superpowers"
        )
        let writingPlans = displayCapability(
            name: "writing-plans",
            pluginID: plugin.id,
            packageName: "superpowers"
        )

        let items = CapabilityDisplayGrouper().items(for: [brainstorming, plugin, writingPlans])

        XCTAssertEqual(items.count, 1)
        guard case let .group(group) = items.first else {
            return XCTFail("Expected plugin group")
        }
        XCTAssertEqual(group.kind, .plugin)
        XCTAssertEqual(group.name, "Superpowers")
        XCTAssertEqual(group.representative?.id, plugin.id)
        XCTAssertEqual(group.capabilities.map(\.name), ["brainstorming", "writing-plans"])
    }

    func testCapabilityDisplayGrouperKeepsMirroredPluginHooksUnderPluginCell() {
        let plugin = Capability(
            id: "plugin:claude:workflow@unicorn-marketplace:user:global",
            name: "Workflow",
            type: .plugin,
            scope: .user,
            source: CapabilitySource(
                kind: "claude-plugin",
                path: "/tmp/.claude/plugins/cache/unicorn-marketplace/workflow/1.4.5",
                packageName: "workflow"
            )
        )
        let sessionStart = Capability(
            id: "hook:workflow-session-start",
            name: "Workflow - SessionStart",
            type: .hook,
            scope: .user,
            source: CapabilitySource(
                kind: "claude-plugin-hook",
                path: "/tmp/.claude/plugins/cache/unicorn-marketplace/workflow/1.4.5/hooks/hooks.json",
                packageName: "workflow"
            ),
            pluginID: plugin.id,
            metadata: ["handlerHost": "Workflow", "event": "SessionStart"]
        )
        let stop = Capability(
            id: "hook:workflow-stop",
            name: "Workflow - Stop (*)",
            type: .hook,
            scope: .user,
            source: CapabilitySource(
                kind: "claude-plugin-hook",
                path: "/tmp/.claude/plugins/cache/unicorn-marketplace/workflow/1.4.5/hooks/hooks.json",
                packageName: "workflow"
            ),
            pluginID: plugin.id,
            metadata: ["handlerHost": "Workflow", "event": "Stop", "matcher": "*"]
        )

        let items = CapabilityDisplayGrouper().items(for: [sessionStart, plugin, stop], preservesInputOrder: true)

        XCTAssertEqual(items.count, 1)
        guard case let .group(group) = items.first else {
            return XCTFail("Expected mirrored plugin hooks to stay under the plugin")
        }
        XCTAssertEqual(group.kind, .plugin)
        XCTAssertEqual(group.representative?.id, plugin.id)
        XCTAssertEqual(group.capabilities.map(\.id), ["hook:workflow-session-start", "hook:workflow-stop"])
    }

    func testCapabilityDisplayGrouperMergesSameHashMirrors() {
        let codex = Capability(
            id: "skill:/tmp/.codex/skills/browser/SKILL.md",
            name: "browser",
            type: .skill,
            scope: .user,
            source: CapabilitySource(kind: "codex-skill", path: "/tmp/.codex/skills/browser/SKILL.md"),
            metadata: ["contentHash": "same-hash"]
        )
        let agents = Capability(
            id: "skill:/tmp/.agents/skills/browser/SKILL.md",
            name: "browser",
            type: .skill,
            scope: .user,
            source: CapabilitySource(kind: "agents-skill", path: "/tmp/.agents/skills/browser/SKILL.md"),
            metadata: ["contentHash": "same-hash"]
        )

        let items = CapabilityDisplayGrouper().items(for: [codex, agents])

        XCTAssertEqual(items.count, 1)
        guard case let .group(group) = items.first else {
            return XCTFail("Expected mirrored group")
        }
        XCTAssertEqual(group.kind, .mirror)
        XCTAssertEqual(group.name, "browser")
        XCTAssertEqual(group.inspectionCapability.type, .skill)
        XCTAssertEqual(group.inspectionCapability.source.kind, "virtual-mirror")
        XCTAssertEqual(group.inspectionCapability.metadata["childCount"], "2")
    }

    func testCapabilityDisplayGrouperAggregatesMirroredPrefixes() throws {
        let capabilities = [
            mirroredDisplayCapability(name: "lark-base", sourceKind: "agents-skill", path: "/tmp/.agents/skills/lark-base/SKILL.md", hash: "base"),
            mirroredDisplayCapability(name: "lark-base", sourceKind: "claude-skill", path: "/tmp/.claude/skills/lark-base/SKILL.md", hash: "base"),
            mirroredDisplayCapability(name: "lark-calendar", sourceKind: "agents-skill", path: "/tmp/.agents/skills/lark-calendar/SKILL.md", hash: "calendar"),
            mirroredDisplayCapability(name: "lark-calendar", sourceKind: "claude-skill", path: "/tmp/.claude/skills/lark-calendar/SKILL.md", hash: "calendar"),
            mirroredDisplayCapability(name: "lark-contact", sourceKind: "agents-skill", path: "/tmp/.agents/skills/lark-contact/SKILL.md", hash: "contact"),
            mirroredDisplayCapability(name: "lark-contact", sourceKind: "claude-skill", path: "/tmp/.claude/skills/lark-contact/SKILL.md", hash: "contact")
        ]

        let items = CapabilityDisplayGrouper().items(for: capabilities, minimumGroupSize: 3)

        // Directory ownership: the `.agents` canonicals and the `.claude` bridges are owned by different
        // agents, so they form TWO separate `lark` prefix tiles (each 3, branded by its own dir's loader)
        // rather than one merged tile of 6. (The Overview previously inflated this to a single doubled
        // count.)
        let groups = items.compactMap { item -> CapabilityGroup? in
            guard case let .group(group) = item else { return nil }
            return group
        }
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(groups.count, 2)
        XCTAssertTrue(groups.allSatisfy { $0.kind == .prefix && $0.name == "lark" })
        XCTAssertTrue(groups.allSatisfy { $0.inspectionCapability.metadata["childCount"] == "3" })
        let agentsGroup = try XCTUnwrap(groups.first { group in
            group.capabilities.allSatisfy { $0.source.kind == "agents-skill" }
        })
        let claudeGroup = try XCTUnwrap(groups.first { group in
            group.capabilities.allSatisfy { $0.source.kind == "claude-skill" }
        })
        XCTAssertEqual(Set(agentsGroup.capabilities.map(\.name)), ["lark-base", "lark-calendar", "lark-contact"])
        XCTAssertEqual(Set(claudeGroup.capabilities.map(\.name)), ["lark-base", "lark-calendar", "lark-contact"])
    }

    /// End-to-end directory-ownership for the real `lark-*` setup: a canonical `.agents/skills` group
    /// plus its `npx skills` symlink bridge under `.trae/skills`. The Overview must show TWO prefix
    /// groups (never one merged count), and each agent's view must hold only the copy in ITS own dir —
    /// Trae sees the `.trae` bridges, Codex/`.agents` see the canonicals, with no crossover.
    func testLarkBridgeSplitsByOwnerDirAndStaysDirectoryScoped() throws {
        var capabilities: [Capability] = []
        for name in ["lark-base", "lark-calendar", "lark-contact"] {
            capabilities.append(Capability(
                id: "skill:/u/.agents/skills/\(name)/SKILL.md",
                name: name,
                type: .skill,
                scope: .user,
                statuses: [.enabled],
                source: CapabilitySource(kind: "agents-skill", path: "/u/.agents/skills/\(name)/SKILL.md"),
                metadata: ["skillsInstalledAgentIDs": "trae"]
            ))
            capabilities.append(Capability(
                id: "skill:/u/.trae/skills/\(name)/SKILL.md",
                name: name,
                type: .skill,
                scope: .user,
                statuses: [.enabled],
                source: CapabilitySource(kind: "trae-skill", path: "/u/.trae/skills/\(name)/SKILL.md"),
                metadata: ["mirrorsAgentsWorkspace": "true"]
            ))
        }

        // Overview (all capabilities) → two `lark` prefix groups of 3, partitioned by owner dir.
        let items = CapabilityDisplayGrouper().items(for: capabilities, minimumGroupSize: 3)
        let groups = items.compactMap { item -> CapabilityGroup? in
            guard case let .group(group) = item else { return nil }
            return group
        }
        XCTAssertEqual(groups.count, 2, "lark must split into an .agents group and a .trae group, not merge to 6")
        XCTAssertTrue(groups.allSatisfy { $0.kind == .prefix && $0.name == "lark" })
        let agentsBucket = try XCTUnwrap(groups.first { $0.capabilities.allSatisfy { $0.source.kind == "agents-skill" } })
        let traeBucket = try XCTUnwrap(groups.first { $0.capabilities.allSatisfy { $0.source.kind == "trae-skill" } })
        XCTAssertEqual(agentsBucket.capabilities.count, 3)
        XCTAssertEqual(traeBucket.capabilities.count, 3)

        // Per-agent visibility: each agent owns the copy in its own dir; no crossover.
        let graph = CapabilityGraph(projectRoot: "/u", capabilities: capabilities, issues: [])
        let traeVisible = Set(AgentViewResolver().visibleCapabilities(for: .trae, graph: graph).map(\.id))
        let codexVisible = Set(AgentViewResolver().visibleCapabilities(for: .codex, graph: graph).map(\.id))
        let traeBridgeIDs = Set(traeBucket.capabilities.map(\.id))
        let agentsCanonicalIDs = Set(agentsBucket.capabilities.map(\.id))
        XCTAssertEqual(traeVisible.intersection(traeBridgeIDs), traeBridgeIDs, "Trae owns its .trae bridges")
        XCTAssertTrue(traeVisible.isDisjoint(with: agentsCanonicalIDs), "Trae must NOT also see the .agents canonical")
        XCTAssertEqual(codexVisible.intersection(agentsCanonicalIDs), agentsCanonicalIDs, "Codex reads the .agents canonical in place")
        XCTAssertTrue(codexVisible.isDisjoint(with: traeBridgeIDs), "Codex must NOT see the .trae bridge")
    }

    func testCapabilityDisplayGrouperMergesSymlinkMirrors() throws {
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("OrbitaMirrorTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }
        try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)

        let target = temporaryRoot.appendingPathComponent("settings.json")
        let link = temporaryRoot.appendingPathComponent("settings-link.json")
        try #"{"hooks": {}}"#.write(to: target, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

        let canonical = Capability(
            id: "hook:canonical",
            name: "Claude settings",
            type: .hook,
            scope: .project,
            source: CapabilitySource(kind: "claude-settings-hook", path: target.path)
        )
        let linked = Capability(
            id: "hook:linked",
            name: "Claude settings",
            type: .hook,
            scope: .project,
            source: CapabilitySource(kind: "claude-settings-hook", path: link.path)
        )

        let items = CapabilityDisplayGrouper().items(for: [canonical, linked], preservesInputOrder: true)

        XCTAssertEqual(items.count, 1)
        guard case let .group(group) = items.first else {
            return XCTFail("Expected mirrored group")
        }
        XCTAssertEqual(group.kind, .mirror)
        XCTAssertEqual(group.capabilities.map(\.id), ["hook:canonical", "hook:linked"])
        XCTAssertEqual(group.inspectionCapability.type, .hook)
    }

    func testCapabilityDisplayGrouperSplitsHookMirrorsByHandlerHost() {
        let sharedPath = "/tmp/hooks.json"
        let ab = Capability(
            id: "hook:ab",
            name: "AB Agent Collect - PreToolUse (*)",
            type: .hook,
            scope: .user,
            source: CapabilitySource(kind: "codex-hook", path: sharedPath),
            metadata: ["handlerHost": "AB Agent Collect", "event": "PreToolUse", "matcher": "*"]
        )
        let vibeStart = Capability(
            id: "hook:vibe-start",
            name: "Vibe Island - SessionStart",
            type: .hook,
            scope: .user,
            source: CapabilitySource(kind: "codex-hook", path: sharedPath),
            metadata: ["handlerHost": "Vibe Island", "event": "SessionStart"]
        )
        let vibeStop = Capability(
            id: "hook:vibe-stop",
            name: "Vibe Island - Stop (*)",
            type: .hook,
            scope: .user,
            source: CapabilitySource(kind: "codex-hook", path: sharedPath),
            metadata: ["handlerHost": "Vibe Island", "event": "Stop", "matcher": "*"]
        )

        let items = CapabilityDisplayGrouper().items(for: [ab, vibeStart, vibeStop], preservesInputOrder: true)

        XCTAssertEqual(items.count, 2)
        XCTAssertTrue(items.contains { item in
            guard case let .capability(capability) = item else { return false }
            return capability.id == "hook:ab"
        })
        XCTAssertTrue(items.contains { item in
            guard case let .group(group) = item else { return false }
            return group.capabilities.map(\.id) == ["hook:vibe-start", "hook:vibe-stop"]
        })
    }

    func testCapabilityDisplayGrouperSynthesizesSelectablePluginGroup() {
        let capabilities = [
            displayCapability(name: "brainstorming", pluginID: "plugin:codex-cache:openai-curated:superpowers", packageName: "superpowers"),
            displayCapability(name: "browser", pluginID: "plugin:codex-cache:openai-curated:superpowers", packageName: "superpowers"),
            displayCapability(name: "executing-plans", pluginID: "plugin:codex-cache:openai-curated:superpowers", packageName: "superpowers")
        ]

        let items = CapabilityDisplayGrouper().items(for: capabilities)

        XCTAssertEqual(items.count, 1)
        guard case let .group(group) = items.first else {
            return XCTFail("Expected synthetic plugin group")
        }
        XCTAssertNil(group.representative)
        XCTAssertEqual(group.kind, .plugin)
        XCTAssertEqual(group.name, "Superpowers")
        XCTAssertEqual(group.inspectionCapability.id, group.id)
        XCTAssertEqual(group.inspectionCapability.name, "Superpowers")
        XCTAssertEqual(group.inspectionCapability.source.kind, "virtual-plugin")
        XCTAssertEqual(group.inspectionCapability.source.packageName, "superpowers")
        XCTAssertEqual(group.inspectionCapability.pluginID, "plugin:codex-cache:openai-curated:superpowers")
    }

    func testScansMixedProjectFixture() throws {
        let root = try fixtureURL("MixedProject")

        let result = try scanProjectOnly(root)

        XCTAssertTrue(result.capabilities.contains { $0.name == "Agent instructions" && $0.type == .instruction })
        XCTAssertTrue(result.capabilities.contains { $0.name == "Claude Code instructions" && $0.type == .instruction })
        XCTAssertTrue(result.capabilities.contains { $0.name == "lark-doc" && $0.type == .skill })
        XCTAssertTrue(result.capabilities.contains { $0.name == "lark" && $0.type == .mcpServer })
        XCTAssertTrue(result.capabilities.contains { $0.name == "project" && $0.type == .rule })
    }

    func testScannerEmitsProgressEventsForMajorPhases() throws {
        let root = try fixtureURL("MixedProject")
        let recorder = ScanProgressRecorder()

        _ = try CapabilityScanner().scan(
            projectRoot: root,
            options: ScanOptions(includeUserScope: false, progressHandler: { event in
                recorder.append(event)
            })
        )

        let names = recorder.events.map(\.name)
        XCTAssertTrue(names.contains("scan.start"))
        XCTAssertTrue(names.contains("scan.codex.start"))
        XCTAssertTrue(names.contains("scan.skills.start"))
        XCTAssertTrue(names.contains("scan.finish"))
    }

    func testProjectSkillScanSkipsGeneratedDirectories() throws {
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("OrbitaCoreTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }

        let realSkill = temporaryRoot.appendingPathComponent("skills/real")
        let generatedSkill = temporaryRoot.appendingPathComponent("dist/generated")
        try FileManager.default.createDirectory(at: realSkill, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: generatedSkill, withIntermediateDirectories: true)
        try """
        ---
        name: real-skill
        ---
        """.write(to: realSkill.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        try """
        ---
        name: generated-skill
        ---
        """.write(to: generatedSkill.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)

        let result = try CapabilityScanner().scan(projectRoot: temporaryRoot, options: ScanOptions(includeUserScope: false))

        XCTAssertTrue(result.capabilities.contains { $0.name == "real-skill" })
        XCTAssertFalse(result.capabilities.contains { $0.name == "generated-skill" })
    }

    func testDefaultProjectSkillScanSkipsNestedTestFixtures() throws {
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("OrbitaCoreTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }

        let fixtureSkill = temporaryRoot.appendingPathComponent("Tests/OrbitaCoreTests/Fixtures/MixedProject/node_modules/example/skills/fixture-skill")
        let projectSkill = temporaryRoot.appendingPathComponent("skills/project-skill")
        try FileManager.default.createDirectory(at: fixtureSkill, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: projectSkill, withIntermediateDirectories: true)
        try skillText(name: "fixture-skill", body: "Fixture skill")
            .write(to: fixtureSkill.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        try skillText(name: "project-skill", body: "Project skill")
            .write(to: projectSkill.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)

        let result = try CapabilityScanner().scan(projectRoot: temporaryRoot, options: ScanOptions(includeUserScope: false))

        XCTAssertTrue(result.capabilities.contains { $0.name == "project-skill" })
        XCTAssertFalse(result.capabilities.contains { $0.name == "fixture-skill" })
    }

    func testScansCodexProjectCommands() throws {
        let root = try fixtureURL("MixedProject")

        let result = try scanProjectOnly(root)

        let command = result.capabilities.first { $0.name == "bootstrap" && $0.type == .command }
        XCTAssertEqual(command?.source.kind, "codex-command")
        XCTAssertEqual(command?.scope, .project)
        XCTAssertEqual(command?.risks, [.info, .read])
    }

    func testScansCodexHooksJSONFromUserConfigLayer() throws {
        let projectRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("OrbitaCoreTests-\(UUID().uuidString)")
        let codexRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("OrbitaCodexHooks-\(UUID().uuidString)")
        let config = codexRoot.appendingPathComponent("config.toml")
        let hooks = codexRoot.appendingPathComponent("hooks.json")
        try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: codexRoot, withIntermediateDirectories: true)
        try """
        [hooks.state]

        [hooks.state."\(hooks.path):post_tool_use:0:0"]
        enabled = true
        trusted_hash = "sha256:test"
        """.write(to: config, atomically: true, encoding: .utf8)
        try """
        {
          "hooks": {
            "PostToolUse": [
              {
                "matcher": ".*",
                "hooks": [
                  {
                    "type": "command",
                    "command": "npx -y hook-runner",
                    "timeout": 30
                  }
                ]
              }
            ]
          }
        }
        """.write(to: hooks, atomically: true, encoding: .utf8)
        defer {
            try? FileManager.default.removeItem(at: projectRoot)
            try? FileManager.default.removeItem(at: codexRoot)
        }

        let result = try CapabilityScanner().scan(
            projectRoot: projectRoot,
            options: ScanOptions(
                includeUserScope: true,
                userSkillRoots: [],
                codexConfigURL: config,
                codexPluginCacheRoot: codexRoot.appendingPathComponent("missing-cache"),
                claudeInstalledPluginsURL: codexRoot.appendingPathComponent("missing-claude.json"),
                claudeSettingsURLs: []
            )
        )

        let hook = try XCTUnwrap(result.capabilities.first { $0.name == "Hook Runner - PostToolUse (.*)" && $0.source.kind == "codex-hook" })
        XCTAssertEqual(hook.scope, .user)
        XCTAssertEqual(hook.statuses.first, .enabled)
        XCTAssertEqual(hook.metadata["event"], "PostToolUse")
        XCTAssertEqual(hook.metadata["command"], "npx -y hook-runner")
        XCTAssertEqual(hook.metadata["handlerKind"], "command")
        XCTAssertEqual(hook.metadata["handlerHost"], "Hook Runner")
        XCTAssertEqual(hook.metadata["handlerRunner"], "npx")
        XCTAssertEqual(hook.metadata["handlerScript"], "hook-runner")
        XCTAssertTrue(hook.risks.contains(.network))
    }

    func testScansClaudeHookHandlerHostFromCommandScript() throws {
        let projectRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("OrbitaCoreTests-\(UUID().uuidString)")
        let claudeRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("OrbitaClaudeHooks-\(UUID().uuidString)")
        let settings = claudeRoot.appendingPathComponent("settings.json")
        try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: claudeRoot, withIntermediateDirectories: true)
        try """
        {
          "hooks": {
            "PermissionRequest": [
              {
                "matcher": "*",
                "hooks": [
                  {
                    "type": "command",
                    "command": "python3 '\(claudeRoot.path)/hooks/claude-island-state.py'",
                    "timeout": 86400
                  }
                ]
              }
            ]
          }
        }
        """.write(to: settings, atomically: true, encoding: .utf8)
        defer {
            try? FileManager.default.removeItem(at: projectRoot)
            try? FileManager.default.removeItem(at: claudeRoot)
        }

        let result = try CapabilityScanner().scan(
            projectRoot: projectRoot,
            options: ScanOptions(
                includeUserScope: true,
                userSkillRoots: [],
                codexConfigURL: claudeRoot.appendingPathComponent("missing-config.toml"),
                codexPluginCacheRoot: claudeRoot.appendingPathComponent("missing-cache"),
                claudeInstalledPluginsURL: claudeRoot.appendingPathComponent("missing-plugins.json"),
                claudeSettingsURLs: [settings]
            )
        )

        let hook = try XCTUnwrap(result.capabilities.first { $0.name == "Vibe Notch - PermissionRequest (*)" })
        XCTAssertEqual(hook.source.kind, "claude-settings-hook")
        XCTAssertEqual(hook.metadata["handlerHost"], "Vibe Notch")
        XCTAssertEqual(hook.metadata["handlerRunner"], "python3")
        XCTAssertEqual(hook.metadata["handlerScript"], "\(claudeRoot.path)/hooks/claude-island-state.py")
        XCTAssertEqual(hook.metadata["timeout"], "86400")
    }

    func testScansClaudeSettingsVibeIslandHooksAsConcreteHandlers() throws {
        let projectRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("OrbitaCoreTests-\(UUID().uuidString)")
        let claudeRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("OrbitaClaudeVibeIsland-\(UUID().uuidString)")
        let settings = claudeRoot.appendingPathComponent("settings.json")
        let command = #"/bin/sh -c '[ -x "$HOME/.vibe-island/bin/vibe-island-bridge" ] && "$HOME/.vibe-island/bin/vibe-island-bridge" --source claude; exit 0'"#
        try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: claudeRoot, withIntermediateDirectories: true)
        let settingsObject: [String: Any] = [
            "hooks": [
                "PermissionRequest": [
                    [
                        "matcher": "*",
                        "hooks": [
                            ["type": "command", "command": command, "timeout": 5]
                        ]
                    ]
                ],
                "SessionStart": [
                    [
                        "hooks": [
                            ["type": "command", "command": command]
                        ]
                    ]
                ],
                "Stop": [
                    [
                        "matcher": "*",
                        "hooks": [
                            ["type": "command", "command": command]
                        ]
                    ]
                ]
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: settingsObject, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: settings)
        defer {
            try? FileManager.default.removeItem(at: projectRoot)
            try? FileManager.default.removeItem(at: claudeRoot)
        }

        let result = try CapabilityScanner().scan(
            projectRoot: projectRoot,
            options: ScanOptions(
                includeUserScope: true,
                userSkillRoots: [],
                codexConfigURL: claudeRoot.appendingPathComponent("missing-config.toml"),
                codexPluginCacheRoot: claudeRoot.appendingPathComponent("missing-cache"),
                claudeInstalledPluginsURL: claudeRoot.appendingPathComponent("missing-plugins.json"),
                claudeSettingsURLs: [settings]
            )
        )

        let hooks = result.capabilities
            .filter { $0.source.kind == "claude-settings-hook" }
            .sorted { $0.name < $1.name }
        XCTAssertEqual(hooks.map(\.name), [
            "Vibe Island - PermissionRequest (*)",
            "Vibe Island - SessionStart",
            "Vibe Island - Stop (*)"
        ])
        XCTAssertTrue(hooks.allSatisfy { $0.scope == .user })
        XCTAssertTrue(hooks.allSatisfy { $0.metadata["handlerHost"] == "Vibe Island" })
        XCTAssertTrue(hooks.allSatisfy { $0.metadata["handlerRunner"] == "sh" })
        XCTAssertTrue(hooks.allSatisfy { $0.metadata["command"] == command })
    }

    func testScansCursorLegacyRulesAndClaudeWorkspaceFiles() throws {
        let root = try fixtureURL("MixedProject")

        let result = try scanProjectOnly(root)

        let legacyRule = result.capabilities.first { $0.name == "Legacy Cursor rules" && $0.type == .rule }
        XCTAssertEqual(legacyRule?.source.kind, "legacy-cursor-rule")
        XCTAssertTrue(legacyRule?.source.path.hasSuffix("/.cursorrules") == true)

        let claudeCommand = result.capabilities.first { $0.name == "review" && $0.type == .command }
        XCTAssertEqual(claudeCommand?.source.kind, "claude-command")

        let claudeHook = result.capabilities.first { $0.name == "Swift - PostToolUse (Write)" && $0.type == .hook }
        XCTAssertEqual(claudeHook?.source.kind, "claude-settings-hook")
        XCTAssertEqual(claudeHook?.metadata["command"], "swift test")
        XCTAssertEqual(claudeHook?.metadata["handlerHost"], "Swift")
        XCTAssertTrue(claudeHook?.metadata["claudeHookDeleteCommand"]?.contains("PostToolUse hook") == true)
        XCTAssertTrue(claudeHook?.risks.contains(.exec) == true)
    }

    func testClaudeNativeSkillLifecycleUsesSkillOverrides() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("OrbitaClaudeSkill-\(UUID().uuidString)")
        let skill = root.appendingPathComponent(".claude/skills/review-helper/SKILL.md")
        let settings = root.appendingPathComponent(".claude/settings.json")
        defer { try? FileManager.default.removeItem(at: root) }

        try FileManager.default.createDirectory(at: skill.deletingLastPathComponent(), withIntermediateDirectories: true)
        try skillText(name: "review-helper", body: "Review helper")
            .write(to: skill, atomically: true, encoding: .utf8)
        try """
        {
          "skillOverrides": {
            "review-helper": "off"
          }
        }
        """.write(to: settings, atomically: true, encoding: .utf8)

        let result = try scanProjectOnly(root)

        let scannedSkill = try XCTUnwrap(result.capabilities.first { $0.name == "review-helper" && $0.source.kind == "claude-skill" })
        XCTAssertEqual(scannedSkill.statuses, [.disabled])
        XCTAssertEqual(scannedSkill.metadata["claudeSkillName"], "review-helper")
        XCTAssertEqual(scannedSkill.metadata["claudeSettingsPath"], settings.path)
        XCTAssertTrue(scannedSkill.metadata["claudeSkillDisableCommand"]?.contains("skillOverrides.review-helper") == true)
        XCTAssertTrue(scannedSkill.metadata["claudeSkillDeleteCommand"]?.contains("/.claude/skills/review-helper") == true)
    }

    func testClaudeProjectMCPConfigExposesDisabledMcpjsonLifecycle() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("OrbitaClaudeMCP-\(UUID().uuidString)")
        let mcp = root.appendingPathComponent(".mcp.json")
        let settings = root.appendingPathComponent(".claude/settings.json")
        defer { try? FileManager.default.removeItem(at: root) }

        try FileManager.default.createDirectory(at: settings.deletingLastPathComponent(), withIntermediateDirectories: true)
        try """
        {
          "mcpServers": {
            "filesystem": {
              "command": "npx",
              "args": ["-y", "@modelcontextprotocol/server-filesystem"]
            }
          }
        }
        """.write(to: mcp, atomically: true, encoding: .utf8)
        try """
        {
          "disabledMcpjsonServers": ["filesystem"]
        }
        """.write(to: settings, atomically: true, encoding: .utf8)

        let result = try scanProjectOnly(root)

        let server = try XCTUnwrap(result.capabilities.first { $0.name == "filesystem" && $0.source.kind == "mcp-config" })
        XCTAssertEqual(server.statuses, [.discovered])
        XCTAssertEqual(server.metadata["mcpServerName"], "filesystem")
        XCTAssertEqual(server.metadata["claudeMCPEnabled"], "false")
        XCTAssertEqual(server.metadata["claudeMCPSettingsPath"], settings.path)
        XCTAssertTrue(server.metadata["claudeMCPEnableCommand"]?.contains("disabledMcpjsonServers") == true)
        XCTAssertTrue(server.metadata["claudeMCPDeleteCommand"]?.contains(".mcp.json") == true)

        let graph = CapabilityResolver().resolve(scanResult: result)
        XCTAssertFalse(AgentViewResolver().view(for: .claudeCode, graph: graph).visibleCapabilities.contains { $0.id == server.id })
        XCTAssertTrue(AgentViewResolver().view(for: .codex, graph: graph).visibleCapabilities.contains { $0.id == server.id })
    }

    func testAgentViewsKeepCodexAndClaudeProjectSkillsSeparate() throws {
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("OrbitaCoreTests-\(UUID().uuidString)")
        let nativeCodexSkill = temporaryRoot.appendingPathComponent(".codex/skills/codex-doc/SKILL.md")
        let nativeClaudeSkill = temporaryRoot.appendingPathComponent(".claude/skills/review-helper/SKILL.md")
        let sharedAgentsSkill = temporaryRoot.appendingPathComponent(".agents/skills/shared-doc/SKILL.md")

        try FileManager.default.createDirectory(at: nativeCodexSkill.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: nativeClaudeSkill.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: sharedAgentsSkill.deletingLastPathComponent(), withIntermediateDirectories: true)
        try skillText(name: "codex-doc", body: "Codex native helper").write(to: nativeCodexSkill, atomically: true, encoding: .utf8)
        try skillText(name: "review-helper", body: "Claude native helper").write(to: nativeClaudeSkill, atomically: true, encoding: .utf8)
        try skillText(name: "shared-doc", body: "Shared agent skill").write(to: sharedAgentsSkill, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }

        let graph = CapabilityResolver().resolve(scanResult: try scanProjectOnly(temporaryRoot))
        let claude = AgentViewResolver().view(for: .claudeCode, graph: graph)
        let codex = AgentViewResolver().view(for: .codex, graph: graph)
        let codexNative = try XCTUnwrap(graph.capabilities.first { $0.name == "codex-doc" && $0.source.kind == "codex-skill" })

        XCTAssertEqual(codexNative.metadata["manager"], "codex")
        XCTAssertTrue(codexNative.statuses.contains(.enabled))
        XCTAssertTrue(claude.visibleCapabilities.contains { $0.name == "review-helper" && $0.source.kind == "claude-skill" })
        XCTAssertFalse(claude.visibleCapabilities.contains { $0.name == "codex-doc" && $0.source.kind == "codex-skill" })
        XCTAssertTrue(codex.visibleCapabilities.contains { $0.name == "codex-doc" && $0.source.kind == "codex-skill" })
        XCTAssertFalse(codex.visibleCapabilities.contains { $0.name == "review-helper" && $0.source.kind == "claude-skill" })
        XCTAssertFalse(claude.visibleCapabilities.contains { $0.name == "shared-doc" && $0.source.kind == "agents-skill" })
        XCTAssertTrue(codex.visibleCapabilities.contains { $0.name == "shared-doc" && $0.source.kind == "agents-skill" })
    }

    func testClaudeAgentsAreScannedAsAgentCapabilities() throws {
        let projectRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("OrbitaCoreTests-\(UUID().uuidString)")
        let userRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("OrbitaClaudeAgents-\(UUID().uuidString)")
        let projectAgent = projectRoot.appendingPathComponent(".claude/agents/code-reviewer.md")
        let userAgent = userRoot.appendingPathComponent(".claude/agents/researcher.md")
        defer {
            try? FileManager.default.removeItem(at: projectRoot)
            try? FileManager.default.removeItem(at: userRoot)
        }

        try FileManager.default.createDirectory(at: projectAgent.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: userAgent.deletingLastPathComponent(), withIntermediateDirectories: true)
        try agentText(name: "code-reviewer", description: "Reviews code changes", tools: "Read, Grep, Bash")
            .write(to: projectAgent, atomically: true, encoding: .utf8)
        try agentText(name: "researcher", description: "Researches implementation options", tools: "Read, Grep")
            .write(to: userAgent, atomically: true, encoding: .utf8)

        let result = try CapabilityScanner().scan(
            projectRoot: projectRoot,
            options: ScanOptions(
                includeUserScope: true,
                userSkillRoots: [],
                userAgentRoots: [userAgent.deletingLastPathComponent()],
                codexConfigURL: userRoot.appendingPathComponent("missing-config.toml"),
                codexPluginCacheRoot: userRoot.appendingPathComponent("missing-cache"),
                claudeInstalledPluginsURL: userRoot.appendingPathComponent("missing-claude.json"),
                claudeSettingsURLs: []
            )
        )
        let graph = CapabilityResolver().resolve(scanResult: result)

        let scannedProjectAgent = try XCTUnwrap(result.capabilities.first { $0.name == "code-reviewer" && $0.source.kind == "claude-agent" })
        let scannedUserAgent = try XCTUnwrap(result.capabilities.first { $0.name == "researcher" && $0.source.kind == "claude-agent" })
        XCTAssertEqual(scannedProjectAgent.type, .agent)
        XCTAssertEqual(scannedProjectAgent.scope, .project)
        XCTAssertEqual(scannedProjectAgent.statuses, [.enabled])
        XCTAssertTrue(scannedProjectAgent.risks.contains(.exec))
        XCTAssertEqual(scannedProjectAgent.metadata["tools"], "Read, Grep, Bash")
        XCTAssertEqual(scannedUserAgent.type, .agent)
        XCTAssertEqual(scannedUserAgent.scope, .user)
        XCTAssertTrue(scannedUserAgent.risks.contains(.global))

        let claude = AgentViewResolver().view(for: .claudeCode, graph: graph)
        let codex = AgentViewResolver().view(for: .codex, graph: graph)
        XCTAssertTrue(claude.visibleCapabilities.contains { $0.id == scannedProjectAgent.id })
        XCTAssertTrue(claude.visibleCapabilities.contains { $0.id == scannedUserAgent.id })
        XCTAssertFalse(codex.visibleCapabilities.contains { $0.id == scannedProjectAgent.id })
    }

    func testFileCapabilitiesIncludeStableContentHash() throws {
        let root = try fixtureURL("MixedProject")

        let result = try scanProjectOnly(root)

        let skill = try XCTUnwrap(result.capabilities.first { $0.name == "lark-doc" && $0.type == .skill })
        let hash = try XCTUnwrap(skill.metadata["contentHash"])
        XCTAssertEqual(hash.count, 64)
        XCTAssertTrue(hash.allSatisfy(\.isHexDigit))
    }

    func testResolverInfersPluginFromNodeModuleSkills() throws {
        let root = try fixtureURL("MixedProject")
        let scan = try scanProjectOnly(root)

        let graph = CapabilityResolver().resolve(scanResult: scan)

        let plugin = graph.capabilities.first { $0.type == .plugin && $0.name == "Lark" }
        XCTAssertNotNil(plugin)
        XCTAssertEqual(plugin?.source.packageName, "@orbita/lark-skills")
        XCTAssertEqual(plugin?.source.inferred, true)
    }

    func testResolverInfersPluginFromCodexPluginCacheSkills() throws {
        let projectRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("OrbitaProject-\(UUID().uuidString)")
        let cacheRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("OrbitaPluginCache-\(UUID().uuidString)")
            .appendingPathComponent(".codex/plugins/cache")
        let skillFile = cacheRoot
            .appendingPathComponent("openai-curated")
            .appendingPathComponent("superpowers")
            .appendingPathComponent("6188456f")
            .appendingPathComponent("skills")
            .appendingPathComponent("brainstorming")
            .appendingPathComponent("SKILL.md")
        defer {
            try? FileManager.default.removeItem(at: projectRoot)
            try? FileManager.default.removeItem(at: cacheRoot)
        }
        try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: skillFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try skillText(name: "brainstorming", body: "Use for ideation.")
            .write(to: skillFile, atomically: true, encoding: .utf8)

        let scan = try CapabilityScanner().scan(
            projectRoot: projectRoot,
            options: ScanOptions(userSkillRoots: [cacheRoot])
        )
        let graph = CapabilityResolver().resolve(scanResult: scan)

        let skill = try XCTUnwrap(graph.capabilities.first { $0.name == "brainstorming" && $0.type == .skill })
        XCTAssertEqual(skill.pluginID, "plugin:codex-cache:openai-curated:superpowers")
        XCTAssertEqual(skill.source.packageName, "superpowers")

        let plugin = try XCTUnwrap(graph.capabilities.first { $0.id == "plugin:codex-cache:openai-curated:superpowers" })
        XCTAssertEqual(plugin.name, "Superpowers")
        XCTAssertEqual(plugin.type, .plugin)
        XCTAssertEqual(plugin.scope, .user)
        XCTAssertTrue(plugin.source.path.hasSuffix("/.codex/plugins/cache/openai-curated/superpowers"))
    }

    func testCodexPluginCacheSkillInheritsPluginLifecycleCommands() throws {
        let projectRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("OrbitaProject-\(UUID().uuidString)")
        let registryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("OrbitaPluginCache-\(UUID().uuidString)")
        let cacheRoot = registryRoot.appendingPathComponent(".codex/plugins/cache")
        let config = registryRoot.appendingPathComponent(".codex/config.toml")
        let skillFile = cacheRoot
            .appendingPathComponent("openai-curated")
            .appendingPathComponent("superpowers")
            .appendingPathComponent("6188456f")
            .appendingPathComponent("skills")
            .appendingPathComponent("brainstorming")
            .appendingPathComponent("SKILL.md")
        defer {
            try? FileManager.default.removeItem(at: projectRoot)
            try? FileManager.default.removeItem(at: registryRoot)
        }
        try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: skillFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: config.deletingLastPathComponent(), withIntermediateDirectories: true)
        try skillText(name: "brainstorming", body: "Use for ideation.")
            .write(to: skillFile, atomically: true, encoding: .utf8)
        try """
        [plugins."superpowers@openai-curated"]
        enabled = true
        """.write(to: config, atomically: true, encoding: .utf8)

        let result = try CapabilityScanner().scan(
            projectRoot: projectRoot,
            options: ScanOptions(userSkillRoots: [cacheRoot], codexConfigURL: config)
        )

        let skill = try XCTUnwrap(result.capabilities.first { $0.name == "brainstorming" && $0.type == .skill })
        XCTAssertEqual(skill.statuses, [.enabled])
        XCTAssertEqual(skill.metadata["manager"], "codex")
        XCTAssertEqual(skill.metadata["pluginSelector"], "superpowers@openai-curated")
        XCTAssertEqual(skill.metadata["enableMode"], "plugin-add")
        XCTAssertEqual(skill.metadata["disableMode"], "config")
        // The auto-run check command must be READ-ONLY (the App runs it merely on selecting a tile, with no
        // confirmation); `marketplace upgrade` (side-effecting/network) lives only in the confirmed updateCommand.
        XCTAssertTrue(skill.metadata["checkCommand"]?.contains("codex plugin list --marketplace 'openai-curated'") == true)
        XCTAssertFalse(skill.metadata["checkCommand"]?.contains("marketplace upgrade") == true)
        XCTAssertTrue(skill.metadata["updateCommand"]?.contains("codex plugin marketplace upgrade 'openai-curated'") == true)
        XCTAssertTrue(skill.metadata["updateCommand"]?.contains("codex plugin add 'superpowers@openai-curated'") == true)
        XCTAssertTrue(skill.metadata["deleteCommand"]?.contains("codex plugin remove 'superpowers@openai-curated'") == true)
        XCTAssertNil(skill.metadata["codexDisableCommand"])
        XCTAssertNil(skill.metadata["codexEnableCommand"])

        // Native-first gating: the bundled skill carries a plugin `disableCommand`, so disabling it must
        // flow through the plugin's config lifecycle — NEVER the destructive disabled-store quarantine.
        // This locks in that hasNativeDisable() recognizes the generic `disableCommand` key.
        XCTAssertTrue(skill.metadata["disableCommand"]?.contains("enabled = false") == true)
        let graph = CapabilityResolver().resolve(scanResult: result)
        let resolvedSkill = try XCTUnwrap(graph.capabilities.first { $0.name == "brainstorming" && $0.type == .skill })
        let disablePlan = try ApplyPlanBuilder().planDisable(capabilityID: resolvedSkill.id, graph: graph)
        XCTAssertFalse(
            disablePlan.operations.contains { $0.kind == .cachePath },
            "a plugin-bundled Codex skill must not be physically quarantined; its disable is native (config)"
        )
    }

    func testBrokenAgentsSkillSymlinkIsReported() throws {
        let temporaryRoot = FileManager.default.temporaryDirectory.standardizedFileURL
            .appendingPathComponent("OrbitaCoreTests-\(UUID().uuidString)")
        let skillsRoot = temporaryRoot.appendingPathComponent(".agents/skills")
        try FileManager.default.createDirectory(at: skillsRoot, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: skillsRoot.appendingPathComponent("missing-skill"),
            withDestinationURL: URL(fileURLWithPath: "../missing-skill")
        )
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }

        let result = try scanProjectOnly(temporaryRoot)

        XCTAssertTrue(result.capabilities.contains { capability in
            capability.name == "missing-skill" && capability.statuses.contains(.broken)
        })
    }

    /// Regression for the write-boundary symlink-escape (applysafety-1/-2): a removePath whose ancestor is
    /// an in-project symlink to an external directory must be rejected before any OS-level delete, because
    /// `removeItem` would otherwise follow the ancestor symlink and delete a file outside the project.
    func testApplyExecutorRejectsRemovePathEscapingProjectViaAncestorSymlink() throws {
        let fm = FileManager.default
        let projectRoot = fm.temporaryDirectory.standardizedFileURL
            .appendingPathComponent("OrbitaCoreTests-\(UUID().uuidString)")
        let externalRoot = fm.temporaryDirectory.standardizedFileURL
            .appendingPathComponent("OrbitaCoreTests-victim-\(UUID().uuidString)")
        try fm.createDirectory(at: projectRoot, withIntermediateDirectories: true)
        try fm.createDirectory(at: externalRoot, withIntermediateDirectories: true)
        let victim = externalRoot.appendingPathComponent("victim.txt")
        try "do not delete".write(to: victim, atomically: true, encoding: .utf8)
        // An in-project directory symlink pointing OUTSIDE the project tree.
        let escapeLink = projectRoot.appendingPathComponent("inner")
        try fm.createSymbolicLink(at: escapeLink, withDestinationURL: externalRoot)
        defer {
            try? fm.removeItem(at: projectRoot)
            try? fm.removeItem(at: externalRoot)
        }

        let plan = ApplyPlan(
            projectRoot: projectRoot.path,
            action: .delete,
            capabilityID: "test:escape",
            requiresConfirmation: true,
            operations: [
                ApplyOperation(
                    kind: .removePath,
                    path: escapeLink.appendingPathComponent("victim.txt").path,
                    risk: .write,
                    description: "Hard delete capability source"
                )
            ]
        )

        XCTAssertThrowsError(try ApplyPlanExecutor().apply(plan)) { error in
            let message = (error as? ApplyExecutionError)?.message ?? "\(error)"
            XCTAssertTrue(message.contains("outside the project"), "unexpected error: \(message)")
        }
        XCTAssertTrue(fm.fileExists(atPath: victim.path), "a file outside the project must not be deleted")
    }

    /// Positive control: the symlink hardening must not over-tighten — a legitimate hard delete of a real
    /// source physically inside the project (e.g. a node_modules package skill) still applies.
    func testApplyExecutorAllowsRemovePathForRealInProjectSource() throws {
        let fm = FileManager.default
        let projectRoot = fm.temporaryDirectory.standardizedFileURL
            .appendingPathComponent("OrbitaCoreTests-\(UUID().uuidString)")
        let packageSkill = projectRoot.appendingPathComponent("node_modules/pkg/skill.md")
        try fm.createDirectory(at: packageSkill.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "source".write(to: packageSkill, atomically: true, encoding: .utf8)
        defer { try? fm.removeItem(at: projectRoot) }

        let plan = ApplyPlan(
            projectRoot: projectRoot.path,
            action: .delete,
            capabilityID: "test:real",
            requiresConfirmation: true,
            operations: [
                ApplyOperation(
                    kind: .removePath,
                    path: packageSkill.path,
                    risk: .write,
                    description: "Hard delete capability source"
                )
            ]
        )

        _ = try ApplyPlanExecutor().apply(plan)
        XCTAssertFalse(fm.fileExists(atPath: packageSkill.path), "an in-project source should be deletable")
    }

    /// Regression for the view/preview divergence (datamodel-4 / cohesion-8): a Claude-native `claude-plugin`
    /// capability that the Claude view shows as visible must also be reported `supported` by the adapter
    /// preview. Before the shared `CapabilityClassifier`, the adapter recognized only `claude-plugin-agent`,
    /// so such a plugin was view-visible yet `supported: false` in the generated capabilities.json.
    func testClaudePluginIsBothViewVisibleAndAdapterSupported() throws {
        let plugin = Capability(
            id: "claude-plugin:demo",
            name: "demo",
            type: .plugin,
            scope: .user,
            statuses: [.enabled],
            risks: [.info],
            source: CapabilitySource(kind: "claude-plugin", path: "/tmp/plugins/demo"),
            pluginID: "claude:demo",
            metadata: ["manager": "claude-code", "pluginSelector": "demo@market"]
        )
        let graph = CapabilityGraph(projectRoot: "/tmp/proj", capabilities: [plugin], issues: [])

        let view = AgentViewResolver().view(for: .claudeCode, graph: graph)
        XCTAssertTrue(
            view.visibleCapabilities.contains { $0.id == plugin.id },
            "a claude-plugin should be visible in the Claude view"
        )

        let preview = AdapterPreviewBuilder().preview(for: .claudeCode, graph: graph)
        let mapping = try XCTUnwrap(preview.capabilityMappings.first { $0.capabilityID == plugin.id })
        XCTAssertTrue(
            mapping.supported,
            "a Claude-native plugin visible in the view must be supported in the adapter preview"
        )
        XCTAssertTrue(preview.supportedCapabilities.contains { $0.id == plugin.id })
    }

    /// A Claude Code plugin must not be reported as loadable by Codex. The codex adapter mapping
    /// previously marked every `.plugin` supported, so a `claude-plugin` showed "Codex loads it" in
    /// the loadability panel even though the Codex view (correctly) hides it. View and preview must
    /// agree via the shared `CapabilityClassifier.isCodexNativePlugin`.
    func testClaudePluginIsNotLoadableByCodexInAdapterPreview() throws {
        let plugin = Capability(
            id: "claude-plugin:demo",
            name: "demo",
            type: .plugin,
            scope: .user,
            statuses: [.enabled],
            risks: [.info],
            source: CapabilitySource(kind: "claude-plugin", path: "/tmp/plugins/demo"),
            pluginID: "claude:demo",
            metadata: ["manager": "claude-code", "pluginSelector": "demo@market"]
        )
        let graph = CapabilityGraph(projectRoot: "/tmp/proj", capabilities: [plugin], issues: [])

        let view = AgentViewResolver().view(for: .codex, graph: graph)
        XCTAssertFalse(
            view.visibleCapabilities.contains { $0.id == plugin.id },
            "a claude-plugin must not be visible in the Codex view"
        )

        let preview = AdapterPreviewBuilder().preview(for: .codex, graph: graph)
        let mapping = try XCTUnwrap(preview.capabilityMappings.first { $0.capabilityID == plugin.id })
        XCTAssertFalse(
            mapping.supported,
            "Codex must not report it loads a Claude Code plugin in the adapter preview"
        )
        XCTAssertFalse(preview.supportedCapabilities.contains { $0.id == plugin.id })
    }

    /// End-to-end coverage for the riskiest write — a user-scope fork into a real agent home (testing-3).
    /// The injectable `homeDirectory` seam lets the builder target, and the executor's write guard allow,
    /// a temporary home instead of the developer's real `~/.codex`. Without the seam this path was build-
    /// only: the executor would reject the temp-home write as "outside known agent storage".
    func testUserScopeCommandForkWritesIntoInjectedHome() throws {
        let fm = FileManager.default
        let projectRoot = fm.temporaryDirectory.standardizedFileURL
            .appendingPathComponent("OrbitaCoreTests-\(UUID().uuidString)")
        let fakeHome = fm.temporaryDirectory.standardizedFileURL
            .appendingPathComponent("OrbitaCoreTests-home-\(UUID().uuidString)")
        let commandSource = projectRoot.appendingPathComponent(".agents/commands/foo.md")
        try fm.createDirectory(at: commandSource.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.createDirectory(at: fakeHome, withIntermediateDirectories: true)
        try "# foo".write(to: commandSource, atomically: true, encoding: .utf8)
        defer {
            try? fm.removeItem(at: projectRoot)
            try? fm.removeItem(at: fakeHome)
        }

        let command = Capability(
            id: "command:foo",
            name: "foo",
            type: .command,
            scope: .project,
            statuses: [.enabled],
            risks: [.info],
            source: CapabilitySource(kind: "agents-command", path: commandSource.path),
            metadata: ["sourcePath": commandSource.path]
        )
        let graph = CapabilityGraph(projectRoot: projectRoot.path, capabilities: [command], issues: [])

        let plan = try ApplyPlanBuilder(homeDirectory: fakeHome).planSyncInstallTarget(
            capabilityID: command.id,
            agentID: "codex",
            graph: graph,
            mode: .copy,
            destinationScope: .user
        )
        _ = try ApplyPlanExecutor(homeDirectory: fakeHome).apply(plan)

        let forked = fakeHome.appendingPathComponent(".codex/commands/foo.md")
        XCTAssertTrue(fm.fileExists(atPath: forked.path), "user-scope command fork should land in the injected home")
        XCTAssertEqual(try String(contentsOf: forked, encoding: .utf8), "# foo")
    }

    /// errors-2: a malformed `.agents/manifest.json` breaks the user's declared intent and must be surfaced
    /// as an `.error`-severity issue (previously a `.warning`, indistinguishable from a benign file-count cap).
    func testMalformedAgentsManifestIsReportedAsError() throws {
        let fm = FileManager.default
        let projectRoot = fm.temporaryDirectory.standardizedFileURL
            .appendingPathComponent("OrbitaCoreTests-\(UUID().uuidString)")
        let manifest = projectRoot.appendingPathComponent(".agents/manifest.json")
        try fm.createDirectory(at: manifest.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "{ this is not valid json".write(to: manifest, atomically: true, encoding: .utf8)
        defer { try? fm.removeItem(at: projectRoot) }

        let result = try scanProjectOnly(projectRoot)
        XCTAssertTrue(
            result.issues.contains { $0.severity == .error && $0.path == manifest.path },
            "a malformed .agents/manifest.json should be reported as an error-severity issue"
        )
    }

    func testScansConfiguredUserSkillRootsOnlyWhenEnabled() throws {
        let projectRoot = FileManager.default.temporaryDirectory.standardizedFileURL
            .appendingPathComponent("OrbitaCoreTests-\(UUID().uuidString)")
        let userRoot = FileManager.default.temporaryDirectory.standardizedFileURL
            .appendingPathComponent("OrbitaUserSkills-\(UUID().uuidString)")
        let userSkill = userRoot.appendingPathComponent("skills/global-doc/SKILL.md")
        try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: userSkill.deletingLastPathComponent(), withIntermediateDirectories: true)
        try """
        ---
        name: global-doc
        description: User-global documentation helper.
        ---

        # Global Doc
        """.write(to: userSkill, atomically: true, encoding: .utf8)
        defer {
            try? FileManager.default.removeItem(at: projectRoot)
            try? FileManager.default.removeItem(at: userRoot)
        }

        let enabled = try CapabilityScanner().scan(
            projectRoot: projectRoot,
            options: ScanOptions(includeUserScope: true, userSkillRoots: [userRoot])
        )
        let disabled = try CapabilityScanner().scan(
            projectRoot: projectRoot,
            options: ScanOptions(includeUserScope: false, userSkillRoots: [userRoot])
        )

        XCTAssertTrue(enabled.capabilities.contains { $0.name == "global-doc" && $0.scope == .user && $0.source.kind == "user-skill" })
        XCTAssertFalse(disabled.capabilities.contains { $0.name == "global-doc" })
    }

    func testResolverMarksUserCapabilityShadowedAndDriftedByProjectCapability() throws {
        let projectRoot = FileManager.default.temporaryDirectory.standardizedFileURL
            .appendingPathComponent("OrbitaCoreTests-\(UUID().uuidString)")
        let projectSkill = projectRoot.appendingPathComponent("skills/global-doc/SKILL.md")
        let userRoot = FileManager.default.temporaryDirectory.standardizedFileURL
            .appendingPathComponent("OrbitaUserSkills-\(UUID().uuidString)")
        let userSkill = userRoot.appendingPathComponent("skills/global-doc/SKILL.md")
        try FileManager.default.createDirectory(at: projectSkill.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: userSkill.deletingLastPathComponent(), withIntermediateDirectories: true)
        try skillText(name: "global-doc", body: "project version").write(to: projectSkill, atomically: true, encoding: .utf8)
        try skillText(name: "global-doc", body: "user version").write(to: userSkill, atomically: true, encoding: .utf8)
        defer {
            try? FileManager.default.removeItem(at: projectRoot)
            try? FileManager.default.removeItem(at: userRoot)
        }

        let scan = try CapabilityScanner().scan(
            projectRoot: projectRoot,
            options: ScanOptions(includeUserScope: true, userSkillRoots: [userRoot])
        )

        let graph = CapabilityResolver().resolve(scanResult: scan)

        let project = try XCTUnwrap(graph.capabilities.first { $0.name == "global-doc" && $0.scope == .project })
        let user = try XCTUnwrap(graph.capabilities.first { $0.name == "global-doc" && $0.scope == .user })
        XCTAssertFalse(project.statuses.contains(.shadowed))
        XCTAssertTrue(project.statuses.contains(.drifted))
        XCTAssertTrue(user.statuses.contains(.shadowed))
        XCTAssertTrue(user.statuses.contains(.drifted))

        // The resolver records *where* the drift is so the inspector can name every copy.
        XCTAssertEqual(project.metadata["driftLocationCount"], "2")
        XCTAssertEqual(user.metadata["driftLocationCount"], "2")

        func driftLocations(_ capability: Capability) throws -> [DriftLocation] {
            let json = try XCTUnwrap(capability.metadata["driftLocationsJSON"])
            let data = try XCTUnwrap(json.data(using: .utf8))
            return try JSONDecoder().decode([DriftLocation].self, from: data)
        }

        let projectLocations = try driftLocations(project)
        let userLocations = try driftLocations(user)
        XCTAssertEqual(projectLocations.count, 2)
        XCTAssertEqual(userLocations.count, 2)

        // Each member flags exactly one location as the tile being inspected, and it is itself.
        XCTAssertEqual(projectLocations.filter { $0.current }.count, 1)
        XCTAssertEqual(userLocations.filter { $0.current }.count, 1)
        let projectCurrent = try XCTUnwrap(projectLocations.first { $0.current })
        let userCurrent = try XCTUnwrap(userLocations.first { $0.current })
        XCTAssertEqual(projectCurrent.scope, "project")
        XCTAssertEqual(userCurrent.scope, "user")
        XCTAssertTrue(projectCurrent.path.contains("global-doc"))

        // The whole point of drift: the two copies carry differing, non-empty content hashes.
        let hashes = Set(projectLocations.map(\.hash))
        XCTAssertEqual(hashes.count, 2)
        XCTAssertFalse(hashes.contains(""))

        // Both members enumerate the same location set — only `current` differs between them.
        XCTAssertEqual(Set(projectLocations.map(\.path)), Set(userLocations.map(\.path)))
    }

    func testResolverAppliesAgentsManifestDisabledStatusAndMarksDriftedWhenSourceStillExists() throws {
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("OrbitaCoreTests-\(UUID().uuidString)")
        try FileManager.default.copyItem(at: try fixtureURL("MixedProject"), to: temporaryRoot)
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }

        let initialGraph = CapabilityResolver().resolve(scanResult: try scanProjectOnly(temporaryRoot))
        let skill = try XCTUnwrap(initialGraph.capabilities.first { $0.name == "lark-doc" && $0.type == .skill })
        let manifest = temporaryRoot.appendingPathComponent(".agents/manifest.json")
        try FileManager.default.createDirectory(at: manifest.deletingLastPathComponent(), withIntermediateDirectories: true)
        try """
        {
          "schemaVersion": 1,
          "capabilities": [
            {
              "id": "\(skill.id)",
              "name": "\(skill.name)",
              "type": "\(skill.type.rawValue)",
              "status": "disabled",
              "sourcePath": "\(skill.source.path)"
            }
          ]
        }
        """.write(to: manifest, atomically: true, encoding: .utf8)

        let graph = CapabilityResolver().resolve(scanResult: try scanProjectOnly(temporaryRoot))

        let resolvedSkill = try XCTUnwrap(graph.capabilities.first { $0.id == skill.id })
        XCTAssertTrue(resolvedSkill.statuses.contains(.disabled))
        XCTAssertTrue(resolvedSkill.statuses.contains(.drifted))
        XCTAssertEqual(resolvedSkill.metadata["manifestStatus"], "disabled")
    }

    func testResolverDoesNotShadowRealCapabilityWithNoMatchDisabledManifestIntent() throws {
        // LOW-5-phantom-badges: a no-match `disabled` manifest intent synthesizes an
        // `agents-intent-missing-source` tile (scope .project, [.disabled], attacker-chosen name). A name
        // colliding with a real user-scope capability used to let the project-scope phantom win the scope
        // comparison and stamp false .shadowed/.duplicate on the real capability. It must not.
        let projectRoot = FileManager.default.temporaryDirectory.standardizedFileURL
            .appendingPathComponent("OrbitaCoreTests-\(UUID().uuidString)")
        let userRoot = FileManager.default.temporaryDirectory.standardizedFileURL
            .appendingPathComponent("OrbitaUserSkills-\(UUID().uuidString)")
        let userSkill = userRoot.appendingPathComponent("skills/phantom-collide/SKILL.md")
        try FileManager.default.createDirectory(at: userSkill.deletingLastPathComponent(), withIntermediateDirectories: true)
        try skillText(name: "phantom-collide", body: "real user skill").write(to: userSkill, atomically: true, encoding: .utf8)

        let manifest = projectRoot.appendingPathComponent(".agents/manifest.json")
        try FileManager.default.createDirectory(at: manifest.deletingLastPathComponent(), withIntermediateDirectories: true)
        try """
        {
          "schemaVersion": 1,
          "capabilities": [
            {
              "id": "skill:nonexistent-phantom-id",
              "name": "phantom-collide",
              "type": "skill",
              "status": "disabled",
              "sourcePath": "/tmp/orbita-nonexistent-phantom/SKILL.md"
            }
          ]
        }
        """.write(to: manifest, atomically: true, encoding: .utf8)
        defer {
            try? FileManager.default.removeItem(at: projectRoot)
            try? FileManager.default.removeItem(at: userRoot)
        }

        let scan = try CapabilityScanner().scan(
            projectRoot: projectRoot,
            options: ScanOptions(includeUserScope: true, userSkillRoots: [userRoot])
        )
        let graph = CapabilityResolver().resolve(scanResult: scan)

        let real = try XCTUnwrap(graph.capabilities.first { $0.name == "phantom-collide" && $0.scope == .user })
        XCTAssertFalse(real.statuses.contains(.shadowed), "a no-match disabled manifest intent must not shadow a real capability")
        XCTAssertFalse(real.statuses.contains(.duplicate), "a no-match disabled manifest intent must not flag a real capability duplicate")
        XCTAssertFalse(real.statuses.contains(.drifted), "a no-match disabled manifest intent must not flag a real capability drifted")

        let phantom = try XCTUnwrap(graph.capabilities.first { $0.source.kind == "agents-intent-missing-source" })
        XCTAssertEqual(phantom.name, "phantom-collide")
        XCTAssertTrue(phantom.statuses.contains(.disabled))
        XCTAssertFalse(phantom.statuses.contains(.shadowed))
        XCTAssertFalse(phantom.statuses.contains(.duplicate))
    }

    func testResolverManifestPathFallbackCannotTamperWithUserScopeCapability() throws {
        // MED-3-manifest-or-match: a project `.agents/manifest.json` is untrusted. An intent whose declared
        // capabilityID matches NOTHING, but whose sourcePath equals an unrelated USER-scope (global)
        // capability's source.path, must NOT have its disabled/drifted status applied to that user capability,
        // nor (via the synthesized missing-source tile) shadow/duplicate it.
        let userSkillPath = "/Users/victim/.codex/skills/global-helper/SKILL.md"
        let userSkill = Capability(
            id: "skill:\(userSkillPath)",
            name: "global-helper",
            type: .skill,
            scope: .user,
            statuses: [.enabled],
            risks: [.read, .global],
            source: CapabilitySource(kind: "codex-skill", path: userSkillPath)
        )
        let maliciousIntent = Capability(
            id: "agents-intent:skill:attacker-bogus-id",
            name: "global-helper",
            type: .skill,
            scope: .project,
            statuses: [.discovered],
            risks: [.info, .read],
            source: CapabilitySource(kind: "agents-intent", path: "/tmp/evil-proj/.agents/manifest.json"),
            metadata: [
                "capabilityID": "skill:attacker-bogus-id",
                "manifestStatus": "disabled",
                "sourcePath": userSkillPath
            ]
        )
        let graph = CapabilityResolver().resolve(scanResult: ScanResult(
            projectRoot: "/tmp/evil-proj",
            capabilities: [userSkill, maliciousIntent],
            issues: []
        ))

        let resolvedUserSkill = try XCTUnwrap(graph.capabilities.first { $0.id == userSkill.id })
        XCTAssertFalse(resolvedUserSkill.statuses.contains(.disabled), "untrusted project manifest must not disable a user-scope capability by path")
        XCTAssertFalse(resolvedUserSkill.statuses.contains(.drifted), "untrusted project manifest must not drift a user-scope capability by path")
        XCTAssertNil(resolvedUserSkill.metadata["manifestStatus"], "user-scope capability must carry no manifest-applied status")
        XCTAssertTrue(resolvedUserSkill.statuses.contains(.enabled), "user-scope capability stays as scanned")
        XCTAssertFalse(resolvedUserSkill.statuses.contains(.shadowed), "untrusted project manifest must not shadow a user-scope capability via name-collision tile")
        XCTAssertFalse(resolvedUserSkill.statuses.contains(.duplicate), "untrusted project manifest must not mark a user-scope capability duplicate via name-collision tile")
        XCTAssertNil(resolvedUserSkill.metadata["duplicateRelationship"], "user-scope capability must carry no duplicate-relationship metadata from the manifest tile")
        XCTAssertTrue(graph.capabilities.contains { $0.id == "skill:attacker-bogus-id" && $0.source.kind == "agents-intent-missing-source" })
    }

    func testResolverManifestPathFallbackStillMatchesProjectScopeCapability() throws {
        // Legit defensive case the OR fallback exists for: the manifest id has drifted but the recorded
        // sourcePath still points at a live PROJECT-scope capability. The path fallback must still apply
        // disabled+drifted to that project capability (the manifest's own domain).
        let projectSkillPath = "/tmp/legit-proj/.agents/skills/lark-doc/SKILL.md"
        let projectSkill = Capability(
            id: "skill:\(projectSkillPath)",
            name: "lark-doc",
            type: .skill,
            scope: .project,
            statuses: [.enabled],
            risks: [.read],
            source: CapabilitySource(kind: "agents-skill", path: projectSkillPath)
        )
        let intent = Capability(
            id: "agents-intent:skill:stale-drifted-id",
            name: "lark-doc",
            type: .skill,
            scope: .project,
            statuses: [.discovered],
            risks: [.info, .read],
            source: CapabilitySource(kind: "agents-intent", path: "/tmp/legit-proj/.agents/manifest.json"),
            metadata: [
                "capabilityID": "skill:stale-drifted-id",
                "manifestStatus": "disabled",
                "sourcePath": projectSkillPath
            ]
        )
        let graph = CapabilityResolver().resolve(scanResult: ScanResult(
            projectRoot: "/tmp/legit-proj",
            capabilities: [projectSkill, intent],
            issues: []
        ))

        let resolved = try XCTUnwrap(graph.capabilities.first { $0.id == projectSkill.id })
        XCTAssertTrue(resolved.statuses.contains(.disabled), "project-scope capability is the manifest's own domain — path fallback must still disable it")
        XCTAssertTrue(resolved.statuses.contains(.drifted))
        XCTAssertEqual(resolved.metadata["manifestStatus"], "disabled")
    }

    func testAgentViewFiltersCodexVisibleCapabilities() throws {
        let root = try fixtureURL("MixedProject")
        let scan = try scanProjectOnly(root)
        let graph = CapabilityResolver().resolve(scanResult: scan)

        let view = AgentViewResolver().view(for: .codex, graph: graph)

        XCTAssertTrue(view.visibleCapabilities.contains { $0.type == .skill })
        XCTAssertTrue(view.visibleCapabilities.contains { $0.type == .plugin })
        XCTAssertFalse(view.visibleCapabilities.contains { $0.type == .rule })
    }

    func testVisibleCapabilitiesFastPathMatchesFullView() throws {
        let root = try fixtureURL("MixedProject")
        let graph = CapabilityResolver().resolve(scanResult: try scanProjectOnly(root))
        let resolver = AgentViewResolver()

        // The visible-only fast path used by the App's tab views must return
        // exactly the same list (same order) as view(for:graph:).visibleCapabilities.
        for agent in [AgentID.codex, .claudeCode, .cursor, .trae] {
            XCTAssertEqual(
                resolver.visibleCapabilities(for: agent, graph: graph).map(\.id),
                resolver.view(for: agent, graph: graph).visibleCapabilities.map(\.id),
                "fast path diverged from full view for \(agent)"
            )
        }
    }

    func testAgentViewsRespectClientSpecificCommandSources() throws {
        let root = try fixtureURL("MixedProject")
        let graph = CapabilityResolver().resolve(scanResult: try scanProjectOnly(root))

        let codex = AgentViewResolver().view(for: .codex, graph: graph)
        let claude = AgentViewResolver().view(for: .claudeCode, graph: graph)
        let cursor = AgentViewResolver().view(for: .cursor, graph: graph)

        XCTAssertTrue(codex.visibleCapabilities.contains { $0.name == "bootstrap" && $0.source.kind == "codex-command" })
        XCTAssertFalse(codex.visibleCapabilities.contains { $0.name == "review" && $0.source.kind == "claude-command" })
        XCTAssertTrue(claude.visibleCapabilities.contains { $0.name == "review" && $0.source.kind == "claude-command" })
        XCTAssertTrue(claude.visibleCapabilities.contains { $0.name == "Swift - PostToolUse (Write)" && $0.source.kind == "claude-settings-hook" })
        XCTAssertFalse(cursor.visibleCapabilities.contains { $0.name == "review" && $0.source.kind == "claude-command" })
    }

    func testTraeAgentViewExcludesAgentsSkillsAndNativeOnes() throws {
        // Trae reads its own .trae/skills, not the shared .agents workspace. An .agents skill is
        // managed in the .agents tab and stays hidden from Trae — even when its skills-CLI lock lists
        // trae (those are just symlinks back into .agents, which the scanner collapses). Only a skill
        // the host genuinely owns (a real .trae dir) shows in Trae.
        let agentsSkill = Capability(
            id: "skill:.agents:shared-doc",
            name: "shared-doc",
            type: .skill,
            scope: .project,
            statuses: [.enabled],
            risks: [.read],
            source: CapabilitySource(kind: "agents-skill", path: "/tmp/project/.agents/skills/shared-doc/SKILL.md")
        )
        let lockListedAgentsSkill = Capability(
            id: "skill:.agents:synced-doc",
            name: "synced-doc",
            type: .skill,
            scope: .project,
            statuses: [.enabled],
            risks: [.read],
            source: CapabilitySource(kind: "agents-skill", path: "/tmp/project/.agents/skills/synced-doc/SKILL.md"),
            metadata: ["skillsInstalledAgentIDs": "codex,trae"]
        )
        let codexSkill = Capability(
            id: "skill:.codex:codex-doc",
            name: "codex-doc",
            type: .skill,
            scope: .project,
            statuses: [.enabled],
            risks: [.read],
            source: CapabilitySource(kind: "codex-skill", path: "/tmp/project/.codex/skills/codex-doc/SKILL.md")
        )
        let claudeSkill = Capability(
            id: "skill:.claude:review-helper",
            name: "review-helper",
            type: .skill,
            scope: .project,
            statuses: [.enabled],
            risks: [.read],
            source: CapabilitySource(kind: "claude-skill", path: "/tmp/project/.claude/skills/review-helper/SKILL.md")
        )
        let claudePlugin = Capability(
            id: "plugin:claude:im-knowledge",
            name: "Im Knowledge",
            type: .plugin,
            scope: .user,
            statuses: [.enabled],
            risks: [.info],
            source: CapabilitySource(kind: "claude-plugin", path: "/tmp/cache/marketplace/im-knowledge/1.0.0", packageName: "im-knowledge")
        )
        let traeNativeSkill = Capability(
            id: "skill:.trae:trae-helper",
            name: "trae-helper",
            type: .skill,
            scope: .user,
            statuses: [.enabled],
            risks: [.read],
            source: CapabilitySource(kind: "trae-skill", path: "/Users/dev/.trae/skills/trae-helper/SKILL.md")
        )
        let codexPluginSkill = Capability(
            id: "skill:codex-plugin:build-macos-apps",
            name: "build-macos-apps",
            type: .skill,
            scope: .user,
            statuses: [.enabled],
            risks: [.read, .global],
            source: CapabilitySource(
                kind: "user-skill",
                path: "/Users/dev/.codex/plugins/cache/openai-curated/build-macos-apps/1.0.0/skills/build-macos-apps/SKILL.md",
                packageName: "build-macos-apps"
            ),
            pluginID: "plugin:codex-cache:openai-curated:build-macos-apps"
        )
        let mcpServer = Capability(
            id: "mcp:project-server",
            name: "project-server",
            type: .mcpServer,
            scope: .project,
            statuses: [.enabled],
            risks: [.network],
            source: CapabilitySource(kind: "mcp-config", path: "/tmp/project/.mcp.json")
        )
        let graph = CapabilityGraph(
            projectRoot: "/tmp/project",
            capabilities: [agentsSkill, lockListedAgentsSkill, codexSkill, claudeSkill, claudePlugin, traeNativeSkill, codexPluginSkill, mcpServer],
            issues: []
        )

        let traeView = AgentViewResolver().view(for: .trae, graph: graph)
        let visibleIDs = Set(traeView.visibleCapabilities.map { $0.id })

        XCTAssertFalse(visibleIDs.contains(agentsSkill.id), "Trae must NOT auto-load shared .agents/skills")
        XCTAssertFalse(visibleIDs.contains(lockListedAgentsSkill.id), "An .agents skill stays gated from Trae even when its lock lists trae; only a real .trae copy shows")
        XCTAssertTrue(visibleIDs.contains(traeNativeSkill.id), "Trae should pick up skills genuinely under ~/.trae/")
        XCTAssertTrue(visibleIDs.contains(mcpServer.id), "Trae should see project MCP servers")
        XCTAssertFalse(visibleIDs.contains(codexSkill.id), "Trae must not see Codex-native skills")
        XCTAssertFalse(visibleIDs.contains(claudeSkill.id), "Trae must not see Claude-native skills")
        XCTAssertFalse(visibleIDs.contains(claudePlugin.id), "Trae has no plugin surface and should ignore Claude plugins")
        XCTAssertFalse(visibleIDs.contains(codexPluginSkill.id), "Trae must not surface Codex plugin-bundled skills as Trae data")
    }

    func testTraeViewIncludesOwnDirSymlinkMirroringAgentsWorkspace() throws {
        // Mirrors the real setup: ~/.trae/skills full of symlinks back into ~/.agents/skills (created by
        // `npx skills`). Directory ownership: a symlink that physically lives under `.trae/skills` is
        // Trae's own — Trae loads it THROUGH that directory — so it IS visible in the Trae view (and
        // branded Trae), distinct from the `.agents` canonical that Codex reads in place. The scanner
        // still flags it `mirrorsAgentsWorkspace`, but own-dir membership now wins over that gate.
        let projectRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("OrbitaTraeSymlink-\(UUID().uuidString)")
        let agentsSharedDir = projectRoot.appendingPathComponent(".agents/skills/lark-doc")
        let traeSkillsRoot = projectRoot.appendingPathComponent(".trae/skills")
        let traeSymlink = traeSkillsRoot.appendingPathComponent("lark-doc")
        defer { try? FileManager.default.removeItem(at: projectRoot) }
        try FileManager.default.createDirectory(at: agentsSharedDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: traeSkillsRoot, withIntermediateDirectories: true)
        try skillText(name: "lark-doc", body: "Shared lark doc skill.")
            .write(to: agentsSharedDir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(at: traeSymlink, withDestinationURL: agentsSharedDir)

        let scan = try CapabilityScanner().scan(
            projectRoot: projectRoot,
            options: ScanOptions(includeUserScope: false, userSkillRoots: [])
        )
        let graph = CapabilityResolver().resolve(scanResult: scan)

        let traeSymlinkRecord = try XCTUnwrap(graph.capabilities.first { $0.name == "lark-doc" && $0.source.kind == "trae-skill" })
        XCTAssertEqual(traeSymlinkRecord.metadata["mirrorsAgentsWorkspace"], "true", "A .trae symlink into .agents is still flagged as agents-shared")

        let traeVisible = Set(AgentViewResolver().visibleCapabilities(for: .trae, graph: graph).map(\.name))
        XCTAssertTrue(traeVisible.contains("lark-doc"), "Trae owns the symlink that physically lives under .trae/skills and must show it")
    }

    func testTraeAndCursorGateAllAgentsScopedCapabilitiesUntilSynced() throws {
        // The gating applies to EVERY .agents capability type, not just skills: Codex reads the
        // shared workspace in place, but Trae/Cursor only see it once synced into their own dir.
        let agentsInstruction = Capability(
            id: "instruction:.agents:house-rules",
            name: "house-rules",
            type: .instruction,
            scope: .project,
            statuses: [.enabled],
            risks: [.read],
            source: CapabilitySource(kind: "agents-instruction", path: "/tmp/project/.agents/AGENTS.md")
        )
        let agentsMCP = Capability(
            id: "mcp:.agents:shared-server",
            name: "shared-server",
            type: .mcpServer,
            scope: .project,
            statuses: [.enabled],
            risks: [.network],
            source: CapabilitySource(kind: "mcp-config", path: "/tmp/project/.agents/.mcp.json")
        )
        let graph = CapabilityGraph(
            projectRoot: "/tmp/project",
            capabilities: [agentsInstruction, agentsMCP],
            issues: []
        )

        let codex = Set(AgentViewResolver().visibleCapabilities(for: .codex, graph: graph).map(\.id))
        let trae = Set(AgentViewResolver().visibleCapabilities(for: .trae, graph: graph).map(\.id))
        let cursor = Set(AgentViewResolver().visibleCapabilities(for: .cursor, graph: graph).map(\.id))

        XCTAssertTrue(codex.contains(agentsInstruction.id), "Codex reads .agents instructions in place")
        XCTAssertTrue(codex.contains(agentsMCP.id), "Codex reads .agents MCP config in place")
        XCTAssertFalse(trae.contains(agentsInstruction.id), "Trae must not auto-load an .agents instruction until synced")
        XCTAssertFalse(trae.contains(agentsMCP.id), "Trae must not auto-load an .agents MCP server until synced")
        XCTAssertFalse(cursor.contains(agentsInstruction.id), "Cursor must not auto-load an .agents instruction until synced")
        XCTAssertFalse(cursor.contains(agentsMCP.id), "Cursor must not auto-load an .agents MCP server until synced")
    }

    func testScannerIncludesTraeSkillRootsAsTraeNativeOnly() throws {
        let projectRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("OrbitaTraeProject-\(UUID().uuidString)")
        let projectSkill = projectRoot.appendingPathComponent(".trae/skills/project-trae")
        let userRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("OrbitaTraeUser-\(UUID().uuidString)")
            .appendingPathComponent(".trae/skills")
        let userSkill = userRoot.appendingPathComponent("user-trae")
        defer {
            try? FileManager.default.removeItem(at: projectRoot)
            try? FileManager.default.removeItem(at: userRoot.deletingLastPathComponent().deletingLastPathComponent())
        }

        try FileManager.default.createDirectory(at: projectSkill, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: userSkill, withIntermediateDirectories: true)
        try skillText(name: "project-trae", body: "Project Trae skill")
            .write(to: projectSkill.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        try skillText(name: "user-trae", body: "User Trae skill")
            .write(to: userSkill.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)

        let result = try CapabilityScanner().scan(
            projectRoot: projectRoot,
            options: ScanOptions(
                includeUserScope: true,
                userSkillRoots: [userRoot],
                codexConfigURL: projectRoot.appendingPathComponent("missing-codex-config.toml"),
                codexPluginCacheRoot: projectRoot.appendingPathComponent("missing-codex-cache"),
                claudeInstalledPluginsURL: projectRoot.appendingPathComponent("missing-claude-plugins.json"),
                claudeSettingsURLs: []
            )
        )

        let scannedProjectSkill = try XCTUnwrap(result.capabilities.first { $0.name == "project-trae" })
        let scannedUserSkill = try XCTUnwrap(result.capabilities.first { $0.name == "user-trae" })
        XCTAssertEqual(scannedProjectSkill.source.kind, "trae-skill")
        XCTAssertEqual(scannedUserSkill.source.kind, "trae-skill")

        let graph = CapabilityGraph(projectRoot: projectRoot.path, capabilities: result.capabilities, issues: [])
        let traeIDs = Set(AgentViewResolver().view(for: .trae, graph: graph).visibleCapabilities.map(\.id))
        let codexIDs = Set(AgentViewResolver().view(for: .codex, graph: graph).visibleCapabilities.map(\.id))

        XCTAssertTrue(traeIDs.contains(scannedProjectSkill.id))
        XCTAssertTrue(traeIDs.contains(scannedUserSkill.id))
        XCTAssertFalse(codexIDs.contains(scannedProjectSkill.id))
        XCTAssertFalse(codexIDs.contains(scannedUserSkill.id))

        // Regression (user-scope Trae disable bug): scanUserSkillRoots passes a codexConfigPath for EVERY
        // user root, but a Trae skill has no Codex `[[skills.config]]` off-switch. It must NOT receive
        // codexSkillConfigPath/codexDisableCommand — otherwise ApplyPlan.hasNativeDisable() returns true and
        // short-circuits the disabled-store fallback, emitting a useless `[[skills.config]]` command pointed
        // into `.trae`. Both scopes must be Codex-disable-free.
        for traeSkill in [scannedProjectSkill, scannedUserSkill] {
            XCTAssertNil(traeSkill.metadata["codexSkillConfigPath"], "Trae skill must not be Codex-disable-capable")
            XCTAssertNil(traeSkill.metadata["codexDisableCommand"], "Trae skill must not carry a Codex disable command")
            XCTAssertNil(traeSkill.metadata["codexEnableCommand"])
        }
    }

    func testHostAgentIDsResolvesDisabledTileToOriginAgentWithoutMakingItVisible() {
        let resolver = AgentViewResolver()

        // A quarantined (disabled) Trae skill keeps its ORIGINAL .trae source path. It is absent from
        // every active view, but host derivation must still surface Trae so the tile shows the Trae icon.
        let quarantinedTrae = Capability(
            id: "skill:trae-disabled",
            name: "trae-disabled",
            type: .skill,
            scope: .user,
            statuses: [.disabled],
            risks: [.read],
            source: CapabilitySource(kind: "orbita-quarantine", path: "/Users/x/.trae/skills/trae-disabled/SKILL.md"),
            metadata: ["sourcePath": "/Users/x/.trae/skills/trae-disabled/SKILL.md"]
        )
        let graph = CapabilityGraph(projectRoot: "/Users/x/proj", capabilities: [quarantinedTrae], issues: [])
        XCTAssertEqual(resolver.hostAgentIDs(for: quarantinedTrae), [.trae])
        XCTAssertFalse(
            resolver.view(for: .trae, graph: graph).visibleCapabilities.contains { $0.id == quarantinedTrae.id },
            "A disabled tile must stay out of the active agent view"
        )

        // A Codex skill turned off natively via [[skills.config]] still resolves to Codex.
        let disabledCodex = Capability(
            id: "skill:codex-disabled",
            name: "codex-disabled",
            type: .skill,
            scope: .user,
            statuses: [.disabled],
            risks: [.read],
            source: CapabilitySource(kind: "codex-skill", path: "/Users/x/.codex/skills/codex-disabled/SKILL.md"),
            metadata: ["codexSkillEnabled": "false"]
        )
        XCTAssertEqual(resolver.hostAgentIDs(for: disabledCodex), [.codex])
    }

    func testCodexAgentViewExcludesClaudeNativePlugins() throws {
        let claudePlugin = Capability(
            id: "plugin:claude:im-knowledge",
            name: "Im Knowledge",
            type: .plugin,
            scope: .user,
            statuses: [.enabled],
            risks: [.info],
            source: CapabilitySource(kind: "claude-plugin", path: "/tmp/cache/marketplace/im-knowledge/1.0.0", packageName: "im-knowledge"),
            metadata: ["manager": "claude-code"]
        )
        let codexPlugin = Capability(
            id: "plugin:codex:formatter",
            name: "Formatter",
            type: .plugin,
            scope: .user,
            statuses: [.enabled],
            risks: [.info],
            source: CapabilitySource(kind: "codex-plugin", path: "/tmp/cache/codex/formatter/1.0.0", packageName: "formatter"),
            metadata: ["manager": "codex"]
        )
        let claudePluginChild = Capability(
            id: "command:/tmp/cache/marketplace/im-knowledge/1.0.0/commands/explain.md",
            name: "explain",
            type: .command,
            scope: .user,
            statuses: [.enabled],
            risks: [.read],
            source: CapabilitySource(kind: "claude-plugin-command", path: "/tmp/cache/marketplace/im-knowledge/1.0.0/commands/explain.md", packageName: "im-knowledge"),
            pluginID: claudePlugin.id,
            metadata: ["manager": "claude-code"]
        )
        let graph = CapabilityGraph(
            projectRoot: "/tmp/codex-plugin-visibility-test",
            capabilities: [claudePlugin, codexPlugin, claudePluginChild],
            issues: []
        )

        let codexView = AgentViewResolver().view(for: .codex, graph: graph)
        let codexVisibleIDs = Set(codexView.visibleCapabilities.map { $0.id })

        XCTAssertFalse(codexVisibleIDs.contains(claudePlugin.id), "Codex view must not include Claude-native plugins")
        XCTAssertFalse(codexVisibleIDs.contains(claudePluginChild.id), "Codex view must not include Claude plugin sub-capabilities")
        XCTAssertTrue(codexVisibleIDs.contains(codexPlugin.id), "Codex view should still include Codex-native plugins")
    }

    /// A marketplace plugin installed for BOTH Codex and Claude Code is not a
    /// conflict — they are independent plugin ecosystems. A same-named
    /// `codex-plugin` and `claude-plugin` must therefore not be flagged as
    /// duplicates/shadows of each other.
    func testCodexAndClaudePluginsWithSameNameAreNotDuplicates() throws {
        let claudePlugin = Capability(
            id: "plugin:claude:im-knowledge",
            name: "Im Knowledge",
            type: .plugin,
            scope: .user,
            statuses: [.enabled],
            risks: [.read],
            source: CapabilitySource(kind: "claude-plugin", path: "/Users/me/.claude/plugins/cache/unicorn-marketplace/im-knowledge/1.5.5", packageName: "im-knowledge"),
            metadata: ["manager": "claude-code", "installedVersion": "1.5.5"]
        )
        let codexPlugin = Capability(
            id: "plugin:codex:im-knowledge",
            name: "Im Knowledge",
            type: .plugin,
            scope: .user,
            statuses: [.enabled],
            risks: [.read],
            source: CapabilitySource(kind: "codex-plugin", path: "/Users/me/.codex/plugins/cache/unicorn-marketplace/im-knowledge", packageName: "im-knowledge"),
            metadata: ["manager": "codex", "installedVersion": "1.5.5"]
        )

        let graph = CapabilityResolver().resolve(scanResult: ScanResult(
            projectRoot: "/tmp/cross-ecosystem-plugin-test",
            capabilities: [claudePlugin, codexPlugin],
            issues: []
        ))

        let claude = try XCTUnwrap(graph.capabilities.first { $0.id == claudePlugin.id })
        let codex = try XCTUnwrap(graph.capabilities.first { $0.id == codexPlugin.id })

        XCTAssertFalse(claude.statuses.contains(.duplicate), "Claude plugin must not duplicate a same-named Codex plugin")
        XCTAssertFalse(codex.statuses.contains(.duplicate), "Codex plugin must not duplicate a same-named Claude plugin")
        XCTAssertFalse(claude.statuses.contains(.shadowed))
        XCTAssertFalse(codex.statuses.contains(.shadowed))
        XCTAssertNil(claude.metadata["duplicateRelationship"])
        XCTAssertNil(codex.metadata["duplicateRelationship"])
    }

    func testClaudeAgentViewShowsEffectivePluginScopeOnly() throws {
        let projectPlugin = Capability(
            id: "plugin:claude:workflow-unicorn-marketplace:project:aweme",
            name: "Workflow",
            type: .plugin,
            scope: .project,
            statuses: [.enabled],
            risks: [.info, .read],
            source: CapabilitySource(kind: "claude-plugin", path: "/tmp/cache/unicorn-marketplace/workflow/1.4.10", packageName: "workflow"),
            metadata: [
                "manager": "claude-code",
                "pluginSelector": "workflow@unicorn-marketplace",
                "managerScope": "project",
                "installedVersion": "1.4.10"
            ]
        )
        let localPlugin = Capability(
            id: "plugin:claude:workflow-unicorn-marketplace:local:aweme",
            name: "Workflow",
            type: .plugin,
            scope: .project,
            statuses: [.enabled],
            risks: [.info, .read],
            source: CapabilitySource(kind: "claude-plugin", path: "/tmp/cache/unicorn-marketplace/workflow/1.4.11", packageName: "workflow"),
            metadata: [
                "manager": "claude-code",
                "pluginSelector": "workflow@unicorn-marketplace",
                "managerScope": "local",
                "installedVersion": "1.4.11"
            ]
        )
        let projectCommand = Capability(
            id: "command:/tmp/cache/unicorn-marketplace/workflow/1.4.10/commands/unicorn-apply.md",
            name: "unicorn-apply",
            type: .command,
            scope: .project,
            statuses: [.enabled],
            risks: [.read],
            source: CapabilitySource(kind: "claude-plugin-command", path: "/tmp/cache/unicorn-marketplace/workflow/1.4.10/commands/unicorn-apply.md", packageName: "workflow"),
            pluginID: projectPlugin.id,
            metadata: [
                "manager": "claude-code",
                "pluginSelector": "workflow@unicorn-marketplace",
                "managerScope": "project",
                "installedVersion": "1.4.10"
            ]
        )
        let localCommand = Capability(
            id: "command:/tmp/cache/unicorn-marketplace/workflow/1.4.11/commands/unicorn-apply.md",
            name: "unicorn-apply",
            type: .command,
            scope: .project,
            statuses: [.enabled],
            risks: [.read],
            source: CapabilitySource(kind: "claude-plugin-command", path: "/tmp/cache/unicorn-marketplace/workflow/1.4.11/commands/unicorn-apply.md", packageName: "workflow"),
            pluginID: localPlugin.id,
            metadata: [
                "manager": "claude-code",
                "pluginSelector": "workflow@unicorn-marketplace",
                "managerScope": "local",
                "installedVersion": "1.4.11"
            ]
        )
        let rawGraph = CapabilityGraph(
            projectRoot: "/tmp/aweme",
            capabilities: [projectPlugin, localPlugin, projectCommand, localCommand],
            issues: []
        )

        let visibleIDs = Set(AgentViewResolver().view(for: .claudeCode, graph: rawGraph).visibleCapabilities.map(\.id))

        XCTAssertTrue(visibleIDs.contains(localPlugin.id))
        XCTAssertTrue(visibleIDs.contains(localCommand.id))
        XCTAssertFalse(visibleIDs.contains(projectPlugin.id))
        XCTAssertFalse(visibleIDs.contains(projectCommand.id))

        let resolvedGraph = CapabilityResolver().resolve(scanResult: ScanResult(
            projectRoot: "/tmp/aweme",
            capabilities: rawGraph.capabilities,
            issues: []
        ))
        let resolvedIDs = Set(resolvedGraph.capabilities.map(\.id))
        XCTAssertTrue(resolvedIDs.contains(localPlugin.id))
        XCTAssertTrue(resolvedIDs.contains(localCommand.id))
        XCTAssertFalse(resolvedIDs.contains(projectPlugin.id))
        XCTAssertFalse(resolvedIDs.contains(projectCommand.id))
    }

    func testClaudeAgentViewUsesLatestVersionWithinSamePluginScope() throws {
        let olderPlugin = Capability(
            id: "plugin:claude:workflow-unicorn-marketplace:local:aweme:old",
            name: "Workflow",
            type: .plugin,
            scope: .project,
            statuses: [.enabled],
            risks: [.info, .read],
            source: CapabilitySource(kind: "claude-plugin", path: "/tmp/cache/unicorn-marketplace/workflow/1.4.10", packageName: "workflow"),
            metadata: [
                "manager": "claude-code",
                "pluginSelector": "workflow@unicorn-marketplace",
                "managerScope": "local",
                "installedVersion": "1.4.10"
            ]
        )
        let latestPlugin = Capability(
            id: "plugin:claude:workflow-unicorn-marketplace:local:aweme:latest",
            name: "Workflow",
            type: .plugin,
            scope: .project,
            statuses: [.enabled],
            risks: [.info, .read],
            source: CapabilitySource(kind: "claude-plugin", path: "/tmp/cache/unicorn-marketplace/workflow/1.4.11", packageName: "workflow"),
            metadata: [
                "manager": "claude-code",
                "pluginSelector": "workflow@unicorn-marketplace",
                "managerScope": "local",
                "installedVersion": "1.4.11"
            ]
        )
        let graph = CapabilityGraph(
            projectRoot: "/tmp/aweme",
            capabilities: [olderPlugin, latestPlugin],
            issues: []
        )

        let visibleIDs = Set(AgentViewResolver().view(for: .claudeCode, graph: graph).visibleCapabilities.map(\.id))

        XCTAssertTrue(visibleIDs.contains(latestPlugin.id))
        XCTAssertFalse(visibleIDs.contains(olderPlugin.id))
    }

    func testAgentOverviewSummarizesPerAgentVisibilityDifferences() throws {
        let root = try fixtureURL("MixedProject")
        let graph = CapabilityResolver().resolve(scanResult: try scanProjectOnly(root))

        let overview = AgentOverviewBuilder().overview(graph: graph)

        XCTAssertEqual(overview.agentSummaries.count, AgentID.allCases.count)
        XCTAssertTrue(overview.agentSummaries.contains { $0.agent == .codex && $0.visibleCount > 0 && $0.hiddenCount > 0 })
        XCTAssertTrue(overview.agentSummaries.contains { $0.agent == .claudeCode && $0.visibleCount > 0 && $0.hiddenCount > 0 })
        XCTAssertTrue(overview.agentSummaries.contains { $0.agent == .cursor && $0.visibleCount > 0 && $0.hiddenCount > 0 })

        let larkDoc = try XCTUnwrap(overview.differences.first { $0.capabilityName == "lark-doc" })
        // Cursor and Trae CN load SKILL.md skills like Trae, so they see this shared skill too.
        XCTAssertEqual(Set(larkDoc.visibleAgents), Set([.codex, .trae, .traeCN, .cursor]))
        XCTAssertTrue(larkDoc.hiddenAgents.contains(.claudeCode))
        XCTAssertFalse(larkDoc.hiddenAgents.contains(.cursor))
    }

    func testCapabilityExplanationIncludesAgentVisibility() throws {
        let root = try fixtureURL("MixedProject")
        let scan = try scanProjectOnly(root)
        let graph = CapabilityResolver().resolve(scanResult: scan)
        let skill = try XCTUnwrap(graph.capabilities.first { $0.name == "lark-doc" && $0.type == .skill })

        let explanation = try CapabilityExplainer().explain(capabilityID: skill.id, graph: graph)

        XCTAssertEqual(explanation.capability.id, skill.id)
        XCTAssertTrue(explanation.visibleAgents.contains(.codex))
        XCTAssertTrue(explanation.visibleAgents.contains(.trae))
        XCTAssertTrue(explanation.visibleAgents.contains(.cursor))
        XCTAssertFalse(explanation.visibleAgents.contains(.claudeCode))
        XCTAssertTrue(explanation.hiddenAgents.contains(.claudeCode))
        XCTAssertFalse(explanation.hiddenAgents.contains(.cursor))
    }

    func testResolverExplainsGlobalAgentsAndClaudeSkillDuplicates() throws {
        let projectRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("OrbitaCoreTests-\(UUID().uuidString)")
        let homeRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("OrbitaSkillDuplicates-\(UUID().uuidString)")
        let agentsSkill = homeRoot.appendingPathComponent(".agents/skills/bytedcli/SKILL.md")
        let claudeSkill = homeRoot.appendingPathComponent(".claude/skills/bytedcli/SKILL.md")
        defer {
            try? FileManager.default.removeItem(at: projectRoot)
            try? FileManager.default.removeItem(at: homeRoot)
        }
        try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: agentsSkill.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: claudeSkill.deletingLastPathComponent(), withIntermediateDirectories: true)
        try skillText(name: "bytedcli", body: "Use bytedcli.")
            .write(to: agentsSkill, atomically: true, encoding: .utf8)
        try skillText(name: "bytedcli", body: "Use bytedcli.")
            .write(to: claudeSkill, atomically: true, encoding: .utf8)

        let scan = try CapabilityScanner().scan(
            projectRoot: projectRoot,
            options: ScanOptions(userSkillRoots: [
                homeRoot.appendingPathComponent(".agents/skills"),
                homeRoot.appendingPathComponent(".claude/skills")
            ])
        )
        let graph = CapabilityResolver().resolve(scanResult: scan)

        let agents = try XCTUnwrap(graph.capabilities.first { $0.name == "bytedcli" && $0.source.kind == "agents-skill" })
        let claude = try XCTUnwrap(graph.capabilities.first { $0.name == "bytedcli" && $0.source.kind == "claude-skill" })
        XCTAssertTrue(agents.statuses.contains(.duplicate))
        XCTAssertTrue(claude.statuses.contains(.duplicate))
        XCTAssertEqual(agents.metadata["duplicateRelationship"], "copied-mirror")
        XCTAssertEqual(claude.metadata["duplicateRelationship"], "copied-mirror")
        XCTAssertTrue(agents.metadata["duplicateDetail"]?.contains("Claude Code") == true)
        XCTAssertTrue(claude.metadata["duplicateDetail"]?.contains(".agents") == true)
        XCTAssertTrue(claude.metadata["duplicateSources"]?.contains(".agents skill") == true)
    }

    func testResolverDoesNotWarnForSymlinkedSkillMirrors() throws {
        let projectRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("OrbitaCoreTests-\(UUID().uuidString)")
        let homeRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("OrbitaSkillSymlinkMirrors-\(UUID().uuidString)")
        let agentsSkillDir = homeRoot.appendingPathComponent(".agents/skills/bytedcli")
        let agentsSkill = agentsSkillDir.appendingPathComponent("SKILL.md")
        let claudeSkillsRoot = homeRoot.appendingPathComponent(".claude/skills")
        let claudeSkillDir = claudeSkillsRoot.appendingPathComponent("bytedcli")
        defer {
            try? FileManager.default.removeItem(at: projectRoot)
            try? FileManager.default.removeItem(at: homeRoot)
        }
        try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: agentsSkillDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: claudeSkillsRoot, withIntermediateDirectories: true)
        try skillText(name: "bytedcli", body: "Use bytedcli.")
            .write(to: agentsSkill, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(at: claudeSkillDir, withDestinationURL: agentsSkillDir)

        let scan = try CapabilityScanner().scan(
            projectRoot: projectRoot,
            options: ScanOptions(userSkillRoots: [
                homeRoot.appendingPathComponent(".agents/skills"),
                homeRoot.appendingPathComponent(".claude/skills")
            ])
        )
        let graph = CapabilityResolver().resolve(scanResult: scan)

        let agents = try XCTUnwrap(graph.capabilities.first { $0.name == "bytedcli" && $0.source.kind == "agents-skill" })
        let claude = try XCTUnwrap(graph.capabilities.first { $0.name == "bytedcli" && $0.source.kind == "claude-skill" })
        XCTAssertFalse(agents.statuses.contains(.duplicate))
        XCTAssertFalse(claude.statuses.contains(.duplicate))
        XCTAssertFalse(claude.statuses.contains(.shadowed))
        XCTAssertEqual(agents.metadata["duplicateRelationship"], "linked-mirror")
        XCTAssertEqual(claude.metadata["duplicateRelationship"], "linked-mirror")
        XCTAssertTrue(claude.metadata["duplicateDetail"]?.contains("Linked mirror") == true)
    }

    func testLinkedMirrorAcrossAgentDirsStaysCleanDespiteHashSkewAndDanglingSibling() throws {
        // One physical skill in `.agents/skills`, symlinked into Claude's dir, reached through two agent
        // homes — PLUS a dangling project symlink (the common relative `../../.agents/skills/x` link in a
        // repo that has no project-level `.agents/skills`). Even though the per-source-kind content hashes
        // differ (the `agents-skill` whole-directory hash vs the `claude-skill` file hash of the same real
        // dir), the healthy records must read as ONE clean linked mirror — not duplicate / shadowed /
        // drifted — and the broken sibling must not contaminate them. Regression for the real-world
        // `iac-ai-setup` case that surfaced "duplicate + shadowed + drifted" badges for a single skill.
        let root = FileManager.default.temporaryDirectory.standardizedFileURL
            .appendingPathComponent("OrbitaLinkedMirror-\(UUID().uuidString)")
        let agentsSkillDir = root.appendingPathComponent(".agents/skills/iac-ai-setup")
        let agentsSkillFile = agentsSkillDir.appendingPathComponent("SKILL.md")
        let claudeSkillDir = root.appendingPathComponent(".claude/skills/iac-ai-setup")
        try FileManager.default.createDirectory(at: claudeSkillDir.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: agentsSkillDir, withIntermediateDirectories: true)
        try skillText(name: "iac-ai-setup", body: "Set up.").write(to: agentsSkillFile, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(at: claudeSkillDir, withDestinationURL: agentsSkillDir)
        defer { try? FileManager.default.removeItem(at: root) }

        let claudeSkillFile = claudeSkillDir.appendingPathComponent("SKILL.md")
        let agents = Capability(
            id: "skill:\(agentsSkillFile.path)", name: "iac-ai-setup", type: .skill, scope: .user,
            statuses: [.enabled],
            source: CapabilitySource(kind: "agents-skill", path: agentsSkillFile.path),
            metadata: ["contentHash": "agents-directory-hash"]
        )
        let claude = Capability(
            id: "skill:\(claudeSkillFile.path)", name: "iac-ai-setup", type: .skill, scope: .user,
            statuses: [.enabled],
            source: CapabilitySource(kind: "claude-skill", path: claudeSkillFile.path),
            metadata: ["contentHash": "claude-file-hash"]
        )
        let danglingProjectLink = Capability(
            id: "skill:\(root.path)/proj/.trae/skills/iac-ai-setup", name: "iac-ai-setup", type: .skill, scope: .project,
            statuses: [.broken],
            source: CapabilitySource(kind: "trae-symlink", path: "\(root.path)/proj/.trae/skills/iac-ai-setup")
        )

        let graph = CapabilityResolver().resolve(
            scanResult: ScanResult(projectRoot: root.path, capabilities: [agents, claude, danglingProjectLink], issues: [])
        )

        let resolvedAgents = try XCTUnwrap(graph.capabilities.first { $0.source.kind == "agents-skill" })
        let resolvedClaude = try XCTUnwrap(graph.capabilities.first { $0.source.kind == "claude-skill" })
        let resolvedBroken = try XCTUnwrap(graph.capabilities.first { $0.source.kind == "trae-symlink" })

        for cap in [resolvedAgents, resolvedClaude] {
            XCTAssertEqual(cap.metadata["duplicateRelationship"], "linked-mirror")
            XCTAssertFalse(cap.statuses.contains(.duplicate), "symlinked copies of one skill are not duplicates")
            XCTAssertFalse(cap.statuses.contains(.shadowed), "symlinked copies of one skill do not shadow each other")
            XCTAssertFalse(cap.statuses.contains(.drifted), "a per-source-kind hash difference on the same real file is not drift")
        }

        XCTAssertTrue(resolvedBroken.statuses.contains(.broken))
        XCTAssertFalse(resolvedBroken.statuses.contains(.duplicate), "a dangling symlink must not be flagged a duplicate")
        XCTAssertFalse(resolvedBroken.statuses.contains(.shadowed))
        XCTAssertFalse(resolvedBroken.statuses.contains(.drifted))
        XCTAssertNil(resolvedBroken.metadata["duplicateRelationship"], "the broken sibling stays out of the mirror group")
    }

    func testCodexSkillConfigDisablesSharedAgentsSkillOnlyForCodex() throws {
        let projectRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("OrbitaCoreTests-\(UUID().uuidString)")
        let configRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("OrbitaCodexSkillConfig-\(UUID().uuidString)")
        let skill = projectRoot.appendingPathComponent(".agents/skills/review-helper/SKILL.md")
        let config = configRoot.appendingPathComponent("config.toml")
        defer {
            try? FileManager.default.removeItem(at: projectRoot)
            try? FileManager.default.removeItem(at: configRoot)
        }
        try FileManager.default.createDirectory(at: skill.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: configRoot, withIntermediateDirectories: true)
        try skillText(name: "review-helper", body: "Review this project.")
            .write(to: skill, atomically: true, encoding: .utf8)
        try """
        [[skills.config]]
        path = "\(skill.path)"
        enabled = false
        """.write(to: config, atomically: true, encoding: .utf8)

        let scan = try CapabilityScanner().scan(
            projectRoot: projectRoot,
            options: ScanOptions(
                includeUserScope: false,
                userSkillRoots: [],
                codexConfigURL: config
            )
        )
        let graph = CapabilityResolver().resolve(scanResult: scan)
        let capability = try XCTUnwrap(graph.capabilities.first { $0.name == "review-helper" && $0.source.kind == "agents-skill" })

        XCTAssertEqual(capability.metadata["codexSkillEnabled"], "false")
        XCTAssertFalse(capability.statuses.contains(.disabled))
        XCTAssertFalse(AgentViewResolver().view(for: .codex, graph: graph).visibleCapabilities.contains { $0.id == capability.id })
        XCTAssertFalse(AgentViewResolver().view(for: .claudeCode, graph: graph).visibleCapabilities.contains { $0.id == capability.id })
    }

    func testCodexSkillConfigCommandsAreAvailableWithoutExistingConfigEntry() throws {
        let projectRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("OrbitaCoreTests-\(UUID().uuidString)")
        let homeRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("OrbitaCodexSkillConfig-\(UUID().uuidString)")
        let skillRoot = homeRoot.appendingPathComponent(".codex/skills")
        let skill = skillRoot.appendingPathComponent("review-helper/SKILL.md")
        let config = homeRoot.appendingPathComponent(".codex/config.toml")
        defer {
            try? FileManager.default.removeItem(at: projectRoot)
            try? FileManager.default.removeItem(at: homeRoot)
        }
        try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: skill.deletingLastPathComponent(), withIntermediateDirectories: true)
        try skillText(name: "review-helper", body: "Review this project.")
            .write(to: skill, atomically: true, encoding: .utf8)

        let scan = try CapabilityScanner().scan(
            projectRoot: projectRoot,
            options: ScanOptions(
                userSkillRoots: [skillRoot],
                codexConfigURL: config
            )
        )
        let graph = CapabilityResolver().resolve(scanResult: scan)
        let capability = try XCTUnwrap(graph.capabilities.first { $0.name == "review-helper" && $0.source.kind == "codex-skill" })

        XCTAssertEqual(capability.metadata["codexConfigPath"], config.path)
        XCTAssertTrue(capability.metadata["codexSkillConfigPath"]?.hasSuffix("/.codex/skills/review-helper/SKILL.md") == true)
        XCTAssertTrue(capability.metadata["codexDisableCommand"]?.contains("[[skills.config]]") == true)
        XCTAssertTrue(capability.metadata["codexEnableCommand"]?.contains(config.path) == true)
        XCTAssertNil(capability.metadata["codexSkillEnabled"])
        XCTAssertTrue(AgentViewResolver().view(for: .codex, graph: graph).visibleCapabilities.contains { $0.id == capability.id })
    }

    func testAdapterPreviewExplainsCodexGeneratedFilesAndUnsupportedCapabilities() throws {
        let root = try fixtureURL("MixedProject")
        let graph = CapabilityResolver().resolve(scanResult: try scanProjectOnly(root))

        let preview = AdapterPreviewBuilder().preview(for: .codex, graph: graph)

        XCTAssertEqual(preview.agent, .codex)
        XCTAssertTrue(preview.generatedFiles.contains { $0.path.hasSuffix("/.orbita/adapters/codex/capabilities.json") })
        XCTAssertTrue(preview.supportedCapabilities.contains { $0.name == "lark-doc" && $0.type == .skill })
        XCTAssertTrue(preview.unsupportedCapabilities.contains { $0.type == .rule })
        XCTAssertFalse(preview.appliesChanges)
    }

    func testAdapterPreviewIncludesCapabilityMappingReasons() throws {
        let root = try fixtureURL("MixedProject")
        let graph = CapabilityResolver().resolve(scanResult: try scanProjectOnly(root))
        let skill = try XCTUnwrap(graph.capabilities.first { $0.name == "lark-doc" && $0.type == .skill })

        let codexPreview = AdapterPreviewBuilder().preview(for: .codex, graph: graph)
        let cursorPreview = AdapterPreviewBuilder().preview(for: .cursor, graph: graph)

        let codexMapping = try XCTUnwrap(codexPreview.capabilityMappings.first { $0.capabilityID == skill.id })
        XCTAssertTrue(codexMapping.supported)
        XCTAssertEqual(codexMapping.targetPath, skill.source.path)
        XCTAssertTrue(codexMapping.reason.contains("Codex loads repo skills"))

        // Cursor loads SKILL.md skills (catalog + App skills-CLI union agree), so the adapter preview must
        // too — core and App now give one answer about whether Cursor sees a forked/shared skill.
        let cursorMapping = try XCTUnwrap(cursorPreview.capabilityMappings.first { $0.capabilityID == skill.id })
        XCTAssertTrue(cursorMapping.supported)
        XCTAssertEqual(cursorMapping.targetPath, skill.source.path)
        XCTAssertTrue(cursorMapping.reason.contains("Cursor loads SKILL.md-based skills"))
    }

    func testTraeAdapterPreviewRejectsCodexPluginBundledSkills() throws {
        let codexPluginSkill = Capability(
            id: "skill:codex-plugin:build-macos-apps",
            name: "build-macos-apps",
            type: .skill,
            scope: .user,
            statuses: [.enabled],
            risks: [.read, .global],
            source: CapabilitySource(
                kind: "user-skill",
                path: "/Users/dev/.codex/plugins/cache/openai-curated/build-macos-apps/1.0.0/skills/build-macos-apps/SKILL.md",
                packageName: "build-macos-apps"
            ),
            pluginID: "plugin:codex-cache:openai-curated:build-macos-apps",
            metadata: ["manager": "codex"]
        )
        let graph = CapabilityGraph(
            projectRoot: "/tmp/project",
            capabilities: [codexPluginSkill],
            issues: []
        )

        let preview = AdapterPreviewBuilder().preview(for: .trae, graph: graph)
        let mapping = try XCTUnwrap(preview.capabilityMappings.first { $0.capabilityID == codexPluginSkill.id })

        XCTAssertFalse(preview.supportedCapabilities.contains { $0.id == codexPluginSkill.id })
        XCTAssertFalse(mapping.supported)
        XCTAssertNil(mapping.targetPath)
        XCTAssertTrue(mapping.reason.contains("does not load this skill source"))
    }

    func testAdapterPreviewGeneratedFileContainsMappingJSON() throws {
        let root = try fixtureURL("MixedProject")
        let graph = CapabilityResolver().resolve(scanResult: try scanProjectOnly(root))

        let preview = AdapterPreviewBuilder().preview(for: .cursor, graph: graph)
        let content = try XCTUnwrap(preview.generatedFiles.first?.content)

        XCTAssertTrue(content.contains("\"mappings\""))
        XCTAssertTrue(content.contains("\"supported\""))
        XCTAssertFalse(content.trimmingCharacters(in: .whitespacesAndNewlines) == "{}")
    }

    func testDriftReportExplainsAgentVisibilityDifferences() throws {
        let root = try fixtureURL("MixedProject")
        let graph = CapabilityResolver().resolve(scanResult: try scanProjectOnly(root))

        let report = DriftReportBuilder().report(graph: graph)

        let larkDoc = try XCTUnwrap(report.items.first { $0.capabilityName == "lark-doc" })
        XCTAssertEqual(Set(larkDoc.visibleAgents), Set([.codex, .trae, .traeCN, .cursor]))
        XCTAssertTrue(larkDoc.hiddenAgents.contains(.claudeCode))
        XCTAssertFalse(larkDoc.hiddenAgents.contains(.cursor))
        XCTAssertTrue(larkDoc.reasons.contains { $0.contains("visible to codex") })
    }

    func testTraeCNScansOwnDirAndIsDistinctFromTrae() throws {
        let projectRoot = FileManager.default.temporaryDirectory.appendingPathComponent("OrbitaTraeCN-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: projectRoot) }
        let skillDir = projectRoot.appendingPathComponent(".traecn/skills/tcn-only")
        try FileManager.default.createDirectory(at: skillDir, withIntermediateDirectories: true)
        try skillText(name: "tcn-only", body: "Trae CN only")
            .write(to: skillDir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)

        let graph = CapabilityResolver().resolve(scanResult: try scanProjectOnly(projectRoot))
        let resolver = AgentViewResolver()
        let traeCNVisible = resolver.visibleCapabilities(for: .traeCN, graph: graph).map(\.name)
        let traeVisible = resolver.visibleCapabilities(for: .trae, graph: graph).map(\.name)

        // Trae CN loads SKILL.md skills from its OWN .traecn dir...
        XCTAssertTrue(traeCNVisible.contains("tcn-only"), "Trae CN must load skills from its own .traecn dir")
        // ...and a .traecn skill must NOT leak into Trae's .trae view (distinct agent, no substring overlap).
        XCTAssertFalse(traeVisible.contains("tcn-only"), "a .traecn skill must not appear in Trae's view")
    }

    func testDriftReportIncludesClientSpecificSourceReasons() throws {
        let root = try fixtureURL("MixedProject")
        let graph = CapabilityResolver().resolve(scanResult: try scanProjectOnly(root))

        let report = DriftReportBuilder().report(graph: graph)

        let claudeCommand = try XCTUnwrap(report.items.first { $0.capabilityName == "review" })
        XCTAssertEqual(claudeCommand.visibleAgents, [.claudeCode])
        XCTAssertTrue(claudeCommand.hiddenAgents.contains(.codex))
        XCTAssertTrue(claudeCommand.hiddenAgents.contains(.cursor))
        XCTAssertTrue(claudeCommand.reasons.contains { $0.contains("claude-command") && $0.contains("Claude Code") })
        XCTAssertTrue(claudeCommand.reasons.contains { $0.contains("Codex") && $0.contains("does not load") })
    }

    func testDriftReportExplainsDisabledManifestIntentStillDiscoverable() throws {
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("OrbitaCoreTests-\(UUID().uuidString)")
        try FileManager.default.copyItem(at: try fixtureURL("MixedProject"), to: temporaryRoot)
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }

        let initialGraph = CapabilityResolver().resolve(scanResult: try scanProjectOnly(temporaryRoot))
        let skill = try XCTUnwrap(initialGraph.capabilities.first { $0.name == "lark-doc" && $0.type == .skill })
        let manifest = temporaryRoot.appendingPathComponent(".agents/manifest.json")
        try FileManager.default.createDirectory(at: manifest.deletingLastPathComponent(), withIntermediateDirectories: true)
        try """
        {
          "schemaVersion": 1,
          "capabilities": [
            {
              "id": "\(skill.id)",
              "name": "\(skill.name)",
              "type": "\(skill.type.rawValue)",
              "status": "disabled",
              "sourcePath": "\(skill.source.path)"
            }
          ]
        }
        """.write(to: manifest, atomically: true, encoding: .utf8)

        let graph = CapabilityResolver().resolve(scanResult: try scanProjectOnly(temporaryRoot))
        let report = DriftReportBuilder().report(graph: graph)

        let item = try XCTUnwrap(report.items.first { $0.capabilityID == skill.id })
        XCTAssertTrue(item.statuses.contains(.disabled))
        XCTAssertTrue(item.reasons.contains { $0.contains("disabled in .agents") && $0.contains("source remains discoverable") })
    }

    func testProjectAgentsManifestIsVisibleWithSourcePath() throws {
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("OrbitaCoreTests-\(UUID().uuidString)")
        let manifest = temporaryRoot.appendingPathComponent(".agents/manifest.json")
        try FileManager.default.createDirectory(at: manifest.deletingLastPathComponent(), withIntermediateDirectories: true)
        try """
        {
          "schemaVersion": 1,
          "capabilities": []
        }
        """.write(to: manifest, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }

        let scan = try scanProjectOnly(temporaryRoot)
        let manifestCapability = try XCTUnwrap(scan.capabilities.first { $0.source.kind == "agents-manifest" })

        XCTAssertEqual(manifestCapability.name, ".agents manifest")
        XCTAssertEqual(manifestCapability.source.path, manifest.path)
    }

    func testInternalThisMacAgentsManifestIsParsedButNotShownAsCapability() throws {
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("OrbitaCoreTests-\(UUID().uuidString)")
        let environmentRoot = temporaryRoot.appendingPathComponent(".orbita/this-mac")
        let manifest = environmentRoot.appendingPathComponent(".agents/manifest.json")
        try FileManager.default.createDirectory(at: manifest.deletingLastPathComponent(), withIntermediateDirectories: true)
        try """
        {
          "schemaVersion": 1,
          "capabilities": [
            {
              "id": "skill:global-example",
              "name": "global-example",
              "type": "skill",
              "status": "disabled",
              "sourcePath": "/tmp/global-example/SKILL.md"
            }
          ]
        }
        """.write(to: manifest, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }

        let scan = try scanProjectOnly(environmentRoot)

        XCTAssertFalse(scan.capabilities.contains { $0.source.kind == "agents-manifest" })
        XCTAssertTrue(scan.capabilities.contains { $0.source.kind == "agents-intent" && $0.name == "global-example" })
    }

    func testEnableSkillPlanIsDryRunAndWritesAgentsIndex() throws {
        let root = try fixtureURL("MixedProject")
        let scan = try scanProjectOnly(root)
        let graph = CapabilityResolver().resolve(scanResult: scan)
        let skill = try XCTUnwrap(graph.capabilities.first { $0.name == "lark-doc" && $0.type == .skill })

        let plan = try ApplyPlanBuilder().planEnable(capabilityID: skill.id, graph: graph)

        XCTAssertEqual(plan.action, .enable)
        XCTAssertEqual(plan.capabilityID, skill.id)
        XCTAssertFalse(plan.appliesChanges)
        XCTAssertTrue(plan.requiresConfirmation)
        XCTAssertTrue(plan.operations.contains { $0.kind == .createDirectory && $0.path.hasSuffix("/.agents/skills") })
        XCTAssertTrue(plan.operations.contains { $0.kind == .createSymlink && $0.path.hasSuffix("/.agents/skills/lark-doc") && $0.target == skill.source.path.replacingOccurrences(of: "/SKILL.md", with: "") })
        XCTAssertTrue(plan.operations.contains { $0.kind == .writeFile && $0.path.hasSuffix("/.agents/manifest.json") })
        XCTAssertTrue(plan.operations.contains { $0.kind == .writeFile && $0.path.hasSuffix("/.agents/lock.json") })
        XCTAssertFalse(plan.operations.contains { $0.kind == .writeFile && $0.path.contains("/.agents/adapters/") })
        XCTAssertFalse(plan.operations.contains { $0.kind == .writeFile && $0.path.contains("/.orbita/adapters/") })
        XCTAssertTrue(plan.operations.contains { $0.kind == .appendLog && $0.path.hasSuffix("/.agents/logs/apply.log") })
    }

    func testDeleteSkillInstallTargetRemovesOnlySelectedAgentCopy() throws {
        let projectRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("OrbitaProject-\(UUID().uuidString)")
        let canonical = FileManager.default.temporaryDirectory
            .appendingPathComponent("OrbitaAgents-\(UUID().uuidString)")
            .appendingPathComponent(".agents/skills/bytedcli")
        let traeCopy = FileManager.default.temporaryDirectory
            .appendingPathComponent("OrbitaTrae-\(UUID().uuidString)")
            .appendingPathComponent(".trae/skills/bytedcli")
        defer {
            try? FileManager.default.removeItem(at: projectRoot)
            try? FileManager.default.removeItem(at: canonical.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent())
            try? FileManager.default.removeItem(at: traeCopy.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent())
        }

        let skill = Capability(
            id: "skill:\(canonical.appendingPathComponent("SKILL.md").path)",
            name: "bytedcli",
            type: .skill,
            scope: .user,
            source: CapabilitySource(kind: "agents-skill", path: canonical.appendingPathComponent("SKILL.md").path),
            metadata: [
                "skillsInstallTargets": [
                    "codex=canonical:\(canonical.path)",
                    "trae=copy:\(traeCopy.path)"
                ].joined(separator: "\n")
            ]
        )
        let graph = CapabilityGraph(projectRoot: projectRoot.path, capabilities: [skill], issues: [])

        let plan = try ApplyPlanBuilder().planDeleteSkillInstallTarget(
            capabilityID: skill.id,
            agentID: "trae",
            graph: graph
        )

        XCTAssertEqual(plan.action, .delete)
        XCTAssertEqual(plan.capabilityID, skill.id)
        XCTAssertTrue(plan.requiresConfirmation)
        XCTAssertTrue(plan.operations.contains {
            $0.kind == .removePath
                && $0.path == traeCopy.path
                && $0.description.contains("trae copy")
        })
        XCTAssertFalse(plan.operations.contains { $0.path == canonical.path })
    }

    func testDeleteCanonicalSkillInstallTargetAlsoRemovesLinkedSymlinks() throws {
        let projectRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("OrbitaProject-\(UUID().uuidString)")
        let canonical = FileManager.default.temporaryDirectory
            .appendingPathComponent("OrbitaCodex-\(UUID().uuidString)")
            .appendingPathComponent(".codex/skills/bytedcli")
        let claudeSymlink = FileManager.default.temporaryDirectory
            .appendingPathComponent("OrbitaClaude-\(UUID().uuidString)")
            .appendingPathComponent(".claude/skills/bytedcli")
        let traeCopy = FileManager.default.temporaryDirectory
            .appendingPathComponent("OrbitaTrae-\(UUID().uuidString)")
            .appendingPathComponent(".trae/skills/bytedcli")
        let cursorOtherSymlink = FileManager.default.temporaryDirectory
            .appendingPathComponent("OrbitaCursor-\(UUID().uuidString)")
            .appendingPathComponent(".cursor/skills/bytedcli")
        defer {
            try? FileManager.default.removeItem(at: projectRoot)
            try? FileManager.default.removeItem(at: canonical.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent())
            try? FileManager.default.removeItem(at: claudeSymlink.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent())
            try? FileManager.default.removeItem(at: traeCopy.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent())
            try? FileManager.default.removeItem(at: cursorOtherSymlink.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent())
        }

        let skill = Capability(
            id: "skill:\(canonical.appendingPathComponent("SKILL.md").path)",
            name: "bytedcli",
            type: .skill,
            scope: .user,
            source: CapabilitySource(kind: "agents-skill", path: canonical.appendingPathComponent("SKILL.md").path),
            metadata: [
                "skillsInstallTargets": [
                    "codex=canonical:\(canonical.path)",
                    "claude-code=symlink:\(claudeSymlink.path)",
                    "trae=copy:\(traeCopy.path)",
                    "cursor=symlink-other:\(cursorOtherSymlink.path)"
                ].joined(separator: "\n")
            ]
        )
        let graph = CapabilityGraph(projectRoot: projectRoot.path, capabilities: [skill], issues: [])

        let plan = try ApplyPlanBuilder().planDeleteSkillInstallTarget(
            capabilityID: skill.id,
            agentID: "codex",
            graph: graph
        )

        XCTAssertEqual(plan.action, .delete)
        XCTAssertTrue(plan.operations.contains {
            $0.kind == .removePath
                && $0.path == canonical.path
                && $0.description.contains("codex canonical")
        })
        XCTAssertTrue(plan.operations.contains {
            $0.kind == .removePath
                && $0.path == claudeSymlink.path
                && $0.description.contains("claude-code symlink")
        })
        XCTAssertFalse(plan.operations.contains { $0.path == traeCopy.path })
        XCTAssertFalse(plan.operations.contains { $0.path == cursorOtherSymlink.path })
    }

    func testSyncSkillInstallTargetCreatesLightweightAgentSymlinkOnly() throws {
        let projectRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("OrbitaProject-\(UUID().uuidString)")
        let skillName = "orbita-sync-\(UUID().uuidString)"
        let source = FileManager.default.temporaryDirectory
            .appendingPathComponent("OrbitaClaude-\(UUID().uuidString)")
            .appendingPathComponent(".claude/skills/\(skillName)")
        defer {
            try? FileManager.default.removeItem(at: projectRoot)
            try? FileManager.default.removeItem(at: source.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent())
        }
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try """
        ---
        name: \(skillName)
        description: Test skill
        ---

        Body
        """.write(to: source.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)

        let skill = Capability(
            id: "skill:\(source.appendingPathComponent("SKILL.md").path)",
            name: skillName,
            type: .skill,
            scope: .user,
            source: CapabilitySource(kind: "claude-skill", path: source.appendingPathComponent("SKILL.md").path),
            metadata: [:]
        )
        let graph = CapabilityGraph(projectRoot: projectRoot.path, capabilities: [skill], issues: [])

        let plan = try ApplyPlanBuilder().planSyncSkillInstallTarget(
            capabilityID: skill.id,
            agentID: "codex",
            graph: graph
        )

        let expectedTarget = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/skills/\(skillName)")
            .path
        XCTAssertEqual(plan.action, .enable)
        XCTAssertFalse(plan.requiresConfirmation)
        XCTAssertFalse(plan.operations.contains { $0.kind == .writeFile })
        XCTAssertTrue(plan.operations.contains {
            $0.kind == .createSymlink
                && $0.path == expectedTarget
                && $0.target == source.path
        })
    }

    func testSyncAgentsSkillToCodexUsesCodexGlobalSkillsRoot() throws {
        let projectRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("OrbitaProject-\(UUID().uuidString)")
        let skillName = "orbita-bytedcli-\(UUID().uuidString)"
        let source = FileManager.default.temporaryDirectory
            .appendingPathComponent("OrbitaAgents-\(UUID().uuidString)")
            .appendingPathComponent(".agents/skills/\(skillName)")
        defer {
            try? FileManager.default.removeItem(at: projectRoot)
            try? FileManager.default.removeItem(at: source.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent())
        }
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try skillText(name: skillName, body: "Use bytedcli.")
            .write(to: source.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)

        let skill = Capability(
            id: "skill:\(source.appendingPathComponent("SKILL.md").path)",
            name: skillName,
            type: .skill,
            scope: .user,
            source: CapabilitySource(kind: "agents-skill", path: source.appendingPathComponent("SKILL.md").path),
            metadata: [
                "skillsCanonicalPath": source.path
            ]
        )
        let graph = CapabilityGraph(projectRoot: projectRoot.path, capabilities: [skill], issues: [])

        let plan = try ApplyPlanBuilder().planSyncSkillInstallTarget(
            capabilityID: skill.id,
            agentID: "codex",
            graph: graph
        )

        let expectedRoot = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/skills")
            .path
        let expectedTarget = URL(fileURLWithPath: expectedRoot)
            .appendingPathComponent(skillName)
            .path
        XCTAssertTrue(plan.operations.contains { $0.kind == .createDirectory && $0.path == expectedRoot })
        XCTAssertTrue(plan.operations.contains {
            $0.kind == .createSymlink
                && $0.path == expectedTarget
                && $0.target == source.path
        })
        XCTAssertFalse(plan.operations.contains {
            $0.kind == .createSymlink
                && $0.path == source.path
                && $0.target == source.path
        })
    }

    func testSyncProjectSkillCanCopyToProjectOrGlobalTarget() throws {
        let projectRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("OrbitaProject-\(UUID().uuidString)")
        let skillName = "project-skill-\(UUID().uuidString)"
        let source = projectRoot.appendingPathComponent(".codex/skills/\(skillName)")
        defer { try? FileManager.default.removeItem(at: projectRoot) }
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try skillText(name: skillName, body: "Project skill")
            .write(to: source.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)

        let skill = Capability(
            id: "skill:\(source.appendingPathComponent("SKILL.md").path)",
            name: skillName,
            type: .skill,
            scope: .project,
            source: CapabilitySource(kind: "codex-skill", path: source.appendingPathComponent("SKILL.md").path)
        )
        let graph = CapabilityGraph(projectRoot: projectRoot.path, capabilities: [skill], issues: [])

        let projectPlan = try ApplyPlanBuilder().planSyncInstallTarget(
            capabilityID: skill.id,
            agentID: "claude-code",
            graph: graph,
            mode: .copy,
            destinationScope: .project
        )
        let projectTarget = projectRoot.appendingPathComponent(".claude/skills/\(skillName)").path
        XCTAssertTrue(projectPlan.operations.contains {
            $0.kind == .copyPath && $0.path == source.path && $0.target == projectTarget
        })

        let codexProjectPlan = try ApplyPlanBuilder().planSyncInstallTarget(
            capabilityID: skill.id,
            agentID: "codex",
            graph: graph,
            mode: .copy,
            destinationScope: .project
        )
        let codexProjectTarget = projectRoot.appendingPathComponent(".agents/skills/\(skillName)").path
        XCTAssertTrue(codexProjectPlan.operations.contains {
            $0.kind == .copyPath && $0.path == source.path && $0.target == codexProjectTarget
        })

        let globalPlan = try ApplyPlanBuilder().planSyncInstallTarget(
            capabilityID: skill.id,
            agentID: "claude-code",
            graph: graph,
            mode: .copy,
            destinationScope: .user
        )
        let globalTarget = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/skills/\(skillName)")
            .path
        XCTAssertTrue(globalPlan.operations.contains {
            $0.kind == .copyPath && $0.path == source.path && $0.target == globalTarget
        })
    }

    func testSyncUserCapabilityTargetsProjectOnlyViaDeepCopy() throws {
        let projectRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("OrbitaProject-\(UUID().uuidString)")
        let source = FileManager.default.temporaryDirectory
            .appendingPathComponent("OrbitaUserSkill-\(UUID().uuidString)")
            .appendingPathComponent(".codex/skills/global-only")
        defer {
            try? FileManager.default.removeItem(at: projectRoot)
            try? FileManager.default.removeItem(at: source.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent())
        }
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try skillText(name: "global-only", body: "Global skill")
            .write(to: source.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)

        let skill = Capability(
            id: "skill:\(source.appendingPathComponent("SKILL.md").path)",
            name: "global-only",
            type: .skill,
            scope: .user,
            source: CapabilitySource(kind: "codex-skill", path: source.appendingPathComponent("SKILL.md").path)
        )
        let graph = CapabilityGraph(projectRoot: projectRoot.path, capabilities: [skill], issues: [])

        // A user-scope ("My Mac") skill may be forked INTO a project, but only as a deep COPY (it vendors
        // an independent copy). A symlink is refused — it would commit an absolute link into ~/.agents.
        let copyPlan = try ApplyPlanBuilder().planSyncInstallTarget(
            capabilityID: skill.id, agentID: "claude-code", graph: graph, mode: .copy, destinationScope: .project
        )
        let projectTarget = projectRoot.appendingPathComponent(".claude/skills/global-only").path
        XCTAssertTrue(copyPlan.operations.contains {
            $0.kind == .copyPath && $0.path == source.path && $0.target == projectTarget
        }, "a user-scope skill deep-copied into a project lands in the project's agent dir")

        XCTAssertThrowsError(try ApplyPlanBuilder().planSyncInstallTarget(
            capabilityID: skill.id, agentID: "claude-code", graph: graph, mode: .symlink, destinationScope: .project
        ), "a user-scope skill still cannot SYMLINK into a project")
    }

    func testSyncCopyCanReplaceExistingSameSourceSymlink() throws {
        let projectRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("OrbitaProject-\(UUID().uuidString)")
        let skillName = "replace-link-\(UUID().uuidString)"
        let source = projectRoot.appendingPathComponent(".codex/skills/\(skillName)")
        let destination = projectRoot.appendingPathComponent(".claude/skills/\(skillName)")
        defer { try? FileManager.default.removeItem(at: projectRoot) }
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try skillText(name: skillName, body: "Project skill")
            .write(to: source.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(at: destination, withDestinationURL: source)

        let skill = Capability(
            id: "skill:\(source.appendingPathComponent("SKILL.md").path)",
            name: skillName,
            type: .skill,
            scope: .project,
            source: CapabilitySource(kind: "codex-skill", path: source.appendingPathComponent("SKILL.md").path)
        )
        let graph = CapabilityGraph(projectRoot: projectRoot.path, capabilities: [skill], issues: [])

        let plan = try ApplyPlanBuilder().planSyncInstallTarget(
            capabilityID: skill.id,
            agentID: "claude-code",
            graph: graph,
            mode: .copy,
            destinationScope: .project
        )

        XCTAssertTrue(plan.operations.contains {
            $0.kind == .copyPath && $0.path == source.path && $0.target == destination.path
        })
    }

    func testSyncCommandsAndAgentsUseKnownCompatibleRoots() throws {
        let projectRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("OrbitaProject-\(UUID().uuidString)")
        let command = projectRoot.appendingPathComponent(".codex/commands/review.md")
        let agent = projectRoot.appendingPathComponent(".claude/agents/reviewer.md")
        defer { try? FileManager.default.removeItem(at: projectRoot) }
        try FileManager.default.createDirectory(at: command.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: agent.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "# Review\n".write(to: command, atomically: true, encoding: .utf8)
        try agentText(name: "reviewer", description: "Reviews code", tools: "Read")
            .write(to: agent, atomically: true, encoding: .utf8)

        let commandCapability = Capability(
            id: "command:\(command.path)",
            name: "review",
            type: .command,
            scope: .project,
            source: CapabilitySource(kind: "codex-command", path: command.path)
        )
        let agentCapability = Capability(
            id: "agent:\(agent.path)",
            name: "reviewer",
            type: .agent,
            scope: .project,
            source: CapabilitySource(kind: "claude-agent", path: agent.path)
        )
        let graph = CapabilityGraph(projectRoot: projectRoot.path, capabilities: [commandCapability, agentCapability], issues: [])

        let commandPlan = try ApplyPlanBuilder().planSyncInstallTarget(
            capabilityID: commandCapability.id,
            agentID: "claude-code",
            graph: graph,
            mode: .symlink,
            destinationScope: .project
        )
        // Project-scope symlink forks use a target relative to the link's own directory so the committed
        // link survives a repo move/clone (.claude/commands/review.md -> ../../.codex/commands/review.md).
        XCTAssertTrue(commandPlan.operations.contains {
            $0.kind == .createSymlink
                && $0.path == projectRoot.appendingPathComponent(".claude/commands/review.md").path
                && $0.target == "../../.codex/commands/review.md"
        })

        let agentPlan = try ApplyPlanBuilder().planSyncInstallTarget(
            capabilityID: agentCapability.id,
            agentID: "codex",
            graph: graph,
            mode: .copy,
            destinationScope: .user
        )
        XCTAssertTrue(agentPlan.operations.contains {
            $0.kind == .copyPath
                && $0.path == agent.path
                && $0.target == FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/agents/reviewer.md").path
        })
    }

    func testMergePlanIndexesDiscoveredProjectCapabilitiesWithoutDeletingSources() throws {
        let root = try fixtureURL("MixedProject")
        let graph = CapabilityResolver().resolve(scanResult: try scanProjectOnly(root))

        let plan = try ApplyPlanBuilder().planMerge(graph: graph)

        XCTAssertEqual(plan.action, .merge)
        XCTAssertEqual(plan.capabilityID, "workspace")
        XCTAssertFalse(plan.appliesChanges)
        XCTAssertTrue(plan.requiresConfirmation)
        XCTAssertTrue(plan.operations.contains { $0.kind == .writeFile && $0.path.hasSuffix("/.agents/manifest.json") && ($0.content ?? "").contains("lark-doc") })
        XCTAssertTrue(plan.operations.contains { $0.kind == .writeFile && $0.path.hasSuffix("/.agents/lock.json") && ($0.content ?? "").contains("contentHash") })
        XCTAssertTrue(plan.operations.contains { $0.kind == .createSymlink && $0.path.hasSuffix("/.agents/skills/lark-doc") })
        XCTAssertFalse(plan.operations.contains { $0.kind == .writeFile && $0.path.contains("/.agents/adapters/") })
        XCTAssertFalse(plan.operations.contains { $0.kind == .writeFile && $0.path.contains("/.orbita/adapters/") })
        XCTAssertFalse(plan.operations.contains { $0.kind == .removePath })
    }

    func testMergePlanExecutorWritesAgentsWorkspaceAndKeepsOriginalSources() throws {
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("OrbitaCoreTests-\(UUID().uuidString)")
        try FileManager.default.copyItem(at: try fixtureURL("MixedProject"), to: temporaryRoot)
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }

        let graph = CapabilityResolver().resolve(scanResult: try scanProjectOnly(temporaryRoot))
        let plan = try ApplyPlanBuilder().planMerge(graph: graph)

        let result = try ApplyPlanExecutor().apply(plan)

        XCTAssertEqual(result.completedOperations.count, plan.operations.count)
        XCTAssertTrue(FileManager.default.fileExists(atPath: temporaryRoot.appendingPathComponent(".agents/manifest.json").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: temporaryRoot.appendingPathComponent(".agents/lock.json").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: temporaryRoot.appendingPathComponent(".agents/adapters/codex/capabilities.json").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: temporaryRoot.appendingPathComponent(".orbita/adapters/codex/capabilities.json").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: temporaryRoot.appendingPathComponent(".codex/commands/bootstrap.md").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: temporaryRoot.appendingPathComponent(".claude/commands/review.md").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: temporaryRoot.appendingPathComponent(".cursor/rules/project.md").path))
    }

    func testApplyPlanExecutorWritesOnlyAgentsIndex() throws {
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("OrbitaCoreTests-\(UUID().uuidString)")
        try FileManager.default.copyItem(at: try fixtureURL("MixedProject"), to: temporaryRoot)
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }

        let scan = try scanProjectOnly(temporaryRoot)
        let graph = CapabilityResolver().resolve(scanResult: scan)
        let skill = try XCTUnwrap(graph.capabilities.first { $0.name == "lark-doc" && $0.type == .skill })
        let plan = try ApplyPlanBuilder().planEnable(capabilityID: skill.id, graph: graph)

        let result = try ApplyPlanExecutor().apply(plan)

        XCTAssertEqual(result.completedOperations.count, plan.operations.count)
        XCTAssertTrue(FileManager.default.fileExists(atPath: temporaryRoot.appendingPathComponent(".agents/manifest.json").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: temporaryRoot.appendingPathComponent(".agents/lock.json").path))

        let symlink = temporaryRoot.appendingPathComponent(".agents/skills/lark-doc")
        let values = try symlink.resourceValues(forKeys: [.isSymbolicLinkKey])
        XCTAssertEqual(values.isSymbolicLink, true)
        let actualTarget = URL(fileURLWithPath: try FileManager.default.destinationOfSymbolicLink(atPath: symlink.path)).resolvingSymlinksInPath().path
        let expectedTarget = temporaryRoot.appendingPathComponent("node_modules/@orbita/lark-skills/skills/lark-doc").resolvingSymlinksInPath().path
        XCTAssertEqual(actualTarget, expectedTarget)

        let manifestText = try String(contentsOf: temporaryRoot.appendingPathComponent(".agents/manifest.json"), encoding: .utf8)
        let lockText = try String(contentsOf: temporaryRoot.appendingPathComponent(".agents/lock.json"), encoding: .utf8)
        let logText = try String(contentsOf: temporaryRoot.appendingPathComponent(".agents/logs/apply.log"), encoding: .utf8)
        XCTAssertTrue(manifestText.contains(skill.id))
        XCTAssertTrue(lockText.contains(try XCTUnwrap(skill.metadata["contentHash"])))
        XCTAssertTrue(logText.contains("enable"))
        XCTAssertTrue(logText.contains(skill.id))
    }

    func testDisableSkillPlanRemovesAgentsSymlinkWithoutDeletingSource() throws {
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("OrbitaCoreTests-\(UUID().uuidString)")
        try FileManager.default.copyItem(at: try fixtureURL("MixedProject"), to: temporaryRoot)
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }

        let initialGraph = CapabilityResolver().resolve(scanResult: try scanProjectOnly(temporaryRoot))
        let skill = try XCTUnwrap(initialGraph.capabilities.first { $0.name == "lark-doc" && $0.type == .skill })
        _ = try ApplyPlanExecutor().apply(try ApplyPlanBuilder().planEnable(capabilityID: skill.id, graph: initialGraph))

        let enabledGraph = CapabilityResolver().resolve(scanResult: try scanProjectOnly(temporaryRoot))
        let plan = try ApplyPlanBuilder().planDisable(capabilityID: skill.id, graph: enabledGraph)
        let result = try ApplyPlanExecutor().apply(plan)

        XCTAssertEqual(plan.action, .disable)
        XCTAssertEqual(result.completedOperations.count, plan.operations.count)
        XCTAssertFalse(FileManager.default.fileExists(atPath: temporaryRoot.appendingPathComponent(".agents/skills/lark-doc").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: skill.source.path))
        XCTAssertFalse(plan.operations.contains { $0.kind == .cachePath })

        let manifestText = try String(contentsOf: temporaryRoot.appendingPathComponent(".agents/manifest.json"), encoding: .utf8)
        let logText = try String(contentsOf: temporaryRoot.appendingPathComponent(".agents/logs/apply.log"), encoding: .utf8)
        XCTAssertTrue(manifestText.contains(CapabilityStatus.disabled.rawValue))
        XCTAssertTrue(logText.contains("disable"))
    }

    func testDisableNonSymlinkAgentSourceCachesAndEnableRestoresIt() throws {
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("OrbitaCoreTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }

        let skillDirectory = temporaryRoot.appendingPathComponent(".codex/skills/browser")
        let skillFile = skillDirectory.appendingPathComponent("SKILL.md")
        try FileManager.default.createDirectory(at: skillDirectory, withIntermediateDirectories: true)
        try """
        ---
        name: browser
        description: browser skill
        ---
        """.write(to: skillFile, atomically: true, encoding: .utf8)

        let capability = Capability(
            id: "skill:\(skillFile.path)",
            name: "browser",
            type: .skill,
            scope: .user,
            source: CapabilitySource(kind: "codex-skill", path: skillFile.path),
            metadata: ["contentHash": "browser-hash"]
        )
        let graph = CapabilityGraph(projectRoot: temporaryRoot.path, capabilities: [capability], issues: [])
        let builder = ApplyPlanBuilder()
        let executor = ApplyPlanExecutor()

        let disable = try builder.planDisable(capabilityID: capability.id, graph: graph)
        let cacheOperation = try XCTUnwrap(disable.operations.first { $0.kind == .cachePath })
        let target = try XCTUnwrap(cacheOperation.target)
        // Data-grade store, not a throwaway "cache".
        XCTAssertTrue(target.contains("/.orbita/disabled/"), "expected the data-grade disabled store, got \(target)")
        XCTAssertFalse(target.contains("/.orbita/cache/"), "must not use the old throwaway cache location")
        // A co-located restore sidecar is written so the entry survives loss of .agents/manifest.json.
        let sidecarOperation = try XCTUnwrap(disable.operations.first {
            $0.kind == .writeFile && $0.path.hasSuffix(".orbita-restore.json")
        })
        _ = try executor.apply(disable)

        XCTAssertFalse(FileManager.default.fileExists(atPath: skillDirectory.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: target))
        XCTAssertTrue(FileManager.default.fileExists(atPath: sidecarOperation.path))

        let enable = try builder.planEnable(capabilityID: capability.id, graph: graph)
        let restoreOperation = try XCTUnwrap(enable.operations.first { $0.kind == .restorePath })
        _ = try executor.apply(enable)

        XCTAssertEqual(restoreOperation.path, cacheOperation.target)
        XCTAssertTrue(FileManager.default.fileExists(atPath: skillFile.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: restoreOperation.path))
    }

    func testDisableUserScopeSourceQuarantinesToUserStoreNotOpenProject() throws {
        // Fix A: disabling a user-global skill must quarantine under the user's own ~/.orbita/disabled,
        // never into whatever project happens to be open (which would strand the only copy in one repo).
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("OrbitaCoreTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }
        let projectRoot = temporaryRoot.appendingPathComponent("project")
        let fakeHome = temporaryRoot.appendingPathComponent("home")
        try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: fakeHome, withIntermediateDirectories: true)

        let skillDirectory = fakeHome.appendingPathComponent(".trae/skills/global-skill")
        let skillFile = skillDirectory.appendingPathComponent("SKILL.md")
        try FileManager.default.createDirectory(at: skillDirectory, withIntermediateDirectories: true)
        try skillText(name: "global-skill", body: "body").write(to: skillFile, atomically: true, encoding: .utf8)

        let capability = Capability(
            id: "skill:\(skillFile.path)",
            name: "global-skill",
            type: .skill,
            scope: .user,
            source: CapabilitySource(kind: "trae-skill", path: skillFile.path)
        )
        let graph = CapabilityGraph(projectRoot: projectRoot.path, capabilities: [capability], issues: [])
        let builder = ApplyPlanBuilder(homeDirectory: fakeHome)
        let executor = ApplyPlanExecutor(homeDirectory: fakeHome)

        let disable = try builder.planDisable(capabilityID: capability.id, graph: graph)
        let target = try XCTUnwrap(disable.operations.first { $0.kind == .cachePath }?.target)
        XCTAssertTrue(target.hasPrefix(fakeHome.appendingPathComponent(".orbita/disabled").path + "/"),
                      "user-scope source must quarantine under ~/.orbita/disabled, got \(target)")
        XCTAssertFalse(target.hasPrefix(projectRoot.appendingPathComponent(".orbita").path + "/"),
                       "user-scope source must NOT be demoted into the open project's .orbita")

        _ = try executor.apply(disable)
        XCTAssertFalse(FileManager.default.fileExists(atPath: skillDirectory.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: target))
        XCTAssertFalse(FileManager.default.fileExists(atPath: projectRoot.appendingPathComponent(".orbita").path))
    }

    func testDisableNativeDisableCapabilityDoesNotMoveSource() throws {
        // Fix C: a capability the host can disable in place (here: Codex `[[skills.config]]`) must never be
        // physically moved, even via the CLI's agent-agnostic plan path.
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("OrbitaCoreTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }

        let skillDirectory = temporaryRoot.appendingPathComponent(".codex/skills/native")
        let skillFile = skillDirectory.appendingPathComponent("SKILL.md")
        try FileManager.default.createDirectory(at: skillDirectory, withIntermediateDirectories: true)
        try skillText(name: "native", body: "body").write(to: skillFile, atomically: true, encoding: .utf8)

        let capability = Capability(
            id: "skill:\(skillFile.path)",
            name: "native",
            type: .skill,
            scope: .user,
            source: CapabilitySource(kind: "codex-skill", path: skillFile.path),
            metadata: ["codexSkillConfigPath": skillFile.path,
                       "codexDisableCommand": "Set [[skills.config]] ... enabled = false"]
        )
        let graph = CapabilityGraph(projectRoot: temporaryRoot.path, capabilities: [capability], issues: [])
        let builder = ApplyPlanBuilder()

        let disable = try builder.planDisable(capabilityID: capability.id, graph: graph)
        XCTAssertNil(disable.operations.first { $0.kind == .cachePath },
                     "a natively-disablable capability must not be moved into the disabled store")
        _ = try ApplyPlanExecutor().apply(disable)
        XCTAssertTrue(FileManager.default.fileExists(atPath: skillFile.path),
                      "native disable must leave the source file in place")
    }

    func testScanReadsBackDisabledStoreWithoutManifest() throws {
        // Fix D: a quarantined entry surfaces as a disabled tile from the store alone, with no .agents intent.
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("OrbitaCoreTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }

        let originalSource = temporaryRoot.appendingPathComponent(".trae/skills/parked").path
        let entryDir = temporaryRoot.appendingPathComponent(".orbita/disabled/skill/testkey")
        let content = entryDir.appendingPathComponent("parked")
        try FileManager.default.createDirectory(at: content, withIntermediateDirectories: true)
        try skillText(name: "parked", body: "b").write(
            to: content.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        try OrbitaDisabledStore.sidecarJSON(
            capabilityID: "skill:quarantined-demo",
            name: "parked",
            type: "skill",
            originalSourcePath: originalSource,
            scope: "project"
        ).write(to: entryDir.appendingPathComponent(".orbita-restore.json"), atomically: true, encoding: .utf8)

        let graph = CapabilityResolver().resolve(scanResult: try scanProjectOnly(temporaryRoot))
        let tile = try XCTUnwrap(graph.capabilities.first { $0.id == "skill:quarantined-demo" })
        XCTAssertEqual(tile.name, "parked")
        XCTAssertTrue(tile.statuses.contains(.disabled))
        XCTAssertFalse(tile.statuses.contains(.drifted), "a quarantined tile is cleanly disabled, not drifted")
        XCTAssertEqual(tile.source.kind, "orbita-quarantine")
    }

    func testRestoreRejectsProjectStoreEntryWhoseSidecarTargetsUserHomeAgentDir() throws {
        // HIGH-1-restore-boundary regression: a hostile repo plants a quarantine entry under the PROJECT
        // store (<repo>/.orbita/disabled) whose attacker-controlled sidecar originalSourcePath points at the
        // user's HOME agent dir (~/.claude/skills/evil/SKILL.md). Enabling that tile must be REJECTED by the
        // executor's scope-binding (project-store entries may only restore back into the project tree), so
        // the planted content can never be written into / overwrite a file under the user home.
        let fm = FileManager.default
        let temporaryRoot = fm.temporaryDirectory
            .appendingPathComponent("OrbitaCoreTests-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: temporaryRoot) }
        let projectRoot = temporaryRoot.appendingPathComponent("project")
        let fakeHome = temporaryRoot.appendingPathComponent("home")
        try fm.createDirectory(at: projectRoot, withIntermediateDirectories: true)
        try fm.createDirectory(at: fakeHome, withIntermediateDirectories: true)

        // Attacker-chosen restore TARGET inside the user's home agent storage.
        let evilTarget = fakeHome.appendingPathComponent(".claude/skills/evil").path

        // Plant a project-store quarantine entry: sidecar + co-located content.
        let entryDir = projectRoot.appendingPathComponent(".orbita/disabled/skill/attackerkey")
        let content = entryDir.appendingPathComponent("SKILL.md")
        try fm.createDirectory(at: content.deletingLastPathComponent(), withIntermediateDirectories: true)
        try skillText(name: "evil", body: "pwned").write(to: content, atomically: true, encoding: .utf8)
        try OrbitaDisabledStore.sidecarJSON(
            capabilityID: "skill:evil-demo",
            name: "evil",
            type: "skill",
            originalSourcePath: evilTarget + "/SKILL.md",
            scope: "user"
        ).write(to: entryDir.appendingPathComponent(".orbita-restore.json"), atomically: true, encoding: .utf8)

        // The scanner reads the planted entry back as a disabled tile (project store is always scanned).
        let graph = CapabilityResolver().resolve(scanResult: try CapabilityScanner().scan(
            projectRoot: projectRoot, options: ScanOptions(includeUserScope: false)))
        let tile = try XCTUnwrap(graph.capabilities.first { $0.id == "skill:evil-demo" })
        XCTAssertTrue(tile.statuses.contains(.disabled))

        // The enable plan's restore op aims at the attacker target (proving the op is generated)...
        let builder = ApplyPlanBuilder(homeDirectory: fakeHome)
        let plan = try builder.planEnable(capabilityID: tile.id, graph: graph)
        let restoreOp = try XCTUnwrap(plan.operations.first { $0.kind == .restorePath })
        XCTAssertEqual(restoreOp.target, evilTarget + "/SKILL.md",
                       "the fallback restore op should target the attacker-controlled sidecar path verbatim")

        // ...but the executor must REJECT it: a project-store source may only restore into the project's own
        // agent dirs (.agents/.codex/.claude/…), so a user-home target is out of scope.
        let executor = ApplyPlanExecutor(homeDirectory: fakeHome)
        XCTAssertThrowsError(try executor.apply(plan)) { error in
            let message = (error as? ApplyExecutionError)?.message ?? "\(error)"
            XCTAssertTrue(message.contains("outside project agent storage"),
                          "expected a project-agent-storage scope rejection, got: \(message)")
        }

        // No file may have been created under the user home.
        XCTAssertFalse(fm.fileExists(atPath: evilTarget + "/SKILL.md"),
                       "the planted content must NOT have been written into the user's home agent dir")
        XCTAssertFalse(fm.fileExists(atPath: fakeHome.appendingPathComponent(".claude").path),
                       "no ~/.claude tree should have been created by the rejected restore")
    }

    func testUserScopeQuarantineEnableStillRestoresIntoUserHome() throws {
        // Positive control for HIGH-1-restore-boundary: the legitimate USER-scope disable->enable round-trip
        // (source under ~/.trae) must still restore correctly after the scope-binding fix.
        let fm = FileManager.default
        let temporaryRoot = fm.temporaryDirectory
            .appendingPathComponent("OrbitaCoreTests-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: temporaryRoot) }
        let projectRoot = temporaryRoot.appendingPathComponent("project")
        let fakeHome = temporaryRoot.appendingPathComponent("home")
        try fm.createDirectory(at: projectRoot, withIntermediateDirectories: true)
        try fm.createDirectory(at: fakeHome, withIntermediateDirectories: true)

        let skillDirectory = fakeHome.appendingPathComponent(".trae/skills/bar")
        let skillFile = skillDirectory.appendingPathComponent("SKILL.md")
        try fm.createDirectory(at: skillDirectory, withIntermediateDirectories: true)
        try skillText(name: "bar", body: "body").write(to: skillFile, atomically: true, encoding: .utf8)

        let capability = Capability(
            id: "skill:\(skillFile.path)",
            name: "bar",
            type: .skill,
            scope: .user,
            source: CapabilitySource(kind: "trae-skill", path: skillFile.path)
        )
        let graph = CapabilityGraph(projectRoot: projectRoot.path, capabilities: [capability], issues: [])
        let builder = ApplyPlanBuilder(homeDirectory: fakeHome)
        let executor = ApplyPlanExecutor(homeDirectory: fakeHome)

        // Disable -> quarantine under ~/.orbita/disabled (the user store).
        let disable = try builder.planDisable(capabilityID: capability.id, graph: graph)
        let quarantineTarget = try XCTUnwrap(disable.operations.first { $0.kind == .cachePath }?.target)
        XCTAssertTrue(quarantineTarget.hasPrefix(fakeHome.appendingPathComponent(".orbita/disabled").path + "/"))
        _ = try executor.apply(disable)
        XCTAssertFalse(fm.fileExists(atPath: skillDirectory.path))
        XCTAssertTrue(fm.fileExists(atPath: quarantineTarget))

        // Enable -> restore back into ~/.trae/skills/bar; the user-store scope-binding must allow this.
        let enable = try builder.planEnable(capabilityID: capability.id, graph: graph)
        let restoreOp = try XCTUnwrap(enable.operations.first { $0.kind == .restorePath })
        XCTAssertEqual(restoreOp.path, quarantineTarget)
        _ = try executor.apply(enable)
        XCTAssertTrue(fm.fileExists(atPath: skillFile.path),
                      "a legitimate user-scope quarantine must still restore into the user home")
        XCTAssertFalse(fm.fileExists(atPath: quarantineTarget),
                       "the quarantine content should be moved back out on restore")
    }

    func testStaleEnabledManifestIntentDoesNotContradictOnDiskQuarantineTile() throws {
        // Regression for LOW-4-enable-atomicity: the enable plan writes the .agents manifest (status=enabled)
        // BEFORE the restore move runs. If the restore move fails, the source is still parked in
        // .orbita/disabled while the manifest already says enabled. The next scan must NOT surface a
        // contradictory disabled+enabled tile — the on-disk store is authoritative.
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("OrbitaCoreTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }

        let originalSource = temporaryRoot.appendingPathComponent(".trae/skills/parked").path
        let entryDir = temporaryRoot.appendingPathComponent(".orbita/disabled/skill/testkey")
        let content = entryDir.appendingPathComponent("parked")
        try FileManager.default.createDirectory(at: content, withIntermediateDirectories: true)
        try skillText(name: "parked", body: "b").write(
            to: content.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        try OrbitaDisabledStore.sidecarJSON(
            capabilityID: "skill:quarantined-demo",
            name: "parked",
            type: "skill",
            originalSourcePath: originalSource,
            scope: "project"
        ).write(to: entryDir.appendingPathComponent(".orbita-restore.json"), atomically: true, encoding: .utf8)

        // Stale manifest left behind by a failed enable: it already flipped to enabled.
        let manifest = temporaryRoot.appendingPathComponent(".agents/manifest.json")
        try FileManager.default.createDirectory(at: manifest.deletingLastPathComponent(), withIntermediateDirectories: true)
        try """
        {
          "schemaVersion": 1,
          "capabilities": [
            {
              "id": "skill:quarantined-demo",
              "name": "parked",
              "type": "skill",
              "status": "enabled",
              "sourcePath": "\(originalSource)"
            }
          ]
        }
        """.write(to: manifest, atomically: true, encoding: .utf8)

        let graph = CapabilityResolver().resolve(scanResult: try scanProjectOnly(temporaryRoot))
        let tile = try XCTUnwrap(graph.capabilities.first { $0.id == "skill:quarantined-demo" })
        XCTAssertEqual(tile.source.kind, "orbita-quarantine")
        XCTAssertTrue(tile.statuses.contains(.disabled), "on-disk store is authoritative: tile stays disabled")
        XCTAssertFalse(tile.statuses.contains(.enabled), "a stale enabled manifest intent must not contradict the parked source")
        XCTAssertFalse(tile.statuses.contains(.drifted), "a quarantined tile is cleanly disabled, not drifted")
        XCTAssertEqual(tile.metadata["manifestStatus"], CapabilityStatus.disabled.rawValue,
                       "manifestStatus is aligned to on-disk truth so the next apply heals the stale manifest")
    }

    func testDisableAfterMergePreservesOtherManifestEntries() throws {
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("OrbitaCoreTests-\(UUID().uuidString)")
        try FileManager.default.copyItem(at: try fixtureURL("MixedProject"), to: temporaryRoot)
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }

        let initialGraph = CapabilityResolver().resolve(scanResult: try scanProjectOnly(temporaryRoot))
        let skill = try XCTUnwrap(initialGraph.capabilities.first { $0.name == "lark-doc" && $0.type == .skill })
        let command = try XCTUnwrap(initialGraph.capabilities.first { $0.name == "bootstrap" && $0.type == .command })
        let executor = ApplyPlanExecutor()
        _ = try executor.apply(try ApplyPlanBuilder().planMerge(graph: initialGraph))

        let mergedGraph = CapabilityResolver().resolve(scanResult: try scanProjectOnly(temporaryRoot))
        _ = try executor.apply(try ApplyPlanBuilder().planDisable(capabilityID: skill.id, graph: mergedGraph))

        let manifestText = try String(contentsOf: temporaryRoot.appendingPathComponent(".agents/manifest.json"), encoding: .utf8)
        XCTAssertTrue(manifestText.contains(skill.id))
        XCTAssertTrue(manifestText.contains(command.id))
        XCTAssertTrue(manifestText.contains(CapabilityStatus.disabled.rawValue))
        XCTAssertTrue(manifestText.contains(CapabilityStatus.enabled.rawValue))
    }

    func testDeleteAfterMergeRemovesCapabilityIntentSkillLinkAndSource() throws {
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("OrbitaCoreTests-\(UUID().uuidString)")
        try FileManager.default.copyItem(at: try fixtureURL("MixedProject"), to: temporaryRoot)
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }

        let initialGraph = CapabilityResolver().resolve(scanResult: try scanProjectOnly(temporaryRoot))
        let skill = try XCTUnwrap(initialGraph.capabilities.first { $0.name == "lark-doc" && $0.type == .skill })
        let command = try XCTUnwrap(initialGraph.capabilities.first { $0.name == "bootstrap" && $0.type == .command })
        let executor = ApplyPlanExecutor()
        _ = try executor.apply(try ApplyPlanBuilder().planMerge(graph: initialGraph))

        let mergedGraph = CapabilityResolver().resolve(scanResult: try scanProjectOnly(temporaryRoot))
        let plan = try ApplyPlanBuilder().planDelete(capabilityID: skill.id, graph: mergedGraph)
        _ = try executor.apply(plan)

        let manifestText = try String(contentsOf: temporaryRoot.appendingPathComponent(".agents/manifest.json"), encoding: .utf8)
        XCTAssertEqual(plan.action, .delete)
        XCTAssertFalse(manifestText.contains(skill.id))
        XCTAssertTrue(manifestText.contains(command.id))
        XCTAssertFalse(FileManager.default.fileExists(atPath: temporaryRoot.appendingPathComponent(".agents/skills/lark-doc").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: skill.source.path))
    }

    func testDeleteManifestOnlyCapabilityRemovesRecordedSourcePathNotManifest() throws {
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("OrbitaCoreTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }

        let recordedSource = temporaryRoot
            .appendingPathComponent("external")
            .appendingPathComponent("orphan")
            .appendingPathComponent("SKILL.md")
        let manifest = temporaryRoot.appendingPathComponent(".agents/manifest.json")
        try FileManager.default.createDirectory(at: manifest.deletingLastPathComponent(), withIntermediateDirectories: true)
        try """
        {
          "schemaVersion": 1,
          "capabilities": [
            {
              "id": "skill:external-orphan",
              "name": "external-orphan",
              "type": "skill",
              "status": "enabled",
              "sourcePath": "\(recordedSource.path)"
            }
          ]
        }
        """.write(to: manifest, atomically: true, encoding: .utf8)

        let graph = CapabilityResolver().resolve(scanResult: try scanProjectOnly(temporaryRoot))
        let capability = try XCTUnwrap(graph.capabilities.first { $0.id == "skill:external-orphan" })
        let plan = try ApplyPlanBuilder().planDelete(capabilityID: capability.id, graph: graph)

        XCTAssertTrue(plan.operations.contains {
            $0.kind == .removePath && $0.path == recordedSource.deletingLastPathComponent().path
        })
        XCTAssertFalse(plan.operations.contains {
            $0.kind == .removePath && $0.path == manifest.path
        })
    }

    func testEnableAfterDisablePreservesOtherManifestEntries() throws {
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("OrbitaCoreTests-\(UUID().uuidString)")
        try FileManager.default.copyItem(at: try fixtureURL("MixedProject"), to: temporaryRoot)
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }

        let initialGraph = CapabilityResolver().resolve(scanResult: try scanProjectOnly(temporaryRoot))
        let skill = try XCTUnwrap(initialGraph.capabilities.first { $0.name == "lark-doc" && $0.type == .skill })
        let command = try XCTUnwrap(initialGraph.capabilities.first { $0.name == "bootstrap" && $0.type == .command })
        let executor = ApplyPlanExecutor()
        _ = try executor.apply(try ApplyPlanBuilder().planMerge(graph: initialGraph))

        let mergedGraph = CapabilityResolver().resolve(scanResult: try scanProjectOnly(temporaryRoot))
        _ = try executor.apply(try ApplyPlanBuilder().planDisable(capabilityID: skill.id, graph: mergedGraph))

        let disabledGraph = CapabilityResolver().resolve(scanResult: try scanProjectOnly(temporaryRoot))
        _ = try executor.apply(try ApplyPlanBuilder().planEnable(capabilityID: skill.id, graph: disabledGraph))

        let manifestText = try String(contentsOf: temporaryRoot.appendingPathComponent(".agents/manifest.json"), encoding: .utf8)
        XCTAssertTrue(manifestText.contains(skill.id))
        XCTAssertTrue(manifestText.contains(command.id))
        XCTAssertFalse(manifestText.contains(CapabilityStatus.disabled.rawValue))
        XCTAssertTrue(manifestText.contains(CapabilityStatus.enabled.rawValue))
    }

    func testDisableSkillPlanExecutorDoesNotWriteAdapterFiles() throws {
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("OrbitaCoreTests-\(UUID().uuidString)")
        try FileManager.default.copyItem(at: try fixtureURL("MixedProject"), to: temporaryRoot)
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }

        let initialGraph = CapabilityResolver().resolve(scanResult: try scanProjectOnly(temporaryRoot))
        let skill = try XCTUnwrap(initialGraph.capabilities.first { $0.name == "lark-doc" && $0.type == .skill })
        let executor = ApplyPlanExecutor()
        _ = try executor.apply(try ApplyPlanBuilder().planEnable(capabilityID: skill.id, graph: initialGraph))
        let enabledGraph = CapabilityResolver().resolve(scanResult: try scanProjectOnly(temporaryRoot))

        let disablePlan = try ApplyPlanBuilder().planDisable(capabilityID: skill.id, graph: enabledGraph)
        _ = try executor.apply(disablePlan)

        XCTAssertFalse(FileManager.default.fileExists(atPath: temporaryRoot.appendingPathComponent(".agents/adapters/codex/capabilities.json").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: temporaryRoot.appendingPathComponent(".orbita/adapters/codex/capabilities.json").path))
    }

    func testRollbackPlanInvertsLastApplyLogAction() throws {
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("OrbitaCoreTests-\(UUID().uuidString)")
        try FileManager.default.copyItem(at: try fixtureURL("MixedProject"), to: temporaryRoot)
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }

        let initialGraph = CapabilityResolver().resolve(scanResult: try scanProjectOnly(temporaryRoot))
        let skill = try XCTUnwrap(initialGraph.capabilities.first { $0.name == "lark-doc" && $0.type == .skill })
        let executor = ApplyPlanExecutor()
        _ = try executor.apply(try ApplyPlanBuilder().planEnable(capabilityID: skill.id, graph: initialGraph))
        let enabledGraph = CapabilityResolver().resolve(scanResult: try scanProjectOnly(temporaryRoot))
        _ = try executor.apply(try ApplyPlanBuilder().planDisable(capabilityID: skill.id, graph: enabledGraph))

        let rollback = try ApplyPlanBuilder().planRollback(graph: enabledGraph)

        XCTAssertEqual(rollback.action, .rollback)
        XCTAssertEqual(rollback.capabilityID, skill.id)
        XCTAssertTrue(rollback.operations.contains { $0.kind == .createSymlink && $0.path.hasSuffix("/.agents/skills/lark-doc") })
        XCTAssertFalse(rollback.operations.contains { $0.kind == .writeFile && $0.path.contains("/adapters/") })
        XCTAssertTrue(rollback.operations.contains { $0.kind == .appendLog && ($0.content ?? "").contains("rollback") })
    }

    /// A forked command (its source is a symlink) must survive a disable→enable round trip: disabling it
    /// removes the link from the agent's command dir, but re-enabling restores it. Before rollback symmetry,
    /// disable bare-removed the link and enable could not reconstruct it (only skills could), silently
    /// leaving the manifest "enabled" while the link stayed gone.
    func testDisableEnableRoundTripRestoresForkedCommandSymlink() throws {
        let fm = FileManager.default
        let projectRoot = fm.temporaryDirectory.standardizedFileURL
            .appendingPathComponent("OrbitaRollback-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: projectRoot) }

        let realCommand = projectRoot.appendingPathComponent("shared/review.md")
        let forkLink = projectRoot.appendingPathComponent(".codex/commands/review.md")
        try fm.createDirectory(at: realCommand.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.createDirectory(at: forkLink.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "# Review\n".write(to: realCommand, atomically: true, encoding: .utf8)
        try fm.createSymbolicLink(atPath: forkLink.path, withDestinationPath: realCommand.path)

        let graph = CapabilityResolver().resolve(scanResult: try scanProjectOnly(projectRoot))
        let command = try XCTUnwrap(graph.capabilities.first { $0.type == .command && $0.name == "review" })

        let executor = ApplyPlanExecutor()
        _ = try executor.apply(try ApplyPlanBuilder().planDisable(capabilityID: command.id, graph: graph))
        XCTAssertNil(
            try? fm.destinationOfSymbolicLink(atPath: forkLink.path),
            "disabling a forked command should remove its link from the agent's command dir"
        )

        let disabledGraph = CapabilityResolver().resolve(scanResult: try scanProjectOnly(projectRoot))
        let disabledCommand = try XCTUnwrap(disabledGraph.capabilities.first { $0.type == .command && $0.name == "review" })
        _ = try executor.apply(try ApplyPlanBuilder().planEnable(capabilityID: disabledCommand.id, graph: disabledGraph))

        let restoredTarget = try fm.destinationOfSymbolicLink(atPath: forkLink.path)
        XCTAssertEqual(restoredTarget, realCommand.path, "re-enabling a forked command must restore its symlink")
    }

    /// Rolling back a disable must restore a forked command's symlink — not just a skill's. Before rollback
    /// symmetry, planRollback only re-created `.agents/skills/<name>` links, so a command/agent fork stayed
    /// gone while the manifest flipped back to enabled.
    func testRollbackRestoresDisabledForkedCommandSymlink() throws {
        let fm = FileManager.default
        let projectRoot = fm.temporaryDirectory.standardizedFileURL
            .appendingPathComponent("OrbitaRollback-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: projectRoot) }

        let realCommand = projectRoot.appendingPathComponent("shared/review.md")
        let forkLink = projectRoot.appendingPathComponent(".codex/commands/review.md")
        try fm.createDirectory(at: realCommand.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.createDirectory(at: forkLink.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "# Review\n".write(to: realCommand, atomically: true, encoding: .utf8)
        try fm.createSymbolicLink(atPath: forkLink.path, withDestinationPath: realCommand.path)

        let graph = CapabilityResolver().resolve(scanResult: try scanProjectOnly(projectRoot))
        let command = try XCTUnwrap(graph.capabilities.first { $0.type == .command && $0.name == "review" })

        let executor = ApplyPlanExecutor()
        _ = try executor.apply(try ApplyPlanBuilder().planDisable(capabilityID: command.id, graph: graph))
        XCTAssertNil(try? fm.destinationOfSymbolicLink(atPath: forkLink.path))

        let disabledGraph = CapabilityResolver().resolve(scanResult: try scanProjectOnly(projectRoot))
        let rollback = try ApplyPlanBuilder().planRollback(graph: disabledGraph)
        XCTAssertEqual(rollback.action, .rollback)
        _ = try executor.apply(rollback)

        XCTAssertEqual(
            try fm.destinationOfSymbolicLink(atPath: forkLink.path),
            realCommand.path,
            "rolling back the disable of a forked command must restore its symlink"
        )
    }

    func testRollbackPlanRejectsMergeLogEntryWithSpecificError() throws {
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("OrbitaCoreTests-\(UUID().uuidString)")
        try FileManager.default.copyItem(at: try fixtureURL("MixedProject"), to: temporaryRoot)
        let logPath = temporaryRoot.appendingPathComponent(".agents/logs/apply.log")
        try FileManager.default.createDirectory(at: logPath.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "2026-05-23T00:00:00Z merge workspace\n".write(to: logPath, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }

        let graph = CapabilityResolver().resolve(scanResult: try scanProjectOnly(temporaryRoot))

        do {
            _ = try ApplyPlanBuilder().planRollback(graph: graph)
            XCTFail("Expected merge apply log entries to be rejected")
        } catch let error as OrbitaError {
            XCTAssertEqual(error.errorDescription, "Invalid apply plan: Cannot rollback a merge entry")
        }
    }

    func testCleanPlanRemovesBrokenAgentsSymlinksOnly() throws {
        let temporaryRoot = FileManager.default.temporaryDirectory.standardizedFileURL
            .appendingPathComponent("OrbitaCoreTests-\(UUID().uuidString)")
        let skillsRoot = temporaryRoot.appendingPathComponent(".agents/skills")
        try FileManager.default.createDirectory(at: skillsRoot, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: skillsRoot.appendingPathComponent("missing-skill"),
            withDestinationURL: URL(fileURLWithPath: "../missing-skill")
        )
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }

        let graph = CapabilityResolver().resolve(scanResult: try scanProjectOnly(temporaryRoot))

        let plan = try ApplyPlanBuilder().planClean(graph: graph)

        XCTAssertEqual(plan.action, .clean)
        XCTAssertEqual(plan.capabilityID, "workspace")
        XCTAssertTrue(plan.operations.contains { $0.kind == .removePath && $0.path.hasSuffix("/.agents/skills/missing-skill") })
        XCTAssertFalse(plan.operations.contains { $0.path.contains("node_modules") })
    }

    func testCleanPlanRemovesStaleAdapterFilesReferencingMissingCapabilities() throws {
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("OrbitaCoreTests-\(UUID().uuidString)")
        try FileManager.default.copyItem(at: try fixtureURL("MixedProject"), to: temporaryRoot)
        let adapterFile = temporaryRoot.appendingPathComponent(".orbita/adapters/codex/capabilities.json")
        try FileManager.default.createDirectory(at: adapterFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try """
        {
          "schemaVersion": 1,
          "agent": "codex",
          "capabilities": [
            {
              "id": "missing-capability",
              "name": "Missing",
              "type": "skill",
              "scope": "project",
              "sourcePath": "/tmp/missing",
              "statuses": ["discovered"],
              "risks": ["info"]
            }
          ],
          "mappings": []
        }
        """.write(to: adapterFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }

        let graph = CapabilityResolver().resolve(scanResult: try scanProjectOnly(temporaryRoot))

        let plan = try ApplyPlanBuilder().planClean(graph: graph)

        XCTAssertTrue(plan.operations.contains { operation in
            operation.kind == .removePath
                && operation.path.hasSuffix("/.orbita/adapters/codex/capabilities.json")
                && operation.description.contains("stale adapter")
        })
        XCTAssertFalse(plan.operations.contains { $0.path.contains("node_modules") })
    }

    func testCleanPlanRemovesLegacyAgentsAdapterFiles() throws {
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("OrbitaCoreTests-\(UUID().uuidString)")
        try FileManager.default.copyItem(at: try fixtureURL("MixedProject"), to: temporaryRoot)
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }

        let graph = CapabilityResolver().resolve(scanResult: try scanProjectOnly(temporaryRoot))
        let skill = try XCTUnwrap(graph.capabilities.first { $0.name == "lark-doc" && $0.type == .skill })
        let adapterFile = temporaryRoot.appendingPathComponent(".agents/adapters/codex/capabilities.json")
        try FileManager.default.createDirectory(at: adapterFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try """
        {
          "schemaVersion": 1,
          "agent": "codex",
          "capabilities": [
            {
              "id": "\(skill.id)",
              "name": "\(skill.name)",
              "type": "\(skill.type.rawValue)",
              "scope": "\(skill.scope.rawValue)",
              "sourcePath": "\(skill.source.path)",
              "statuses": ["discovered"],
              "risks": ["info"]
            }
          ],
          "mappings": []
        }
        """.write(to: adapterFile, atomically: true, encoding: .utf8)

        let plan = try ApplyPlanBuilder().planClean(graph: graph)

        XCTAssertTrue(plan.operations.contains { operation in
            operation.kind == .removePath
                && operation.path.hasSuffix("/.agents/adapters/codex/capabilities.json")
                && operation.description.contains("legacy .agents adapter")
        })
    }

    func testCleanPlanRemovesAdapterFilesReferencingDisabledCapabilities() throws {
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("OrbitaCoreTests-\(UUID().uuidString)")
        try FileManager.default.copyItem(at: try fixtureURL("MixedProject"), to: temporaryRoot)
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }

        let initialGraph = CapabilityResolver().resolve(scanResult: try scanProjectOnly(temporaryRoot))
        let skill = try XCTUnwrap(initialGraph.capabilities.first { $0.name == "lark-doc" && $0.type == .skill })
        let manifest = temporaryRoot.appendingPathComponent(".agents/manifest.json")
        try FileManager.default.createDirectory(at: manifest.deletingLastPathComponent(), withIntermediateDirectories: true)
        try """
        {
          "schemaVersion": 1,
          "capabilities": [
            {
              "id": "\(skill.id)",
              "name": "\(skill.name)",
              "type": "\(skill.type.rawValue)",
              "status": "disabled",
              "sourcePath": "\(skill.source.path)"
            }
          ]
        }
        """.write(to: manifest, atomically: true, encoding: .utf8)

        let adapterFile = temporaryRoot.appendingPathComponent(".orbita/adapters/codex/capabilities.json")
        try FileManager.default.createDirectory(at: adapterFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try """
        {
          "schemaVersion": 1,
          "agent": "codex",
          "capabilities": [
            {
              "id": "\(skill.id)",
              "name": "\(skill.name)",
              "type": "\(skill.type.rawValue)",
              "scope": "\(skill.scope.rawValue)",
              "sourcePath": "\(skill.source.path)",
              "statuses": ["discovered"],
              "risks": ["info"]
            }
          ],
          "mappings": []
        }
        """.write(to: adapterFile, atomically: true, encoding: .utf8)

        let graph = CapabilityResolver().resolve(scanResult: try scanProjectOnly(temporaryRoot))

        let plan = try ApplyPlanBuilder().planClean(graph: graph)

        XCTAssertTrue(plan.operations.contains { operation in
            operation.kind == .removePath
                && operation.path.hasSuffix("/.orbita/adapters/codex/capabilities.json")
                && operation.description.contains("disabled")
        })
    }

    func testCleanPlanExecutorRemovesBrokenSymlinks() throws {
        let temporaryRoot = FileManager.default.temporaryDirectory.standardizedFileURL
            .appendingPathComponent("OrbitaCoreTests-\(UUID().uuidString)")
        let skillsRoot = temporaryRoot.appendingPathComponent(".agents/skills")
        let symlink = skillsRoot.appendingPathComponent("missing-skill")
        try FileManager.default.createDirectory(at: skillsRoot, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: symlink,
            withDestinationURL: URL(fileURLWithPath: "../missing-skill")
        )
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }
        XCTAssertNoThrow(try FileManager.default.destinationOfSymbolicLink(atPath: symlink.path))

        let graph = CapabilityResolver().resolve(scanResult: try scanProjectOnly(temporaryRoot))
        let plan = try ApplyPlanBuilder().planClean(graph: graph)

        _ = try ApplyPlanExecutor().apply(plan)

        XCTAssertThrowsError(try FileManager.default.destinationOfSymbolicLink(atPath: symlink.path))
    }

    func testCleanPlanIsNoopWhenThereAreNoBrokenAgentsSymlinks() throws {
        let root = try fixtureURL("MixedProject")
        let graph = CapabilityResolver().resolve(scanResult: try scanProjectOnly(root))

        let plan = try ApplyPlanBuilder().planClean(graph: graph)

        XCTAssertEqual(plan.action, .clean)
        XCTAssertEqual(plan.operations.count, 0)
        XCTAssertFalse(plan.requiresConfirmation)
    }

    func testApplyPlanExecutorReportsCompletedFailedAndPendingOperations() throws {
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("OrbitaCoreTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }

        let completedOperation = ApplyOperation(
            kind: .createDirectory,
            path: temporaryRoot.appendingPathComponent(".agents").path,
            risk: .write,
            description: "Create .agents root"
        )
        let failedOperation = ApplyOperation(
            kind: .writeFile,
            path: temporaryRoot.appendingPathComponent("outside.json").path,
            content: "{}\n",
            risk: .write,
            description: "Attempt unsafe write"
        )
        let pendingOperation = ApplyOperation(
            kind: .writeFile,
            path: temporaryRoot.appendingPathComponent(".agents/manifest.json").path,
            content: "{}\n",
            risk: .write,
            description: "Pending safe write"
        )
        let plan = ApplyPlan(
            projectRoot: temporaryRoot.path,
            action: .enable,
            capabilityID: "test",
            requiresConfirmation: true,
            operations: [completedOperation, failedOperation, pendingOperation]
        )

        do {
            _ = try ApplyPlanExecutor().apply(plan)
            XCTFail("Expected apply to throw partial failure details")
        } catch let error as ApplyExecutionError {
            XCTAssertEqual(error.completedOperations, [completedOperation])
            XCTAssertEqual(error.failedOperation, failedOperation)
            XCTAssertEqual(error.pendingOperations, [pendingOperation])
            XCTAssertTrue(error.errorDescription?.contains("outside .agents") == true)
        }
    }

    func testDoctorReportChecksUserCapabilityDirectories() throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("OrbitaDoctorTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: home.appendingPathComponent(".codex/skills"),
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: home) }

        let report = DoctorReportBuilder().report(
            currentDirectory: home.path,
            homeDirectory: home,
            swiftVersion: "test-swift"
        )

        XCTAssertEqual(report.swiftVersion, "test-swift")
        XCTAssertTrue(report.checks.contains { check in
            check.id == "codex-skills" && check.status == .ok && check.path?.hasSuffix("/.codex/skills") == true
        })
        XCTAssertTrue(report.checks.contains { check in
            check.id == "agents-skills" && check.status == .warning && check.message.contains("does not exist")
        })
    }

    func testScansCodexPluginCacheWithEnablementAndUpdateCommand() throws {
        let projectRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("OrbitaCoreTests-\(UUID().uuidString)")
        let registryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("OrbitaCodexPlugins-\(UUID().uuidString)")
        let config = registryRoot.appendingPathComponent("config.toml")
        let manifest = registryRoot
            .appendingPathComponent("cache/test-marketplace/sample-plugin/1.2.3/.codex-plugin/plugin.json")
        let hooks = registryRoot
            .appendingPathComponent("cache/test-marketplace/sample-plugin/1.2.3/hooks/hooks.json")
        try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: manifest.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: hooks.deletingLastPathComponent(), withIntermediateDirectories: true)
        try """
        [plugins."sample-plugin@test-marketplace"]
        enabled = false
        """.write(to: config, atomically: true, encoding: .utf8)
        try """
        {
          "name": "sample-plugin",
          "version": "1.2.3",
          "description": "Sample plugin"
        }
        """.write(to: manifest, atomically: true, encoding: .utf8)
        try """
        {
          "hooks": {
            "PostToolUse": [
              {
                "matcher": "Write",
                "hooks": [
                  {
                    "type": "command",
                    "command": "node hooks/sample.js"
                  }
                ]
              }
            ]
          }
        }
        """.write(to: hooks, atomically: true, encoding: .utf8)
        defer {
            try? FileManager.default.removeItem(at: projectRoot)
            try? FileManager.default.removeItem(at: registryRoot)
        }

        let result = try CapabilityScanner().scan(
            projectRoot: projectRoot,
            options: ScanOptions(
                includeUserScope: true,
                userSkillRoots: [],
                codexConfigURL: config,
                codexPluginCacheRoot: registryRoot.appendingPathComponent("cache"),
                claudeInstalledPluginsURL: registryRoot.appendingPathComponent("missing-claude.json"),
                claudeSettingsURLs: []
            )
        )

        let plugin = try XCTUnwrap(
            result.capabilities.first { $0.source.kind == "codex-plugin" },
            result.capabilities.map { "\($0.name):\($0.source.kind):\($0.source.path)" }.joined(separator: "\n")
        )
        XCTAssertEqual(plugin.name, "Sample")
        XCTAssertEqual(plugin.statuses, [.disabled])
        XCTAssertEqual(plugin.metadata["manager"], "codex")
        XCTAssertEqual(plugin.metadata["installedVersion"], "1.2.3")
        XCTAssertEqual(plugin.metadata["enableMode"], "plugin-add")
        XCTAssertTrue(plugin.metadata["enableCommand"]?.contains("codex plugin add 'sample-plugin@test-marketplace'") == true)
        XCTAssertTrue(plugin.metadata["deleteCommand"]?.contains("codex plugin remove 'sample-plugin@test-marketplace'") == true)
        XCTAssertEqual(plugin.metadata["disableMode"], "config")
        XCTAssertTrue(plugin.metadata["disableCommand"]?.contains("[plugins.\"sample-plugin@test-marketplace\"]") == true)
        XCTAssertTrue(plugin.metadata["updateCommand"]?.contains("codex plugin marketplace upgrade 'test-marketplace'") == true)

        let hook = try XCTUnwrap(result.capabilities.first { $0.source.kind == "codex-plugin-hook" })
        XCTAssertEqual(hook.type, .hook)
        XCTAssertEqual(hook.pluginID, plugin.id)
        XCTAssertEqual(hook.metadata["pluginSelector"], "sample-plugin@test-marketplace")

        let items = CapabilityDisplayGrouper().items(for: [plugin, hook], preservesInputOrder: true)
        XCTAssertEqual(items.count, 1)
        guard case let .group(group) = items.first else {
            return XCTFail("Expected plugin hook to be grouped under the real plugin")
        }
        XCTAssertEqual(group.kind, .plugin)
        XCTAssertEqual(group.representative?.id, plugin.id)
    }

    func testScansNestedCodexPluginInstallCacheByManifestName() throws {
        let projectRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("OrbitaCoreTests-\(UUID().uuidString)")
        let registryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("OrbitaNestedCodexPlugins-\(UUID().uuidString)")
        let cacheRoot = registryRoot.appendingPathComponent(".codex/plugins/cache")
        let config = registryRoot.appendingPathComponent(".codex/config.toml")
        let oldManifest = cacheRoot
            .appendingPathComponent("unicorn-marketplace/plugin-install-2ZrgBl/im-knowledge/1.4.9/.claude-plugin/plugin.json")
        let latestManifest = cacheRoot
            .appendingPathComponent("unicorn-marketplace/plugin-install-2zD3G5/im-knowledge/1.4.10/.claude-plugin/plugin.json")
        let oldSkill = cacheRoot
            .appendingPathComponent("unicorn-marketplace/plugin-install-2ZrgBl/im-knowledge/1.4.9/skills/im-legacy-api/SKILL.md")
        let latestSkill = cacheRoot
            .appendingPathComponent("unicorn-marketplace/plugin-install-2zD3G5/im-knowledge/1.4.10/skills/im-foundation-api/SKILL.md")
        try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: oldManifest.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: latestManifest.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: oldSkill.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: latestSkill.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: config.deletingLastPathComponent(), withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: projectRoot)
            try? FileManager.default.removeItem(at: registryRoot)
        }

        try """
        [plugins."im-knowledge@unicorn-marketplace"]
        enabled = true
        """.write(to: config, atomically: true, encoding: .utf8)
        try """
        {
          "name": "im-knowledge",
          "version": "1.4.9",
          "description": "IM knowledge"
        }
        """.write(to: oldManifest, atomically: true, encoding: .utf8)
        try """
        {
          "name": "im-knowledge",
          "version": "1.4.10",
          "description": "IM knowledge"
        }
        """.write(to: latestManifest, atomically: true, encoding: .utf8)
        try skillText(name: "im-legacy-api", body: "Legacy APIs.")
            .write(to: oldSkill, atomically: true, encoding: .utf8)
        try skillText(name: "im-foundation-api", body: "Foundation APIs.")
            .write(to: latestSkill, atomically: true, encoding: .utf8)

        let result = try CapabilityScanner().scan(
            projectRoot: projectRoot,
            options: ScanOptions(
                userSkillRoots: [cacheRoot],
                codexConfigURL: config,
                codexPluginCacheRoot: cacheRoot,
                claudeInstalledPluginsURL: registryRoot.appendingPathComponent("missing-claude.json"),
                claudeSettingsURLs: []
            )
        )

        let plugins = result.capabilities.filter { $0.source.kind == "codex-plugin" }
        XCTAssertEqual(
            plugins.count,
            1,
            result.capabilities.map { "\($0.name):\($0.source.kind):\($0.source.path)" }.joined(separator: "\n")
        )
        let plugin = try XCTUnwrap(plugins.first)
        XCTAssertEqual(plugin.id, "plugin:codex-cache:unicorn-marketplace:im-knowledge")
        XCTAssertEqual(plugin.name, "Im Knowledge")
        XCTAssertEqual(plugin.statuses, [.enabled])
        XCTAssertEqual(plugin.source.packageName, "im-knowledge")
        XCTAssertTrue(plugin.source.path.hasSuffix("/unicorn-marketplace/plugin-install-2zD3G5/im-knowledge"))
        XCTAssertEqual(plugin.metadata["pluginSelector"], "im-knowledge@unicorn-marketplace")
        XCTAssertEqual(plugin.metadata["installedVersion"], "1.4.10")

        let skill = try XCTUnwrap(result.capabilities.first { $0.name == "im-foundation-api" && $0.type == .skill })
        XCTAssertEqual(skill.pluginID, plugin.id)
        XCTAssertEqual(skill.source.packageName, "im-knowledge")
        XCTAssertEqual(skill.metadata["pluginSelector"], "im-knowledge@unicorn-marketplace")
        XCTAssertEqual(skill.metadata["installedVersion"], "1.4.10")
        XCTAssertFalse(result.capabilities.contains { $0.name == "im-legacy-api" })
        let graph = CapabilityResolver().resolve(scanResult: result)
        XCTAssertFalse(graph.capabilities.contains { capability in
            capability.type == .plugin
                && (capability.name.contains("Plugin Install")
                    || capability.id.contains("plugin-install")
                    || capability.source.packageName?.contains("plugin-install") == true)
        })
    }

    func testScansCanonicalCodexPluginCacheSkillsWhenInstallTempHasSameVersion() throws {
        let projectRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("OrbitaCoreTests-\(UUID().uuidString)")
        let registryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("OrbitaCanonicalCodexPlugins-\(UUID().uuidString)")
        let cacheRoot = registryRoot.appendingPathComponent(".codex/plugins/cache")
        let config = registryRoot.appendingPathComponent(".codex/config.toml")
        let canonicalManifest = cacheRoot
            .appendingPathComponent("unicorn-marketplace/im-knowledge/1.4.10/.claude-plugin/plugin.json")
        let tempManifest = cacheRoot
            .appendingPathComponent("unicorn-marketplace/plugin-install-2zD3G5/im-knowledge/1.4.10/.claude-plugin/plugin.json")
        let canonicalSkill = cacheRoot
            .appendingPathComponent("unicorn-marketplace/im-knowledge/1.4.10/skills/im-current-api/SKILL.md")
        let tempSkill = cacheRoot
            .appendingPathComponent("unicorn-marketplace/plugin-install-2zD3G5/im-knowledge/1.4.10/skills/im-temp-api/SKILL.md")
        try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: canonicalManifest.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: tempManifest.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: canonicalSkill.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: tempSkill.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: config.deletingLastPathComponent(), withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: projectRoot)
            try? FileManager.default.removeItem(at: registryRoot)
        }

        try """
        [plugins."im-knowledge@unicorn-marketplace"]
        enabled = true
        """.write(to: config, atomically: true, encoding: .utf8)
        let manifest = """
        {
          "name": "im-knowledge",
          "version": "1.4.10",
          "description": "IM knowledge"
        }
        """
        try manifest.write(to: canonicalManifest, atomically: true, encoding: .utf8)
        try manifest.write(to: tempManifest, atomically: true, encoding: .utf8)
        try skillText(name: "im-current-api", body: "Current APIs.")
            .write(to: canonicalSkill, atomically: true, encoding: .utf8)
        try skillText(name: "im-temp-api", body: "Temp APIs.")
            .write(to: tempSkill, atomically: true, encoding: .utf8)

        let result = try CapabilityScanner().scan(
            projectRoot: projectRoot,
            options: ScanOptions(
                userSkillRoots: [cacheRoot],
                codexConfigURL: config,
                codexPluginCacheRoot: cacheRoot,
                claudeInstalledPluginsURL: registryRoot.appendingPathComponent("missing-claude.json"),
                claudeSettingsURLs: []
            )
        )

        let plugin = try XCTUnwrap(result.capabilities.first { $0.id == "plugin:codex-cache:unicorn-marketplace:im-knowledge" })
        XCTAssertTrue(plugin.source.path.hasSuffix("/unicorn-marketplace/im-knowledge"))
        XCTAssertTrue(result.capabilities.contains { $0.name == "im-current-api" && $0.type == .skill })
        XCTAssertFalse(result.capabilities.contains { $0.name == "im-temp-api" })
    }

    func testScansProjectCodexPluginWhenUserScopeIsDisabled() throws {
        let projectRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("OrbitaCoreTests-\(UUID().uuidString)")
        let manifest = projectRoot
            .appendingPathComponent("plugins/project-helper/.codex-plugin/plugin.json")
        let config = projectRoot.appendingPathComponent(".codex/config.toml")
        try FileManager.default.createDirectory(at: manifest.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: config.deletingLastPathComponent(), withIntermediateDirectories: true)
        try """
        [plugins."project-helper@project"]
        enabled = true
        """.write(to: config, atomically: true, encoding: .utf8)
        try """
        {
          "name": "project-helper",
          "version": "0.2.0",
          "description": "Project local plugin"
        }
        """.write(to: manifest, atomically: true, encoding: .utf8)
        defer {
            try? FileManager.default.removeItem(at: projectRoot)
        }

        let result = try CapabilityScanner().scan(
            projectRoot: projectRoot,
            options: ScanOptions(includeUserScope: false)
        )

        let plugin = try XCTUnwrap(result.capabilities.first { $0.source.kind == "codex-plugin" })
        XCTAssertEqual(plugin.scope, .project)
        XCTAssertEqual(plugin.statuses, [.enabled])
        XCTAssertEqual(plugin.metadata["pluginSelector"], "project-helper@project")
        XCTAssertEqual(plugin.metadata["enableMode"], "config")
        XCTAssertTrue(plugin.metadata["enableCommand"]?.contains("[plugins.\"project-helper@project\"]") == true)
    }

    func testMarketplaceRootSkipsProjectPluginsDirectory() throws {
        let projectRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("OrbitaCoreTests-\(UUID().uuidString)")
        let marketplaceManifest = projectRoot.appendingPathComponent(".claude-plugin/marketplace.json")
        let marketplacePlugin = projectRoot.appendingPathComponent("plugins/sample/.claude-plugin/plugin.json")
        let marketplaceSkill = projectRoot.appendingPathComponent("plugins/sample/skills/marketplace-skill/SKILL.md")
        let localSkill = projectRoot.appendingPathComponent(".codex/skills/local-skill/SKILL.md")
        try FileManager.default.createDirectory(at: marketplaceManifest.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: marketplacePlugin.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: marketplaceSkill.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: localSkill.deletingLastPathComponent(), withIntermediateDirectories: true)
        try """
        {
          "name": "sample-marketplace",
          "plugins": [
            { "name": "sample", "source": "./plugins/sample" }
          ]
        }
        """.write(to: marketplaceManifest, atomically: true, encoding: .utf8)
        try """
        {
          "name": "sample",
          "version": "0.1.0",
          "description": "Marketplace plugin source"
        }
        """.write(to: marketplacePlugin, atomically: true, encoding: .utf8)
        try skillText(name: "marketplace-skill", body: "marketplace plugin source skill")
            .write(to: marketplaceSkill, atomically: true, encoding: .utf8)
        try skillText(name: "local-skill", body: "skill that lives in the marketplace repo itself")
            .write(to: localSkill, atomically: true, encoding: .utf8)
        defer {
            try? FileManager.default.removeItem(at: projectRoot)
        }

        let result = try scanProjectOnly(projectRoot)

        XCTAssertFalse(
            result.capabilities.contains { $0.source.kind == "codex-plugin" && $0.source.path.contains("/plugins/sample") },
            "Marketplace plugin sources under <repo>/plugins must not be reported as project-scope plugins"
        )
        XCTAssertFalse(
            result.capabilities.contains { $0.type == .skill && $0.source.path.contains("/plugins/sample/skills/") },
            "Skills inside marketplace plugin sources must not be reported as project skills"
        )
        XCTAssertTrue(
            result.capabilities.contains { $0.type == .skill && $0.name == "local-skill" },
            "Skills inside the marketplace repo's own .codex/skills must still be scanned"
        )
    }

    func testScansClaudeInstalledPluginsWithProjectScopeAndLifecycleCommands() throws {
        let projectRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("OrbitaCoreTests-\(UUID().uuidString)")
        let registryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("OrbitaClaudePlugins-\(UUID().uuidString)")
        let installed = registryRoot.appendingPathComponent("installed_plugins.json")
        let settings = registryRoot.appendingPathComponent("settings.json")
        try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: registryRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            atPath: "\(registryRoot.path)/cache/test-marketplace/project-tool/2.0.0",
            withIntermediateDirectories: true
        )
        let pluginHooks = registryRoot.appendingPathComponent("cache/test-marketplace/project-tool/2.0.0/hooks/hooks.json")
        try FileManager.default.createDirectory(at: pluginHooks.deletingLastPathComponent(), withIntermediateDirectories: true)
        try """
        {
          "version": 2,
          "plugins": {
            "project-tool@test-marketplace": [
              {
                "scope": "project",
                "projectPath": "\(projectRoot.path)",
                "installPath": "\(registryRoot.path)/cache/test-marketplace/project-tool/2.0.0",
                "version": "2.0.0",
                "installedAt": "2026-05-01T00:00:00Z",
                "lastUpdated": "2026-05-02T00:00:00Z"
              }
            ],
            "other-project@test-marketplace": [
              {
                "scope": "project",
                "projectPath": "\(registryRoot.path)/Other",
                "installPath": "\(registryRoot.path)/cache/test-marketplace/other-project/1.0.0",
                "version": "1.0.0"
              }
            ]
          }
        }
        """.write(to: installed, atomically: true, encoding: .utf8)
        try """
        {
          "enabledPlugins": {
            "project-tool@test-marketplace": true,
            "other-project@test-marketplace": true
          }
        }
        """.write(to: settings, atomically: true, encoding: .utf8)
        try """
        {
          "hooks": {
            "SessionStart": [
              {
                "hooks": [
                  {
                    "type": "command",
                    "command": "bash hooks/project-tool.sh"
                  }
                ]
              }
            ]
          }
        }
        """.write(to: pluginHooks, atomically: true, encoding: .utf8)
        defer {
            try? FileManager.default.removeItem(at: projectRoot)
            try? FileManager.default.removeItem(at: registryRoot)
        }

        let result = try CapabilityScanner().scan(
            projectRoot: projectRoot,
            options: ScanOptions(
                includeUserScope: true,
                userSkillRoots: [],
                codexConfigURL: registryRoot.appendingPathComponent("missing-config.toml"),
                codexPluginCacheRoot: registryRoot.appendingPathComponent("missing-cache"),
                claudeInstalledPluginsURL: installed,
                claudeSettingsURLs: [settings]
            )
        )

        let plugin = try XCTUnwrap(result.capabilities.first { $0.name == "Project Tool" && $0.source.kind == "claude-plugin" })
        XCTAssertEqual(plugin.scope, .project)
        XCTAssertEqual(plugin.statuses, [.enabled])
        XCTAssertEqual(plugin.metadata["manager"], "claude-code")
        XCTAssertTrue(plugin.metadata["disableCommand"]?.contains("claude plugin disable 'project-tool@test-marketplace'") == true)
        XCTAssertTrue(plugin.metadata["disableCommand"]?.contains("--scope 'project'") == true)
        XCTAssertTrue(plugin.metadata["deleteCommand"]?.contains("claude plugin remove 'project-tool@test-marketplace'") == true)
        XCTAssertTrue(plugin.metadata["deleteCommand"]?.contains("--scope 'project' -y") == true)
        XCTAssertFalse(result.capabilities.contains { $0.name == "Other Project" })

        let hook = try XCTUnwrap(result.capabilities.first { $0.source.kind == "claude-plugin-hook" })
        XCTAssertEqual(hook.type, .hook)
        XCTAssertEqual(hook.pluginID, plugin.id)
        XCTAssertEqual(hook.metadata["pluginSelector"], "project-tool@test-marketplace")
        XCTAssertTrue(hook.metadata["disableCommand"]?.contains("claude plugin disable 'project-tool@test-marketplace'") == true)
        XCTAssertTrue(hook.metadata["disableCommand"]?.contains("--scope 'project'") == true)
        XCTAssertTrue(hook.metadata["deleteCommand"]?.contains("claude plugin remove 'project-tool@test-marketplace'") == true)
        XCTAssertTrue(hook.metadata["deleteCommand"]?.contains("--scope 'project' -y") == true)

        let items = CapabilityDisplayGrouper().items(for: [plugin, hook], preservesInputOrder: true)
        XCTAssertEqual(items.count, 1)
        guard case let .group(group) = items.first else {
            return XCTFail("Expected Claude plugin hook to be grouped under the real plugin")
        }
        XCTAssertEqual(group.kind, .plugin)
        XCTAssertEqual(group.representative?.id, plugin.id)
    }

    func testEnvironmentScanSkipsProjectScopedClaudePlugins() throws {
        let environmentRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("OrbitaEnvironment-\(UUID().uuidString)")
            .appendingPathComponent(".orbita/this-mac")
        let registryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("OrbitaClaudeEnvironment-\(UUID().uuidString)")
        let projectRoot = registryRoot.appendingPathComponent("Project")
        let installed = registryRoot.appendingPathComponent("installed_plugins.json")
        let settings = registryRoot.appendingPathComponent("settings.json")
        let localInstallPath = registryRoot.appendingPathComponent("cache/test-marketplace/local-tool/1.0.0")
        let userInstallPath = registryRoot.appendingPathComponent("cache/test-marketplace/user-tool/1.0.0")
        try FileManager.default.createDirectory(at: environmentRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: localInstallPath, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: userInstallPath, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: environmentRoot.deletingLastPathComponent().deletingLastPathComponent())
            try? FileManager.default.removeItem(at: registryRoot)
        }

        try """
        {
          "version": 2,
          "plugins": {
            "local-tool@test-marketplace": [
              {
                "scope": "local",
                "projectPath": "\(projectRoot.path)",
                "installPath": "\(localInstallPath.path)",
                "version": "1.0.0"
              }
            ],
            "user-tool@test-marketplace": [
              {
                "scope": "user",
                "installPath": "\(userInstallPath.path)",
                "version": "1.0.0"
              }
            ]
          }
        }
        """.write(to: installed, atomically: true, encoding: .utf8)
        try """
        {
          "enabledPlugins": {
            "local-tool@test-marketplace": true,
            "user-tool@test-marketplace": true
          }
        }
        """.write(to: settings, atomically: true, encoding: .utf8)

        let result = try CapabilityScanner().scan(
            projectRoot: environmentRoot,
            options: ScanOptions(
                includeUserScope: true,
                userSkillRoots: [],
                codexConfigURL: registryRoot.appendingPathComponent("missing-config.toml"),
                codexPluginCacheRoot: registryRoot.appendingPathComponent("missing-cache"),
                claudeInstalledPluginsURL: installed,
                claudeSettingsURLs: [settings]
            )
        )

        XCTAssertFalse(result.capabilities.contains { $0.metadata["pluginSelector"] == "local-tool@test-marketplace" })
        let userPlugin = try XCTUnwrap(result.capabilities.first { $0.metadata["pluginSelector"] == "user-tool@test-marketplace" })
        XCTAssertEqual(userPlugin.scope, .user)
        XCTAssertTrue(userPlugin.metadata["deleteCommand"]?.contains("--scope 'user' -y") == true)
    }

    func testScansClaudePluginSkillsAndCommandsAsPluginChildren() throws {
        let projectRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("OrbitaCoreTests-\(UUID().uuidString)")
        let registryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("OrbitaClaudePlugins-\(UUID().uuidString)")
        let installed = registryRoot.appendingPathComponent("installed_plugins.json")
        let settings = registryRoot.appendingPathComponent("settings.json")
        let pluginRoot = registryRoot.appendingPathComponent("cache/superpowers-marketplace/superpowers/5.0.6")
        let manifest = pluginRoot.appendingPathComponent(".claude-plugin/plugin.json")
        let skill = pluginRoot.appendingPathComponent("skills/using-superpowers/SKILL.md")
        let command = pluginRoot.appendingPathComponent("commands/brainstorm.md")
        let agent = pluginRoot.appendingPathComponent("agents/reviewer.md")
        try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: manifest.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: skill.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: command.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: agent.deletingLastPathComponent(), withIntermediateDirectories: true)
        try """
        {
          "name": "superpowers",
          "description": "Core skills library for Claude Code",
          "version": "5.0.6"
        }
        """.write(to: manifest, atomically: true, encoding: .utf8)
        try skillText(name: "using-superpowers", body: "Use Superpowers.")
            .write(to: skill, atomically: true, encoding: .utf8)
        try """
        ---
        description: Brainstorm with Superpowers
        ---

        Brainstorm the implementation.
        """.write(to: command, atomically: true, encoding: .utf8)
        try """
        ---
        name: reviewer
        description: Reviews changes with Superpowers
        tools: Read, Grep
        model: sonnet
        ---

        Review recent changes.
        """.write(to: agent, atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: registryRoot, withIntermediateDirectories: true)
        try """
        {
          "version": 2,
          "plugins": {
            "superpowers@superpowers-marketplace": [
              {
                "scope": "user",
                "installPath": "\(pluginRoot.path)",
                "version": "5.0.6"
              }
            ]
          }
        }
        """.write(to: installed, atomically: true, encoding: .utf8)
        try """
        {
          "enabledPlugins": {
            "superpowers@superpowers-marketplace": true
          }
        }
        """.write(to: settings, atomically: true, encoding: .utf8)
        defer {
            try? FileManager.default.removeItem(at: projectRoot)
            try? FileManager.default.removeItem(at: registryRoot)
        }

        let result = try CapabilityScanner().scan(
            projectRoot: projectRoot,
            options: ScanOptions(
                includeUserScope: true,
                userSkillRoots: [],
                codexConfigURL: registryRoot.appendingPathComponent("missing-config.toml"),
                codexPluginCacheRoot: registryRoot.appendingPathComponent("missing-cache"),
                claudeInstalledPluginsURL: installed,
                claudeSettingsURLs: [settings]
            )
        )

        let plugin = try XCTUnwrap(result.capabilities.first { $0.name == "Superpowers" && $0.source.kind == "claude-plugin" })
        let pluginSkill = try XCTUnwrap(result.capabilities.first { $0.name == "using-superpowers" && $0.source.kind == "claude-plugin-skill" })
        let pluginCommand = try XCTUnwrap(result.capabilities.first { $0.name == "brainstorm" && $0.source.kind == "claude-plugin-command" })
        let pluginAgent = try XCTUnwrap(result.capabilities.first { $0.name == "reviewer" && $0.source.kind == "claude-plugin-agent" })
        XCTAssertEqual(pluginSkill.pluginID, plugin.id)
        XCTAssertEqual(pluginCommand.pluginID, plugin.id)
        XCTAssertEqual(pluginAgent.pluginID, plugin.id)
        XCTAssertEqual(pluginSkill.source.packageName, "superpowers")
        XCTAssertEqual(pluginCommand.source.packageName, "superpowers")
        XCTAssertEqual(pluginAgent.source.packageName, "superpowers")
        XCTAssertEqual(pluginSkill.statuses, [.enabled])
        XCTAssertEqual(pluginCommand.statuses, [.enabled])
        XCTAssertEqual(pluginAgent.statuses, [.enabled])
        XCTAssertEqual(pluginSkill.metadata["pluginSelector"], "superpowers@superpowers-marketplace")
        XCTAssertEqual(pluginCommand.metadata["manager"], "claude-code")
        XCTAssertEqual(pluginAgent.metadata["manager"], "claude-code")
        XCTAssertTrue(pluginSkill.metadata["deleteCommand"]?.contains("claude plugin remove 'superpowers@superpowers-marketplace'") == true)
        XCTAssertTrue(pluginCommand.metadata["disableCommand"]?.contains("claude plugin disable 'superpowers@superpowers-marketplace'") == true)
        XCTAssertEqual(pluginAgent.metadata["tools"], "Read, Grep")

        let items = CapabilityDisplayGrouper().items(for: [plugin, pluginSkill, pluginCommand, pluginAgent], preservesInputOrder: true)
        XCTAssertEqual(items.count, 1)
        guard case let .group(group) = items.first else {
            return XCTFail("Expected Claude plugin children to be grouped under the real plugin")
        }
        XCTAssertEqual(group.kind, .plugin)
        XCTAssertEqual(group.representative?.id, plugin.id)
        XCTAssertEqual(group.capabilities.map(\.id).sorted(), [pluginAgent.id, pluginCommand.id, pluginSkill.id].sorted())
    }

    func testAgentsSkillsExposeSkillsCLIUpdateCommand() throws {
        let projectRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("OrbitaCoreTests-\(UUID().uuidString)")
        let userRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("OrbitaAgentsSkills-\(UUID().uuidString)")
        let skillsRoot = userRoot.appendingPathComponent(".agents/skills")
        let skill = skillsRoot.appendingPathComponent("example-skill/SKILL.md")
        let lock = userRoot.appendingPathComponent(".agents/.skill-lock.json")
        try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: skill.deletingLastPathComponent(), withIntermediateDirectories: true)
        try skillText(name: "example-skill", body: "Body")
            .write(to: skill, atomically: true, encoding: .utf8)
        try """
        {
          "version": 3,
          "skills": {
            "example-skill": {
              "source": "vercel-labs/agent-skills",
              "sourceType": "github",
              "sourceUrl": "https://github.com/vercel-labs/agent-skills.git",
              "ref": "main",
              "skillPath": "skills/example-skill/SKILL.md",
              "skillFolderHash": "abc123",
              "installedAt": "2026-01-01T00:00:00Z",
              "updatedAt": "2026-01-02T00:00:00Z"
            }
          }
        }
        """.write(to: lock, atomically: true, encoding: .utf8)
        defer {
            try? FileManager.default.removeItem(at: projectRoot)
            try? FileManager.default.removeItem(at: userRoot)
        }

        let result = try CapabilityScanner().scan(
            projectRoot: projectRoot,
            options: ScanOptions(
                includeUserScope: true,
                userSkillRoots: [skillsRoot],
                codexConfigURL: userRoot.appendingPathComponent("missing-config.toml"),
                codexPluginCacheRoot: userRoot.appendingPathComponent("missing-cache"),
                claudeInstalledPluginsURL: userRoot.appendingPathComponent("missing-claude.json"),
                claudeSettingsURLs: []
            )
        )

        let scannedSkill = try XCTUnwrap(result.capabilities.first { $0.name == "example-skill" })
        XCTAssertEqual(scannedSkill.metadata["manager"], "agents-skills")
        XCTAssertEqual(scannedSkill.statuses, [.enabled])
        XCTAssertEqual(scannedSkill.metadata["checkCommand"], "npx skills list -g")
        XCTAssertTrue(scannedSkill.metadata["updateCommand"]?.contains("npx skills update 'example-skill' -g -y") == true)
        XCTAssertEqual(scannedSkill.metadata["skillsLockSource"], "vercel-labs/agent-skills")
        XCTAssertEqual(scannedSkill.metadata["skillsLockRef"], "main")
        XCTAssertEqual(scannedSkill.metadata["skillsLockSkillPath"], "skills/example-skill/SKILL.md")
        XCTAssertEqual(scannedSkill.metadata["skillsLockHash"], "abc123")
        XCTAssertNotEqual(scannedSkill.metadata["skillsInstalledAgentIDs"]?.contains("codex"), true)
        XCTAssertNotEqual(scannedSkill.metadata["skillsInstallTargets"]?.contains("codex=canonical"), true)
        XCTAssertTrue(scannedSkill.metadata["installCommand"]?.contains("npx skills add 'https://github.com/vercel-labs/agent-skills.git' --skill 'example-skill' -g -y") == true)
    }

    func testProjectAgentsSkillReadsSkillsLockAndInstallTargets() throws {
        let projectRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("OrbitaCoreTests-\(UUID().uuidString)")
        let skillDirectory = projectRoot.appendingPathComponent(".agents/skills/review-helper")
        let claudeDirectory = projectRoot.appendingPathComponent(".claude/skills/review-helper")
        let lock = projectRoot.appendingPathComponent("skills-lock.json")
        defer { try? FileManager.default.removeItem(at: projectRoot) }

        try FileManager.default.createDirectory(at: skillDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: claudeDirectory.deletingLastPathComponent(), withIntermediateDirectories: true)
        try skillText(name: "review-helper", body: "Review helper")
            .write(to: skillDirectory.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(at: claudeDirectory, withDestinationURL: skillDirectory)
        try """
        {
          "version": 1,
          "skills": {
            "review-helper": {
              "source": "vercel-labs/agent-skills",
              "ref": "main",
              "sourceType": "github",
              "skillPath": "skills/review-helper/SKILL.md",
              "computedHash": "def456"
            }
          }
        }
        """.write(to: lock, atomically: true, encoding: .utf8)

        let result = try CapabilityScanner().scan(projectRoot: projectRoot, options: ScanOptions(includeUserScope: false))
        let scannedSkill = try XCTUnwrap(result.capabilities.first { $0.name == "review-helper" && $0.source.kind == "agents-skill" })

        XCTAssertEqual(scannedSkill.metadata["skillsLockStatus"], "locked")
        XCTAssertEqual(scannedSkill.metadata["skillsLockSource"], "vercel-labs/agent-skills")
        XCTAssertEqual(scannedSkill.metadata["skillsLockHash"], "def456")
        let canonicalPath = try XCTUnwrap(scannedSkill.metadata["skillsCanonicalPath"])
        XCTAssertEqual(
            URL(fileURLWithPath: canonicalPath).standardizedFileURL.resolvingSymlinksInPath().path,
            skillDirectory.standardizedFileURL.resolvingSymlinksInPath().path
        )
        XCTAssertTrue(scannedSkill.metadata["skillsInstalledAgentIDs"]?.contains("claude-code") == true)
        XCTAssertTrue(scannedSkill.metadata["skillsInstallTargets"]?.contains("claude-code=symlink") == true)
        XCTAssertTrue(scannedSkill.metadata["skillsInstalledAgentIDs"]?.contains("codex") == true)
        XCTAssertTrue(scannedSkill.metadata["skillsInstallTargets"]?.contains("codex=canonical") == true)
    }

    // MARK: - Agent sync (fork): executor on disk + collision/type/agent gates

    private func makeForkSourceSkill(in projectRoot: URL, name: String, extraFiles: [String: String] = [:]) throws -> Capability {
        let sourceDir = projectRoot.appendingPathComponent("lib/\(name)")
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        try skillText(name: name, body: "Body for \(name)")
            .write(to: sourceDir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        for (file, contents) in extraFiles {
            try contents.write(to: sourceDir.appendingPathComponent(file), atomically: true, encoding: .utf8)
        }
        let skillMd = sourceDir.appendingPathComponent("SKILL.md")
        return Capability(
            id: "skill:\(skillMd.path)",
            name: name,
            type: .skill,
            scope: .project,
            source: CapabilitySource(kind: "skill", path: skillMd.path)
        )
    }

    func testSyncSymlinkPlanExecutorLinksOnDiskResolvingToSource() throws {
        let projectRoot = FileManager.default.temporaryDirectory.appendingPathComponent("OrbitaSyncExec-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: projectRoot) }
        let skill = try makeForkSourceSkill(in: projectRoot, name: "foo")
        let graph = CapabilityGraph(projectRoot: projectRoot.path, capabilities: [skill], issues: [])

        let plan = try ApplyPlanBuilder().planSyncInstallTarget(
            capabilityID: skill.id, agentID: "claude-code", graph: graph, mode: .symlink, destinationScope: .project
        )
        _ = try ApplyPlanExecutor().apply(plan)

        let destination = projectRoot.appendingPathComponent(".claude/skills/foo")
        XCTAssertNotNil(try? FileManager.default.destinationOfSymbolicLink(atPath: destination.path), "fork should create a symlink on disk")
        XCTAssertEqual(
            destination.resolvingSymlinksInPath().path,
            projectRoot.appendingPathComponent("lib/foo").resolvingSymlinksInPath().path,
            "the on-disk symlink must resolve back to the canonical source"
        )
    }

    func testSyncCopyPlanExecutorCopiesDirectoryOnDisk() throws {
        let projectRoot = FileManager.default.temporaryDirectory.appendingPathComponent("OrbitaSyncExec-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: projectRoot) }
        let skill = try makeForkSourceSkill(in: projectRoot, name: "foo")
        let graph = CapabilityGraph(projectRoot: projectRoot.path, capabilities: [skill], issues: [])

        let plan = try ApplyPlanBuilder().planSyncInstallTarget(
            capabilityID: skill.id, agentID: "claude-code", graph: graph, mode: .copy, destinationScope: .project
        )
        _ = try ApplyPlanExecutor().apply(plan)

        let destination = projectRoot.appendingPathComponent(".claude/skills/foo")
        XCTAssertNil(try? FileManager.default.destinationOfSymbolicLink(atPath: destination.path), "a copy fork must not be a symlink")
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.appendingPathComponent("SKILL.md").path), "the copied skill directory must contain SKILL.md")
    }

    func testReSyncRefreshesDivergedCopyAndBacksUpOldCopy() throws {
        let projectRoot = FileManager.default.temporaryDirectory.appendingPathComponent("OrbitaReSyncExec-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: projectRoot) }
        let skill = try makeForkSourceSkill(in: projectRoot, name: "foo")
        let graph = CapabilityGraph(projectRoot: projectRoot.path, capabilities: [skill], issues: [])

        // Initial copy fork into Claude's project skills dir.
        let syncPlan = try ApplyPlanBuilder().planSyncInstallTarget(
            capabilityID: skill.id, agentID: "claude-code", graph: graph, mode: .copy, destinationScope: .project
        )
        _ = try ApplyPlanExecutor().apply(syncPlan)

        // Simulate divergence: the source changed AND the copy was hand-edited.
        let destination = projectRoot.appendingPathComponent(".claude/skills/foo")
        try "Body for foo (UPDATED)".write(to: projectRoot.appendingPathComponent("lib/foo/SKILL.md"), atomically: true, encoding: .utf8)
        let handEdit = destination.appendingPathComponent("HANDEDIT.txt")
        try "local edit".write(to: handEdit, atomically: true, encoding: .utf8)

        // Re-sync: refresh the copy from source, backing up the diverged copy first.
        let resyncPlan = try ApplyPlanBuilder().planReSyncInstallTarget(
            capabilityID: skill.id, agentID: "claude-code", graph: graph, destinationScope: .project
        )
        XCTAssertTrue(resyncPlan.requiresConfirmation, "overwriting an existing on-disk copy should require confirmation")
        _ = try ApplyPlanExecutor().apply(resyncPlan)

        // The fresh copy reflects the new source and no longer carries the local edit.
        let refreshed = try String(contentsOf: destination.appendingPathComponent("SKILL.md"), encoding: .utf8)
        XCTAssertTrue(refreshed.contains("UPDATED"), "the re-synced copy must reflect the updated source")
        XCTAssertFalse(FileManager.default.fileExists(atPath: handEdit.path), "the stale copy's local edit must not survive the refresh")

        // The diverged copy (incl. the local edit) is preserved in the scope-correct fork-backup store.
        let backupRoot = projectRoot.appendingPathComponent(".orbita/fork-backups")
        let entries = (try? FileManager.default.contentsOfDirectory(atPath: backupRoot.path)) ?? []
        let fooBackup = entries.first { $0.hasSuffix("__foo") }
        XCTAssertNotNil(fooBackup, "a fork-backup entry should be created for the diverged copy")
        if let fooBackup {
            let backedUpEdit = backupRoot.appendingPathComponent(fooBackup).appendingPathComponent("HANDEDIT.txt")
            XCTAssertTrue(FileManager.default.fileExists(atPath: backedUpEdit.path), "the backup must preserve the diverged copy's local edit")
        }
    }

    func testReSyncRefusesWhenNoExistingCopy() throws {
        let projectRoot = FileManager.default.temporaryDirectory.appendingPathComponent("OrbitaReSyncExec-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: projectRoot) }
        let skill = try makeForkSourceSkill(in: projectRoot, name: "foo")
        let graph = CapabilityGraph(projectRoot: projectRoot.path, capabilities: [skill], issues: [])
        XCTAssertThrowsError(try ApplyPlanBuilder().planReSyncInstallTarget(
            capabilityID: skill.id, agentID: "claude-code", graph: graph, destinationScope: .project
        )) { error in
            XCTAssertTrue("\(error)".contains("no existing copy to re-sync"))
        }
    }

    func testReSyncSkipsLiveSymlinkToSource() throws {
        let projectRoot = FileManager.default.temporaryDirectory.appendingPathComponent("OrbitaReSyncExec-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: projectRoot) }
        let skill = try makeForkSourceSkill(in: projectRoot, name: "foo")
        let destination = projectRoot.appendingPathComponent(".claude/skills/foo")
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: destination.path, withDestinationPath: projectRoot.appendingPathComponent("lib/foo").path)
        let graph = CapabilityGraph(projectRoot: projectRoot.path, capabilities: [skill], issues: [])
        XCTAssertThrowsError(try ApplyPlanBuilder().planReSyncInstallTarget(
            capabilityID: skill.id, agentID: "claude-code", graph: graph, destinationScope: .project
        )) { error in
            XCTAssertTrue("\(error)".contains("Nothing to re-sync"), "a live symlink already tracks the source, so there is nothing to refresh")
        }
    }

    func testReSyncMidPlanFailureRestoresForkFromBackup() throws {
        let projectRoot = FileManager.default.temporaryDirectory.appendingPathComponent("OrbitaReSyncFail-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: projectRoot) }
        let skill = try makeForkSourceSkill(in: projectRoot, name: "foo")
        let graph = CapabilityGraph(projectRoot: projectRoot.path, capabilities: [skill], issues: [])

        // Fork (copy) into Claude, then diverge the copy.
        _ = try ApplyPlanExecutor().apply(try ApplyPlanBuilder().planSyncInstallTarget(
            capabilityID: skill.id, agentID: "claude-code", graph: graph, mode: .copy, destinationScope: .project))
        let destination = projectRoot.appendingPathComponent(".claude/skills/foo")
        try "diverged".write(to: destination.appendingPathComponent("MARK.txt"), atomically: true, encoding: .utf8)

        // Build the re-sync plan while the source still exists, then make the refresh copy fail by
        // removing the source before applying — so .backupPath succeeds (copy moved aside) but the
        // subsequent .copyPath throws.
        let plan = try ApplyPlanBuilder().planReSyncInstallTarget(
            capabilityID: skill.id, agentID: "claude-code", graph: graph, destinationScope: .project)
        try FileManager.default.removeItem(at: projectRoot.appendingPathComponent("lib/foo"))

        XCTAssertThrowsError(try ApplyPlanExecutor().apply(plan)) { error in
            XCTAssertTrue("\(error)".contains("Source does not exist"))
        }

        // Compensation must restore the diverged fork from its backup rather than strand the agent dir.
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.appendingPathComponent("SKILL.md").path),
                      "a mid-plan failure must restore the fork from its backup")
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.appendingPathComponent("MARK.txt").path),
                      "the restored fork must be the original diverged copy, recovered intact")
        // The recovery move consumes the backup, leaving no orphan in the fork-backup store.
        let backupRoot = projectRoot.appendingPathComponent(".orbita/fork-backups")
        let leftovers = (try? FileManager.default.contentsOfDirectory(atPath: backupRoot.path)) ?? []
        XCTAssertTrue(leftovers.filter { $0.hasSuffix("__foo") }.isEmpty, "recovery should consume the backup, leaving no orphan")
    }

    func testSyncPlanExecutorRejectsDestinationOutsideAgentStorage() throws {
        let projectRoot = FileManager.default.temporaryDirectory.appendingPathComponent("OrbitaSyncExec-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: projectRoot) }

        let plan = ApplyPlan(
            projectRoot: projectRoot.path,
            action: .enable,
            capabilityID: "x",
            requiresConfirmation: false,
            operations: [
                ApplyOperation(
                    kind: .createSymlink,
                    path: projectRoot.appendingPathComponent("outside/foo").path,
                    target: projectRoot.appendingPathComponent("lib/foo").path,
                    risk: .write,
                    description: "Out-of-boundary symlink"
                )
            ]
        )
        XCTAssertThrowsError(try ApplyPlanExecutor().apply(plan)) { error in
            XCTAssertTrue("\(error)".contains("outside known agent storage"))
        }
    }

    func testSyncCopyPlannerRefusesPreexistingForeignDestination() throws {
        let projectRoot = FileManager.default.temporaryDirectory.appendingPathComponent("OrbitaSyncExec-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: projectRoot) }
        let skill = try makeForkSourceSkill(in: projectRoot, name: "foo")
        let foreign = projectRoot.appendingPathComponent(".claude/skills/foo")
        try FileManager.default.createDirectory(at: foreign, withIntermediateDirectories: true)
        try "not the same skill".write(to: foreign.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        let graph = CapabilityGraph(projectRoot: projectRoot.path, capabilities: [skill], issues: [])

        XCTAssertThrowsError(try ApplyPlanBuilder().planSyncInstallTarget(
            capabilityID: skill.id, agentID: "claude-code", graph: graph, mode: .copy, destinationScope: .project
        )) { error in
            XCTAssertTrue("\(error)".contains("Target already exists"))
        }
    }

    func testSyncSymlinkIsIdempotentForExistingSameSourceLink() throws {
        let projectRoot = FileManager.default.temporaryDirectory.appendingPathComponent("OrbitaSyncExec-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: projectRoot) }
        let skill = try makeForkSourceSkill(in: projectRoot, name: "foo")
        let destination = projectRoot.appendingPathComponent(".claude/skills/foo")
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: destination.path, withDestinationPath: projectRoot.appendingPathComponent("lib/foo").path)
        let graph = CapabilityGraph(projectRoot: projectRoot.path, capabilities: [skill], issues: [])

        XCTAssertThrowsError(try ApplyPlanBuilder().planSyncInstallTarget(
            capabilityID: skill.id, agentID: "claude-code", graph: graph, mode: .symlink, destinationScope: .project
        )) { error in
            XCTAssertTrue("\(error)".contains("already has this"), "re-syncing an identical link should be a no-op, not a clobber")
        }
    }

    func testSyncSymlinkPlannerRefusesForeignFileAtDestination() throws {
        let projectRoot = FileManager.default.temporaryDirectory.appendingPathComponent("OrbitaSyncExec-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: projectRoot) }
        let skill = try makeForkSourceSkill(in: projectRoot, name: "foo")
        let destination = projectRoot.appendingPathComponent(".claude/skills/foo")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let graph = CapabilityGraph(projectRoot: projectRoot.path, capabilities: [skill], issues: [])

        XCTAssertThrowsError(try ApplyPlanBuilder().planSyncInstallTarget(
            capabilityID: skill.id, agentID: "claude-code", graph: graph, mode: .symlink, destinationScope: .project
        )) { error in
            XCTAssertTrue("\(error)".contains("Target already exists"))
        }
    }

    func testSyncRejectsIncompatibleTypesAndAgents() throws {
        let projectRoot = FileManager.default.temporaryDirectory.appendingPathComponent("OrbitaSyncExec-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: projectRoot) }
        let skill = try makeForkSourceSkill(in: projectRoot, name: "foo")
        let hook = Capability(id: "hook:h", name: "h", type: .hook, scope: .project,
                              source: CapabilitySource(kind: "claude-settings", path: "/tmp/x/.claude/settings.json"))
        let tomlCommand = Capability(id: "command:c", name: "c", type: .command, scope: .project,
                                     source: CapabilitySource(kind: "codex-command", path: "/tmp/x/.codex/commands/c.toml"))
        let mdCommand = Capability(id: "command:m", name: "m", type: .command, scope: .project,
                                   source: CapabilitySource(kind: "claude-command", path: "/tmp/x/.claude/commands/m.md"))
        let graph = CapabilityGraph(projectRoot: projectRoot.path, capabilities: [skill, hook, tomlCommand, mdCommand], issues: [])
        let builder = ApplyPlanBuilder()

        // hook is not a syncable type at all
        XCTAssertThrowsError(try builder.planSyncInstallTarget(capabilityID: hook.id, agentID: "claude-code", graph: graph, mode: .symlink, destinationScope: .project))
        // a .toml command cannot be loaded by Claude Code
        XCTAssertThrowsError(try builder.planSyncInstallTarget(capabilityID: tomlCommand.id, agentID: "claude-code", graph: graph, mode: .symlink, destinationScope: .project)) { error in
            XCTAssertTrue("\(error)".contains("cannot directly load"))
        }
        // commands cannot be forked into cursor at all
        XCTAssertThrowsError(try builder.planSyncInstallTarget(capabilityID: mdCommand.id, agentID: "cursor", graph: graph, mode: .symlink, destinationScope: .project)) { error in
            XCTAssertTrue("\(error)".contains("cannot directly load"))
        }
        // an unknown agent id is rejected outright
        XCTAssertThrowsError(try builder.planSyncInstallTarget(capabilityID: skill.id, agentID: "nope", graph: graph, mode: .symlink, destinationScope: .project)) { error in
            XCTAssertTrue("\(error)".contains("Unknown Skills CLI agent"))
        }
    }

    func testCommandForkReverseDeleteGivesActionableOneWayError() throws {
        let projectRoot = FileManager.default.temporaryDirectory.appendingPathComponent("OrbitaSyncExec-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: projectRoot) }
        let command = Capability(id: "command:c", name: "c", type: .command, scope: .project,
                                 source: CapabilitySource(kind: "codex-command", path: "/tmp/x/.codex/commands/c.md"))
        let graph = CapabilityGraph(projectRoot: projectRoot.path, capabilities: [command], issues: [])
        XCTAssertThrowsError(try ApplyPlanBuilder().planDeleteSkillInstallTarget(capabilityID: command.id, agentID: "codex", graph: graph)) { error in
            XCTAssertTrue("\(error)".contains("one-way"))
        }
    }

    // MARK: - Scanner fixes

    func testBrokenSkillSymlinkIsReportedForNonAgentsRoots() throws {
        let projectRoot = FileManager.default.temporaryDirectory.appendingPathComponent("OrbitaBrokenFork-\(UUID().uuidString)")
        let skillsRoot = projectRoot.appendingPathComponent(".trae/skills")
        try FileManager.default.createDirectory(at: skillsRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: projectRoot) }
        try FileManager.default.createSymbolicLink(
            atPath: skillsRoot.appendingPathComponent("ghost").path,
            withDestinationPath: projectRoot.appendingPathComponent("does-not-exist/ghost").path
        )

        let scan = try CapabilityScanner().scan(projectRoot: projectRoot, options: ScanOptions(includeUserScope: false, userSkillRoots: []))
        let broken = scan.capabilities.first { $0.name == "ghost" }
        XCTAssertNotNil(broken, "a dangling skill symlink in .trae/skills should be surfaced")
        XCTAssertEqual(broken?.statuses, [.broken])
        XCTAssertEqual(broken?.source.kind, "trae-symlink")
    }

    func testCodexSkillStateParsesTrailingComment() throws {
        let projectRoot = FileManager.default.temporaryDirectory.appendingPathComponent("OrbitaTomlComment-\(UUID().uuidString)")
        let configRoot = FileManager.default.temporaryDirectory.appendingPathComponent("OrbitaTomlConfig-\(UUID().uuidString)")
        let skill = projectRoot.appendingPathComponent(".agents/skills/review-helper/SKILL.md")
        let config = configRoot.appendingPathComponent("config.toml")
        defer {
            try? FileManager.default.removeItem(at: projectRoot)
            try? FileManager.default.removeItem(at: configRoot)
        }
        try FileManager.default.createDirectory(at: skill.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: configRoot, withIntermediateDirectories: true)
        try skillText(name: "review-helper", body: "Review.").write(to: skill, atomically: true, encoding: .utf8)
        try """
        [[skills.config]]
        path = "\(skill.path)"
        enabled = false # turned off while iterating
        """.write(to: config, atomically: true, encoding: .utf8)

        let scan = try CapabilityScanner().scan(
            projectRoot: projectRoot,
            options: ScanOptions(includeUserScope: false, userSkillRoots: [], codexConfigURL: config)
        )
        let graph = CapabilityResolver().resolve(scanResult: scan)
        let capability = try XCTUnwrap(graph.capabilities.first { $0.name == "review-helper" && $0.source.kind == "agents-skill" })
        XCTAssertEqual(capability.metadata["codexSkillEnabled"], "false", "enabled = false # comment must parse as false, not fall back to default")
    }

    func testUnrelatedSameNameSkillsFromDifferentPackagesAreNotFlagged() throws {
        let a = Capability(
            id: "skill:a", name: "helper", type: .skill, scope: .project,
            source: CapabilitySource(kind: "skill", path: "/tmp/pkgA/skills/helper/SKILL.md", packageName: "pkgA"),
            pluginID: "plugin:pkga", metadata: ["contentHash": "aaaa"]
        )
        let b = Capability(
            id: "skill:b", name: "helper", type: .skill, scope: .project,
            source: CapabilitySource(kind: "skill", path: "/tmp/pkgB/skills/helper/SKILL.md", packageName: "pkgB"),
            pluginID: "plugin:pkgb", metadata: ["contentHash": "bbbb"]
        )
        let graph = CapabilityResolver().resolve(scanResult: ScanResult(projectRoot: "/tmp", capabilities: [a, b], issues: []))
        for cap in graph.capabilities where cap.name == "helper" && cap.type == .skill {
            XCTAssertFalse(cap.statuses.contains(.duplicate), "coincidental same-name skills from different packages must not be flagged duplicate")
            XCTAssertFalse(cap.statuses.contains(.drifted), "…nor drifted")
        }
    }

    func testCopyForkDriftDetectedViaWholeDirectoryHash() throws {
        let projectRoot = FileManager.default.temporaryDirectory.appendingPathComponent("OrbitaDirHash-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: projectRoot) }
        // Same SKILL.md in both copies, but a bundled script diverges. SKILL.md-only hashing would call
        // these a clean copied-mirror; whole-directory hashing must flag drift.
        _ = try makeDirSkill(in: projectRoot, subdir: "a", name: "helper", script: "echo v1")
        _ = try makeDirSkill(in: projectRoot, subdir: "b", name: "helper", script: "echo v2")

        let scan = try CapabilityScanner().scan(projectRoot: projectRoot, options: ScanOptions(includeUserScope: false, userSkillRoots: []))
        let graph = CapabilityResolver().resolve(scanResult: scan)
        let helpers = graph.capabilities.filter { $0.name == "helper" && $0.type == .skill }
        XCTAssertEqual(helpers.count, 2)
        XCTAssertTrue(helpers.contains { $0.statuses.contains(.drifted) }, "copies diverging only in a bundled file must be detected as drifted")
    }

    private func makeDirSkill(in projectRoot: URL, subdir: String, name: String, script: String) throws -> URL {
        let dir = projectRoot.appendingPathComponent("\(subdir)/\(name)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try skillText(name: name, body: "Shared body.").write(to: dir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        try script.write(to: dir.appendingPathComponent("run.sh"), atomically: true, encoding: .utf8)
        return dir
    }

    func testOversizedBundledSkillAssetDoesNotReadBytesAndEmitsWarning() throws {
        // MED-2: a hostile repo ships a skill whose bundled asset is larger than the hash cap. The scanner
        // must NOT read the whole file (no OOM), must still surface the skill with a valid contentHash, and
        // must emit a warning ScanIssue for the capped file.
        let projectRoot = FileManager.default.temporaryDirectory.appendingPathComponent("OrbitaBigAsset-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: projectRoot) }
        let skillDir = projectRoot.appendingPathComponent(".agents/skills/huge")
        try FileManager.default.createDirectory(at: skillDir, withIntermediateDirectories: true)
        try skillText(name: "huge", body: "Has a giant asset.").write(to: skillDir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)

        // Sparse 60 MB asset (> the 50 MB hash cap) without allocating 60 MB of RAM in the test.
        let assetURL = skillDir.appendingPathComponent("asset.bin")
        FileManager.default.createFile(atPath: assetURL.path, contents: nil)
        let handle = try FileHandle(forWritingTo: assetURL)
        try handle.truncate(atOffset: 60 * 1024 * 1024)
        try handle.close()

        let scan = try CapabilityScanner().scan(projectRoot: projectRoot, options: ScanOptions(includeUserScope: false, userSkillRoots: []))
        let skill = try XCTUnwrap(scan.capabilities.first { $0.name == "huge" && $0.type == .skill })
        let hash = try XCTUnwrap(skill.metadata["contentHash"])
        XCTAssertEqual(hash.count, 64, "directory hash must still be a valid SHA256 even with an over-cap asset")
        XCTAssertTrue(hash.allSatisfy(\.isHexDigit))
        // The scanner canonicalizes the project root (resolving /var -> /private/var), so compare on suffix.
        XCTAssertTrue(
            scan.issues.contains { $0.severity == .warning && $0.path.hasSuffix("huge/asset.bin") && $0.message.contains("size limit") },
            "an over-cap bundled asset must produce a warning ScanIssue"
        )
    }

    func testOversizedMcpConfigEmitsWarningInsteadOfReadingWholeFile() throws {
        // A hostile .mcp.json larger than the config cap must be skipped with a warning, not read whole.
        let projectRoot = FileManager.default.temporaryDirectory.appendingPathComponent("OrbitaBigMcp-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: projectRoot) }
        try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)
        let mcpURL = projectRoot.appendingPathComponent(".mcp.json")
        FileManager.default.createFile(atPath: mcpURL.path, contents: Data("{}".utf8))
        let handle = try FileHandle(forWritingTo: mcpURL)
        try handle.truncate(atOffset: 10 * 1024 * 1024) // > 8 MB config cap
        try handle.close()

        let scan = try CapabilityScanner().scan(projectRoot: projectRoot, options: ScanOptions(includeUserScope: false, userSkillRoots: []))
        XCTAssertTrue(
            scan.issues.contains { $0.severity == .warning && $0.path == mcpURL.path },
            "an over-cap .mcp.json must surface a warning ScanIssue"
        )
        XCTAssertFalse(
            scan.capabilities.contains { $0.source.path == mcpURL.path },
            "no MCP capabilities should be emitted from an unread oversized config"
        )
    }

    private func fixtureURL(_ name: String) throws -> URL {
        #if SWIFT_PACKAGE
        return Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures")!
        #else
        throw XCTSkip("Fixtures require Swift Package resources")
        #endif
    }

    private func scanProjectOnly(_ root: URL) throws -> ScanResult {
        try CapabilityScanner().scan(projectRoot: root, options: ScanOptions(includeUserScope: false))
    }

    func testRestoreRejectsProjectStoreEntryTargetingInRepoNonAgentPath() throws {
        // #1 (security): the project-store restore branch was tightened from "anywhere under the repo" to
        // "the project's own agent dirs only". A hostile repo commits a <repo>/.orbita/disabled entry whose
        // attacker-controlled sidecar originalSourcePath points at <repo>/.git/hooks/pre-commit; clicking
        // Enable must be REJECTED, so the restore can't plant an executable git hook (the no-clobber rule
        // blocks overwrites, but not the creation of a new file).
        let fm = FileManager.default
        let temporaryRoot = fm.temporaryDirectory.appendingPathComponent("OrbitaCoreTests-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: temporaryRoot) }
        let projectRoot = temporaryRoot.appendingPathComponent("project")
        let fakeHome = temporaryRoot.appendingPathComponent("home")
        try fm.createDirectory(at: projectRoot, withIntermediateDirectories: true)
        try fm.createDirectory(at: fakeHome, withIntermediateDirectories: true)

        let evilTarget = projectRoot.appendingPathComponent(".git/hooks/pre-commit").path
        let entryDir = projectRoot.appendingPathComponent(".orbita/disabled/skill/attackerkey")
        try fm.createDirectory(at: entryDir, withIntermediateDirectories: true)
        try "#!/bin/sh\necho pwned\n".write(to: entryDir.appendingPathComponent("pre-commit"), atomically: true, encoding: .utf8)
        try OrbitaDisabledStore.sidecarJSON(
            capabilityID: "skill:evil-hook",
            name: "pre-commit",
            type: "skill",
            originalSourcePath: evilTarget,
            scope: "project"
        ).write(to: entryDir.appendingPathComponent(".orbita-restore.json"), atomically: true, encoding: .utf8)

        let graph = CapabilityResolver().resolve(scanResult: try CapabilityScanner().scan(
            projectRoot: projectRoot, options: ScanOptions(includeUserScope: false)))
        let tile = try XCTUnwrap(graph.capabilities.first { $0.id == "skill:evil-hook" })

        let builder = ApplyPlanBuilder(homeDirectory: fakeHome)
        let plan = try builder.planEnable(capabilityID: tile.id, graph: graph)
        let executor = ApplyPlanExecutor(homeDirectory: fakeHome)
        XCTAssertThrowsError(try executor.apply(plan)) { error in
            let message = (error as? ApplyExecutionError)?.message ?? "\(error)"
            XCTAssertTrue(message.contains("outside project agent storage"),
                          "expected a project-agent-storage rejection, got: \(message)")
        }
        XCTAssertFalse(fm.fileExists(atPath: evilTarget),
                       "the planted hook must NOT have been written into .git/hooks")
    }

    func testGroupedDisableRollbackInvertsAllMembers() throws {
        // #2: a grouped enable/disable now records its member ids in apply.log, so rollback inverts the WHOLE
        // group instead of failing to resolve the synthetic group id (the old behavior threw capabilityNotFound).
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("OrbitaCoreTests-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: root) }
        for name in ["alpha", "beta"] {
            let dir = root.appendingPathComponent(".trae/skills/\(name)")
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            try skillText(name: name, body: "b").write(to: dir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        }
        let graph = CapabilityResolver().resolve(scanResult: try scanProjectOnly(root))
        let alpha = try XCTUnwrap(graph.capabilities.first { $0.name == "alpha" })
        let beta = try XCTUnwrap(graph.capabilities.first { $0.name == "beta" })

        let builder = ApplyPlanBuilder()
        let disable = try builder.planDisable(capabilityIDs: [alpha.id, beta.id], groupID: "g", groupName: "Group", graph: graph)
        _ = try ApplyPlanExecutor().apply(disable)

        let rollback = try builder.planRollback(graph: graph)
        XCTAssertEqual(rollback.action, .rollback)
        let affected = Set(rollback.affectedCapabilityIDs ?? [])
        XCTAssertTrue(affected.contains(alpha.id) && affected.contains(beta.id),
                      "grouped rollback must invert every member, got \(affected)")
    }

    func testStoreEscapeTargetsAreRejected() throws {
        // #17: defense-in-depth negative tests for the cachePath/backupPath target guards (symmetric with the
        // restorePath scope-binding test). A hand-built op whose target escapes its store must be rejected.
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("OrbitaCoreTests-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: root) }
        let project = root.appendingPathComponent("project")
        let source = project.appendingPathComponent(".trae/skills/foo")
        try fm.createDirectory(at: source, withIntermediateDirectories: true)
        try "x".write(to: source.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)

        let cacheEvil = root.appendingPathComponent("evil/cache").path
        let cachePlan = ApplyPlan(projectRoot: project.path, action: .disable, capabilityID: "skill:foo",
                                  requiresConfirmation: true,
                                  operations: [ApplyOperation(kind: .cachePath, path: source.path, target: cacheEvil, risk: .write, description: "evil cache")])
        XCTAssertThrowsError(try ApplyPlanExecutor().apply(cachePlan)) { error in
            XCTAssertTrue(((error as? ApplyExecutionError)?.message ?? "\(error)").contains("outside .orbita/disabled"))
        }
        XCTAssertFalse(fm.fileExists(atPath: cacheEvil))

        let backupEvil = root.appendingPathComponent("evil/backup").path
        let backupPlan = ApplyPlan(projectRoot: project.path, action: .enable, capabilityID: "skill:foo",
                                   requiresConfirmation: true,
                                   operations: [ApplyOperation(kind: .backupPath, path: source.path, target: backupEvil, risk: .write, description: "evil backup")])
        XCTAssertThrowsError(try ApplyPlanExecutor().apply(backupPlan)) { error in
            XCTAssertTrue(((error as? ApplyExecutionError)?.message ?? "\(error)").contains("outside .orbita/fork-backups"))
        }
        XCTAssertFalse(fm.fileExists(atPath: backupEvil))
    }

    func testClaudeHooksFlattenMultipleMatchersAndHandlersWithDistinctKeys() throws {
        // #6: with one event carrying TWO matcher groups (one holding TWO handlers), the scanner must emit
        // THREE distinct hook capabilities with the correct entryIndex:hookIndex — so the App's index-based
        // deleteHook removes the right handler. The whole fixture set previously only had single-handler hooks.
        let projectRoot = FileManager.default.temporaryDirectory.appendingPathComponent("OrbitaCoreTests-\(UUID().uuidString)")
        let claudeRoot = FileManager.default.temporaryDirectory.appendingPathComponent("OrbitaClaudeMulti-\(UUID().uuidString)")
        let settings = claudeRoot.appendingPathComponent("settings.json")
        try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: claudeRoot, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: projectRoot)
            try? FileManager.default.removeItem(at: claudeRoot)
        }
        let settingsObject: [String: Any] = [
            "hooks": [
                "PostToolUse": [
                    ["matcher": "Write", "hooks": [
                        ["type": "command", "command": "echo a"],
                        ["type": "command", "command": "echo b"]
                    ]],
                    ["matcher": "Edit", "hooks": [
                        ["type": "command", "command": "echo c"]
                    ]]
                ]
            ]
        ]
        try JSONSerialization.data(withJSONObject: settingsObject, options: [.prettyPrinted, .sortedKeys]).write(to: settings)

        let result = try CapabilityScanner().scan(
            projectRoot: projectRoot,
            options: ScanOptions(includeUserScope: true, userSkillRoots: [],
                                 codexConfigURL: claudeRoot.appendingPathComponent("missing.toml"),
                                 codexPluginCacheRoot: claudeRoot.appendingPathComponent("missing-cache"),
                                 claudeInstalledPluginsURL: claudeRoot.appendingPathComponent("missing.json"),
                                 claudeSettingsURLs: [settings]))

        let hooks = result.capabilities.filter { $0.source.kind == "claude-settings-hook" }
        XCTAssertEqual(hooks.count, 3, "two matcher groups (2 + 1 handlers) must flatten to three distinct hooks")
        XCTAssertEqual(Set(hooks.map(\.id)).count, 3, "each flattened hook must have a distinct capability id")
        let indexPairs = Set(hooks.map { "\($0.metadata["entryIndex"] ?? "?"):\($0.metadata["hookIndex"] ?? "?")" })
        XCTAssertEqual(indexPairs, ["0:0", "0:1", "1:0"], "got \(indexPairs)")
        // The second handler of the first group must carry 0:1 in its delete command (not 0:0).
        let secondHandler = try XCTUnwrap(hooks.first { $0.metadata["command"] == "echo b" })
        XCTAssertTrue(secondHandler.metadata["claudeHookDeleteCommand"]?.contains("0:1") == true,
                      "got: \(secondHandler.metadata["claudeHookDeleteCommand"] ?? "nil")")
    }

    func testTraeSkillDoesNotLeakIntoTraeCNView() throws {
        // #20: companion to testTraeCNScansOwnDirAndIsDistinctFromTrae — the REVERSE direction. Because
        // ".trae" is a string prefix of ".traecn", a prefix-based match would leak a Trae skill into Trae CN.
        let projectRoot = FileManager.default.temporaryDirectory.appendingPathComponent("OrbitaTrae-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: projectRoot) }
        let skillDir = projectRoot.appendingPathComponent(".trae/skills/trae-only")
        try FileManager.default.createDirectory(at: skillDir, withIntermediateDirectories: true)
        try skillText(name: "trae-only", body: "Trae only")
            .write(to: skillDir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)

        let graph = CapabilityResolver().resolve(scanResult: try scanProjectOnly(projectRoot))
        let resolver = AgentViewResolver()
        XCTAssertTrue(resolver.visibleCapabilities(for: .trae, graph: graph).map(\.name).contains("trae-only"))
        XCTAssertFalse(resolver.visibleCapabilities(for: .traeCN, graph: graph).map(\.name).contains("trae-only"),
                       "a .trae skill must not appear in Trae CN's view")
    }

    private func skillText(name: String, body: String) -> String {
        """
        ---
        name: \(name)
        description: test skill
        ---

        \(body)
        """
    }

    private func agentText(name: String, description: String, tools: String) -> String {
        """
        ---
        name: \(name)
        description: \(description)
        tools: \(tools)
        model: sonnet
        ---

        \(description)
        """
    }
}

private func displayCapability(
    name: String,
    type: CapabilityType = .skill,
    pluginID: String? = nil,
    packageName: String? = nil
) -> Capability {
    Capability(
        id: "skill:\(name)",
        name: name,
        type: type,
        scope: .project,
        source: CapabilitySource(kind: "skill", path: "/tmp/\(name)/SKILL.md", packageName: packageName),
        pluginID: pluginID
    )
}

private func mirroredDisplayCapability(name: String, sourceKind: String, path: String, hash: String) -> Capability {
    Capability(
        id: "skill:\(sourceKind):\(name)",
        name: name,
        type: .skill,
        scope: .user,
        source: CapabilitySource(kind: sourceKind, path: path),
        metadata: ["contentHash": hash]
    )
}

private final class ScanProgressRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storedEvents: [ScanProgressEvent] = []

    var events: [ScanProgressEvent] {
        lock.lock()
        defer { lock.unlock() }
        return storedEvents
    }

    func append(_ event: ScanProgressEvent) {
        lock.lock()
        defer { lock.unlock() }
        storedEvents.append(event)
    }
}
