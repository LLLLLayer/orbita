import SwiftUI
import OrbitaCore

struct AddAgentSheet: View {
    @State private var name = ""
    @State private var behavior = AgentBehavior.generic
    @State private var selectedPresetID = ""
    @FocusState private var nameFieldFocused: Bool

    let onAdd: (AgentSelection) -> Void
    let onCancel: () -> Void

    private var presets: [SkillsAgentDefinition] {
        let builtInIDs: Set<String> = ["codex", "claude-code", "cursor", "trae"]
        return SkillsAgentCatalog.addableAgents.filter { !builtInIDs.contains($0.id) }
    }

    private var selectedPreset: SkillsAgentDefinition? {
        presets.first { $0.id == selectedPresetID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            AddAgentHeader()

            VStack(alignment: .leading, spacing: 14) {
                AddAgentFieldLabel(title: "Agent source", systemImage: "wand.and.stars")
                presetMenu

                AddAgentFieldLabel(title: "Display name", systemImage: "textformat")
                    .padding(.top, 2)
                nameField
            }
            .padding(16)
            .orbitaCard(cornerRadius: 18, shadowRadius: 8, shadowY: 4)

            capabilityModelSection

            HStack(spacing: 10) {
                Spacer(minLength: 0)
                AddAgentActionButton(title: "Cancel", systemImage: "xmark", action: onCancel)
                AddAgentActionButton(
                    title: "Add",
                    systemImage: "plus",
                    prominent: true,
                    isDisabled: trimmedName.isEmpty,
                    action: addAgent
                )
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 560)
        .background(OrbitaTheme.canvas)
        .presentationBackground(OrbitaTheme.canvas)
        .onAppear {
            nameFieldFocused = true
        }
    }

    private var presetMenu: some View {
        Menu {
            Button {
                selectCustomPreset()
            } label: {
                Label("Custom", systemImage: "person.crop.circle")
            }

            Divider()

            ForEach(presets) { preset in
                Button {
                    select(preset)
                } label: {
                    Label(preset.displayName, systemImage: "wand.and.stars")
                }
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: selectedPreset == nil ? "person.crop.circle" : "wand.and.stars")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: 2) {
                    Text(selectedPreset?.displayName ?? "Custom")
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text(presetDetail)
                        .font(.caption)
                        .foregroundStyle(selectedPreset == nil ? .secondary : OrbitaTheme.prominentControlForeground.opacity(0.72))
                        .lineLimit(1)
                }

                Spacer(minLength: 12)

                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(selectedPreset == nil ? .secondary : OrbitaTheme.prominentControlForeground.opacity(0.78))
            }
            .padding(.horizontal, 12)
            .frame(height: 48)
            .foregroundStyle(selectedPreset == nil ? Color.primary : OrbitaTheme.prominentControlForeground)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .orbitaControlSurface(selected: selectedPreset != nil, cornerRadius: 14)
    }

    private var nameField: some View {
        TextField("Agent name", text: $name)
            .textFieldStyle(.plain)
            .font(.body.weight(.medium))
            .padding(.horizontal, 12)
            .frame(height: 40)
            .background(OrbitaTheme.controlFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(nameFieldFocused ? OrbitaTheme.strongBorder : OrbitaTheme.border, lineWidth: nameFieldFocused ? 1.5 : 1)
            }
            .focused($nameFieldFocused)
            .onSubmit(addAgent)
    }

    @ViewBuilder
    private var capabilityModelSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            AddAgentFieldLabel(title: "Capability model", systemImage: "slider.horizontal.3")

