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

        loaded.remove(projectPath: projectB.path)
        try store.save(loaded)
        let reloaded = try store.load()

        XCTAssertEqual(reloaded.projects.map(\.name), [projectA.lastPathComponent])
        XCTAssertEqual(reloaded.lastProjectPath, projectA.standardizedFileURL.resolvingSymlinksInPath().path)
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
        XCTAssertTrue(claudeHook?.risks.contains(.exec) == true)
    }

    func testClaudeCodeSeesNativeAndSharedAgentsSkills() throws {
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("OrbitaCoreTests-\(UUID().uuidString)")
        let nativeClaudeSkill = temporaryRoot.appendingPathComponent(".claude/skills/review-helper/SKILL.md")
        let sharedAgentsSkill = temporaryRoot.appendingPathComponent(".agents/skills/shared-doc/SKILL.md")

        try FileManager.default.createDirectory(at: nativeClaudeSkill.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: sharedAgentsSkill.deletingLastPathComponent(), withIntermediateDirectories: true)
        try skillText(name: "review-helper", body: "Claude native helper").write(to: nativeClaudeSkill, atomically: true, encoding: .utf8)
        try skillText(name: "shared-doc", body: "Shared agent skill").write(to: sharedAgentsSkill, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }

        let graph = CapabilityResolver().resolve(scanResult: try scanProjectOnly(temporaryRoot))
        let claude = AgentViewResolver().view(for: .claudeCode, graph: graph)
        let codex = AgentViewResolver().view(for: .codex, graph: graph)

        XCTAssertTrue(claude.visibleCapabilities.contains { $0.name == "review-helper" && $0.source.kind == "claude-skill" })
        XCTAssertTrue(claude.visibleCapabilities.contains { $0.name == "shared-doc" && $0.source.kind == "agents-skill" })
        XCTAssertTrue(codex.visibleCapabilities.contains { $0.name == "shared-doc" && $0.source.kind == "agents-skill" })
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
        XCTAssertTrue(skill.metadata["checkCommand"]?.contains("codex plugin marketplace upgrade 'openai-curated'") == true)
        XCTAssertTrue(skill.metadata["updateCommand"]?.contains("codex plugin add 'superpowers@openai-curated'") == true)
        XCTAssertTrue(skill.metadata["deleteCommand"]?.contains("codex plugin remove 'superpowers@openai-curated'") == true)
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

    func testAgentViewFiltersCodexVisibleCapabilities() throws {
        let root = try fixtureURL("MixedProject")
        let scan = try scanProjectOnly(root)
        let graph = CapabilityResolver().resolve(scanResult: scan)

        let view = AgentViewResolver().view(for: .codex, graph: graph)

        XCTAssertTrue(view.visibleCapabilities.contains { $0.type == .skill })
        XCTAssertTrue(view.visibleCapabilities.contains { $0.type == .plugin })
        XCTAssertFalse(view.visibleCapabilities.contains { $0.type == .rule })
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

    func testAgentOverviewSummarizesPerAgentVisibilityDifferences() throws {
        let root = try fixtureURL("MixedProject")
        let graph = CapabilityResolver().resolve(scanResult: try scanProjectOnly(root))

        let overview = AgentOverviewBuilder().overview(graph: graph)

        XCTAssertEqual(overview.agentSummaries.count, AgentID.allCases.count)
        XCTAssertTrue(overview.agentSummaries.contains { $0.agent == .codex && $0.visibleCount > 0 && $0.hiddenCount > 0 })
        XCTAssertTrue(overview.agentSummaries.contains { $0.agent == .claudeCode && $0.visibleCount > 0 && $0.hiddenCount > 0 })
        XCTAssertTrue(overview.agentSummaries.contains { $0.agent == .cursor && $0.visibleCount > 0 && $0.hiddenCount > 0 })

        let larkDoc = try XCTUnwrap(overview.differences.first { $0.capabilityName == "lark-doc" })
        XCTAssertEqual(larkDoc.visibleAgents, [.codex])
        XCTAssertTrue(larkDoc.hiddenAgents.contains(.claudeCode))
        XCTAssertTrue(larkDoc.hiddenAgents.contains(.cursor))
    }

    func testCapabilityExplanationIncludesAgentVisibility() throws {
        let root = try fixtureURL("MixedProject")
        let scan = try scanProjectOnly(root)
        let graph = CapabilityResolver().resolve(scanResult: scan)
        let skill = try XCTUnwrap(graph.capabilities.first { $0.name == "lark-doc" && $0.type == .skill })

        let explanation = try CapabilityExplainer().explain(capabilityID: skill.id, graph: graph)

        XCTAssertEqual(explanation.capability.id, skill.id)
        XCTAssertTrue(explanation.visibleAgents.contains(.codex))
        XCTAssertFalse(explanation.visibleAgents.contains(.claudeCode))
        XCTAssertFalse(explanation.visibleAgents.contains(.cursor))
        XCTAssertTrue(explanation.hiddenAgents.contains(.claudeCode))
        XCTAssertTrue(explanation.hiddenAgents.contains(.cursor))
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
        XCTAssertTrue(AgentViewResolver().view(for: .claudeCode, graph: graph).visibleCapabilities.contains { $0.id == capability.id })
    }

    func testAdapterPreviewExplainsCodexGeneratedFilesAndUnsupportedCapabilities() throws {
        let root = try fixtureURL("MixedProject")
        let graph = CapabilityResolver().resolve(scanResult: try scanProjectOnly(root))

        let preview = AdapterPreviewBuilder().preview(for: .codex, graph: graph)

        XCTAssertEqual(preview.agent, .codex)
        XCTAssertTrue(preview.generatedFiles.contains { $0.path.hasSuffix("/.agents/adapters/codex/capabilities.json") })
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
        XCTAssertEqual(codexMapping.targetPath?.hasSuffix("/.agents/skills/lark-doc"), true)
        XCTAssertTrue(codexMapping.reason.contains("Codex loads skills"))

        let cursorMapping = try XCTUnwrap(cursorPreview.capabilityMappings.first { $0.capabilityID == skill.id })
        XCTAssertFalse(cursorMapping.supported)
        XCTAssertNil(cursorMapping.targetPath)
        XCTAssertTrue(cursorMapping.reason.contains("does not load skill"))
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
        XCTAssertEqual(larkDoc.visibleAgents, [.codex])
        XCTAssertTrue(larkDoc.hiddenAgents.contains(.claudeCode))
        XCTAssertTrue(larkDoc.hiddenAgents.contains(.cursor))
        XCTAssertTrue(larkDoc.reasons.contains { $0.contains("visible to codex") })
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
        XCTAssertTrue(plan.operations.contains { $0.kind == .writeFile && $0.path.hasSuffix("/.agents/adapters/codex/capabilities.json") })
        XCTAssertTrue(plan.operations.contains { $0.kind == .writeFile && $0.path.hasSuffix("/.agents/adapters/claude-code/capabilities.json") })
        XCTAssertTrue(plan.operations.contains { $0.kind == .writeFile && $0.path.hasSuffix("/.agents/adapters/cursor/capabilities.json") })
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
            .appendingPathComponent(".agents/skills/\(skillName)")
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
        XCTAssertTrue(plan.operations.contains { $0.kind == .writeFile && $0.path.hasSuffix("/.agents/adapters/codex/capabilities.json") })
        XCTAssertTrue(plan.operations.contains { $0.kind == .writeFile && $0.path.hasSuffix("/.agents/adapters/claude-code/capabilities.json") })
        XCTAssertTrue(plan.operations.contains { $0.kind == .writeFile && $0.path.hasSuffix("/.agents/adapters/cursor/capabilities.json") })
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
        XCTAssertTrue(FileManager.default.fileExists(atPath: temporaryRoot.appendingPathComponent(".agents/adapters/codex/capabilities.json").path))
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
        _ = try executor.apply(disable)

        XCTAssertFalse(FileManager.default.fileExists(atPath: skillDirectory.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: try XCTUnwrap(cacheOperation.target)))

        let enable = try builder.planEnable(capabilityID: capability.id, graph: graph)
        let restoreOperation = try XCTUnwrap(enable.operations.first { $0.kind == .restorePath })
        _ = try executor.apply(enable)

        XCTAssertEqual(restoreOperation.path, cacheOperation.target)
        XCTAssertTrue(FileManager.default.fileExists(atPath: skillFile.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: restoreOperation.path))
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

    func testDisableSkillPlanExecutorRegeneratesAdaptersWithoutDisabledSkill() throws {
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

        let adapterPath = temporaryRoot.appendingPathComponent(".agents/adapters/codex/capabilities.json")
        let adapterText = try String(contentsOf: adapterPath, encoding: .utf8)
        XCTAssertTrue(adapterText.contains("\"agent\" : \"codex\""))
        XCTAssertFalse(adapterText.contains("\"id\" : \"\(skill.id)\""))
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
        XCTAssertTrue(rollback.operations.contains { $0.kind == .writeFile && $0.path.hasSuffix("/.agents/adapters/codex/capabilities.json") })
        XCTAssertTrue(rollback.operations.contains { $0.kind == .appendLog && ($0.content ?? "").contains("rollback") })
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
        let adapterFile = temporaryRoot.appendingPathComponent(".agents/adapters/codex/capabilities.json")
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
                && operation.path.hasSuffix("/.agents/adapters/codex/capabilities.json")
                && operation.description.contains("stale adapter")
        })
        XCTAssertFalse(plan.operations.contains { $0.path.contains("node_modules") })
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

        let graph = CapabilityResolver().resolve(scanResult: try scanProjectOnly(temporaryRoot))

        let plan = try ApplyPlanBuilder().planClean(graph: graph)

        XCTAssertTrue(plan.operations.contains { operation in
            operation.kind == .removePath
                && operation.path.hasSuffix("/.agents/adapters/codex/capabilities.json")
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
        XCTAssertFalse(result.capabilities.contains { $0.name == "Other Project" })

        let hook = try XCTUnwrap(result.capabilities.first { $0.source.kind == "claude-plugin-hook" })
        XCTAssertEqual(hook.type, .hook)
        XCTAssertEqual(hook.pluginID, plugin.id)
        XCTAssertEqual(hook.metadata["pluginSelector"], "project-tool@test-marketplace")

        let items = CapabilityDisplayGrouper().items(for: [plugin, hook], preservesInputOrder: true)
        XCTAssertEqual(items.count, 1)
        guard case let .group(group) = items.first else {
            return XCTFail("Expected Claude plugin hook to be grouped under the real plugin")
        }
        XCTAssertEqual(group.kind, .plugin)
        XCTAssertEqual(group.representative?.id, plugin.id)
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
        XCTAssertTrue(scannedSkill.metadata["skillsInstalledAgentIDs"]?.contains("codex") == true)
        XCTAssertTrue(scannedSkill.metadata["skillsInstallTargets"]?.contains("codex=canonical") == true)
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
        XCTAssertTrue(scannedSkill.metadata["skillsInstallTargets"]?.contains("codex=canonical") == true)
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

    private func skillText(name: String, body: String) -> String {
        """
        ---
        name: \(name)
        description: test skill
        ---

        \(body)
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
