import SwiftUI
import Foundation

enum OrbitaLanguage: String, CaseIterable, Identifiable {
    case english = "en"
    case simplifiedChinese = "zh-Hans"
    case traditionalChinese = "zh-Hant"

    var id: String { rawValue }

    /// Always rendered in the language's own script — never translated. The picker
    /// is the one place users need to recognize a language even when the UI is in
    /// another one.
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

    @MainActor
    var title: String {
        switch self {
        case .thirtyMinutes:
            return L("refresh.thirtyMinutes")
        case .oneHour:
            return L("refresh.oneHour")
        case .automatic:
            return L("refresh.automatic")
        case .manual:
            return L("refresh.manual")
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

    /// Plain-language description of *when* this policy re-scans, shown live under the
    /// picker so the user understands what "Automatic" actually does (its TTL is
    /// scope-dependent — 30 min for a project, 60 min for This Mac).
    @MainActor
    var explanation: String {
        L("refresh.explain.\(rawValue)")
    }
}

enum CapabilitySortOption: String, CaseIterable, Identifiable {
    case nameAscending
    case modifiedNewest
    case modifiedOldest
    case statusPriority
    case riskLevel

    var id: String { rawValue }

    @MainActor
    var title: String {
        switch self {
        case .nameAscending:
            return L("sort.name")
        case .modifiedNewest:
            return L("sort.modifiedNewest")
        case .modifiedOldest:
            return L("sort.modifiedOldest")
        case .statusPriority:
            return L("sort.statusPriority")
        case .riskLevel:
            return L("sort.riskLevel")
        }
    }
}

struct OrbitaSettingsView: View {
    // Observe the language manager so this view (and its L() calls) re-render on a
    // language switch via normal dependency tracking — no `.id()` rebuild, so the
    // selected page and other local state survive the switch.
    @ObservedObject private var localization = LocalizationManager.shared
    @Binding var refreshPolicy: String
    @Binding var languageCode: String
    @Binding var sortOption: String
    let projectName: String
    let projectRootPath: String?
    let onRefresh: () -> Void
    let onClose: () -> Void
    var onShowGuide: (() -> Void)? = nil

    @AppStorage("orbitaOnboardingGuideFrequency") private var guideFrequency = OnboardingGuideFrequency.firstLaunchOnly.rawValue
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
        .background(OrbitaTheme.canvas)
        .localized()
    }

    private var settingsSidebar: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(L("settings.title"))
                    .font(.title3.weight(.semibold))
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
                .orbitaControlSurface(cornerRadius: 8)
                .help(L("settings.close"))
                .accessibilityLabel(L("settings.close"))
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
                case .guide:
                    guideSettings
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
            SettingsHeader(title: L("settings.page.general"), subtitle: L("settings.general.subtitle"))
            SettingsCard(title: L("settings.general.preferences"), systemImage: "slider.horizontal.3") {
                // Each preference is a stacked block — title + subtitle, then the
                // control on its own line sharing the card's leading edge. This
                // removes the old ragged trailing-float of three mismatched-width
                // controls and the dead zone between each subtitle and its control.
                SettingsPreferenceRow(
                    title: L("settings.general.refresh.title"),
                    subtitle: L("settings.general.refresh.subtitle")
                ) {
                    VStack(alignment: .leading, spacing: 9) {
                        Picker(L("settings.general.refresh.title"), selection: $refreshPolicy) {
                            ForEach(ScanRefreshPolicy.allCases) { policy in
                                Text(policy.title).tag(policy.rawValue)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .frame(maxWidth: SettingsLayout.segmentedMaxWidth, alignment: .leading)

                        // Live, plain-language explanation of the selected policy — this is the
                        // line that finally tells the user what "Automatic" means.
                        Label {
                            Text((ScanRefreshPolicy(rawValue: refreshPolicy) ?? .automatic).explanation)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        } icon: {
                            Image(systemName: "info.circle")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: SettingsLayout.segmentedMaxWidth, alignment: .leading)
                        .animation(.easeInOut(duration: 0.18), value: refreshPolicy)
                    }
                }

                SettingsDivider()

                SettingsPreferenceRow(
                    title: L("settings.general.sort.title"),
                    subtitle: L("settings.general.sort.subtitle")
                ) {
                    Picker(L("settings.general.sort.title"), selection: $sortOption) {
                        ForEach(CapabilitySortOption.allCases) { option in
                            Text(option.title).tag(option.rawValue)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize()
                }

                SettingsDivider()

                SettingsPreferenceRow(
                    title: L("settings.general.language.title"),
                    subtitle: L("settings.general.language.subtitle")
                ) {
                    Picker(L("settings.general.language.picker"), selection: $languageCode) {
                        ForEach(OrbitaLanguage.allCases) { language in
                            Text(language.title).tag(language.rawValue)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(maxWidth: SettingsLayout.segmentedMaxWidth, alignment: .leading)
                }
            }
        }
    }

    private var guideSettings: some View {
        SettingsPageStack {
            SettingsHeader(title: L("settings.page.guide"), subtitle: L("settings.guide.subtitle"))
            SettingsCard(title: L("settings.guide.card"), systemImage: "sparkles") {
                SettingsPreferenceRow(
                    title: L("settings.guide.replay.title"),
                    subtitle: L("settings.guide.replay.subtitle")
                ) {
                    Button {
                        onClose()
                        onShowGuide?()
                    } label: {
                        Label(L("settings.guide.replay.button"), systemImage: "play.circle")
                    }
                    .controlSize(.large)
                    .disabled(onShowGuide == nil)
                }

                SettingsDivider()

                SettingsPreferenceRow(
                    title: L("settings.guide.frequency.title"),
                    subtitle: L("settings.guide.frequency.subtitle")
                ) {
                    Picker(L("settings.guide.frequency.title"), selection: $guideFrequency) {
                        ForEach(OnboardingGuideFrequency.allCases) { frequency in
                            Text(frequency.title).tag(frequency.rawValue)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(maxWidth: SettingsLayout.segmentedMaxWidth, alignment: .leading)
                }
            }
        }
    }

    private var pluginSettings: some View {
        SettingsPageStack {
            SettingsHeader(title: L("settings.page.plugins"), subtitle: L("settings.plugins.subtitle"))
            SettingsCard(title: L("settings.plugins.maintenance"), systemImage: "terminal") {
                CommandRow(
                    title: L("settings.plugins.codex.title"),
                    detail: L("settings.plugins.codex.detail"),
                    command: "codex plugin marketplace upgrade",
                    isRunning: isRunningCommand,
                    onRun: { runCommand("codex plugin marketplace upgrade") }
                )

                SettingsDivider()

                CommandRow(
                    title: L("settings.plugins.claude.title"),
                    detail: L("settings.plugins.claude.detail"),
                    command: "claude plugin list --json",
                    isRunning: isRunningCommand,
                    onRun: { runCommand("claude plugin list --json") }
                )

                SettingsDivider()

                CommandRow(
                    title: L("settings.plugins.agents.title"),
                    detail: L("settings.plugins.agents.detail"),
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
            SettingsHeader(title: L("settings.page.release"), subtitle: L("settings.release.subtitle"))
            ReleaseSummaryCard(
                versionInfo: VersionInfo.current,
                projectName: projectName,
                projectRootPath: projectRootPath
            )

            // The old single "Pipeline" card crammed 9 read-only rows into three
            // unlabeled divider groups. Split into three demoted (flat, no-shadow)
            // reference cards so each concern is named: what gets built, how it's
            // trusted, how it auto-updates.
            SettingsReferenceCard(title: L("settings.release.group.build"), systemImage: "hammer") {
                SettingsInfoRow(title: L("settings.release.row.workflow"), value: ".github/workflows/release.yml")
                SettingsInfoRow(title: L("settings.release.row.tag"), value: "v\(VersionInfo.current.version)")
                SettingsInfoRow(title: L("settings.release.row.artifact"), value: "Orbita-v\(VersionInfo.current.version).dmg")
            }

            SettingsReferenceCard(title: L("settings.release.group.trust"), systemImage: "checkmark.seal") {
                SettingsInfoRow(title: L("settings.release.row.signing"), value: "Developer ID Application")
                SettingsInfoRow(title: L("settings.release.row.runtime"), value: "Hardened Runtime")
                SettingsInfoRow(title: L("settings.release.row.notary"), value: "xcrun notarytool + stapler")
            }

            SettingsReferenceCard(title: L("settings.release.group.update"), systemImage: "arrow.down.circle") {
                SettingsInfoRow(title: L("settings.release.row.updater"), value: "Sparkle runtime + appcast")
                SettingsInfoRow(title: L("settings.release.row.feed"), value: "SUFeedURL over HTTPS")
                SettingsInfoRow(title: L("settings.release.row.security"), value: "SUPublicEDKey + EdDSA archive signatures")
            }

            SettingsCard(title: L("settings.release.actions"), systemImage: "play.circle") {
                CommandRow(
                    title: L("settings.release.action.gh.title"),
                    detail: L("settings.release.action.gh.detail"),
                    command: "gh auth status",
                    isRunning: isRunningCommand,
                    onRun: { runCommand("gh auth status") }
                )

                SettingsDivider()

                CommandRow(
                    title: L("settings.release.action.tag.title"),
                    detail: L("settings.release.action.tag.detail"),
                    command: "script/release_github.sh v\(VersionInfo.current.version)",
                    isRunning: isRunningCommand,
                    isPrimary: true,
                    onRun: { runCommand("script/release_github.sh v\(VersionInfo.current.version)") }
                )
            }
            commandResultView
        }
    }

    @ViewBuilder
    private var commandResultView: some View {
        if let commandResult {
            SettingsCard(
                title: commandResult.exitCode == 0 ? L("settings.command.output") : L("settings.command.failed"),
                systemImage: commandResult.exitCode == 0 ? "terminal" : "exclamationmark.triangle"
            ) {
                Text(commandResult.output.isEmpty ? L("settings.command.empty") : commandResult.output)
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
    case guide
    case plugins
    case release

    var id: String { rawValue }

    @MainActor
    var title: String {
        switch self {
        case .general: return L("settings.page.general")
        case .guide: return L("settings.page.guide")
        case .plugins: return L("settings.page.plugins")
        case .release: return L("settings.page.release")
        }
    }

    var systemImage: String {
        switch self {
        case .general: return "gearshape"
        case .guide: return "sparkles"
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

/// A demoted variant of `SettingsCard` for read-only reference facts: flat
/// `controlFill` background, no shadow, and a small uppercase caption header. The
/// lack of elevation visually ranks these below the actionable (elevated) cards so
/// the page reads as "reference, then actions" instead of one flat wall of rows.
private struct SettingsReferenceCard<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
            } icon: {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
            }
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(OrbitaTheme.controlFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(OrbitaTheme.border)
        }
    }
}

private struct ReleaseSummaryCard: View {
    @ObservedObject private var localization = LocalizationManager.shared
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
                    Text(String(format: L("settings.release.buildFor"), versionInfo.build, projectName))
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

            SettingsInfoRow(title: L("settings.release.row.bundle"), value: versionInfo.bundleIdentifier)
            SettingsInfoRow(title: L("settings.release.row.project"), value: projectName)
            if let projectRootPath {
                SettingsInfoRow(title: L("settings.release.row.path"), value: projectRootPath)
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

private enum SettingsLayout {
    /// Shared upper bound for the General-page segmented pickers. Wide enough to
    /// fit the longest localized option set ("30 minutes | 1 hour | Automatic |
    /// Manual" and "30 分钟 | 1 小时 | 自动 | 手动") without stretching to the
    /// content clamp, and identical for both bars so they read as one set.
    static let segmentedMaxWidth: CGFloat = 460
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
        VStack(alignment: .leading, spacing: 9) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.callout.weight(.semibold))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Control sits on its own line at the card's leading edge — segmented
            // bars size to their localized labels (capped), the menu hugs content.
            control()
                .tint(OrbitaTheme.prominentControlFill)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 2)
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
    @ObservedObject private var localization = LocalizationManager.shared
    let title: String
    let detail: String
    let command: String
    let isRunning: Bool
    // Defaulted so the plugins-page call sites keep compiling without it; only the
    // release "Tag current version" row sets it, making it the page's lead action.
    var isPrimary: Bool = false
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

            // .buttonStyle(.borderedProminent) vs (.bordered) are different concrete
            // types, so the primary/secondary split is branched rather than ternary'd.
            Group {
                if isPrimary {
                    Button(action: onRun) {
                        Label(isRunning ? L("settings.command.running") : L("settings.command.run"), systemImage: isRunning ? "hourglass" : "play")
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button(action: onRun) {
                        Label(isRunning ? L("settings.command.running") : L("settings.command.run"), systemImage: isRunning ? "hourglass" : "play")
                    }
                    .buttonStyle(.bordered)
                }
            }
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
