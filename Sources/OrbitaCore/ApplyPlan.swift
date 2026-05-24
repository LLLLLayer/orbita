import Foundation

public enum ApplyAction: String, Codable, Sendable {
    case enable
    case disable
    case delete
    case merge
    case rollback
    case clean
}

public enum ApplyOperationKind: String, Codable, Sendable {
    case readSource
    case createDirectory
    case createSymlink
    case removePath
    case writeFile
    case appendLog
}

public struct ApplyOperation: Codable, Hashable, Sendable {
    public var kind: ApplyOperationKind
    public var path: String
    public var target: String?
    public var content: String?
    public var risk: RiskLevel
    public var description: String

    public init(kind: ApplyOperationKind, path: String, target: String? = nil, content: String? = nil, risk: RiskLevel, description: String) {
        self.kind = kind
        self.path = path
        self.target = target
        self.content = content
        self.risk = risk
        self.description = description
    }
}

public struct ApplyExecutionResult: Codable, Sendable {
    public var schemaVersion: Int
    public var projectRoot: String
    public var completedOperations: [ApplyOperation]

    public init(schemaVersion: Int = 1, projectRoot: String, completedOperations: [ApplyOperation]) {
        self.schemaVersion = schemaVersion
        self.projectRoot = projectRoot
        self.completedOperations = completedOperations
    }
}

public struct ApplyExecutionError: Error, LocalizedError, Codable, Sendable {
    public var schemaVersion: Int
    public var projectRoot: String
    public var completedOperations: [ApplyOperation]
    public var failedOperation: ApplyOperation
    public var pendingOperations: [ApplyOperation]
    public var message: String

    public init(
        schemaVersion: Int = 1,
        projectRoot: String,
        completedOperations: [ApplyOperation],
        failedOperation: ApplyOperation,
        pendingOperations: [ApplyOperation],
        message: String
    ) {
        self.schemaVersion = schemaVersion
        self.projectRoot = projectRoot
        self.completedOperations = completedOperations
        self.failedOperation = failedOperation
        self.pendingOperations = pendingOperations
        self.message = message
    }

    public var errorDescription: String? {
        message
    }
}

public struct ApplyPlan: Codable, Identifiable, Sendable {
    public var schemaVersion: Int
    public var projectRoot: String
    public var action: ApplyAction
    public var capabilityID: String
    public var affectedCapabilityIDs: [String]?
    public var appliesChanges: Bool
    public var requiresConfirmation: Bool
    public var operations: [ApplyOperation]

    public var id: String {
        "\(action.rawValue):\(capabilityID)"
    }

    public init(
        schemaVersion: Int = 1,
        projectRoot: String,
        action: ApplyAction,
        capabilityID: String,
        affectedCapabilityIDs: [String]? = nil,
        appliesChanges: Bool = false,
        requiresConfirmation: Bool,
        operations: [ApplyOperation]
    ) {
        self.schemaVersion = schemaVersion
        self.projectRoot = projectRoot
        self.action = action
        self.capabilityID = capabilityID
        self.affectedCapabilityIDs = affectedCapabilityIDs
        self.appliesChanges = appliesChanges
        self.requiresConfirmation = requiresConfirmation
        self.operations = operations
    }
}

public final class ApplyPlanBuilder {
    public init() {}

    public func planEnable(capabilityID: String, graph: CapabilityGraph) throws -> ApplyPlan {
        guard let capability = graph.capabilities.first(where: { $0.id == capabilityID }) else {
            throw OrbitaError.capabilityNotFound(capabilityID)
        }

        let agentsRoot = URL(fileURLWithPath: graph.projectRoot).appendingPathComponent(".agents")
        var operations = baseIndexOperations(
            action: .enable,
            capability: capability,
            graph: graph,
            agentsRoot: agentsRoot
        )

        if capability.type == .skill {
            let skillsRoot = agentsRoot.appendingPathComponent("skills")
            operations.append(ApplyOperation(
                kind: .createDirectory,
                path: skillsRoot.path,
                risk: .write,
                description: "Create project skill links directory"
            ))
            operations.append(ApplyOperation(
                kind: .createSymlink,
                path: skillsRoot.appendingPathComponent(capability.name).path,
                target: skillDirectoryPath(for: capability),
                risk: .write,
                description: "Link skill into project capability index"
            ))
        }

        operations.append(contentsOf: adapterPreviewOperations(
            graph: graphWithProjectedIntent(capabilityID: capabilityID, status: .enabled, graph: graph)
        ))
        operations.append(logOperation(action: .enable, capability: capability, agentsRoot: agentsRoot))

        return ApplyPlan(
            projectRoot: graph.projectRoot,
            action: .enable,
            capabilityID: capabilityID,
            appliesChanges: false,
            requiresConfirmation: requiresConfirmation(for: capability, operations: operations),
            operations: operations
        )
    }

