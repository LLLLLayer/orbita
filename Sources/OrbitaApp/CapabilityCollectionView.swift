import SwiftUI
import OrbitaCore

struct CapabilityCollectionView: View {
    let sections: [CapabilityCollectionSection]
    @Binding var selectedCapability: Capability?
    @Binding var expandedGroupIDs: Set<String>
    let availableWidth: CGFloat

    @State private var expandedGroupOrder: [String] = []
    @State private var collapsedSectionIDs: Set<String> = []

    private let itemMinWidth: CGFloat = 118
    private let itemTargetWidth: CGFloat = 142
    private let itemSpacing: CGFloat = 18

    var body: some View {
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
                        sectionContent(section)
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

    private func sectionContent(_ section: CapabilityDisplaySectionRows) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(section.rows) { row in
                LazyVGrid(columns: columns, alignment: .leading, spacing: 20) {
                    ForEach(row.items) { item in
                        tile(for: item)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                ForEach(expandedGroups(for: row)) { group in
                    ExpandedCapabilityGroupShelf(
                        group: group,
                        selectedCapability: $selectedCapability,
                        columns: columns
                    )
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
    private func tile(for item: CapabilityDisplayItem) -> some View {
        switch item {
        case let .capability(capability):
            CapabilityTile(
                capability: capability,
                isSelected: selectedCapability?.id == capability.id
            ) {
                withAnimation(.snappy(duration: 0.18)) {
                    selectedCapability = capability
                }
            }
        case let .group(group):
            let inspectionCapability = group.inspectionCapability
            CapabilityGroupTile(
                group: group,
                isExpanded: expandedGroupIDs.contains(group.id),
                isSelected: selectedCapability?.id == inspectionCapability.id
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
                rows: displayRows(for: section.items)
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
                "\(section.id):\(section.items.count)"
            }
            .joined(separator: "|")
    }
}

struct CapabilityCollectionSection: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let items: [CapabilityDisplayItem]
}

private struct CapabilityDisplaySectionRows: Identifiable {
    let id: String
    let title: String
    let subtitle: String
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
    @Binding var selectedCapability: Capability?
    let columns: [GridItem]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 20) {
            ForEach(group.capabilities) { capability in
                CapabilityTile(
                    capability: capability,
                    isSelected: selectedCapability?.id == capability.id
                ) {
                    withAnimation(.snappy(duration: 0.18)) {
                        selectedCapability = capability
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
}

private struct CapabilityGroupTile: View {
    let group: CapabilityGroup
    let isExpanded: Bool
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack(alignment: .topTrailing) {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(OrbitaTheme.controlFill)
                        .frame(width: 56, height: 52)
                        .overlay {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(
                                    group.isVirtualPlugin ? OrbitaTheme.strongBorder : OrbitaTheme.border,
                                    style: group.outlineStyle(lineWidth: 1.2)
                                )
                        }

                    Image(systemName: group.systemImage)
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(.primary)
                        .frame(width: 56, height: 52)

                    Text("\(group.capabilities.count)")
                        .font(.caption2.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(OrbitaTheme.elevatedSurface, in: Capsule())
                        .offset(x: 8, y: -7)
                }
                .frame(width: 66, height: 58)

                VStack(spacing: 3) {
                    Text(group.name)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(groupSubtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, minHeight: 128, alignment: .top)
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
        }
        .buttonStyle(.plain)
    }

    private var tileBorderColor: Color {
        if isSelected {
            return OrbitaTheme.strongBorder
        }
        return group.isVirtualPlugin ? OrbitaTheme.strongBorder : OrbitaTheme.border
    }

    private var groupSubtitle: String {
        if group.kind == .plugin {
            return "Plugin - \(group.capabilities.count) capabilities"
        }
        let typeNames = Set(group.capabilities.map { $0.type.displayName }).sorted()
        return typeNames.prefix(2).joined(separator: ", ")
    }
}

private extension CapabilityGroup {
    var systemImage: String {
        switch kind {
        case .plugin:
            return CapabilityVisuals.iconName(for: .plugin)
        case .prefix:
            return "square.stack.3d.up.fill"
        }
    }

    var isVirtualPlugin: Bool {
        switch kind {
        case .prefix:
            return true
        case .plugin:
            return false
        }
    }

    func outlineStyle(lineWidth: CGFloat) -> StrokeStyle {
        StrokeStyle(lineWidth: lineWidth, dash: isVirtualPlugin ? [5, 4] : [])
    }
}

private struct CapabilityTile: View {
    let capability: Capability
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                CapabilityTileIcon(
                    capability: capability,
                    isVirtual: capability.isVirtualPlugin,
                    isSelected: isSelected
                )

                VStack(spacing: 3) {
                    Text(capability.name)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .truncationMode(.middle)
                        .frame(minHeight: 32)

                    Text(sourceLabel)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, minHeight: 128, alignment: .top)
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
        }
        .buttonStyle(.plain)
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
        "\(capability.type.displayName) - \(CapabilitySourceClassifier.label(for: capability))"
    }
}

private extension Capability {
    var isVirtualPlugin: Bool {
        type == .plugin && source.kind == "virtual-plugin"
    }
}

private struct CapabilityTileIcon: View {
    let capability: Capability
    let isVirtual: Bool
    let isSelected: Bool

    var body: some View {
        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(isSelected ? OrbitaTheme.controlHoverFill : OrbitaTheme.controlFill)
                .frame(width: 56, height: 52)
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(
                            isSelected || isVirtual ? OrbitaTheme.strongBorder : OrbitaTheme.border,
                            style: StrokeStyle(lineWidth: isSelected ? 1.5 : 1, dash: isVirtual ? [5, 4] : [])
                        )
                }

            Image(systemName: CapabilityVisuals.iconName(for: capability.type))
                .font(.system(size: 21, weight: .medium))
                .foregroundStyle(.primary)
                .frame(width: 56, height: 52)

            Circle()
                .fill(CapabilityVisuals.statusColor(for: capability))
                .frame(width: 8, height: 8)
                .offset(x: 4, y: -4)
                .help(CapabilityVisuals.statusLabel(for: capability))
        }
        .frame(width: 66, height: 58)
    }
}
