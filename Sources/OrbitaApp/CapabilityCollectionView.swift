import SwiftUI
import OrbitaCore

private typealias AgentVisibilityIndex = [String: Set<String>]

struct CapabilityCollectionView: View {
    let sections: [CapabilityCollectionSection]
    let graph: CapabilityGraph?
    let agentOptions: [AgentSelection]
    @Binding var selectedCapability: Capability?
    @Binding var expandedGroupIDs: Set<String>
    let availableWidth: CGFloat
    let onSyncCapability: (Capability) -> Void

    @State private var expandedGroupOrder: [String] = []
    @State private var collapsedSectionIDs: Set<String> = []

    private let itemMinWidth: CGFloat = 118
    private let itemTargetWidth: CGFloat = 142
    private let itemSpacing: CGFloat = 18

    var body: some View {
        let agentVisibilityIndex = makeAgentVisibilityIndex()
        VStack(alignment: .leading, spacing: 24) {
            ForEach(sectionRows) { section in
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .center, spacing: 8) {
                        Text(section.title)
                            .font(.headline)
                        Text(section.subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                        sectionCollapseButton(for: section)
                    }

                    if !collapsedSectionIDs.contains(section.id) {
                        sectionContent(section, agentVisibilityIndex: agentVisibilityIndex)
                            .clipped()
                            .transition(.opacity)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onChange(of: expandedGroupIDs) { _, ids in
            expandedGroupOrder.removeAll { !ids.contains($0) }
        }
        .onChange(of: sections.map(\.id)) { _, ids in
            collapsedSectionIDs = collapsedSectionIDs.filter { ids.contains($0) }
        }
        .animation(.interactiveSpring(response: 0.32, dampingFraction: 0.86, blendDuration: 0.08), value: contentSignature)
    }

    private func sectionContent(
        _ section: CapabilityDisplaySectionRows,
        agentVisibilityIndex: AgentVisibilityIndex
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(section.subsections) { subsection in
                VStack(alignment: .leading, spacing: 10) {
                    if let title = subsection.title {
                        HStack(spacing: 6) {
                            Text(title)
                                .font(.subheadline.weight(.semibold))
                            if let subtitle = subsection.subtitle {
                                Text(subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    ForEach(subsection.rows) { row in
                        LazyVGrid(columns: columns, alignment: .leading, spacing: 20) {
                            ForEach(row.items) { item in
                                tile(for: item, agentVisibilityIndex: agentVisibilityIndex)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        ForEach(expandedGroups(for: row)) { group in
                            ExpandedCapabilityGroupShelf(
                                group: group,
                                agentOptions: agentOptions,
                                agentVisibilityIndex: agentVisibilityIndex,
                                selectedCapability: $selectedCapability,
                                columns: columns,
                                onSyncCapability: onSyncCapability
                            )
                        }
                    }
                }
            }
        }
    }

    private func sectionCollapseButton(for section: CapabilityDisplaySectionRows) -> some View {
        let isCollapsed = collapsedSectionIDs.contains(section.id)
        return Button {
            withAnimation(.snappy(duration: 0.18)) {
                if isCollapsed {
                    collapsedSectionIDs.remove(section.id)
                } else {
                    collapsedSectionIDs.insert(section.id)
                }
            }
        } label: {
            Image(systemName: isCollapsed ? "chevron.down" : "chevron.up")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
                .background(OrbitaTheme.controlFill, in: Circle())
                .overlay {
                    Circle().strokeBorder(OrbitaTheme.border)
                }
        }
        .buttonStyle(.plain)
        .contentShape(Circle())
        .help(isCollapsed ? "Expand \(section.title)" : "Collapse \(section.title)")
        .accessibilityLabel(isCollapsed ? "Expand \(section.title)" : "Collapse \(section.title)")
    }

    @ViewBuilder
    private func tile(for item: CapabilityDisplayItem, agentVisibilityIndex: AgentVisibilityIndex) -> some View {
        switch item {
        case let .capability(capability):
            CapabilityTile(
                capability: capability,
                visibleAgents: visibleAgents(for: item, in: agentVisibilityIndex),
                isSelected: selectedCapability?.id == capability.id,
                onSync: {
                    onSyncCapability(capability)
                }
            ) {
                selectedCapability = capability
            }
        case let .group(group):
            let inspectionCapability = group.inspectionCapability
            CapabilityGroupTile(
                group: group,
                visibleAgents: visibleAgents(for: item, in: agentVisibilityIndex),
                isExpanded: expandedGroupIDs.contains(group.id),
                isSelected: selectedCapability?.id == inspectionCapability.id,
                onSync: {
                    onSyncCapability(inspectionCapability)
                }
            ) {
                withAnimation(.interactiveSpring(response: 0.28, dampingFraction: 0.88, blendDuration: 0.08)) {
                    selectedCapability = inspectionCapability
                    toggleExpandedGroup(group.id)
                }
            }
        }
    }

    private func expandedGroups(for row: CapabilityDisplayRow) -> [CapabilityGroup] {
        row.expandedGroups
            .filter { expandedGroupIDs.contains($0.id) }
            .sorted { expansionRank(for: $0.id) < expansionRank(for: $1.id) }
    }

    private func expansionRank(for groupID: String) -> Int {
        expandedGroupOrder.firstIndex(of: groupID) ?? Int.max
    }

    private func toggleExpandedGroup(_ groupID: String) {
        expandedGroupOrder.removeAll { $0 == groupID }
        if expandedGroupIDs.contains(groupID) {
            expandedGroupIDs.remove(groupID)
        } else {
            expandedGroupIDs.insert(groupID)
            expandedGroupOrder.insert(groupID, at: 0)
        }
    }

    private func visibleAgents(for item: CapabilityDisplayItem, in agentVisibilityIndex: AgentVisibilityIndex) -> [AgentSelection] {
        let capabilityIDs = Set(item.capabilities.map(\.id))
        return agentOptions.filter { agent in
            guard let visibleIDs = agentVisibilityIndex[agent.id] else {
                return false
            }
            return !capabilityIDs.isDisjoint(with: visibleIDs)
        }
    }

    private func makeAgentVisibilityIndex() -> AgentVisibilityIndex {
        guard let graph else { return [:] }
        return Dictionary(uniqueKeysWithValues: agentOptions.map { agent in
            (agent.id, agent.visibleCapabilityIDs(in: graph))
        })
    }

    private var columns: [GridItem] {
        Array(
            repeating: GridItem(.flexible(minimum: itemMinWidth), spacing: itemSpacing, alignment: .top),
            count: columnCount
        )
    }

    private var columnCount: Int {
        let count = Int((availableWidth + itemSpacing) / (itemTargetWidth + itemSpacing))
        return max(1, count)
    }

    private var sectionRows: [CapabilityDisplaySectionRows] {
        sections.map { section in
            CapabilityDisplaySectionRows(
                id: section.id,
                title: section.title,
                subtitle: section.subtitle,
                subsections: section.subsections.map { subsection in
                    CapabilityDisplaySubsectionRows(
                        id: subsection.id,
                        title: subsection.title,
                        subtitle: subsection.subtitle,
                        rows: displayRows(for: subsection.items)
                    )
                }
            )
        }
    }

    private func displayRows(for items: [CapabilityDisplayItem]) -> [CapabilityDisplayRow] {
        var rows: [CapabilityDisplayRow] = []
        var start = 0
        var index = 0
        while start < items.count {
            let end = min(items.count, start + columnCount)
            let rowItems = Array(items[start..<end])
            rows.append(CapabilityDisplayRow(index: index, items: rowItems))
            start = end
            index += 1
        }
        return rows
    }

    private var contentSignature: String {
        sections
            .map { section in
                let subsectionSignature = section.subsections
                    .map { subsection in
                        "\(subsection.id):\(subsection.items.count)"
                    }
                    .joined(separator: ",")
                return "\(section.id):\(subsectionSignature)"
            }
            .joined(separator: "|")
    }
}

struct CapabilityCollectionSection: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let subsections: [CapabilityCollectionSubsection]

    init(id: String, title: String, subtitle: String, items: [CapabilityDisplayItem]) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.subsections = [
            CapabilityCollectionSubsection(
                id: "\(id)-all",
                title: nil,
                subtitle: nil,
                items: items
            )
        ]
    }

    init(id: String, title: String, subtitle: String, subsections: [CapabilityCollectionSubsection]) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.subsections = subsections
    }
}

struct CapabilityCollectionSubsection: Identifiable, Hashable {
    let id: String
    let title: String?
    let subtitle: String?
    let items: [CapabilityDisplayItem]
}

private struct CapabilityDisplaySectionRows: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let subsections: [CapabilityDisplaySubsectionRows]
}

private struct CapabilityDisplaySubsectionRows: Identifiable {
    let id: String
    let title: String?
    let subtitle: String?
    let rows: [CapabilityDisplayRow]
}

private struct CapabilityDisplayRow: Identifiable {
    let index: Int
    let items: [CapabilityDisplayItem]

    var id: String {
        "row-\(index)"
    }

    var expandedGroups: [CapabilityGroup] {
        items.compactMap { item in
            guard case let .group(group) = item else {
                return nil
            }
            return group
        }
    }
}

private struct ExpandedCapabilityGroupShelf: View {
    let group: CapabilityGroup
    let agentOptions: [AgentSelection]
    let agentVisibilityIndex: AgentVisibilityIndex
    @Binding var selectedCapability: Capability?
    let columns: [GridItem]
    let onSyncCapability: (Capability) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(shelfSections) { section in
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 6) {
                        Text(section.title)
                            .font(.subheadline.weight(.semibold))
                        Text("\(section.itemCount) items")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    LazyVGrid(columns: columns, alignment: .leading, spacing: 20) {
                        ForEach(section.items) { item in
                            shelfTile(for: item)
                        }
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(OrbitaTheme.elevatedSurface)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(OrbitaTheme.border)
        }
        .shadow(color: OrbitaTheme.cardShadow, radius: 8, x: 0, y: 4)
        .padding(.top, 2)
        .transition(.asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 0.985, anchor: .top)),
            removal: .opacity.combined(with: .scale(scale: 0.995, anchor: .top))
        ))
    }

    @ViewBuilder
    private func shelfTile(for item: CapabilityDisplayItem) -> some View {
        switch item {
        case let .capability(capability):
            CapabilityTile(
                capability: capability,
                visibleAgents: visibleAgents(for: item),
                isSelected: selectedCapability?.id == capability.id,
                onSync: {
                    onSyncCapability(capability)
                }
            ) {
                selectedCapability = capability
            }
        case let .group(group):
            let inspectionCapability = group.inspectionCapability
            CapabilityGroupTile(
                group: group,
                visibleAgents: visibleAgents(for: item),
                isExpanded: false,
                isSelected: selectedCapability?.id == inspectionCapability.id,
                showsDisclosure: false,
                onSync: {
                    onSyncCapability(inspectionCapability)
                }
            ) {
                selectedCapability = inspectionCapability
            }
        }
    }

    private func visibleAgents(for item: CapabilityDisplayItem) -> [AgentSelection] {
        let capabilityIDs = Set(item.capabilities.map(\.id))
        return agentOptions.filter { agent in
            guard let visibleIDs = agentVisibilityIndex[agent.id] else {
                return false
            }
            return !capabilityIDs.isDisjoint(with: visibleIDs)
        }
    }

    private var shelfSections: [ExpandedGroupSection] {
        if group.kind == .mirror {
            return [
                ExpandedGroupSection(
                    id: "all",
                    title: group.kindLabel,
                    items: group.capabilities.map(CapabilityDisplayItem.capability)
                )
            ]
        }

        let displayItems = CapabilityDisplayGrouper().items(
            for: group.capabilities,
            minimumGroupSize: Int.max,
            groupsPluginChildren: false
        )
        let grouped = Dictionary(grouping: displayItems) { item in
            CapabilityTypeSection(type: item.inspectionCapability.type)
        }
        return CapabilityTypeSection.displayOrder.compactMap { section in
            guard let items = grouped[section], !items.isEmpty else {
                return nil
            }
            return ExpandedGroupSection(
                id: section.id,
                title: section.title,
                items: items.sorted { lhs, rhs in
                    lhs.inspectionCapability.name.localizedCaseInsensitiveCompare(rhs.inspectionCapability.name) == .orderedAscending
                }
            )
        }
    }
}

private struct ExpandedGroupSection: Identifiable {
    let id: String
    let title: String
    let items: [CapabilityDisplayItem]

