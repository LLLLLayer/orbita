import SwiftUI
import Foundation
import AppKit
import OrbitaCore

struct CapabilityInspectorView: View {
    @ObservedObject private var localization = LocalizationManager.shared
    let capability: Capability?
    let selectedAgent: AgentSelection?
    let onClose: () -> Void
    let onEnable: (Capability) -> Void
    let onDisable: (Capability) -> Void
    let onDelete: (Capability) -> Void
    let onOpenMarkdownPreview: (MarkdownPreviewDocument) -> Void
    let onBeginNativeMutation: (CapabilityOptimisticMutation, Capability) -> CapabilityOptimisticMutationToken
    let onNativeMutationSucceeded: (CapabilityOptimisticMutation, Capability, CapabilityOptimisticMutationToken) -> Void
    let onNativeMutationFailed: (Capability, CapabilityOptimisticMutationToken, String) -> Void
    let onNativePluginChanged: () -> Void

    @State private var runningNativeActionID: String?
    @State private var nativeActionResult: NativePluginActionResult?
    @State private var pendingNativeDeleteAction: NativePluginDeleteRequest?
    @AppStorage("nativePluginVersionChecksJSON") private var nativePluginVersionChecksJSON = "{}"
    @State private var autoCheckInFlight: Set<String> = []

