import Foundation
import OrbitaCore

private enum ApplyExecutionOutcome: Sendable {
    case success(ApplyExecutionResult)
    case executionFailure(ApplyExecutionError)
    case failure(String)
}

enum CapabilityOptimisticMutation: Equatable, Sendable {
    case enable
    case disable
    case delete
}

struct CapabilityOptimisticMutationToken: Sendable {
    fileprivate let previousGraph: CapabilityGraph?
    fileprivate let optimisticRevision: Int?
    fileprivate let affectedCapabilities: [Capability]
}

@MainActor
final class ProjectCapabilityStore: ObservableObject {
    static let environmentSelectionID = "environment"
    static let environmentRoot = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".orbita/this-mac", isDirectory: true)
        .standardizedFileURL
        .resolvingSymlinksInPath()

    @Published var graph: CapabilityGraph?
    @Published var errorMessage: String?
    /// Transient confirmation shown after a successful apply, so a destructive enable/disable/delete
    /// reads as "done" instead of a silent re-scan. Cleared on the next apply and auto-dismissed by
    /// the banner. Bumped token lets the banner restart its dismiss timer on repeated identical text.
    @Published var successMessage: String?
    @Published private(set) var successMessageToken = 0
    @Published var isScanning = false
    @Published var scanMessage: String?
    @Published var scanProgress = 0.0
    @Published var projects: [ProjectRecord] = []
    @Published var lastRefreshedAt: Date?

    private var projectRoot: URL?
    private var isEnvironment = true
    private var library = ProjectLibrary()
    private var scanTask: Task<Void, Never>?
    private var refreshPolicy = ScanRefreshPolicy.oneHour
    private let snapshotStore: CapabilitySnapshotStore
    private let projectLibraryStore: ProjectLibraryStore
    private let iso8601Formatter = ISO8601DateFormatter()
    private(set) var graphRevision = 0

    init(
        projectRoot: URL? = nil,
        snapshotStore: CapabilitySnapshotStore = CapabilitySnapshotStore(),
        projectLibraryStore: ProjectLibraryStore = ProjectLibraryStore()
    ) {
        self.projectRoot = projectRoot
        self.snapshotStore = snapshotStore
        self.projectLibraryStore = projectLibraryStore
    }

    var hasProject: Bool {
        projectRoot != nil && !isEnvironment
    }

    var hasActiveContext: Bool {
        projectRoot != nil
    }

    var selectionID: String {
        guard let projectRoot, !isEnvironment else {
            return Self.environmentSelectionID
        }
        return projectRoot.standardizedFileURL.resolvingSymlinksInPath().path
    }

    var projectName: String {
        if isEnvironment { return L("scope.thisMac") }
        guard let projectRoot else { return L("scope.openProject") }
        return projectRoot.lastPathComponent.isEmpty ? projectRoot.path : projectRoot.lastPathComponent
    }

    var activeRootPath: String? {
        projectRoot?.path
    }

    var lastRefreshLabel: String {
        guard let lastRefreshedAt else {
            return L("scan.neverRefreshed")
        }
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return String(format: L("scan.lastRefresh"), formatter.string(from: lastRefreshedAt))
    }

    func configure(refreshPolicy rawValue: String) {
        self.refreshPolicy = ScanRefreshPolicy(rawValue: rawValue) ?? .oneHour
    }

    func prepare() {
        OrbitaTelemetry.app.notice("app.ready")
        do {
            library = try projectLibraryStore.load()
            projects = library.projects
            openEnvironment()
        } catch {
            errorMessage = error.localizedDescription
            openEnvironment()
        }
    }

    func reload(force: Bool = false, preserveCurrentGraph: Bool = false) {
        guard let projectRoot else {
            OrbitaTelemetry.scan.notice("scan.skipped reason=no-project")
            if !preserveCurrentGraph {
                setGraph(nil)
            }
            errorMessage = nil
            isScanning = false
            scanMessage = nil
            scanProgress = 0
            lastRefreshedAt = nil
            return
        }

        let root = projectRoot.standardizedFileURL.resolvingSymlinksInPath()
        let startedAt = Date()
        scanTask?.cancel()
        scanTask = nil
        errorMessage = nil
        if let snapshot = try? snapshotStore.load(projectRoot: root) {
            if !preserveCurrentGraph {
                setGraph(snapshot.graph)
            }
            lastRefreshedAt = iso8601Formatter.date(from: snapshot.capturedAt)
            if !force, isSnapshotFresh(snapshot) {
                isScanning = false
                scanMessage = L("scan.usingCachedSnapshot")
                scanProgress = 1
                OrbitaTelemetry.scan.notice("snapshot.cache.hit root=\(root.path, privacy: .private)")
                return
            }
            scanMessage = L("scan.refreshingCachedSnapshot")
            scanProgress = 0.08
            OrbitaTelemetry.scan.notice("snapshot.loaded root=\(root.path, privacy: .private)")
        } else {
            if !preserveCurrentGraph {
                setGraph(nil)
            }
            lastRefreshedAt = nil
            scanMessage = String(format: L("main.loading.scanning"), projectName)
            scanProgress = 0.04
        }
        isScanning = true

        OrbitaTelemetry.scan.notice("scan.start root=\(root.path, privacy: .private)")

        let progressRelay = ScanProgressRelay(store: self, root: root)
        scanTask = Task { [weak self] in
            do {
                let graph = try await Task.detached(priority: .userInitiated) {
                    let options = ScanOptions(progressHandler: { event in
                        let count = event.count ?? -1
                        OrbitaTelemetry.scan.notice("scan.phase name=\(event.name, privacy: .public) path=\(event.path, privacy: .private) count=\(count, privacy: .public)")
                        progressRelay.receive(event)
                    })
                    let scan = try CapabilityScanner().scan(projectRoot: root, options: options)
                    return CapabilityResolver().resolve(scanResult: scan)
                }.value

                guard !Task.isCancelled else {
                    OrbitaTelemetry.scan.notice("scan.cancelled root=\(root.path, privacy: .private)")
                    return
                }

                let durationMilliseconds = Int(Date().timeIntervalSince(startedAt) * 1000)
                guard let self else { return }
                guard self.projectRoot?.standardizedFileURL.resolvingSymlinksInPath() == root else {
                    OrbitaTelemetry.scan.notice("scan.stale root=\(root.path, privacy: .private)")
                    return
                }

                self.setGraph(graph)
                self.errorMessage = nil
                self.isScanning = false
                self.scanMessage = String(format: L("scan.foundCapabilities"), graph.capabilities.count)
                self.scanProgress = 1
                self.lastRefreshedAt = Date()
                do {
                    try self.snapshotStore.save(graph)
                    OrbitaTelemetry.scan.notice("snapshot.saved root=\(root.path, privacy: .private)")
                } catch {
                    OrbitaTelemetry.scan.error("snapshot.save.failed root=\(root.path, privacy: .private) error=\(error.localizedDescription, privacy: .public)")
                }
                OrbitaTelemetry.scan.notice("scan.finish root=\(root.path, privacy: .private) capabilities=\(graph.capabilities.count, privacy: .public) issues=\(graph.issues.count, privacy: .public) durationMs=\(durationMilliseconds, privacy: .public)")
            } catch {
                let durationMilliseconds = Int(Date().timeIntervalSince(startedAt) * 1000)
                guard let self else { return }
                guard !Task.isCancelled else {
                    OrbitaTelemetry.scan.notice("scan.cancelled root=\(root.path, privacy: .private)")
                    return
                }
                self.setGraph(nil)
                self.errorMessage = error.localizedDescription
                self.isScanning = false
                self.scanMessage = nil
                self.scanProgress = 0
                OrbitaTelemetry.scan.error("scan.failed root=\(root.path, privacy: .private) durationMs=\(durationMilliseconds, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func isSnapshotFresh(_ snapshot: CapabilitySnapshot) -> Bool {
        guard let ttlMinutes = refreshPolicy.cacheTTLMinutes(isEnvironment: isEnvironment) else {
            return true
        }
        guard let capturedAt = iso8601Formatter.date(from: snapshot.capturedAt) else {
            return false
        }
        return Date().timeIntervalSince(capturedAt) < Double(ttlMinutes * 60)
    }

    private func setGraph(_ graph: CapabilityGraph?) {
        self.graph = graph
        graphRevision += 1
    }

    fileprivate func updateScanProgress(_ event: ScanProgressEvent, for root: URL) {
        guard projectRoot?.standardizedFileURL.resolvingSymlinksInPath() == root else { return }
        scanProgress = max(scanProgress, progressValue(for: event.name))
        scanMessage = scanMessage(for: event)
    }

    private func progressValue(for eventName: String) -> Double {
        switch eventName {
        case "scan.start":
            return 0.04
        case "scan.instructions.finish":
            return 0.12
        case "scan.codex.finish":
            return 0.24
        case "scan.claude.finish":
            return 0.36
        case "scan.cursor.finish":
            return 0.48
        case "scan.mcp.finish":
            return 0.58
        case "scan.agents.finish":
            return 0.68
        case "scan.skills.start":
            return 0.76
        case "scan.skills.finish":
            return 0.9
        case "scan.finish":
            return 1
        default:
            return scanProgress
        }
    }

    private func scanMessage(for event: ScanProgressEvent) -> String {
        switch event.name {
        case "scan.start":
            return String(format: L("scan.preparing"), projectName)
        case "scan.instructions.start", "scan.instructions.finish":
            return L("scan.checkingInstructions")
        case "scan.codex.start", "scan.codex.finish":
            return L("scan.checkingCodex")
        case "scan.claude.start", "scan.claude.finish":
            return L("scan.checkingClaude")
        case "scan.cursor.start", "scan.cursor.finish":
            return L("scan.checkingRules")
        case "scan.mcp.start", "scan.mcp.finish":
            return L("scan.checkingMCP")
        case "scan.agents.start", "scan.agents.finish":
            return L("scan.checkingAgents")
        case "scan.skills.start":
            return L("scan.scanningSkills")
        case "scan.skills.finish":
            if let count = event.count {
                return String(format: L("scan.scannedSkillsCount"), count)
            }
            return L("scan.scannedSkills")
        case "scan.finish":
            return L("scan.finishing")
        default:
            return scanMessage ?? String(format: L("main.loading.scanning"), projectName)
        }
    }

    func openProject(_ url: URL) {
        openProject(url, recordInLibrary: true)
    }

    private func openProject(_ url: URL, recordInLibrary: Bool) {
        OrbitaTelemetry.app.notice("project.open requested root=\(url.path, privacy: .private)")
        let root = url.standardizedFileURL.resolvingSymlinksInPath()
        isEnvironment = false
        projectRoot = root
        if recordInLibrary {
            library.upsert(projectRoot: root)
            projects = library.projects
            do {
                try projectLibraryStore.save(library)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
        reload()
    }

    func openEnvironment() {
        let root = Self.environmentRoot
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        } catch {
            errorMessage = error.localizedDescription
        }
        OrbitaTelemetry.app.notice("environment.open root=\(root.path, privacy: .private)")
        isEnvironment = true
        projectRoot = root
        reload()
    }

    func removeProject(_ project: ProjectRecord) {
        library.remove(projectPath: project.path)
        projects = library.projects
        do {
            try projectLibraryStore.save(library)
        } catch {
            errorMessage = error.localizedDescription
        }
        if selectionID == project.path {
            openEnvironment()
        }
    }

    func pinProject(_ project: ProjectRecord) {
        library.moveProjectToTop(projectPath: project.path)
        projects = library.projects
        do {
            try projectLibraryStore.save(library)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func moveProjects(from source: IndexSet, to destination: Int) {
        library.moveProjects(fromOffsets: source, toOffset: destination)
        projects = library.projects
        do {
            try projectLibraryStore.save(library)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func capability(id: String) -> Capability? {
        graph?.capabilities.first { $0.id == id }
    }

    func planEnable(_ capability: Capability, visibleTo agent: AgentSelection? = nil) -> ApplyPlan? {
        guard let graph else { return nil }
        do {
            let plan: ApplyPlan
            let capabilityIDs = scopedCapabilityIDs(for: capability, visibleTo: agent, graph: graph)
            if isVirtualGroup(capability), capabilityIDs.count > 1 {
                plan = try ApplyPlanBuilder().planEnable(
                    capabilityIDs: capabilityIDs,
                    groupID: capability.id,
                    groupName: capability.name,
                    graph: graph
                )
            } else {
                plan = try ApplyPlanBuilder().planEnable(capabilityID: capabilityIDs.first ?? capability.id, graph: graph)
            }
            OrbitaTelemetry.apply.notice("plan.enable capability=\(capability.name, privacy: .public) operations=\(plan.operations.count, privacy: .public)")
            return plan
        } catch {
            errorMessage = error.localizedDescription
            OrbitaTelemetry.apply.error("plan.enable.failed capability=\(capability.name, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    func planSync(
        _ capability: Capability,
        to agent: AgentSelection,
        mode: AgentSyncMode,
        destinationScope: AgentSyncDestinationScope
    ) -> ApplyPlan? {
        guard let graph else { return nil }
        let capabilityIDs = groupedCapabilityIDs(for: capability)
        let syncableCapabilities = graph.capabilities.filter { candidate in
            (capabilityIDs.isEmpty ? [capability.id] : capabilityIDs).contains(candidate.id)
                && candidate.type.supportsAgentSync
        }
        guard !syncableCapabilities.isEmpty else {
            return nil
        }
        guard let agentID = agent.skillsInstallAgentID else {
            return nil
        }

        do {
            let plan: ApplyPlan
            if capabilityIDs.isEmpty {
                plan = try ApplyPlanBuilder().planSyncInstallTarget(
                    capabilityID: capability.id,
                    agentID: agentID,
                    graph: graph,
                    mode: mode,
                    destinationScope: destinationScope
                )
            } else {
                plan = try ApplyPlanBuilder().planSyncInstallTargets(
                    capabilityIDs: capabilityIDs,
                    groupID: capability.id,
                    agentID: agentID,
                    graph: graph,
                    mode: mode,
                    destinationScope: destinationScope
                )
            }
            OrbitaTelemetry.apply.notice("plan.sync capability=\(capability.name, privacy: .public) agent=\(agentID, privacy: .public) mode=\(mode.rawValue, privacy: .public) scope=\(destinationScope.rawValue, privacy: .public) operations=\(plan.operations.count, privacy: .public)")
            return plan
        } catch {
            errorMessage = error.localizedDescription
            OrbitaTelemetry.apply.error("plan.sync.failed capability=\(capability.name, privacy: .public) agent=\(agentID, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    func planDisable(_ capability: Capability, visibleTo agent: AgentSelection? = nil) -> ApplyPlan? {
        guard let graph else { return nil }
        do {
            let plan: ApplyPlan
            let capabilityIDs = scopedCapabilityIDs(for: capability, visibleTo: agent, graph: graph)
            if isVirtualGroup(capability), capabilityIDs.count > 1 {
                plan = try ApplyPlanBuilder().planDisable(
                    capabilityIDs: capabilityIDs,
                    groupID: capability.id,
                    groupName: capability.name,
                    graph: graph
                )
            } else {
                plan = try ApplyPlanBuilder().planDisable(capabilityID: capabilityIDs.first ?? capability.id, graph: graph)
            }
            OrbitaTelemetry.apply.notice("plan.disable capability=\(capability.name, privacy: .public) operations=\(plan.operations.count, privacy: .public)")
            return plan
        } catch {
            errorMessage = error.localizedDescription
            OrbitaTelemetry.apply.error("plan.disable.failed capability=\(capability.name, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    func planDelete(_ capability: Capability, visibleTo agent: AgentSelection? = nil) -> ApplyPlan? {
        guard let graph else { return nil }
        do {
            let plan: ApplyPlan
            if let agent,
               let agentID = agent.skillsInstallAgentID,
               let agentScopedPlan = try? planDeleteSkillInstallTargets(
                   capability,
                   agentID: agentID,
                   graph: graph
               ) {
                plan = agentScopedPlan
            } else if isVirtualGroup(capability) {
                let childIDs = scopedCapabilityIDs(for: capability, visibleTo: agent, graph: graph)
                plan = try ApplyPlanBuilder().planDelete(
                    capabilityIDs: childIDs,
                    groupID: capability.id,
                    groupName: capability.name,
                    graph: graph
                )
            } else {
                plan = try ApplyPlanBuilder().planDelete(capabilityID: capability.id, graph: graph)
            }
            OrbitaTelemetry.apply.notice("plan.delete capability=\(capability.name, privacy: .public) operations=\(plan.operations.count, privacy: .public)")
            return plan
        } catch {
            errorMessage = error.localizedDescription
            OrbitaTelemetry.apply.error("plan.delete.failed capability=\(capability.name, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func planDeleteSkillInstallTargets(
        _ capability: Capability,
        agentID: String,
        graph: CapabilityGraph
    ) throws -> ApplyPlan {
        let capabilityIDs = groupedCapabilityIDs(for: capability)
        if capabilityIDs.isEmpty {
            return try ApplyPlanBuilder().planDeleteSkillInstallTarget(
                capabilityID: capability.id,
                agentID: agentID,
                graph: graph
            )
        }
        return try ApplyPlanBuilder().planDeleteSkillInstallTargets(
            capabilityIDs: capabilityIDs,
            groupID: capability.id,
            agentID: agentID,
            graph: graph
        )
    }

    private func isVirtualGroup(_ capability: Capability) -> Bool {
        !groupedCapabilityIDs(for: capability).isEmpty
    }

    private func scopedCapabilityIDs(for capability: Capability, visibleTo agent: AgentSelection?, graph: CapabilityGraph) -> [String] {
        var ids = groupedCapabilityIDs(for: capability)
        if ids.isEmpty {
            ids = [capability.id]
        }
        guard let agent else {
            return ids
        }
        let visibleIDs = Set(agent.visibleCapabilities(in: graph).map(\.id))
        let scoped = ids.filter { visibleIDs.contains($0) }
        return scoped.isEmpty ? ids : scoped
    }

    private func groupedCapabilityIDs(for capability: Capability) -> [String] {
        capability.metadata["childIDs"]?
            .split(separator: "\n")
            .map(String.init)
            .filter { !$0.isEmpty } ?? []
    }

    func planRollback() -> ApplyPlan? {
        guard let graph else { return nil }
        do {
            let plan = try ApplyPlanBuilder().planRollback(graph: graph)
            OrbitaTelemetry.apply.notice("plan.rollback operations=\(plan.operations.count, privacy: .public)")
            return plan
        } catch {
            errorMessage = error.localizedDescription
            OrbitaTelemetry.apply.error("plan.rollback.failed error=\(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Turns a structured ApplyExecutionError into a message that tells the user exactly which step failed
    /// and how much of a grouped/multi-target plan (e.g. a fork across several agents) was completed vs not
    /// attempted, instead of collapsing everything to a bare error string.
    @MainActor static func failureMessage(for error: ApplyExecutionError) -> String {
        var lines = [error.message]
        let completed = error.completedOperations.count
        let pending = error.pendingOperations.count
        if completed > 0 || pending > 0 {
            var summary = String(format: L("apply.failure.failedAt"), error.failedOperation.description)
            if completed > 0 {
                summary += " " + String(format: L("apply.failure.alreadyApplied"), completed)
            }
            if pending > 0 {
                summary += " " + String(format: L("apply.failure.notAttempted"), pending)
            }
            lines.append(summary)
        }
        return lines.joined(separator: "\n")
    }

    @discardableResult
    func apply(_ plan: ApplyPlan) -> Bool {
        let affectedCapabilities = affectedCapabilities(for: plan)
        let previousGraph = graph
        errorMessage = nil
        successMessage = nil

        let didOptimisticallyApply = optimisticallyApply(plan)
        let optimisticRevision = didOptimisticallyApply ? graphRevision : nil

        Task { [weak self, plan, affectedCapabilities, previousGraph, optimisticRevision] in
            let outcome = await Task.detached(priority: .userInitiated) {
                do {
                    let result = try ApplyPlanExecutor().apply(plan)
                    return ApplyExecutionOutcome.success(result)
                } catch let executionError as ApplyExecutionError {
                    return ApplyExecutionOutcome.executionFailure(executionError)
                } catch {
                    return ApplyExecutionOutcome.failure(error.localizedDescription)
                }
            }.value

            guard let self else { return }

            switch outcome {
            case let .success(result):
                self.finishApply(
                    plan,
                    result: result,
                    affectedCapabilities: affectedCapabilities,
                    optimisticRevision: optimisticRevision
                )
            case let .executionFailure(executionError):
                self.failApply(
                    plan,
                    message: Self.failureMessage(for: executionError),
                    previousGraph: previousGraph,
                    optimisticRevision: optimisticRevision
                )
            case let .failure(message):
                self.failApply(
                    plan,
                    message: message,
                    previousGraph: previousGraph,
                    optimisticRevision: optimisticRevision
                )
            }
        }

        return true
    }

    private func finishApply(
        _ plan: ApplyPlan,
        result: ApplyExecutionResult,
        affectedCapabilities: [Capability],
        optimisticRevision: Int?
    ) {
        OrbitaTelemetry.apply.notice("apply.finish action=\(plan.action.rawValue, privacy: .public) operations=\(result.completedOperations.count, privacy: .public)")
        showApplySuccess(for: plan, affectedCount: affectedCapabilities.count)
        if plan.action == .delete, isCurrentOptimisticRevision(optimisticRevision) {
            finishFastDeleteSync(affectedCapabilities: affectedCapabilities)
        } else {
            reload(force: true, preserveCurrentGraph: true)
        }
    }

    /// Publish a localized, action-aware confirmation. Count-based actions (enable/disable/delete)
    /// report how many items changed; workspace actions (merge/rollback/clean) report the operation.
    private func showApplySuccess(for plan: ApplyPlan, affectedCount: Int) {
        let count = max(affectedCount, 1)
        let message: String
        switch plan.action {
        case .enable:
            message = String(format: L("apply.success.enable"), String(count))
        case .disable:
            message = String(format: L("apply.success.disable"), String(count))
        case .delete:
            message = String(format: L("apply.success.delete"), String(count))
        case .merge:
            message = L("apply.success.merge")
        case .rollback:
            message = L("apply.success.rollback")
        case .clean:
            message = L("apply.success.clean")
        }
        successMessageToken += 1
        successMessage = message
    }

    private func failApply(
        _ plan: ApplyPlan,
        message: String,
        previousGraph: CapabilityGraph?,
        optimisticRevision: Int?
    ) {
        if isCurrentOptimisticRevision(optimisticRevision) {
            setGraph(previousGraph)
        }
        OrbitaTelemetry.apply.error("apply.failed action=\(plan.action.rawValue, privacy: .public) error=\(message, privacy: .public)")
        reload(force: true, preserveCurrentGraph: true)
        errorMessage = message
    }

    private func isCurrentOptimisticRevision(_ revision: Int?) -> Bool {
        guard let revision else { return false }
        return graphRevision == revision
    }

    func beginOptimisticMutation(
        _ mutation: CapabilityOptimisticMutation,
        capability: Capability
    ) -> CapabilityOptimisticMutationToken {
        let affectedCapabilities = affectedCapabilities(for: optimisticCapabilityIDs(for: capability))
        let previousGraph = graph
        let didOptimisticallyApply = optimisticallyApply(mutation, capability: capability)
        return CapabilityOptimisticMutationToken(
            previousGraph: previousGraph,
            optimisticRevision: didOptimisticallyApply ? graphRevision : nil,
            affectedCapabilities: affectedCapabilities.isEmpty ? [capability] : affectedCapabilities
        )
    }

    func finishOptimisticMutation(
        _ mutation: CapabilityOptimisticMutation,
        capability: Capability,
        token: CapabilityOptimisticMutationToken
    ) {
        if mutation == .delete, isCurrentOptimisticRevision(token.optimisticRevision) {
            finishFastDeleteSync(affectedCapabilities: token.affectedCapabilities)
        } else {
            reload(force: true, preserveCurrentGraph: true)
        }
    }

    func failOptimisticMutation(_ token: CapabilityOptimisticMutationToken, message: String) {
        if isCurrentOptimisticRevision(token.optimisticRevision) {
            setGraph(token.previousGraph)
        }
        reload(force: true, preserveCurrentGraph: true)
        errorMessage = message
    }

    private func affectedCapabilities(for plan: ApplyPlan) -> [Capability] {
        let affectedIDs = Set(plan.affectedCapabilityIDs ?? [plan.capabilityID])
        return affectedCapabilities(for: affectedIDs)
    }

    private func affectedCapabilities(for affectedIDs: Set<String>) -> [Capability] {
        guard let graph else { return [] }
        return graph.capabilities.filter { affectedIDs.contains($0.id) }
    }

    private func finishFastDeleteSync(affectedCapabilities: [Capability]) {
        scanTask?.cancel()
        scanTask = nil
        isScanning = false
        scanMessage = nil
        scanProgress = 0
        saveCurrentSnapshot()
        syncEnvironmentSnapshotDelete(affectedCapabilities: affectedCapabilities)
    }

    private func saveCurrentSnapshot() {
        guard let graph else { return }
        lastRefreshedAt = Date()
        do {
            try snapshotStore.save(graph)
            OrbitaTelemetry.scan.notice("snapshot.saved.fast-delete root=\(graph.projectRoot, privacy: .private)")
        } catch {
            errorMessage = error.localizedDescription
            OrbitaTelemetry.scan.error("snapshot.save.fast-delete.failed root=\(graph.projectRoot, privacy: .private) error=\(error.localizedDescription, privacy: .public)")
        }
    }

    private func syncEnvironmentSnapshotDelete(affectedCapabilities: [Capability]) {
        guard !isEnvironment else { return }
        let syncedCapabilities = affectedCapabilities.filter { $0.scope == .user || $0.risks.contains(.global) }
        guard !syncedCapabilities.isEmpty else { return }

        do {
            guard var snapshot = try snapshotStore.load(projectRoot: Self.environmentRoot) else {
                return
            }
            let affectedIDs = Set(syncedCapabilities.map(\.id))
            let affectedPaths = Set(syncedCapabilities.flatMap { capability in
                [capability.source.path, capability.metadata["sourcePath"]]
                    .compactMap { $0 }
                    .filter { !$0.isEmpty }
            })
            let initialCount = snapshot.graph.capabilities.count
            snapshot.graph.capabilities.removeAll { capability in
                affectedIDs.contains(capability.id)
                    || affectedPaths.contains(capability.source.path)
                    || affectedPaths.contains(capability.metadata["sourcePath"] ?? "")
            }
            guard snapshot.graph.capabilities.count != initialCount else { return }
            snapshot.graph.generatedAt = ISO8601DateFormatter().string(from: Date())
            try snapshotStore.save(snapshot.graph)
            OrbitaTelemetry.scan.notice("snapshot.this-mac.synced-delete capabilities=\(initialCount - snapshot.graph.capabilities.count, privacy: .public)")
        } catch {
            errorMessage = error.localizedDescription
            OrbitaTelemetry.scan.error("snapshot.this-mac.sync-delete.failed error=\(error.localizedDescription, privacy: .public)")
        }
    }

    private func optimisticallyApply(_ plan: ApplyPlan) -> Bool {
        guard var projected = graph,
              projected.projectRoot == plan.projectRoot
        else {
            return false
        }

        switch plan.action {
        case .enable:
            setStatus(.enabled, capabilityID: plan.capabilityID, in: &projected)
            applyOptimisticSkillSync(from: plan, in: &projected)
        case .disable:
            setStatus(.disabled, capabilityID: plan.capabilityID, in: &projected)
        case .delete:
            let affectedIDs = Set(plan.affectedCapabilityIDs ?? [plan.capabilityID])
            projected.capabilities.removeAll { affectedIDs.contains($0.id) }
        case .merge, .rollback, .clean:
            return false
        }

        projected.generatedAt = ISO8601DateFormatter().string(from: Date())
        setGraph(projected)
        return true
    }

    private func optimisticallyApply(_ mutation: CapabilityOptimisticMutation, capability: Capability) -> Bool {
        guard var projected = graph else {
            return false
        }

        let affectedIDs = optimisticCapabilityIDs(for: capability)
        switch mutation {
        case .enable:
            for capabilityID in affectedIDs {
                setStatus(.enabled, capabilityID: capabilityID, in: &projected)
            }
        case .disable:
            for capabilityID in affectedIDs {
                setStatus(.disabled, capabilityID: capabilityID, in: &projected)
            }
        case .delete:
            projected.capabilities.removeAll { affectedIDs.contains($0.id) }
        }

        projected.generatedAt = ISO8601DateFormatter().string(from: Date())
        setGraph(projected)
        return true
    }

    private func optimisticCapabilityIDs(for capability: Capability) -> Set<String> {
        var ids = Set(groupedCapabilityIDs(for: capability))
        ids.insert(capability.id)
        return ids
    }

    private func setStatus(_ status: CapabilityStatus, capabilityID: String, in graph: inout CapabilityGraph) {
        guard let index = graph.capabilities.firstIndex(where: { $0.id == capabilityID }) else {
            return
        }

        switch status {
        case .enabled:
            graph.capabilities[index].statuses.removeAll { $0 == .disabled }
            appendStatus(.enabled, to: &graph.capabilities[index])
        case .disabled:
            graph.capabilities[index].statuses.removeAll { $0 == .enabled }
            appendStatus(.disabled, to: &graph.capabilities[index])
        default:
            appendStatus(status, to: &graph.capabilities[index])
        }
        graph.capabilities[index].metadata["manifestStatus"] = status.rawValue
    }

    private func appendStatus(_ status: CapabilityStatus, to capability: inout Capability) {
        if !capability.statuses.contains(status) {
            capability.statuses.append(status)
        }
    }

    private func applyOptimisticSkillSync(from plan: ApplyPlan, in graph: inout CapabilityGraph) {
        guard let agentID = syncAgentID(from: plan),
              let agent = SkillsAgentCatalog.agents.first(where: { $0.id == agentID })
        else {
            return
        }

        let installTargetsByName = plan.operations
            .compactMap { operation -> (name: String, relationship: String, path: String)? in
                switch operation.kind {
                case .createSymlink:
                    let path = operation.path
                    return (URL(fileURLWithPath: path).lastPathComponent, "symlink", path)
                case .copyPath:
                    guard let path = operation.target else { return nil }
                    return (URL(fileURLWithPath: path).lastPathComponent, "copy", path)
                default:
                    return nil
                }
            }
            .reduce(into: [String: (relationship: String, path: String)]()) { result, target in
                result[target.name] = (target.relationship, target.path)
            }
        let affectedIDs = Set(plan.affectedCapabilityIDs ?? [plan.capabilityID])
        for index in graph.capabilities.indices where affectedIDs.contains(graph.capabilities[index].id) {
            guard graph.capabilities[index].type == .skill else {
                continue
            }
            let installTarget = installTargetsByName[graph.capabilities[index].name]
            appendMetadataListValue(agentID, key: "skillsInstalledAgentIDs", separator: ",", in: &graph.capabilities[index])
            appendMetadataListValue(agent.displayName, key: "skillsInstalledAgents", separator: ", ", in: &graph.capabilities[index])
            if let installTarget {
                upsertSkillInstallTarget(
                    agentID: agentID,
                    relationship: installTarget.relationship,
                    installPath: installTarget.path,
                    in: &graph.capabilities[index]
                )
            }
        }
    }

    private func syncAgentID(from plan: ApplyPlan) -> String? {
        for operation in plan.operations where operation.kind == .appendLog {
            guard let content = operation.content,
                  let range = content.range(of: " agent-target:")
            else {
                continue
            }
            let suffix = content[range.upperBound...]
            let value = suffix.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" }).first
            if let value, !value.isEmpty {
                return String(value)
            }
        }
        return nil
    }

    private func appendMetadataListValue(
        _ value: String,
        key: String,
        separator: String,
        in capability: inout Capability
    ) {
        let values = capability.metadata[key]?
            .split(separator: separator.first ?? ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty } ?? []
        guard !values.contains(value) else {
            return
        }
        capability.metadata[key] = (values + [value]).joined(separator: separator)
    }

    private func upsertSkillInstallTarget(agentID: String, relationship: String, installPath: String, in capability: inout Capability) {
        let prefix = "\(agentID)="
        var lines = capability.metadata["skillsInstallTargets"]?
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map(String.init) ?? []
        lines.removeAll { $0.hasPrefix(prefix) }
        lines.append("\(agentID)=\(relationship):\(installPath)")
        capability.metadata["skillsInstallTargets"] = lines.joined(separator: "\n")
    }
}

private final class ScanProgressRelay: @unchecked Sendable {
    weak var store: ProjectCapabilityStore?
    let root: URL

    init(store: ProjectCapabilityStore, root: URL) {
        self.store = store
        self.root = root
    }

    func receive(_ event: ScanProgressEvent) {
        Task { @MainActor [weak store, root] in
            store?.updateScanProgress(event, for: root)
        }
    }
}
