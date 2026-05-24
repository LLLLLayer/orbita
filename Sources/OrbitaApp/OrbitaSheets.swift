import SwiftUI
import OrbitaCore

struct AddAgentSheet: View {
    @State private var name = ""
    @State private var behavior = AgentBehavior.generic
    let onAdd: (AgentSelection) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add Coding Agent")
                .font(.title2.weight(.semibold))

            TextField("Agent name", text: $name)
                .textFieldStyle(.roundedBorder)

            Picker("Capability model", selection: $behavior) {
                Text("Generic").tag(AgentBehavior.generic)
                Text("Codex-like").tag(AgentBehavior.codexLike)
                Text("Claude-like").tag(AgentBehavior.claudeLike)
            }
            .pickerStyle(.radioGroup)

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                Button("Add") {
                    onAdd(AgentSelection(
                        id: "custom:\(UUID().uuidString)",
                        displayName: trimmedName,
                        behavior: behavior
                    ))
                }
                .keyboardShortcut(.defaultAction)
                .disabled(trimmedName.isEmpty)
            }
        }
        .padding()
        .frame(width: 360)
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