    var itemCount: Int {
        items.reduce(0) { total, item in
            total + item.capabilities.count
        }
    }
}

private enum CapabilityTypeSection: String, CaseIterable, Hashable {
    case plugins
    case skills
    case agents
    case commands
    case mcp
    case hooks
    case instructions
    case other

    init(type: CapabilityType) {
        switch type {
        case .plugin:
            self = .plugins
        case .skill:
            self = .skills
        case .agent:
            self = .agents
        case .command:
            self = .commands
        case .mcpServer:
            self = .mcp
        case .hook:
            self = .hooks
        case .instruction, .rule:
            self = .instructions
        case .unknown:
            self = .other
        }
    }

    static let displayOrder: [CapabilityTypeSection] = [
        .plugins,
        .skills,
        .agents,
        .commands,
        .mcp,
        .hooks,
        .instructions,
        .other
    ]

    var id: String { rawValue }

    var title: String {
        switch self {
        case .plugins:
            return "Plugins"
        case .skills:
            return "Skills"
        case .agents:
            return "Agents"
        case .commands:
            return "Commands"
        case .mcp:
            return "MCP"
        case .hooks:
            return "Hooks"
        case .instructions:
            return "Instructions"
        case .other:
            return "Other"
        }
    }
}

private struct CapabilityGroupTile: View {
    let group: CapabilityGroup
    let visibleAgents: [AgentSelection]
    let isExpanded: Bool
    let isSelected: Bool
    var showsDisclosure = true
    let onSync: () -> Void
    let action: () -> Void

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 8) {
                    CapabilityKindPill(
                        title: group.kindLabel,
                        systemImage: group.systemImage,
                        isSelected: isSelected
                    )
                    Spacer(minLength: 6)
                    GroupTopBadge(
                        text: groupTopBadgeText,
                        isExpanded: isExpanded,
                        showsDisclosure: showsDisclosure
                    )
                }
                .frame(height: CapabilityTileMetrics.headerHeight, alignment: .top)

