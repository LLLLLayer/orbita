import SwiftUI
import Foundation

enum OrbitaLanguage: String, CaseIterable, Identifiable {
    case english = "en"
    case simplifiedChinese = "zh-Hans"
    case traditionalChinese = "zh-Hant"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .english:
            return "English"
        case .simplifiedChinese:
            return "简体中文"
        case .traditionalChinese:
            return "繁體中文"
        }
    }
}

enum ScanRefreshPolicy: String, CaseIterable, Identifiable {
    case thirtyMinutes
    case oneHour
    case automatic
    case manual

    var id: String { rawValue }

    var title: String {
        switch self {
        case .thirtyMinutes:
            return "30 minutes"
        case .oneHour:
            return "1 hour"
        case .automatic:
            return "Automatic"
        case .manual:
            return "Manual"
        }
    }

    func cacheTTLMinutes(isEnvironment: Bool) -> Int? {
        switch self {
        case .thirtyMinutes:
            return 30
        case .oneHour:
            return 60
        case .automatic:
            return isEnvironment ? 60 : 30
        case .manual:
            return nil
        }
    }
}

enum CapabilitySortOption: String, CaseIterable, Identifiable {
    case nameAscending
    case modifiedNewest
    case modifiedOldest

    var id: String { rawValue }

    var title: String {
        switch self {
        case .nameAscending:
            return "Name"
        case .modifiedNewest:
            return "Modified newest"
        case .modifiedOldest:
            return "Modified oldest"
        }
    }
}

struct OrbitaSettingsView: View {
    @Binding var refreshPolicy: String
    @Binding var languageCode: String
    @Binding var sortOption: String
    let projectName: String
    let projectRootPath: String?
    let onRefresh: () -> Void
    let onClose: () -> Void

    @State private var selectedPage = SettingsPage.general
    @State private var commandResult: CommandRunResult?
    @State private var isRunningCommand = false

    var body: some View {
        HStack(spacing: 0) {
            settingsSidebar
                .frame(width: 208)
            Divider()
            settingsDetail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(OrbitaTheme.canvas)
    }

    private var settingsSidebar: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Settings")
                    .font(.title3.weight(.semibold))
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
                .orbitaControlSurface(cornerRadius: 8)
                .help("Close settings")
            }
            .padding(.top, 26)
            .padding(.horizontal, 16)

            VStack(spacing: 2) {
                ForEach(SettingsPage.allCases) { page in
                    SettingsSidebarRow(
                        page: page,
                        isSelected: selectedPage == page,
                        action: {
                            selectedPage = page
                        }
                    )
                }
            }
            .padding(.horizontal, 8)

