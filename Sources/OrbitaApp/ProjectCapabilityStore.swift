import Foundation
import OrbitaCore

@MainActor
final class ProjectCapabilityStore: ObservableObject {
    static let environmentSelectionID = "environment"
    static let environmentRoot = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".orbita/this-mac", isDirectory: true)
        .standardizedFileURL
        .resolvingSymlinksInPath()

    @Published var graph: CapabilityGraph?
    @Published var errorMessage: String?
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
        if isEnvironment { return "This Mac" }
        guard let projectRoot else { return "Open a project" }
        return projectRoot.lastPathComponent.isEmpty ? projectRoot.path : projectRoot.lastPathComponent
    }

    var activeRootPath: String? {
        projectRoot?.path
    }

    var lastRefreshLabel: String {
        guard let lastRefreshedAt else {
            return "Never refreshed"
        }
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return "Last refresh \(formatter.string(from: lastRefreshedAt))"
    }

    func configure(refreshPolicy rawValue: String) {
        self.refreshPolicy = ScanRefreshPolicy(rawValue: rawValue) ?? .oneHour
    }

    func prepare() {
        OrbitaTelemetry.app.notice("app.ready")
        do {
            library = try projectLibraryStore.load()
            projects = library.projects
            if let lastProjectPath = library.lastProjectPath,
               FileManager.default.fileExists(atPath: lastProjectPath) {
                openProject(URL(fileURLWithPath: lastProjectPath), recordInLibrary: false)
            } else {
                openEnvironment()
            }
        } catch {
            errorMessage = error.localizedDescription
            openEnvironment()
        }
    }

    func reload(force: Bool = false, preserveCurrentGraph: Bool = false) {
        guard let projectRoot else {
            OrbitaTelemetry.scan.notice("scan.skipped reason=no-project")
            if !preserveCurrentGraph {
                graph = nil
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
                graph = snapshot.graph
            }
            lastRefreshedAt = iso8601Formatter.date(from: snapshot.capturedAt)
            if !force, isSnapshotFresh(snapshot) {
                isScanning = false
                scanMessage = "Using cached snapshot"
                scanProgress = 1
                OrbitaTelemetry.scan.notice("snapshot.cache.hit root=\(root.path, privacy: .private)")
                return
            }
            scanMessage = "Refreshing cached snapshot"
            scanProgress = 0.08
            OrbitaTelemetry.scan.notice("snapshot.loaded root=\(root.path, privacy: .private)")
        } else {
            if !preserveCurrentGraph {
                graph = nil
            }
            lastRefreshedAt = nil
            scanMessage = "Scanning \(projectName)"
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

                self.graph = graph
                self.errorMessage = nil
                self.isScanning = false
                self.scanMessage = "Found \(graph.capabilities.count) capabilities"
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
                self.graph = nil
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
            return "Preparing \(projectName)"
        case "scan.instructions.start", "scan.instructions.finish":
            return "Checking project instructions"
        case "scan.codex.start", "scan.codex.finish":
            return "Checking Codex"
        case "scan.claude.start", "scan.claude.finish":
            return "Checking Claude Code"
        case "scan.cursor.start", "scan.cursor.finish":
            return "Checking project rules"
        case "scan.mcp.start", "scan.mcp.finish":
            return "Checking MCP"
        case "scan.agents.start", "scan.agents.finish":
            return "Checking .agents"
        case "scan.skills.start":
            return "Scanning skills"
        case "scan.skills.finish":
            if let count = event.count {
                return "Scanned skills - \(count) found"
            }
            return "Scanned skills"
        case "scan.finish":
            return "Finishing scan"
        default:
            return scanMessage ?? "Scanning \(projectName)"
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

    func planEnable(_ capability: Capability) -> ApplyPlan? {
        guard let graph else { return nil }
        do {
            let plan = try ApplyPlanBuilder().planEnable(capabilityID: capability.id, graph: graph)
            OrbitaTelemetry.apply.notice("plan.enable capability=\(capability.name, privacy: .public) operations=\(plan.operations.count, privacy: .public)")
            return plan
        } catch {
            errorMessage = error.localizedDescription
            OrbitaTelemetry.apply.error("plan.enable.failed capability=\(capability.name, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    func planDisable(_ capability: Capability) -> ApplyPlan? {
        guard let graph else { return nil }
        do {
            let plan = try ApplyPlanBuilder().planDisable(capabilityID: capability.id, graph: graph)
            OrbitaTelemetry.apply.notice("plan.disable capability=\(capability.name, privacy: .public) operations=\(plan.operations.count, privacy: .public)")
            return plan
        } catch {
            errorMessage = error.localizedDescription
            OrbitaTelemetry.apply.error("plan.disable.failed capability=\(capability.name, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    func planDelete(_ capability: Capability) -> ApplyPlan? {
        guard let graph else { return nil }
        do {
            let plan: ApplyPlan
            if capability.source.kind == "virtual-plugin" {
                let childIDs = groupedCapabilityIDs(for: capability)
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

    private func groupedCapabilityIDs(for capability: Capability) -> [String] {
        capability.metadata["childIDs"]?
            .split(separator: "\n")
            .map(String.init) ?? []
    }

    func planMerge() -> ApplyPlan? {
        guard let graph else { return nil }
        do {
            let plan = try ApplyPlanBuilder().planMerge(graph: graph)
            OrbitaTelemetry.apply.notice("plan.merge operations=\(plan.operations.count, privacy: .public)")
            return plan
        } catch {
            errorMessage = error.localizedDescription
            OrbitaTelemetry.apply.error("plan.merge.failed error=\(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    func planClean() -> ApplyPlan? {
        guard let graph else { return nil }
        do {
            let plan = try ApplyPlanBuilder().planClean(graph: graph)
            OrbitaTelemetry.apply.notice("plan.clean operations=\(plan.operations.count, privacy: .public)")
            return plan
        } catch {
            errorMessage = error.localizedDescription
            OrbitaTelemetry.apply.error("plan.clean.failed error=\(error.localizedDescription, privacy: .public)")
            return nil
        }
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

    @discardableResult
    func apply(_ plan: ApplyPlan) -> Bool {
        let affectedCapabilities = affectedCapabilities(for: plan)
        errorMessage = nil
        do {
            let result = try ApplyPlanExecutor().apply(plan)
            OrbitaTelemetry.apply.notice("apply.finish action=\(plan.action.rawValue, privacy: .public) operations=\(result.completedOperations.count, privacy: .public)")
            optimisticallyApply(plan)
            if plan.action == .delete {
                finishFastDeleteSync(affectedCapabilities: affectedCapabilities)
            } else {
                reload(force: true, preserveCurrentGraph: true)
            }
            return true
        } catch {
            errorMessage = error.localizedDescription
            OrbitaTelemetry.apply.error("apply.failed action=\(plan.action.rawValue, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    private func affectedCapabilities(for plan: ApplyPlan) -> [Capability] {
        guard let graph else { return [] }
        let affectedIDs = Set(plan.affectedCapabilityIDs ?? [plan.capabilityID])
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

    private func optimisticallyApply(_ plan: ApplyPlan) {
        guard var projected = graph,
              projected.projectRoot == plan.projectRoot
        else {
            return
        }

        switch plan.action {
        case .enable:
            setStatus(.enabled, capabilityID: plan.capabilityID, in: &projected)
        case .disable:
            setStatus(.disabled, capabilityID: plan.capabilityID, in: &projected)
        case .delete:
            let affectedIDs = Set(plan.affectedCapabilityIDs ?? [plan.capabilityID])
            projected.capabilities.removeAll { affectedIDs.contains($0.id) }
        case .merge, .rollback, .clean:
            return
        }

        projected.generatedAt = ISO8601DateFormatter().string(from: Date())
        graph = projected
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