    public func planDisable(capabilityID: String, graph: CapabilityGraph) throws -> ApplyPlan {
        guard let capability = graph.capabilities.first(where: { $0.id == capabilityID }) else {
            throw OrbitaError.capabilityNotFound(capabilityID)
        }

        let agentsRoot = URL(fileURLWithPath: graph.projectRoot).appendingPathComponent(".agents")
        var operations = baseIndexOperations(
            action: .disable,
            capability: capability,
            graph: graph,
            agentsRoot: agentsRoot
        )

        if capability.type == .skill {
            operations.append(ApplyOperation(
                kind: .removePath,
                path: agentsRoot.appendingPathComponent("skills").appendingPathComponent(capability.name).path,
                risk: .write,
                description: "Remove project skill link without deleting source"
            ))
        }

        operations.append(contentsOf: adapterPreviewOperations(
            graph: graphWithProjectedIntent(capabilityID: capabilityID, status: .disabled, graph: graph)
        ))
        operations.append(logOperation(action: .disable, capability: capability, agentsRoot: agentsRoot))

        return ApplyPlan(
            projectRoot: graph.projectRoot,
            action: .disable,
            capabilityID: capabilityID,
            appliesChanges: false,
            requiresConfirmation: true,
            operations: operations
        )
    }

    public func planDelete(capabilityID: String, graph: CapabilityGraph) throws -> ApplyPlan {
        guard let capability = graph.capabilities.first(where: { $0.id == capabilityID }) else {
            throw OrbitaError.capabilityNotFound(capabilityID)
        }

        let agentsRoot = URL(fileURLWithPath: graph.projectRoot).appendingPathComponent(".agents")
        let remainingIntents = capabilityIntentsExcluding(capability: capability, graph: graph)
        let remainingCapabilities = remainingIntents.map(\.capability)
        var operations = [
            ApplyOperation(
                kind: .createDirectory,
                path: agentsRoot.path,
                risk: .write,
                description: "Create project capability index directory"
            ),
            ApplyOperation(
                kind: .writeFile,
                path: agentsRoot.appendingPathComponent("manifest.json").path,
                content: manifestJSON(for: remainingIntents),
                risk: .write,
                description: "Remove capability from project capability intent"
            ),
            ApplyOperation(
                kind: .writeFile,
                path: agentsRoot.appendingPathComponent("lock.json").path,
                content: lockJSON(for: remainingCapabilities),
                risk: .write,
                description: "Update resolved source, risk, and hash metadata"
            )
        ]

        var removalPathDescriptions: [String: String] = [:]
        func registerRemoval(_ path: String, description: String) {
            let normalizedPath = URL(fileURLWithPath: path).standardizedFileURL.path
            removalPathDescriptions[normalizedPath] = description
        }

        if capability.type == .skill {
            registerRemoval(
                agentsRoot.appendingPathComponent("skills").appendingPathComponent(capability.name).path,
                description: "Remove project skill link"
            )
        }
        if let managedPath = managedCapabilityPath(for: capability, agentsRoot: agentsRoot),
           managedPath != agentsRoot.appendingPathComponent("manifest.json").path {
            registerRemoval(managedPath, description: "Remove managed .agents capability path")
        }
        if let sourcePath = hardDeleteSourcePath(for: capability) {
            registerRemoval(sourcePath, description: "Hard delete capability source")
        }

        operations.append(contentsOf: removalPathDescriptions.sorted { $0.key < $1.key }.map { entry in
            ApplyOperation(
                kind: .removePath,
                path: entry.key,
                risk: .write,
                description: entry.value
            )
        })

        operations.append(contentsOf: adapterPreviewOperations(
            graph: graphWithProjectedIntent(capabilityID: capabilityID, status: .disabled, graph: graph)
        ))
        operations.append(logOperation(action: .delete, capability: capability, agentsRoot: agentsRoot))

        return ApplyPlan(
            projectRoot: graph.projectRoot,
            action: .delete,
            capabilityID: capabilityID,
            appliesChanges: false,
            requiresConfirmation: true,
            operations: operations
        )
    }