            Spacer()
        }
        .background(OrbitaTheme.sidebarBackground)
    }

    @ViewBuilder
    private var settingsDetail: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                switch selectedPage {
                case .general:
                    generalSettings
                case .plugins:
                    pluginSettings
                case .release:
                    releaseSettings
                }
            }
            .padding(.top, 28)
            .padding(.horizontal, 32)
            .padding(.bottom, 34)
            .frame(maxWidth: 820, alignment: .topLeading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .background(OrbitaTheme.canvas)
    }

    private var generalSettings: some View {
        SettingsPageStack {
            SettingsHeader(title: "General", subtitle: "Scan behavior, language, and capability display preferences.")
            SettingsCard(title: "Preferences", systemImage: "slider.horizontal.3") {
                SettingsPreferenceRow(
                    title: "Refresh",
                    subtitle: "Controls cache lifetime before Orbita scans capabilities again."
                ) {
                    Picker("Refresh", selection: $refreshPolicy) {
                        ForEach(ScanRefreshPolicy.allCases) { policy in
                            Text(policy.title).tag(policy.rawValue)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 360)
                }

                SettingsDivider()

                SettingsPreferenceRow(
                    title: "Capability sort",
                    subtitle: "Default order for capability lists and grouped sections."
                ) {
                    Picker("Capability sort", selection: $sortOption) {
                        ForEach(CapabilitySortOption.allCases) { option in
                            Text(option.title).tag(option.rawValue)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 190)
                }

                SettingsDivider()

                SettingsPreferenceRow(
                    title: "Language",
                    subtitle: "Display language used by the Orbita interface."
                ) {
                    Picker("Display language", selection: $languageCode) {
                        ForEach(OrbitaLanguage.allCases) { language in
                            Text(language.title).tag(language.rawValue)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 320)
                }
            }
        }
    }

    private var pluginSettings: some View {
        SettingsPageStack {
            SettingsHeader(title: "Plugins", subtitle: "Maintenance commands for Codex, Claude Code, and .agents skills.")
            SettingsCard(title: "Maintenance", systemImage: "terminal") {
                CommandRow(
                    title: "Codex marketplaces",
                    detail: "Refresh configured Git marketplace snapshots and rescan Orbita.",
                    command: "codex plugin marketplace upgrade",
                    isRunning: isRunningCommand,
                    onRun: { runCommand("codex plugin marketplace upgrade") }
                )

                SettingsDivider()

                CommandRow(
                    title: "Claude Code plugins",
                    detail: "List installed plugins with enable status. Update individual plugins from the inspector.",
                    command: "claude plugin list --json",
                    isRunning: isRunningCommand,
                    onRun: { runCommand("claude plugin list --json") }
                )

                SettingsDivider()

                CommandRow(
                    title: ".agents skills",
                    detail: "Trigger Skills CLI update in the current project context.",
                    command: projectRootPath == nil ? "npx skills update -y" : "npx skills update -p -y",
                    isRunning: isRunningCommand,
                    onRun: { runCommand(projectRootPath == nil ? "npx skills update -y" : "npx skills update -p -y") }
                )
            }
            commandResultView
        }
    }

    private var releaseSettings: some View {
        SettingsPageStack {
            SettingsHeader(title: "Release", subtitle: "Version metadata, signed DMG release, notarization, and Sparkle readiness.")
            ReleaseSummaryCard(
                versionInfo: VersionInfo.current,
                projectName: projectName,
                projectRootPath: projectRootPath
            )

            SettingsCard(title: "Pipeline", systemImage: "shippingbox") {
                SettingsInfoRow(title: "Workflow", value: ".github/workflows/release.yml")
                SettingsInfoRow(title: "Tag", value: "v\(VersionInfo.current.version)")
                SettingsInfoRow(title: "Artifact", value: "Orbita-v\(VersionInfo.current.version).dmg")

                SettingsDivider()

                SettingsInfoRow(title: "Signing", value: "Developer ID Application")
                SettingsInfoRow(title: "Runtime", value: "Hardened Runtime")
                SettingsInfoRow(title: "Notary", value: "xcrun notarytool + stapler")

                SettingsDivider()

                SettingsInfoRow(title: "Updater", value: "Sparkle runtime + appcast")
                SettingsInfoRow(title: "Feed", value: "SUFeedURL over HTTPS")
                SettingsInfoRow(title: "Security", value: "SUPublicEDKey + EdDSA archive signatures")
            }

            SettingsCard(title: "Actions", systemImage: "play.circle") {
                CommandRow(
                    title: "Check GitHub CLI",
                    detail: "Verify local gh authentication before creating tags or releases.",
                    command: "gh auth status",
                    isRunning: isRunningCommand,
                    onRun: { runCommand("gh auth status") }
                )

                SettingsDivider()

                CommandRow(
                    title: "Tag current version",
                    detail: "Create a local DMG, push the release tag, then let GitHub Actions sign, notarize, staple, and publish the DMG.",
                    command: "script/release_github.sh v\(VersionInfo.current.version)",
                    isRunning: isRunningCommand,
                    onRun: { runCommand("script/release_github.sh v\(VersionInfo.current.version)") }
                )
            }
            commandResultView
        }
    }

    @ViewBuilder
    private var commandResultView: some View {
        if let commandResult {
            SettingsCard(title: commandResult.exitCode == 0 ? "Command Output" : "Command Failed", systemImage: commandResult.exitCode == 0 ? "terminal" : "exclamationmark.triangle") {
                Text(commandResult.output.isEmpty ? "(no output)" : commandResult.output)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                    .lineLimit(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func runCommand(_ command: String) {
        guard !isRunningCommand else { return }
        isRunningCommand = true
        commandResult = nil
        let workingDirectory = projectRootPath ?? FileManager.default.currentDirectoryPath
        Task.detached {
            let result = ShellCommandRunner.run(command, workingDirectory: workingDirectory)
            await MainActor.run {
                commandResult = result
                isRunningCommand = false
                onRefresh()
            }
        }
    }
}

private enum SettingsPage: String, CaseIterable, Identifiable {
    case general
    case plugins
    case release

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .plugins: return "Plugins"
        case .release: return "Release"
        }
    }

    var systemImage: String {
        switch self {
        case .general: return "gearshape"
        case .plugins: return "shippingbox"
        case .release: return "arrow.up.circle"
        }
    }
}

private struct SettingsSidebarRow: View {
    let page: SettingsPage
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label {
                Text(page.title)
                    .font(.subheadline.weight(isSelected ? .semibold : .regular))
                    .lineLimit(1)
            } icon: {
                Image(systemName: page.systemImage)
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 18)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .frame(height: 34)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(isSelected ? .primary : .secondary)
        .background(
            isSelected ? OrbitaTheme.elevatedSurface : Color.clear,
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(isSelected ? OrbitaTheme.border : Color.clear)
        }
    }
}

private struct SettingsPageStack<Content: View>: View {
    private let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            content()
        }
    }
}

private struct SettingsHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.title2.weight(.semibold))
            Text(subtitle)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}