            if selectedPreset == nil {
                HStack(spacing: 10) {
                    ForEach(AddAgentBehaviorOption.customOptions) { option in
                        AddAgentBehaviorButton(
                            option: option,
                            isSelected: behavior == option.behavior
                        ) {
                            behavior = option.behavior
                        }
                    }
                }
            } else if let selectedPreset {
                SkillsPresetSummary(preset: selectedPreset)
            }
        }
    }

    private var presetDetail: String {
        guard let selectedPreset else {
            return "Manual capability view"
        }
        return "\(selectedPreset.projectSkillsDir) / \(displayPath(selectedPreset.globalSkillsDir))"
    }

    private func select(_ preset: SkillsAgentDefinition) {
        selectedPresetID = preset.id
        name = preset.displayName
        behavior = .skillsAgent
    }

    private func selectCustomPreset() {
        selectedPresetID = ""
        behavior = .generic
    }

    private func addAgent() {
        guard !trimmedName.isEmpty else {
            return
        }
        onAdd(AgentSelection(
            id: selectedPresetID.isEmpty ? "custom:\(UUID().uuidString)" : "skills-agent:\(selectedPresetID)",
            displayName: trimmedName,
            behavior: behavior,
            skillsAgentID: selectedPresetID.isEmpty ? nil : selectedPresetID
        ))
    }

    private func displayPath(_ path: String?) -> String {
        guard let path, !path.isEmpty else {
            return "No global path"
        }
        let homePath = FileManager.default.homeDirectoryForCurrentUser.path
        if path == homePath {
            return "~"
        }
        if path.hasPrefix(homePath + "/") {
            return "~" + path.dropFirst(homePath.count)
        }
        return path
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct AddAgentHeader: View {
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(OrbitaTheme.controlFill)
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(OrbitaTheme.border)
                    }

                Image(systemName: "plus.square.dashed")
                    .font(.system(size: 20, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
            }
            .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 2) {
                Text("Add Coding Agent")
                    .font(.title2.weight(.semibold))
                Text("Preset or custom capability view")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
    }
}

private struct AddAgentFieldLabel: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .labelStyle(.titleAndIcon)
    }
}

private struct AddAgentBehaviorOption: Identifiable {
    let behavior: AgentBehavior
    let title: String
    let subtitle: String
    let systemImage: String

    var id: AgentBehavior { behavior }

    static let customOptions: [AddAgentBehaviorOption] = [
        .init(
            behavior: .generic,
            title: "Generic",
            subtitle: "All enabled capabilities",
            systemImage: "square.grid.2x2"
        ),
        .init(
            behavior: .codexLike,
            title: "Codex-style",
            subtitle: "Codex visibility rules",
            systemImage: "command"
        ),
        .init(
            behavior: .claudeLike,
            title: "Claude-style",
            subtitle: "Claude visibility rules",
            systemImage: "text.bubble"
        )
    ]
}

private struct AddAgentBehaviorButton: View {
    let option: AddAgentBehaviorOption
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: option.systemImage)
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 22, height: 20, alignment: .leading)

                VStack(alignment: .leading, spacing: 2) {
                    Text(option.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text(option.subtitle)
                        .font(.caption)
                        .foregroundStyle(isSelected ? OrbitaTheme.prominentControlForeground.opacity(0.72) : .secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
            .foregroundStyle(isSelected ? OrbitaTheme.prominentControlForeground : Color.primary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .orbitaControlSurface(selected: isSelected, cornerRadius: 14)
    }
}

private struct SkillsPresetSummary: View {
    let preset: SkillsAgentDefinition

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "folder.badge.gearshape")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 24)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text("Skills CLI install paths")
                        .font(.subheadline.weight(.semibold))
                    Text(preset.usesSharedProjectSkills ? "Shared" : "Dedicated")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(OrbitaTheme.controlFill, in: Capsule())
                }

                Text("\(preset.projectSkillsDir) / \(displayPath(preset.globalSkillsDir))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .textSelection(.enabled)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .orbitaCard(cornerRadius: 16, shadowRadius: 6, shadowY: 3)
    }

    private func displayPath(_ path: String?) -> String {
        guard let path, !path.isEmpty else {
            return "No global path"
        }
        let homePath = FileManager.default.homeDirectoryForCurrentUser.path
        if path == homePath {
            return "~"
        }
        if path.hasPrefix(homePath + "/") {
            return "~" + path.dropFirst(homePath.count)
        }
        return path
    }
}

private struct AddAgentActionButton: View {
    let title: String
    let systemImage: String
    var prominent = false
    var isDisabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .labelStyle(.titleAndIcon)
                .padding(.horizontal, 12)
                .frame(height: 34)
                .foregroundStyle(prominent ? OrbitaTheme.prominentControlForeground : Color.primary)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .orbitaControlSurface(selected: prominent, cornerRadius: 11)
        .opacity(isDisabled ? 0.42 : 1)
        .disabled(isDisabled)
    }
}

struct SyncCapabilityRequest {
    var agent: AgentSelection
    var mode: AgentSyncMode
    var destinationScope: AgentSyncDestinationScope
}

struct SyncCapabilitySheet: View {
    let capability: Capability
    let agents: [AgentSelection]
    let visibleAgentIDs: Set<String>
    let onSelect: (SyncCapabilityRequest) -> Void
    let onCancel: () -> Void

    @State private var selectedAgentID: String?
    @State private var selectedMode: AgentSyncMode
    @State private var selectedDestinationScope: AgentSyncDestinationScope

