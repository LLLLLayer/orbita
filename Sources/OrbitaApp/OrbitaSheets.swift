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
        let builtInIDs: Set<String> = ["codex", "claude-code", "cursor"]
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

struct SyncCapabilitySheet: View {
    let capability: Capability
    let agents: [AgentSelection]
    let visibleAgentIDs: Set<String>
    let onSelect: (AgentSelection) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            CategorySheetHeader(
                title: "Sync to Agent",
                subtitle: capability.name,
                systemImage: "arrow.triangle.branch"
            )

            ScrollView {
                VStack(spacing: 8) {
                    ForEach(agents) { agent in
                        SyncAgentRow(
                            agent: agent,
                            isAlreadyVisible: visibleAgentIDs.contains(agent.id)
                        ) {
                            onSelect(agent)
                        }
                    }
                }
                .padding(14)
            }
            .frame(height: min(340, CGFloat(max(agents.count, 1)) * 62 + 28))
            .orbitaCard(cornerRadius: 18, shadowRadius: 8, shadowY: 4)

            HStack(spacing: 10) {
                Text("Targets match the current Agent row order.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer(minLength: 0)

                AddAgentActionButton(title: "Cancel", systemImage: "xmark", action: onCancel)
            }
        }
        .padding(22)
        .frame(width: 500)
        .background(OrbitaTheme.canvas)
        .presentationBackground(OrbitaTheme.canvas)
    }
}

private struct SyncAgentRow: View {
    let agent: AgentSelection
    let isAlreadyVisible: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                AgentBrandIcon(agent: agent, size: 18)
                    .frame(width: 34, height: 34)
                    .background(OrbitaTheme.controlFill, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .strokeBorder(OrbitaTheme.border)
                    }

                VStack(alignment: .leading, spacing: 2) {
                    Text(agent.displayName)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text(isAlreadyVisible ? "Already synced" : "Sync capability here")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 12)

                Image(systemName: isAlreadyVisible ? "checkmark.circle.fill" : "arrow.right.circle")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(isAlreadyVisible ? Color.green : Color.primary)
                    .frame(width: 24, height: 24)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(OrbitaTheme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(OrbitaTheme.border)
        }
        .disabled(isAlreadyVisible)
        .opacity(isAlreadyVisible ? 0.56 : 1)
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