                CapabilityTileTextBlock(title: group.tileTitle, subtitle: groupSubtitle)

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            if group.capabilities.contains(where: { $0.type.supportsAgentSync }) {
                AgentSyncStack(agents: visibleAgents, onSync: onSync)
            }
        }
        .padding(12)
        .frame(
            maxWidth: .infinity,
            minHeight: CapabilityTileMetrics.height,
            maxHeight: CapabilityTileMetrics.height,
            alignment: .top
        )
        .contentShape(Rectangle())
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(isSelected ? OrbitaTheme.elevatedSurface : OrbitaTheme.surface)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(tileBorderColor, style: group.outlineStyle(lineWidth: isSelected ? 1.5 : 1))
        }
        .shadow(color: isSelected ? OrbitaTheme.selectedShadow : Color.clear, radius: 10, x: 0, y: 5)
        .onTapGesture(perform: action)
        .accessibilityAddTraits(.isButton)
    }

    private var tileBorderColor: Color {
        if isSelected {
            return OrbitaTheme.strongBorder
        }
        return group.isVirtualPlugin ? OrbitaTheme.strongBorder : OrbitaTheme.border
    }

    private var groupSubtitle: String {
        switch group.kind {
        case .mirror:
            if let subtitle = group.hookTimingSummary {
                return hookTimingDescription(for: subtitle)
            }
            return group.mirrorRelationshipLabel
        case .plugin:
            return CapabilityType.plugin.protocolDescription
        case .prefix:
            return "前缀为 \(group.name)-* 聚合的内容"
        }
    }

    private var groupTopBadgeText: String {
        "\(group.capabilities.count)"
    }
}