    /// How long an automatic update check is trusted before it re-runs when the
    /// plugin is selected again. Keeps selection cheap — one background command
    /// per plugin, then cached — instead of re-querying the marketplace on
    /// every open.
    private static let autoUpdateCheckTTL: TimeInterval = 6 * 60 * 60

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
        .onChange(of: capability?.id) { _, _ in
            runningNativeActionID = nil
            nativeActionResult = nil
        }
        .task(id: capability?.id) {
            if let capability {
                await autoCheckForUpdate(capability)
            }
        }
    }

    private func inspectorContent(for capability: Capability) -> some View {
        let nativeActions = nativePluginActions(for: capability)
        let nativePrimaryAction = nativeActions.first(where: \.isEnablementToggle)
        let nativeDeleteAction = nativeActions.first(where: { $0.kind == .delete })
        let nativeSecondaryActions = nativeActions.filter { !$0.isEnablementToggle && $0.kind != .delete }

        return VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 12) {
                        InspectorActionStrip(
                            capability: capability,
                            nativePrimaryAction: nativePrimaryAction,
                            nativeDeleteAction: nativeDeleteAction,
                            runningNativeActionID: runningNativeActionID,
                            allowsFallbackEnablement: allowsFallbackEnablement(for: capability),
                            allowsFallbackDelete: allowsFallbackDelete(for: capability, nativeDeleteAction: nativeDeleteAction),
                            onEnable: onEnable,
                            onDisable: onDisable,
                            onDelete: onDelete,
                            onClose: onClose,
                            onNativeAction: { action in
                                runNativePluginAction(action, capability: capability)
                            },
                            onNativeDelete: { action in
                                pendingNativeDeleteAction = NativePluginDeleteRequest(action: action, capability: capability)
                            }
                        )

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

                    VStack(alignment: .leading, spacing: 16) {
                        InspectorSection {
                            InspectorField(L("inspector.field.scope"), value: localizedCapabilityScope(capability.scope.rawValue))
                            InspectorField(L("inspector.field.status"), value: CapabilityVisuals.statusLabel(for: capability))
                            if let installedVersion = capability.metadata["installedVersion"],
                               !installedVersion.isEmpty {
                                InspectorField(L("inspector.field.version"), value: installedVersion)
                            }
                            InspectorField(L("inspector.field.access"), value: CapabilityDisplayText.accessSummary(for: capability.risks))
                            InspectorPathField(L("inspector.field.source"), path: sourcePath(for: capability))
                            if let canonicalPath = canonicalPathToDisplay(for: capability) {
                                InspectorPathField(L("inspector.field.canon"), path: canonicalPath)
                            }
                            if let installedAgents = capability.metadata["skillsInstalledAgents"], !installedAgents.isEmpty {
                                InspectorField(L("inspector.field.agents"), value: installedAgents)
                            }
                            if let lockSource = capability.metadata["skillsLockSource"], !lockSource.isEmpty {
                                InspectorField(L("inspector.field.lock"), value: lockSource)
                            } else if let lockStatus = capability.metadata["skillsLockStatus"], !lockStatus.isEmpty {
                                InspectorField(L("inspector.field.lock"), value: lockStatus)
                            }
                            if let lockRef = capability.metadata["skillsLockRef"], !lockRef.isEmpty {
                                InspectorField(L("inspector.field.ref"), value: lockRef)
                            }
                            if let skillPath = capability.metadata["skillsLockSkillPath"], !skillPath.isEmpty {
                                InspectorField(L("inspector.field.skill"), value: skillPath)
                            }
                            if let hash = capability.metadata["skillsLockHash"], !hash.isEmpty {
                                InspectorField(L("inspector.field.hash"), value: shortHash(hash))
                            }
                            if let childCount = capability.metadata["childCount"] {
                                InspectorField(L("inspector.field.children"), value: childCount)
                            }
                        }

                        StatusReasonSection(capability: capability)

                        DriftLocationsSection(capability: capability)
                    }

                    if !nativeSecondaryActions.isEmpty {
                        NativePluginActionSection(
                            capability: capability,
                            actions: nativeSecondaryActions,
                            runningActionID: runningNativeActionID,
                            result: nativeActionResult,
                            versionCheck: nativePluginVersionCheck(for: capability),
                            onRun: { action in
                                runNativePluginAction(action, capability: capability)
                            }
                        )
                    }

                    if let markdownPath = markdownPreviewPath(for: capability) {
                        MarkdownPreviewCard(sourcePath: markdownPath, onOpenPreview: onOpenMarkdownPreview)
                    }
                }
                .padding(.top, 20)
                .padding(.leading, 24)
                .padding(.trailing, 22)
                .padding(.bottom, 18)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .sheet(item: $pendingNativeDeleteAction) { request in
            NativePluginDeleteConfirmationSheet(
                capability: request.capability,
                command: request.action.command,
                onDelete: {
                    runNativePluginAction(request.action, capability: request.capability)
                    pendingNativeDeleteAction = nil
                },
                onCancel: {
                    pendingNativeDeleteAction = nil
                }
            )
        }
    }

    private struct NativePluginDeleteConfirmationSheet: View {
        @ObservedObject private var localization = LocalizationManager.shared
        let capability: Capability
        let command: String
        let onDelete: () -> Void
        let onCancel: () -> Void

        var body: some View {
            VStack(alignment: .leading, spacing: 18) {
                header
                impactPanel
                commandPanel

                HStack(spacing: 10) {
                    NativeDeleteSheetButton(
                        title: L("inspector.delete.cancel"),
                        systemImage: "xmark",
                        action: onCancel
                    )

                    Spacer(minLength: 0)

                    NativeDeleteSheetButton(
                        title: L("inspector.action.delete"),
                        systemImage: "trash",
                        isDestructive: true,
                        action: onDelete
                    )
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(22)
            .frame(width: 560)
            .background(OrbitaTheme.canvas)
            .presentationBackground(OrbitaTheme.canvas)
        }

        private var header: some View {
            HStack(alignment: .center, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.red.opacity(0.11))
                        .overlay {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(Color.red.opacity(0.22))
                        }

                    Image(systemName: "trash")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.red)
                }
                .frame(width: 42, height: 42)

                VStack(alignment: .leading, spacing: 2) {
                    Text(String(format: L("inspector.delete.title"), capability.name))
                        .font(.title2.weight(.semibold))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(L("inspector.delete.subtitle"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }
        }

        private var impactPanel: some View {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.red)
                    .frame(width: 44, height: 44)
                    .background(Color.red.opacity(0.11), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Color.red.opacity(0.22))
                    }

                VStack(alignment: .leading, spacing: 5) {
                    Text(L("inspector.delete.permanent.title"))
                        .font(.headline.weight(.semibold))
                    Text(L("inspector.delete.permanent.detail"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }
            .padding(16)
            .orbitaCard(cornerRadius: 18, shadowRadius: 8, shadowY: 4)
        }

        private var commandPanel: some View {
            VStack(alignment: .leading, spacing: 8) {
                Label(L("inspector.command.label"), systemImage: "terminal")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Text(command)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(3)
                    .truncationMode(.middle)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(OrbitaTheme.controlFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(OrbitaTheme.border)
                    }
            }
        }
    }

    private struct NativeDeleteSheetButton: View {
        let title: String
        let systemImage: String
        var isDestructive = false
        let action: () -> Void

        var body: some View {
            Button(action: action) {
                Label(title, systemImage: systemImage)
                    .font(.subheadline.weight(.semibold))
                    .labelStyle(.titleAndIcon)
                    .padding(.horizontal, 12)
                    .frame(height: 34)
                    .foregroundStyle(isDestructive ? .red : .primary)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(backgroundColor, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(isDestructive ? Color.red.opacity(0.24) : OrbitaTheme.border)
            }
        }

        private var backgroundColor: Color {
            isDestructive ? Color.red.opacity(0.11) : OrbitaTheme.controlFill
        }
    }

    private func sourcePath(for capability: Capability) -> String {
        if let selectedAgentPath = selectedAgentSourcePath(for: capability) {
            return selectedAgentPath
        }
        if let path = capability.metadata["sourcePath"],
           !path.isEmpty,
           !isInternalOrbitaIndexPath(path) {
            return path
        }
        if isInternalOrbitaIndexPath(capability.source.path) {
            return "-"
        }
        if !capability.source.path.isEmpty {
            return capability.source.path
        }
        return "-"
    }

    private func selectedAgentSourcePath(for capability: Capability) -> String? {
        guard let agentID = selectedAgent?.skillsInstallAgentID,
              let targetPath = skillsInstallTargetPath(for: agentID, capability: capability) else {
            return nil
        }
        return displayableSkillPath(targetPath)
    }

    private func skillsInstallTargetPath(for agentID: String, capability: Capability) -> String? {
        guard let value = capability.metadata["skillsInstallTargets"] else {
            return nil
        }
        let prefix = "\(agentID)="
        return value
            .split(separator: "\n", omittingEmptySubsequences: true)
            .compactMap { line -> String? in
                guard line.hasPrefix(prefix),
                      let separator = line.firstIndex(of: ":") else {
                    return nil
                }
                let pathStart = line.index(after: separator)
                let path = String(line[pathStart...])
                return path.isEmpty ? nil : path
            }
            .first
    }

    private func displayableSkillPath(_ path: String) -> String {
        let url = URL(fileURLWithPath: path)
        var isDirectory = ObjCBool(false)
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
           isDirectory.boolValue {
            let skillFile = url.appendingPathComponent("SKILL.md")
            if FileManager.default.fileExists(atPath: skillFile.path) {
                return skillFile.path
            }
        }
        return path
    }

    private func isInternalOrbitaIndexPath(_ path: String) -> Bool {
        path.contains("/.orbita/this-mac/")
    }

    private func canonicalPathToDisplay(for capability: Capability) -> String? {
        guard let canonicalPath = capability.metadata["skillsCanonicalPath"],
              !canonicalPath.isEmpty else {
            return nil
        }
        let sourcePath = sourcePath(for: capability)
        guard !sourcePathRepresentsCanonicalSkill(sourcePath, canonicalPath: canonicalPath) else {
            return nil
        }
        return canonicalPath
    }

    private func sourcePathRepresentsCanonicalSkill(_ sourcePath: String, canonicalPath: String) -> Bool {
        guard sourcePath != "-", !sourcePath.isEmpty else {
            return false
        }

        let canonicalCandidates = normalizedPathCandidates(for: canonicalPath)
        let sourceURL = URL(fileURLWithPath: sourcePath).standardizedFileURL
        let sourceCandidates = normalizedPathCandidates(for: sourcePath)

        if !canonicalCandidates.isDisjoint(with: sourceCandidates) {
            return true
        }

        guard sourceURL.lastPathComponent.caseInsensitiveCompare("SKILL.md") == .orderedSame else {
            return false
        }
        let sourceDirectoryCandidates = normalizedPathCandidates(for: sourceURL.deletingLastPathComponent().path)
        return !canonicalCandidates.isDisjoint(with: sourceDirectoryCandidates)
    }

    private func normalizedPathCandidates(for path: String) -> Set<String> {
        let url = URL(fileURLWithPath: path).standardizedFileURL
        return [
            url.path,
            url.resolvingSymlinksInPath().path
        ]
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
        var actions = NativePluginAction.actions(for: capability)
        if selectedAgent?.skillsInstallAgentID == "codex",
           let action = NativePluginAction.codexSkillConfigAction(for: capability) {
            actions.insert(action, at: 0)
        }
        if selectedAgent?.skillsInstallAgentID == "claude-code" {
            if let action = NativePluginAction.claudeSkillOverrideAction(for: capability) {
                actions.insert(action, at: 0)
            }
            if let action = NativePluginAction.claudeSkillDeleteAction(for: capability) {
                actions.append(action)
            }
            if let action = NativePluginAction.claudeMCPConfigAction(for: capability) {
                actions.insert(action, at: 0)
            }
            if let action = NativePluginAction.claudeMCPDeleteAction(for: capability) {
                actions.append(action)
            }
            if let action = NativePluginAction.claudeHookDeleteAction(for: capability) {
                actions.append(action)
            }
        }
        return actions
    }

    private func allowsFallbackEnablement(for capability: Capability) -> Bool {
        guard selectedAgent?.skillsInstallAgentID == "claude-code" else {
            return true
        }
        if capability.type == .mcpServer, capability.source.kind == "mcp-config" {
            return false
        }
        switch capability.source.kind {
        case "claude-plugin",
             "claude-plugin-skill",
             "claude-plugin-command",
             "claude-plugin-hook",
             "claude-skill",
             "claude-command",
             "claude-settings",
             "claude-settings-hook":
            return false
        default:
            return true
        }
    }

    private func allowsFallbackDelete(for capability: Capability, nativeDeleteAction: NativePluginAction?) -> Bool {
        guard selectedAgent?.skillsInstallAgentID == "claude-code" else {
            return true
        }
        if nativeDeleteAction != nil {
            return false
        }
        if capability.type == .mcpServer, capability.source.kind == "mcp-config" {
            return false
        }
        switch capability.source.kind {
        case "claude-plugin",
             "claude-plugin-skill",
             "claude-plugin-command",
             "claude-plugin-hook",
             "claude-skill",
             "claude-settings",
             "claude-settings-hook":
            return false
        default:
            return true
        }
    }

    private func nativePluginVersionCheck(for capability: Capability) -> NativePluginVersionCheck? {
        nativePluginVersionChecks[capability.id]
    }

    private var nativePluginVersionChecks: [String: NativePluginVersionCheck] {
        guard let data = nativePluginVersionChecksJSON.data(using: .utf8),
              let checks = try? JSONDecoder().decode([String: NativePluginVersionCheck].self, from: data)
        else {
            return [:]
        }
        return checks
    }

    private func saveNativePluginVersionCheck(_ check: NativePluginVersionCheck, for capability: Capability) {
        var checks = nativePluginVersionChecks
        checks[capability.id] = check
        saveNativePluginVersionChecks(checks)
    }

    private func removeNativePluginVersionCheck(for capability: Capability) {
        var checks = nativePluginVersionChecks
        checks.removeValue(forKey: capability.id)
        saveNativePluginVersionChecks(checks)
    }

    private func saveNativePluginVersionChecks(_ checks: [String: NativePluginVersionCheck]) {
        if let data = try? JSONEncoder().encode(checks),
           let json = String(data: data, encoding: .utf8) {
            nativePluginVersionChecksJSON = json
        }
    }

    private func shortHash(_ value: String) -> String {
        value.count > 16 ? String(value.prefix(16)) : value
    }

    /// Auto-check for a newer version when a native plugin is selected. Runs the
    /// plugin's `checkCommand` once in the background (cached for
    /// `autoUpdateCheckTTL`) and stores the parsed result, so the "New version
    /// available" reminder appears without a manual Check button. Applying the
    /// update stays user-driven via the Update action.
    private func autoCheckForUpdate(_ capability: Capability) async {
        guard let manager = capability.metadata["manager"],
              ["codex", "claude-code"].contains(manager),
              let command = capability.metadata["checkCommand"],
              !command.isEmpty else {
            return
        }
        if let existing = nativePluginVersionCheck(for: capability),
           Date().timeIntervalSince(existing.checkedAt) < Self.autoUpdateCheckTTL {
            return
        }
        guard !autoCheckInFlight.contains(capability.id) else { return }
        autoCheckInFlight.insert(capability.id)
        defer { autoCheckInFlight.remove(capability.id) }

        let action = NativePluginAction(
            id: "auto-check",
            title: "Check",
            systemImage: "magnifyingglass",
            command: command,
            manager: manager,
            kind: .check
        )
        let workingDirectory = action.workingDirectory(for: capability)
            ?? FileManager.default.currentDirectoryPath
        let result = await Task.detached(priority: .utility) {
            ShellCommandRunner.run(command, workingDirectory: workingDirectory)
        }.value

        guard self.capability?.id == capability.id else { return }
        guard result.exitCode == 0,
              let versionCheck = NativePluginResultSummary(capability: capability, action: action, result: result).versionCheck else {
            return
        }
        saveNativePluginVersionCheck(versionCheck, for: capability)
    }

    private func runNativePluginAction(_ action: NativePluginAction, capability: Capability) {
        guard runningNativeActionID == nil else { return }
        runningNativeActionID = action.id
        nativeActionResult = nil
        let optimisticMutation = action.optimisticMutation
        let optimisticToken = optimisticMutation.map { onBeginNativeMutation($0, capability) }

        Task.detached {
            let result: CommandRunResult
            let codexEnableUsesConfig = action.kind == .enable
                && (capability.metadata["enableMode"] == "config" || action.command.hasPrefix("Set [plugins."))
            if action.manager == NativePluginAction.codexSkillManager {
                result = CodexSkillConfigUpdater.setEnabled(
                    action.kind == .enable,
                    skillPath: capability.metadata["codexSkillConfigPath"] ?? capability.source.path,
                    configPath: capability.metadata["codexConfigPath"] ?? "\(FileManager.default.homeDirectoryForCurrentUser.path)/.codex/config.toml"
                )
            } else if action.manager == NativePluginAction.claudeSkillManager {
                if action.kind == .delete {
                    result = ClaudeSkillLifecycleUpdater.deleteSkill(
                        at: capability.metadata["claudeSkillDeletePath"] ?? URL(fileURLWithPath: capability.source.path).deletingLastPathComponent().path
                    )
                } else {
                    result = ClaudeSkillLifecycleUpdater.setEnabled(
                        action.kind == .enable,
                        skillName: capability.metadata["claudeSkillName"] ?? capability.name,
                        settingsPath: capability.metadata["claudeSettingsPath"] ?? "\(FileManager.default.homeDirectoryForCurrentUser.path)/.claude/settings.json"
                    )
                }
            } else if action.manager == NativePluginAction.claudeMCPManager {
                if action.kind == .delete {
                    result = ClaudeMCPJsonLifecycleUpdater.deleteServer(
                        capability.metadata["mcpServerName"] ?? capability.name,
                        configPath: capability.metadata["mcpConfigPath"] ?? capability.source.path
                    )
                } else {
                    result = ClaudeMCPJsonLifecycleUpdater.setEnabled(
                        action.kind == .enable,
                        serverName: capability.metadata["mcpServerName"] ?? capability.name,
                        settingsPath: capability.metadata["claudeMCPSettingsPath"] ?? URL(fileURLWithPath: capability.source.path).deletingLastPathComponent().appendingPathComponent(".claude/settings.json").path
                    )
                }
            } else if action.manager == NativePluginAction.claudeHookManager {
                result = ClaudeHookLifecycleUpdater.deleteHook(
                    event: capability.metadata["event"] ?? "",
                    entryIndex: Int(capability.metadata["entryIndex"] ?? "") ?? 0,
                    hookIndex: Int(capability.metadata["hookIndex"] ?? "") ?? 0,
                    settingsPath: capability.metadata["claudeHookSettingsPath"] ?? capability.source.path
                )
            } else if action.manager == "codex", action.kind == .disable || codexEnableUsesConfig {
                result = CodexPluginConfigUpdater.setEnabled(
                    action.kind == .enable,
                    selector: capability.metadata["pluginSelector"] ?? capability.name,
                    configPath: capability.metadata["configPath"] ?? "\(FileManager.default.homeDirectoryForCurrentUser.path)/.codex/config.toml"
                )
            } else {
                result = ShellCommandRunner.run(
                    action.command,
                    workingDirectory: action.workingDirectory(for: capability) ?? FileManager.default.currentDirectoryPath
                )
            }
            await MainActor.run {
                nativeActionResult = NativePluginActionResult(action: action, result: result)
                let summary = NativePluginResultSummary(capability: capability, action: action, result: result)
                if result.exitCode == 0, let versionCheck = summary.versionCheck {
                    saveNativePluginVersionCheck(versionCheck, for: capability)
                } else if result.exitCode == 0, action.kind == .check {
                    removeNativePluginVersionCheck(for: capability)
                }
                runningNativeActionID = nil
                if result.exitCode == 0 {
                    if let optimisticMutation, let optimisticToken {
                        onNativeMutationSucceeded(optimisticMutation, capability, optimisticToken)
                    } else {
                        onNativePluginChanged()
                    }
                } else if let optimisticToken {
                    let output = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
                    onNativeMutationFailed(
                        capability,
                        optimisticToken,
                        output.isEmpty ? "\(action.title) failed: \(action.command)" : output
                    )
                }
            }
        }
    }
}

private struct EmptyInspectorSelectionView: View {
    @ObservedObject private var localization = LocalizationManager.shared
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "sidebar.right")
                .font(.system(size: 38, weight: .regular))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)

            VStack(spacing: 6) {
                Text(L("inspector.empty.title"))
                    .font(.title2.weight(.semibold))
                Text(L("inspector.empty.subtitle"))
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
    @ObservedObject private var localization = LocalizationManager.shared
    let capability: Capability
    let nativePrimaryAction: NativePluginAction?
    let nativeDeleteAction: NativePluginAction?
    let runningNativeActionID: String?
    let allowsFallbackEnablement: Bool
    let allowsFallbackDelete: Bool
    let onEnable: (Capability) -> Void
    let onDisable: (Capability) -> Void
    let onDelete: (Capability) -> Void
    let onClose: () -> Void
    let onNativeAction: (NativePluginAction) -> Void
    let onNativeDelete: (NativePluginAction) -> Void

    var body: some View {
        HStack(spacing: 10) {
            if let nativePrimaryAction {
                InspectorToolbarButton(
                    systemImage: nativePrimaryAction.systemImage,
                    tint: nativePrimaryAction.kind == .enable ? .green : .secondary,
                    title: runningNativeActionID == nativePrimaryAction.id ? L("inspector.action.running") : nativePrimaryAction.title,
                    help: nativePrimaryAction.command,
                    isDisabled: runningNativeActionID != nil
                ) {
                    onNativeAction(nativePrimaryAction)
                }
            } else if allowsFallbackEnablement, capability.statuses.contains(.disabled) {
                InspectorToolbarButton(
                    systemImage: "checkmark.circle",
                    tint: .green,
                    title: L("inspector.action.enable"),
                    help: L("inspector.action.enable")
                ) {
                    onEnable(capability)
                }
            } else if allowsFallbackEnablement {
                InspectorToolbarButton(
                    systemImage: "minus.circle",
                    tint: .secondary,
                    title: L("inspector.action.disable"),
                    help: L("inspector.action.disable")
                ) {
                    onDisable(capability)
                }
            }

            Spacer(minLength: 10)

            if let nativeDeleteAction {
                InspectorToolbarButton(
                    systemImage: runningNativeActionID == nativeDeleteAction.id ? "hourglass" : "trash",
                    tint: .red,
                    help: nativeDeleteAction.command,
                    isDestructive: true,
                    isDisabled: runningNativeActionID != nil
                ) {
                    onNativeDelete(nativeDeleteAction)
                }
            } else if allowsFallbackDelete {
                InspectorToolbarButton(
                    systemImage: "trash",
                    tint: .red,
                    help: L("inspector.action.delete"),
                    isDestructive: true
                ) {
                    onDelete(capability)
                }
            }

            InspectorToolbarButton(
                systemImage: "sidebar.right",
                tint: .secondary,
                help: L("inspector.action.hide")
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
    var isDisabled = false
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
                .foregroundStyle(isDisabled ? .secondary : tint)
                .frame(width: title == nil ? OrbitaTheme.iconControlSize : 118, height: OrbitaTheme.iconControlSize)
                .background(backgroundColor, in: RoundedRectangle(cornerRadius: OrbitaTheme.controlRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: OrbitaTheme.controlRadius, style: .continuous)
                        .strokeBorder(borderColor)
                }
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .contentShape(RoundedRectangle(cornerRadius: OrbitaTheme.controlRadius, style: .continuous))
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

private struct NativePluginVersionCheck: Codable, Equatable {
    var currentVersion: String?
    var latestVersion: String?
    var hasUpdate: Bool
    var checkedAt: Date

    var compactChangeText: String {
        let current = currentVersion ?? "unknown"
        let latest = latestVersion ?? "unknown"
        return "\(current) -> \(latest)"
    }
}

private struct NativePluginActionSection: View {
    @ObservedObject private var localization = LocalizationManager.shared
    let capability: Capability
    let actions: [NativePluginAction]
    let runningActionID: String?
    let result: NativePluginActionResult?
    let versionCheck: NativePluginVersionCheck?
    let onRun: (NativePluginAction) -> Void

    var body: some View {
        InspectorSection {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        HStack(spacing: 8) {
                            Label(sectionTitle, systemImage: sectionIcon)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text(displayManagerName(capability.metadata["manager"]))
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        if let versionCheck, versionCheck.hasUpdate {
                            Text(String(format: L("inspector.native.newVersion"), versionCheck.compactChangeText))
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.orange)
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                        }
                    }

                    if let note = capability.metadata["lifecycleNote"] {
                        Text(note)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 8) {
                    Spacer(minLength: 0)
                    ForEach(actions) { action in
                        NativePluginInlineButton(
                            title: runningActionID == action.id ? L("inspector.action.running") : action.title,
                            systemImage: runningActionID == action.id ? "hourglass" : action.systemImage,
                            isDisabled: runningActionID != nil
                        ) {
                            onRun(action)
                        }
                        .help(action.command)
                    }
                }

                if let result {
                    NativePluginActionResultView(capability: capability, actionResult: result)
                }
            }
        }
    }

    private var sectionTitle: String {
        capability.metadata["manager"] == "agents-skills" ? L("inspector.section.skillsCLI") : L("inspector.section.nativePlugin")
    }

    private var sectionIcon: String {
        capability.metadata["manager"] == "agents-skills" ? "wand.and.stars" : "shippingbox"
    }
}

private struct NativePluginInlineButton: View {
    let title: String
    let systemImage: String
    let isDisabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 15)
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(isDisabled ? .secondary : .primary)
            .frame(height: 32)
            .padding(.horizontal, 12)
            .background(OrbitaTheme.controlFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(OrbitaTheme.border)
            }
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }
}

private struct NativePluginActionResult: Identifiable {
    var id: String { "\(action.id):\(result.command):\(result.exitCode):\(result.output)" }
    let action: NativePluginAction
    let result: CommandRunResult
}

private struct NativePluginDeleteRequest: Identifiable {
    var id: String { "\(capability.id):\(action.id):\(action.command)" }
    let action: NativePluginAction
    let capability: Capability
}

private struct NativePluginActionResultView: View {
    let capability: Capability
    let actionResult: NativePluginActionResult

    var body: some View {
        let summary = NativePluginResultSummary(
            capability: capability,
            action: actionResult.action,
            result: actionResult.result
        )

        HStack(alignment: .top, spacing: 10) {
            Image(systemName: summary.systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(summary.tint)
                .frame(width: 18, alignment: .center)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 3) {
                Text(summary.title)
                    .font(.caption.weight(.semibold))
                if let versionCheck = summary.versionCheck {
                    NativePluginVersionRows(versionCheck: versionCheck)
                } else {
                    Text(summary.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(OrbitaTheme.controlFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(OrbitaTheme.border)
        }
    }
}

private struct NativePluginVersionRows: View {
    @ObservedObject private var localization = LocalizationManager.shared
    let versionCheck: NativePluginVersionCheck

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            versionRow(title: L("inspector.version.current"), value: versionCheck.currentVersion ?? L("inspector.version.unknown"))
            versionRow(title: L("inspector.version.latest"), value: versionCheck.latestVersion ?? L("inspector.version.unknown"))
        }
        .padding(.top, 2)
    }

    private func versionRow(title: String, value: String) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.tertiary)
                .frame(width: 46, alignment: .leading)
            Text(value)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}

private struct NativePluginResultSummary {
    enum Tone {
        case success
        case warning
        case failure
    }

    let title: String
    let detail: String
    let systemImage: String
    let tone: Tone
    let versionCheck: NativePluginVersionCheck?

    @MainActor
    init(capability: Capability, action: NativePluginAction, result: CommandRunResult) {
        if result.exitCode != 0 {
            self.title = String(format: L("inspector.result.failed.title"), action.title)
            self.detail = Self.conciseOutput(result.output, fallback: L("inspector.result.failed.detail"))
            self.systemImage = "exclamationmark.triangle"
            self.tone = .failure
            self.versionCheck = nil
            return
        }

        switch action.kind {
        case .install:
            self.title = L("inspector.result.installed.title")
            self.detail = Self.conciseOutput(result.output, fallback: String(format: L("inspector.result.installed.detail"), capability.name))
            self.systemImage = "checkmark.circle"
            self.tone = .success
            self.versionCheck = nil
        case .check:
            self = Self.checkSummary(capability: capability, output: result.output)
        case .update:
            self = Self.updateSummary(capability: capability, output: result.output)
        case .enable:
            self.title = L("inspector.result.enabled.title")
            self.detail = Self.conciseOutput(result.output, fallback: String(format: L("inspector.result.enabled.detail"), capability.name))
            self.systemImage = "checkmark.circle"
            self.tone = .success
            self.versionCheck = nil
        case .disable:
            self.title = L("inspector.result.disabled.title")
            self.detail = Self.conciseOutput(result.output, fallback: String(format: L("inspector.result.disabled.detail"), capability.name))
            self.systemImage = "minus.circle"
            self.tone = .success
            self.versionCheck = nil
        case .delete:
            self.title = L("inspector.result.deleted.title")
            self.detail = Self.conciseOutput(result.output, fallback: String(format: L("inspector.result.deleted.detail"), capability.name))
            self.systemImage = "trash"
            self.tone = .success
            self.versionCheck = nil
        }
    }

    var tint: Color {
        switch tone {
        case .success:
            return .green
        case .warning:
            return .orange
        case .failure:
            return .red
        }
    }

    @MainActor
    private static func checkSummary(capability: Capability, output: String) -> NativePluginResultSummary {
        if let update = updateVersionChange(in: output) {
            let versionCheck = NativePluginVersionCheck(
                currentVersion: update.from,
                latestVersion: update.to,
                hasUpdate: update.from != update.to,
                checkedAt: Date()
            )
            return NativePluginResultSummary(
                title: L("inspector.result.updateAvailable.title"),
                detail: String(format: L("inspector.result.updateAvailable.detail"), capability.name, update.from, update.to),
                systemImage: "arrow.down.circle",
                tone: .warning,
                versionCheck: versionCheck
            )
        }

        if let versionCheck = pluginVersionCheck(in: output, capability: capability) {
            return NativePluginResultSummary(
                title: versionCheck.hasUpdate ? L("inspector.result.updateAvailable.title") : L("inspector.result.checked.title"),
                detail: versionCheck.hasUpdate
                    ? String(format: L("inspector.result.canMove.detail"), capability.name, versionCheck.currentVersion ?? L("inspector.version.unknown.lower"), versionCheck.latestVersion ?? L("inspector.version.unknown.lower"))
                    : String(format: L("inspector.result.isChecked.detail"), capability.name),
                systemImage: versionCheck.hasUpdate ? "arrow.down.circle" : "checkmark.circle",
                tone: versionCheck.hasUpdate ? .warning : .success,
                versionCheck: versionCheck
            )
        }

        if let codexLine = matchingCodexListLine(in: output, capability: capability) {
            return NativePluginResultSummary(
                title: L("inspector.result.checked.title"),
                detail: codexLine,
                systemImage: "checkmark.circle",
                tone: .success
            )
        }

        return NativePluginResultSummary(
            title: L("inspector.result.checked.title"),
            detail: conciseOutput(output, fallback: L("inspector.result.checked.noVersion")),
            systemImage: "checkmark.circle",
            tone: .success
        )
    }

    @MainActor
    private static func updateSummary(capability: Capability, output: String) -> NativePluginResultSummary {
        if let update = updateVersionChange(in: output) {
            let versionCheck = NativePluginVersionCheck(
                currentVersion: update.to,
                latestVersion: update.to,
                hasUpdate: false,
                checkedAt: Date()
            )
            return NativePluginResultSummary(
                title: L("inspector.result.updated.title"),
                detail: String(format: L("inspector.result.updated.detail"), capability.name, update.from, update.to),
                systemImage: "checkmark.circle",
                tone: .success,
                versionCheck: versionCheck
            )
        }

        let lowercased = output.lowercased()
        if lowercased.contains("already") || lowercased.contains("up to date") || lowercased.contains("no update") {
            let versionCheck = pluginVersionCheck(in: output, capability: capability).map {
                NativePluginVersionCheck(
                    currentVersion: $0.currentVersion,
                    latestVersion: $0.latestVersion ?? $0.currentVersion,
                    hasUpdate: false,
                    checkedAt: Date()
                )
            }
            return NativePluginResultSummary(
                title: L("inspector.result.upToDate.title"),
                detail: conciseOutput(output, fallback: String(format: L("inspector.result.upToDate.detail"), capability.name)),
                systemImage: "checkmark.circle",
                tone: .success,
                versionCheck: versionCheck
            )
        }

        return NativePluginResultSummary(
            title: L("inspector.result.updateCompleted.title"),
            detail: conciseOutput(output, fallback: String(format: L("inspector.result.updateCompleted.detail"), capability.name)),
            systemImage: "checkmark.circle",
            tone: .success
        )
    }

    private init(
        title: String,
        detail: String,
        systemImage: String,
        tone: Tone,
        versionCheck: NativePluginVersionCheck? = nil
    ) {
        self.title = title
        self.detail = detail
        self.systemImage = systemImage
        self.tone = tone
        self.versionCheck = versionCheck
    }

    private static func matchingCodexListLine(in output: String, capability: Capability) -> String? {
        guard jsonObject(in: output) == nil else {
            return nil
        }
        let selector = capability.metadata["pluginSelector"] ?? capability.name
        return output
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { $0.hasPrefix(selector + " ") || $0.hasPrefix(selector + "(") || $0.contains(selector) }
    }

    private static func pluginVersionCheck(in output: String, capability: Capability) -> NativePluginVersionCheck? {
        guard let records = matchingPluginRecords(in: output, capability: capability) else {
            return nil
        }
        let current = records.first(where: isInstalledRecord).flatMap(installedVersion)
            ?? records.compactMap { stringValue($0["currentVersion"]) ?? stringValue($0["installedVersion"]) }.first
            ?? capability.metadata["installedVersion"]
        let latest = records.compactMap(latestVersion).first

        guard current != nil || latest != nil else {
            return nil
        }
        return NativePluginVersionCheck(
            currentVersion: current,
            latestVersion: latest,
            hasUpdate: current != nil && latest != nil && current != latest,
            checkedAt: Date()
        )
    }

    private static func matchingPluginRecords(in output: String, capability: Capability) -> [[String: Any]]? {
        guard let json = jsonObject(in: output) else {
            return nil
        }
        let selector = capability.metadata["pluginSelector"] ?? capability.name
        let pluginName = selector.split(separator: "@", maxSplits: 1).first.map(String.init) ?? capability.name
        let records = pluginRecords(in: json).filter { record in
            let values = ["id", "pluginId", "selector", "name", "plugin", "pluginName", "packageName"]
                .compactMap { stringValue(record[$0]) }
            return values.contains(selector)
                || values.contains(pluginName)
                || values.contains(capability.name)
                || values.contains(where: { $0.hasPrefix(selector) })
        }
        return records.isEmpty ? nil : records
    }

    private static func pluginRecords(in value: Any, container: String? = nil) -> [[String: Any]] {
        if let array = value as? [Any] {
            return array.flatMap { pluginRecords(in: $0, container: container) }
        }

        guard let dictionary = value as? [String: Any] else {
            return []
        }

        var records: [[String: Any]] = []
        if dictionary.keys.contains(where: { ["id", "pluginId", "selector", "name", "version", "enabled"].contains($0) }) {
            var record = dictionary
            if let container {
                record["recordContainer"] = record["recordContainer"] ?? container
            }
            records.append(record)
        }

        for key in ["plugins", "items", "data", "installed", "available"] {
            guard let nested = dictionary[key] else { continue }
            if let keyed = nested as? [String: Any] {
                for (id, value) in keyed {
                    if var record = value as? [String: Any] {
                        record["id"] = record["id"] ?? id
                        record["recordContainer"] = record["recordContainer"] ?? key
                        records.append(record)
                    } else if let array = value as? [Any] {
                        records.append(contentsOf: array.flatMap { pluginRecords(in: $0, container: key) }.map { record in
                            var record = record
                            record["id"] = record["id"] ?? id
                            record["recordContainer"] = record["recordContainer"] ?? key
                            return record
                        })
                    }
                }
            } else {
                records.append(contentsOf: pluginRecords(in: nested, container: key))
            }
        }
        return records
    }

    private static func installedVersion(in record: [String: Any]) -> String? {
        stringValue(record["installedVersion"])
            ?? stringValue(record["currentVersion"])
            ?? stringValue(record["version"])
    }

    private static func latestVersion(in record: [String: Any]) -> String? {
        stringValue(record["latestVersion"])
            ?? stringValue(record["availableVersion"])
            ?? stringValue(record["marketplaceVersion"])
            ?? (isAvailableRecord(record) ? stringValue(record["version"]) : nil)
    }

    private static func isInstalledRecord(_ record: [String: Any]) -> Bool {
        stringValue(record["recordContainer"]) == "installed"
            || record["installPath"] != nil
            || record["installedAt"] != nil
            || record["lastUpdated"] != nil
    }

    private static func isAvailableRecord(_ record: [String: Any]) -> Bool {
        stringValue(record["recordContainer"]) == "available"
            || (record["pluginId"] != nil && record["installCount"] != nil)
    }

    private static func jsonObject(in output: String) -> Any? {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }
        if let data = trimmed.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) {
            return json
        }

        for (opening, closing) in [("{", "}"), ("[", "]")] {
            guard let start = trimmed.firstIndex(of: Character(opening)),
                  let end = trimmed.lastIndex(of: Character(closing)),
                  start < end else {
                continue
            }
            let candidate = String(trimmed[start...end])
            if let data = candidate.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) {
                return json
            }
        }
        return nil
    }

    private static func updateVersionChange(in output: String) -> (from: String, to: String)? {
        let pattern = #"(?:would\s+update|updated|update)\s+from\s+([^\s]+)\s+to\s+([^\s]+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(output.startIndex..<output.endIndex, in: output)
        guard let match = regex.firstMatch(in: output, range: range),
              match.numberOfRanges >= 3,
              let fromRange = Range(match.range(at: 1), in: output),
              let toRange = Range(match.range(at: 2), in: output) else {
            return nil
        }
        return (String(output[fromRange]).trimmingCharacters(in: .punctuationCharacters),
                String(output[toRange]).trimmingCharacters(in: .punctuationCharacters))
    }

    private static func conciseOutput(_ output: String, fallback: String) -> String {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return fallback
        }
        if trimmed.hasPrefix("{") || trimmed.hasPrefix("[") {
            return fallback
        }
        let lines = trimmed
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return lines.prefix(2).joined(separator: " ")
    }

    private static func stringValue(_ value: Any?) -> String? {
        switch value {
        case let string as String:
            return string.isEmpty ? nil : string
        case let number as NSNumber:
            return number.stringValue
        default:
            return nil
        }
    }

    private static func boolValue(_ value: Any?) -> Bool? {
        switch value {
        case let bool as Bool:
            return bool
        case let number as NSNumber:
            return number.boolValue
        case let string as String:
            return Bool(string.lowercased())
        default:
            return nil
        }
    }
}

