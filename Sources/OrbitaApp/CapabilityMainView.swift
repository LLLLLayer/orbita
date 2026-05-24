import SwiftUI
import OrbitaCore

struct CapabilityMainView: View {
    let projectName: String
    let hasActiveContext: Bool
    let graph: CapabilityGraph?
    let isScanning: Bool
    let scanMessage: String?
    let scanProgress: Double
    let lastRefreshLabel: String
    let errorMessage: String?
    @Binding var selectedAgent: AgentSelection?
    @Binding var selectedGroup: CapabilityCategory
    let agentOptions: [AgentSelection]
    let displaySections: [CapabilityCollectionSection]
    @Binding var selectedCapability: Capability?
    @Binding var expandedGroupIDs: Set<String>
    let onAddAgent: () -> Void
    let onOpenProject: () -> Void
    let onRefresh: () -> Void
    let onMerge: () -> Void
    let onClean: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let graph {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        HeaderSurface(
                            projectName: projectName,
                            graph: graph,
                            selectedAgent: selectedAgent,
                            isScanning: isScanning,
                            lastRefreshLabel: lastRefreshLabel,
                            onRefresh: onRefresh,
                            onMerge: onMerge,
                            onClean: onClean
                        )

                        if isScanning {
                            ScanningProgressCard(
                                message: scanMessage ?? "Scanning \(projectName)",
                                progress: scanProgress
                            )
                        }

                        CapabilityFilterBar(
                            agentOptions: agentOptions,
                            selectedAgent: $selectedAgent,
                            selectedGroup: $selectedGroup,
                            onAddAgent: onAddAgent
                        )

                        if displaySections.isEmpty {
                            ContentUnavailableView("No capabilities", systemImage: "tray")
                                .frame(maxWidth: .infinity, minHeight: 280)
                        } else {
                            CapabilityCollectionView(
                                sections: displaySections,
                                selectedCapability: $selectedCapability,
                                expandedGroupIDs: $expandedGroupIDs
                            )
                            .padding(.top, 4)
                        }
                    }
                    .padding(.top, 28)
                    .padding(.horizontal, 28)
                    .padding(.bottom, 28)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            } else if isScanning || hasActiveContext {
                ProjectLoadingView(
                    projectName: projectName,
                    message: scanMessage ?? "Scanning \(projectName)",
                    progress: scanProgress,
                    isScanning: isScanning,
                    lastRefreshLabel: lastRefreshLabel,
                    errorMessage: errorMessage,
                    onRefresh: onRefresh
                )
                .padding(.top, 28)
                .padding(.horizontal, 28)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.opacity)
            } else if let errorMessage {
                VStack {
                    ContentUnavailableView(
                        "Unable to scan",
                        systemImage: "exclamationmark.triangle",
                        description: Text(errorMessage)
                    )
                    .frame(maxWidth: .infinity, minHeight: 500)
                }
                .padding(.top, 28)
                .padding(.horizontal, 28)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack {
                    EmptyProjectView(onOpenProject: onOpenProject)
                        .frame(maxWidth: .infinity, minHeight: 560)
                }
                .padding(.top, 28)
                .padding(.horizontal, 28)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.55))
    }
}

private struct HeaderSurface: View {
    let projectName: String
    let graph: CapabilityGraph
    let selectedAgent: AgentSelection?
    let isScanning: Bool
    let lastRefreshLabel: String
    let onRefresh: () -> Void
    let onMerge: () -> Void
    let onClean: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(projectName)
                        .font(.title2.weight(.semibold))
                        .lineLimit(1)
                }

                Spacer(minLength: 16)

                HeaderCommandButton("Merge", systemImage: "arrow.triangle.merge", action: onMerge)
                HeaderCommandButton("Clean", systemImage: "sparkles", action: onClean)
                HeaderRefreshButton(title: lastRefreshLabel, isScanning: isScanning, action: onRefresh)
            }

            HStack(spacing: 18) {
                SummaryStat(title: "Total", value: graph.capabilities.count, systemImage: "square.grid.2x2")
                SummaryStat(title: "Plugins", value: count(.plugin), systemImage: "shippingbox")
                SummaryStat(title: "Drift", value: statusCount(.drifted), systemImage: "arrow.triangle.branch")
                SummaryStat(title: "Review", value: statusCount(.risky), systemImage: "exclamationmark.triangle")
                if isScanning {
                    Label("Scanning", systemImage: "dot.radiowaves.left.and.right")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }

            if selectedAgent == nil {
                SourceOverviewStrip(
                    capabilities: graph.capabilities,
                    overview: AgentOverviewBuilder().overview(graph: graph)
                )
            }
        }
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.secondary.opacity(0.12))
        }
    }

    private func count(_ type: CapabilityType) -> Int {
        graph.capabilities.filter { $0.type == type }.count
    }

    private func statusCount(_ status: CapabilityStatus) -> Int {
        graph.capabilities.filter { $0.statuses.contains(status) }.count
    }
}

private struct ProjectLoadingView: View {
    let projectName: String
    let message: String
    let progress: Double
    let isScanning: Bool
    let lastRefreshLabel: String
    let errorMessage: String?
    let onRefresh: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(projectName)
                        .font(.title2.weight(.semibold))
                        .lineLimit(1)
                    Text(lastRefreshLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                HeaderRefreshButton(title: lastRefreshLabel, isScanning: isScanning, action: onRefresh)
            }
            .padding(16)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(.secondary.opacity(0.12))
            }

            if let errorMessage {
                ContentUnavailableView(
                    "Unable to scan",
                    systemImage: "exclamationmark.triangle",
                    description: Text(errorMessage)
                )
                .frame(maxWidth: .infinity, minHeight: 420)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        ProgressView()
                            .controlSize(.small)
                        Text(message)
                            .font(.subheadline.weight(.medium))
                        Spacer()
                        Text("\(Int(progress * 100))%")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    ProgressView(value: max(progress, 0.04), total: 1)
                        .progressViewStyle(.linear)
                }
                .padding(16)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(.secondary.opacity(0.12))
                }
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct SummaryStat: View {
    let title: String
    let value: Int
    let systemImage: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text("\(value)")
                    .font(.headline.monospacedDigit())
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(minWidth: 92, alignment: .leading)
    }
}

