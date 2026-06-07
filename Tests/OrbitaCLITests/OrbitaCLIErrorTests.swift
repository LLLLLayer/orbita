import XCTest
@testable import OrbitaCLI
import OrbitaCore

final class OrbitaCLIErrorTests: XCTestCase {
    func testStatusExitsNonZeroWhenAgentsManifestIsMalformed() throws {
        let fm = FileManager.default
        let projectRoot = fm.temporaryDirectory.standardizedFileURL
            .appendingPathComponent("OrbitaCLITests-\(UUID().uuidString)")
        let manifest = projectRoot.appendingPathComponent(".agents/manifest.json")
        try fm.createDirectory(at: manifest.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "{ this is not valid json".write(to: manifest, atomically: true, encoding: .utf8)
        defer { try? fm.removeItem(at: projectRoot) }

        let result = OrbitaCLI.runForTesting(arguments: ["status", projectRoot.path, "--no-user-scope"])
        XCTAssertEqual(result.exitCode, 2, "a malformed .agents/manifest.json should make the CLI exit non-zero")
    }

    func testGraphJSONCommandReturnsFixtureSnapshotFields() throws {
        let root = fixtureURL("MixedProject")

        let result = OrbitaCLI.runForTesting(arguments: ["graph", root.path, "--no-user-scope", "--json"])

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stderr.isEmpty)
        let data = try XCTUnwrap(result.stdout.data(using: .utf8))
        let graph = try JSONDecoder().decode(CapabilityGraph.self, from: data)
        XCTAssertEqual(graph.schemaVersion, 1)
        XCTAssertTrue(graph.capabilities.contains { $0.name == "lark-doc" && $0.type == .skill })
        XCTAssertTrue(graph.capabilities.contains { $0.name == "review" && $0.source.kind == "claude-command" })
        XCTAssertTrue(graph.capabilities.contains { $0.name == "Legacy Cursor rules" && $0.source.kind == "legacy-cursor-rule" })
    }

