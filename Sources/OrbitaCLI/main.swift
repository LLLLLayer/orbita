import Foundation
import Darwin
import OrbitaCore

struct CLIRunResult {
    var exitCode: Int32
    var stdout: String
    var stderr: String
}

@main
struct OrbitaCLI {
    static func main() {
        let result = runForTesting(arguments: Array(CommandLine.arguments.dropFirst()))
        if !result.stdout.isEmpty {
            FileHandle.standardOutput.write(Data(result.stdout.utf8))
        }
        if !result.stderr.isEmpty {
            FileHandle.standardError.write(Data(result.stderr.utf8))
        }
        if result.exitCode != 0 {
            Darwin.exit(result.exitCode)
        }
    }

    static func runForTesting(arguments: [String]) -> CLIRunResult {
        var stdout = ""
        var stderr = ""
        do {
            let command = try ParsedCommand(arguments: arguments)
            let exitCode = try run(command) { line in
                stdout += line
                stdout += "\n"
            }
            return CLIRunResult(exitCode: exitCode, stdout: stdout, stderr: stderr)
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            if arguments.contains("--json") {
                if let applyError = error as? ApplyExecutionError {
                    stdout += jsonString(jsonErrorPayload(for: applyError))
                } else {
                    stdout += jsonString(CLIErrorPayload(schemaVersion: 1, error: message))
                }
                stdout += "\n"
            } else {
                stderr += "error: \(message)\n"
            }
            return CLIRunResult(exitCode: 1, stdout: stdout, stderr: stderr)
        }
    }

