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

    /// Ordered, de-duplicated, human-readable guidance for each non-`info` risk a
    /// capability requests — token label + a plain-language sentence + an icon — so the
    /// inspector can explain *what* "exec, network, secret" actually means rather than
    /// just listing the tokens.
    @MainActor static func riskGuidance(for risks: [RiskLevel]) -> [RiskGuidance] {
        var seen = Set<RiskLevel>()
        return risks
            .filter { $0 != .info }
            .sorted { accessRank($0) < accessRank($1) }
            .filter { seen.insert($0).inserted }
            .map { RiskGuidance(risk: $0, label: $0.accessLabel, explanation: $0.explanation, systemImage: $0.riskSystemImage) }
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

struct RiskGuidance: Identifiable {
    let risk: RiskLevel
    let label: String
    let explanation: String
    let systemImage: String

    var id: String { risk.rawValue }
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

    @MainActor var explanation: String {
        switch self {
        case .info:
            return L("risk.explain.info")
        case .read:
            return L("risk.explain.read")
        case .write:
            return L("risk.explain.write")
        case .exec:
            return L("risk.explain.exec")
        case .network:
            return L("risk.explain.network")
        case .secret:
            return L("risk.explain.secret")
        case .global:
            return L("risk.explain.global")
        }
    }

    var riskSystemImage: String {
        switch self {
        case .info:
            return "info.circle"
        case .read:
            return "eye"
        case .write:
            return "pencil"
        case .exec:
            return "terminal"
        case .network:
            return "network"
        case .secret:
            return "key"
        case .global:
            return "globe"
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
