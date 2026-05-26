import SwiftUI
import OrbitaCore

struct AddAgentSheet: View {
    @State private var name = ""
    @State private var behavior = AgentBehavior.generic
    @State private var selectedPresetID = ""
    let onAdd: (AgentSelection) -> Void
    let onCancel: () -> Void

    private var presets: [SkillsAgentDefinition] {
        let builtInIDs: Set<String> = ["codex", "claude-code", "cursor"]
        return SkillsAgentCatalog.addableAgents.filter { !builtInIDs.contains($0.id) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add Coding Agent")
                .font(.title2.weight(.semibold))

            Picker("Skills CLI preset", selection: $selectedPresetID) {
                Text("Custom").tag("")
                ForEach(presets) { preset in
                    Text(preset.displayName).tag(preset.id)
                }
            }
            .onChange(of: selectedPresetID) { _, value in
                guard let preset = presets.first(where: { $0.id == value }) else {
                    behavior = .generic
                    return
                }
                name = preset.displayName
                behavior = .skillsAgent
            }

            TextField("Agent name", text: $name)
                .textFieldStyle(.roundedBorder)

            if selectedPresetID.isEmpty {
                Picker("Capability model", selection: $behavior) {
                    Text("Generic").tag(AgentBehavior.generic)
                    Text("Codex-like").tag(AgentBehavior.codexLike)
                    Text("Claude-like").tag(AgentBehavior.claudeLike)
                }
                .pickerStyle(.radioGroup)
            } else {
                LabeledContent("Capability model", value: "Skills CLI install paths")
            }

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                Button("Add") {
                    onAdd(AgentSelection(
                        id: selectedPresetID.isEmpty ? "custom:\(UUID().uuidString)" : "skills-agent:\(selectedPresetID)",
                        displayName: trimmedName,
                        behavior: behavior,
                        skillsAgentID: selectedPresetID.isEmpty ? nil : selectedPresetID
                    ))
                }
                .keyboardShortcut(.defaultAction)
                .disabled(trimmedName.isEmpty)
            }
        }
        .padding()
        .frame(width: 420)
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
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
