import SwiftUI
import Foundation
import AppKit
import OrbitaCore

struct CapabilityInspectorView: View {
    let capability: Capability?
    let onClose: () -> Void
    let onEnable: (Capability) -> Void
    let onDisable: (Capability) -> Void
    let onDelete: (Capability) -> Void
    let onNativePluginChanged: () -> Void

    @State private var runningNativeActionID: String?
    @State private var nativeActionResult: CommandRunResult?

    var body: some View {
        Group {
            if let capability {
                inspectorContent(for: capability)
            } else {
                EmptyInspectorSelectionView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(OrbitaTheme.canvas)
    }

    private func inspectorContent(for capability: Capability) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 12) {
                        if canApplyActions(to: capability) {
                            InspectorActionStrip(
                                capability: capability,
                                onEnable: onEnable,
                                onDisable: onDisable,
                                onDelete: onDelete,
                                onClose: onClose
                            )
                        } else {
                            HStack {
                                Spacer(minLength: 0)
                                InspectorHeaderButton(
                                    systemImage: "sidebar.right",
                                    tint: .secondary,
                                    help: "Hide inspector",
                                    action: onClose
                                )
                            }
                        }

                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: CapabilityVisuals.iconName(for: capability.type))
                                .font(.system(size: 20, weight: .medium))
                                .frame(width: 28, height: 28)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(capability.name)
                                    .font(.title3.weight(.semibold))
                                    .lineLimit(2)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text(capability.type.displayName)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(.top, 16)

                    VStack(alignment: .leading, spacing: 16) {
                        InspectorSection {
                            InspectorField("Scope", value: capability.scope.rawValue)
                            InspectorField("Status", value: CapabilityVisuals.statusLabel(for: capability))
                            InspectorField("Access", value: CapabilityDisplayText.accessSummary(for: capability.risks))
                            InspectorPathField("Source", path: sourcePath(for: capability))
                            if let childCount = capability.metadata["childCount"] {
                                InspectorField("Children", value: childCount)
                            }
                        }

                        StatusReasonSection(capability: capability)
                    }

                    if !nativePluginActions(for: capability).isEmpty {
                        NativePluginActionSection(
                            capability: capability,
                            actions: nativePluginActions(for: capability),
                            runningActionID: runningNativeActionID,
                            result: nativeActionResult,
                            onRun: { action in
                                runNativePluginAction(action, capability: capability)
                            }
                        )
                    }

                    if let markdownPath = markdownPreviewPath(for: capability) {
                        MarkdownPreviewCard(sourcePath: markdownPath)
                    }
                }
                .padding(.top, 24)
                .padding(.leading, 24)
                .padding(.trailing, 22)
                .padding(.bottom, 18)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func sourcePath(for capability: Capability) -> String {
        if !capability.source.path.isEmpty {
            return capability.source.path
        }
        if let path = capability.metadata["sourcePath"], !path.isEmpty {
            return path
        }
        return "-"
    }

    private func canApplyActions(to capability: Capability) -> Bool {
        if capability.source.kind == "virtual-plugin" {
            return true
        }
        return !["codex", "claude-code"].contains(capability.metadata["manager"] ?? "")
    }

    private func markdownPreviewPath(for capability: Capability) -> String? {
        let path = sourcePath(for: capability)
        guard path != "-", path.lowercased().hasSuffix(".md") else {
            return nil
        }
        var isDirectory = ObjCBool(false)
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
              !isDirectory.boolValue else {
            return nil
        }
        return path
    }

    private func nativePluginActions(for capability: Capability) -> [NativePluginAction] {
        NativePluginAction.actions(for: capability)
    }

    private func runNativePluginAction(_ action: NativePluginAction, capability: Capability) {
        guard runningNativeActionID == nil else { return }
        runningNativeActionID = action.id
        nativeActionResult = nil

        Task.detached {
            let result: CommandRunResult
            if action.manager == "codex", action.kind == .enable || action.kind == .disable {
                result = CodexPluginConfigUpdater.setEnabled(
                    action.kind == .enable,
                    selector: capability.metadata["pluginSelector"] ?? capability.name,
                    configPath: capability.metadata["configPath"] ?? "\(FileManager.default.homeDirectoryForCurrentUser.path)/.codex/config.toml"
                )
            } else {
                result = ShellCommandRunner.run(action.command, workingDirectory: FileManager.default.currentDirectoryPath)
            }
            await MainActor.run {
                nativeActionResult = result
                runningNativeActionID = nil
                if result.exitCode == 0 {
                    onNativePluginChanged()
                }
            }
        }
    }
}

private struct EmptyInspectorSelectionView: View {
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "sidebar.right")
                .font(.system(size: 38, weight: .regular))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)

            VStack(spacing: 6) {
                Text("No Selection")
                    .font(.title2.weight(.semibold))
                Text("Select a capability to inspect source, scope, access, and loading path.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
            }
        }
        .padding(.horizontal, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}