private extension CapabilityGroup {
    var tileTitle: String {
        if let title = hookHostSummary {
            return title
        }
        return name
    }

    var hookHostSummary: String? {
        guard capabilities.allSatisfy({ $0.type == .hook }) else {
            return nil
        }
        let hosts = uniquePreservingOrder(capabilities.map(\.hookHostTitle))
        guard let first = hosts.first else {
            return nil
        }
        return hosts.count == 1 ? first : "\(first) + \(hosts.count - 1)"
    }

    var hookTimingSummary: String? {
        guard capabilities.allSatisfy({ $0.type == .hook }) else {
            return nil
        }
        let timings = uniquePreservingOrder(capabilities.map(\.hookTimingLabel))
        guard let first = timings.first else {
            return nil
        }
        if timings.count == 1 {
            return first
        }
        if timings.count == 2 {
            return timings.joined(separator: ", ")
        }
        return "\(first), \(timings[1]) + \(timings.count - 2)"
    }

    var systemImage: String {
        switch kind {
        case .plugin:
            return CapabilityVisuals.iconName(for: .plugin)
        case .mirror:
            return "square.stack.3d.up"
        case .prefix:
            return "square.stack.3d.up.fill"
        }
    }

    var kindLabel: String {
        switch kind {
        case .plugin:
            return "Plugin"
        case .mirror:
            return inspectionCapability.type.displayName
        case .prefix:
            return "Group"
        }
    }

