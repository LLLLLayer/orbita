import SwiftUI
import UniformTypeIdentifiers
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
    let categoryOptions: [CapabilityCategory]
    let displaySections: [CapabilityCollectionSection]
    @Binding var selectedCapability: Capability?
    @Binding var expandedGroupIDs: Set<String>
    let onAddAgent: () -> Void
    let onMoveAgent: (_ sourceID: String, _ targetID: String) -> Void
    let onPinAgent: (_ agentID: String) -> Void
    let onDeleteAgent: (_ agentID: String) -> Void
    let onMoveCategory: (_ sourceID: String, _ targetID: String) -> Void
    let onPinCategory: (_ categoryID: String) -> Void
    let onHideCategory: (_ categoryID: String) -> Void
    let onHideCategories: () -> Void
    let onOpenProject: () -> Void
    let onRefresh: () -> Void
    let onMerge: () -> Void
    let onClean: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let graph {
                GeometryReader { proxy in
                    let contentPadding = horizontalContentPadding(for: proxy.size.width)
                    let contentWidth = max(1, proxy.size.width - contentPadding * 2)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            HeaderSurface(
                                projectName: projectName,
                                graph: graph,
                                isScanning: isScanning,
                                lastRefreshLabel: lastRefreshLabel,
                                onRefresh: onRefresh,
                                onMerge: onMerge,
                                onClean: onClean
                            )

                            if let errorMessage, !errorMessage.isEmpty {
                                InlineErrorBanner(message: errorMessage)
                            }

                            CapabilityFilterBar(
                                agentOptions: agentOptions,
                                categoryOptions: categoryOptions,
                                selectedAgent: $selectedAgent,
                                selectedGroup: $selectedGroup,
                                onAddAgent: onAddAgent,
                                onMoveAgent: onMoveAgent,
                                onPinAgent: onPinAgent,
                                onDeleteAgent: onDeleteAgent,
                                onMoveCategory: onMoveCategory,
                                onPinCategory: onPinCategory,
                                onHideCategory: onHideCategory,
                                onHideCategories: onHideCategories
                            )

                            if selectedAgent == nil {
                                SourceOverviewStrip(
                                    capabilities: graph.capabilities,
                                    overview: AgentOverviewBuilder().overview(graph: graph)
                                )
                                .transition(.opacity.combined(with: .move(edge: .top)))
                            }

                            if displaySections.isEmpty {
                                EmptyCapabilitiesState()
                                    .frame(
                                        width: contentWidth,
                                        height: emptyStateHeight(for: proxy.size.height),
                                        alignment: .center
                                    )
                            } else {
                                CapabilityCollectionView(
                                    sections: displaySections,
                                    selectedCapability: $selectedCapability,
                                    expandedGroupIDs: $expandedGroupIDs,
                                    availableWidth: contentWidth
                                )
                                .padding(.top, 4)
                            }
                        }
                        .frame(width: contentWidth, alignment: .topLeading)
                        .padding(.top, 20)
                        .padding(.horizontal, contentPadding)
                        .padding(.bottom, 28)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
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
                .padding(.top, 20)
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
                .padding(.top, 20)
                .padding(.horizontal, 28)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack {
                    EmptyProjectView(onOpenProject: onOpenProject)
                        .frame(maxWidth: .infinity, minHeight: 560)
                }
                .padding(.top, 20)
                .padding(.horizontal, 28)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(OrbitaTheme.canvas)
    }

    private func horizontalContentPadding(for width: CGFloat) -> CGFloat {
        if width < 760 {
            return 18
        }
        if width < 980 {
            return 22
        }
        return 28
    }

    private func emptyStateHeight(for height: CGFloat) -> CGFloat {
        max(360, height - 360)
    }
}

private struct HeaderSurface: View {
    let projectName: String
    let graph: CapabilityGraph
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
            }

        }
        .padding(18)
        .orbitaCard(cornerRadius: 22, shadowRadius: 12, shadowY: 7)
    }

    private func count(_ type: CapabilityType) -> Int {
        graph.capabilities.filter { $0.type == type }.count
    }

    private func statusCount(_ status: CapabilityStatus) -> Int {
        graph.capabilities.filter { $0.statuses.contains(status) }.count
    }
}

private struct InlineErrorBanner: View {
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.red)
                .frame(width: 18)
            Text(message)
                .font(.caption.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(3)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.red.opacity(0.18))
        }
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
            .padding(18)
            .orbitaCard(cornerRadius: 22, shadowRadius: 12, shadowY: 7)

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
                .orbitaCard(cornerRadius: 16, shadowRadius: 8, shadowY: 4)
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
        .orbitaControlSurface(cornerRadius: 10)
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
        .orbitaControlSurface(cornerRadius: 10)
    }
}