private struct NativePluginAction: Identifiable {
    static let codexSkillManager = "codex-skill"
    static let claudeSkillManager = "claude-code-skill"
    static let claudeMCPManager = "claude-code-mcpjson-server"
    static let claudeHookManager = "claude-code-hook"

    enum Kind: Equatable {
        case install
        case enable
        case disable
        case delete
        case check
        case update
    }

    let id: String
    let title: String
    let systemImage: String
    let command: String
    let manager: String
    let kind: Kind

    var isEnablementToggle: Bool {
        kind == .enable || kind == .disable
    }

    var optimisticMutation: CapabilityOptimisticMutation? {
        switch kind {
        case .enable:
            return .enable
        case .disable:
            return .disable
        case .delete:
            return .delete
        case .install, .check, .update:
            return nil
        }
    }

    @MainActor
    static func actions(for capability: Capability) -> [NativePluginAction] {
        guard let manager = capability.metadata["manager"] else { return [] }
        var actions: [NativePluginAction] = []
        // The installed version is shown by default as a "Version" field, so the
        // manual "Check" action (checkCommand) is intentionally not surfaced —
        // updates/installs are left to the user via Update / Reinstall.
        if let command = capability.metadata["installCommand"] {
            actions.append(NativePluginAction(id: "install", title: L("inspector.action.reinstall"), systemImage: "arrow.down.doc", command: command, manager: manager, kind: .install))
        }
        if capability.statuses.contains(.disabled), let command = capability.metadata["enableCommand"] {
            actions.append(NativePluginAction(id: "enable", title: L("inspector.action.enable"), systemImage: "checkmark.circle", command: command, manager: manager, kind: .enable))
        }
        if capability.statuses.contains(.enabled), let command = capability.metadata["disableCommand"] {
            actions.append(NativePluginAction(id: "disable", title: L("inspector.action.disable"), systemImage: "minus.circle", command: command, manager: manager, kind: .disable))
        }
        if let command = capability.metadata["updateCommand"] {
            actions.append(NativePluginAction(id: "update", title: L("inspector.action.update"), systemImage: "arrow.down.circle", command: command, manager: manager, kind: .update))
        }
        if ["codex", "claude-code"].contains(manager),
           let command = capability.metadata["deleteCommand"] {
            actions.append(NativePluginAction(id: "delete", title: L("inspector.action.delete"), systemImage: "trash", command: command, manager: manager, kind: .delete))
        }
        return actions
    }