    var mirrorRelationshipLabel: String {
        let relationships = Set(capabilities.compactMap { $0.metadata["duplicateRelationship"] })
        if relationships.contains("linked-mirror") {
            return "Linked mirrors"
        }
        if relationships.contains("copied-mirror") {
            return "Same hash copies"
        }
        return "Same source"
    }

    var isVirtualPlugin: Bool {
        switch kind {
        case .prefix:
            return true
        case .plugin, .mirror:
            return false
        }
    }

    func outlineStyle(lineWidth: CGFloat) -> StrokeStyle {
        StrokeStyle(lineWidth: lineWidth, dash: isVirtualPlugin ? [5, 4] : [])
    }
}

private struct CapabilityTile: View {
    let capability: Capability
    let visibleAgents: [AgentSelection]
    let isSelected: Bool
    let onSync: () -> Void
    let action: () -> Void

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 8) {
                    CapabilityKindPill(
                        title: capability.type.displayName,
                        systemImage: CapabilityVisuals.iconName(for: capability.type),
                        isSelected: isSelected
                    )
                    Spacer(minLength: 6)
                }
                .frame(height: CapabilityTileMetrics.headerHeight, alignment: .top)

                CapabilityTileTextBlock(title: capability.tileTitle, subtitle: sourceLabel)

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            if capability.type.supportsAgentSync {
                AgentSyncStack(agents: visibleAgents, onSync: onSync)
            }
        }
        .padding(12)
        .frame(
            maxWidth: .infinity,
            minHeight: CapabilityTileMetrics.height,
            maxHeight: CapabilityTileMetrics.height,
            alignment: .top
        )
        .contentShape(Rectangle())
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(isSelected ? OrbitaTheme.elevatedSurface : OrbitaTheme.surface)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(tileBorderColor, style: tileOutlineStyle)
        }
        .shadow(color: isSelected ? OrbitaTheme.selectedShadow : Color.clear, radius: 10, x: 0, y: 5)
        .onTapGesture(perform: action)
        .accessibilityAddTraits(.isButton)
        .animation(.snappy(duration: 0.18), value: isSelected)
    }

    private var tileBorderColor: Color {
        if isSelected {
            return OrbitaTheme.strongBorder
        }
        return capability.isVirtualPlugin ? OrbitaTheme.strongBorder : OrbitaTheme.border
    }

    private var tileOutlineStyle: StrokeStyle {
        StrokeStyle(lineWidth: isSelected ? 1.5 : 1, dash: capability.isVirtualPlugin ? [5, 4] : [])
    }

    private var sourceLabel: String {
        capability.tileSubtitle
    }
}