private struct InspectorActionStrip: View {
    let capability: Capability
    let onEnable: (Capability) -> Void
    let onDisable: (Capability) -> Void
    let onDelete: (Capability) -> Void
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            if capability.source.kind != "virtual-plugin", capability.statuses.contains(.disabled) {
                InspectorToolbarButton(
                    systemImage: "checkmark.circle",
                    tint: .green,
                    title: "Enable",
                    help: "Enable"
                ) {
                    onEnable(capability)
                }
            } else if capability.source.kind != "virtual-plugin" {
                InspectorToolbarButton(
                    systemImage: "minus.circle",
                    tint: .secondary,
                    title: "Disable",
                    help: "Disable"
                ) {
                    onDisable(capability)
                }
            }

            Spacer(minLength: 10)

            InspectorToolbarButton(
                systemImage: "trash",
                tint: .red,
                help: "Delete",
                isDestructive: true
            ) {
                onDelete(capability)
            }

            InspectorToolbarButton(
                systemImage: "sidebar.right",
                tint: .secondary,
                help: "Hide inspector"
            ) {
                onClose()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct InspectorToolbarButton: View {
    let systemImage: String
    let tint: Color
    var title: String? = nil
    let help: String
    var isDestructive = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 15)
                if let title {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.9)
                        .fixedSize(horizontal: true, vertical: false)
                }
            }
                .foregroundStyle(tint)
                .frame(width: title == nil ? 44 : 118, height: 34)
                .background(backgroundColor, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(borderColor)
                }
        }
        .buttonStyle(.plain)
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .help(help)
        .accessibilityLabel(help)
    }

    private var backgroundColor: Color {
        if isDestructive {
            return Color.red.opacity(0.12)
        }
        if tint == .green {
            return Color.green.opacity(0.1)
        }
        return OrbitaTheme.controlFill
    }

    private var borderColor: Color {
        if isDestructive {
            return Color.red.opacity(0.2)
        }
        if tint == .green {
            return Color.green.opacity(0.18)
        }
        return OrbitaTheme.border
    }
}

private struct InspectorHeaderButton: View {
    let systemImage: String
    let tint: Color
    let help: String
    var isDestructive = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 34, height: 30)
                .background(backgroundColor, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(tint.opacity(isDestructive ? 0.2 : 0.12))
                }
        }
        .buttonStyle(.plain)
        .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .help(help)
        .accessibilityLabel(help)
    }

    private var backgroundColor: Color {
        isDestructive ? Color.red.opacity(0.11) : OrbitaTheme.controlFill
    }
}

private struct NativePluginActionSection: View {
    let capability: Capability
    let actions: [NativePluginAction]
    let runningActionID: String?
    let result: CommandRunResult?
    let onRun: (NativePluginAction) -> Void

    var body: some View {
        InspectorSection {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("Native Plugin", systemImage: "shippingbox")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    Text(capability.metadata["manager"] ?? "plugin")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }

                if let note = capability.metadata["lifecycleNote"] {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 8) {
                    ForEach(actions) { action in
                        Button {
                            onRun(action)
                        } label: {
                            Label(runningActionID == action.id ? "Running" : action.title, systemImage: runningActionID == action.id ? "hourglass" : action.systemImage)
                        }
                        .buttonStyle(.bordered)
                        .disabled(runningActionID != nil)
                        .help(action.command)
                    }
                }

                if let result {
                    Divider()
                    Text(result.output.isEmpty ? "(no output)" : result.output)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                        .lineLimit(8)
                }
            }
        }
    }
}

private struct NativePluginAction: Identifiable {
    enum Kind {
        case enable
        case disable
        case check
        case update
    }

    let id: String
    let title: String
    let systemImage: String
    let command: String
    let manager: String
    let kind: Kind

    static func actions(for capability: Capability) -> [NativePluginAction] {
        guard let manager = capability.metadata["manager"] else { return [] }
        var actions: [NativePluginAction] = []
        if let command = capability.metadata["checkCommand"] {
            actions.append(NativePluginAction(id: "check", title: "Check", systemImage: "magnifyingglass", command: command, manager: manager, kind: .check))
        }
        if capability.statuses.contains(.disabled), let command = capability.metadata["enableCommand"] {
            actions.append(NativePluginAction(id: "enable", title: "Enable", systemImage: "checkmark.circle", command: command, manager: manager, kind: .enable))
        }
        if capability.statuses.contains(.enabled), let command = capability.metadata["disableCommand"] {
            actions.append(NativePluginAction(id: "disable", title: "Disable", systemImage: "minus.circle", command: command, manager: manager, kind: .disable))
        }
        if let command = capability.metadata["updateCommand"] {
            actions.append(NativePluginAction(id: "update", title: "Update", systemImage: "arrow.down.circle", command: command, manager: manager, kind: .update))
        }
        return actions
    }
}