    private static func run(_ command: ParsedCommand, emit: (String) -> Void) throws -> Int32 {
        // A resolved graph carrying an `.error` issue (e.g. a malformed `.agents/manifest.json`) means the
        // user's declared intent could not be honored — exit non-zero so scripts and CI notice, even though
        // we still print the partial result.
        var errorExitCode: Int32 = 0
        // Single place that turns a resolved graph carrying an `.error` issue into exit code 2.
        // Every READ-ONLY graph-consuming command goes through this so the documented contract holds
        // by construction. `plan` deliberately calls the raw `graph(...)` helper instead: it may need to
        // *repair* the malformed manifest, and it owns its own 0/1 exit semantics.
        func resolvedGraph(_ projectRoot: String, _ includeUserScope: Bool) throws -> CapabilityGraph {
            let resolved = try graph(projectRoot: projectRoot, includeUserScope: includeUserScope)
            if resolved.issues.contains(where: { $0.severity == .error }) { errorExitCode = 2 }
            return resolved
        }
        switch command.name {
        case "help":
            emit(helpText())
        case "scan":
            let result = try scan(projectRoot: command.projectRoot, includeUserScope: command.includeUserScope)
            if result.issues.contains(where: { $0.severity == .error }) { errorExitCode = 2 }
            if command.json {
                emit(jsonString(result))
            } else {
                printScan(result, emit: emit)
            }
        case "status":
            let graph = try resolvedGraph(command.projectRoot, command.includeUserScope)
            if command.json {
                emit(jsonString(graph))
            } else {
                printStatus(graph, emit: emit)
            }
        case "graph":
            let graph = try resolvedGraph(command.projectRoot, command.includeUserScope)
            if command.json {
                emit(jsonString(graph))
            } else {
                printStatus(graph, emit: emit)
            }
        case "drift":
            let resolvedGraph = try resolvedGraph(command.projectRoot, command.includeUserScope)
            let report = DriftReportBuilder().report(graph: resolvedGraph)
            if command.json {
                emit(jsonString(report))
            } else {
                printDrift(report, emit: emit)
            }
        case "overview":
            let resolvedGraph = try resolvedGraph(command.projectRoot, command.includeUserScope)
            let overview = AgentOverviewBuilder().overview(graph: resolvedGraph)
            if command.json {
                emit(jsonString(overview))
            } else {
                printOverview(overview, emit: emit)
            }
        case "agent":
            let agent = try command.agentID()
            let resolvedGraph = try resolvedGraph(command.projectRoot, command.includeUserScope)
            let view = AgentViewResolver().view(for: agent, graph: resolvedGraph)
            if command.json {
                emit(jsonString(view))
            } else {
                emit("\(agent.rawValue) sees \(view.visibleCapabilities.count) visible, \(view.hiddenCapabilities.count) hidden")
                for capability in view.visibleCapabilities {
                    emit("- \(capability.name) [\(capability.type.rawValue)]")
                }
                if !view.hiddenCapabilities.isEmpty {
                    emit("Hidden (not loaded by \(agent.rawValue)):")
                    for capability in view.hiddenCapabilities {
                        emit("- \(capability.name) [\(capability.type.rawValue)]")
                    }
                }
            }
        case "explain":
            let resolvedGraph = try resolvedGraph(command.projectRoot, command.includeUserScope)
            guard let id = command.capabilityID else {
                throw CLIError.missingCapabilityID
            }
            let capability = try resolveCapability(id, in: resolvedGraph)
            let explanation = try CapabilityExplainer().explain(capabilityID: capability.id, graph: resolvedGraph)
            if command.json {
                emit(jsonString(explanation))
            } else {
                printExplain(explanation, emit: emit)
            }
        case "plan":
            let plan: ApplyPlan
            if let enableID = command.enableCapabilityID {
                let resolvedGraph = try graph(projectRoot: command.projectRoot, includeUserScope: command.includeUserScope)
                let capability = try resolveCapability(enableID, in: resolvedGraph)
                plan = try ApplyPlanBuilder().planEnable(capabilityID: capability.id, graph: resolvedGraph)
            } else if let disableID = command.disableCapabilityID {
                let resolvedGraph = try graph(projectRoot: command.projectRoot, includeUserScope: command.includeUserScope)
                let capability = try resolveCapability(disableID, in: resolvedGraph)
                plan = try ApplyPlanBuilder().planDisable(capabilityID: capability.id, graph: resolvedGraph)
            } else if let deleteID = command.deleteCapabilityID {
                let resolvedGraph = try graph(projectRoot: command.projectRoot, includeUserScope: command.includeUserScope)
                let capability = try resolveCapability(deleteID, in: resolvedGraph)
                plan = try ApplyPlanBuilder().planDelete(capabilityID: capability.id, graph: resolvedGraph)
            } else if command.rollback {
                let resolvedGraph = try graph(projectRoot: command.projectRoot, includeUserScope: command.includeUserScope)
                plan = try ApplyPlanBuilder().planRollback(graph: resolvedGraph)
            } else if command.merge {
                let resolvedGraph = try graph(projectRoot: command.projectRoot, includeUserScope: command.includeUserScope)
                plan = try ApplyPlanBuilder().planMerge(graph: resolvedGraph)
            } else if command.clean {
                let resolvedGraph = try graph(projectRoot: command.projectRoot, includeUserScope: command.includeUserScope)
                plan = try ApplyPlanBuilder().planClean(graph: resolvedGraph)
            } else if let syncID = command.syncCapabilityID {
                guard let agentID = command.agent else { throw CLIError.missingValue("--agent") }
                let mode: AgentSyncMode
                if let rawMode = command.syncMode {
                    guard let parsed = AgentSyncMode(rawValue: rawMode) else { throw CLIError.invalidValue("--mode", rawMode) }
                    mode = parsed
                } else {
                    mode = .symlink
                }
                let scope: AgentSyncDestinationScope?
                if let rawScope = command.syncScope {
                    guard let parsed = AgentSyncDestinationScope(rawValue: rawScope) else { throw CLIError.invalidValue("--scope", rawScope) }
                    scope = parsed
                } else {
                    scope = nil
                }
                let resolvedGraph = try graph(projectRoot: command.projectRoot, includeUserScope: command.includeUserScope)
                let capability = try resolveCapability(syncID, in: resolvedGraph)
                plan = try ApplyPlanBuilder().planSyncInstallTarget(
                    capabilityID: capability.id,
                    agentID: agentID,
                    graph: resolvedGraph,
                    mode: mode,
                    destinationScope: scope
                )
            } else if let resyncID = command.resyncCapabilityID {
                guard let agentID = command.agent else { throw CLIError.missingValue("--agent") }
                let scope: AgentSyncDestinationScope?
                if let rawScope = command.syncScope {
                    guard let parsed = AgentSyncDestinationScope(rawValue: rawScope) else { throw CLIError.invalidValue("--scope", rawScope) }
                    scope = parsed
                } else {
                    scope = nil
                }
                let resolvedGraph = try graph(projectRoot: command.projectRoot, includeUserScope: command.includeUserScope)
                let capability = try resolveCapability(resyncID, in: resolvedGraph)
                plan = try ApplyPlanBuilder().planReSyncInstallTarget(
                    capabilityID: capability.id,
                    agentID: agentID,
                    graph: resolvedGraph,
                    destinationScope: scope
                )
            } else {
                throw CLIError.missingPlanCapabilityID
            }
            if command.apply {
                let result = try ApplyPlanExecutor().apply(plan)
                if command.json {
                    emit(jsonString(result))
                } else {
                    emit("Applied \(result.completedOperations.count) operations")
                }
            } else if command.json {
                emit(jsonString(plan))
            } else {
                printPlan(plan, emit: emit)
            }
        case "preview":
            let agent = try command.agentID()
            let resolvedGraph = try resolvedGraph(command.projectRoot, command.includeUserScope)
            let preview = AdapterPreviewBuilder().preview(for: agent, graph: resolvedGraph)
            if command.json {
                emit(jsonString(preview))
            } else {
                printPreview(preview, emit: emit)
            }
        case "doctor":
            let doctor = DoctorReportBuilder().report(currentDirectory: command.projectRoot, swiftVersion: swiftVersionString())
            if command.json {
                emit(jsonString(doctor))
            } else {
                emit("Orbita doctor")
                emit("- Swift: \(doctor.swiftVersion)")
                emit("- CWD: \(doctor.currentDirectory)")
                for check in doctor.checks {
                    let path = check.path.map { " \($0)" } ?? ""
                    emit("- [\(check.status.rawValue)] \(check.title): \(check.message)\(path)")
                }
            }
        default:
            throw CLIError.unknownCommand(command.name)
        }
        return errorExitCode
    }