    func workingDirectory(for capability: Capability) -> String? {
        guard manager == "claude-code",
              ["local", "project"].contains(capability.metadata["managerScope"]),
              let projectPath = capability.metadata["projectPath"],
              !projectPath.isEmpty else {
            return nil
        }
        return projectPath
    }

    @MainActor
    static func codexSkillConfigAction(for capability: Capability) -> NativePluginAction? {
        guard capability.type == .skill,
              capability.metadata["codexConfigPath"] != nil,
              capability.metadata["codexSkillConfigPath"] != nil,
              !capability.source.kind.contains("plugin-skill"),
              !(capability.metadata["manager"] == "codex" && capability.metadata["pluginSelector"] != nil)
        else {
            return nil
        }

        let isDisabledForCodex = capability.metadata["codexSkillEnabled"] == "false"
        let commandKey = isDisabledForCodex ? "codexEnableCommand" : "codexDisableCommand"
        guard let command = capability.metadata[commandKey] else { return nil }
        return NativePluginAction(
            id: isDisabledForCodex ? "codex-skill-enable" : "codex-skill-disable",
            title: isDisabledForCodex ? L("inspector.action.enable") : L("inspector.action.disable"),
            systemImage: isDisabledForCodex ? "checkmark.circle" : "minus.circle",
            command: command,
            manager: Self.codexSkillManager,
            kind: isDisabledForCodex ? .enable : .disable
        )
    }

