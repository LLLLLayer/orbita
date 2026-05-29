import SwiftUI
import Foundation

/// Real in-app i18n: a singleton observable that re-publishes whenever the user
/// changes the language picker. Strings are looked up by key against per-language
/// dictionaries below. Views subscribe to `LocalizationManager.shared` so they
/// re-render on language change without restarting the app.
///
/// To add a new string:
///   1. Add a key + English value under `englishStrings`.
///   2. Add the same key under `simplifiedChineseStrings` and `traditionalChineseStrings`.
///   3. Use `Text(L("key"))` or `String.localized("key")` from views.
///
/// Missing keys fall back to the English dictionary, then to the raw key — so
/// untranslated surfaces stay readable instead of crashing.
@MainActor
final class LocalizationManager: ObservableObject {
    static let shared = LocalizationManager()

    @Published private(set) var language: OrbitaLanguage

    private init() {
        let stored = UserDefaults.standard.string(forKey: "orbitaLanguageCode")
        self.language = OrbitaLanguage(rawValue: stored ?? "") ?? .english
    }

    func setLanguage(_ code: String) {
        let next = OrbitaLanguage(rawValue: code) ?? .english
        guard next != language else { return }
        language = next
    }

    func string(for key: String) -> String {
        let table: [String: String]
        switch language {
        case .english:
            table = LocalizationCatalog.english
        case .simplifiedChinese:
            table = LocalizationCatalog.simplifiedChinese
        case .traditionalChinese:
            table = LocalizationCatalog.traditionalChinese
        }
        if let value = table[key] {
            return value
        }
        return LocalizationCatalog.english[key] ?? key
    }
}

/// Convenience for `Text(L("settings.title"))` at call sites.
@MainActor
func L(_ key: String) -> String {
    LocalizationManager.shared.string(for: key)
}

extension String {
    @MainActor
    static func localized(_ key: String) -> String {
        LocalizationManager.shared.string(for: key)
    }
}

/// View modifier that re-renders the subtree whenever the language changes.
/// Apply `.localized()` near the root of any view that uses `L(...)`.
struct LocalizedModifier: ViewModifier {
    @ObservedObject private var manager = LocalizationManager.shared

    func body(content: Content) -> some View {
        content.id(manager.language.rawValue)
    }
}

extension View {
    func localized() -> some View {
        modifier(LocalizedModifier())
    }
}

enum LocalizationCatalog {
    static let english: [String: String] = [
        // Settings — chrome
        "settings.title": "Settings",
        "settings.close": "Close settings",
        "settings.page.general": "General",
        "settings.page.plugins": "Plugins",
        "settings.page.release": "Release",

        // Settings — General
        "settings.general.subtitle": "Scan behavior, language, and capability display preferences.",
        "settings.general.preferences": "Preferences",
        "settings.general.refresh.title": "Refresh",
        "settings.general.refresh.subtitle": "Controls cache lifetime before Orbita scans capabilities again.",
        "settings.general.sort.title": "Capability sort",
        "settings.general.sort.subtitle": "Default order for capability lists and grouped sections.",
        "settings.general.language.title": "Language",
        "settings.general.language.subtitle": "Display language used by the Orbita interface.",
        "settings.general.language.picker": "Display language",

        // Settings — Plugins
        "settings.plugins.subtitle": "Maintenance commands for Codex, Claude Code, and .agents skills.",
        "settings.plugins.maintenance": "Maintenance",
        "settings.plugins.codex.title": "Codex marketplaces",
        "settings.plugins.codex.detail": "Refresh configured Git marketplace snapshots and rescan Orbita.",
        "settings.plugins.claude.title": "Claude Code plugins",
        "settings.plugins.claude.detail": "List installed plugins with enable status. Update individual plugins from the inspector.",
        "settings.plugins.agents.title": ".agents skills",
        "settings.plugins.agents.detail": "Trigger Skills CLI update in the current project context.",

        // Settings — Release
        "settings.release.subtitle": "Version metadata, signed DMG release, notarization, and Sparkle readiness.",
        "settings.release.pipeline": "Pipeline",
        "settings.release.actions": "Actions",
        "settings.release.action.gh.title": "Check GitHub CLI",
        "settings.release.action.gh.detail": "Verify local gh authentication before creating tags or releases.",
        "settings.release.action.tag.title": "Tag current version",
        "settings.release.action.tag.detail": "Create a local DMG, push the release tag, then let GitHub Actions sign, notarize, staple, and publish the DMG.",
        "settings.release.row.workflow": "Workflow",
        "settings.release.row.tag": "Tag",
        "settings.release.row.artifact": "Artifact",
        "settings.release.row.signing": "Signing",
        "settings.release.row.runtime": "Runtime",
        "settings.release.row.notary": "Notary",
        "settings.release.row.updater": "Updater",
        "settings.release.row.feed": "Feed",
        "settings.release.row.security": "Security",
        "settings.release.row.bundle": "Bundle",
        "settings.release.row.project": "Project",
        "settings.release.row.path": "Path",

        "settings.command.output": "Command Output",
        "settings.command.failed": "Command Failed",
        "settings.command.empty": "(no output)",
        "settings.command.run": "Run",
        "settings.command.running": "Running",

        // Refresh policy
        "refresh.thirtyMinutes": "30 minutes",
        "refresh.oneHour": "1 hour",
        "refresh.automatic": "Automatic",
        "refresh.manual": "Manual",

        // Sort
        "sort.name": "Name",
        "sort.modifiedNewest": "Modified newest",
        "sort.modifiedOldest": "Modified oldest",

        // Capability tiles
        "group.prefix.subtitle": "Grouped by the %@-* prefix",
        "hook.timing": "Hook timing",
        "hook.timing.format": "%@ hook timing",

        // Toast
        "toast.comingSoon": "Coming soon"
    ]