    private static func helpText() -> String {
        """
        orbita — manage coding-agent capabilities across Codex, Claude Code, Cursor, Trae, and .agents

        USAGE
          orbita <command> [<project-path>] [options]

        The project path can be given positionally, or with --project / --project-root.
        doctor needs no project; help needs no arguments.

        READ-ONLY COMMANDS
          scan      List raw discovered capabilities and scan issues
          status    Capability counts by type, status, and risk
          graph     Resolved capability graph (duplicates/shadows/drift marked)
          overview  Per-agent visibility summary across all agents
          drift     Capabilities that differ across agents or locations
          agent     What a single agent sees (and what it hides) — needs --agent
          explain   Why an agent sees a capability — needs <capability-id>
          preview   Adapter preview for an agent — needs --agent
          doctor    Environment checks (no project required)

        MUTATING COMMANDS
          plan      Build (and optionally apply) a change. One action required:
                      --enable <id> | --disable <id> | --delete <id>
                      --merge | --rollback | --clean
                      --sync <id> --agent <id> [--mode copy|symlink] [--scope project|user]
                      --resync <id> --agent <id> [--scope project|user]
                    Add --apply to execute; without it, prints a dry run.

        OPTIONS
          --agent <id>       codex | claude-code | cursor | trae | trae-cn (agent commands default to codex)
          --project <path>   Project root (synonym: --project-root; or pass it positionally)
          --no-user-scope    Restrict scanning to the project (skip ~/.codex, ~/.claude, etc.)
          --json             Emit machine-readable JSON (supported by every read command and plan)
          -h, --help, help   Show this help

        EXIT CODES
          0  success
          1  runtime error (missing path, invalid flag/value, capability not found)
          2  the resolved graph carries an error issue (e.g. malformed .agents/manifest.json)

        EXAMPLES
          orbita status .
          orbita agent ~/code/app --agent claude-code
          orbita drift . --json
          orbita plan . --disable skill:foo
          orbita plan . --sync skill:foo --agent trae --mode symlink --apply
        """
    }

    private static func scan(projectRoot: String, includeUserScope: Bool) throws -> ScanResult {
        try CapabilityScanner().scan(projectRoot: URL(fileURLWithPath: projectRoot), options: ScanOptions(includeUserScope: includeUserScope))
    }

    private static func graph(projectRoot: String, includeUserScope: Bool) throws -> CapabilityGraph {
        let result = try scan(projectRoot: projectRoot, includeUserScope: includeUserScope)
        return CapabilityResolver().resolve(scanResult: result)
    }

