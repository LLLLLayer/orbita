import Foundation

public enum CapabilityType: String, Codable, CaseIterable, Sendable {
    case plugin
    case skill
    case agent
    case mcpServer
    case rule
    case instruction
    case hook
    case command
    case unknown
}

public enum CapabilityScope: String, Codable, CaseIterable, Sendable {
    case project
    case user
    case installed
    case environment
}

public enum CapabilityStatus: String, Codable, CaseIterable, Sendable {
    case discovered
    case enabled
    case disabled
    case broken
    case shadowed
    case drifted
    case duplicate
    case risky
}

public enum RiskLevel: String, Codable, CaseIterable, Sendable {
    case info
    case read
    case exec
    case network
    case secret
    case write
    case global
}

public enum AgentID: String, Codable, CaseIterable, Sendable {
    case codex
    case claudeCode = "claude-code"
    case cursor
}

public struct CapabilitySource: Codable, Hashable, Sendable {
    public var kind: String
    public var path: String
    public var packageName: String?
    public var inferred: Bool

    public init(kind: String, path: String, packageName: String? = nil, inferred: Bool = false) {
        self.kind = kind
        self.path = path
        self.packageName = packageName
        self.inferred = inferred
    }
}

public struct Capability: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var type: CapabilityType
    public var scope: CapabilityScope
    public var statuses: [CapabilityStatus]
    public var risks: [RiskLevel]
    public var source: CapabilitySource
    public var pluginID: String?
    public var summary: String?
    public var metadata: [String: String]

    public init(
        id: String,
        name: String,
        type: CapabilityType,
        scope: CapabilityScope,
        statuses: [CapabilityStatus] = [.discovered],
        risks: [RiskLevel] = [.info],
        source: CapabilitySource,
        pluginID: String? = nil,
        summary: String? = nil,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.scope = scope
        self.statuses = statuses
        self.risks = risks
        self.source = source
        self.pluginID = pluginID
        self.summary = summary
        self.metadata = metadata
    }
}

public struct ScanIssue: Codable, Hashable, Sendable {
    public enum Severity: String, Codable, Sendable {
        case warning
        case error
    }

    public var severity: Severity
    public var path: String
    public var message: String

    public init(severity: Severity, path: String, message: String) {
        self.severity = severity
        self.path = path
        self.message = message
    }
}

public struct ScanResult: Codable, Sendable {
    public var projectRoot: String
    public var capabilities: [Capability]
    public var issues: [ScanIssue]

    public init(projectRoot: String, capabilities: [Capability], issues: [ScanIssue]) {
        self.projectRoot = projectRoot
        self.capabilities = capabilities
        self.issues = issues
    }
}

public struct CapabilityGraph: Codable, Sendable {
    public var schemaVersion: Int
    public var projectRoot: String
    public var generatedAt: String
    public var capabilities: [Capability]
    public var issues: [ScanIssue]

    public init(
        schemaVersion: Int = 1,
        projectRoot: String,
        generatedAt: String = ISO8601DateFormatter().string(from: Date()),
        capabilities: [Capability],
        issues: [ScanIssue]
    ) {
        self.schemaVersion = schemaVersion
        self.projectRoot = projectRoot
        self.generatedAt = generatedAt
        self.capabilities = capabilities
        self.issues = issues
    }
}

public struct AgentView: Codable, Sendable {
    public var schemaVersion: Int
    public var projectRoot: String
    public var agent: AgentID
    public var visibleCapabilities: [Capability]
    public var hiddenCapabilities: [Capability]

    public init(
        schemaVersion: Int = 1,
        projectRoot: String,
        agent: AgentID,
        visibleCapabilities: [Capability],
        hiddenCapabilities: [Capability]
    ) {
        self.schemaVersion = schemaVersion
        self.projectRoot = projectRoot
        self.agent = agent
        self.visibleCapabilities = visibleCapabilities
        self.hiddenCapabilities = hiddenCapabilities
    }
}

public enum OrbitaError: LocalizedError, Sendable {
    case projectRootNotFound(String)
    case projectRootIsNotDirectory(String)
    case invalidAgent(String)
    case capabilityNotFound(String)
    case invalidApplyPlan(String)

    public var errorDescription: String? {
        switch self {
        case .projectRootNotFound(let path):
            return "Project root does not exist: \(path)"
        case .projectRootIsNotDirectory(let path):
            return "Project root is not a directory: \(path)"
        case .invalidAgent(let value):
            return "Unsupported agent: \(value)"
        case .capabilityNotFound(let id):
            return "Capability not found: \(id)"
        case .invalidApplyPlan(let message):
            return "Invalid apply plan: \(message)"
        }
    }
}