    static let simplifiedChinese: [String: String] = [
        "settings.title": "设置",
        "settings.close": "关闭设置",
        "settings.page.general": "通用",
        "settings.page.plugins": "插件",
        "settings.page.release": "发布",

        "settings.general.subtitle": "扫描行为、语言和能力展示偏好。",
        "settings.general.preferences": "偏好设置",
        "settings.general.refresh.title": "刷新",
        "settings.general.refresh.subtitle": "控制 Orbita 重新扫描能力前的缓存有效期。",
        "settings.general.sort.title": "能力排序",
        "settings.general.sort.subtitle": "能力列表和分组区块的默认排序。",
        "settings.general.language.title": "语言",
        "settings.general.language.subtitle": "Orbita 界面使用的显示语言。",
        "settings.general.language.picker": "显示语言",

        "settings.plugins.subtitle": "Codex、Claude Code 和 .agents 技能的维护命令。",
        "settings.plugins.maintenance": "维护",
        "settings.plugins.codex.title": "Codex 集市",
        "settings.plugins.codex.detail": "刷新已配置的 Git 集市快照,并重新扫描 Orbita。",
        "settings.plugins.claude.title": "Claude Code 插件",
        "settings.plugins.claude.detail": "列出已安装的插件及其启用状态。可在检视器中单独更新插件。",
        "settings.plugins.agents.title": ".agents 技能",
        "settings.plugins.agents.detail": "在当前项目上下文中触发 Skills CLI 更新。",

        "settings.release.subtitle": "版本元数据、签名 DMG 发布、公证以及 Sparkle 就绪状态。",
        "settings.release.pipeline": "流水线",
        "settings.release.actions": "操作",
        "settings.release.action.gh.title": "检查 GitHub CLI",
        "settings.release.action.gh.detail": "在创建标签或发布前,验证本地 gh 认证状态。",
        "settings.release.action.tag.title": "标记当前版本",
        "settings.release.action.tag.detail": "本地构建 DMG,推送发布标签,由 GitHub Actions 完成签名、公证、装订并发布 DMG。",
        "settings.release.row.workflow": "工作流",
        "settings.release.row.tag": "标签",
        "settings.release.row.artifact": "产物",
        "settings.release.row.signing": "签名",
        "settings.release.row.runtime": "运行时",
        "settings.release.row.notary": "公证",
        "settings.release.row.updater": "更新器",
        "settings.release.row.feed": "Feed",
        "settings.release.row.security": "安全",
        "settings.release.row.bundle": "Bundle",
        "settings.release.row.project": "项目",
        "settings.release.row.path": "路径",

        "settings.command.output": "命令输出",
        "settings.command.failed": "命令失败",
        "settings.command.empty": "(无输出)",
        "settings.command.run": "运行",
        "settings.command.running": "运行中",

        "refresh.thirtyMinutes": "30 分钟",
        "refresh.oneHour": "1 小时",
        "refresh.automatic": "自动",
        "refresh.manual": "手动",

        "sort.name": "名称",
        "sort.modifiedNewest": "最近修改优先",
        "sort.modifiedOldest": "最早修改优先",

        "group.prefix.subtitle": "前缀为 %@-* 聚合的内容",
        "hook.timing": "Hook 时机",
        "hook.timing.format": "Hook %@ 时机",

        "toast.comingSoon": "敬请期待"
    ]

