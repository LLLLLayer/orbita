import OrbitaCore

enum CapabilityDisplayText {
    @MainActor static func accessSummary(for risks: [RiskLevel]) -> String {
        let visibleRisks = risks.filter { $0 != .info }
        guard !visibleRisks.isEmpty else {
            return L("risk.info")
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
    @MainActor var accessLabel: String {
        switch self {
        case .info:
            return L("risk.info")
        case .read:
            return L("risk.read")
        case .write:
            return L("risk.write")
        case .exec:
            return L("risk.exec")
        case .network:
            return L("risk.network")
        case .secret:
            return L("risk.secret")
        case .global:
            return L("risk.global")
        }
    }
}

extension ApplyAction {
    @MainActor var displayTitle: String {
        switch self {
        case .enable:
            return L("inspector.action.enable")
        case .disable:
            return L("inspector.action.disable")
        case .delete:
            return L("inspector.action.delete")
        case .merge:
            return L("applyAction.merge")
        case .rollback:
            return L("applyAction.rollback")
        case .clean:
            return L("applyAction.clean")
        }
    }
}

extension ApplyOperationKind {
    @MainActor var displayTitle: String {
        switch self {
        case .readSource:
            return L("op.readSource")
        case .createDirectory:
            return L("op.createDirectory")
        case .createSymlink:
            return L("op.createSymlink")
        case .copyPath:
            return L("op.copyPath")
        case .cachePath:
            return L("op.cachePath")
        case .restorePath:
            return L("op.restorePath")
        case .removePath:
            return L("op.removePath")
        case .writeFile:
            return L("op.writeFile")
        case .appendLog:
            return L("op.appendLog")
        }
    }
}