private struct HeaderRefreshButton: View {
    let title: String
    let isScanning: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                RefreshButtonIcon(isSpinning: isScanning)
                Text(isScanning ? "Refreshing..." : title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .frame(height: 30)
        }
        .buttonStyle(.plain)
        .orbitaControlSurface(cornerRadius: 10)
        .help("Refresh")
    }
}

private struct RefreshButtonIcon: View {
    let isSpinning: Bool

    var body: some View {
        TimelineView(.animation) { context in
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 14, weight: .semibold))
                .rotationEffect(.degrees(rotationDegrees(at: context.date)))
                .frame(width: 16, height: 16)
        }
    }

    private func rotationDegrees(at date: Date) -> Double {
        guard isSpinning else { return 0 }
        return date.timeIntervalSinceReferenceDate
            .truncatingRemainder(dividingBy: 1)
            * 360
    }
}

struct CapabilityFilterBar: View {
    let agentOptions: [AgentSelection]
    let categoryOptions: [CapabilityCategory]
    @Binding var selectedAgent: AgentSelection?
    @Binding var selectedGroup: CapabilityCategory
    let onAddAgent: () -> Void
    let onMoveAgent: (_ sourceID: String, _ targetID: String) -> Void
    let onPinAgent: (_ agentID: String) -> Void
    let onDeleteAgent: (_ agentID: String) -> Void
    let onMoveCategory: (_ sourceID: String, _ targetID: String) -> Void
    let onPinCategory: (_ categoryID: String) -> Void
    let onHideCategory: (_ categoryID: String) -> Void
    let onHideCategories: () -> Void
    @State private var draggedAgentID: String?
    @State private var draggedCategoryID: String?
    @State private var agentDropTargetID: String?
    @State private var categoryDropTargetID: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                FilterIconButton(systemImage: "plus", help: "Add coding agent", action: onAddAgent)

                FilterChip(title: "Overview", systemImage: "square.grid.2x2", isSelected: selectedAgent == nil) {
                    withAnimation(.snappy(duration: 0.18)) {
                        selectedAgent = nil
                    }
                }
                ForEach(agentOptions) { agent in
                    ReorderableFilterChip(
                        id: agent.id,
                        title: agent.displayName,
                        systemImage: agent.systemImage,
                        isSelected: selectedAgent == agent,
                        draggedID: $draggedAgentID,
                        activeDropTargetID: $agentDropTargetID,
                        onMove: onMoveAgent
                    ) {
                        withAnimation(.snappy(duration: 0.18)) {
                            selectedAgent = agent
                        }
                    }
                    .contextMenu {
                        Button {
                            withAnimation(.snappy(duration: 0.18)) {
                                onPinAgent(agent.id)
                            }
                        } label: {
                            Label("Pin to Top", systemImage: "pin")
                        }

                        Divider()

                        Button(role: .destructive) {
                            withAnimation(.snappy(duration: 0.18)) {
                                onDeleteAgent(agent.id)
                            }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        .disabled(agent.isDeleteProtected)
                    }
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    FilterIconButton(systemImage: "eye.slash", help: "Hide categories", action: onHideCategories)

                    ForEach(categoryOptions) { category in
                        ReorderableFilterChip(
                            id: category.rawValue,
                            title: category.title,
                            isSelected: selectedGroup == category,
                            draggedID: $draggedCategoryID,
                            activeDropTargetID: $categoryDropTargetID,
                            onMove: onMoveCategory
                        ) {
                            withAnimation(.snappy(duration: 0.18)) {
                                selectedGroup = category
                            }
                        }
                        .contextMenu {
                            Button {
                                withAnimation(.snappy(duration: 0.18)) {
                                    onPinCategory(category.rawValue)
                                }
                            } label: {
                                Label("Pin to Top", systemImage: "pin")
                            }

                            Divider()

                            Button {
                                withAnimation(.snappy(duration: 0.18)) {
                                    onHideCategory(category.rawValue)
                                }
                            } label: {
                                Label("Hide", systemImage: "eye.slash")
                            }
                            .disabled(category == .all)
                        }
                    }
                }
            }
        }
    }
}

private struct ReorderableFilterChip: View {
    let id: String
    let title: String
    var systemImage: String?
    let isSelected: Bool
    @Binding var draggedID: String?
    @Binding var activeDropTargetID: String?
    let onMove: (_ sourceID: String, _ targetID: String) -> Void
    let action: () -> Void

