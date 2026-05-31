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
    case copyPath
    case cachePath
    case restorePath
    case removePath
    case writeFile
    case appendLog
}

public enum AgentSyncMode: String, Codable, CaseIterable, Sendable {
    case copy
    case symlink
}

public enum AgentSyncDestinationScope: String, Codable, CaseIterable, Sendable {
    case project
    case user
}

public extension CapabilityType {
    var supportsAgentSync: Bool {
        switch self {
        case .skill, .command, .agent:
            return true
        case .plugin, .mcpServer, .rule, .instruction, .hook, .unknown:
            return false
        }
    }
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
    private let homeDirectory: URL

    public init(
        fileManager: FileManager = .default,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) {
        self.fileManager = fileManager
        self.homeDirectory = homeDirectory
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
        graph: CapabilityGraph,
        mode: AgentSyncMode = .symlink,
        destinationScope: AgentSyncDestinationScope? = nil
    ) throws -> ApplyPlan {
        try planSyncInstallTarget(
            capabilityID: capabilityID,
            agentID: agentID,
            graph: graph,
            mode: mode,
            destinationScope: destinationScope
        )
    }

    public func planSyncInstallTarget(
        capabilityID: String,
        agentID: String,
        graph: CapabilityGraph,
        mode: AgentSyncMode = .symlink,
        destinationScope: AgentSyncDestinationScope? = nil
    ) throws -> ApplyPlan {
        let capabilities = try capabilities(matching: [capabilityID], fallbackID: capabilityID, graph: graph)
        return try planSyncInstallTargets(
            capabilities: capabilities,
            planCapabilityID: capabilityID,
            agentID: agentID,
            graph: graph,
            mode: mode,
            destinationScope: destinationScope
        )
    }

    public func planSyncSkillInstallTargets(
        capabilityIDs: [String],
        groupID: String,
        agentID: String,
        graph: CapabilityGraph,
        mode: AgentSyncMode = .symlink,
        destinationScope: AgentSyncDestinationScope? = nil
    ) throws -> ApplyPlan {
        try planSyncInstallTargets(
            capabilityIDs: capabilityIDs,
            groupID: groupID,
            agentID: agentID,
            graph: graph,
            mode: mode,
            destinationScope: destinationScope
        )
    }

