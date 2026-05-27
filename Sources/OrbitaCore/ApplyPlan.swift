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
    case cachePath
    case restorePath
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
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func planEnable(capabilityID: String, graph: CapabilityGraph) throws -> ApplyPlan {
        guard let capability = graph.capabilities.first(where: { $0.id == capabilityID }) else {
            throw OrbitaError.capabilityNotFound(capabilityID)
        }

        return try planStatusChange(action: .enable, capabilities: [capability], planCapabilityID: capabilityID, graph: graph)
    }

    public func planEnable(
        capabilityIDs: [String],
        groupID: String,
        groupName: String,
        graph: CapabilityGraph
    ) throws -> ApplyPlan {
        let capabilities = try capabilities(matching: capabilityIDs, fallbackID: groupID, graph: graph)
        return try planStatusChange(action: .enable, capabilities: capabilities, planCapabilityID: groupID, graph: graph)
    }

    public func planSyncSkillInstallTarget(
        capabilityID: String,
        agentID: String,
        graph: CapabilityGraph
    ) throws -> ApplyPlan {
        let capabilities = try capabilities(matching: [capabilityID], fallbackID: capabilityID, graph: graph)
        return try planSyncSkillInstallTargets(
            capabilities: capabilities,
            planCapabilityID: capabilityID,
            agentID: agentID,
            graph: graph
        )
    }

    public func planSyncSkillInstallTargets(
        capabilityIDs: [String],
        groupID: String,
        agentID: String,
        graph: CapabilityGraph
    ) throws -> ApplyPlan {
        let capabilities = try capabilities(matching: capabilityIDs, fallbackID: groupID, graph: graph)
        return try planSyncSkillInstallTargets(
            capabilities: capabilities,
            planCapabilityID: groupID,
            agentID: agentID,
            graph: graph
        )
    }

    public func planDisable(capabilityID: String, graph: CapabilityGraph) throws -> ApplyPlan {
        guard let capability = graph.capabilities.first(where: { $0.id == capabilityID }) else {
            throw OrbitaError.capabilityNotFound(capabilityID)
        }

        return try planStatusChange(action: .disable, capabilities: [capability], planCapabilityID: capabilityID, graph: graph)
    }

    public func planDisable(
        capabilityIDs: [String],
        groupID: String,
        groupName: String,
        graph: CapabilityGraph
    ) throws -> ApplyPlan {
        let capabilities = try capabilities(matching: capabilityIDs, fallbackID: groupID, graph: graph)
        return try planStatusChange(action: .disable, capabilities: capabilities, planCapabilityID: groupID, graph: graph)
    }

    private func planStatusChange(
        action: ApplyAction,
        capabilities: [Capability],
        planCapabilityID: String,
        graph: CapabilityGraph
    ) throws -> ApplyPlan {
        guard action == .enable || action == .disable else {
            throw OrbitaError.invalidApplyPlan("Unsupported status change action: \(action.rawValue)")
        }
        guard let primaryCapability = capabilities.first else {
            throw OrbitaError.capabilityNotFound(planCapabilityID)
        }

        let agentsRoot = URL(fileURLWithPath: graph.projectRoot).appendingPathComponent(".agents")
        var operations = baseIndexOperations(
            action: action,
            capabilities: capabilities,
            graph: graph,
            agentsRoot: agentsRoot
        )

        for capability in capabilities {
            switch action {
            case .enable:
                if let restoreOperation = restoreOperation(for: capability, graph: graph) {
                    operations.append(restoreOperation)
                } else if capability.type == .skill {
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
            case .disable:
                operations.append(contentsOf: disableSourceOperations(for: capability, graph: graph, agentsRoot: agentsRoot))
            case .delete, .merge, .rollback, .clean:
                break
            }
        }

        operations.append(contentsOf: adapterPreviewOperations(
            graph: graphWithProjectedIntent(capabilityIDs: capabilities.map(\.id), status: action == .enable ? .enabled : .disabled, graph: graph)
        ))
        if capabilities.count == 1 {
            operations.append(logOperation(action: action, capability: primaryCapability, agentsRoot: agentsRoot))
        } else {
            operations.append(ApplyOperation(
                kind: .appendLog,
                path: agentsRoot.appendingPathComponent("logs/apply.log").path,
                content: "\(ISO8601DateFormatter().string(from: Date())) \(action.rawValue) \(planCapabilityID) affected:\(capabilities.count)\n",
                risk: .write,
                description: "Append grouped \(action.rawValue) operation log"
            ))
        }

        return ApplyPlan(
            projectRoot: graph.projectRoot,
            action: action,
            capabilityID: planCapabilityID,
            affectedCapabilityIDs: capabilities.count > 1 ? capabilities.map(\.id) : nil,
            appliesChanges: false,
            requiresConfirmation: requiresConfirmation(for: capabilities, operations: operations),
            operations: operations
        )
    }

    private func planSyncSkillInstallTargets(
        capabilities: [Capability],
        planCapabilityID: String,
        agentID: String,
        graph: CapabilityGraph
    ) throws -> ApplyPlan {
        guard let agent = SkillsAgentCatalog.agents.first(where: { $0.id == agentID }) else {
            throw OrbitaError.invalidApplyPlan("Unknown Skills CLI agent: \(agentID)")
        }

        let syncTargets = try capabilities.compactMap { capability -> (capability: Capability, root: URL, destination: URL, source: URL)? in
            guard capability.type == .skill else {
                return nil
            }
            let source = try skillSyncSourceDirectory(for: capability)
            let root = skillSyncDestinationRoot(for: agent, capability: capability, source: source, graph: graph)
            let destination = root.appendingPathComponent(skillSyncDirectoryName(for: capability, source: source))
            guard !skillInstallTargetExists(destination: destination, source: source) else {
                return nil
            }
            guard !fileManager.fileExists(atPath: destination.path),
                  (try? fileManager.destinationOfSymbolicLink(atPath: destination.path)) == nil
            else {
                throw OrbitaError.invalidApplyPlan("Target already exists for \(agent.displayName): \(destination.path)")
            }
            return (capability, root, destination, source)
        }

        guard !syncTargets.isEmpty else {
            throw OrbitaError.invalidApplyPlan("\(agent.displayName) already has this skill target")
        }

        var operations: [ApplyOperation] = []
        let roots = uniquePreservingOrder(syncTargets.map { $0.root.path })
        for root in roots {
            operations.append(ApplyOperation(
                kind: .createDirectory,
                path: root,
                risk: .write,
                description: "Create \(agent.displayName) skill directory"
            ))
        }
        operations.append(contentsOf: syncTargets
            .sorted { $0.destination.path < $1.destination.path }
            .map { target in
                ApplyOperation(
                    kind: .createSymlink,
                    path: target.destination.path,
                    target: target.source.path,
                    risk: .write,
                    description: "Link \(target.capability.name) into \(agent.displayName)"
                )
            })

        let agentsRoot = URL(fileURLWithPath: graph.projectRoot).appendingPathComponent(".agents")
        operations.append(ApplyOperation(
            kind: .appendLog,
            path: agentsRoot.appendingPathComponent("logs/apply.log").path,
            content: "\(ISO8601DateFormatter().string(from: Date())) sync \(planCapabilityID) agent-target:\(agentID) affected:\(syncTargets.count)\n",
            risk: .write,
            description: "Append agent sync operation log"
        ))

        return ApplyPlan(
            projectRoot: graph.projectRoot,
            action: .enable,
            capabilityID: planCapabilityID,
            affectedCapabilityIDs: syncTargets.count > 1 ? syncTargets.map { $0.capability.id } : nil,
            appliesChanges: false,
            requiresConfirmation: false,
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

    public func planDeleteSkillInstallTarget(
        capabilityID: String,
        agentID: String,
        graph: CapabilityGraph
    ) throws -> ApplyPlan {
        let capabilities = try capabilities(matching: [capabilityID], fallbackID: capabilityID, graph: graph)
        return try planDeleteSkillInstallTargets(
            capabilities: capabilities,
            planCapabilityID: capabilityID,
            agentID: agentID,
            graph: graph
        )
    }

    public func planDeleteSkillInstallTargets(
        capabilityIDs: [String],
        groupID: String,
        agentID: String,
        graph: CapabilityGraph
    ) throws -> ApplyPlan {
        let capabilities = try capabilities(matching: capabilityIDs, fallbackID: groupID, graph: graph)
        return try planDeleteSkillInstallTargets(
            capabilities: capabilities,
            planCapabilityID: groupID,
            agentID: agentID,
            graph: graph
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

    private func planDeleteSkillInstallTargets(
        capabilities: [Capability],
        planCapabilityID: String,
        agentID: String,
        graph: CapabilityGraph
    ) throws -> ApplyPlan {
        let targets = capabilities.flatMap { capability -> [(capability: Capability, target: SkillInstallTarget, description: String)] in
            let installTargets = skillInstallTargets(for: capability)
            guard let selectedTarget = installTargets.first(where: { $0.agentID == agentID }) else {
                return []
            }
            if selectedTarget.isAgentSpecific {
                return [(
                    capability,
                    selectedTarget,
                    "Remove \(agentID) \(selectedTarget.relationship) skill install target for \(capability.name)"
                )]
            }
            guard selectedTarget.isCanonical else {
                return []
            }
            var removals = [(
                capability,
                selectedTarget,
                "Remove \(agentID) canonical skill install target for \(capability.name)"
            )]
            removals.append(contentsOf: installTargets
                .filter { $0.agentID != agentID && $0.isSymlinkToCanonical }
                .map { linkedTarget in
                    (
                        capability,
                        linkedTarget,
                        "Remove \(linkedTarget.agentID) symlink skill install target linked to \(agentID) canonical source for \(capability.name)"
                    )
                })
            return removals
        }
        guard !targets.isEmpty else {
            throw OrbitaError.invalidApplyPlan("No agent-specific skill install target for \(agentID)")
        }

        let agentsRoot = URL(fileURLWithPath: graph.projectRoot).appendingPathComponent(".agents")
        var operations = targets
            .sorted { $0.target.path < $1.target.path }
            .map { entry in
                ApplyOperation(
                    kind: .removePath,
                    path: entry.target.path,
                    risk: .write,
                    description: entry.description
                )
            }
        operations.append(ApplyOperation(
            kind: .appendLog,
            path: agentsRoot.appendingPathComponent("logs/apply.log").path,
            content: "\(ISO8601DateFormatter().string(from: Date())) delete \(planCapabilityID) agent-target:\(agentID) affected:\(targets.count)\n",
            risk: .write,
            description: "Append agent-scoped delete operation log"
        ))

        return ApplyPlan(
            projectRoot: graph.projectRoot,
            action: .delete,
            capabilityID: planCapabilityID,
            affectedCapabilityIDs: targets.count > 1 ? targets.map { $0.capability.id } : nil,
            appliesChanges: false,
            requiresConfirmation: requiresConfirmation(for: targets.map(\.capability), operations: operations),
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
        graphWithProjectedIntent(capabilityIDs: [capabilityID], status: status, graph: graph)
    }

    private func graphWithProjectedIntent(capabilityIDs: [String], status: CapabilityStatus, graph: CapabilityGraph) -> CapabilityGraph {
        var projected = graph
        let selectedIDs = Set(capabilityIDs)
        for index in projected.capabilities.indices where selectedIDs.contains(projected.capabilities[index].id) {
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
        }
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
        baseIndexOperations(action: action, capabilities: [capability], graph: graph, agentsRoot: agentsRoot)
    }

    private func baseIndexOperations(action: ApplyAction, capabilities: [Capability], graph: CapabilityGraph, agentsRoot: URL) -> [ApplyOperation] {
        let capabilityIntents = projectedCapabilityIntents(action: action, capabilities: capabilities, graph: graph)
        let indexedCapabilities = capabilityIntents.map(\.capability)
        var operations = capabilities.map { capability in
            ApplyOperation(
                kind: .readSource,
                path: manifestSourcePath(for: capability),
                risk: .read,
                description: "Read capability source before indexing"
            )
        }
        operations.append(contentsOf: [
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
        ])
        return operations
    }

    private func projectedCapabilityIntents(
        action: ApplyAction,
        capability selectedCapability: Capability,
        graph: CapabilityGraph
    ) -> [(capability: Capability, status: CapabilityStatus)] {
        projectedCapabilityIntents(action: action, capabilities: [selectedCapability], graph: graph)
    }

    private func projectedCapabilityIntents(
        action: ApplyAction,
        capabilities selectedCapabilities: [Capability],
        graph: CapabilityGraph
    ) -> [(capability: Capability, status: CapabilityStatus)] {
        let selectedStatus: CapabilityStatus = action == .enable ? .enabled : .disabled
        let selectedIDs = Set(selectedCapabilities.map(\.id))
        let selectedManifestIDs = Set(selectedCapabilities.map(manifestCapabilityID(for:)))
        var values: [(capability: Capability, status: CapabilityStatus)] = graph.capabilities.compactMap { capability -> (capability: Capability, status: CapabilityStatus)? in
            let isSelected = selectedIDs.contains(capability.id) || selectedManifestIDs.contains(manifestCapabilityID(for: capability))
            guard isSelected || capability.metadata["manifestStatus"] != nil else {
                return nil
            }
            guard !capability.source.kind.hasPrefix("agents-") else {
                return nil
            }
            if isSelected {
                return (capability: capability, status: selectedStatus)
            }
            let status = capability.metadata["manifestStatus"].flatMap(CapabilityStatus.init(rawValue:)) ?? .enabled
            return (capability: capability, status: status)
        }

        var existingManifestIDs = Set(values.map { manifestCapabilityID(for: $0.capability) })
        for selectedCapability in selectedCapabilities where !existingManifestIDs.contains(manifestCapabilityID(for: selectedCapability)) {
            values.append((capability: selectedCapability, status: selectedStatus))
            existingManifestIDs.insert(manifestCapabilityID(for: selectedCapability))
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

    private func capabilities(matching capabilityIDs: [String], fallbackID: String, graph: CapabilityGraph) throws -> [Capability] {
        let selectedIDs = Set(capabilityIDs)
        let capabilities = graph.capabilities
            .filter { selectedIDs.contains($0.id) }
            .sorted { $0.id < $1.id }
        guard !capabilities.isEmpty else {
            throw OrbitaError.capabilityNotFound(fallbackID)
        }
        return capabilities
    }

    private struct SkillInstallTarget {
        var agentID: String
        var relationship: String
        var path: String

        var isCanonical: Bool {
            relationship == "canonical"
        }

        var isAgentSpecific: Bool {
            switch relationship {
            case "copy", "symlink", "symlink-other", "broken-symlink":
                return true
            default:
                return false
            }
        }

        var isSymlinkToCanonical: Bool {
            relationship == "symlink"
        }
    }

    private func skillInstallTargets(for capability: Capability) -> [SkillInstallTarget] {
        guard capability.type == .skill,
              let value = capability.metadata["skillsInstallTargets"]
        else {
            return []
        }

        return value.split(separator: "\n").compactMap { line -> SkillInstallTarget? in
            let assignment = line.split(separator: "=", maxSplits: 1).map(String.init)
            guard assignment.count == 2 else {
                return nil
            }
            let relationshipAndPath = assignment[1].split(separator: ":", maxSplits: 1).map(String.init)
            guard relationshipAndPath.count == 2, !relationshipAndPath[1].isEmpty else {
                return nil
            }
            return SkillInstallTarget(
                agentID: assignment[0],
                relationship: relationshipAndPath[0],
                path: relationshipAndPath[1]
            )
        }
    }

    private func skillInstallTarget(for capability: Capability, agentID: String) -> SkillInstallTarget? {
        skillInstallTargets(for: capability).first { $0.agentID == agentID }
    }

    private func skillSyncSourceDirectory(for capability: Capability) throws -> URL {
        let canonicalPath = capability.metadata["skillsCanonicalPath"]
            .flatMap { $0.isEmpty ? nil : $0 }
        let source = URL(fileURLWithPath: canonicalPath ?? skillDirectoryPath(for: capability)).standardizedFileURL
        guard fileManager.fileExists(atPath: source.path) ||
            (try? fileManager.destinationOfSymbolicLink(atPath: source.path)) != nil
        else {
            throw OrbitaError.invalidApplyPlan("Skill source does not exist: \(source.path)")
        }
        return source
    }

    private func skillSyncDestinationRoot(
        for agent: SkillsAgentDefinition,
        capability: Capability,
        source: URL,
        graph: CapabilityGraph
    ) -> URL {
        if capability.scope == .user {
            if let globalSkillsDir = agent.globalSkillsDir {
                return URL(fileURLWithPath: globalSkillsDir).standardizedFileURL
            }
            if agent.usesSharedProjectSkills {
                if let canonicalPath = capability.metadata["skillsCanonicalPath"],
                   !canonicalPath.isEmpty {
                    return URL(fileURLWithPath: canonicalPath).deletingLastPathComponent().standardizedFileURL
                }
                if let agentsSkillsRoot = sharedAgentsSkillsRoot(containing: source) {
                    return agentsSkillsRoot
                }
                return FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent(".agents/skills")
                    .standardizedFileURL
            }
        }
        return URL(fileURLWithPath: graph.projectRoot)
            .appendingPathComponent(agent.projectSkillsDir)
            .standardizedFileURL
    }

    private func sharedAgentsSkillsRoot(containing source: URL) -> URL? {
        let components = source.standardizedFileURL.pathComponents
        guard let agentsIndex = components.lastIndex(of: ".agents"),
              agentsIndex + 1 < components.count,
              components[agentsIndex + 1] == "skills"
        else {
            return nil
        }
        return components.dropFirst().prefix(agentsIndex + 1).reduce(URL(fileURLWithPath: "/")) { url, component in
            url.appendingPathComponent(component)
        }
        .standardizedFileURL
    }

    private func skillSyncDirectoryName(for capability: Capability, source: URL) -> String {
        if let canonicalPath = capability.metadata["skillsCanonicalPath"],
           !canonicalPath.isEmpty {
            return URL(fileURLWithPath: canonicalPath).lastPathComponent
        }
        return source.lastPathComponent
    }

    private func skillInstallTargetExists(destination: URL, source: URL) -> Bool {
        if let existingTarget = try? fileManager.destinationOfSymbolicLink(atPath: destination.path) {
            let resolved = resolveSymlink(destination: existingTarget, from: destination.deletingLastPathComponent())
            return resolved.standardizedFileURL.resolvingSymlinksInPath().path == source.standardizedFileURL.resolvingSymlinksInPath().path
        }
        guard fileManager.fileExists(atPath: destination.path) else {
            return false
        }
        return destination.standardizedFileURL.resolvingSymlinksInPath().path == source.standardizedFileURL.resolvingSymlinksInPath().path
    }

    private func resolveSymlink(destination: String, from directory: URL) -> URL {
        if destination.hasPrefix("/") {
            return URL(fileURLWithPath: destination).standardizedFileURL
        }
        return directory.appendingPathComponent(destination).standardizedFileURL
    }

    private func uniquePreservingOrder(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for value in values where seen.insert(value).inserted {
            result.append(value)
        }
        return result
    }

    private func disableSourceOperations(for capability: Capability, graph: CapabilityGraph, agentsRoot: URL) -> [ApplyOperation] {
        if let symlinkPath = symbolicDisablePath(for: capability, agentsRoot: agentsRoot) {
            return [
                ApplyOperation(
                    kind: .removePath,
                    path: symlinkPath,
                    risk: .write,
                    description: "Remove symbolic link so the current host stops loading this capability; linked target content remains"
                )
            ]
        }

        guard let sourcePath = cacheableSourcePath(for: capability),
              isCacheableAgentSourcePath(sourcePath),
              fileManager.fileExists(atPath: sourcePath)
        else {
            return []
        }

        return [
            ApplyOperation(
                kind: .cachePath,
                path: sourcePath,
                target: disabledCachePath(for: capability, sourcePath: sourcePath, graph: graph),
                risk: .write,
                description: "Copy capability source into .orbita disabled cache before removing it from the host-visible location"
            )
        ]
    }

    private func restoreOperation(for capability: Capability, graph: CapabilityGraph) -> ApplyOperation? {
        guard let sourcePath = cacheableSourcePath(for: capability) else {
            return nil
        }
        let cachePath = disabledCachePath(for: capability, sourcePath: sourcePath, graph: graph)
        guard fileManager.fileExists(atPath: cachePath) else {
            return nil
        }
        return ApplyOperation(
            kind: .restorePath,
            path: cachePath,
            target: sourcePath,
            risk: .write,
            description: "Restore capability source from .orbita disabled cache"
        )
    }

    private func symbolicDisablePath(for capability: Capability, agentsRoot: URL) -> String? {
        if let skillLink = agentsSkillLinkPath(for: capability, agentsRoot: agentsRoot),
           isSymbolicLink(atPath: skillLink) {
            return skillLink
        }
        guard let sourcePath = cacheableSourcePath(for: capability) else {
            return nil
        }
        if isSymbolicLink(atPath: sourcePath) {
            return sourcePath
        }
        if capability.type == .skill {
            let parent = URL(fileURLWithPath: manifestSourcePath(for: capability)).deletingLastPathComponent().path
            if isSymbolicLink(atPath: parent) {
                return parent
            }
        }
        return nil
    }

    private func agentsSkillLinkPath(for capability: Capability, agentsRoot: URL) -> String? {
        guard capability.type == .skill else {
            return nil
        }
        return agentsRoot.appendingPathComponent("skills").appendingPathComponent(capability.name).path
    }

    private func isSymbolicLink(atPath path: String) -> Bool {
        (try? fileManager.destinationOfSymbolicLink(atPath: path)) != nil
    }

    private func cacheableSourcePath(for capability: Capability) -> String? {
        let path = manifestSourcePath(for: capability)
        guard !path.isEmpty, path != "-" else {
            return nil
        }
        if capability.type == .skill, path.hasSuffix("/SKILL.md") {
            return URL(fileURLWithPath: path).deletingLastPathComponent().standardizedFileURL.path
        }
        return URL(fileURLWithPath: path).standardizedFileURL.path
    }

    private func isCacheableAgentSourcePath(_ path: String) -> Bool {
        let components = Set(URL(fileURLWithPath: path).standardizedFileURL.pathComponents)
        return components.contains(".agents")
            || components.contains(".codex")
            || components.contains(".claude")
            || components.contains(".cursor")
    }

    private func disabledCachePath(for capability: Capability, sourcePath: String, graph: CapabilityGraph) -> String {
        let key = cacheKey(for: "\(manifestCapabilityID(for: capability))|\(sourcePath)")
        let sourceName = URL(fileURLWithPath: sourcePath).lastPathComponent
        return URL(fileURLWithPath: graph.projectRoot)
            .appendingPathComponent(".orbita/cache/disabled")
            .appendingPathComponent(capability.type.rawValue)
            .appendingPathComponent(key)
            .appendingPathComponent(sourceName.isEmpty ? "source" : sourceName)
            .path
    }

    private func cacheKey(for value: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x100000001b3
        }
        return String(hash, radix: 16)
    }

    private func skillDirectoryPath(for capability: Capability) -> String {
        let path = manifestSourcePath(for: capability)
        if path.hasSuffix("/SKILL.md") {
            return String(path.dropLast("/SKILL.md".count))
        }
        return path
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
        let path = capability.metadata["sourcePath"] ?? capability.source.path
        guard !path.isEmpty, path != "-" else {
            return nil
        }
        guard !isInternalOrbitaIndexPath(path) else {
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

    private func isInternalOrbitaIndexPath(_ path: String) -> Bool {
        path.contains("/.orbita/this-mac/")
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
        let orbitaRoot = URL(fileURLWithPath: plan.projectRoot).appendingPathComponent(".orbita").standardizedFileURL
        var completed: [ApplyOperation] = []

        for (index, operation) in plan.operations.enumerated() {
            do {
                try validate(operation: operation, action: plan.action, agentsRoot: agentsRoot, orbitaRoot: orbitaRoot)
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
        case .cachePath, .restorePath:
            guard let target = operation.target else {
                throw OrbitaError.invalidApplyPlan("Missing target for \(operation.path)")
            }
            try copyReplacingItem(from: operation.path, to: target)
            if fileManager.fileExists(atPath: operation.path) || (try? fileManager.destinationOfSymbolicLink(atPath: operation.path)) != nil {
                try fileManager.removeItem(atPath: operation.path)
            }
        case .removePath:
            if fileManager.fileExists(atPath: operation.path) || (try? fileManager.destinationOfSymbolicLink(atPath: operation.path)) != nil {
                try fileManager.removeItem(atPath: operation.path)
            }
        }
    }

    private func copyReplacingItem(from sourcePath: String, to destinationPath: String) throws {
        guard fileManager.fileExists(atPath: sourcePath) || (try? fileManager.destinationOfSymbolicLink(atPath: sourcePath)) != nil else {
            throw OrbitaError.invalidApplyPlan("Source does not exist: \(sourcePath)")
        }
        let destinationURL = URL(fileURLWithPath: destinationPath)
        let parent = destinationURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: destinationPath) || (try? fileManager.destinationOfSymbolicLink(atPath: destinationPath)) != nil {
            try fileManager.removeItem(atPath: destinationPath)
        }
        try fileManager.copyItem(atPath: sourcePath, toPath: destinationPath)
    }

    private func validate(operation: ApplyOperation, action: ApplyAction, agentsRoot: URL, orbitaRoot: URL) throws {
        guard operation.kind != .readSource else { return }
        if action == .delete, operation.kind == .removePath {
            return
        }
        if action == .disable, operation.kind == .removePath {
            return
        }
        let operationPath = normalizedContainmentPath(URL(fileURLWithPath: operation.path).standardizedFileURL.path)
        let agentsRootPath = normalizedContainmentPath(agentsRoot.standardizedFileURL.path)
        let orbitaRootPath = normalizedContainmentPath(orbitaRoot.standardizedFileURL.path)
        switch operation.kind {
        case .cachePath:
            guard let target = operation.target else {
                throw OrbitaError.invalidApplyPlan("Missing cache target for \(operation.path)")
            }
            guard isAgentStoragePath(operationPath) else {
                throw OrbitaError.invalidApplyPlan("Cache source is outside known agent storage: \(operation.path)")
            }
            let targetPath = normalizedContainmentPath(URL(fileURLWithPath: target).standardizedFileURL.path)
            guard targetPath == orbitaRootPath || targetPath.hasPrefix(orbitaRootPath + "/") else {
                throw OrbitaError.invalidApplyPlan("Cache target is outside .orbita: \(target)")
            }
        case .restorePath:
            guard let target = operation.target else {
                throw OrbitaError.invalidApplyPlan("Missing restore target for \(operation.path)")
            }
            guard operationPath == orbitaRootPath || operationPath.hasPrefix(orbitaRootPath + "/") else {
                throw OrbitaError.invalidApplyPlan("Restore source is outside .orbita: \(operation.path)")
            }
            let targetPath = normalizedContainmentPath(URL(fileURLWithPath: target).standardizedFileURL.path)
            guard isAgentStoragePath(targetPath) else {
                throw OrbitaError.invalidApplyPlan("Restore target is outside known agent storage: \(target)")
            }
        case .createDirectory, .createSymlink:
            let isProjectPath = operationPath == agentsRootPath
                || operationPath.hasPrefix(agentsRootPath + "/")
                || operationPath == orbitaRootPath
                || operationPath.hasPrefix(orbitaRootPath + "/")
            guard isProjectPath || isAgentStoragePath(operationPath) else {
                throw OrbitaError.invalidApplyPlan("Operation is outside known agent storage: \(operation.path)")
            }
            if operation.kind == .createSymlink,
               let target = operation.target {
                let targetPath = normalizedContainmentPath(URL(fileURLWithPath: target).standardizedFileURL.path)
                let targetIsProjectPath = targetPath == agentsRootPath
                    || targetPath.hasPrefix(agentsRootPath + "/")
                    || targetPath == orbitaRootPath
                    || targetPath.hasPrefix(orbitaRootPath + "/")
                guard isProjectPath || targetIsProjectPath || isAgentStoragePath(targetPath) else {
                    throw OrbitaError.invalidApplyPlan("Symlink target is outside known agent storage: \(target)")
                }
            }
        default:
            guard operationPath == agentsRootPath
                || operationPath.hasPrefix(agentsRootPath + "/")
                || operationPath == orbitaRootPath
                || operationPath.hasPrefix(orbitaRootPath + "/")
            else {
                throw OrbitaError.invalidApplyPlan("Operation is outside .agents or .orbita: \(operation.path)")
            }
        }
    }

    private func isAgentStoragePath(_ path: String) -> Bool {
        let components = Set(URL(fileURLWithPath: path).standardizedFileURL.pathComponents)
        if components.contains(".agents")
            || components.contains(".codex")
            || components.contains(".claude")
            || components.contains(".cursor")
            || components.contains(".trae")
            || components.contains(".trae-cn") {
            return true
        }
        return SkillsAgentCatalog.agents.contains { agent in
            guard let globalSkillsDir = agent.globalSkillsDir else {
                return false
            }
            let root = normalizedContainmentPath(URL(fileURLWithPath: globalSkillsDir).standardizedFileURL.path)
            return path == root || path.hasPrefix(root + "/")
        }
    }

    private func normalizedContainmentPath(_ path: String) -> String {
        if path.hasPrefix("/private/var/") {
            return String(path.dropFirst("/private".count))
        }
        return path
    }
}