    @MainActor
    static func claudeSkillOverrideAction(for capability: Capability) -> NativePluginAction? {
        guard capability.type == .skill,
              capability.source.kind == "claude-skill",
              capability.metadata["claudeSkillName"] != nil else {
            return nil
        }

        let isDisabled = capability.statuses.contains(.disabled) || capability.metadata["claudeSkillEnabled"] == "false"
        let commandKey = isDisabled ? "claudeSkillEnableCommand" : "claudeSkillDisableCommand"
        guard let command = capability.metadata[commandKey] else { return nil }
        return NativePluginAction(
            id: isDisabled ? "claude-skill-enable" : "claude-skill-disable",
            title: isDisabled ? L("inspector.action.enable") : L("inspector.action.disable"),
            systemImage: isDisabled ? "checkmark.circle" : "minus.circle",
            command: command,
            manager: Self.claudeSkillManager,
            kind: isDisabled ? .enable : .disable
        )
    }

    @MainActor
    static func claudeSkillDeleteAction(for capability: Capability) -> NativePluginAction? {
        guard capability.type == .skill,
              capability.source.kind == "claude-skill",
              let command = capability.metadata["claudeSkillDeleteCommand"] else {
            return nil
        }
        return NativePluginAction(
            id: "claude-skill-delete",
            title: L("inspector.action.delete"),
            systemImage: "trash",
            command: command,
            manager: Self.claudeSkillManager,
            kind: .delete
        )
    }