    init(
        capability: Capability,
        agents: [AgentSelection],
        visibleAgentIDs: Set<String>,
        onSelect: @escaping (SyncCapabilityRequest) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.capability = capability
        self.agents = agents
        self.visibleAgentIDs = visibleAgentIDs
        self.onSelect = onSelect
        self.onCancel = onCancel
        _selectedAgentID = State(initialValue: agents.first { !visibleAgentIDs.contains($0.id) }?.id ?? agents.first?.id)
        _selectedMode = State(initialValue: .copy)
        _selectedDestinationScope = State(initialValue: capability.scope == .project ? .project : .user)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            CategorySheetHeader(
                title: "Sync to Agent",
                subtitle: syncSubtitle,
                systemImage: "arrow.triangle.branch"
            )

            VStack(spacing: 12) {
                destinationPanel

                HStack(alignment: .top, spacing: 12) {
                    methodPanel
                    locationPanel
                }

                syncPreview
            }

            HStack(spacing: 10) {
                Label(statusText, systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)

                AddAgentActionButton(title: "Cancel", systemImage: "xmark", action: onCancel)
                AddAgentActionButton(
                    title: "Sync",
                    systemImage: "arrow.triangle.branch",
                    prominent: true,
                    isDisabled: selectedAgent == nil
                ) {
                    guard let selectedAgent else { return }
                    onSelect(SyncCapabilityRequest(
                        agent: selectedAgent,
                        mode: selectedMode,
                        destinationScope: selectedDestinationScope
                    ))
                }
            }
        }
        .padding(22)
        .frame(width: 620)
        .background(OrbitaTheme.canvas)
        .presentationBackground(OrbitaTheme.canvas)
    }

    private var syncSubtitle: String {
        capability.name
    }

    private var destinationPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            SyncStepHeader(
                number: 1,
                title: "Destination",
                detail: selectedAgent.map { "Sync to \($0.displayName)" } ?? "Choose an agent"
            )

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(agents.enumerated()), id: \.element.id) { index, agent in
                        SyncAgentRow(
                            agent: agent,
                            isAlreadyVisible: visibleAgentIDs.contains(agent.id),
                            isSelected: selectedAgentID == agent.id
                        ) {
                            selectedAgentID = agent.id
                        }

                        if index < agents.count - 1 {
                            Divider()
                                .padding(.leading, 54)
                        }
                    }
                }
                .padding(.vertical, 6)
            }
            .frame(height: min(236, CGFloat(max(agents.count, 1)) * 58 + 12))
            .background(OrbitaTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(OrbitaTheme.border)
            }
        }
        .padding(14)
        .orbitaCard(cornerRadius: 18, shadowRadius: 8, shadowY: 4)
    }

    private var methodPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            SyncStepHeader(number: 2, title: "Method", detail: selectedMode.title)

            VStack(spacing: 8) {
                SyncOptionButton(
                    title: "Copy",
                    detail: "Create an independent file at the target.",
                    systemImage: "doc.on.doc",
                    isSelected: selectedMode == .copy
                ) {
                    selectedMode = .copy
                }

                SyncOptionButton(
                    title: "Symlink",
                    detail: "Point the target back to this source.",
                    systemImage: "link",
                    isSelected: selectedMode == .symlink
                ) {
                    selectedMode = .symlink
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .orbitaCard(cornerRadius: 18, shadowRadius: 8, shadowY: 4)
    }

    private var locationPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            SyncStepHeader(number: 3, title: "Location", detail: selectedDestinationScope.title)

            VStack(spacing: 8) {
                ForEach(destinationScopes, id: \.self) { scope in
                    SyncOptionButton(
                        title: scope.title,
                        detail: scope.detail,
                        systemImage: scope.systemImage,
                        isSelected: selectedDestinationScope == scope
                    ) {
                        selectedDestinationScope = scope
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .orbitaCard(cornerRadius: 18, shadowRadius: 8, shadowY: 4)
    }

    private var syncPreview: some View {
        HStack(spacing: 10) {
            Label(capability.name, systemImage: capabilityPreviewIcon)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .truncationMode(.middle)

            Image(systemName: "arrow.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Label(selectedAgent?.displayName ?? "Agent", systemImage: "person.crop.circle")
                .font(.caption.weight(.semibold))
                .lineLimit(1)

            Spacer(minLength: 8)

            Text("\(selectedMode.title) · \(selectedDestinationScope.title)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .frame(height: 40)
        .background(OrbitaTheme.controlFill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(OrbitaTheme.border)
        }
    }

    private var statusText: String {
        guard let selectedAgent else {
            return "Choose a destination agent."
        }
        if visibleAgentIDs.contains(selectedAgent.id) {
            return "\(selectedAgent.displayName) already has this capability."
        }
        return "Ready to sync to \(selectedAgent.displayName)."
    }

    private var selectedAgent: AgentSelection? {
        agents.first { $0.id == selectedAgentID }
    }

    private var destinationScopes: [AgentSyncDestinationScope] {
        capability.scope == .project ? [.project, .user] : [.user]
    }

    private var capabilityPreviewIcon: String {
        switch capability.type {
        case .skill:
            return "wand.and.stars"
        case .command:
            return "terminal"
        case .agent:
            return "person.crop.circle"
        case .plugin:
            return "shippingbox"
        case .mcpServer:
            return "server.rack"
        case .rule:
            return "checklist"
        case .instruction:
            return "doc.text"
        case .hook:
            return "point.3.connected.trianglepath.dotted"
        case .unknown:
            return "questionmark.circle"
        }
    }
}

private struct SyncStepHeader: View {
    let number: Int
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 9) {
            Text("\(number)")
                .font(.caption.weight(.bold))
                .foregroundStyle(OrbitaTheme.prominentControlForeground)
                .frame(width: 20, height: 20)
                .background(OrbitaTheme.prominentControlFill, in: Circle())

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Text(detail)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 0)
        }
    }
}

private struct SyncAgentRow: View {
    let agent: AgentSelection
    let isAlreadyVisible: Bool
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                AgentBrandIcon(agent: agent, size: 18)
                    .frame(width: 30, height: 30)

                VStack(alignment: .leading, spacing: 2) {
                    Text(agent.displayName)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text(isAlreadyVisible ? "Already available" : "Available target")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 12)

                Image(systemName: trailingSystemImage)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(trailingColor)
                    .frame(width: 24, height: 24)
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(OrbitaTheme.controlFill)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
            }
        }
    }

    private var trailingSystemImage: String {
        isSelected ? "checkmark.circle.fill" : isAlreadyVisible ? "checkmark.circle" : "plus.circle"
    }

    private var trailingColor: Color {
        if isSelected { return .accentColor }
        if isAlreadyVisible { return .green }
        return .secondary
    }
}