    func testScanTextListsCapabilitiesWithSourcesAndRisks() throws {
        let root = fixtureURL("MixedProject")

        let result = OrbitaCLI.runForTesting(arguments: ["scan", root.path, "--no-user-scope"])

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stderr.isEmpty)
        XCTAssertTrue(result.stdout.contains("Capabilities:"))
        XCTAssertTrue(result.stdout.contains("- lark-doc [skill]"))
        XCTAssertTrue(result.stdout.contains("risk:"))
        XCTAssertTrue(result.stdout.contains("source:"))
        XCTAssertTrue(result.stdout.contains("/SKILL.md"))
    }

    func testStatusTextIncludesStatusAndRiskSummaries() throws {
        let root = fixtureURL("MixedProject")

        let result = OrbitaCLI.runForTesting(arguments: ["status", root.path, "--no-user-scope"])

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stderr.isEmpty)
        XCTAssertTrue(result.stdout.contains("By type:"))
        XCTAssertTrue(result.stdout.contains("Status:"))
        XCTAssertTrue(result.stdout.contains("- discovered:"))
        XCTAssertTrue(result.stdout.contains("- risky:"))
        XCTAssertTrue(result.stdout.contains("Risk:"))
        XCTAssertTrue(result.stdout.contains("- exec:"))
    }

    func testProjectRootAndProjectFlagsAreEquivalent() throws {
        let root = fixtureURL("MixedProject")

        let viaProjectRoot = OrbitaCLI.runForTesting(arguments: ["scan", "--project-root", root.path, "--no-user-scope"])
        let viaProject = OrbitaCLI.runForTesting(arguments: ["scan", "--project", root.path, "--no-user-scope"])
        let viaPositional = OrbitaCLI.runForTesting(arguments: ["scan", root.path, "--no-user-scope"])

        XCTAssertEqual(viaProjectRoot.exitCode, 0)
        XCTAssertEqual(viaProject.exitCode, 0)
        XCTAssertEqual(viaPositional.exitCode, 0)
        XCTAssertEqual(viaProjectRoot.stdout, viaPositional.stdout)
        XCTAssertEqual(viaProject.stdout, viaPositional.stdout)
    }

    func testMissingProjectRootReturnsJSONErrorAndNonZeroExit() throws {
        let result = OrbitaCLI.runForTesting(arguments: ["scan", "/tmp/orbita-missing-\(UUID().uuidString)", "--json"])

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertTrue(result.stderr.isEmpty)
        let data = try XCTUnwrap(result.stdout.data(using: .utf8))
        let payload = try JSONDecoder().decode(CLIErrorPayload.self, from: data)
        XCTAssertEqual(payload.schemaVersion, 1)
        XCTAssertTrue(payload.error.contains("Project root does not exist"))
    }

    func testAgentCodexJSONHidesClaudeSpecificCommands() throws {
        let root = fixtureURL("MixedProject")

        let result = OrbitaCLI.runForTesting(arguments: ["agent", root.path, "--agent", "codex", "--no-user-scope", "--json"])

        XCTAssertEqual(result.exitCode, 0)
        let data = try XCTUnwrap(result.stdout.data(using: .utf8))
        let view = try JSONDecoder().decode(AgentView.self, from: data)
        XCTAssertTrue(view.visibleCapabilities.contains { $0.name == "bootstrap" && $0.source.kind == "codex-command" })
        XCTAssertFalse(view.visibleCapabilities.contains { $0.name == "review" && $0.source.kind == "claude-command" })
    }

    func testOverviewJSONReturnsAgentVisibilitySummary() throws {
        let root = fixtureURL("MixedProject")

        let result = OrbitaCLI.runForTesting(arguments: ["overview", root.path, "--no-user-scope", "--json"])

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stderr.isEmpty)
        let data = try XCTUnwrap(result.stdout.data(using: .utf8))
        let overview = try JSONDecoder().decode(AgentCapabilityOverview.self, from: data)
        XCTAssertEqual(overview.schemaVersion, 1)
        XCTAssertEqual(overview.agentSummaries.count, AgentID.allCases.count)
        XCTAssertTrue(overview.agentSummaries.contains { $0.agent == .codex && $0.visibleCount > 0 })
        XCTAssertTrue(overview.differences.contains { $0.capabilityName == "lark-doc" && Set($0.visibleAgents) == Set([.codex, .trae, .traeCN, .cursor]) })
    }

    func testOverviewTextPrintsAgentDifferenceSummary() throws {
        let root = fixtureURL("MixedProject")

        let result = OrbitaCLI.runForTesting(arguments: ["overview", root.path, "--no-user-scope"])

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.contains("Orbita agent overview"))
        XCTAssertTrue(result.stdout.contains("codex:"))
        XCTAssertTrue(result.stdout.contains("Differences:"))
        XCTAssertTrue(result.stdout.contains("lark-doc"))
    }

    func testPlanMergeJSONReturnsWorkspaceMergePlan() throws {
        let root = fixtureURL("MixedProject")

        let result = OrbitaCLI.runForTesting(arguments: ["plan", root.path, "--merge", "--no-user-scope", "--json"])

        XCTAssertEqual(result.exitCode, 0)
        let data = try XCTUnwrap(result.stdout.data(using: .utf8))
        let plan = try JSONDecoder().decode(ApplyPlan.self, from: data)
        XCTAssertEqual(plan.action, .merge)
        XCTAssertEqual(plan.capabilityID, "workspace")
        XCTAssertTrue(plan.operations.contains { $0.kind == .writeFile && $0.path.hasSuffix("/.agents/manifest.json") })
        XCTAssertTrue(plan.operations.contains { $0.kind == .createSymlink && $0.path.hasSuffix("/.agents/skills/lark-doc") })
        XCTAssertFalse(plan.operations.contains { $0.kind == .removePath })
    }

    func testPlanEnableAcceptsCapabilityName() throws {
        let root = fixtureURL("MixedProject")

        let result = OrbitaCLI.runForTesting(arguments: ["plan", root.path, "--enable", "lark-doc", "--no-user-scope", "--json"])

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stderr.isEmpty)
        let data = try XCTUnwrap(result.stdout.data(using: .utf8))
        let plan = try JSONDecoder().decode(ApplyPlan.self, from: data)
        XCTAssertEqual(plan.action, .enable)
        XCTAssertTrue(plan.operations.contains { $0.kind == .createSymlink && $0.path.hasSuffix("/.agents/skills/lark-doc") })
    }

    func testPlanDisableAcceptsCapabilityName() throws {
        let root = fixtureURL("MixedProject")

        let result = OrbitaCLI.runForTesting(arguments: ["plan", root.path, "--disable", "lark-doc", "--no-user-scope", "--json"])

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stderr.isEmpty)
        let data = try XCTUnwrap(result.stdout.data(using: .utf8))
        let plan = try JSONDecoder().decode(ApplyPlan.self, from: data)
        XCTAssertEqual(plan.action, .disable)
        XCTAssertTrue(plan.operations.contains { $0.kind == .writeFile && $0.path.hasSuffix("/.agents/manifest.json") && ($0.content ?? "").contains(CapabilityStatus.disabled.rawValue) })
        XCTAssertFalse(plan.operations.contains { $0.kind == .removePath && $0.path.hasSuffix("/.agents/skills/lark-doc") })
    }

    func testPlanSyncBuildsAgentSyncPlan() throws {
        let root = fixtureURL("MixedProject")

        let result = OrbitaCLI.runForTesting(arguments: ["plan", root.path, "--sync", "lark-doc", "--agent", "codex", "--no-user-scope", "--json"])

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stderr.isEmpty)
        let data = try XCTUnwrap(result.stdout.data(using: .utf8))
        let plan = try JSONDecoder().decode(ApplyPlan.self, from: data)
        XCTAssertEqual(plan.action, .enable)
        XCTAssertTrue(plan.operations.contains { $0.kind == .createSymlink && $0.path.hasSuffix("/.agents/skills/lark-doc") })
    }

    func testPlanSyncRejectsInvalidMode() throws {
        let root = fixtureURL("MixedProject")

        let result = OrbitaCLI.runForTesting(arguments: ["plan", root.path, "--sync", "lark-doc", "--agent", "codex", "--mode", "bogus", "--no-user-scope", "--json"])

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.contains("Invalid value for --mode"))
    }

    func testPlanTextPrintsOperationDescriptionsAndRisks() throws {
        let root = fixtureURL("MixedProject")

        let result = OrbitaCLI.runForTesting(arguments: ["plan", root.path, "--enable", "lark-doc", "--no-user-scope"])

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stderr.isEmpty)
        XCTAssertTrue(result.stdout.contains("Operations:"))
        XCTAssertTrue(result.stdout.contains("Read capability source before indexing"))
        XCTAssertTrue(result.stdout.contains("[write]"))
        XCTAssertTrue(result.stdout.contains("requiresConfirmation: true"))
    }

    func testJSONErrorPayloadIncludesApplyRecoveryDetails() throws {
        let completed = ApplyOperation(
            kind: .createDirectory,
            path: "/tmp/project/.agents",
            risk: .write,
            description: "Create .agents root"
        )
        let failed = ApplyOperation(
            kind: .writeFile,
            path: "/tmp/project/outside.json",
            content: "{}\n",
            risk: .write,
            description: "Unsafe write"
        )
        let pending = ApplyOperation(
            kind: .writeFile,
            path: "/tmp/project/.agents/manifest.json",
            content: "{}\n",
            risk: .write,
            description: "Write manifest"
        )
        let error = ApplyExecutionError(
            projectRoot: "/tmp/project",
            completedOperations: [completed],
            failedOperation: failed,
            pendingOperations: [pending],
            message: "Operation is outside .agents: /tmp/project/outside.json"
        )

        let payload = OrbitaCLI.jsonErrorPayload(for: error)

        XCTAssertEqual(payload.schemaVersion, 1)
        XCTAssertEqual(payload.error, error.message)
        XCTAssertEqual(payload.completedOperations, [completed])
        XCTAssertEqual(payload.failedOperation, failed)
        XCTAssertEqual(payload.pendingOperations, [pending])
    }

    func testHelpIsDiscoverableFromNoArgsAndHelpTokens() throws {
        for arguments in [[], ["help"], ["--help"], ["-h"]] {
            let result = OrbitaCLI.runForTesting(arguments: arguments)
            XCTAssertEqual(result.exitCode, 0, "help should exit 0 for \(arguments)")
            XCTAssertTrue(result.stderr.isEmpty, "help should not write to stderr for \(arguments)")
            XCTAssertTrue(result.stdout.contains("USAGE"), "help should print usage for \(arguments)")
            XCTAssertTrue(result.stdout.contains("plan"), "help should list the plan command for \(arguments)")
            XCTAssertTrue(result.stdout.contains("EXIT CODES"), "help should document exit codes for \(arguments)")
        }

        // A help token that is NOT in the command position (e.g. a capability id passed as a flag value)
        // must not hijack the command into help. Here `-h` is the --disable value, so this is a plan, not help.
        let notHelp = OrbitaCLI.runForTesting(arguments: ["plan", "/tmp/nonexistent-project", "--disable", "-h"])
        XCTAssertFalse(notHelp.stdout.contains("USAGE"), "a help token used as a flag value must not trigger help")
    }

    func testAgentTextOutputAlsoListsHiddenCapabilities() throws {
        let root = fixtureURL("MixedProject")

        let result = OrbitaCLI.runForTesting(arguments: ["agent", root.path, "--agent", "codex", "--no-user-scope"])

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stderr.isEmpty)
        // The header reports both counts, and a Claude-only command is surfaced under Hidden so a
        // text-mode user can see *why* an agent doesn't load it (parity with the --json output).
        XCTAssertTrue(result.stdout.contains("visible,"))
        XCTAssertTrue(result.stdout.contains("hidden"))
        XCTAssertTrue(result.stdout.contains("Hidden (not loaded by codex):"))
        XCTAssertTrue(result.stdout.contains("- review [command]"))
    }

    func testDoctorHonorsProjectRootForMcpCheck() throws {
        // INFO-doctor-flag: --project-root must steer the project-mcp check at the passed directory,
        // not the test process CWD.
        let fm = FileManager.default
        let projectRoot = fm.temporaryDirectory.standardizedFileURL
            .appendingPathComponent("OrbitaCLIDoctorTests-\(UUID().uuidString)")
        try fm.createDirectory(at: projectRoot, withIntermediateDirectories: true)
        let mcp = projectRoot.appendingPathComponent(".mcp.json")
        try "{}\n".write(to: mcp, atomically: true, encoding: .utf8)
        defer { try? fm.removeItem(at: projectRoot) }

        let result = OrbitaCLI.runForTesting(arguments: ["doctor", "--project-root", projectRoot.path, "--json"])

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stderr.isEmpty)
        let data = try XCTUnwrap(result.stdout.data(using: .utf8))
        let report = try JSONDecoder().decode(DoctorReport.self, from: data)
        XCTAssertEqual(report.currentDirectory, projectRoot.path)
        let mcpCheck = try XCTUnwrap(report.checks.first { $0.id == "project-mcp" })
        XCTAssertEqual(mcpCheck.status, .ok)
        XCTAssertTrue(mcpCheck.path?.hasSuffix("/.mcp.json") == true)
        XCTAssertTrue(mcpCheck.path?.hasPrefix(projectRoot.path) == true)
    }

    func testGraphConsumingCommandsExitTwoWhenAgentsManifestIsMalformed() throws {
        // LOW-6: every READ-ONLY command that resolves a graph must honor the documented exit-2 contract
        // on a malformed .agents/manifest.json, not just scan/status/graph.
        let fm = FileManager.default
        let projectRoot = fm.temporaryDirectory.standardizedFileURL
            .appendingPathComponent("OrbitaCLITests-\(UUID().uuidString)")
        let manifest = projectRoot.appendingPathComponent(".agents/manifest.json")
        try fm.createDirectory(at: manifest.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "{ this is not valid json".write(to: manifest, atomically: true, encoding: .utf8)
        defer { try? fm.removeItem(at: projectRoot) }

        let driftResult = OrbitaCLI.runForTesting(arguments: ["drift", projectRoot.path, "--no-user-scope"])
        XCTAssertEqual(driftResult.exitCode, 2, "drift should exit 2 on a malformed .agents/manifest.json")

        let agentResult = OrbitaCLI.runForTesting(arguments: ["agent", projectRoot.path, "--agent", "codex", "--no-user-scope"])
        XCTAssertEqual(agentResult.exitCode, 2, "agent should exit 2 on a malformed .agents/manifest.json")

        let previewResult = OrbitaCLI.runForTesting(arguments: ["preview", projectRoot.path, "--agent", "codex", "--no-user-scope"])
        XCTAssertEqual(previewResult.exitCode, 2, "preview should exit 2 on a malformed .agents/manifest.json")

        let overviewResult = OrbitaCLI.runForTesting(arguments: ["overview", projectRoot.path, "--no-user-scope"])
        XCTAssertEqual(overviewResult.exitCode, 2, "overview should exit 2 on a malformed .agents/manifest.json")
    }

    func testGraphConsumingCommandsExitZeroOnWellFormedProject() throws {
        // Companion to the malformed-manifest regression: the same commands must keep exiting 0 on a
        // well-formed project (no .error issue), proving the exit-2 helper only fires on errors.
        let root = fixtureURL("MixedProject")
        for command in [
            ["drift", root.path, "--no-user-scope"],
            ["agent", root.path, "--agent", "codex", "--no-user-scope"],
            ["preview", root.path, "--agent", "codex", "--no-user-scope"],
            ["overview", root.path, "--no-user-scope"]
        ] {
            let result = OrbitaCLI.runForTesting(arguments: command)
            XCTAssertEqual(result.exitCode, 0, "\(command.first ?? "") should exit 0 on a well-formed project")
        }
    }

    private func fixtureURL(_ name: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("OrbitaCoreTests/Fixtures")
            .appendingPathComponent(name)
    }
}