private enum CapabilityTileMetrics {
    static let height: CGFloat = 152
    static let headerHeight: CGFloat = 30
    static let textHeight: CGFloat = 52
}

private struct CapabilityTileTextBlock: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .lineLimit(2)
                .truncationMode(.middle)
                .fixedSize(horizontal: false, vertical: true)

            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(
            maxWidth: .infinity,
            minHeight: CapabilityTileMetrics.textHeight,
            maxHeight: CapabilityTileMetrics.textHeight,
            alignment: .topLeading
        )
    }
}

private extension Capability {
    var isVirtualPlugin: Bool {
        type == .plugin && source.kind == "virtual-plugin"
    }

    var tileTitle: String {
        type == .hook ? hookHostTitle : name
    }

    var tileSubtitle: String {
        if type == .hook {
            return hookTimingDescription(for: hookTimingLabel)
        }
        if let summary, !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return summary
        }
        return type.protocolDescription
    }

    var hookHostTitle: String {
        if let host = metadata["handlerHost"], !host.isEmpty {
            return normalizedHookHostTitle(host)
        }
        guard let separator = name.range(of: " - ") else {
            return normalizedHookHostTitle(name)
        }
        return normalizedHookHostTitle(String(name[..<separator.lowerBound]))
    }

    var hookTimingLabel: String {
        let rawEvent = metadata["event"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let event = rawEvent.isEmpty ? parsedHookTimingFromName : rawEvent
        let matcher = metadata["matcher"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !event.isEmpty else {
            return "Hook timing"
        }
        guard !matcher.isEmpty else {
            return event
        }
        return "\(event) (\(matcher))"
    }

    private var parsedHookTimingFromName: String {
        guard let separator = name.range(of: " - ") else {
            return ""
        }
        return String(name[separator.upperBound...])
    }

    private func normalizedHookHostTitle(_ value: String) -> String {
        if value == "AB Agent Collect Event" {
            return "AB Agent Collect"
        }
        return value
    }
}

private extension CapabilityType {
    var protocolDescription: String {
        switch self {
        case .skill:
            return "Skill capability"
        case .agent:
            return "Subagent"
        case .plugin:
            return "Plugin package"
        case .mcpServer:
            return "MCP server"
        case .hook:
            return "Hook timing"
        case .command:
            return "Command"
        case .instruction, .rule:
            return "Instruction"
        case .unknown:
            return "Capability"
        }
    }
}

private func hookTimingDescription(for timing: String) -> String {
    let trimmed = timing.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, trimmed != "Hook timing" else {
        return "Hook timing"
    }
    return "Hook \(trimmed) 时机"
}

private func uniquePreservingOrder(_ values: [String]) -> [String] {
    var seen = Set<String>()
    var result: [String] = []
    for value in values {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, seen.insert(trimmed).inserted else {
            continue
        }
        result.append(trimmed)
    }
    return result
}

private struct CapabilityKindPill: View {
    let title: String
    let systemImage: String
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
            Text(title)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
        }
        .foregroundStyle(isSelected ? .primary : .secondary)
        .padding(.horizontal, 8)
        .frame(height: 28)
        .background(isSelected ? OrbitaTheme.controlHoverFill : OrbitaTheme.controlFill, in: Capsule())
        .overlay {
            Capsule().strokeBorder(isSelected ? OrbitaTheme.strongBorder : OrbitaTheme.border)
        }
    }
}

private struct GroupTopBadge: View {
    let text: String
    let isExpanded: Bool
    var showsDisclosure = true

    var body: some View {
        HStack(spacing: 5) {
            Text(text)
                .font(.caption.weight(.semibold))
                .monospacedDigit()
            if showsDisclosure {
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.caption2.weight(.bold))
            }
        }
        .foregroundStyle(.secondary)
        .frame(minWidth: 34)
        .frame(height: 28)
        .padding(.horizontal, 8)
        .background(OrbitaTheme.controlFill, in: Capsule())
        .overlay {
            Capsule().strokeBorder(OrbitaTheme.border)
        }
        .accessibilityLabel("\(text) items")
    }
}