    public func planDelete(
        capabilityIDs: [String],
        groupID: String,
        groupName: String,
        graph: CapabilityGraph
    ) throws -> ApplyPlan {
        let selectedIDs = Set(capabilityIDs)
        let capabilities = graph.capabilities
            .filter { selectedIDs.contains($0.id) }
            .sorted { $0.id < $1.id }
        guard !capabilities.isEmpty else {
            throw OrbitaError.capabilityNotFound(groupID)
        }

        let agentsRoot = URL(fileURLWithPath: graph.projectRoot).appendingPathComponent(".agents")
        let selectedManifestIDs = Set(capabilities.map { manifestCapabilityID(for: $0) })
        let remainingIntents = capabilityIntentsExcluding(manifestIDs: selectedManifestIDs, graph: graph)
        let remainingCapabilities = remainingIntents.map(\.capability)
        var operations = [
            ApplyOperation(
                kind: .createDirectory,
                path: agentsRoot.path,
                risk: .write,
                description: "Create project capability index directory"
            ),
            ApplyOperation(
                kind: .writeFile,
                path: agentsRoot.appendingPathComponent("manifest.json").path,
                content: manifestJSON(for: remainingIntents),
                risk: .write,
                description: "Remove grouped capabilities from project capability intent"
            ),
            ApplyOperation(
                kind: .writeFile,
                path: agentsRoot.appendingPathComponent("lock.json").path,
                content: lockJSON(for: remainingCapabilities),
                risk: .write,
                description: "Update resolved source, risk, and hash metadata"
            )
        ]

        var removalPathDescriptions: [String: String] = [:]
        func registerRemoval(_ path: String, description: String) {
            let normalizedPath = URL(fileURLWithPath: path).standardizedFileURL.path
            removalPathDescriptions[normalizedPath] = description
        }

        for capability in capabilities {
            if capability.type == .skill {
                registerRemoval(
                    agentsRoot.appendingPathComponent("skills").appendingPathComponent(capability.name).path,
                    description: "Remove grouped project skill link"
                )
            }
            if let managedPath = managedCapabilityPath(for: capability, agentsRoot: agentsRoot),
               managedPath != agentsRoot.appendingPathComponent("manifest.json").path {
                registerRemoval(managedPath, description: "Remove managed grouped capability path")
            }
            if let sourcePath = hardDeleteSourcePath(for: capability) {
                registerRemoval(sourcePath, description: "Hard delete grouped capability source")
            }
        }

        operations.append(contentsOf: removalPathDescriptions.sorted { $0.key < $1.key }.map { entry in
            ApplyOperation(
                kind: .removePath,
                path: entry.key,
                risk: .write,
                description: entry.value
            )
        })

        let projected = capabilities.reduce(graph) { partialGraph, capability in
            graphWithProjectedIntent(capabilityID: capability.id, status: .disabled, graph: partialGraph)
        }
        operations.append(contentsOf: adapterPreviewOperations(graph: projected))
        operations.append(ApplyOperation(
            kind: .appendLog,
            path: agentsRoot.appendingPathComponent("logs/apply.log").path,
            content: "\(ISO8601DateFormatter().string(from: Date())) delete \(groupID)\n",
            risk: .write,
            description: "Append grouped delete operation log"
        ))

        return ApplyPlan(
            projectRoot: graph.projectRoot,
            action: .delete,
            capabilityID: groupID,
            affectedCapabilityIDs: capabilities.map(\.id),
            appliesChanges: false,
            requiresConfirmation: requiresConfirmation(for: capabilities, operations: operations),
            operations: operations
        )
    }

