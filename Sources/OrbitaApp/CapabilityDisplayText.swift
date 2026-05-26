import OrbitaCore

enum CapabilityDisplayText {
    static func accessSummary(for risks: [RiskLevel]) -> String {
        let visibleRisks = risks.filter { $0 != .info }
        guard !visibleRisks.isEmpty else {
            return "Metadata only"
        }
        return visibleRisks
            .sorted { accessRank($0) < accessRank($1) }
            .map(\.accessLabel)
            .joined(separator: ", ")
    }

    private static func accessRank(_ risk: RiskLevel) -> Int {
        switch risk {
        case .info:
            return 0
        case .read:
            return 1
        case .write:
            return 2
        case .exec:
            return 3
        case .network:
            return 4
        case .secret:
            return 5
        case .global:
            return 6
        }
    }
}

extension RiskLevel {
    var accessLabel: String {
        switch self {
        case .info:
            return "Metadata only"
        case .read:
            return "Reads files"
        case .write:
            return "Writes files"
        case .exec:
            return "Runs commands"
        case .network:
            return "Network access"
        case .secret:
            return "Secrets/env"
        case .global:
            return "Global scope"
        }
    }
}

extension ApplyAction {
    var displayTitle: String {
        switch self {
        case .enable:
            return "Enable"
        case .disable:
            return "Disable"
        case .delete:
            return "Delete"
        case .merge:
            return "Merge into .agents"
        case .rollback:
            return "Rollback"
        case .clean:
            return "Clean"
        }
    }
}

extension ApplyOperationKind {
    var displayTitle: String {
        switch self {
        case .readSource:
            return "Read source"
        case .createDirectory:
            return "Create folder"
        case .createSymlink:
            return "Create link"
        case .cachePath:
            return "Cache source"
        case .restorePath:
            return "Restore source"
        case .removePath:
            return "Remove path"
        case .writeFile:
            return "Write file"
        case .appendLog:
            return "Append log"
        }
    }
}