private enum CodexPluginConfigUpdater {
    static func setEnabled(_ enabled: Bool, selector: String, configPath: String) -> CommandRunResult {
        let url = URL(fileURLWithPath: configPath)
        let section = "[plugins.\"\(selector)\"]"
        let enabledLine = "enabled = \(enabled ? "true" : "false")"
        do {
            let original = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            let lines = original.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            var output: [String] = []
            var inTargetSection = false
            var foundSection = false
            var wroteEnabled = false

            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if inTargetSection, trimmed.hasPrefix("[") {
                    if !wroteEnabled {
                        output.append(enabledLine)
                        wroteEnabled = true
                    }
                    inTargetSection = false
                }

                if trimmed == section {
                    inTargetSection = true
                    foundSection = true
                    wroteEnabled = false
                    output.append(line)
                    continue
                }

                if inTargetSection, trimmed.hasPrefix("enabled") {
                    output.append(enabledLine)
                    wroteEnabled = true
                    continue
                }

                output.append(line)
            }

            if inTargetSection, !wroteEnabled {
                output.append(enabledLine)
            }

            if !foundSection {
                if !output.isEmpty, output.last?.isEmpty == false {
                    output.append("")
                }
                output.append(section)
                output.append(enabledLine)
            }

            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try output.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
            return CommandRunResult(command: "Codex config update", exitCode: 0, output: "\(selector) \(enabled ? "enabled" : "disabled") in \(configPath)")
        } catch {
            return CommandRunResult(command: "Codex config update", exitCode: 1, output: error.localizedDescription)
        }
    }
}

private struct StatusReasonSection: View {
    let capability: Capability

    var body: some View {
        InspectorSection {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(CapabilityVisuals.statusColor(for: capability))
                        .frame(width: 8, height: 8)
                    Text("Status")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    Text(dotLabel)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(reasons) { reason in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: reason.systemImage)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(reason.color)
                                .frame(width: 14, alignment: .center)
                                .padding(.top, 2)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(reason.title)
                                    .font(.caption.weight(.semibold))
                                Text(reason.detail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }
        }
    }

    private var dotLabel: String {
        if capability.statuses.contains(.broken) {
            return "Broken"
        }
        if capability.statuses.contains(.drifted) || capability.statuses.contains(.shadowed) {
            return "Needs attention"
        }
        if capability.statuses.contains(.risky) {
            return "Review needed"
        }
        return "Ready"
    }

    private var reasons: [StatusReason] {
        var items: [StatusReason] = []

        if capability.statuses.contains(.broken) {
            items.append(StatusReason(
                title: "Broken source",
                detail: "Orbita found a record for this capability, but the source path is missing, unreadable, or could not be resolved.",
                systemImage: "xmark.octagon",
                color: .red
            ))
        }

        if capability.statuses.contains(.shadowed) {
            items.append(StatusReason(
                title: "Overridden by a higher-priority scope",
                detail: "Another capability with the same type and name exists in a higher-priority scope. Priority is project, user, installed, then environment.",
                systemImage: "square.on.square",
                color: .orange
            ))
        }

        if capability.statuses.contains(.drifted) {
            items.append(StatusReason(
                title: "Drift detected",
                detail: driftDetail,
                systemImage: "arrow.triangle.branch",
                color: .orange
            ))
        }

        if capability.statuses.contains(.risky) {
            items.append(StatusReason(
                title: "Access needs review",
                detail: "This capability requests \(CapabilityDisplayText.accessSummary(for: capability.risks)).",
                systemImage: "exclamationmark.triangle",
                color: .yellow
            ))
        }

        if capability.statuses.contains(.disabled) {
            items.append(StatusReason(
                title: "Disabled",
                detail: disabledDetail,
                systemImage: "minus.circle",
                color: .secondary
            ))
        }

        if capability.statuses.contains(.duplicate) {
            items.append(StatusReason(
                title: "Duplicate name",
                detail: "Orbita found more than one capability with this type and name.",
                systemImage: "doc.on.doc",
                color: .secondary
            ))
        }

        if items.isEmpty {
            items.append(StatusReason(
                title: "Ready",
                detail: "Orbita found this capability and did not detect broken links, drift, overrides, or review flags.",
                systemImage: "checkmark.circle",
                color: .green
            ))
        }

        return items
    }

    private var driftDetail: String {
        if let reason = capability.metadata["driftReason"], !reason.isEmpty {
            return reason
        }
        return "A capability with the same type and name exists in multiple places, and the content hash is different."
    }

    private var disabledDetail: String {
        if let manager = capability.metadata["manager"], !manager.isEmpty {
            return "\(manager) marks this plugin as disabled."
        }
        return "The .agents manifest marks this capability as disabled."
    }
}