    static let traditionalChinese: [String: String] = [
        "settings.title": "設定",
        "settings.close": "關閉設定",
        "settings.page.general": "一般",
        "settings.page.plugins": "外掛",
        "settings.page.release": "發佈",

        "settings.general.subtitle": "掃描行為、語言和能力顯示偏好。",
        "settings.general.preferences": "偏好設定",
        "settings.general.refresh.title": "重新整理",
        "settings.general.refresh.subtitle": "控制 Orbita 重新掃描能力前的快取有效期。",
        "settings.general.sort.title": "能力排序",
        "settings.general.sort.subtitle": "能力列表和分組區塊的預設排序。",
        "settings.general.language.title": "語言",
        "settings.general.language.subtitle": "Orbita 介面使用的顯示語言。",
        "settings.general.language.picker": "顯示語言",

        "settings.plugins.subtitle": "Codex、Claude Code 和 .agents 技能的維護指令。",
        "settings.plugins.maintenance": "維護",
        "settings.plugins.codex.title": "Codex 市集",
        "settings.plugins.codex.detail": "重新整理已設定的 Git 市集快照,並重新掃描 Orbita。",
        "settings.plugins.claude.title": "Claude Code 外掛",
        "settings.plugins.claude.detail": "列出已安裝的外掛及啟用狀態。可在檢視器中個別更新外掛。",
        "settings.plugins.agents.title": ".agents 技能",
        "settings.plugins.agents.detail": "在目前的專案上下文中觸發 Skills CLI 更新。",

        "settings.release.subtitle": "版本中繼資料、簽署 DMG 發佈、公證以及 Sparkle 就緒狀態。",
        "settings.release.pipeline": "流水線",
        "settings.release.actions": "操作",
        "settings.release.action.gh.title": "檢查 GitHub CLI",
        "settings.release.action.gh.detail": "在建立標籤或發佈前,驗證本機 gh 認證狀態。",
        "settings.release.action.tag.title": "標記目前版本",
        "settings.release.action.tag.detail": "本機建立 DMG,推送發佈標籤,由 GitHub Actions 完成簽署、公證、裝訂並發佈 DMG。",
        "settings.release.row.workflow": "工作流",
        "settings.release.row.tag": "標籤",
        "settings.release.row.artifact": "產物",
        "settings.release.row.signing": "簽署",
        "settings.release.row.runtime": "執行階段",
        "settings.release.row.notary": "公證",
        "settings.release.row.updater": "更新器",
        "settings.release.row.feed": "Feed",
        "settings.release.row.security": "安全性",
        "settings.release.row.bundle": "Bundle",
        "settings.release.row.project": "專案",
        "settings.release.row.path": "路徑",

        "settings.command.output": "指令輸出",
        "settings.command.failed": "指令失敗",
        "settings.command.empty": "(無輸出)",
        "settings.command.run": "執行",
        "settings.command.running": "執行中",

        "refresh.thirtyMinutes": "30 分鐘",
        "refresh.oneHour": "1 小時",
        "refresh.automatic": "自動",
        "refresh.manual": "手動",

        "sort.name": "名稱",
        "sort.modifiedNewest": "最近修改優先",
        "sort.modifiedOldest": "最早修改優先",

        "group.prefix.subtitle": "前綴為 %@-* 彙整的內容",
        "hook.timing": "Hook 時機",
        "hook.timing.format": "Hook %@ 時機",

        "toast.comingSoon": "敬請期待"
    ]
}