private struct SettingsCard<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            Label {
                Text(title)
                    .font(.headline)
            } icon: {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 18)
            }
            content()
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .orbitaCard(cornerRadius: 12, shadowRadius: 5, shadowY: 2)
    }
}

private struct ReleaseSummaryCard: View {
    let versionInfo: VersionInfo
    let projectName: String
    let projectRootPath: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: "app.badge")
                    .font(.system(size: 23, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 44)
                    .background(OrbitaTheme.controlFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text("Orbita")
                        .font(.title3.weight(.semibold))
                    Text("Build \(versionInfo.build) for \(projectName)")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 16)

                Text("v\(versionInfo.version)")
                    .font(.callout.monospacedDigit().weight(.semibold))
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(OrbitaTheme.controlFill, in: Capsule())
            }

            SettingsDivider()

            SettingsInfoRow(title: "Bundle", value: versionInfo.bundleIdentifier)
            SettingsInfoRow(title: "Project", value: projectName)
            if let projectRootPath {
                SettingsInfoRow(title: "Path", value: projectRootPath)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .orbitaCard(cornerRadius: 12, shadowRadius: 5, shadowY: 2)
    }
}

private struct SettingsDivider: View {
    var body: some View {
        Divider()
            .padding(.vertical, 1)
    }
}

private struct SettingsPreferenceRow<Control: View>: View {
    let title: String
    let subtitle: String
    private let control: () -> Control

    init(
        title: String,
        subtitle: String,
        @ViewBuilder control: @escaping () -> Control
    ) {
        self.title = title
        self.subtitle = subtitle
        self.control = control
    }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.callout.weight(.semibold))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            control()
                .tint(OrbitaTheme.prominentControlFill)
        }
    }
}

private struct SettingsInfoRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 86, alignment: .leading)
            Text(value)
                .font(.subheadline)
                .textSelection(.enabled)
                .lineLimit(2)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
    }
}

private struct CommandRow: View {
    let title: String
    let detail: String
    let command: String
    let isRunning: Bool
    let onRun: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.callout.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(command)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: onRun) {
                Label(isRunning ? "Running" : "Run", systemImage: isRunning ? "hourglass" : "play")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(isRunning)
        }
    }
}

private struct VersionInfo {
    let version: String
    let build: String
    let bundleIdentifier: String

    static var current: VersionInfo {
        let bundle = Bundle.main
        return VersionInfo(
            version: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0",
            build: bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1",
            bundleIdentifier: bundle.bundleIdentifier ?? "dev.orbita.app"
        )
    }
}

struct CommandRunResult: Sendable {
    let command: String
    let exitCode: Int32
    let output: String
}

enum ShellCommandRunner {
    static func run(_ command: String, workingDirectory: String) -> CommandRunResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", command]
        process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            return CommandRunResult(command: command, exitCode: process.terminationStatus, output: output)
        } catch {
            return CommandRunResult(command: command, exitCode: 1, output: error.localizedDescription)
        }
    }
}