    public func planSyncInstallTargets(
        capabilityIDs: [String],
        groupID: String,
        agentID: String,
        graph: CapabilityGraph,
        mode: AgentSyncMode = .symlink,
        destinationScope: AgentSyncDestinationScope? = nil
    ) throws -> ApplyPlan {
        let capabilities = try capabilities(matching: capabilityIDs, fallbackID: groupID, graph: graph)
        return try planSyncInstallTargets(
            capabilities: capabilities,
            planCapabilityID: groupID,
            agentID: agentID,
            graph: graph,
            mode: mode,
            destinationScope: destinationScope
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

    private func planSyncInstallTargets(
        capabilities: [Capability],
        planCapabilityID: String,
        agentID: String,
        graph: CapabilityGraph,
        mode: AgentSyncMode,
        destinationScope requestedDestinationScope: AgentSyncDestinationScope?
    ) throws -> ApplyPlan {
        guard let agent = SkillsAgentCatalog.agents.first(where: { $0.id == agentID }) else {
            throw OrbitaError.invalidApplyPlan("Unknown Skills CLI agent: \(agentID)")
        }
        let destinationScope = requestedDestinationScope ?? defaultSyncDestinationScope(for: capabilities)

        let syncTargets = try capabilities.compactMap { capability -> (capability: Capability, root: URL, destination: URL, source: URL)? in
            guard capability.type.supportsAgentSync else {
                return nil
            }
            guard isDirectSyncCompatible(capability: capability, agentID: agent.id) else {
                throw OrbitaError.invalidApplyPlan("\(agent.displayName) cannot directly load \(capability.type.rawValue) files from \(capability.source.kind)")
            }
            let source = try syncSourceURL(for: capability)
            let root = try syncDestinationRoot(
                for: agent,
                capability: capability,
                destinationScope: destinationScope,
                graph: graph
            )
            let destination = root.appendingPathComponent(syncDestinationName(for: capability, source: source))
            switch mode {
            case .copy:
                if let existingTarget = try? fileManager.destinationOfSymbolicLink(atPath: destination.path) {
                    let resolved = resolveSymlink(destination: existingTarget, from: destination.deletingLastPathComponent())
                    guard resolved.standardizedFileURL.resolvingSymlinksInPath().path == source.standardizedFileURL.resolvingSymlinksInPath().path else {
                        throw OrbitaError.invalidApplyPlan("Target already exists for \(agent.displayName): \(destination.path)")
                    }
                } else if fileManager.fileExists(atPath: destination.path) {
                    throw OrbitaError.invalidApplyPlan("Target already exists for \(agent.displayName): \(destination.path)")
                }
            case .symlink:
                guard !skillInstallTargetExists(destination: destination, source: source) else {
                    return nil
                }
                guard !fileManager.fileExists(atPath: destination.path),
                      (try? fileManager.destinationOfSymbolicLink(atPath: destination.path)) == nil
                else {
                    throw OrbitaError.invalidApplyPlan("Target already exists for \(agent.displayName): \(destination.path)")
                }
            }
            return (capability, root, destination, source)
        }

        guard !syncTargets.isEmpty else {
            throw OrbitaError.invalidApplyPlan("\(agent.displayName) already has this \(syncKindDescription(for: capabilities)) target")
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
                switch mode {
                case .copy:
                    return ApplyOperation(
                        kind: .copyPath,
                        path: target.source.path,
                        target: target.destination.path,
                        risk: .write,
                        description: "Copy \(target.capability.name) into \(agent.displayName)"
                    )
                case .symlink:
                    return ApplyOperation(
                        kind: .createSymlink,
                        path: target.destination.path,
                        target: symlinkTarget(
                            source: target.source,
                            destination: target.destination,
                            destinationScope: destinationScope,
                            graph: graph
                        ),
                        risk: .write,
                        description: "Link \(target.capability.name) into \(agent.displayName)"
                    )
                }
            })

        let agentsRoot = URL(fileURLWithPath: graph.projectRoot).appendingPathComponent(".agents")
        operations.append(ApplyOperation(
            kind: .appendLog,
            path: agentsRoot.appendingPathComponent("logs/apply.log").path,
            content: "\(ISO8601DateFormatter().string(from: Date())) sync \(planCapabilityID) agent-target:\(agentID) mode:\(mode.rawValue) scope:\(destinationScope.rawValue) affected:\(syncTargets.count)\n",
            risk: .write,
            description: "Append agent sync operation log"
        ))

        return ApplyPlan(
            projectRoot: graph.projectRoot,
            action: .enable,
            capabilityID: planCapabilityID,
            affectedCapabilityIDs: syncTargets.count > 1 ? syncTargets.map { $0.capability.id } : nil,
            appliesChanges: false,
            // The interactive sync picker (agent + mode + scope) is itself the explicit confirmation gate
            // for a fork, so no secondary prompt is required.
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
            // Cascade to symlink-to-canonical forks in other agent homes so deleting the source does not
            // orphan dangling links. Copies and foreign symlinks are intentionally left (they are
            // independent on-disk artifacts, not links into this source).
            for target in skillInstallTargets(for: capability) where target.isSymlinkToCanonical {
                registerRemoval(
                    target.path,
                    description: "Remove \(target.agentID) symlink fork linked to \(capability.name)"
                )
            }
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
            // Only skill forks carry round-trip install-target metadata. Command/agent forks are
            // intentionally one-way; give an actionable error instead of the misleading skill-only message.
            if capabilities.contains(where: { $0.type != .skill }) {
                throw OrbitaError.invalidApplyPlan("Agent-scoped delete is only tracked for skill forks; \(syncKindDescription(for: capabilities)) forks are one-way — delete the source capability or remove the forked file directly")
            }
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

        // Reuse the SAME source-operation builders as a normal enable/disable so rollback is symmetric for
        // every capability type by construction — not just skills. A rolled-back disable restores the source
        // (from the disabled store for a quarantined command/agent fork, or by reconstructing a skill's
        // `.agents/skills/<name>` link); a rolled-back enable re-runs the disable source ops.
        switch inverseAction {
        case .enable:
            if let restore = restoreOperation(for: capability, graph: graph) {
                operations.append(restore)
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
                    description: "Restore project skill link"
                ))
            }
        case .disable:
            operations.append(contentsOf: disableSourceOperations(for: capability, graph: graph, agentsRoot: agentsRoot))
        case .delete, .merge, .rollback, .clean:
            break
        }

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
        let projectRoot = URL(fileURLWithPath: graph.projectRoot)
        let agentsRoot = projectRoot.appendingPathComponent(".agents")
        let orbitaRoot = projectRoot.appendingPathComponent(".orbita")
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
            adaptersRoot: orbitaRoot.appendingPathComponent("adapters"),
            activeCapabilityIDs: activeCapabilityIDs
        ))
        operations.append(contentsOf: legacyAdapterCleanOperations(
            adaptersRoot: agentsRoot.appendingPathComponent("adapters")
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

    private func staleAdapterCleanOperations(adaptersRoot: URL, activeCapabilityIDs: Set<String>) -> [ApplyOperation] {
        adapterFiles(in: adaptersRoot).compactMap { file in
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

    private func legacyAdapterCleanOperations(adaptersRoot: URL) -> [ApplyOperation] {
        adapterFiles(in: adaptersRoot).compactMap { file in
            guard isOrbitaAdapterFile(file) else {
                return nil
            }
            return ApplyOperation(
                kind: .removePath,
                path: file.path,
                risk: .write,
                description: "Remove legacy .agents adapter preview; Orbita stores adapter previews in .orbita"
            )
        }
    }

    private func adapterFiles(in adaptersRoot: URL) -> [URL] {
        guard let agentDirectories = try? FileManager.default.contentsOfDirectory(
            at: adaptersRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return agentDirectories.map { $0.appendingPathComponent("capabilities.json") }
    }

    private func adapterFileReferencesOnlyActiveCapabilities(_ file: URL, activeCapabilityIDs: Set<String>) -> Bool {
        guard let object = adapterObject(file) else {
            return false
        }

        let capabilityIDs = ids(in: object["capabilities"], key: "id")
        let mappingIDs = ids(in: object["mappings"], key: "capabilityID")
        let referencedIDs = capabilityIDs.union(mappingIDs)
        return referencedIDs.allSatisfy { activeCapabilityIDs.contains($0) }
    }

    private func isOrbitaAdapterFile(_ file: URL) -> Bool {
        guard let object = adapterObject(file) else {
            return false
        }
        return object["schemaVersion"] != nil
            && object["agent"] is String
            && object["capabilities"] != nil
            && object["mappings"] != nil
    }

    private func adapterObject(_ file: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: file),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return object
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

    private func defaultSyncDestinationScope(for capabilities: [Capability]) -> AgentSyncDestinationScope {
        capabilities.allSatisfy { $0.scope == .project } ? .project : .user
    }

    private func syncKindDescription(for capabilities: [Capability]) -> String {
        let types = Set(capabilities.map(\.type))
        if types.count == 1, let type = types.first {
            return type.rawValue
        }
        return "capability"
    }

    private func syncSourceURL(for capability: Capability) throws -> URL {
        let source: URL
        if capability.type == .skill {
            source = try skillSyncSourceDirectory(for: capability)
        } else {
            source = URL(fileURLWithPath: manifestSourcePath(for: capability)).standardizedFileURL
        }
        let resolved = source.resolvingSymlinksInPath()
        let effectiveSource = fileManager.fileExists(atPath: resolved.path) ? resolved : source
        guard fileManager.fileExists(atPath: effectiveSource.path) ||
            (try? fileManager.destinationOfSymbolicLink(atPath: source.path)) != nil
        else {
            throw OrbitaError.invalidApplyPlan("Sync source does not exist: \(source.path)")
        }
        return effectiveSource
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

    private func syncDestinationRoot(
        for agent: SkillsAgentDefinition,
        capability: Capability,
        destinationScope: AgentSyncDestinationScope,
        graph: CapabilityGraph
    ) throws -> URL {
        if destinationScope == .project, capability.scope != .project {
            throw OrbitaError.invalidApplyPlan("My Mac capabilities can only sync into global agent storage")
        }

        switch capability.type {
        case .skill:
            return try skillSyncDestinationRoot(
                for: agent,
                capability: capability,
                destinationScope: destinationScope,
                graph: graph
            )
        case .command:
            if let root = commandSyncDestinationRoot(for: agent.id, destinationScope: destinationScope, graph: graph) {
                return root
            }
        case .agent:
            if let root = agentSyncDestinationRoot(for: agent.id, destinationScope: destinationScope, graph: graph) {
                return root
            }
        case .plugin, .mcpServer, .rule, .instruction, .hook, .unknown:
            break
        }
        throw OrbitaError.invalidApplyPlan("\(agent.displayName) does not expose a compatible \(capability.type.rawValue) sync directory")
    }

    private func skillSyncDestinationRoot(
        for agent: SkillsAgentDefinition,
        capability: Capability,
        destinationScope: AgentSyncDestinationScope,
        graph: CapabilityGraph
    ) throws -> URL {
        if destinationScope == .user {
            guard let globalSkillsDir = agent.globalSkillsDir else {
                throw OrbitaError.invalidApplyPlan("\(agent.displayName) does not expose a global skills directory")
            }
            let root = URL(fileURLWithPath: globalSkillsDir).standardizedFileURL
            // Invariant: Orbita may only write where it can re-scan. A user-scope skill fork is allowed
            // only into a global skills dir the scanner actually re-reads (defaultUserSkillRoots), so the
            // fork stays discoverable and reversible. Otherwise it would be a write-only phantom install.
            let resolvedRoot = root.resolvingSymlinksInPath().path
            let rescannable = ScanOptions.defaultUserSkillRoots().contains {
                $0.standardizedFileURL.resolvingSymlinksInPath().path == resolvedRoot
            }
            guard rescannable else {
                throw OrbitaError.invalidApplyPlan("\(agent.displayName)'s global skills directory is not re-scanned by Orbita, so a user-scope skill fork there cannot be tracked or undone")
            }
            return root
        }
        return URL(fileURLWithPath: graph.projectRoot)
            .appendingPathComponent(agent.projectSkillsDir)
            .standardizedFileURL
    }

    /// Symlink target for a fork. For project-scope forks where both endpoints live under the project
    /// root, emit a path RELATIVE to the link's own directory so the committed link survives a repo
    /// move/clone. User-scope / cross-tree forks keep an absolute target (relativity is meaningless).
    private func symlinkTarget(
        source: URL,
        destination: URL,
        destinationScope: AgentSyncDestinationScope,
        graph: CapabilityGraph
    ) -> String {
        guard destinationScope == .project else { return source.path }
        let projectRootPath = URL(fileURLWithPath: graph.projectRoot).standardizedFileURL.path
        let sourcePath = source.standardizedFileURL.path
        let destinationPath = destination.standardizedFileURL.path
        guard sourcePath == projectRootPath || sourcePath.hasPrefix(projectRootPath + "/"),
              destinationPath == projectRootPath || destinationPath.hasPrefix(projectRootPath + "/") else {
            return source.path
        }
        return relativePath(from: destination.deletingLastPathComponent(), to: source)
    }

    private func relativePath(from base: URL, to target: URL) -> String {
        let baseComponents = base.standardizedFileURL.pathComponents
        let targetComponents = target.standardizedFileURL.pathComponents
        var commonPrefix = 0
        while commonPrefix < baseComponents.count,
              commonPrefix < targetComponents.count,
              baseComponents[commonPrefix] == targetComponents[commonPrefix] {
            commonPrefix += 1
        }
        var components = Array(repeating: "..", count: baseComponents.count - commonPrefix)
        components.append(contentsOf: targetComponents[commonPrefix...])
        return components.isEmpty ? "." : components.joined(separator: "/")
    }

    private func commandSyncDestinationRoot(
        for agentID: String,
        destinationScope: AgentSyncDestinationScope,
        graph: CapabilityGraph
    ) -> URL? {
        let home = homeDirectory
        switch (agentID, destinationScope) {
        case ("codex", .project):
            return URL(fileURLWithPath: graph.projectRoot).appendingPathComponent(".codex/commands").standardizedFileURL
        case ("codex", .user):
            return home.appendingPathComponent(".codex/commands").standardizedFileURL
        case ("claude-code", .project):
            return URL(fileURLWithPath: graph.projectRoot).appendingPathComponent(".claude/commands").standardizedFileURL
        case ("claude-code", .user):
            return home.appendingPathComponent(".claude/commands").standardizedFileURL
        default:
            return nil
        }
    }

    private func agentSyncDestinationRoot(
        for agentID: String,
        destinationScope: AgentSyncDestinationScope,
        graph: CapabilityGraph
    ) -> URL? {
        let home = homeDirectory
        switch (agentID, destinationScope) {
        case ("codex", .project):
            return URL(fileURLWithPath: graph.projectRoot).appendingPathComponent(".codex/agents").standardizedFileURL
        case ("codex", .user):
            return home.appendingPathComponent(".codex/agents").standardizedFileURL
        case ("claude-code", .project):
            return URL(fileURLWithPath: graph.projectRoot).appendingPathComponent(".claude/agents").standardizedFileURL
        case ("claude-code", .user):
            return home.appendingPathComponent(".claude/agents").standardizedFileURL
        default:
            return nil
        }
    }

    private func isDirectSyncCompatible(capability: Capability, agentID: String) -> Bool {
        AgentSyncPolicy.isCompatible(capability: capability, agentID: agentID)
    }

    private func syncDestinationName(for capability: Capability, source: URL) -> String {
        guard capability.type == .skill else {
            return source.lastPathComponent
        }
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
            // A skill's `.agents/skills/<name>` link is reconstructed from the capability on enable, so a
            // bare removal round-trips. A non-skill fork (command/agent symlink) has NO such reconstruction,
            // so removing the link would be irreversible — quarantine the LINK instead (copyItem preserves
            // the symlink), which the type-agnostic restoreOperation() puts back on enable/rollback.
            // Native-first still wins: a capability the host can disable in place must never be moved, so a
            // native-disable symlink keeps the pre-existing bare removal (it carries no quarantine sidecar).
            // We also fall back to removal if the link can't be quarantined (outside agent storage).
            if capability.type != .skill, !hasNativeDisable(capability), isCacheableAgentSourcePath(symlinkPath) {
                return quarantineOperations(for: capability, sourcePath: symlinkPath, graph: graph)
            }
            return [removeSymlinkOperation(symlinkPath)]
        }

        // Native-first: a capability the host can disable IN PLACE (Codex `[[skills.config]] enabled=false`,
        // Claude `skillOverrides=off`, or any native plugin/skill lifecycle) must NOT be physically moved.
        // Its disable is expressed as an emitted native command, and the `.agents` intent write above already
        // records Orbita's view; quarantining it here would both violate "source file stays where it is" and
        // fight the native client. The destructive move is a last-resort fallback ONLY for hosts with no
        // native off-switch (e.g. Trae/Cursor skills). Without this gate a `orbita plan --disable <id>` on a
        // Codex/Claude real-file skill from the CLI would wrongly relocate it.
        guard !hasNativeDisable(capability) else {
            return []
        }

        guard let sourcePath = cacheableSourcePath(for: capability),
              isCacheableAgentSourcePath(sourcePath),
              fileManager.fileExists(atPath: sourcePath)
        else {
            return []
        }

        return quarantineOperations(for: capability, sourcePath: sourcePath, graph: graph)
    }

    private func removeSymlinkOperation(_ symlinkPath: String) -> ApplyOperation {
        ApplyOperation(
            kind: .removePath,
            path: symlinkPath,
            risk: .write,
            description: "Remove symbolic link so the current host stops loading this capability; linked target content remains"
        )
    }

    /// Move a capability's source into the scope-correct Orbita disabled store with a co-located restore
    /// sidecar. Shared by the no-native-disable fallback and the non-skill-fork case so both round-trip
    /// through the type-agnostic restoreOperation() on enable.
    private func quarantineOperations(for capability: Capability, sourcePath: String, graph: CapabilityGraph) -> [ApplyOperation] {
        let quarantinePath = disabledQuarantineContentPath(for: capability, sourcePath: sourcePath, graph: graph)
        let entryDirectory = URL(fileURLWithPath: quarantinePath).deletingLastPathComponent()
        return [
            ApplyOperation(
                kind: .cachePath,
                path: sourcePath,
                target: quarantinePath,
                risk: .write,
                description: "Move capability source into the scope-correct Orbita disabled store (host has no native disable); restorable on enable"
            ),
            ApplyOperation(
                kind: .writeFile,
                path: OrbitaDisabledStore.sidecarPath(forEntryDirectory: entryDirectory).path,
                content: OrbitaDisabledStore.sidecarJSON(
                    capabilityID: manifestCapabilityID(for: capability),
                    name: capability.name,
                    type: capability.type.rawValue,
                    originalSourcePath: sourcePath,
                    scope: capability.scope.rawValue
                ),
                risk: .write,
                description: "Write co-located restore metadata so the disabled item survives loss of .agents/manifest.json"
            )
        ]
    }

    /// True when the host owns a native, non-destructive disable for this capability — so Orbita must never
    /// physically move it. Keyed on the native-lifecycle metadata the scanner attaches (Codex
    /// `codexSkillConfigPath`/`codexDisableCommand`, Claude `claudeSkillDisableCommand`, plugin
    /// `disableCommand`) plus the Claude-native source kinds. Trae/Cursor skills carry none of these.
    private func hasNativeDisable(_ capability: Capability) -> Bool {
        let metadata = capability.metadata
        if metadata["codexSkillConfigPath"] != nil
            || metadata["codexDisableCommand"] != nil
            || metadata["claudeSkillDisableCommand"] != nil
            || metadata["disableCommand"] != nil {
            return true
        }
        switch capability.source.kind {
        case "claude-plugin",
             "claude-plugin-skill",
             "claude-plugin-command",
             "claude-plugin-hook",
             "claude-skill",
             "claude-settings",
             "claude-settings-hook":
            return true
        default:
            return false
        }
    }

    private func restoreOperation(for capability: Capability, graph: CapabilityGraph) -> ApplyOperation? {
        // Deterministic first (form-stable): the new scope-correct store path, then the legacy
        // `.orbita/cache/disabled` location for entries quarantined before the data-grade store existed.
        // This covers the normal case AND the manifest-lost case (the scanner-reconstructed tile still
        // carries the original sourcePath + capabilityID, so the same key recomputes the same path).
        if let sourcePath = cacheableSourcePath(for: capability) {
            let candidates = [
                disabledQuarantineContentPath(for: capability, sourcePath: sourcePath, graph: graph),
                legacyDisabledCachePath(for: capability, sourcePath: sourcePath, graph: graph)
            ]
            for candidate in candidates where fileManager.fileExists(atPath: candidate) {
                return ApplyOperation(
                    kind: .restorePath,
                    path: candidate,
                    target: sourcePath,
                    risk: .write,
                    description: "Restore capability source from the Orbita disabled store"
                )
            }
        }

        // Final fallback — manifest-independent: locate the entry by its co-located sidecar (capabilityID
        // match) for the rare case where the deterministic key no longer matches (e.g. the capability id or
        // source path drifted since it was disabled).
        let roots = OrbitaDisabledStore.roots(
            projectRoot: URL(fileURLWithPath: graph.projectRoot),
            home: homeDirectory,
            includeUserScope: true
        )
        let capabilityID = manifestCapabilityID(for: capability)
        let preferredSource = manifestSourcePath(for: capability)
        // `entries()` returns filesystem-enumeration order, which is non-deterministic. When more than one
        // entry shares a capabilityID (entry dirs are keyed by fnv1a(capabilityID|sourcePath), so distinct
        // source paths collide on id), pick stably: prefer the entry whose original source matches this
        // capability, otherwise the lexicographically-first contentPath — never whatever the FS yields first.
        let matches = OrbitaDisabledStore.entries(roots: roots, fileManager: fileManager)
            .filter { $0.capabilityID == capabilityID }
            .sorted { $0.contentPath < $1.contentPath }
        if let entry = matches.first(where: { $0.originalSourcePath == preferredSource }) ?? matches.first {
            return ApplyOperation(
                kind: .restorePath,
                path: entry.contentPath,
                target: entry.originalSourcePath,
                risk: .write,
                description: "Restore capability source from the Orbita disabled store"
            )
        }
        return nil
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
            || components.contains(".trae")
    }

    private func disabledQuarantineContentPath(for capability: Capability, sourcePath: String, graph: CapabilityGraph) -> String {
        OrbitaDisabledStore.contentPath(
            capabilityID: manifestCapabilityID(for: capability),
            type: capability.type.rawValue,
            sourcePath: sourcePath,
            projectRoot: URL(fileURLWithPath: graph.projectRoot),
            home: homeDirectory
        ).path
    }

    /// Pre-migration location (`<project>/.orbita/cache/disabled/...`) — READ-ONLY, consulted only so an
    /// entry quarantined before the scope-correct data-grade store existed can still be restored.
    private func legacyDisabledCachePath(for capability: Capability, sourcePath: String, graph: CapabilityGraph) -> String {
        let key = OrbitaDisabledStore.fnv1a("\(manifestCapabilityID(for: capability))|\(sourcePath)")
        let sourceName = URL(fileURLWithPath: sourcePath).lastPathComponent
        return URL(fileURLWithPath: graph.projectRoot)
            .appendingPathComponent(".orbita/cache/disabled")
            .appendingPathComponent(capability.type.rawValue)
            .appendingPathComponent(key)
            .appendingPathComponent(sourceName.isEmpty ? "source" : sourceName)
            .path
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
    private let homeDirectory: URL

    public init(
        fileManager: FileManager = .default,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) {
        self.fileManager = fileManager
        self.homeDirectory = homeDirectory
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
                // A grouped fork writes copies/links into several external agent homes. On a mid-plan
                // failure, best-effort undo the writes that already landed OUTSIDE the project's .agents/
                // .orbita (i.e. the fork footprint) so the user isn't left with a half-applied scatter.
                // Internal .agents/.orbita ops are intentionally left in place (idempotent; some plans rely
                // on partial-state + rescan reconciliation).
                bestEffortCompensateExternalWrites(completed, agentsRoot: agentsRoot, orbitaRoot: orbitaRoot)
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

    private func bestEffortCompensateExternalWrites(_ completed: [ApplyOperation], agentsRoot: URL, orbitaRoot: URL) {
        let agentsPath = resolvedRootPath(agentsRoot.path)
        let orbitaPath = resolvedRootPath(orbitaRoot.path)
        func isInternal(_ path: String) -> Bool {
            let normalized = containmentPath(path)
            return normalized == agentsPath || normalized.hasPrefix(agentsPath + "/")
                || normalized == orbitaPath || normalized.hasPrefix(orbitaPath + "/")
        }
        for operation in completed.reversed() {
            switch operation.kind {
            case .createSymlink:
                guard !isInternal(operation.path),
                      (try? fileManager.destinationOfSymbolicLink(atPath: operation.path)) != nil else { continue }
                try? fileManager.removeItem(atPath: operation.path)
            case .copyPath:
                guard let target = operation.target, !isInternal(target),
                      fileManager.fileExists(atPath: target) else { continue }
                try? fileManager.removeItem(atPath: target)
            case .createDirectory:
                // Only remove a directory this plan created if we left it empty — never delete a
                // pre-existing populated agent home.
                guard !isInternal(operation.path),
                      let contents = try? fileManager.contentsOfDirectory(atPath: operation.path),
                      contents.isEmpty else { continue }
                try? fileManager.removeItem(atPath: operation.path)
            default:
                continue
            }
        }
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
        case .copyPath:
            guard let target = operation.target else {
                throw OrbitaError.invalidApplyPlan("Missing copy target for \(operation.path)")
            }
            // Fork copies into real agent homes: re-assert the planner's no-clobber rule at write time so a
            // file that appeared after the plan was built (TOCTOU) or a stale re-applied plan cannot silently
            // delete a user's existing skill/command/agent. Only a same-source managed link may be replaced.
            try copyReplacingItem(from: operation.path, to: target, refuseForeignDestination: true)
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

    private func copyReplacingItem(from sourcePath: String, to destinationPath: String, refuseForeignDestination: Bool = false) throws {
        guard fileManager.fileExists(atPath: sourcePath) || (try? fileManager.destinationOfSymbolicLink(atPath: sourcePath)) != nil else {
            throw OrbitaError.invalidApplyPlan("Source does not exist: \(sourcePath)")
        }
        let destinationURL = URL(fileURLWithPath: destinationPath)
        let parent = destinationURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
        let destinationExists = fileManager.fileExists(atPath: destinationPath) || (try? fileManager.destinationOfSymbolicLink(atPath: destinationPath)) != nil
        if destinationExists {
            if refuseForeignDestination, !destinationResolvesToSameSource(destinationPath, sourcePath: sourcePath) {
                throw OrbitaError.invalidApplyPlan("Path already exists and is not a managed link to the same source: \(destinationPath)")
            }
            try fileManager.removeItem(atPath: destinationPath)
        }
        try fileManager.copyItem(atPath: sourcePath, toPath: destinationPath)
    }

    /// True only when `destinationPath` is a symlink resolving to the same on-disk source — the one case
    /// the planner permits replacing. Used to keep the sync copy path from clobbering an unrelated file.
    private func destinationResolvesToSameSource(_ destinationPath: String, sourcePath: String) -> Bool {
        guard let existing = try? fileManager.destinationOfSymbolicLink(atPath: destinationPath) else { return false }
        let parent = URL(fileURLWithPath: destinationPath).deletingLastPathComponent()
        let resolved = existing.hasPrefix("/")
            ? URL(fileURLWithPath: existing)
            : parent.appendingPathComponent(existing)
        return resolved.standardizedFileURL.resolvingSymlinksInPath().path
            == URL(fileURLWithPath: sourcePath).standardizedFileURL.resolvingSymlinksInPath().path
    }

    private func validate(operation: ApplyOperation, action: ApplyAction, agentsRoot: URL, orbitaRoot: URL) throws {
        guard operation.kind != .readSource else { return }
        let operationPath = containmentPath(operation.path)
        let projectRootPath = resolvedRootPath(agentsRoot.deletingLastPathComponent().path)
        let agentsRootPath = resolvedRootPath(agentsRoot.path)
        let orbitaRootPath = resolvedRootPath(orbitaRoot.path)
        func isProjectPath(_ path: String) -> Bool {
            path == projectRootPath || path.hasPrefix(projectRootPath + "/")
        }
        func isInternalProjectStoragePath(_ path: String) -> Bool {
            path == agentsRootPath
                || path.hasPrefix(agentsRootPath + "/")
                || path == orbitaRootPath
                || path.hasPrefix(orbitaRootPath + "/")
        }
        // Delete/disable removals are bounded to the project tree or known agent storage. Legitimate
        // hard-deletes target a source inside the project (e.g. node_modules package skills) or a fork in
        // an agent home; this still closes the "trust whatever path the metadata held" hole for a path that
        // is outside BOTH the project and every known agent root (e.g. a hand-edited skillsInstallTargets).
        if operation.kind == .removePath, action == .delete || action == .disable {
            guard isProjectPath(operationPath)
                || isInternalProjectStoragePath(operationPath)
                || isAgentStoragePath(operationPath, projectRoot: projectRootPath) else {
                throw OrbitaError.invalidApplyPlan("Delete target is outside the project and known agent storage: \(operation.path)")
            }
            return
        }
        switch operation.kind {
        case .cachePath:
            guard let target = operation.target else {
                throw OrbitaError.invalidApplyPlan("Missing cache target for \(operation.path)")
            }
            guard isAgentStoragePath(operationPath, projectRoot: projectRootPath) else {
                throw OrbitaError.invalidApplyPlan("Cache source is outside known agent storage: \(operation.path)")
            }
            let targetPath = containmentPath(target)
            guard isDisabledStorePath(targetPath, projectRootPath: projectRootPath) else {
                throw OrbitaError.invalidApplyPlan("Disabled-store target is outside .orbita/disabled: \(target)")
            }
        case .restorePath:
            guard let target = operation.target else {
                throw OrbitaError.invalidApplyPlan("Missing restore target for \(operation.path)")
            }
            // Source must live in a quarantine store: the project's `.orbita` (covers both the new
            // `.orbita/disabled` store and the legacy `.orbita/cache/disabled` location) or the user store.
            guard operationPath == orbitaRootPath
                || operationPath.hasPrefix(orbitaRootPath + "/")
                || isDisabledStorePath(operationPath, projectRootPath: projectRootPath) else {
                throw OrbitaError.invalidApplyPlan("Restore source is outside the Orbita disabled store: \(operation.path)")
            }
            let targetPath = containmentPath(target)
            guard isAgentStoragePath(targetPath, projectRoot: projectRootPath) else {
                throw OrbitaError.invalidApplyPlan("Restore target is outside known agent storage: \(target)")
            }
        case .createDirectory, .createSymlink:
            let destinationIsAllowed = isInternalProjectStoragePath(operationPath) || isAgentStoragePath(operationPath, projectRoot: projectRootPath)
            guard destinationIsAllowed else {
                throw OrbitaError.invalidApplyPlan("Operation is outside known agent storage: \(operation.path)")
            }
            if operation.kind == .createSymlink,
               let target = operation.target {
                // Relative targets (project-scope forks) resolve against the link's own directory, not CWD.
                let resolvedTargetURL = target.hasPrefix("/")
                    ? URL(fileURLWithPath: target)
                    : URL(fileURLWithPath: operation.path).deletingLastPathComponent().appendingPathComponent(target)
                let targetPath = containmentPath(resolvedTargetURL.path)
                guard isProjectPath(targetPath) || isAgentStoragePath(targetPath, projectRoot: projectRootPath) else {
                    throw OrbitaError.invalidApplyPlan("Symlink target is outside known agent storage: \(target)")
                }
            }
        case .copyPath:
            guard let target = operation.target else {
                throw OrbitaError.invalidApplyPlan("Missing copy target for \(operation.path)")
            }
            guard isProjectPath(operationPath) || isAgentStoragePath(operationPath, projectRoot: projectRootPath) else {
                throw OrbitaError.invalidApplyPlan("Copy source is outside known agent storage: \(operation.path)")
            }
            let targetPath = containmentPath(target)
            guard isInternalProjectStoragePath(targetPath) || isAgentStoragePath(targetPath, projectRoot: projectRootPath) else {
                throw OrbitaError.invalidApplyPlan("Copy target is outside known agent storage: \(target)")
            }
        default:
            guard operationPath == agentsRootPath
                || operationPath.hasPrefix(agentsRootPath + "/")
                || operationPath == orbitaRootPath
                || operationPath.hasPrefix(orbitaRootPath + "/")
                || isDisabledStorePath(operationPath, projectRootPath: projectRootPath)
            else {
                throw OrbitaError.invalidApplyPlan("Operation is outside .agents or .orbita: \(operation.path)")
            }
        }
    }

    /// The scope-correct disabled-store roots: the project's `<repo>/.orbita/disabled` and the user's
    /// `~/.orbita/disabled`. Anchored (resolving symlinks) so it is a true last line of defense, not a
    /// "path contains .orbita" membership test. The user store is Orbita's own state dir, so this widens
    /// the write boundary only to a location Orbita already owns — never into an agent's or a foreign tree.
    private func isDisabledStorePath(_ path: String, projectRootPath: String) -> Bool {
        let stores = [
            resolvedRootPath(projectRootPath + "/.orbita/" + OrbitaDisabledStore.directoryName),
            resolvedRootPath(homeDirectory.path + "/.orbita/" + OrbitaDisabledStore.directoryName)
        ]
        return stores.contains { path == $0 || path.hasPrefix($0 + "/") }
    }

    /// Agent-sync (fork) is allowed to write into agent storage. To keep the guard a true last line of
    /// defense (not merely "some path component is literally named .codex"), the allowed set is anchored:
    /// the project's own agent dotdirs, the same dotdirs under the real user home, and the concrete
    /// `globalSkillsDir` roots from SkillsAgentCatalog. A path like /tmp/x/.claude/y no longer passes.
    private func isAgentStoragePath(_ path: String, projectRoot: String) -> Bool {
        let home = homeDirectory.path
        var rawRoots: [String] = []
        for dotDir in [".agents", ".codex", ".claude", ".cursor", ".trae"] {
            rawRoots.append(projectRoot + "/" + dotDir)
            rawRoots.append(home + "/" + dotDir)
        }
        for agent in SkillsAgentCatalog.agents {
            guard let globalSkillsDir = agent.globalSkillsDir else { continue }
            rawRoots.append(globalSkillsDir)
        }
        // Canonicalize each allow-root (resolving symlinks, incl. a dotdir that is itself a symlink) so the
        // comparison is against real on-disk locations, matching how `path` was produced.
        let allowedRoots = rawRoots.map { resolvedRootPath($0) }
        return allowedRoots.contains { path == $0 || path.hasPrefix($0 + "/") }
    }

    /// Containment path for an operation target: resolves symbolic links in the PARENT chain — so an
    /// ancestor symlink cannot smuggle a write outside an allowed root — while keeping the final path
    /// component literal, because that leaf may be a symlink we are about to create or remove (both
    /// `removeItem` and `createSymbolicLink` act on the link itself, never following it). `standardizedFileURL`
    /// alone is purely lexical (`.`/`..`) and would let `<project>/<symlink-to-/etc>/x` pass as in-project
    /// while the OS-level file op landed on `/etc/x`.
    private func containmentPath(_ rawPath: String) -> String {
        let url = URL(fileURLWithPath: rawPath).standardizedFileURL
        let leaf = url.lastPathComponent
        let resolvedParent = url.deletingLastPathComponent().resolvingSymlinksInPath()
        let combined = leaf.isEmpty ? resolvedParent : resolvedParent.appendingPathComponent(leaf)
        return normalizedContainmentPath(combined.standardizedFileURL.path)
    }

    /// Containment path for an allow-root / known directory: fully resolves symbolic links (the root is a
    /// real directory we are comparing against, so following its own symlink is correct).
    private func resolvedRootPath(_ rawPath: String) -> String {
        normalizedContainmentPath(URL(fileURLWithPath: rawPath).resolvingSymlinksInPath().standardizedFileURL.path)
    }

    /// Maps the macOS `/private` firmlinks back to their conventional form so both sides of a containment
    /// check agree regardless of which alias a path arrived in. `resolvingSymlinksInPath()` canonicalizes
    /// `/var`, `/tmp`, and `/etc` to their `/private/...` realpath; strip that prefix uniformly.
    private func normalizedContainmentPath(_ path: String) -> String {
        for firmlink in ["/private/var/", "/private/tmp/", "/private/etc/"] {
            if path.hasPrefix(firmlink) {
                return String(path.dropFirst("/private".count))
            }
        }
        return path
    }
}