private struct SyncOptionButton: View {
    let title: String
    let detail: String
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(isSelected ? OrbitaTheme.prominentControlForeground.opacity(0.72) : .secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, minHeight: 62, alignment: .leading)
            .foregroundStyle(isSelected ? OrbitaTheme.prominentControlForeground : Color.primary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .orbitaControlSurface(selected: isSelected, cornerRadius: 14)
    }
}

private struct SyncSummaryRow: View {
    let title: String
    let detail: String
    let systemImage: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 20, height: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
    }
}

private extension AgentSyncMode {
    var title: String {
        switch self {
        case .copy:
            return "Copy"
        case .symlink:
            return "Symlink"
        }
    }

    var summaryTitle: String {
        switch self {
        case .copy:
            return "Copies are independent"
        case .symlink:
            return "Symlinks follow the source"
        }
    }

    var summaryDetail: String {
        switch self {
        case .copy:
            return "Future edits to the original will not update this target automatically."
        case .symlink:
            return "The target points back to the original capability on disk."
        }
    }

    var summarySystemImage: String {
        switch self {
        case .copy:
            return "doc.on.doc"
        case .symlink:
            return "link"
        }
    }
}

private extension AgentSyncDestinationScope {
    var title: String {
        switch self {
        case .project:
            return "Project"
        case .user:
            return "Global"
        }
    }

    var detail: String {
        switch self {
        case .project:
            return "Install into this project only."
        case .user:
            return "Install for local projects on this Mac."
        }
    }

    var systemImage: String {
        switch self {
        case .project:
            return "folder"
        case .user:
            return "desktopcomputer"
        }
    }

    var summaryTitle: String {
        switch self {
        case .project:
            return "Installs into the project"
        case .user:
            return "Installs globally"
        }
    }

    var summaryDetail: String {
        switch self {
        case .project:
            return "Only this project gets the synced capability."
        case .user:
            return "The selected agent can use it across local projects."
        }
    }
}

struct ScopedCapabilityActionSheet: View {
    let title: String
    let message: String
    let primaryButtonTitle: String
    let secondaryConfirmationMessage: String?
    let isDestructive: Bool
    let onConfirm: () -> Void
    let onCancel: () -> Void

