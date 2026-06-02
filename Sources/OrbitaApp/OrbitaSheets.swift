import SwiftUI
import OrbitaCore

struct AddAgentSheet: View {
    @ObservedObject private var localization = LocalizationManager.shared
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
                AddAgentFieldLabel(title: L("sheet.addagent.field.source"), systemImage: "wand.and.stars")
                presetMenu

                AddAgentFieldLabel(title: L("sheet.addagent.field.displayname"), systemImage: "textformat")
                    .padding(.top, 2)
                nameField
            }
            .padding(16)
            .orbitaCard(cornerRadius: 18, shadowRadius: 8, shadowY: 4)

            capabilityModelSection

            HStack(spacing: 10) {
                Spacer(minLength: 0)
                AddAgentActionButton(title: L("sheet.action.cancel"), systemImage: "xmark", action: onCancel)
                AddAgentActionButton(
                    title: L("sheet.action.add"),
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
                Label(L("sheet.addagent.preset.custom"), systemImage: "person.crop.circle")
            }

            Divider()

            ForEach(presets) { preset in
                Button {
                    select(preset)
                } label: {
                    Label {
                        Text(preset.displayName)
                    } icon: {
                        Image(nsImage: AgentGlyphImage.nsImage(
                            assetName: AgentBrandIconStore.assetName(forAgentID: preset.id),
                            seed: preset.id,
                            displayName: preset.displayName
                        ))
                    }
                }
            }
        } label: {
            HStack(spacing: 12) {
                Group {
                    if let selectedPreset {
                        AgentGlyph(
                            assetName: AgentBrandIconStore.assetName(forAgentID: selectedPreset.id),
                            seed: selectedPreset.id,
                            displayName: selectedPreset.displayName,
                            size: 18
                        )
                    } else {
                        Image(systemName: "person.crop.circle")
                            .font(.system(size: 16, weight: .semibold))
                    }
                }
                .frame(width: 22)

                VStack(alignment: .leading, spacing: 2) {
                    Text(selectedPreset?.displayName ?? L("sheet.addagent.preset.custom"))
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
        TextField(L("sheet.addagent.field.name.placeholder"), text: $name)
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
            AddAgentFieldLabel(title: L("sheet.addagent.field.capabilitymodel"), systemImage: "slider.horizontal.3")

            if let selectedPreset {
                SkillsPresetSummary(preset: selectedPreset)
            } else {
                // A custom tool uses the default (Generic) scheme for now. Agent-specific schemes
                // (Codex/Claude visibility rules) are intentionally not offered in the add panel yet — the
                // note below tells the user which scheme they're getting.
                DefaultSchemeNote()
            }
        }
    }

    private var presetDetail: String {
        guard let selectedPreset else {
            return L("sheet.addagent.preset.manualview")
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
            return L("sheet.addagent.noglobalpath")
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
    @ObservedObject private var localization = LocalizationManager.shared
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
                Text(L("sheet.addagent.header.title"))
                    .font(.title2.weight(.semibold))
                Text(L("sheet.addagent.header.subtitle"))
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

private struct DefaultSchemeNote: View {
    @ObservedObject private var localization = LocalizationManager.shared
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 24)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(L("sheet.addagent.scheme.generic"))
                        .font(.subheadline.weight(.semibold))
                    Text(L("sheet.addagent.scheme.default"))
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(OrbitaTheme.controlFill, in: Capsule())
                }

                Text(L("sheet.addagent.scheme.note"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .orbitaCard(cornerRadius: 16, shadowRadius: 6, shadowY: 3)
    }
}

private struct SkillsPresetSummary: View {
    @ObservedObject private var localization = LocalizationManager.shared
    let preset: SkillsAgentDefinition

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "folder.badge.gearshape")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 24)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(L("sheet.addagent.skillspaths.title"))
                        .font(.subheadline.weight(.semibold))
                    Text(preset.usesSharedProjectSkills ? L("sheet.addagent.skillspaths.shared") : L("sheet.addagent.skillspaths.dedicated"))
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
            return L("sheet.addagent.noglobalpath")
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
    @ObservedObject private var localization = LocalizationManager.shared
    let capability: Capability
    let agents: [AgentSelection]
    let visibleAgentIDs: Set<String>
    /// True when a real project (not "This Mac") is open, so a user-scope source may also be forked
    /// INTO that project — but only as a deep copy (the core rejects a user→project symlink).
    let allowsProjectLocation: Bool
    let onSelect: (SyncCapabilityRequest) -> Void
    let onCancel: () -> Void

    @State private var selectedAgentID: String?
    @State private var selectedMode: AgentSyncMode
    @State private var selectedDestinationScope: AgentSyncDestinationScope

    init(
        capability: Capability,
        agents: [AgentSelection],
        visibleAgentIDs: Set<String>,
        allowsProjectLocation: Bool = false,
        onSelect: @escaping (SyncCapabilityRequest) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.capability = capability
        self.agents = agents
        self.visibleAgentIDs = visibleAgentIDs
        self.allowsProjectLocation = allowsProjectLocation
        self.onSelect = onSelect
        self.onCancel = onCancel
        _selectedAgentID = State(initialValue: agents.first { !visibleAgentIDs.contains($0.id) }?.id ?? agents.first?.id)
        _selectedMode = State(initialValue: .copy)
        _selectedDestinationScope = State(initialValue: capability.scope == .project ? .project : .user)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            CategorySheetHeader(
                title: L("sheet.sync.title"),
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
            .onChange(of: selectedMode) { _, _ in
                // Switching to symlink can remove `.project` for a user-scope source — fall back to Global
                // so the selection never points at an option that is no longer offered.
                if !destinationScopes.contains(selectedDestinationScope) {
                    selectedDestinationScope = .user
                }
            }

            HStack(spacing: 10) {
                Label(statusText, systemImage: "info.circle")
                    // statusText is already localized
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)

                AddAgentActionButton(title: L("sheet.action.cancel"), systemImage: "xmark", action: onCancel)
                AddAgentActionButton(
                    title: L("sheet.action.sync"),
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
                title: L("sheet.sync.step.destination"),
                detail: selectedAgent.map { String(format: L("sheet.sync.destination.syncto"), $0.displayName) } ?? L("sheet.sync.destination.choose")
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
            SyncStepHeader(number: 2, title: L("sheet.sync.step.method"), detail: selectedMode.title)

            VStack(spacing: 8) {
                SyncOptionButton(
                    title: L("sheet.sync.method.copy"),
                    detail: L("sheet.sync.method.copy.detail"),
                    systemImage: "doc.on.doc",
                    isSelected: selectedMode == .copy
                ) {
                    selectedMode = .copy
                }

                SyncOptionButton(
                    title: L("sheet.sync.method.symlink"),
                    detail: L("sheet.sync.method.symlink.detail"),
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
            SyncStepHeader(number: 3, title: L("sheet.sync.step.location"), detail: selectedDestinationScope.title)

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

            Label(selectedAgent?.displayName ?? L("sheet.sync.preview.agent"), systemImage: "person.crop.circle")
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
            return L("sheet.sync.status.choose")
        }
        if visibleAgentIDs.contains(selectedAgent.id) {
            return String(format: L("sheet.sync.status.alreadyhas"), selectedAgent.displayName)
        }
        return String(format: L("sheet.sync.status.ready"), selectedAgent.displayName)
    }

    private var selectedAgent: AgentSelection? {
        agents.first { $0.id == selectedAgentID }
    }

    private var destinationScopes: [AgentSyncDestinationScope] {
        if capability.scope == .project { return [.project, .user] }
        // A user-scope ("This Mac") source can be forked INTO an open project, but only as a deep copy —
        // a symlink would commit an absolute link into ~/.agents to the repo. So `.project` appears for a
        // user-scope source only when a project is open AND the deep-copy method is selected.
        if allowsProjectLocation, selectedMode == .copy { return [.project, .user] }
        return [.user]
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
    @ObservedObject private var localization = LocalizationManager.shared
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
                    Text(isAlreadyVisible ? L("sheet.sync.row.alreadyavailable") : L("sheet.sync.row.availabletarget"))
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

@MainActor
private extension AgentSyncMode {
    var title: String {
        switch self {
        case .copy:
            return L("sheet.sync.method.copy")
        case .symlink:
            return L("sheet.sync.method.symlink")
        }
    }

    var summaryTitle: String {
        switch self {
        case .copy:
            return L("sheet.sync.summary.copy.title")
        case .symlink:
            return L("sheet.sync.summary.symlink.title")
        }
    }

    var summaryDetail: String {
        switch self {
        case .copy:
            return L("sheet.sync.summary.copy.detail")
        case .symlink:
            return L("sheet.sync.summary.symlink.detail")
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

@MainActor
private extension AgentSyncDestinationScope {
    var title: String {
        switch self {
        case .project:
            return L("sheet.sync.scope.project")
        case .user:
            return L("sheet.sync.scope.global")
        }
    }

    var detail: String {
        switch self {
        case .project:
            return L("sheet.sync.scope.project.detail")
        case .user:
            return L("sheet.sync.scope.global.detail")
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
            return L("sheet.sync.scope.project.summary")
        case .user:
            return L("sheet.sync.scope.global.summary")
        }
    }

    var summaryDetail: String {
        switch self {
        case .project:
            return L("sheet.sync.scope.project.summary.detail")
        case .user:
            return L("sheet.sync.scope.global.summary.detail")
        }
    }
}

struct ScopedCapabilityActionSheet: View {
    @ObservedObject private var localization = LocalizationManager.shared
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
                subtitle: L("sheet.scoped.subtitle"),
                systemImage: headerSystemImage
            )

            ActionImpactPanel(
                title: impactTitle,
                message: displayedMessage,
                systemImage: messageSystemImage,
                tint: messageColor
            )

            HStack(spacing: 10) {
                AddAgentActionButton(title: L("sheet.action.cancel"), systemImage: "xmark", action: onCancel)

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
        isShowingSecondaryConfirmation ? L("sheet.scoped.header.linkeddelete") : title
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
            return L("sheet.scoped.impact.linkedremoved")
        }
        return isDestructive ? L("sheet.scoped.impact.permanentdelete") : L("sheet.scoped.impact.willbedisabled")
    }

    private var showsContinueButton: Bool {
        secondaryConfirmationMessage != nil && !isShowingSecondaryConfirmation
    }

    private var actionButtonTitle: String {
        showsContinueButton ? L("sheet.scoped.action.continue") : primaryButtonTitle
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
    @ObservedObject private var localization = LocalizationManager.shared
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
                title: L("sheet.hide.title"),
                subtitle: L("sheet.hide.subtitle"),
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
                AddAgentActionButton(title: L("sheet.hide.showall"), systemImage: "eye") {
                    hiddenIDs.removeAll()
                }

                Spacer(minLength: 0)

                AddAgentActionButton(title: L("sheet.action.cancel"), systemImage: "xmark", action: onCancel)
                AddAgentActionButton(
                    title: L("sheet.action.save"),
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
    @ObservedObject private var localization = LocalizationManager.shared
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
                Text(isLocked ? L("sheet.hide.row.alwaysvisible") : isHidden ? L("sheet.hide.row.hidden") : L("sheet.hide.row.visible"))
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
    @ObservedObject private var localization = LocalizationManager.shared
    let plan: ApplyPlan
    let onCancel: () -> Void
    let onApply: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L("sheet.apply.title"))
                    .font(.title2.weight(.semibold))
                Text(L("sheet.apply.subtitle"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            LabeledContent(L("sheet.apply.row.action"), value: plan.action.displayTitle)
            LabeledContent(L("sheet.apply.row.capability"), value: plan.capabilityID)
            LabeledContent(L("sheet.apply.row.operations"), value: "\(plan.operations.count)")
            LabeledContent(L("sheet.apply.row.confirmation"), value: plan.requiresConfirmation ? L("sheet.apply.confirmation.required") : L("sheet.apply.confirmation.notrequired"))

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
                        Text(String(format: L("sheet.apply.operation.target"), target))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
            }

            HStack {
                Spacer()
                Button(L("sheet.action.cancel"), action: onCancel)
                Button(L("sheet.action.apply"), action: onApply)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(minWidth: 560, minHeight: 420)
        .presentationBackground(OrbitaTheme.canvas)
    }
}