    var body: some View {
        FilterChip(title: title, systemImage: systemImage, isSelected: isSelected, action: action)
            .onDrag {
                draggedID = id
                activeDropTargetID = nil
                return NSItemProvider(object: id as NSString)
            }
            .onDrop(
                of: [UTType.text],
                delegate: FilterChipDropDelegate(
                    targetID: id,
                    draggedID: $draggedID,
                    activeDropTargetID: $activeDropTargetID,
                    onMove: onMove
                )
            )
            .help("Drag to reorder")
    }
}

private struct FilterChipDropDelegate: DropDelegate {
    let targetID: String
    @Binding var draggedID: String?
    @Binding var activeDropTargetID: String?
    let onMove: (_ sourceID: String, _ targetID: String) -> Void

    func dropEntered(info: DropInfo) {
        guard let sourceID = draggedID,
              sourceID != targetID,
              activeDropTargetID != targetID else {
            return
        }
        activeDropTargetID = targetID
        withAnimation(.snappy(duration: 0.18)) {
            onMove(sourceID, targetID)
        }
    }

    func dropExited(info: DropInfo) {
        if activeDropTargetID == targetID {
            activeDropTargetID = nil
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedID = nil
        activeDropTargetID = nil
        return true
    }
}

private struct FilterIconButton: View {
    let systemImage: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .orbitaControlSurface(cornerRadius: 10)
        .help(help)
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
            .foregroundStyle(isSelected ? OrbitaTheme.prominentControlForeground : .primary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isSelected ? OrbitaTheme.prominentControlFill : OrbitaTheme.controlFill)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(isSelected ? Color.clear : OrbitaTheme.border)
        }
        .scaleEffect(isSelected ? 1.02 : 1)
        .animation(.snappy(duration: 0.16), value: isSelected)
    }
}

private struct SourceOverviewStrip: View {
    let capabilities: [Capability]
    let overview: AgentCapabilityOverview

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(sourceSummaries, id: \.kind) { summary in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: summary.kind.systemImage)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 18, height: 22)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(summary.kind.title)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                            Text(primaryDetail(for: summary))
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            Text(secondaryDetail(for: summary))
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .frame(width: 258, alignment: .topLeading)
                    .frame(height: 72, alignment: .topLeading)
                    .orbitaControlSurface(cornerRadius: 10)
                }
            }
        }
    }

    private var sourceSummaries: [SourceSummary] {
        let grouped = Dictionary(grouping: capabilities, by: CapabilitySourceClassifier.sourceKind(for:))
        let agentSummaries = Dictionary(uniqueKeysWithValues: overview.agentSummaries.map { ($0.agent, $0) })
        return CapabilitySourceClassifier.SourceKind.headerKinds
            .map { kind in
                let sourceCapabilities = grouped[kind] ?? []
                return SourceSummary(
                    kind: kind,
                    count: sourceCapabilities.count,
                    enabledCount: sourceCapabilities.filter { $0.statuses.contains(.enabled) }.count,
                    disabledCount: sourceCapabilities.filter { $0.statuses.contains(.disabled) }.count,
                    driftedCount: sourceCapabilities.filter { $0.statuses.contains(.drifted) }.count,
                    agentSummary: agentSummary(for: kind, in: agentSummaries)
                )
            }
    }

    private func primaryDetail(for summary: SourceSummary) -> String {
        guard let agentSummary = summary.agentSummary else {
            return "\(summary.count) indexed · \(summary.enabledCount) enabled"
        }
        return "\(agentSummary.visibleCount) visible · \(agentSummary.hiddenCount) hidden"
    }

    private func secondaryDetail(for summary: SourceSummary) -> String {
        if let agentSummary = summary.agentSummary {
            let drift = agentSummary.driftedCount == 0 ? "no drift" : "\(agentSummary.driftedCount) drift"
            let risk = agentSummary.riskyCount == 0 ? "ready" : "\(agentSummary.riskyCount) review"
            return "\(risk) · \(drift) · native \(summary.kind.title) loading"
        }
        let disabled = summary.disabledCount == 0 ? "no disabled entries" : "\(summary.disabledCount) disabled"
        let drift = summary.driftedCount == 0 ? "sync ready" : "\(summary.driftedCount) drift"
        return "\(disabled) · \(drift) · shared across agents"
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
        let enabledCount: Int
        let disabledCount: Int
        let driftedCount: Int
        let agentSummary: AgentCapabilitySummary?
    }
}

private struct EmptyCapabilitiesState: View {
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "tray")
                .font(.system(size: 38, weight: .regular))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
            Text("No capabilities")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
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