    public func planRollback(graph: CapabilityGraph) throws -> ApplyPlan {
        let agentsRoot = URL(fileURLWithPath: graph.projectRoot).appendingPathComponent(".agents")
        let logPath = agentsRoot.appendingPathComponent("logs/apply.log").path
        guard let lastEntry = try readLastApplyLogEntry(at: logPath) else {
            throw OrbitaError.invalidApplyPlan("No apply log entries to rollback")
        }

        let inverseAction: ApplyAction
        switch lastEntry.action {
        case .enable:
            inverseAction = .disable
        case .disable:
            inverseAction = .enable
        case .delete, .merge, .rollback, .clean:
            throw OrbitaError.invalidApplyPlan("Cannot rollback a \(lastEntry.action.rawValue) entry")
        }

        guard let capability = graph.capabilities.first(where: { $0.id == lastEntry.capabilityID }) else {
            throw OrbitaError.capabilityNotFound(lastEntry.capabilityID)
        }

        var operations = baseIndexOperations(
            action: inverseAction,
            capability: capability,
            graph: graph,
            agentsRoot: agentsRoot
        )

        if capability.type == .skill {
            switch inverseAction {
            case .enable:
                let skillsRoot = agentsRoot.appendingPathComponent("skills")
                operations.append(ApplyOperation(
                    kind: .createDirectory,
                    path: skillsRoot.path,
                    risk: .write,
                    description: "Create project skill links directory"
                ))
                operations.append(ApplyOperation(
                    kind: .createSymlink,
                    path: skillsRoot.appendingPathComponent(capability.name).path,
                    target: skillDirectoryPath(for: capability),
                    risk: .write,
                    description: "Restore project skill link"
                ))
            case .disable:
                operations.append(ApplyOperation(
                    kind: .removePath,
                    path: agentsRoot.appendingPathComponent("skills").appendingPathComponent(capability.name).path,
                    risk: .write,
                    description: "Remove project skill link during rollback"
                ))
            case .delete, .merge, .rollback, .clean:
                break
            }
        }

        let projectedStatus: CapabilityStatus = inverseAction == .enable ? .enabled : .disabled
        operations.append(contentsOf: adapterPreviewOperations(
            graph: graphWithProjectedIntent(capabilityID: capability.id, status: projectedStatus, graph: graph)
        ))
        operations.append(ApplyOperation(
            kind: .appendLog,
            path: logPath,
            content: "\(ISO8601DateFormatter().string(from: Date())) rollback \(capability.id) inverse:\(inverseAction.rawValue)\n",
            risk: .write,
            description: "Append rollback operation log"
        ))

        return ApplyPlan(
            projectRoot: graph.projectRoot,
            action: .rollback,
            capabilityID: capability.id,
            appliesChanges: false,
            requiresConfirmation: true,
            operations: operations
        )
    }

    public func planMerge(graph: CapabilityGraph) throws -> ApplyPlan {
        let agentsRoot = URL(fileURLWithPath: graph.projectRoot).appendingPathComponent(".agents")
        let capabilities = graph.capabilities
            .filter { capability in
                capability.scope == .project
                    && !capability.statuses.contains(.broken)
                    && !capability.source.kind.hasPrefix("agents-")
            }
            .sorted { $0.id < $1.id }

        guard !capabilities.isEmpty else {
            return ApplyPlan(
                projectRoot: graph.projectRoot,
                action: .merge,
                capabilityID: "workspace",
                appliesChanges: false,
                requiresConfirmation: false,
                operations: []
            )
        }

        var operations: [ApplyOperation] = capabilities.map { capability in
            ApplyOperation(
                kind: .readSource,
                path: capability.source.path,
                risk: .read,
                description: "Read capability source before merging"
            )
        }

        operations.append(ApplyOperation(
            kind: .createDirectory,
            path: agentsRoot.path,
            risk: .write,
            description: "Create project capability index directory"
        ))
        operations.append(ApplyOperation(
            kind: .writeFile,
            path: agentsRoot.appendingPathComponent("manifest.json").path,
            content: manifestJSON(for: capabilities, status: .enabled),
            risk: .write,
            description: "Record merged project capability intent"
        ))
        operations.append(ApplyOperation(
            kind: .writeFile,
            path: agentsRoot.appendingPathComponent("lock.json").path,
            content: lockJSON(for: capabilities),
            risk: .write,
            description: "Record merged source, risk, and hash metadata"
        ))

        let skills = capabilities.filter { $0.type == .skill }
        if !skills.isEmpty {
            let skillsRoot = agentsRoot.appendingPathComponent("skills")
            operations.append(ApplyOperation(
                kind: .createDirectory,
                path: skillsRoot.path,
                risk: .write,
                description: "Create project skill links directory"
            ))
            for skill in skills {
                operations.append(ApplyOperation(
                    kind: .createSymlink,
                    path: skillsRoot.appendingPathComponent(skill.name).path,
                    target: skillDirectoryPath(for: skill),
                    risk: .write,
                    description: "Link skill into merged project capability index"
                ))
            }
        }

        for agent in AgentID.allCases {
            let preview = AdapterPreviewBuilder().preview(for: agent, graph: graph)
            for generatedFile in preview.generatedFiles {
                operations.append(ApplyOperation(
                    kind: .writeFile,
                    path: generatedFile.path,
                    content: generatedFile.content,
                    risk: .write,
                    description: "Write \(agent.rawValue) adapter preview"
                ))
            }
        }

        operations.append(ApplyOperation(
            kind: .appendLog,
            path: agentsRoot.appendingPathComponent("logs/apply.log").path,
            content: "\(ISO8601DateFormatter().string(from: Date())) merge workspace\n",
            risk: .write,
            description: "Append merge operation log"
        ))

        return ApplyPlan(
            projectRoot: graph.projectRoot,
            action: .merge,
            capabilityID: "workspace",
            appliesChanges: false,
            requiresConfirmation: requiresConfirmation(for: capabilities, operations: operations),
            operations: operations
        )
    }

