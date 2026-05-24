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
                .frame(width: OrbitaLayoutMetrics.sidebarWidth)
            Divider()
            settingsDetail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(.regularMaterial)
    }

    private var settingsSidebar: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Settings")
                    .font(.title2.weight(.semibold))
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .help("Close settings")
            }
            .padding(.top, 28)
            .padding(.horizontal, 18)

            VStack(spacing: 4) {
                ForEach(SettingsPage.allCases) { page in
                    Button {
                        selectedPage = page
                    } label: {
                        Label(page.title, systemImage: page.systemImage)
                            .font(.subheadline.weight(selectedPage == page ? .semibold : .regular))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 10)
                            .frame(height: 32)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(selectedPage == page ? .primary : .secondary)
                    .background(selectedPage == page ? Color.secondary.opacity(0.08) : Color.clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
            .padding(.horizontal, 10)

            Spacer()
        }
        .background(.bar)
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
                case .about:
                    aboutSettings
                }
            }
            .padding(.top, 30)
            .padding(.horizontal, 30)
            .padding(.bottom, 34)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.55))
    }

    private var generalSettings: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsHeader(title: "General", subtitle: "Scan behavior, language, and capability display preferences.")
            SettingsCard(title: "Scan", systemImage: "arrow.clockwise") {
                Picker("Refresh", selection: $refreshPolicy) {
                    ForEach(ScanRefreshPolicy.allCases) { policy in
                        Text(policy.title).tag(policy.rawValue)
                    }
                }
                .pickerStyle(.radioGroup)
            }
            SettingsCard(title: "Display", systemImage: "arrow.up.arrow.down") {
                HStack(spacing: 12) {
                    Text("Capability sort")
                        .font(.callout)
                    Spacer()
                    Picker("Capability sort", selection: $sortOption) {
                        ForEach(CapabilitySortOption.allCases) { option in
                            Text(option.title).tag(option.rawValue)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 180)
                }
            }
            SettingsCard(title: "Language", systemImage: "globe") {
                Picker("Display language", selection: $languageCode) {
                    ForEach(OrbitaLanguage.allCases) { language in
                        Text(language.title).tag(language.rawValue)
                    }
                }
                .pickerStyle(.radioGroup)
            }
        }
    }

    private var pluginSettings: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsHeader(title: "Plugins", subtitle: "Maintenance commands for Codex, Claude Code, and .agents skills.")
            CommandCard(
                title: "Codex marketplaces",
                detail: "Refresh configured Git marketplace snapshots and rescan Orbita.",
                command: "codex plugin marketplace upgrade",
                isRunning: isRunningCommand,
                onRun: { runCommand("codex plugin marketplace upgrade") }
            )
            CommandCard(
                title: "Claude Code plugins",
                detail: "List installed plugins with enable status. Update individual plugins from the inspector.",
                command: "claude plugin list --json",
                isRunning: isRunningCommand,
                onRun: { runCommand("claude plugin list --json") }
            )
            CommandCard(
                title: ".agents skills",
                detail: "Trigger Skills CLI update in the current project context.",
                command: projectRootPath == nil ? "npx skills update -y" : "npx skills update -p -y",
                isRunning: isRunningCommand,
                onRun: { runCommand(projectRootPath == nil ? "npx skills update -y" : "npx skills update -p -y") }
            )
            commandResultView
        }
    }

    private var releaseSettings: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsHeader(title: "Release", subtitle: "Signed DMG release, notarization, and Sparkle update feed readiness.")
            SettingsCard(title: "GitHub Actions", systemImage: "shippingbox") {
                SettingsInfoRow(title: "Workflow", value: ".github/workflows/release.yml")
                SettingsInfoRow(title: "Trigger", value: "Push a tag like v\(VersionInfo.current.version)")
                SettingsInfoRow(title: "Artifact", value: "Orbita-v\(VersionInfo.current.version).dmg")
            }
            SettingsCard(title: "Distribution", systemImage: "checkmark.seal") {
                SettingsInfoRow(title: "Signing", value: "Developer ID Application")
                SettingsInfoRow(title: "Runtime", value: "Hardened Runtime")
                SettingsInfoRow(title: "Notary", value: "xcrun notarytool + stapler")
            }
            SettingsCard(title: "Auto Updates", systemImage: "arrow.triangle.2.circlepath") {
                SettingsInfoRow(title: "Updater", value: "Sparkle runtime + appcast")
                SettingsInfoRow(title: "Feed", value: "SUFeedURL over HTTPS")
                SettingsInfoRow(title: "Security", value: "SUPublicEDKey + EdDSA archive signatures")
            }
            CommandCard(
                title: "Check GitHub CLI",
                detail: "Verify local gh authentication before creating tags or releases.",
                command: "gh auth status",
                isRunning: isRunningCommand,
                onRun: { runCommand("gh auth status") }
            )
            CommandCard(
                title: "Tag current version",
                detail: "Create a local DMG, push the release tag, then let GitHub Actions sign, notarize, staple, and publish the DMG.",
                command: "script/release_github.sh v\(VersionInfo.current.version)",
                isRunning: isRunningCommand,
                onRun: { runCommand("script/release_github.sh v\(VersionInfo.current.version)") }
            )
            commandResultView
        }
    }

    private var aboutSettings: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsHeader(title: "Version", subtitle: "Build metadata and project context.")
            SettingsCard(title: "Orbita", systemImage: "app.badge") {
                SettingsInfoRow(title: "Version", value: VersionInfo.current.version)
                SettingsInfoRow(title: "Build", value: VersionInfo.current.build)
                SettingsInfoRow(title: "Bundle", value: VersionInfo.current.bundleIdentifier)
                SettingsInfoRow(title: "Project", value: projectName)
                if let projectRootPath {
                    SettingsInfoRow(title: "Path", value: projectRootPath)
                }
            }
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
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .plugins: return "Plugins"
        case .release: return "Release"
        case .about: return "Version"
        }
    }

    var systemImage: String {
        switch self {
        case .general: return "gearshape"
        case .plugins: return "shippingbox"
        case .release: return "arrow.up.circle"
        case .about: return "info.circle"
        }
    }
}

private struct SettingsHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
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
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.headline)
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(.secondary.opacity(0.1))
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
                .frame(width: 76, alignment: .leading)
            Text(value)
                .font(.subheadline)
                .textSelection(.enabled)
                .lineLimit(2)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
    }
}

private struct CommandCard: View {
    let title: String
    let detail: String
    let command: String
    let isRunning: Bool
    let onRun: () -> Void

    var body: some View {
        SettingsCard(title: title, systemImage: "terminal") {
            Text(detail)
                .font(.callout)
                .foregroundStyle(.secondary)
            Text(command)
                .font(.caption.monospaced())
                .textSelection(.enabled)
                .lineLimit(2)
            Button(action: onRun) {
                Label(isRunning ? "Running" : "Run", systemImage: isRunning ? "hourglass" : "play")
            }
            .buttonStyle(.bordered)
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