    @State private var isShowingSecondaryConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            CategorySheetHeader(
                title: headerTitle,
                subtitle: "Review current capability",
                systemImage: headerSystemImage
            )

            ActionImpactPanel(
                title: impactTitle,
                message: displayedMessage,
                systemImage: messageSystemImage,
                tint: messageColor
            )

            HStack(spacing: 10) {
                AddAgentActionButton(title: "Cancel", systemImage: "xmark", action: onCancel)

                Spacer(minLength: 0)

                ScopedActionButton(
                    title: actionButtonTitle,
                    systemImage: actionButtonSystemImage,
                    isDestructive: isDestructive && !showsContinueButton,
                    action: confirmOrContinue
                )
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 560)
        .background(OrbitaTheme.canvas)
        .presentationBackground(OrbitaTheme.canvas)
    }

    private var headerTitle: String {
        isShowingSecondaryConfirmation ? "Confirm Linked Delete" : title
    }

    private var headerSystemImage: String {
        if isShowingSecondaryConfirmation {
            return "exclamationmark.triangle"
        }
        return isDestructive ? "trash" : "minus.circle"
    }

    private var displayedMessage: String {
        isShowingSecondaryConfirmation ? (secondaryConfirmationMessage ?? message) : message
    }

    private var messageSystemImage: String {
        if isShowingSecondaryConfirmation {
            return "exclamationmark.triangle.fill"
        }
        return isDestructive ? "exclamationmark.triangle.fill" : "info.circle.fill"
    }

    private var messageColor: Color {
        isDestructive ? .red : .secondary
    }

    private var impactTitle: String {
        if isShowingSecondaryConfirmation {
            return "Linked targets will be removed"
        }
        return isDestructive ? "Permanent delete" : "Capability will be disabled"
    }

    private var showsContinueButton: Bool {
        secondaryConfirmationMessage != nil && !isShowingSecondaryConfirmation
    }

    private var actionButtonTitle: String {
        showsContinueButton ? "Continue" : primaryButtonTitle
    }

    private var actionButtonSystemImage: String {
        if showsContinueButton {
            return "arrow.right.circle"
        }
        return isDestructive ? "trash" : "minus.circle"
    }

    private func confirmOrContinue() {
        if showsContinueButton {
            isShowingSecondaryConfirmation = true
            return
        }
        onConfirm()
    }
}

private struct ScopedActionButton: View {
    let title: String
    let systemImage: String
    var isDestructive = false
    var isDisabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .labelStyle(.titleAndIcon)
                .lineLimit(1)
                .minimumScaleFactor(0.9)
                .padding(.horizontal, 12)
                .frame(height: 34)
                .foregroundStyle(foregroundColor)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(backgroundColor, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(borderColor)
        }
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.46 : 1)
    }

    private var foregroundColor: Color {
        if isDisabled {
            return .secondary
        }
        return isDestructive ? .red : .primary
    }

    private var backgroundColor: Color {
        isDestructive ? Color.red.opacity(0.11) : OrbitaTheme.controlFill
    }

    private var borderColor: Color {
        isDestructive ? Color.red.opacity(0.24) : OrbitaTheme.border
    }
}

private struct ActionImpactPanel: View {
    let title: String
    let message: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(tint.opacity(0.12))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(tint.opacity(0.22))
                    }

                Image(systemName: systemImage)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(tint)
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.headline.weight(.semibold))
                    .lineLimit(1)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .orbitaCard(cornerRadius: 18, shadowRadius: 8, shadowY: 4)
    }
}

private struct HelpBadge: View {
    let help: String

    var body: some View {
        Image(systemName: "questionmark.circle")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(width: 28, height: 28)
            .background(OrbitaTheme.controlFill, in: Circle())
            .overlay {
                Circle().strokeBorder(OrbitaTheme.border)
            }
            .help(help)
            .accessibilityLabel(help)
    }
}

struct HideCategoriesSheet: View {
    let categories: [CapabilityCategory]
    let onSave: (Set<String>) -> Void
    let onCancel: () -> Void

    @State private var hiddenIDs: Set<String>