    public func planClean(graph: CapabilityGraph) throws -> ApplyPlan {
        let agentsRoot = URL(fileURLWithPath: graph.projectRoot).appendingPathComponent(".agents")
        var operations = graph.capabilities
            .filter { $0.statuses.contains(.broken) && $0.source.kind == "agents-symlink" }
            .map { capability in
                ApplyOperation(
                    kind: .removePath,
                    path: capability.source.path,
                    risk: .write,
                    description: "Remove broken .agents symlink"
                )
            }

        let activeCapabilityIDs = Set(graph.capabilities
            .filter { capability in
                !capability.statuses.contains(.disabled)
                    && !capability.statuses.contains(.broken)
            }
            .map(\.id))
        operations.append(contentsOf: staleAdapterCleanOperations(
            agentsRoot: agentsRoot,
            activeCapabilityIDs: activeCapabilityIDs
        ))

        let removalCount = operations.count
        if removalCount > 0 {
            operations.append(ApplyOperation(
                kind: .appendLog,
                path: agentsRoot.appendingPathComponent("logs/apply.log").path,
                content: "\(ISO8601DateFormatter().string(from: Date())) clean workspace removed:\(removalCount)\n",
                risk: .write,
                description: "Append clean operation log"
            ))
        }

        return ApplyPlan(
            projectRoot: graph.projectRoot,
            action: .clean,
            capabilityID: "workspace",
            appliesChanges: false,
            requiresConfirmation: removalCount > 0,
            operations: operations
        )
    }

    private func adapterPreviewOperations(graph: CapabilityGraph) -> [ApplyOperation] {
        AgentID.allCases.flatMap { agent in
            AdapterPreviewBuilder().preview(for: agent, graph: graph).generatedFiles.map { generatedFile in
                ApplyOperation(
                    kind: .writeFile,
                    path: generatedFile.path,
                    content: generatedFile.content,
                    risk: .write,
                    description: "Write \(agent.rawValue) adapter preview"
                )
            }
        }
    }

    private func graphWithProjectedIntent(capabilityID: String, status: CapabilityStatus, graph: CapabilityGraph) -> CapabilityGraph {
        var projected = graph
        guard let index = projected.capabilities.firstIndex(where: { $0.id == capabilityID }) else {
            return projected
        }

        switch status {
        case .enabled:
            projected.capabilities[index].statuses.removeAll { $0 == .disabled }
            appendStatus(.enabled, to: &projected.capabilities[index])
        case .disabled:
            projected.capabilities[index].statuses.removeAll { $0 == .enabled }
            appendStatus(.disabled, to: &projected.capabilities[index])
        default:
            appendStatus(status, to: &projected.capabilities[index])
        }
        projected.capabilities[index].metadata["manifestStatus"] = status.rawValue
        return projected
    }

    private func appendStatus(_ status: CapabilityStatus, to capability: inout Capability) {
        if !capability.statuses.contains(status) {
            capability.statuses.append(status)
        }
    }