private enum AgentAvatarMetrics {
    static let size: CGFloat = 30
    static let overlapStep: CGFloat = 21
}

private struct AgentSyncStack: View {
    let agents: [AgentSelection]
    let onSync: () -> Void

    private var visibleAgents: [AgentSelection] {
        Array(agents.prefix(4))
    }

    private var badgeCount: Int {
        visibleAgents.count + overflowBadgeCount + 1
    }

    private var overflowBadgeCount: Int {
        agents.count > visibleAgents.count ? 1 : 0
    }

    var body: some View {
        ZStack(alignment: .leading) {
            ForEach(Array(visibleAgents.enumerated()), id: \.element.id) { index, agent in
                AgentVisibilityBadge(agent: agent)
                    .offset(x: CGFloat(index) * AgentAvatarMetrics.overlapStep)
                    .zIndex(Double(index))
            }

            if agents.count > visibleAgents.count {
                AgentOverflowBadge(count: agents.count - visibleAgents.count)
                    .offset(x: CGFloat(visibleAgents.count) * AgentAvatarMetrics.overlapStep)
                    .zIndex(Double(visibleAgents.count))
            }

            AgentSyncButton(action: onSync)
                .offset(x: syncButtonOffset)
                .zIndex(Double(badgeCount))
        }
        .frame(width: stackWidth, height: AgentAvatarMetrics.size, alignment: .leading)
        .help(helpText)
    }

    private var syncButtonOffset: CGFloat {
        CGFloat(visibleAgents.count + overflowBadgeCount) * AgentAvatarMetrics.overlapStep
    }

    private var stackWidth: CGFloat {
        guard badgeCount > 0 else { return AgentAvatarMetrics.size }
        return CGFloat(max(0, badgeCount - 1)) * AgentAvatarMetrics.overlapStep + AgentAvatarMetrics.size
    }

    private var helpText: String {
        guard !agents.isEmpty else {
            return "Sync to another agent"
        }
        return "\(agents.map(\.displayName).joined(separator: ", ")). Add another agent"
    }
}

private struct AgentSyncButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.primary)
                .frame(width: AgentAvatarMetrics.size, height: AgentAvatarMetrics.size)
                .background(OrbitaTheme.elevatedSurface, in: Circle())
                .overlay {
                    Circle().strokeBorder(Color.white.opacity(0.92), lineWidth: 2)
                    Circle().strokeBorder(OrbitaTheme.border)
                }
                .shadow(color: OrbitaTheme.cardShadow, radius: 4, x: 0, y: 2)
        }
        .buttonStyle(.plain)
        .help("Sync to another agent")
        .accessibilityLabel("Sync capability to another agent")
    }
}

private struct AgentOverflowBadge: View {
    let count: Int

    var body: some View {
        Text("+\(count)")
            .font(.caption2.weight(.bold))
            .foregroundStyle(.secondary)
            .frame(width: AgentAvatarMetrics.size, height: AgentAvatarMetrics.size)
            .background(OrbitaTheme.elevatedSurface, in: Circle())
            .overlay {
                Circle().strokeBorder(Color.white.opacity(0.92), lineWidth: 2)
                Circle().strokeBorder(OrbitaTheme.border)
            }
            .shadow(color: OrbitaTheme.cardShadow, radius: 4, x: 0, y: 2)
        }
    }

private struct AgentVisibilityBadge: View {
    let agent: AgentSelection

    var body: some View {
        AgentBrandIcon(agent: agent, size: 14)
            .frame(width: AgentAvatarMetrics.size, height: AgentAvatarMetrics.size)
            .background(OrbitaTheme.elevatedSurface, in: Circle())
            .overlay {
                Circle().strokeBorder(Color.white.opacity(0.92), lineWidth: 2)
                Circle().strokeBorder(OrbitaTheme.border)
            }
            .shadow(color: OrbitaTheme.cardShadow, radius: 4, x: 0, y: 2)
    }
}