    private static func printScan(_ result: ScanResult, emit: (String) -> Void) {
        emit("Discovered \(result.capabilities.count) capabilities in \(result.projectRoot)")
        emit("Capabilities:")
        for capability in result.capabilities.sorted(by: { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }) {
            emit("- \(capability.name) [\(capability.type.rawValue)] scope:\(capability.scope.rawValue) risk:\(capability.risks.map(\.rawValue).joined(separator: ",")) source:\(capability.source.path)")
        }
        printIssues(result.issues, emit: emit)
    }

    private static func printStatus(_ graph: CapabilityGraph, emit: (String) -> Void) {
        emit("Orbita status for \(graph.projectRoot)")
        emit("Capabilities: \(graph.capabilities.count)")

        emit("By type:")
        let grouped = Dictionary(grouping: graph.capabilities, by: \.type)
        for type in CapabilityType.allCases {
            guard let values = grouped[type], !values.isEmpty else { continue }
            emit("- \(type.rawValue): \(values.count)")
        }

        emit("Status:")
        for status in CapabilityStatus.allCases {
            let count = graph.capabilities.filter { $0.statuses.contains(status) }.count
            emit("- \(status.rawValue): \(count)")
        }

        emit("Risk:")
        for risk in RiskLevel.allCases {
            let count = graph.capabilities.filter { $0.risks.contains(risk) }.count
            emit("- \(risk.rawValue): \(count)")
        }
        printIssues(graph.issues, emit: emit)
    }

    private static func printIssues(_ issues: [ScanIssue], emit: (String) -> Void) {
        guard !issues.isEmpty else { return }
        emit("Issues:")
        for issue in issues {
            emit("- [\(issue.severity.rawValue)] \(issue.path): \(issue.message)")
        }
    }

    private static func printExplain(_ explanation: CapabilityExplanation, emit: (String) -> Void) {
        let capability = explanation.capability
        emit(capability.name)
        emit("- id: \(capability.id)")
        emit("- type: \(capability.type.rawValue)")
        emit("- scope: \(capability.scope.rawValue)")
        emit("- source: \(capability.source.path)")
        emit("- status: \(capability.statuses.map(\.rawValue).joined(separator: ", "))")
        emit("- risk: \(capability.risks.map(\.rawValue).joined(separator: ", "))")
        emit("- visibleAgents: \(explanation.visibleAgents.map(\.rawValue).joined(separator: ", "))")
        emit("- hiddenAgents: \(explanation.hiddenAgents.map(\.rawValue).joined(separator: ", "))")
        if let summary = capability.summary {
            emit("- summary: \(summary)")
        }
    }

    private static func printPlan(_ plan: ApplyPlan, emit: (String) -> Void) {
        emit("Orbita apply plan")
        emit("- action: \(plan.action.rawValue)")
        emit("- capability: \(plan.capabilityID)")
        emit("- dryRun: \(!plan.appliesChanges)")
        emit("- requiresConfirmation: \(plan.requiresConfirmation)")
        emit("Operations:")
        for operation in plan.operations {
            if let target = operation.target {
                emit("- \(operation.kind.rawValue): \(operation.path) -> \(target) [\(operation.risk.rawValue)] \(operation.description)")
            } else {
                emit("- \(operation.kind.rawValue): \(operation.path) [\(operation.risk.rawValue)] \(operation.description)")
            }
        }
    }

    private static func printPreview(_ preview: AdapterPreview, emit: (String) -> Void) {
        emit("\(preview.agent.rawValue) adapter preview")
        emit("- supported: \(preview.supportedCapabilities.count)")
        emit("- unsupported: \(preview.unsupportedCapabilities.count)")
        emit("Generated files:")
        for file in preview.generatedFiles {
            emit("- \(file.path)")
        }
    }

    private static func printDrift(_ report: DriftReport, emit: (String) -> Void) {
        emit("Orbita drift report")
        emit("- items: \(report.items.count)")
        for item in report.items {
            emit("- \(item.capabilityName): \(item.reasons.joined(separator: "; "))")
        }
    }