    private func staleAdapterCleanOperations(agentsRoot: URL, activeCapabilityIDs: Set<String>) -> [ApplyOperation] {
        let adaptersRoot = agentsRoot.appendingPathComponent("adapters")
        guard let agentDirectories = try? FileManager.default.contentsOfDirectory(
            at: adaptersRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return agentDirectories.compactMap { agentDirectory in
            let file = agentDirectory.appendingPathComponent("capabilities.json")
            guard FileManager.default.fileExists(atPath: file.path) else {
                return nil
            }
            guard adapterFileReferencesOnlyActiveCapabilities(file, activeCapabilityIDs: activeCapabilityIDs) else {
                return ApplyOperation(
                    kind: .removePath,
                    path: file.path,
                    risk: .write,
                    description: "Remove stale adapter file referencing missing or disabled capabilities"
                )
            }
            return nil
        }
    }

    private func adapterFileReferencesOnlyActiveCapabilities(_ file: URL, activeCapabilityIDs: Set<String>) -> Bool {
        guard let data = try? Data(contentsOf: file),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return false
        }

        let capabilityIDs = ids(in: object["capabilities"], key: "id")
        let mappingIDs = ids(in: object["mappings"], key: "capabilityID")
        let referencedIDs = capabilityIDs.union(mappingIDs)
        return referencedIDs.allSatisfy { activeCapabilityIDs.contains($0) }
    }

    private func ids(in value: Any?, key: String) -> Set<String> {
        guard let objects = value as? [[String: Any]] else {
            return []
        }
        return Set(objects.compactMap { $0[key] as? String })
    }

    private func baseIndexOperations(action: ApplyAction, capability: Capability, graph: CapabilityGraph, agentsRoot: URL) -> [ApplyOperation] {
        let capabilityIntents = projectedCapabilityIntents(action: action, capability: capability, graph: graph)
        let indexedCapabilities = capabilityIntents.map(\.capability)
        return [
            ApplyOperation(
                kind: .readSource,
                path: capability.source.path,
                risk: .read,
                description: "Read capability source before indexing"
            ),
            ApplyOperation(
                kind: .createDirectory,
                path: agentsRoot.path,
                risk: .write,
                description: "Create project capability index directory"
            ),
            ApplyOperation(
                kind: .writeFile,
                path: agentsRoot.appendingPathComponent("manifest.json").path,
                content: manifestJSON(for: capabilityIntents),
                risk: .write,
                description: "Record \(action.rawValue) capability intent"
            ),
            ApplyOperation(
                kind: .writeFile,
                path: agentsRoot.appendingPathComponent("lock.json").path,
                content: lockJSON(for: indexedCapabilities),
                risk: .write,
                description: "Record resolved source, risk, and hash metadata"
            )
        ]
    }

    private func projectedCapabilityIntents(
        action: ApplyAction,
        capability selectedCapability: Capability,
        graph: CapabilityGraph
    ) -> [(capability: Capability, status: CapabilityStatus)] {
        let selectedStatus: CapabilityStatus = action == .enable ? .enabled : .disabled
        var values: [(capability: Capability, status: CapabilityStatus)] = graph.capabilities.compactMap { capability -> (capability: Capability, status: CapabilityStatus)? in
            guard capability.id == selectedCapability.id || capability.metadata["manifestStatus"] != nil else {
                return nil
            }
            guard !capability.source.kind.hasPrefix("agents-") else {
                return nil
            }
            if capability.id == selectedCapability.id {
                return (capability: capability, status: selectedStatus)
            }
            let status = capability.metadata["manifestStatus"].flatMap(CapabilityStatus.init(rawValue:)) ?? .enabled
            return (capability: capability, status: status)
        }

        if !values.contains(where: { $0.capability.id == selectedCapability.id }) {
            values.append((capability: selectedCapability, status: selectedStatus))
        }

        return values.sorted { lhs, rhs in
            lhs.capability.id < rhs.capability.id
        }
    }

    private func capabilityIntentsExcluding(
        capability selectedCapability: Capability,
        graph: CapabilityGraph
    ) -> [(capability: Capability, status: CapabilityStatus)] {
        capabilityIntentsExcluding(manifestIDs: [manifestCapabilityID(for: selectedCapability)], graph: graph)
    }

    private func capabilityIntentsExcluding(
        manifestIDs selectedManifestIDs: Set<String>,
        graph: CapabilityGraph
    ) -> [(capability: Capability, status: CapabilityStatus)] {
        var seenIDs: Set<String> = []
        let values = graph.capabilities.compactMap { capability -> (capability: Capability, status: CapabilityStatus)? in
            guard let manifestStatus = capability.metadata["manifestStatus"].flatMap(CapabilityStatus.init(rawValue:)) else {
                return nil
            }

            let manifestID = manifestCapabilityID(for: capability)
            guard !selectedManifestIDs.contains(manifestID), !seenIDs.contains(manifestID) else {
                return nil
            }
            seenIDs.insert(manifestID)
            return (capability: capability, status: manifestStatus)
        }

        return values.sorted { lhs, rhs in
            manifestCapabilityID(for: lhs.capability) < manifestCapabilityID(for: rhs.capability)
        }
    }