    init(
        categories: [CapabilityCategory],
        hiddenCategoryIDs: Set<String>,
        onSave: @escaping (Set<String>) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.categories = categories
        self.onSave = onSave
        self.onCancel = onCancel
        _hiddenIDs = State(initialValue: hiddenCategoryIDs)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            CategorySheetHeader(
                title: "Hidden Categories",
                subtitle: "Second filter visibility",
                systemImage: "eye.slash"
            )

            ScrollView {
                VStack(spacing: 8) {
                    ForEach(categories) { category in
                        HideCategoryRow(
                            category: category,
                            isHidden: hiddenIDs.contains(category.rawValue),
                            isLocked: category == .all
                        ) {
                            toggle(category)
                        }
                    }
                }
                .padding(14)
            }
            .frame(height: 340)
            .orbitaCard(cornerRadius: 18, shadowRadius: 8, shadowY: 4)

            HStack(spacing: 10) {
                AddAgentActionButton(title: "Show All", systemImage: "eye") {
                    hiddenIDs.removeAll()
                }

                Spacer(minLength: 0)

                AddAgentActionButton(title: "Cancel", systemImage: "xmark", action: onCancel)
                AddAgentActionButton(
                    title: "Save",
                    systemImage: "checkmark",
                    prominent: true
                ) {
                    onSave(hiddenIDs)
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 560)
        .background(OrbitaTheme.canvas)
        .presentationBackground(OrbitaTheme.canvas)
    }

    private func toggle(_ category: CapabilityCategory) {
        guard category != .all else {
            return
        }
        withAnimation(.snappy(duration: 0.18)) {
            if hiddenIDs.contains(category.rawValue) {
                hiddenIDs.remove(category.rawValue)
            } else {
                hiddenIDs.insert(category.rawValue)
            }
        }
    }
}

private struct CategorySheetHeader: View {
    let title: String
    let subtitle: String
    let systemImage: String

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(OrbitaTheme.controlFill)
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(OrbitaTheme.border)
                    }

                Image(systemName: systemImage)
                    .font(.system(size: 20, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
            }
            .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.title2.weight(.semibold))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
    }
}

private struct HideCategoryRow: View {
    let category: CapabilityCategory
    let isHidden: Bool
    let isLocked: Bool
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            CategoryIcon(category: category)

            VStack(alignment: .leading, spacing: 2) {
                Text(category.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(isLocked ? "Always visible" : isHidden ? "Hidden" : "Visible")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            Button(action: onToggle) {
                Image(systemName: isHidden ? "eye.slash" : "eye")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 34, height: 28)
                    .foregroundStyle(isHidden ? .secondary : .primary)
            }
            .buttonStyle(.plain)
            .orbitaControlSurface(cornerRadius: 9)
            .disabled(isLocked)
            .opacity(isLocked ? 0.42 : 1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
        .background(OrbitaTheme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(OrbitaTheme.border)
        }
    }
}

private struct CategoryIcon: View {
    let category: CapabilityCategory

    var body: some View {
        Image(systemName: category.managementSystemImage)
            .font(.system(size: 16, weight: .semibold))
            .frame(width: 34, height: 34)
            .background(OrbitaTheme.controlFill, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(OrbitaTheme.border)
            }
    }
}

private extension CapabilityCategory {
    var managementSystemImage: String {
        switch self {
        case .all:
            return "square.grid.2x2"
        case .plugin:
            return "shippingbox"
        case .skill:
            return "wand.and.stars"
        case .agent:
            return "person.2"
        case .command:
            return "terminal"
        case .mcp:
            return "server.rack"
        case .hook:
            return "link"
        case .instruction:
            return "text.book.closed"
        }
    }
}

struct ApplyPlanSheet: View {
    let plan: ApplyPlan
    let onCancel: () -> Void
    let onApply: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Confirm Changes")
                    .font(.title2.weight(.semibold))
                Text("Nothing has been changed yet. Review the file operations before applying.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            LabeledContent("Action", value: plan.action.displayTitle)
            LabeledContent("Capability", value: plan.capabilityID)
            LabeledContent("Operations", value: "\(plan.operations.count)")
            LabeledContent("Confirmation", value: plan.requiresConfirmation ? "Required" : "Not required")

            List(plan.operations, id: \.self) { operation in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(operation.kind.displayTitle)
                            .font(.headline)
                        Spacer()
                        Text(operation.risk.accessLabel)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(OrbitaTheme.controlFill, in: Capsule())
                    }
                    Text(operation.description)
                        .font(.subheadline)
                    Text(operation.path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    if let target = operation.target {
                        Text("Target: \(target)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
            }

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                Button("Apply", action: onApply)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(minWidth: 560, minHeight: 420)
        .presentationBackground(OrbitaTheme.canvas)
    }
}