    private static func printOverview(_ overview: AgentCapabilityOverview, emit: (String) -> Void) {
        emit("Orbita agent overview")
        for summary in overview.agentSummaries {
            emit("- \(summary.agent.rawValue): \(summary.visibleCount) visible, \(summary.hiddenCount) hidden, \(summary.driftedCount) drifted")
        }
        emit("Differences:")
        if overview.differences.isEmpty {
            emit("- none")
        } else {
            for difference in overview.differences.prefix(10) {
                let visible = difference.visibleAgents.map(\.rawValue).joined(separator: ", ")
                let hidden = difference.hiddenAgents.map(\.rawValue).joined(separator: ", ")
                emit("- \(difference.capabilityName): visible to \(visible); hidden from \(hidden)")
            }
        }
    }

    private static func jsonString<T: Encodable>(_ value: T) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(value), let text = String(data: data, encoding: .utf8) {
            return text
        }
        return "{}"
    }

    static func jsonErrorPayload(for error: ApplyExecutionError) -> CLIApplyExecutionErrorPayload {
        CLIApplyExecutionErrorPayload(
            schemaVersion: error.schemaVersion,
            error: error.message,
            projectRoot: error.projectRoot,
            completedOperations: error.completedOperations,
            failedOperation: error.failedOperation,
            pendingOperations: error.pendingOperations
        )
    }

    private static func swiftVersionString() -> String {
        #if swift(>=6.0)
        return "Swift 6+"
        #else
        return "Swift"
        #endif
    }

    private static func normalizedIdentifier(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: "@", with: "")
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: "_", with: "-")
            .trimmingCharacters(in: CharacterSet(charactersIn: "- "))
    }

    private static func resolveCapability(_ requestedID: String, in graph: CapabilityGraph) throws -> Capability {
        if let capability = graph.capabilities.first(where: { $0.id == requestedID }) {
            return capability
        }

        let normalized = normalizedIdentifier(requestedID)
        if let capability = graph.capabilities.first(where: { normalizedIdentifier($0.name) == normalized }) {
            return capability
        }

        throw CLIError.capabilityNotFound(requestedID)
    }
}

struct ParsedCommand {
    var name: String
    var projectRoot: String
    var json: Bool
    var includeUserScope: Bool
    var agent: String?
    var capabilityID: String?
    var enableCapabilityID: String?
    var disableCapabilityID: String?
    var deleteCapabilityID: String?
    var syncCapabilityID: String?
    var resyncCapabilityID: String?
    var syncMode: String?
    var syncScope: String?
    var apply: Bool
    var rollback: Bool
    var merge: Bool
    var clean: Bool

