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
        case .cursor:
            return "Cursor"
        case .trae:
            return "Trae"
        case .packages:
            return "package"
        case .project:
            return "project"
        case .other:
            return capability.scope.rawValue
        }
    }

    static func sourceKind(for capability: Capability) -> SourceKind {
        let path = classificationPath(for: capability)
        if path.contains("/.agents/") {
            return .agents
        }
        if path.contains("/.codex/") {
            return .codex
        }
        if path.contains("/.claude/") {
            return .claude
        }
        if path.contains("/.cursor/") || capability.source.kind == "legacy-cursor-rule" || capability.source.kind == "cursor-rule" {
            return .cursor
        }
        if path.contains("/.trae/") {
            return .trae
        }
        if path.contains("/node_modules/") {
            return .packages
        }
        if capability.scope == .project {
            return .project
        }
        return .other
    }

    private static func classificationPath(for capability: Capability) -> String {
        if let path = capability.metadata["sourcePath"],
           !path.isEmpty,
           !isInternalOrbitaPath(path) {
            return path
        }
        return capability.source.path
    }

    private static func isInternalOrbitaPath(_ path: String) -> Bool {
        path.contains("/.orbita/")
    }

    enum SourceKind: String, CaseIterable {
        case agents
        case codex
        case claude
        case cursor
        case trae
        case packages
        case project
        case other

        static let headerKinds: [SourceKind] = [.agents, .codex, .claude, .cursor, .trae]

        var title: String {
            switch self {
            case .agents:
                return "Agents"
            case .codex:
                return "Codex"
            case .claude:
                return "Claude"
            case .cursor:
                return "Cursor"
            case .trae:
                return "Trae"
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
            case .cursor:
                return "cursorarrow.rays"
            case .trae:
                return "sparkles"
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
            case .cursor:
                return ".cursor"
            case .trae:
                return ".trae"
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