    @MainActor
    static func claudeMCPConfigAction(for capability: Capability) -> NativePluginAction? {
        guard capability.type == .mcpServer,
              capability.source.kind == "mcp-config",
              capability.metadata["mcpServerName"] != nil else {
            return nil
        }

        let isDisabled = capability.statuses.contains(.disabled) || capability.metadata["claudeMCPEnabled"] == "false"
        let commandKey = isDisabled ? "claudeMCPEnableCommand" : "claudeMCPDisableCommand"
        guard let command = capability.metadata[commandKey] else { return nil }
        return NativePluginAction(
            id: isDisabled ? "claude-mcp-enable" : "claude-mcp-disable",
            title: isDisabled ? L("inspector.action.enable") : L("inspector.action.disable"),
            systemImage: isDisabled ? "checkmark.circle" : "minus.circle",
            command: command,
            manager: Self.claudeMCPManager,
            kind: isDisabled ? .enable : .disable
        )
    }

    @MainActor
    static func claudeMCPDeleteAction(for capability: Capability) -> NativePluginAction? {
        guard capability.type == .mcpServer,
              capability.source.kind == "mcp-config",
              let command = capability.metadata["claudeMCPDeleteCommand"] else {
            return nil
        }
        return NativePluginAction(
            id: "claude-mcp-delete",
            title: L("inspector.action.delete"),
            systemImage: "trash",
            command: command,
            manager: Self.claudeMCPManager,
            kind: .delete
        )
    }

    @MainActor
    static func claudeHookDeleteAction(for capability: Capability) -> NativePluginAction? {
        guard capability.type == .hook,
              capability.source.kind == "claude-settings-hook",
              let command = capability.metadata["claudeHookDeleteCommand"] else {
            return nil
        }
        return NativePluginAction(
            id: "claude-hook-delete",
            title: L("inspector.action.delete"),
            systemImage: "trash",
            command: command,
            manager: Self.claudeHookManager,
            kind: .delete
        )
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

private enum CodexSkillConfigUpdater {
    private struct SkillConfigBlock {
        var end: Int
        var path: String?
        var pathLineIndex: Int?
        var enabledLineIndex: Int?
    }

    static func setEnabled(_ enabled: Bool, skillPath: String, configPath: String) -> CommandRunResult {
        let url = URL(fileURLWithPath: configPath)
        let enabledLine = "enabled = \(enabled ? "true" : "false")"
        do {
            let original = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            var lines = original.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            if original.isEmpty {
                lines = []
            }

            let targetPaths = normalizedPathCandidates(for: skillPath)
            if let block = skillConfigBlocks(in: lines).first(where: { block in
                guard let path = block.path else { return false }
                return !targetPaths.isDisjoint(with: normalizedPathCandidates(for: path))
            }) {
                if let enabledLineIndex = block.enabledLineIndex {
                    lines[enabledLineIndex] = "\(indentation(of: lines[enabledLineIndex]))\(enabledLine)"
                } else {
                    let insertIndex = block.pathLineIndex.map { $0 + 1 } ?? block.end
                    let indent = block.pathLineIndex.map { indentation(of: lines[$0]) } ?? ""
                    lines.insert("\(indent)\(enabledLine)", at: insertIndex)
                }
            } else {
                if !lines.isEmpty, lines.last?.isEmpty == false {
                    lines.append("")
                }
                lines.append("[[skills.config]]")
                lines.append("path = \(tomlString(skillPath))")
                lines.append(enabledLine)
            }

            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
            return CommandRunResult(command: "Codex skill config update", exitCode: 0, output: "\(skillPath) \(enabled ? "enabled" : "disabled") for Codex in \(configPath)")
        } catch {
            return CommandRunResult(command: "Codex skill config update", exitCode: 1, output: error.localizedDescription)
        }
    }

    private static func skillConfigBlocks(in lines: [String]) -> [SkillConfigBlock] {
        var blocks: [SkillConfigBlock] = []
        var currentStart: Int?
        var currentPath: String?
        var currentPathLineIndex: Int?
        var currentEnabledLineIndex: Int?

        func flush(end: Int) {
            guard currentStart != nil else { return }
            blocks.append(SkillConfigBlock(
                end: end,
                path: currentPath,
                pathLineIndex: currentPathLineIndex,
                enabledLineIndex: currentEnabledLineIndex
            ))
        }

        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == "[[skills.config]]" {
                flush(end: index)
                currentStart = index
                currentPath = nil
                currentPathLineIndex = nil
                currentEnabledLineIndex = nil
                continue
            }
            if trimmed.hasPrefix("[") {
                flush(end: index)
                currentStart = nil
                currentPath = nil
                currentPathLineIndex = nil
                currentEnabledLineIndex = nil
                continue
            }
            guard currentStart != nil else { continue }

            if let value = tomlValue(from: trimmed, key: "path") {
                currentPath = value
                currentPathLineIndex = index
            } else if tomlValue(from: trimmed, key: "enabled") != nil {
                currentEnabledLineIndex = index
            }
        }

        flush(end: lines.count)
        return blocks
    }

    private static func tomlValue(from line: String, key: String) -> String? {
        guard let splitIndex = line.firstIndex(of: "=") else { return nil }
        let lhs = line[..<splitIndex].trimmingCharacters(in: .whitespaces)
        guard lhs == key else { return nil }
        let rawValue = line[line.index(after: splitIndex)...].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawValue.isEmpty else { return nil }
        if rawValue.count >= 2,
           rawValue.first == "\"",
           rawValue.last == "\"" {
            let body = rawValue.dropFirst().dropLast()
            return body
                .replacingOccurrences(of: "\\\"", with: "\"")
                .replacingOccurrences(of: "\\\\", with: "\\")
        }
        if rawValue.count >= 2,
           rawValue.first == "'",
           rawValue.last == "'" {
            return String(rawValue.dropFirst().dropLast())
        }
        return rawValue
    }

    private static func normalizedPathCandidates(for path: String) -> Set<String> {
        let url = URL(fileURLWithPath: path)
        return [
            path,
            url.standardizedFileURL.path,
            url.standardizedFileURL.resolvingSymlinksInPath().path
        ]
    }

    private static func indentation(of line: String) -> String {
        String(line.prefix { character in
            character == " " || character == "\t"
        })
    }

    private static func tomlString(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}

private enum ClaudeSkillLifecycleUpdater {
    static func setEnabled(_ enabled: Bool, skillName: String, settingsPath: String) -> CommandRunResult {
        let command = "Claude skillOverrides update"
        do {
            let url = URL(fileURLWithPath: settingsPath)
            var object = try JSONFileEditor.object(at: url)
            var overrides = object["skillOverrides"] as? [String: Any] ?? [:]
            if enabled {
                overrides.removeValue(forKey: skillName)
            } else {
                overrides[skillName] = "off"
            }
            if overrides.isEmpty {
                object.removeValue(forKey: "skillOverrides")
            } else {
                object["skillOverrides"] = overrides
            }
            try JSONFileEditor.write(object, to: url)
            return CommandRunResult(command: command, exitCode: 0, output: "\(skillName) \(enabled ? "enabled" : "disabled") for Claude Code in \(settingsPath)")
        } catch {
            return CommandRunResult(command: command, exitCode: 1, output: error.localizedDescription)
        }
    }

    static func deleteSkill(at path: String) -> CommandRunResult {
        let command = "Claude skill delete"
        do {
            let url = URL(fileURLWithPath: path)
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
            return CommandRunResult(command: command, exitCode: 0, output: "Removed \(path)")
        } catch {
            return CommandRunResult(command: command, exitCode: 1, output: error.localizedDescription)
        }
    }
}

private enum ClaudeMCPJsonLifecycleUpdater {
    static func setEnabled(_ enabled: Bool, serverName: String, settingsPath: String) -> CommandRunResult {
        let command = "Claude disabledMcpjsonServers update"
        do {
            let url = URL(fileURLWithPath: settingsPath)
            var object = try JSONFileEditor.object(at: url)
            var servers = (object["disabledMcpjsonServers"] as? [Any])?.compactMap { $0 as? String } ?? []
            if enabled {
                servers.removeAll { $0 == serverName }
            } else if !servers.contains(serverName) {
                servers.append(serverName)
            }
            if servers.isEmpty {
                object.removeValue(forKey: "disabledMcpjsonServers")
            } else {
                object["disabledMcpjsonServers"] = servers
            }
            try JSONFileEditor.write(object, to: url)
            return CommandRunResult(command: command, exitCode: 0, output: "\(serverName) \(enabled ? "enabled" : "disabled") for Claude Code in \(settingsPath)")
        } catch {
            return CommandRunResult(command: command, exitCode: 1, output: error.localizedDescription)
        }
    }

    static func deleteServer(_ serverName: String, configPath: String) -> CommandRunResult {
        let command = "Claude .mcp.json delete"
        do {
            let url = URL(fileURLWithPath: configPath)
            var object = try JSONFileEditor.object(at: url)
            var removed = false
            for key in ["mcpServers", "servers"] {
                guard var servers = object[key] as? [String: Any],
                      servers.removeValue(forKey: serverName) != nil else {
                    continue
                }
                removed = true
                object[key] = servers
            }
            guard removed else {
                return CommandRunResult(command: command, exitCode: 1, output: "\(serverName) was not found in \(configPath)")
            }
            try JSONFileEditor.write(object, to: url)
            return CommandRunResult(command: command, exitCode: 0, output: "Removed \(serverName) from \(configPath)")
        } catch {
            return CommandRunResult(command: command, exitCode: 1, output: error.localizedDescription)
        }
    }
}

private enum ClaudeHookLifecycleUpdater {
    static func deleteHook(event: String, entryIndex: Int, hookIndex: Int, settingsPath: String) -> CommandRunResult {
        let command = "Claude hook delete"
        do {
            guard !event.isEmpty else {
                return CommandRunResult(command: command, exitCode: 1, output: "Hook event is missing.")
            }

            let url = URL(fileURLWithPath: settingsPath)
            var object = try JSONFileEditor.object(at: url)
            let hasNestedHooks = object["hooks"] is [String: Any]
            var hooksObject = (object["hooks"] as? [String: Any]) ?? object
            guard var entries = hooksObject[event] as? [Any],
                  entries.indices.contains(entryIndex),
                  var entry = entries[entryIndex] as? [String: Any] else {
                return CommandRunResult(command: command, exitCode: 1, output: "\(event) hook entry \(entryIndex) was not found in \(settingsPath)")
            }

            if var hookArray = entry["hooks"] as? [Any] {
                guard hookArray.indices.contains(hookIndex) else {
                    return CommandRunResult(command: command, exitCode: 1, output: "\(event) hook \(entryIndex):\(hookIndex) was not found in \(settingsPath)")
                }
                hookArray.remove(at: hookIndex)
                if hookArray.isEmpty {
                    entries.remove(at: entryIndex)
                } else {
                    entry["hooks"] = hookArray
                    entries[entryIndex] = entry
                }
            } else {
                guard hookIndex == 0 else {
                    return CommandRunResult(command: command, exitCode: 1, output: "\(event) hook \(entryIndex):\(hookIndex) was not found in \(settingsPath)")
                }
                entries.remove(at: entryIndex)
            }

            if entries.isEmpty {
                hooksObject.removeValue(forKey: event)
            } else {
                hooksObject[event] = entries
            }

            if hasNestedHooks {
                if hooksObject.isEmpty {
                    object.removeValue(forKey: "hooks")
                } else {
                    object["hooks"] = hooksObject
                }
            } else {
                object = hooksObject
            }

            try JSONFileEditor.write(object, to: url)
            return CommandRunResult(command: command, exitCode: 0, output: "Removed \(event) hook \(entryIndex):\(hookIndex) from \(settingsPath)")
        } catch {
            return CommandRunResult(command: command, exitCode: 1, output: error.localizedDescription)
        }
    }
}

private enum JSONFileEditor {
    static func object(at url: URL) throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return [:]
        }
        let data = try Data(contentsOf: url)
        if data.isEmpty {
            return [:]
        }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(domain: "Orbita.JSONFileEditor", code: 1, userInfo: [NSLocalizedDescriptionKey: "\(url.path) is not a JSON object"])
        }
        return object
    }

    static func write(_ object: [String: Any], to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        var text = String(decoding: data, as: UTF8.self)
        if !text.hasSuffix("\n") {
            text.append("\n")
        }
        try text.write(to: url, atomically: true, encoding: .utf8)
    }
}