    init(arguments: [String]) throws {
        // Help is discoverable before anything else: no args, or a help token in the COMMAND position
        // (`orbita`, `orbita help`, `orbita --help`, `orbita -h`). We deliberately do NOT scan the whole
        // argument list — a capability id passed as a flag value (`--disable -h`) must not be hijacked.
        let helpTokens: Set<String> = ["help", "--help", "-h"]
        if arguments.isEmpty || helpTokens.contains(arguments[0]) {
            name = "help"
            projectRoot = ""
            json = false
            includeUserScope = true
            agent = nil
            capabilityID = nil
            enableCapabilityID = nil
            disableCapabilityID = nil
            deleteCapabilityID = nil
            syncCapabilityID = nil
            resyncCapabilityID = nil
            syncMode = nil
            syncScope = nil
            apply = false
            rollback = false
            merge = false
            clean = false
            return
        }

        guard let first = arguments.first else {
            throw CLIError.missingCommand
        }
        name = first
        json = arguments.contains("--json")
        includeUserScope = !arguments.contains("--no-user-scope")

        var positional: [String] = []
        var index = 1
        var parsedAgent: String?
        var explicitProject: String?
        var parsedEnableCapabilityID: String?
        var parsedDisableCapabilityID: String?
        var parsedDeleteCapabilityID: String?
        var parsedSyncCapabilityID: String?
        var parsedResyncCapabilityID: String?
        var parsedSyncMode: String?
        var parsedSyncScope: String?
        var parsedApply = false
        var parsedRollback = false
        var parsedMerge = false
        var parsedClean = false

        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--json", "--no-user-scope":
                index += 1
            case "--apply":
                parsedApply = true
                index += 1
            case "--rollback":
                parsedRollback = true
                index += 1
            case "--merge":
                parsedMerge = true
                index += 1
            case "--clean":
                parsedClean = true
                index += 1
            case "--agent":
                guard index + 1 < arguments.count else { throw CLIError.missingValue("--agent") }
                parsedAgent = arguments[index + 1]
                index += 2
            case "--enable":
                guard index + 1 < arguments.count else { throw CLIError.missingValue("--enable") }
                parsedEnableCapabilityID = arguments[index + 1]
                index += 2
            case "--disable":
                guard index + 1 < arguments.count else { throw CLIError.missingValue("--disable") }
                parsedDisableCapabilityID = arguments[index + 1]
                index += 2
            case "--delete":
                guard index + 1 < arguments.count else { throw CLIError.missingValue("--delete") }
                parsedDeleteCapabilityID = arguments[index + 1]
                index += 2
            case "--sync":
                guard index + 1 < arguments.count else { throw CLIError.missingValue("--sync") }
                parsedSyncCapabilityID = arguments[index + 1]
                index += 2
            case "--resync":
                guard index + 1 < arguments.count else { throw CLIError.missingValue("--resync") }
                parsedResyncCapabilityID = arguments[index + 1]
                index += 2
            case "--mode":
                guard index + 1 < arguments.count else { throw CLIError.missingValue("--mode") }
                parsedSyncMode = arguments[index + 1]
                index += 2
            case "--scope":
                guard index + 1 < arguments.count else { throw CLIError.missingValue("--scope") }
                parsedSyncScope = arguments[index + 1]
                index += 2
            case "--project", "--project-root":
                guard index + 1 < arguments.count else { throw CLIError.missingValue(argument) }
                explicitProject = arguments[index + 1]
                index += 2
            default:
                positional.append(argument)
                index += 1
            }
        }

        agent = parsedAgent
        enableCapabilityID = parsedEnableCapabilityID
        disableCapabilityID = parsedDisableCapabilityID
        deleteCapabilityID = parsedDeleteCapabilityID
        syncCapabilityID = parsedSyncCapabilityID
        resyncCapabilityID = parsedResyncCapabilityID
        syncMode = parsedSyncMode
        syncScope = parsedSyncScope
        apply = parsedApply
        rollback = parsedRollback
        merge = parsedMerge
        clean = parsedClean

        if name == "doctor" {
            projectRoot = explicitProject ?? FileManager.default.currentDirectoryPath
            capabilityID = nil
            return
        }

        guard let root = explicitProject ?? positional.first else {
            throw CLIError.missingProjectRoot
        }
        projectRoot = root
        capabilityID = positional.dropFirst().first
    }

    func agentID() throws -> AgentID {
        guard let agent else { return .codex }
        guard let id = AgentID(rawValue: agent) else {
            throw OrbitaError.invalidAgent(agent)
        }
        return id
    }
}

enum CLIError: LocalizedError {
    case missingCommand
    case unknownCommand(String)
    case missingProjectRoot
    case missingValue(String)
    case invalidValue(String, String)
    case missingCapabilityID
    case missingPlanCapabilityID
    case capabilityNotFound(String)

    var errorDescription: String? {
        switch self {
        case .missingCommand:
            return "Missing command. Try scan, status, graph, overview, drift, agent, explain, preview, plan, or doctor."
        case .unknownCommand(let command):
            return "Unknown command: \(command)"
        case .missingProjectRoot:
            return "Missing project root path."
        case .missingValue(let flag):
            return "Missing value for \(flag)."
        case let .invalidValue(flag, value):
            return "Invalid value for \(flag): \(value)."
        case .missingCapabilityID:
            return "Missing capability id."
        case .missingPlanCapabilityID:
            return "Missing plan action. Use --enable <capability-id>, --disable <capability-id>, --delete <capability-id>, --sync <capability-id> --agent <id> [--mode copy|symlink] [--scope project|user], --resync <capability-id> --agent <id> [--scope project|user], --merge, --rollback, or --clean."
        case .capabilityNotFound(let id):
            return "Capability not found: \(id)"
        }
    }
}

struct CLIErrorPayload: Codable {
    var schemaVersion: Int
    var error: String
}

struct CLIApplyExecutionErrorPayload: Codable {
    var schemaVersion: Int
    var error: String
    var projectRoot: String
    var completedOperations: [ApplyOperation]
    var failedOperation: ApplyOperation
    var pendingOperations: [ApplyOperation]
}