    private func requiresConfirmation(for capability: Capability, operations: [ApplyOperation]) -> Bool {
        let operationRisks = operations.map(\.risk)
        let allRisks = Set(capability.risks + operationRisks)
        return !allRisks.isDisjoint(with: [.exec, .network, .secret, .write, .global])
    }

    private func requiresConfirmation(for capabilities: [Capability], operations: [ApplyOperation]) -> Bool {
        let capabilityRisks = capabilities.flatMap(\.risks)
        let operationRisks = operations.map(\.risk)
        let allRisks = Set(capabilityRisks + operationRisks)
        return !allRisks.isDisjoint(with: [.exec, .network, .secret, .write, .global])
    }

    private func skillDirectoryPath(for capability: Capability) -> String {
        if capability.source.path.hasSuffix("/SKILL.md") {
            return String(capability.source.path.dropLast("/SKILL.md".count))
        }
        return capability.source.path
    }

    private func managedCapabilityPath(for capability: Capability, agentsRoot: URL) -> String? {
        let sourcePath = URL(fileURLWithPath: capability.source.path).standardizedFileURL.path
        let rootPath = agentsRoot.standardizedFileURL.path
        guard sourcePath == rootPath || sourcePath.hasPrefix(rootPath + "/") else {
            return nil
        }
        return sourcePath
    }

    private func hardDeleteSourcePath(for capability: Capability) -> String? {
        let path = capability.source.path
        guard !path.isEmpty, path != "-" else {
            return nil
        }
        if capability.type == .skill, path.hasSuffix("/SKILL.md") {
            return URL(fileURLWithPath: path)
                .deletingLastPathComponent()
                .standardizedFileURL
                .path
        }
        return URL(fileURLWithPath: path).standardizedFileURL.path
    }

    private func manifestCapabilityID(for capability: Capability) -> String {
        capability.metadata["capabilityID"] ?? capability.id
    }

    private func manifestSourcePath(for capability: Capability) -> String {
        capability.metadata["sourcePath"] ?? capability.source.path
    }

    private func manifestJSON(for capability: Capability, status: CapabilityStatus) -> String {
        manifestJSON(for: [capability], status: status)
    }

    private func manifestJSON(for capabilities: [Capability], status: CapabilityStatus) -> String {
        manifestJSON(for: capabilities.map { ($0, status) })
    }

    private func manifestJSON(for capabilityIntents: [(capability: Capability, status: CapabilityStatus)]) -> String {
        let object: [String: Any] = [
            "schemaVersion": 1,
            "capabilities": capabilityIntents.map { entry in
                [
                    "id": manifestCapabilityID(for: entry.capability),
                    "name": entry.capability.name,
                    "type": entry.capability.type.rawValue,
                    "status": entry.status.rawValue,
                    "sourcePath": manifestSourcePath(for: entry.capability)
                ] as [String: Any]
            }
        ]
        return prettyJSONString(object)
    }

    private func lockJSON(for capability: Capability) -> String {
        lockJSON(for: [capability])
    }

    private func lockJSON(for capabilities: [Capability]) -> String {
        let object: [String: Any] = [
            "schemaVersion": 1,
            "capabilities": capabilities.map { capability in
                [
                    "id": capability.id,
                    "sourcePath": manifestSourcePath(for: capability),
                    "contentHash": capability.metadata["contentHash"] ?? "",
                    "risks": capability.risks.map(\.rawValue)
                ] as [String: Any]
            }
        ]
        return prettyJSONString(object)
    }

    private func prettyJSONString(_ object: [String: Any]) -> String {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
              let text = String(data: data, encoding: .utf8) else {
            return "{}\n"
        }
        return text.replacingOccurrences(of: "\\/", with: "/") + "\n"
    }

    private func logOperation(action: ApplyAction, capability: Capability, agentsRoot: URL) -> ApplyOperation {
        ApplyOperation(
            kind: .appendLog,
            path: agentsRoot.appendingPathComponent("logs/apply.log").path,
            content: "\(ISO8601DateFormatter().string(from: Date())) \(action.rawValue) \(capability.id)\n",
            risk: .write,
            description: "Append apply operation log"
        )
    }