private struct StatusReasonSection: View {
    @ObservedObject private var localization = LocalizationManager.shared
    let capability: Capability

    var body: some View {
        InspectorSection {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(CapabilityVisuals.statusColor(for: capability))
                        .frame(width: 8, height: 8)
                    Text(L("inspector.field.status"))
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
            return L("inspector.dot.broken")
        }
        if capability.statuses.contains(.drifted) || capability.statuses.contains(.shadowed) {
            return L("inspector.dot.needsAttention")
        }
        if capability.statuses.contains(.risky) {
            return L("inspector.dot.reviewNeeded")
        }
        return L("inspector.dot.ready")
    }

    private var reasons: [StatusReason] {
        var items: [StatusReason] = []

        if capability.statuses.contains(.broken) {
            items.append(StatusReason(
                title: L("inspector.reason.broken.title"),
                detail: L("inspector.reason.broken.detail"),
                systemImage: "xmark.octagon",
                color: .red
            ))
        }

        if capability.statuses.contains(.shadowed) {
            items.append(StatusReason(
                title: L("inspector.reason.shadowed.title"),
                detail: L("inspector.reason.shadowed.detail"),
                systemImage: "square.on.square",
                color: .orange
            ))
        }

        if capability.statuses.contains(.drifted) {
            items.append(StatusReason(
                title: L("inspector.reason.drift.title"),
                detail: driftDetail,
                systemImage: "arrow.triangle.branch",
                color: .orange
            ))
        }

        if capability.statuses.contains(.risky) {
            items.append(StatusReason(
                title: L("inspector.reason.risky.title"),
                detail: String(format: L("inspector.reason.risky.detail"), CapabilityDisplayText.accessSummary(for: capability.risks)),
                systemImage: "exclamationmark.triangle",
                color: .yellow
            ))
        }

        if capability.statuses.contains(.disabled) {
            items.append(StatusReason(
                title: L("inspector.reason.disabled.title"),
                detail: disabledDetail,
                systemImage: "minus.circle",
                color: .secondary
            ))
        }

        if capability.metadata["codexSkillEnabled"] == "false", !capability.statuses.contains(.disabled) {
            items.append(StatusReason(
                title: L("inspector.reason.disabledCodex.title"),
                detail: codexSkillDisabledDetail,
                systemImage: "minus.circle",
                color: .secondary
            ))
        }

        // When the drift-locations panel is shown it already enumerates every copy *and* their
        // divergence, so the generic "duplicate name" prose row would just repeat it. Keep the
        // duplicate row only for non-drift duplicates (e.g. identical copied mirrors).
        if capability.statuses.contains(.duplicate), !showsDriftLocationsPanel {
            items.append(StatusReason(
                title: L("inspector.reason.duplicate.title"),
                detail: duplicateDetail,
                systemImage: "doc.on.doc",
                color: .secondary
            ))
        }

        if items.isEmpty {
            items.append(StatusReason(
                title: L("inspector.reason.ready.title"),
                detail: L("inspector.reason.ready.detail"),
                systemImage: "checkmark.circle",
                color: .green
            ))
        }

        return items
    }

    /// True when the dedicated DriftLocationsSection below will actually render its per-copy
    /// comparison, so the status reasons can defer the "where / which differs" detail to it.
    /// Mirrors the panel's own `locations.count > 1` gate (not just JSON presence) so a malformed
    /// or under-populated payload never suppresses the duplicate row *and* hides the panel.
    private var showsDriftLocationsPanel: Bool {
        capability.statuses.contains(.drifted)
            && decodedDriftLocations(for: capability).count > 1
    }

    private var driftDetail: String {
        if let reason = capability.metadata["driftReason"], !reason.isEmpty {
            return reason
        }
        // When the resolver enumerated the conflicting locations, the dedicated
        // DriftLocationsSection below spells out *where* — so keep this line a short,
        // count-aware summary instead of repeating the generic sentence.
        if let count = capability.metadata["driftLocationCount"], !count.isEmpty {
            return String(format: L("inspector.drift.summary"), count)
        }
        return L("inspector.drift.detail")
    }

    private var duplicateDetail: String {
        if let detail = capability.metadata["duplicateDetail"], !detail.isEmpty {
            return detail
        }
        return L("inspector.duplicate.detail")
    }

    private var disabledDetail: String {
        if let manager = capability.metadata["manager"], !manager.isEmpty {
            return String(format: L("inspector.disabled.byManager"), manager)
        }
        if capability.metadata["codexSkillEnabled"] == "false" {
            return codexSkillDisabledDetail
        }
        return L("inspector.disabled.byManifest")
    }

    private var codexSkillDisabledDetail: String {
        let configPath = capability.metadata["codexConfigPath"] ?? "~/.codex/config.toml"
        return String(format: L("inspector.disabled.codexSkill"), configPath)
    }
}

private struct StatusReason: Identifiable {
    var id: String { title }
    let title: String
    let detail: String
    let systemImage: String
    let color: Color
}

