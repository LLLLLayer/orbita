import AppKit
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
    let graphForAgentVisibility: CapabilityGraph?
    let graphRevision: Int
    @Binding var hideMacScope: Bool
    let showHideMacScopeToggle: Bool
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
    let onSyncCapability: (Capability) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if graph != nil {
                GeometryReader { proxy in
                    let contentPadding = horizontalContentPadding(for: proxy.size.width)
                    let contentWidth = max(1, proxy.size.width - contentPadding * 2)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            HeaderSurface(
                                projectName: projectName,
                                capabilities: headerCapabilities,
                                isScanning: isScanning,
                                lastRefreshLabel: lastRefreshLabel,
                                hideMacScope: $hideMacScope,
                                showHideMacScopeToggle: showHideMacScopeToggle,
                                onRefresh: onRefresh
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
                                    graph: graphForAgentVisibility,
                                    graphRevision: graphRevision,
                                    agentOptions: agentOptions,
                                    selectedAgent: selectedAgent,
                                    selectedCapability: $selectedCapability,
                                    expandedGroupIDs: $expandedGroupIDs,
                                    availableWidth: contentWidth,
                                    onSyncCapability: onSyncCapability
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

    private var headerCapabilities: [Capability] {
        guard let graph else { return [] }
        guard let selectedAgent else { return graph.capabilities }
        return selectedAgent.visibleCapabilities(in: graph)
    }
}

private struct HeaderSurface: View {
    let projectName: String
    let capabilities: [Capability]
    let isScanning: Bool
    let lastRefreshLabel: String
    @Binding var hideMacScope: Bool
    let showHideMacScopeToggle: Bool
    let onRefresh: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(projectName)
                        .font(.title2.weight(.semibold))
                        .lineLimit(1)
                }

                Spacer(minLength: 16)

                if showHideMacScopeToggle {
                    HeaderMacScopeToggle(isHiding: $hideMacScope)
                }

                HeaderRefreshButton(title: lastRefreshLabel, isScanning: isScanning, action: onRefresh)
            }

            HStack(spacing: 0) {
                SummaryStat(title: "Total", value: capabilities.count, systemImage: "square.grid.2x2")
                SummaryStat(title: "Plugins", value: count(.plugin), systemImage: "shippingbox")
                SummaryStat(title: "Skills", value: count(.skill), systemImage: "wand.and.stars")
                SummaryStat(title: "Agents", value: count(.agent), systemImage: "person.2")
                SummaryStat(title: "Commands", value: count(.command), systemImage: "terminal")
                SummaryStat(title: "MCP", value: count(.mcp), systemImage: "server.rack")
                SummaryStat(title: "Hooks", value: count(.hook), systemImage: "link")
            }
            .frame(maxWidth: .infinity, alignment: .leading)

        }
        .padding(18)
        .orbitaCard(cornerRadius: 22, shadowRadius: 12, shadowY: 7)
    }

    private func count(_ category: CapabilityCategory) -> Int {
        capabilities.filter { category.matches($0) }.count
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
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

private struct HeaderMacScopeToggle: View {
    @Binding var isHiding: Bool

    var body: some View {
        Button {
            isHiding.toggle()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "laptopcomputer")
                    .font(.system(size: 13, weight: .semibold))
                Text(isHiding ? "Show This Mac" : "Hide This Mac")
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
            }
            .foregroundStyle(isHiding ? OrbitaTheme.prominentControlForeground : Color.primary)
            .padding(.horizontal, 10)
            .frame(height: 30)
        }
        .buttonStyle(.plain)
        .orbitaControlSurface(selected: isHiding, cornerRadius: 10)
        .help(isHiding ? "Show capabilities that come from This Mac" : "Hide capabilities that come from This Mac")
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
                        agentIcon: agent,
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
    var agentIcon: AgentSelection?
    let isSelected: Bool
    @Binding var draggedID: String?
    @Binding var activeDropTargetID: String?
    let onMove: (_ sourceID: String, _ targetID: String) -> Void
    let action: () -> Void

    var body: some View {
        FilterChip(title: title, systemImage: systemImage, agentIcon: agentIcon, isSelected: isSelected, action: action)
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
    var agentIcon: AgentSelection?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let agentIcon {
                    AgentBrandIcon(agent: agentIcon, size: 15, isSelected: isSelected)
                        .frame(width: 15)
                } else if let systemImage {
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
            .foregroundStyle(isSelected ? OrbitaTheme.prominentControlForeground : Color.primary)
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

private struct EmptyCapabilitiesState: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 12) {
            if let image = EmptyStateIllustrationStore.image(named: imageName) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: 190, height: 190)
                    .accessibilityHidden(true)
            } else {
                Image(systemName: "tray")
                    .font(.system(size: 38, weight: .regular))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
            }
            Text("No capabilities")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private var imageName: String {
        colorScheme == .dark ? "empty-placeholder-dark" : "empty-placeholder-light"
    }
}

@MainActor
private enum EmptyStateIllustrationStore {
    private static var cache: [String: NSImage] = [:]

    static func image(named name: String) -> NSImage? {
        if let cached = cache[name] {
            return cached
        }
        guard let url = resourceURL(for: name),
              let image = NSImage(contentsOf: url)?.copy() as? NSImage else {
            return nil
        }
        cache[name] = image
        return image
    }

    private static func resourceURL(for name: String) -> URL? {
        #if SWIFT_PACKAGE
        if let url = Bundle.module.url(
            forResource: name,
            withExtension: "png",
            subdirectory: "EmptyStates"
        ) {
            return url
        }
        if let url = Bundle.module.url(forResource: name, withExtension: "png") {
            return url
        }
        #endif

        if let url = Bundle.main.url(forResource: name, withExtension: "png", subdirectory: "EmptyStates") {
            return url
        }
        if let url = Bundle.main.url(forResource: name, withExtension: "png", subdirectory: "Resources/EmptyStates") {
            return url
        }
        return Bundle.main.url(forResource: name, withExtension: "png")
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