private struct StatusReason: Identifiable {
    var id: String { title }
    let title: String
    let detail: String
    let systemImage: String
    let color: Color
}

private struct InspectorSection<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .orbitaCard(cornerRadius: 16, shadowRadius: 5, shadowY: 2)
    }
}

private struct InspectorField: View {
    let title: String
    let value: String

    init(_ title: String, value: String) {
        self.title = title
        self.value = value
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 58, alignment: .leading)
            Text(value.isEmpty ? "-" : value)
                .font(.subheadline)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}

private struct InspectorPathField: View {
    let title: String
    let path: String

    init(_ title: String, path: String) {
        self.title = title
        self.path = path
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 58, alignment: .leading)
                .padding(.top, 1)

            Text(path.isEmpty ? "-" : path)
                .font(.caption.monospaced())
                .textSelection(.enabled)
                .lineLimit(2)
                .truncationMode(.middle)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            SourceFolderButton(path: path)
        }
    }
}

private struct SourceFolderButton: View {
    let path: String

    var body: some View {
        Button {
            openInFinder()
        } label: {
            Image(systemName: "folder")
                .font(.system(size: 12, weight: .medium))
                .frame(width: 24, height: 22)
        }
        .buttonStyle(.plain)
        .orbitaControlSurface(cornerRadius: 8)
        .help("Open source folder")
        .disabled(!canOpen)
        .opacity(canOpen ? 1 : 0.45)
    }

    private var canOpen: Bool {
        resolvedTargetURL() != nil
    }

    private func openInFinder() {
        guard let targetURL = resolvedTargetURL() else {
            return
        }
        var isDirectory = ObjCBool(false)
        let exists = FileManager.default.fileExists(atPath: targetURL.path, isDirectory: &isDirectory)
        if exists, isDirectory.boolValue {
            NSWorkspace.shared.open(targetURL)
        } else {
            NSWorkspace.shared.activateFileViewerSelecting([targetURL])
        }
    }

    private func resolvedTargetURL() -> URL? {
        guard path != "-", !path.isEmpty else {
            return nil
        }

        let url = URL(fileURLWithPath: path).standardizedFileURL
        if FileManager.default.fileExists(atPath: url.path) {
            return url
        }

        let parent = url.deletingLastPathComponent()
        guard FileManager.default.fileExists(atPath: parent.path) else {
            return nil
        }
        return parent
    }
}

private struct MarkdownPreviewCard: View {
    let sourcePath: String

    @State private var previewState: MarkdownPreviewState = .loading

    var body: some View {
        InspectorSection {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("Markdown Preview", systemImage: "doc.richtext")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                }

                switch previewState {
                case .loading:
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Loading preview")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                case .unavailable:
                    Text("No markdown preview available.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                case let .rendered(markdown):
                    Text(markdown)
                        .font(.callout)
                        .lineSpacing(3)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                case let .raw(text):
                    Text(text)
                        .font(.callout.monospaced())
                        .lineSpacing(3)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                case let .failed(message):
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .task(id: sourcePath) {
            previewState = .loading
            previewState = MarkdownPreviewState.load(path: sourcePath)
        }
    }
}

private enum MarkdownPreviewState {
    case loading
    case unavailable
    case rendered(AttributedString)
    case raw(String)
    case failed(String)

    static func load(path: String) -> MarkdownPreviewState {
        var isDirectory = ObjCBool(false)
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
              !isDirectory.boolValue else {
            return .unavailable
        }

        do {
            let rawText = try String(contentsOfFile: path, encoding: .utf8)
            let markdown = trimmedMarkdown(rawText)
            guard !markdown.isEmpty else {
                return .unavailable
            }

            do {
                let rendered = try AttributedString(
                    markdown: markdown,
                    options: AttributedString.MarkdownParsingOptions(
                        interpretedSyntax: .full,
                        failurePolicy: .returnPartiallyParsedIfPossible
                    )
                )
                return .rendered(rendered)
            } catch {
                return .raw(markdown)
            }
        } catch {
            return .failed("Unable to read markdown: \(error.localizedDescription)")
        }
    }

    private static func trimmedMarkdown(_ text: String) -> String {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        let body = stripFrontmatter(from: normalized)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let maxLength = 80_000
        guard body.count > maxLength else {
            return body
        }
        let endIndex = body.index(body.startIndex, offsetBy: maxLength)
        return String(body[..<endIndex]) + "\n\nPreview truncated."
    }

    private static func stripFrontmatter(from text: String) -> String {
        guard text.hasPrefix("---\n") else {
            return text
        }
        let searchStart = text.index(text.startIndex, offsetBy: 4)
        guard let closingRange = text.range(of: "\n---\n", range: searchStart..<text.endIndex) else {
            return text
        }
        return String(text[closingRange.upperBound...])
    }
}