    private func readLastApplyLogEntry(at path: String) throws -> (action: ApplyAction, capabilityID: String)? {
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else {
            return nil
        }
        let lines = text.split(separator: "\n").reversed()
        for line in lines {
            let parts = line.split(separator: " ", maxSplits: 2).map(String.init)
            guard parts.count == 3, let action = ApplyAction(rawValue: parts[1]), action != .rollback else {
                continue
            }
            return (action, parts[2])
        }
        return nil
    }
}

public final class ApplyPlanExecutor {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func apply(_ plan: ApplyPlan) throws -> ApplyExecutionResult {
        let agentsRoot = URL(fileURLWithPath: plan.projectRoot).appendingPathComponent(".agents").standardizedFileURL
        var completed: [ApplyOperation] = []

        for (index, operation) in plan.operations.enumerated() {
            do {
                try validate(operation: operation, action: plan.action, agentsRoot: agentsRoot)
                try perform(operation)
                completed.append(operation)
            } catch {
                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                throw ApplyExecutionError(
                    projectRoot: plan.projectRoot,
                    completedOperations: completed,
                    failedOperation: operation,
                    pendingOperations: Array(plan.operations.dropFirst(index + 1)),
                    message: message
                )
            }
        }

        return ApplyExecutionResult(projectRoot: plan.projectRoot, completedOperations: completed)
    }

    private func perform(_ operation: ApplyOperation) throws {
        switch operation.kind {
        case .readSource:
            _ = fileManager.fileExists(atPath: operation.path)
        case .createDirectory:
            try fileManager.createDirectory(atPath: operation.path, withIntermediateDirectories: true, attributes: nil)
        case .writeFile:
            guard let content = operation.content else {
                throw OrbitaError.invalidApplyPlan("Missing write content for \(operation.path)")
            }
            let parent = URL(fileURLWithPath: operation.path).deletingLastPathComponent()
            try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
            try content.write(toFile: operation.path, atomically: true, encoding: .utf8)
        case .appendLog:
            guard let content = operation.content else {
                throw OrbitaError.invalidApplyPlan("Missing log content for \(operation.path)")
            }
            let parent = URL(fileURLWithPath: operation.path).deletingLastPathComponent()
            try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
            if fileManager.fileExists(atPath: operation.path) {
                let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: operation.path))
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: Data(content.utf8))
            } else {
                try content.write(toFile: operation.path, atomically: true, encoding: .utf8)
            }
        case .createSymlink:
            guard let target = operation.target else {
                throw OrbitaError.invalidApplyPlan("Missing symlink target for \(operation.path)")
            }
            let parent = URL(fileURLWithPath: operation.path).deletingLastPathComponent()
            try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
            if let existing = try? fileManager.destinationOfSymbolicLink(atPath: operation.path) {
                guard existing == target else {
                    throw OrbitaError.invalidApplyPlan("Path already exists with different target: \(operation.path)")
                }
            } else if fileManager.fileExists(atPath: operation.path) {
                throw OrbitaError.invalidApplyPlan("Path already exists and is not a symlink: \(operation.path)")
            } else {
                try fileManager.createSymbolicLink(atPath: operation.path, withDestinationPath: target)
            }
        case .removePath:
            if fileManager.fileExists(atPath: operation.path) || (try? fileManager.destinationOfSymbolicLink(atPath: operation.path)) != nil {
                try fileManager.removeItem(atPath: operation.path)
            }
        }
    }

    private func validate(operation: ApplyOperation, action: ApplyAction, agentsRoot: URL) throws {
        guard operation.kind != .readSource else { return }
        if action == .delete, operation.kind == .removePath {
            return
        }
        let operationPath = normalizedContainmentPath(URL(fileURLWithPath: operation.path).standardizedFileURL.path)
        let rootPath = normalizedContainmentPath(agentsRoot.standardizedFileURL.path)
        let agentsPath = rootPath + "/"
        guard operationPath == rootPath || operationPath.hasPrefix(agentsPath) else {
            throw OrbitaError.invalidApplyPlan("Operation is outside .agents: \(operation.path)")
        }
    }

    private func normalizedContainmentPath(_ path: String) -> String {
        if path.hasPrefix("/private/var/") {
            return String(path.dropFirst("/private".count))
        }
        return path
    }
}
