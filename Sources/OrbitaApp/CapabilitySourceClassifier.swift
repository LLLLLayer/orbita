import Foundation
import OrbitaCore

enum CapabilitySourceClassifier {
    static func label(for capability: Capability) -> String {
        switch sourceKind(for: capability) {
        case .agents:
            return "Agents"
        case .codex:
            return "Codex"
        case .claude:
            return "Claude"
        case .packages:
            return "package"
        case .project:
            return "project"
        case .other:
            return capability.scope.rawValue
        }
    }

    static func sourceKind(for capability: Capability) -> SourceKind {
        let path = capability.source.path
        if path.contains("/.agents/") {
            return .agents
        }
        if path.contains("/.codex/") {
            return .codex
        }
        if path.contains("/.claude/") {
            return .claude
        }
        if path.contains("/node_modules/") {
            return .packages
        }
        if capability.scope == .project {
            return .project
        }
        return .other
    }

    enum SourceKind: String, CaseIterable {
        case agents
        case codex
        case claude
        case packages
        case project
        case other

        static let headerKinds: [SourceKind] = [.agents, .codex, .claude]

        var title: String {
            switch self {
            case .agents:
                return "Agents"
            case .codex:
                return "Codex"
            case .claude:
                return "Claude"
            case .packages:
                return "Packages"
            case .project:
                return "Project"
            case .other:
                return "Other"
            }
        }

        var systemImage: String {
            switch self {
            case .agents:
                return "point.3.connected.trianglepath.dotted"
            case .codex:
                return "command"
            case .claude:
                return "text.bubble"
            case .packages:
                return "shippingbox"
            case .project:
                return "folder"
            case .other:
                return "questionmark.square"
            }
        }

        var sourceRoot: String {
            switch self {
            case .agents:
                return ".agents"
            case .codex:
                return ".codex"
            case .claude:
                return ".claude"
            case .packages:
                return "node_modules"
            case .project:
                return "project"
            case .other:
                return "other"
            }
        }

    }
}