private struct HeaderCommandButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    init(_ title: String, systemImage: String, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.medium))
                .labelStyle(.titleAndIcon)
                .padding(.horizontal, 10)
                .frame(height: 30)
        }
        .buttonStyle(.plain)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct HeaderIconButton: View {
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .medium))
                .frame(width: 30, height: 30)
        }
        .buttonStyle(.plain)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct HeaderRefreshButton: View {
    let title: String
    let isScanning: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: isScanning ? "dot.radiowaves.left.and.right" : "arrow.clockwise")
                .font(.subheadline.weight(.medium))
                .labelStyle(.titleAndIcon)
                .lineLimit(1)
                .padding(.horizontal, 10)
                .frame(height: 30)
        }
        .buttonStyle(.plain)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .help("Refresh")
    }
}

struct CapabilityFilterBar: View {
    let agentOptions: [AgentSelection]
    @Binding var selectedAgent: AgentSelection?
    @Binding var selectedGroup: CapabilityCategory
    let onAddAgent: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                FilterChip(title: "Overview", systemImage: "square.grid.2x2", isSelected: selectedAgent == nil) {
                    withAnimation(.snappy(duration: 0.18)) {
                        selectedAgent = nil
                    }
                }
                ForEach(agentOptions) { agent in
                    FilterChip(title: agent.displayName, systemImage: agent.systemImage, isSelected: selectedAgent == agent) {
                        withAnimation(.snappy(duration: 0.18)) {
                            selectedAgent = agent
                        }
                    }
                }
                Button(action: onAddAgent) {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .help("Add coding agent")
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    ForEach(CapabilityCategory.allCases) { category in
                        FilterChip(title: category.title, isSelected: selectedGroup == category) {
                            withAnimation(.snappy(duration: 0.18)) {
                                selectedGroup = category
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct FilterChip: View {
    let title: String
    var systemImage: String?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 13, weight: .medium))
                        .frame(width: 15)
                }
                Text(title)
                    .font(.subheadline.weight(isSelected ? .semibold : .regular))
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .frame(height: 30)
            .foregroundStyle(isSelected ? .white : .primary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? Color.accentColor : Color.secondary.opacity(0.08))
        }
        .scaleEffect(isSelected ? 1.02 : 1)
        .animation(.snappy(duration: 0.16), value: isSelected)
    }
}

private struct SourceOverviewStrip: View {
    let capabilities: [Capability]
    let overview: AgentCapabilityOverview

    var body: some View {
        HStack(spacing: 8) {
            ForEach(sourceSummaries, id: \.kind) { summary in
                HStack(spacing: 10) {
                    Image(systemName: summary.kind.systemImage)
                        .foregroundStyle(.secondary)
                        .frame(width: 18)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(summary.kind.title)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        Text(subtitle(for: summary))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(.secondary.opacity(0.1))
                }
            }
        }
    }

    private var sourceSummaries: [SourceSummary] {
        let grouped = Dictionary(grouping: capabilities, by: CapabilitySourceClassifier.sourceKind(for:))
        let agentSummaries = Dictionary(uniqueKeysWithValues: overview.agentSummaries.map { ($0.agent, $0) })
        return CapabilitySourceClassifier.SourceKind.headerKinds
            .map { kind in
                SourceSummary(
                    kind: kind,
                    count: grouped[kind]?.count ?? 0,
                    agentSummary: agentSummary(for: kind, in: agentSummaries)
                )
            }
    }

    private func subtitle(for summary: SourceSummary) -> String {
        guard let agentSummary = summary.agentSummary else {
            return ".agents - \(summary.count) capabilities"
        }
        return "\(agentSummary.visibleCount) visible, \(agentSummary.hiddenCount) hidden · \(summary.kind.sourceRoot) \(summary.count)"
    }

    private func agentSummary(
        for kind: CapabilitySourceClassifier.SourceKind,
        in summaries: [AgentID: AgentCapabilitySummary]
    ) -> AgentCapabilitySummary? {
        switch kind {
        case .codex:
            return summaries[.codex]
        case .claude:
            return summaries[.claudeCode]
        default:
            return nil
        }
    }

    private struct SourceSummary {
        let kind: CapabilitySourceClassifier.SourceKind
        let count: Int
        let agentSummary: AgentCapabilitySummary?
    }
}

struct ScanningProgressCard: View {
    let message: String
    let progress: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                Text(message)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Spacer()
                Text("\(Int(progress * 100))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: progress, total: 1)
                .progressViewStyle(.linear)
        }
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(.secondary.opacity(0.12))
        }
    }
}

private struct EmptyProjectView: View {
    let onOpenProject: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 42, weight: .regular))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)

            VStack(spacing: 6) {
                Text("Open a project")
                    .font(.title2.weight(.semibold))
                Text("Choose a repository to inspect local coding-agent capabilities.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button(action: onOpenProject) {
                Label("Open Project...", systemImage: "folder.badge.plus")
                    .frame(minWidth: 136)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .frame(maxWidth: 420)
    }
}