/// "Where did it drift?" — the dedicated panel answering the question the one-line drift
/// reason can't: it lists every physical copy the resolver found in the conflicting group,
/// flags the one currently being inspected, marks which copies' content diverges from it,
/// and ends with concrete guidance on how to converge them. Renders nothing unless the
/// resolver attached `driftLocationsJSON` (so older snapshots / non-hash drifts are unaffected).
private struct DriftLocationsSection: View {
    @ObservedObject private var localization = LocalizationManager.shared
    let capability: Capability

    var body: some View {
        if locations.count > 1 {
            InspectorSection {
                VStack(alignment: .leading, spacing: 12) {
                    header
                    Text(String(format: L("inspector.drift.locations.intro"), String(locations.count)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(spacing: 8) {
                        ForEach(locations) { location in
                            DriftLocationRow(location: location, currentHash: currentHash)
                        }
                    }

                    guidance
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.triangle.branch")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.orange)
            Text(L("inspector.drift.locations.title"))
                .font(.caption.weight(.semibold))
            Spacer(minLength: 0)
        }
    }

    private var guidance: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "lightbulb")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.yellow)
                .frame(width: 14, alignment: .center)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(L("inspector.drift.guidance.title"))
                    .font(.caption.weight(.semibold))
                Text(L("inspector.drift.guidance"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.top, 2)
    }

    private var currentHash: String {
        locations.first(where: { $0.location.current })?.location.hash ?? ""
    }

    private var locations: [DriftLocationDisplay] {
        decodedDriftLocations(for: capability).enumerated().map { index, value in
            DriftLocationDisplay(index: index, location: value)
        }
    }
}

/// Decode the resolver's drift-location records for a capability. Returns `[]` when the metadata
/// is absent or malformed, so both the panel and the duplicate-row suppression agree on whether a
/// usable comparison exists. Shared by `DriftLocationsSection` and `StatusReasonSection`.
private func decodedDriftLocations(for capability: Capability) -> [DriftLocation] {
    guard let raw = capability.metadata["driftLocationsJSON"],
          let data = raw.data(using: .utf8),
          let decoded = try? JSONDecoder().decode([DriftLocation].self, from: data) else {
        return []
    }
    return decoded
}

/// Identifiable wrapper keyed by position in the decoded list, so `ForEach` stays stable even when
/// two copies share an identical display path (the path is not unique; the list position is).
private struct DriftLocationDisplay: Identifiable {
    let index: Int
    let location: DriftLocation
    var id: Int { index }
}

private struct DriftLocationRow: View {
    @ObservedObject private var localization = LocalizationManager.shared
    let location: DriftLocationDisplay
    let currentHash: String

    private var record: DriftLocation { location.location }

    private var sourceKind: CapabilitySourceClassifier.SourceKind {
        CapabilitySourceClassifier.sourceKind(forPath: record.path, sourceKind: record.kind)
    }

    /// A non-current copy whose content hash matches the inspected tile is identical; any other
    /// known hash is a genuine divergence worth flagging in orange. Both hashes must be known —
    /// when either is empty (unhashable file) we can't claim divergence, so we stay silent.
    private var divergesFromCurrent: Bool {
        !record.current
            && !record.hash.isEmpty
            && !currentHash.isEmpty
            && record.hash != currentHash
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: sourceKind.systemImage)
                .font(.caption)
                .foregroundStyle(record.current ? Color.accentColor : .secondary)
                .frame(width: 16, alignment: .center)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(sourceKind.title)
                        .font(.caption.weight(.semibold))
                    DriftScopeTag(scope: record.scope)
                    if record.current {
                        DriftStateTag(text: L("inspector.drift.location.current"), tint: .accentColor)
                    } else if divergesFromCurrent {
                        DriftStateTag(text: L("inspector.drift.location.differs"), tint: .orange)
                    }
                    Spacer(minLength: 0)
                }

                Text(displayPath)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .help(record.path)
            }

            if !record.hash.isEmpty {
                Text(shortHash)
                    .font(.caption2.monospaced())
                    .foregroundStyle(divergesFromCurrent ? .orange : .secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(OrbitaTheme.controlFill, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(divergesFromCurrent ? Color.orange.opacity(0.5) : OrbitaTheme.border)
                    }
                    .padding(.top, 1)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .orbitaControlSurface(selected: record.current)
    }

    private var shortHash: String {
        record.hash.count > 12 ? String(record.hash.prefix(12)) : record.hash
    }

    private var displayPath: String {
        // Core already home-abbreviated the path; collapse very long ones to the tail.
        let path = record.path
        guard path.count > 48 else { return path }
        let components = path.split(separator: "/").map(String.init)
        guard components.count > 3 else { return path }
        return "…/" + components.suffix(3).joined(separator: "/")
    }
}

private struct DriftScopeTag: View {
    let scope: String

    var body: some View {
        Text(localizedScope)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(OrbitaTheme.controlFill, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(OrbitaTheme.border)
            }
    }

    @MainActor
    private var localizedScope: String {
        localizedCapabilityScope(scope)
    }
}

/// Localized label for a `CapabilityScope` raw value, falling back to the raw value for any
/// unknown scope so the field never renders a bare key.
@MainActor
func localizedCapabilityScope(_ scope: String) -> String {
    let key = "scope.\(scope)"
    let localized = L(key)
    return localized == key ? scope : localized
}

/// Human-readable label for a plugin `manager` metadata value. The scanner records raw enum
/// tokens (`codex`, `claude-code`, `agents-skills`); rendering those verbatim next to a localized
/// section title looks broken. Managers are native-client brand names, so they map to a consistent
/// branded display (not a translation), with the raw value as a safe fallback for unknowns.
@MainActor
func displayManagerName(_ manager: String?) -> String {
    guard let manager, !manager.isEmpty else { return L("inspector.native.managerFallback") }
    switch manager {
    case "codex": return "Codex"
    case "claude-code", "claude": return "Claude Code"
    case "agents-skills", "agents": return "Agents"
    default: return manager
    }
}

private struct DriftStateTag: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(tint.opacity(0.12), in: Capsule())
    }
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

            Text(displayPath)
                .font(.caption.monospaced())
                .lineLimit(2, reservesSpace: true)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .help(path.isEmpty ? "-" : path)

            SourceFolderButton(path: path)
                .padding(.top, 1)
        }
    }

    private var displayPath: String {
        let value = path.isEmpty ? "-" : path.replacingOccurrences(
            of: FileManager.default.homeDirectoryForCurrentUser.path,
            with: "~"
        )
        guard value.count > 42 else {
            return value
        }
        let components = value.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard components.count > 4 else {
            return value
        }
        return "…/" + components.suffix(3).joined(separator: "/")
    }
}

private struct SourceFolderButton: View {
    @ObservedObject private var localization = LocalizationManager.shared
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
        .help(L("inspector.source.openFolder"))
        .accessibilityLabel(L("inspector.source.openFolder"))
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
    @ObservedObject private var localization = LocalizationManager.shared
    let sourcePath: String
    let onOpenPreview: (MarkdownPreviewDocument) -> Void

    @State private var previewState: MarkdownPreviewState = .loading

    var body: some View {
        InspectorSection {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label(L("inspector.markdown.title"), systemImage: "doc.richtext")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()

                    if let document = previewState.document {
                        Button {
                            onOpenPreview(document)
                        } label: {
                            Label(L("inspector.markdown.preview"), systemImage: "arrow.up.forward.square")
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 10)
                                .frame(height: 28)
                        }
                        .buttonStyle(.plain)
                        .orbitaControlSurface(cornerRadius: 10)
                        .help(L("inspector.markdown.openFull"))
                    }
                }

                switch previewState {
                case .loading:
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text(L("inspector.markdown.loading"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                case .unavailable:
                    Text(L("inspector.markdown.unavailable"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                case let .rendered(_, markdown):
                    Text(markdown)
                        .font(.callout)
                        .lineSpacing(3)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                case let .raw(document):
                    Text(document.markdown)
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
    case rendered(MarkdownPreviewDocument, AttributedString)
    case raw(MarkdownPreviewDocument)
    case failed(String)

    var document: MarkdownPreviewDocument? {
        switch self {
        case let .rendered(document, _), let .raw(document):
            return document
        default:
            return nil
        }
    }

    @MainActor
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
            let document = MarkdownPreviewDocument(
                sourcePath: path,
                title: URL(fileURLWithPath: path).lastPathComponent,
                markdown: markdown
            )

            do {
                let rendered = try AttributedString(
                    markdown: markdown,
                    options: AttributedString.MarkdownParsingOptions(
                        interpretedSyntax: .full,
                        failurePolicy: .returnPartiallyParsedIfPossible
                    )
                )
                return .rendered(document, rendered)
            } catch {
                return .raw(document)
            }
        } catch {
            return .failed(String(format: L("inspector.markdown.readError"), error.localizedDescription))
        }
    }

    @MainActor
    private static func trimmedMarkdown(_ text: String) -> String {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        let body = stripFrontmatter(from: normalized)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let maxLength = 80_000
        guard body.count > maxLength else {
            return body
        }
        let endIndex = body.index(body.startIndex, offsetBy: maxLength)
        return String(body[..<endIndex]) + "\n\n" + L("inspector.markdown.truncated")
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
