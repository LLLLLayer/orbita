import Foundation
import OrbitaCore

enum CapabilitySourceClassifier {
    @MainActor
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
            return L("source.packages.lower")
        case .project:
            return L("source.project.lower")
        case .other:
            return capability.scope.rawValue
        }
    }

    static func sourceKind(for capability: Capability) -> SourceKind {
        let kind = sourceKind(forPath: classificationPath(for: capability), sourceKind: capability.source.kind)
        if kind == .other, capability.scope == .project {
            return .project
        }
        return kind
    }

    /// Classify a bare on-disk path (plus its `source.kind`, used only to recognise
    /// Cursor rule files that don't live under `/.cursor/`). Shared by `sourceKind(for:)`
    /// and the drift-locations panel, which has a path string but no full `Capability`.
    /// Returns `.other` when nothing matches — the project-scope fallback lives in the
    /// capability-aware overload because a bare path carries no scope.
    static func sourceKind(forPath path: String, sourceKind kind: String = "") -> SourceKind {
        if path.contains("/.agents/") {
            return .agents
        }
        if path.contains("/.codex/") {
            return .codex
        }
        if path.contains("/.claude/") {
            return .claude
        }
        if path.contains("/.cursor/") || kind == "legacy-cursor-rule" || kind == "cursor-rule" {
            return .cursor
        }
        if path.contains("/.trae/") {
            return .trae
        }
        if path.contains("/node_modules/") {
            return .packages
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

        @MainActor
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
                return L("source.packages")
            case .project:
                return L("source.project")
            case .other:
                return L("source.other")
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
