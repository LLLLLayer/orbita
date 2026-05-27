import Foundation
import CryptoKit

public struct ScanOptions: Sendable {
    public var includeUserScope: Bool
    public var maxSkillFiles: Int
    public var userSkillRoots: [URL]
    public var userAgentRoots: [URL]
    public var codexConfigURL: URL
    public var codexPluginCacheRoot: URL
    public var claudeInstalledPluginsURL: URL
    public var claudeSettingsURLs: [URL]
    public var skillsGlobalLockURL: URL
    public var ignoredDirectoryNames: Set<String>
    public var progressHandler: (@Sendable (ScanProgressEvent) -> Void)?

    public init(
        includeUserScope: Bool = true,
        maxSkillFiles: Int = 200,
        userSkillRoots: [URL]? = nil,
        userAgentRoots: [URL]? = nil,
        codexConfigURL: URL? = nil,
        codexPluginCacheRoot: URL? = nil,
        claudeInstalledPluginsURL: URL? = nil,
        claudeSettingsURLs: [URL]? = nil,
        skillsGlobalLockURL: URL? = nil,
        ignoredDirectoryNames: Set<String> = Self.defaultIgnoredDirectoryNames,
        progressHandler: (@Sendable (ScanProgressEvent) -> Void)? = nil
    ) {
        let home = FileManager.default.homeDirectoryForCurrentUser
        self.includeUserScope = includeUserScope
        self.maxSkillFiles = maxSkillFiles
        self.userSkillRoots = userSkillRoots ?? Self.defaultUserSkillRoots()
        self.userAgentRoots = userAgentRoots ?? (userSkillRoots == nil ? Self.defaultUserAgentRoots() : [])
        self.codexConfigURL = codexConfigURL ?? home.appendingPathComponent(".codex/config.toml")
        self.codexPluginCacheRoot = codexPluginCacheRoot ?? home.appendingPathComponent(".codex/plugins/cache")
        self.claudeInstalledPluginsURL = claudeInstalledPluginsURL ?? home.appendingPathComponent(".claude/plugins/installed_plugins.json")
        self.claudeSettingsURLs = claudeSettingsURLs ?? [home.appendingPathComponent(".claude/settings.json")]
        self.skillsGlobalLockURL = skillsGlobalLockURL ?? SkillsAgentCatalog.defaultGlobalLockURL()
        self.ignoredDirectoryNames = ignoredDirectoryNames
        self.progressHandler = progressHandler
    }

    public static func defaultUserSkillRoots() -> [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            home.appendingPathComponent(".codex/skills"),
            home.appendingPathComponent(".agents/skills"),
            home.appendingPathComponent(".claude/skills"),
            home.appendingPathComponent(".codex/plugins/cache")
        ]
    }

    public static func defaultUserAgentRoots() -> [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            home.appendingPathComponent(".claude/agents")
        ]
    }

    public static let defaultIgnoredDirectoryNames: Set<String> = [
        ".build",
        ".git",
        ".swiftpm",
        ".xcodeproj",
        ".xcworkspace",
        "__pycache__",
        "__pypackages__",
        "DerivedData",
        "build",
        "coverage",
        "dist",
        "prototypes",
        "xcuserdata"
    ]
}

public struct ScanProgressEvent: Sendable, Hashable {
    public var name: String
    public var path: String
    public var count: Int?

    public init(name: String, path: String, count: Int? = nil) {
        self.name = name
        self.path = path
        self.count = count
    }
}

public final class CapabilityScanner {
    private let fileManager: FileManager

    private struct ClaudeSkillOverrideState {
        var enabled: Bool
        var settingsPath: String
    }

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func scan(projectRoot: URL, options: ScanOptions = ScanOptions()) throws -> ScanResult {
        let root = projectRoot.standardizedFileURL.resolvingSymlinksInPath()
        emitProgress("scan.start", path: root.path, options: options)
        try validateProjectRoot(root)

        var capabilities: [Capability] = []
        var issues: [ScanIssue] = []
        var codexSkillStateOverrides = codexSkillStates(at: options.codexConfigURL)
        codexSkillStateOverrides.merge(codexSkillStates(at: root.appendingPathComponent(".codex/config.toml"))) { _, project in
            project
        }
        let claudeStateURLs = claudeSettingsStateURLs(projectRoot: root, options: options)
        let claudeSkillStates = claudeSkillOverrideStates(at: claudeStateURLs)
        let claudeDisabledMCPServerSettingsPaths = claudeDisabledMcpjsonServerSettingsPaths(at: claudeStateURLs)
        let projectSkillsLock = SkillsLockReader.read(at: root.appendingPathComponent("skills-lock.json"))
        let globalSkillsLock = SkillsLockReader.read(at: options.skillsGlobalLockURL)

        emitProgress("scan.instructions.start", path: root.path, options: options)
        scanInstructionFiles(at: root, into: &capabilities)
        emitProgress("scan.instructions.finish", path: root.path, count: capabilities.count, options: options)

        emitProgress("scan.codex.start", path: root.appendingPathComponent(".codex").path, options: options)
        scanCodexWorkspace(
            at: root,
            options: options,
            codexSkillStates: codexSkillStateOverrides,
            into: &capabilities,
            issues: &issues
        )
        if options.includeUserScope {
            scanCodexHooksConfig(
                at: options.codexConfigURL.deletingLastPathComponent().appendingPathComponent("hooks.json"),
                scope: .user,
                stateConfigURL: options.codexConfigURL,
                into: &capabilities,
                issues: &issues
            )
        }
        emitProgress("scan.codex.finish", path: root.appendingPathComponent(".codex").path, count: capabilities.count, options: options)

        emitProgress("scan.claude.start", path: root.appendingPathComponent(".claude").path, options: options)
        scanClaudeWorkspace(at: root, options: options, claudeSkillStates: claudeSkillStates, into: &capabilities, issues: &issues)
        if options.includeUserScope {
            for settingsURL in options.claudeSettingsURLs {
                scanClaudeSettings(
                    at: settingsURL,
                    scope: .user,
                    into: &capabilities,
                    issues: &issues
                )
            }
            scanUserAgentRoots(
                options: options,
                into: &capabilities,
                issues: &issues
            )
        }
        emitProgress("scan.claude.finish", path: root.appendingPathComponent(".claude").path, count: capabilities.count, options: options)

        emitProgress("scan.cursor.start", path: root.appendingPathComponent(".cursor").path, options: options)
        scanCursorRules(at: root, into: &capabilities, issues: &issues)
        emitProgress("scan.cursor.finish", path: root.appendingPathComponent(".cursor").path, count: capabilities.count, options: options)

        emitProgress("scan.mcp.start", path: root.appendingPathComponent(".mcp.json").path, options: options)
        scanMCPConfig(
            at: root.appendingPathComponent(".mcp.json"),
            scope: .project,
            disabledMcpjsonServerSettingsPaths: claudeDisabledMCPServerSettingsPaths,
            into: &capabilities,
            issues: &issues
        )
        emitProgress("scan.mcp.finish", path: root.appendingPathComponent(".mcp.json").path, count: capabilities.count, options: options)

        emitProgress("scan.agents.start", path: root.appendingPathComponent(".agents").path, options: options)
        scanAgentsWorkspace(
            at: root,
            options: options,
            skillsLock: projectSkillsLock,
            codexSkillStates: codexSkillStateOverrides,
            into: &capabilities,
            issues: &issues
        )
        emitProgress("scan.agents.finish", path: root.appendingPathComponent(".agents").path, count: capabilities.count, options: options)

        scanSkillFiles(at: root, options: options, into: &capabilities, issues: &issues, codexConfigPath: options.codexConfigURL.path, codexSkillStates: codexSkillStateOverrides)
        scanUserSkillRoots(
            projectRoot: root,
            options: options,
            globalSkillsLock: globalSkillsLock,
            codexSkillStates: codexSkillStateOverrides,
            claudeSkillStates: claudeSkillStates,
            into: &capabilities,
            issues: &issues
        )
        scanNativePluginRegistries(projectRoot: root, options: options, into: &capabilities, issues: &issues)

        emitProgress("scan.finish", path: root.path, count: capabilities.count, options: options)
        return ScanResult(
            projectRoot: root.path,
            capabilities: capabilities.sorted { $0.id < $1.id },
            issues: issues
        )
    }

    private func emitProgress(_ name: String, path: String, count: Int? = nil, options: ScanOptions) {
        options.progressHandler?(ScanProgressEvent(name: name, path: path, count: count))
    }

    private func validateProjectRoot(_ root: URL) throws {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: root.path, isDirectory: &isDirectory) else {
            throw OrbitaError.projectRootNotFound(root.path)
        }
        guard isDirectory.boolValue else {
            throw OrbitaError.projectRootIsNotDirectory(root.path)
        }
    }

    private func scanInstructionFiles(at root: URL, into capabilities: inout [Capability]) {
        let files = [
            ("AGENTS.md", "Agent instructions"),
            ("CLAUDE.md", "Claude Code instructions"),
            ("GEMINI.md", "Gemini instructions")
        ]

        for (fileName, displayName) in files {
            let url = root.appendingPathComponent(fileName)
            guard fileManager.fileExists(atPath: url.path) else { continue }
            capabilities.append(Capability(
                id: stableID(type: .instruction, path: url.path),
                name: displayName,
                type: .instruction,
                scope: .project,
                statuses: [.discovered],
                risks: [.info, .read],
                source: CapabilitySource(kind: "instruction", path: url.path),
                summary: fileName,
                metadata: fileMetadata(for: url)
            ))
        }
    }

    private func scanCodexWorkspace(
        at root: URL,
        options: ScanOptions,
        codexSkillStates: [String: Bool],
        into capabilities: inout [Capability],
        issues: inout [ScanIssue]
    ) {
        scanCodexMarkdownFiles(
            at: root.appendingPathComponent(".codex/commands"),
            type: .command,
            sourceKind: "codex-command",
            into: &capabilities,
            issues: &issues
        )
        scanCodexMarkdownFiles(
            at: root.appendingPathComponent(".codex/hooks"),
            type: .hook,
            sourceKind: "codex-hook",
            into: &capabilities,
            issues: &issues
        )
        scanSkillFiles(
            at: root.appendingPathComponent(".codex/skills"),
            options: options,
            into: &capabilities,
            issues: &issues,
            scope: .project,
            sourceKind: "codex-skill",
            projectRoot: root,
            codexConfigPath: root.appendingPathComponent(".codex/config.toml").path,
            codexSkillStates: codexSkillStates
        )
        scanCodexHooksConfig(
            at: root.appendingPathComponent(".codex/hooks.json"),
            scope: .project,
            stateConfigURL: root.appendingPathComponent(".codex/config.toml"),
            into: &capabilities,
            issues: &issues
        )
    }

    private func scanClaudeWorkspace(
        at root: URL,
        options: ScanOptions,
        claudeSkillStates: [String: ClaudeSkillOverrideState],
        into capabilities: inout [Capability],
        issues: inout [ScanIssue]
    ) {
        scanCodexMarkdownFiles(
            at: root.appendingPathComponent(".claude/commands"),
            type: .command,
            sourceKind: "claude-command",
            into: &capabilities,
            issues: &issues
        )
        scanClaudeSettings(
            at: root.appendingPathComponent(".claude/settings.json"),
            scope: .project,
            into: &capabilities,
            issues: &issues
        )
        scanClaudeSettings(
            at: root.appendingPathComponent(".claude/settings.local.json"),
            scope: .project,
            into: &capabilities,
            issues: &issues
        )
        scanSkillFiles(
            at: root.appendingPathComponent(".claude/skills"),
            options: options,
            into: &capabilities,
            issues: &issues,
            scope: .project,
            sourceKind: "claude-skill",
            projectRoot: root,
            claudeSkillStates: claudeSkillStates
        )
        scanAgentFiles(
            at: root.appendingPathComponent(".claude/agents"),
            options: options,
            into: &capabilities,
            issues: &issues,
            scope: .project,
            sourceKind: "claude-agent"
        )
    }

    private func scanClaudeSettings(
        at url: URL,
        scope: CapabilityScope,
        into capabilities: inout [Capability],
        issues: inout [ScanIssue]
    ) {
        guard fileManager.fileExists(atPath: url.path) else { return }
        let hookCount = scanHooksConfig(
            at: url,
            scope: scope,
            sourceKind: "claude-settings-hook",
            manager: "claude-code",
            into: &capabilities,
            issues: &issues
        )
        if hookCount > 0 {
            return
        }

        let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        let lowercased = text.lowercased()
        var risks: Set<RiskLevel> = [.info, .read]
        if lowercased.contains("\"hooks\"") || lowercased.contains("\"command\"") {
            risks.insert(.exec)
        }
        if lowercased.contains("\"env\"") || lowercased.contains("token") || lowercased.contains("secret") {
            risks.insert(.secret)
        }
        capabilities.append(Capability(
            id: stableID(type: .hook, path: url.path),
            name: "Claude Code settings",
            type: .hook,
            scope: scope,
            statuses: risks.contains(.exec) || risks.contains(.secret) ? [.discovered, .risky] : [.discovered],
            risks: risks.sorted { $0.rawValue < $1.rawValue },
            source: CapabilitySource(kind: "claude-settings", path: url.path),
            summary: "Claude Code project settings",
            metadata: fileMetadata(for: url)
        ))
    }

    private func scanCodexHooksConfig(
        at url: URL,
        scope: CapabilityScope,
        stateConfigURL: URL,
        into capabilities: inout [Capability],
        issues: inout [ScanIssue]
    ) {
        _ = scanHooksConfig(
            at: url,
            scope: scope,
            sourceKind: "codex-hook",
            manager: "codex",
            into: &capabilities,
            issues: &issues,
            stateConfigURL: stateConfigURL
        )
    }

    @discardableResult
    private func scanHooksConfig(
        at url: URL,
        scope: CapabilityScope,
        sourceKind: String,
        manager: String,
        into capabilities: inout [Capability],
        issues: inout [ScanIssue],
        stateConfigURL: URL? = nil,
        inheritedEnabled: Bool? = nil,
        pluginID: String? = nil,
        metadata baseMetadata: [String: String] = [:]
    ) -> Int {
        guard fileManager.fileExists(atPath: url.path) else { return 0 }
        guard let object = jsonObject(at: url) else {
            issues.append(ScanIssue(severity: .warning, path: url.path, message: "Hook config is not a JSON object"))
            return 0
        }
        let hooksObject = object["hooks"] as? [String: Any] ?? object
        let hookStates = stateConfigURL.map(codexHookStates) ?? [:]
        var scannedCount = 0

        for event in hooksObject.keys.sorted() {
            guard let entries = hooksObject[event] as? [Any] else { continue }
            for (entryIndex, entryValue) in entries.enumerated() {
                guard let entry = entryValue as? [String: Any] else { continue }
                let matcher = entry["matcher"] as? String
                let hooks = hookObjects(in: entry)
                for (hookIndex, hook) in hooks.enumerated() {
                    let descriptor = hookDescriptor(for: hook, baseMetadata: baseMetadata)
                    let pathKey = "\(url.path)#\(event):\(entryIndex):\(hookIndex)"
                    let stateKey = codexHookStateKey(
                        path: url.path,
                        event: event,
                        entryIndex: entryIndex,
                        hookIndex: hookIndex
                    )
                    let enabled = hookStates[stateKey] ?? inheritedEnabled
                    let risks = riskHints(forHook: hook)
                    var metadata = baseMetadata
                    metadata["manager"] = manager
                    metadata["event"] = event
                    metadata["matcher"] = matcher ?? ""
                    metadata["hookType"] = descriptor.kind
                    metadata["handlerKind"] = descriptor.kind
                    metadata["timeout"] = stringValue(hook["timeout"])
                    metadata["entryIndex"] = String(entryIndex)
                    metadata["hookIndex"] = String(hookIndex)
                    metadata["stateKey"] = stateKey
                    metadata["filter"] = hook["if"] as? String ?? ""
                    if sourceKind == "claude-settings-hook" {
                        metadata["claudeHookSettingsPath"] = url.path
                        metadata["claudeHookDeleteCommand"] = "Remove \(event) hook \(entryIndex):\(hookIndex) from \(url.path)"
                    }
                    descriptor.metadata.forEach { metadata[$0.key] = $0.value }

                    capabilities.append(Capability(
                        id: stableID(type: .hook, path: pathKey),
                        name: hookDisplayName(event: event, matcher: matcher, hostName: descriptor.hostName, kind: descriptor.kind),
                        type: .hook,
                        scope: scope,
                        statuses: hookStatuses(enabled: enabled, risks: risks),
                        risks: risks,
                        source: CapabilitySource(kind: sourceKind, path: url.path, packageName: baseMetadata["pluginName"]),
                        pluginID: pluginID,
                        summary: descriptor.summary,
                        metadata: fileMetadata(for: url, merging: metadata.filter { !$0.value.isEmpty })
                    ))
                    scannedCount += 1
                }
            }
        }
        return scannedCount
    }

    private func hookObjects(in entry: [String: Any]) -> [[String: Any]] {
        if let hooks = entry["hooks"] as? [[String: Any]] {
            return hooks
        }
        if entry["command"] != nil
            || entry["url"] != nil
            || entry["prompt"] != nil
            || entry["tool"] != nil
            || entry["server"] != nil
            || entry["agent"] != nil {
            return [entry]
        }
        return []
    }

    private struct HookHandlerDescriptor {
        var kind: String
        var hostName: String?
        var summary: String?
        var metadata: [String: String]
    }

    private struct HookCommandAnalysis {
        var hostName: String?
        var executable: String?
        var runner: String?
        var script: String?
    }

    private func hookDescriptor(for hook: [String: Any], baseMetadata: [String: String]) -> HookHandlerDescriptor {
        let kind = hookKind(for: hook)
        var metadata: [String: String] = [:]

        switch kind.lowercased() {
        case "command":
            let command = hook["command"] as? String ?? ""
            let analysis = analyzeHookCommand(command, pluginName: baseMetadata["pluginName"])
            metadata["command"] = command
            metadata["handlerHost"] = analysis.hostName ?? ""
            metadata["handlerExecutable"] = analysis.executable ?? ""
            metadata["handlerRunner"] = analysis.runner ?? ""
            metadata["handlerScript"] = analysis.script ?? ""
            return HookHandlerDescriptor(kind: kind, hostName: analysis.hostName, summary: command, metadata: metadata)
        case "http":
            let url = hook["url"] as? String ?? ""
            let host = URL(string: url)?.host
            metadata["url"] = url
            metadata["handlerHost"] = host ?? ""
            return HookHandlerDescriptor(kind: kind, hostName: host, summary: url, metadata: metadata)
        case "prompt":
            let prompt = hook["prompt"] as? String ?? ""
            metadata["prompt"] = prompt
            return HookHandlerDescriptor(kind: kind, hostName: "Prompt", summary: prompt, metadata: metadata)
        case "agent":
            let agentName = hook["agent"] as? String ?? hook["name"] as? String ?? "Agent"
            metadata["agent"] = agentName
            return HookHandlerDescriptor(kind: kind, hostName: humanizedHookHost(agentName), summary: agentName, metadata: metadata)
        case "mcp_tool":
            let toolName = hook["tool"] as? String ?? hook["name"] as? String ?? hook["server"] as? String ?? "MCP Tool"
            metadata["tool"] = toolName
            return HookHandlerDescriptor(kind: kind, hostName: humanizedHookHost(toolName), summary: toolName, metadata: metadata)
        default:
            let summary = hookSummaryValue(for: hook)
            return HookHandlerDescriptor(kind: kind, hostName: nil, summary: summary, metadata: metadata)
        }
    }

    private func hookKind(for hook: [String: Any]) -> String {
        if let type = hook["type"] as? String, !type.isEmpty {
            return type
        }
        if hook["command"] is String { return "command" }
        if hook["url"] is String { return "http" }
        if hook["prompt"] is String { return "prompt" }
        if hook["tool"] is String || hook["server"] is String { return "mcp_tool" }
        if hook["agent"] is String { return "agent" }
        return "hook"
    }

    private func hookDisplayName(event: String, matcher: String?, hostName: String?, kind: String) -> String {
        let eventName = {
            guard let matcher, !matcher.isEmpty else {
                return event
            }
            return "\(event) (\(matcher))"
        }()

        if let hostName, !hostName.isEmpty {
            return "\(hostName) - \(eventName)"
        }
        if kind != "command", kind != "hook" {
            return "\(humanizedHookHost(kind)) - \(eventName)"
        }
        return "\(eventName) hook"
    }

    private func hookSummaryValue(for hook: [String: Any]) -> String? {
        if let command = hook["command"] as? String {
            return command
        }
        if let url = hook["url"] as? String {
            return url
        }
        if let prompt = hook["prompt"] as? String {
            return prompt
        }
        return nil
    }

    private func analyzeHookCommand(_ command: String, pluginName: String?) -> HookCommandAnalysis {
        let words = normalizedCommandWords(from: command)
        guard let executable = words.first else {
            return HookCommandAnalysis(hostName: pluginName.map(humanizedHookHost), executable: nil, runner: nil, script: nil)
        }

        let executableName = fileStem(forShellToken: executable)
        let runnerNames: Set<String> = [
            "bash", "sh", "zsh", "fish",
            "python", "python3", "node", "ruby", "perl",
            "deno", "bun", "npx", "tsx", "uv", "swift"
        ]
        let runner = runnerNames.contains(executableName.lowercased()) ? executableName : nil
        let script: String?
        if runner == nil {
            script = executable
        } else if executableName.lowercased() == "swift" {
            script = nil
        } else if executableName.lowercased() == "npx" {
            script = scriptToken(in: words.dropFirst())
        } else {
            script = scriptToken(in: words.dropFirst())
        }
        let hostName = hookHostName(command: command, pluginName: pluginName, script: script, executable: executable)

        return HookCommandAnalysis(hostName: hostName, executable: executableName, runner: runner, script: script)
    }

    private func normalizedCommandWords(from command: String) -> [String] {
        var words = shellWords(from: command)
        while let first = words.first {
            if first == "env" {
                words.removeFirst()
                continue
            }
            if first.contains("="), !first.hasPrefix("/"), !first.hasPrefix("./"), !first.hasPrefix("../") {
                words.removeFirst()
                continue
            }
            break
        }
        return words
    }

    private func scriptToken(in tokens: ArraySlice<String>) -> String? {
        var skipNext = false
        for token in tokens {
            if skipNext {
                skipNext = false
                continue
            }
            if ["-c", "-lc", "-e", "-m"].contains(token) {
                return nil
            }
            if ["--require", "--loader", "--import", "--eval"].contains(token) {
                skipNext = true
                continue
            }
            if token.hasPrefix("-") {
                continue
            }
            return token
        }
        return nil
    }

    private func hookHostName(command: String, pluginName: String?, script: String?, executable: String) -> String {
        let lowercasedCommand = command.lowercased()
        if lowercasedCommand.contains("vibe-island-bridge")
            || lowercasedCommand.contains(".vibe-island/bin")
            || lowercasedCommand.contains("vibe island") {
            return "Vibe Island"
        }
        if lowercasedCommand.contains("claude-island-state.py")
            || lowercasedCommand.contains("claude island")
            || lowercasedCommand.contains("vibe-notch") {
            return "Vibe Notch"
        }
        if lowercasedCommand.contains("notchikko-hook.sh")
            || lowercasedCommand.contains(".notchikko/hooks") {
            return "Notchikko"
        }
        if lowercasedCommand.contains("clawd-hook.js") {
            return "Clawd On Desk"
        }
        if lowercasedCommand.contains("@dp/ab-agent-collect-event") {
            return "AB Agent Collect"
        }
        if lowercasedCommand.contains("@dp/ai-code-report")
            || lowercasedCommand.contains("ai-report-hook-run") {
            return "AI Code Report"
        }
        if let pluginName, !pluginName.isEmpty {
            return humanizedHookHost(pluginName)
        }
        if let script, !script.isEmpty {
            return humanizedHookHost(fileStem(forShellToken: script))
        }
        return humanizedHookHost(fileStem(forShellToken: executable))
    }

    private func shellWords(from command: String) -> [String] {
        var words: [String] = []
        var current = ""
        var quote: Character?
        var escaping = false

        func flush() {
            if !current.isEmpty {
                words.append(current)
                current = ""
            }
        }

        for character in command {
            if escaping {
                current.append(character)
                escaping = false
                continue
            }
            if character == "\\" {
                escaping = true
                continue
            }
            if let activeQuote = quote {
                if character == activeQuote {
                    quote = nil
                } else {
                    current.append(character)
                }
                continue
            }
            if character == "'" || character == "\"" {
                quote = character
                continue
            }
            if character.isWhitespace {
                flush()
                continue
            }
            current.append(character)
        }
        flush()
        return words
    }

    private func fileStem(forShellToken token: String) -> String {
        let trimmed = token.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        let lastComponent = trimmed.split(separator: "/").last.map(String.init) ?? trimmed
        let withoutExtension = (lastComponent as NSString).deletingPathExtension
        return withoutExtension.isEmpty ? lastComponent : withoutExtension
    }

    private func humanizedHookHost(_ value: String) -> String {
        let normalized = value
            .replacingOccurrences(of: "${CLAUDE_PLUGIN_ROOT}", with: "")
            .replacingOccurrences(of: "${PLUGIN_ROOT}", with: "")
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: ".", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return value }
        return normalized
            .split(separator: " ")
            .map { part in
                let lower = part.lowercased()
                switch lower {
                case "mcp":
                    return "MCP"
                case "http":
                    return "HTTP"
                case "url":
                    return "URL"
                case "cli":
                    return "CLI"
                default:
                    return lower.prefix(1).uppercased() + String(lower.dropFirst())
                }
            }
            .joined(separator: " ")
    }

    private func hookStatuses(enabled: Bool?, risks: [RiskLevel]) -> [CapabilityStatus] {
        var statuses = statusList(enabled: enabled)
        if risks.contains(.secret) || risks.contains(.network) {
            statuses.append(.risky)
        }
        return statuses
    }

    private func riskHints(forHook hook: [String: Any]) -> [RiskLevel] {
        var risks: Set<RiskLevel> = [.info, .read]
        let command = (hook["command"] as? String ?? "").lowercased()
        let url = (hook["url"] as? String ?? "").lowercased()
        let hookType = (hook["type"] as? String ?? "").lowercased()

        if !command.isEmpty || hookType == "command" {
            risks.insert(.exec)
        }
        if hook["env"] is [String: Any]
            || command.contains("token")
            || command.contains("secret")
            || command.contains("key=") {
            risks.insert(.secret)
        }
        if url.hasPrefix("http")
            || command.contains("http://")
            || command.contains("https://")
            || command.contains("curl ")
            || command.contains("npx ")
            || command.contains("npm ")
            || command.contains("pnpm ") {
            risks.insert(.network)
        }
        return risks.sorted { $0.rawValue < $1.rawValue }
    }

    private func codexHookStates(at url: URL) -> [String: Bool] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [:] }
        var states: [String: Bool] = [:]
        var currentKey: String?

        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[hooks.state.\""), line.hasSuffix("\"]") {
                currentKey = String(line.dropFirst("[hooks.state.\"".count).dropLast(2))
                continue
            }
            if line.hasPrefix("["), !line.hasPrefix("[hooks.state.\"") {
                currentKey = nil
                continue
            }
            guard let currentKey, line.hasPrefix("enabled"), let enabled = tomlBoolValue(from: line) else {
                continue
            }
            states[currentKey] = enabled
        }
        return states
    }

    private func codexHookStateKey(path: String, event: String, entryIndex: Int, hookIndex: Int) -> String {
        "\(path):\(codexHookEventStateName(event)):\(entryIndex):\(hookIndex)"
    }

    private func codexHookEventStateName(_ event: String) -> String {
        var result = ""
        for character in event {
            if character.isUppercase, !result.isEmpty {
                result.append("_")
            }
            result.append(character.lowercased())
        }
        return result.replacingOccurrences(of: "-", with: "_")
    }

    private func stringValue(_ value: Any?) -> String {
        guard let value else { return "" }
        return String(describing: value)
    }

    private func scanCodexMarkdownFiles(
        at directory: URL,
        type: CapabilityType,
        sourceKind: String,
        scope: CapabilityScope = .project,
        statuses: [CapabilityStatus] = [.discovered],
        risks: [RiskLevel]? = nil,
        packageName: String? = nil,
        pluginID: String? = nil,
        metadata baseMetadata: [String: String] = [:],
        into capabilities: inout [Capability],
        issues: inout [ScanIssue]
    ) {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: directory.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return
        }

        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            issues.append(ScanIssue(severity: .warning, path: directory.path, message: "Unable to enumerate Codex workspace files"))
            return
        }

        for case let url as URL in enumerator {
            guard ["md", "json", "toml"].contains(url.pathExtension.lowercased()) else { continue }
            let frontmatter = (try? String(contentsOf: url, encoding: .utf8)).flatMap(parseFrontmatter) ?? [:]
            var metadata = fileMetadata(for: url, merging: frontmatter)
            for (key, value) in baseMetadata where !value.isEmpty {
                metadata[key] = value
            }
            capabilities.append(Capability(
                id: stableID(type: type, path: url.path),
                name: frontmatter["name"] ?? url.deletingPathExtension().lastPathComponent,
                type: type,
                scope: scope,
                statuses: statuses,
                risks: risks ?? (type == .hook ? [.exec, .read] : [.info, .read]),
                source: CapabilitySource(kind: sourceKind, path: url.path, packageName: packageName),
                pluginID: pluginID,
                summary: frontmatter["description"],
                metadata: metadata
            ))
        }
    }

    private func scanCursorRules(at root: URL, into capabilities: inout [Capability], issues: inout [ScanIssue]) {
        scanLegacyCursorRules(at: root.appendingPathComponent(".cursorrules"), into: &capabilities)

        let rulesRoot = root.appendingPathComponent(".cursor/rules")
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: rulesRoot.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return
        }

        guard let enumerator = fileManager.enumerator(
            at: rulesRoot,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            issues.append(ScanIssue(severity: .warning, path: rulesRoot.path, message: "Unable to enumerate Cursor rules"))
            return
        }

        for case let url as URL in enumerator {
            guard ["md", "mdc"].contains(url.pathExtension.lowercased()) else { continue }
            capabilities.append(Capability(
                id: stableID(type: .rule, path: url.path),
                name: url.deletingPathExtension().lastPathComponent,
                type: .rule,
                scope: .project,
                statuses: [.discovered],
                risks: [.info, .read],
                source: CapabilitySource(kind: "cursor-rule", path: url.path),
                metadata: fileMetadata(for: url)
            ))
        }
    }

    private func scanLegacyCursorRules(at url: URL, into capabilities: inout [Capability]) {
        guard fileManager.fileExists(atPath: url.path) else { return }
        capabilities.append(Capability(
            id: stableID(type: .rule, path: url.path),
            name: "Legacy Cursor rules",
            type: .rule,
            scope: .project,
            statuses: [.discovered],
            risks: [.info, .read],
            source: CapabilitySource(kind: "legacy-cursor-rule", path: url.path),
            summary: ".cursorrules",
            metadata: fileMetadata(for: url)
        ))
    }

    private func scanMCPConfig(
        at url: URL,
        scope: CapabilityScope,
        disabledMcpjsonServerSettingsPaths: [String: String] = [:],
        into capabilities: inout [Capability],
        issues: inout [ScanIssue]
    ) {
        guard fileManager.fileExists(atPath: url.path) else { return }

        do {
            let data = try Data(contentsOf: url)
            let json = try JSONSerialization.jsonObject(with: data)
            guard let root = json as? [String: Any] else {
                issues.append(ScanIssue(severity: .warning, path: url.path, message: "MCP config is not an object"))
                return
            }

            let serverContainers = ["mcpServers", "servers"]
            for key in serverContainers {
                guard let servers = root[key] as? [String: Any] else { continue }
                for (serverName, value) in servers {
                    let server = value as? [String: Any] ?? [:]
                    let risks = riskHints(forMCPServer: server)
                    let disabledSettingsPath = disabledMcpjsonServerSettingsPaths[serverName]
                    let isDisabledForClaude = disabledSettingsPath != nil
                    var metadata = compactMetadata(server)
                    metadata["mcpServerName"] = serverName
                    metadata["mcpConfigPath"] = url.path
                    if scope == .project {
                        let claudeSettingsPath = disabledSettingsPath ?? url.deletingLastPathComponent().appendingPathComponent(".claude/settings.json").path
                        metadata["claudeMCPSettingsPath"] = claudeSettingsPath
                        metadata["claudeMCPEnabled"] = String(!isDisabledForClaude)
                        metadata["claudeMCPDisableCommand"] = "Add \(serverName) to disabledMcpjsonServers in \(claudeSettingsPath)"
                        metadata["claudeMCPEnableCommand"] = "Remove \(serverName) from disabledMcpjsonServers in \(claudeSettingsPath)"
                        metadata["claudeMCPDeleteCommand"] = "Remove \(serverName) from \(url.path)"
                    }
                    capabilities.append(Capability(
                        id: stableID(type: .mcpServer, path: "\(url.path)#\(serverName)"),
                        name: serverName,
                        type: .mcpServer,
                        scope: scope,
                        statuses: risks.contains(.secret) || risks.contains(.network) ? [.discovered, .risky] : [.discovered],
                        risks: risks,
                        source: CapabilitySource(kind: "mcp-config", path: url.path),
                        summary: "MCP server",
                        metadata: metadata
                    ))
                }
            }
        } catch {
            issues.append(ScanIssue(severity: .warning, path: url.path, message: "Unable to parse MCP config: \(error.localizedDescription)"))
        }
    }

    private func riskHints(forMCPServer server: [String: Any]) -> [RiskLevel] {
        var risks: Set<RiskLevel> = [.info]

        if server["command"] is String {
            risks.insert(.exec)
        }
        if server["env"] is [String: Any] {
            risks.insert(.secret)
        }
        if let url = server["url"] as? String, url.hasPrefix("http") {
            risks.insert(.network)
        }
        if let transport = server["transport"] as? String, transport.lowercased().contains("http") || transport.lowercased().contains("sse") {
            risks.insert(.network)
        }

        return risks.sorted { $0.rawValue < $1.rawValue }
    }

    private func compactMetadata(_ object: [String: Any]) -> [String: String] {
        var metadata: [String: String] = [:]
        for key in ["command", "url", "transport"] {
            if let value = object[key] as? String {
                metadata[key] = value
            }
        }
        if let args = object["args"] as? [String], !args.isEmpty {
            metadata["args"] = args.joined(separator: " ")
        }
        return metadata
    }

    private func scanAgentsWorkspace(
        at root: URL,
        options: ScanOptions,
        skillsLock: SkillsLockFile?,
        codexSkillStates: [String: Bool],
        into capabilities: inout [Capability],
        issues: inout [ScanIssue]
    ) {
        let agentsRoot = root.appendingPathComponent(".agents")
        let manifest = agentsRoot.appendingPathComponent("manifest.json")
        if fileManager.fileExists(atPath: manifest.path) {
            if !isInternalEnvironmentRoot(root) {
                capabilities.append(Capability(
                    id: stableID(type: .instruction, path: manifest.path),
                    name: ".agents manifest",
                    type: .instruction,
                    scope: .project,
                    statuses: [.enabled],
                    risks: [.info, .read],
                    source: CapabilitySource(kind: "agents-manifest", path: manifest.path)
                ))
            }
            scanAgentsManifestEntries(at: manifest, into: &capabilities, issues: &issues)
        }

        let skillsRoot = agentsRoot.appendingPathComponent("skills")
        scanSkillFiles(
            at: skillsRoot,
            options: options,
            into: &capabilities,
            issues: &issues,
            scope: .project,
            sourceKind: "agents-skill",
            projectRoot: root,
            skillsLock: skillsLock,
            skillsCanonicalRoot: skillsRoot,
            codexConfigPath: options.codexConfigURL.path,
            codexSkillStates: codexSkillStates
        )

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: skillsRoot.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return
        }

        do {
            let entries = try fileManager.contentsOfDirectory(at: skillsRoot, includingPropertiesForKeys: [.isSymbolicLinkKey])
            for entry in entries {
                let values = try entry.resourceValues(forKeys: [.isSymbolicLinkKey])
                guard values.isSymbolicLink == true else { continue }
                let destination = try fileManager.destinationOfSymbolicLink(atPath: entry.path)
                let resolved = resolveSymlink(destination: destination, from: entry.deletingLastPathComponent())
                if !fileManager.fileExists(atPath: resolved.path) {
                    capabilities.append(Capability(
                        id: stableID(type: .skill, path: entry.path),
                        name: entry.lastPathComponent,
                        type: .skill,
                        scope: .project,
                        statuses: [.broken],
                        risks: [.read],
                        source: CapabilitySource(kind: "agents-symlink", path: entry.path),
                        summary: "Broken symlink",
                        metadata: ["target": destination]
                    ))
                }
            }
        } catch {
            issues.append(ScanIssue(severity: .warning, path: skillsRoot.path, message: "Unable to inspect .agents skills: \(error.localizedDescription)"))
        }
    }

    private func isInternalEnvironmentRoot(_ root: URL) -> Bool {
        root.pathComponents.suffix(2).joined(separator: "/") == ".orbita/this-mac"
    }

    private func scanAgentsManifestEntries(at url: URL, into capabilities: inout [Capability], issues: inout [ScanIssue]) {
        do {
            let data = try Data(contentsOf: url)
            let json = try JSONSerialization.jsonObject(with: data)
            guard let root = json as? [String: Any] else {
                issues.append(ScanIssue(severity: .warning, path: url.path, message: ".agents manifest is not an object"))
                return
            }
            guard let entries = root["capabilities"] as? [[String: Any]] else {
                return
            }

            for entry in entries {
                guard let id = entry["id"] as? String,
                      let name = entry["name"] as? String,
                      let rawType = entry["type"] as? String,
                      let type = CapabilityType(rawValue: rawType),
                      let status = entry["status"] as? String,
                      let sourcePath = entry["sourcePath"] as? String else {
                    continue
                }
                capabilities.append(Capability(
                    id: "agents-intent:\(id)",
                    name: name,
                    type: type,
                    scope: .project,
                    statuses: [.discovered],
                    risks: [.info, .read],
                    source: CapabilitySource(kind: "agents-intent", path: url.path),
                    summary: "Project capability intent",
                    metadata: [
                        "capabilityID": id,
                        "manifestStatus": status,
                        "sourcePath": sourcePath
                    ]
                ))
            }
        } catch {
            issues.append(ScanIssue(severity: .warning, path: url.path, message: "Unable to parse .agents manifest: \(error.localizedDescription)"))
        }
    }

    private func resolveSymlink(destination: String, from directory: URL) -> URL {
        if destination.hasPrefix("/") {
            return URL(fileURLWithPath: destination).standardizedFileURL
        }
        return directory.appendingPathComponent(destination).standardizedFileURL
    }

    private func scanUserAgentRoots(
        options: ScanOptions,
        into capabilities: inout [Capability],
        issues: inout [ScanIssue]
    ) {
        for root in options.userAgentRoots {
            scanAgentFiles(
                at: root.standardizedFileURL.resolvingSymlinksInPath(),
                options: options,
                into: &capabilities,
                issues: &issues,
                scope: .user,
                sourceKind: "claude-agent"
            )
        }
    }

    private func scanAgentFiles(
        at root: URL,
        options: ScanOptions,
        into capabilities: inout [Capability],
        issues: inout [ScanIssue],
        scope: CapabilityScope,
        sourceKind: String,
        packageName: String? = nil,
        pluginID: String? = nil,
        inheritedEnabled: Bool? = nil,
        metadata baseMetadata: [String: String] = [:]
    ) {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return
        }

        emitProgress("scan.agents-files.start", path: root.path, options: options)

        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            issues.append(ScanIssue(severity: .warning, path: root.path, message: "Unable to enumerate agent files"))
            emitProgress("scan.agents-files.failed", path: root.path, options: options)
            return
        }

        var count = 0
        for case let url as URL in enumerator {
            guard url.pathExtension.lowercased() == "md" else { continue }
            count += 1
            let frontmatter = (try? String(contentsOf: url, encoding: .utf8)).flatMap(parseFrontmatter) ?? [:]
            var metadata = fileMetadata(for: url, merging: frontmatter)
            for (key, value) in baseMetadata where !value.isEmpty {
                metadata[key] = value
            }
            metadata["agentName"] = frontmatter["name"] ?? url.deletingPathExtension().lastPathComponent
            metadata["tools"] = frontmatter["tools"] ?? ""
            metadata["disallowedTools"] = frontmatter["disallowedTools"] ?? ""
            metadata["model"] = frontmatter["model"] ?? ""
            metadata["permissionMode"] = frontmatter["permissionMode"] ?? ""
            metadata["mcpServers"] = frontmatter["mcpServers"] ?? ""

            capabilities.append(Capability(
                id: stableID(type: .agent, path: url.path),
                name: frontmatter["name"] ?? url.deletingPathExtension().lastPathComponent,
                type: .agent,
                scope: scope,
                statuses: statusList(enabled: inheritedEnabled ?? true),
                risks: riskHints(forAgentFrontmatter: frontmatter, scope: scope),
                source: CapabilitySource(kind: sourceKind, path: url.path, packageName: packageName),
                pluginID: pluginID,
                summary: frontmatter["description"],
                metadata: metadata.filter { !$0.value.isEmpty }
            ))
        }

        emitProgress("scan.agents-files.finish", path: root.path, count: count, options: options)
    }

    private func riskHints(forAgentFrontmatter frontmatter: [String: String], scope: CapabilityScope) -> [RiskLevel] {
        var risks: Set<RiskLevel> = [.info, .read]
        let tools = (frontmatter["tools"] ?? "").lowercased()
        let disallowedTools = (frontmatter["disallowedTools"] ?? "").lowercased()
        let permissionMode = (frontmatter["permissionMode"] ?? "").lowercased()
        let mcpServers = (frontmatter["mcpServers"] ?? "").lowercased()

        if tools.contains("bash") || tools.contains("agent(") || tools == "agent" {
            risks.insert(.exec)
        }
        if tools.contains("write")
            || tools.contains("edit")
            || permissionMode.contains("acceptedits")
            || permissionMode.contains("bypasspermissions") {
            risks.insert(.write)
        }
        if !mcpServers.isEmpty || tools.contains("mcp__") || disallowedTools.contains("mcp__") {
            risks.insert(.network)
        }
        if scope == .user {
            risks.insert(.global)
        }

        return risks.sorted { $0.rawValue < $1.rawValue }
    }

    private func scanSkillFiles(
        at root: URL,
        options: ScanOptions,
        into capabilities: inout [Capability],
        issues: inout [ScanIssue],
        scope: CapabilityScope = .project,
        sourceKind: String = "skill",
        projectRoot: URL? = nil,
        skillsLock: SkillsLockFile? = nil,
        skillsCanonicalRoot: URL? = nil,
        codexConfigPath: String? = nil,
        codexPluginStates: [String: Bool] = [:],
        codexSkillStates: [String: Bool] = [:],
        claudeSkillStates: [String: ClaudeSkillOverrideState] = [:],
        forcedPackageInfo: (packageName: String, pluginID: String)? = nil,
        inheritedEnabled: Bool? = nil,
        metadata baseMetadata: [String: String] = [:]
    ) {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return
        }

        emitProgress("scan.skills.start", path: root.path, options: options)

        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ) else {
            issues.append(ScanIssue(severity: .warning, path: root.path, message: "Unable to enumerate project files"))
            emitProgress("scan.skills.failed", path: root.path, options: options)
            return
        }

        var count = 0
        for case let url as URL in enumerator {
            let last = url.lastPathComponent
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            let isDirectory = values?.isDirectory ?? false
            let isSymbolicLink = values?.isSymbolicLink ?? false
            if isDirectory && shouldSkipSkillDirectory(url, scanRoot: root, options: options) {
                enumerator.skipDescendants()
                continue
            }

            if isSymbolicLink {
                let skillFile = url.appendingPathComponent("SKILL.md")
                var isSkillDirectory: ObjCBool = false
                if fileManager.fileExists(atPath: skillFile.path, isDirectory: &isSkillDirectory), !isSkillDirectory.boolValue {
                    count += 1
                    if count > options.maxSkillFiles {
                        issues.append(ScanIssue(severity: .warning, path: root.path, message: "Stopped after \(options.maxSkillFiles) skill files"))
                        break
                    }
                    capabilities.append(scanSkill(
                        at: skillFile,
                        projectRoot: projectRoot ?? root,
                        scope: scope,
                        sourceKind: sourceKind,
                        skillsLock: skillsLock,
                        skillsCanonicalRoot: skillsCanonicalRoot,
                        codexConfigPath: codexConfigPath,
                        codexPluginStates: codexPluginStates,
                        codexSkillStates: codexSkillStates,
                        claudeSkillStates: claudeSkillStates,
                        forcedPackageInfo: forcedPackageInfo,
                        inheritedEnabled: inheritedEnabled,
                        metadata: baseMetadata
                    ))
                }
                enumerator.skipDescendants()
                continue
            }

            guard last == "SKILL.md" else { continue }
            count += 1
            if count > options.maxSkillFiles {
                issues.append(ScanIssue(severity: .warning, path: root.path, message: "Stopped after \(options.maxSkillFiles) skill files"))
                break
            }

            capabilities.append(scanSkill(
                at: url,
                projectRoot: projectRoot ?? root,
                scope: scope,
                sourceKind: sourceKind,
                skillsLock: skillsLock,
                skillsCanonicalRoot: skillsCanonicalRoot,
                codexConfigPath: codexConfigPath,
                codexPluginStates: codexPluginStates,
                codexSkillStates: codexSkillStates,
                claudeSkillStates: claudeSkillStates,
                forcedPackageInfo: forcedPackageInfo,
                inheritedEnabled: inheritedEnabled,
                metadata: baseMetadata
            ))
        }

        emitProgress("scan.skills.finish", path: root.path, count: count, options: options)
    }

    private func scanRootSkill(
        at url: URL,
        projectRoot: URL,
        scope: CapabilityScope,
        sourceKind: String,
        packageInfo: (packageName: String, pluginID: String),
        inheritedEnabled: Bool?,
        metadata baseMetadata: [String: String],
        into capabilities: inout [Capability]
    ) {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory), !isDirectory.boolValue else {
            return
        }
        capabilities.append(scanSkill(
            at: url,
            projectRoot: projectRoot,
            scope: scope,
            sourceKind: sourceKind,
            skillsLock: nil,
            skillsCanonicalRoot: nil,
            codexConfigPath: nil,
            codexPluginStates: [:],
            codexSkillStates: [:],
            claudeSkillStates: [:],
            forcedPackageInfo: packageInfo,
            inheritedEnabled: inheritedEnabled,
            metadata: baseMetadata
        ))
    }

    private func shouldSkipSkillDirectory(_ url: URL, scanRoot: URL, options: ScanOptions) -> Bool {
        if options.ignoredDirectoryNames.contains(url.lastPathComponent) {
            return true
        }

        let rootPath = scanRoot.standardizedFileURL.path
        let urlPath = url.standardizedFileURL.path
        guard urlPath.hasPrefix(rootPath + "/") else {
            return false
        }
        let relative = String(urlPath.dropFirst(rootPath.count + 1))
        let components = relative.split(separator: "/").map(String.init)
        guard let testsIndex = components.firstIndex(of: "Tests"),
              testsIndex < components.count - 1 else {
            return false
        }
        return components[(testsIndex + 1)...].contains("Fixtures")
    }

    private func scanUserSkillRoots(
        projectRoot: URL,
        options: ScanOptions,
        globalSkillsLock: SkillsLockFile?,
        codexSkillStates: [String: Bool],
        claudeSkillStates: [String: ClaudeSkillOverrideState],
        into capabilities: inout [Capability],
        issues: inout [ScanIssue]
    ) {
        guard options.includeUserScope else { return }
        let codexStates = codexPluginStates(at: options.codexConfigURL)
        for root in options.userSkillRoots {
            let standardizedRoot = root.standardizedFileURL.resolvingSymlinksInPath()
            let sourceKind = userSkillSourceKind(for: standardizedRoot)
            let lock = sourceKind == "agents-skill"
                ? skillsLockForUserAgentsRoot(standardizedRoot, fallback: globalSkillsLock)
                : nil
            if standardizedRoot.path == options.codexPluginCacheRoot.standardizedFileURL.resolvingSymlinksInPath().path {
                let manifests = latestCodexPluginManifests(at: standardizedRoot, scope: .user, issues: &issues)
                for manifest in manifests {
                    scanSkillFiles(
                        at: codexPluginVersionRoot(for: manifest).appendingPathComponent("skills"),
                        options: options,
                        into: &capabilities,
                        issues: &issues,
                        scope: .user,
                        sourceKind: sourceKind,
                        projectRoot: projectRoot,
                        skillsLock: nil,
                        skillsCanonicalRoot: nil,
                        codexConfigPath: options.codexConfigURL.path,
                        codexPluginStates: codexStates,
                        codexSkillStates: codexSkillStates,
                        claudeSkillStates: claudeSkillStates
                    )
                }
                continue
            }
            scanSkillFiles(
                at: standardizedRoot,
                options: options,
                into: &capabilities,
                issues: &issues,
                scope: .user,
                sourceKind: sourceKind,
                projectRoot: projectRoot,
                skillsLock: lock,
                skillsCanonicalRoot: sourceKind == "agents-skill" ? standardizedRoot : nil,
                codexConfigPath: options.codexConfigURL.path,
                codexPluginStates: codexStates,
                codexSkillStates: codexSkillStates,
                claudeSkillStates: claudeSkillStates
            )
        }
    }

    private func skillsLockForUserAgentsRoot(_ root: URL, fallback: SkillsLockFile?) -> SkillsLockFile? {
        let sibling = root.deletingLastPathComponent().appendingPathComponent(".skill-lock.json")
        return SkillsLockReader.read(at: sibling) ?? fallback
    }

    private func userSkillSourceKind(for root: URL) -> String {
        let components = root.pathComponents
        if components.contains(".agents") {
            return "agents-skill"
        }
        if components.contains(".claude") {
            return "claude-skill"
        }
        if containsPathComponentPair(".codex", "skills", in: components) {
            return "codex-skill"
        }
        return "user-skill"
    }

    private func containsPathComponentPair(_ first: String, _ second: String, in components: [String]) -> Bool {
        guard components.count >= 2 else { return false }
        for index in 0..<(components.count - 1) {
            if components[index] == first, components[index + 1] == second {
                return true
            }
        }
        return false
    }

    private func scanSkill(
        at url: URL,
        projectRoot: URL,
        scope: CapabilityScope,
        sourceKind: String,
        skillsLock: SkillsLockFile?,
        skillsCanonicalRoot: URL?,
        codexConfigPath: String?,
        codexPluginStates: [String: Bool],
        codexSkillStates: [String: Bool],
        claudeSkillStates: [String: ClaudeSkillOverrideState],
        forcedPackageInfo: (packageName: String, pluginID: String)? = nil,
        inheritedEnabled: Bool? = nil,
        metadata baseMetadata: [String: String] = [:]
    ) -> Capability {
        let frontmatter = (try? String(contentsOf: url, encoding: .utf8)).flatMap(parseFrontmatter) ?? [:]
        let parentName = url.deletingLastPathComponent().lastPathComponent
        let name = frontmatter["name"] ?? parentName
        let inferredPackageInfo = packageInfo(for: url, projectRoot: projectRoot)
        let packageInfo = forcedPackageInfo ?? inferredPackageInfo
        let codexCacheInfo = forcedPackageInfo == nil ? codexPluginCacheInfo(for: url) : nil
        var metadata = fileMetadata(for: url, merging: frontmatter)
        for (key, value) in baseMetadata where !value.isEmpty {
            metadata[key] = value
        }
        var statuses: [CapabilityStatus]
        if sourceKind == "agents-skill" {
            metadata["manager"] = "agents-skills"
            metadata["pluginSelector"] = name
            metadata["checkCommand"] = scope == .user ? "npx skills list -g" : "npx skills list"
            metadata["updateCommand"] = "npx skills update \(shellQuoted(name)) \(scope == .user ? "-g" : "-p") -y"
            metadata["deleteCommand"] = "npx skills remove \(shellQuoted(name)) \(scope == .user ? "-g" : "-p") -y"
            metadata["lifecycleNote"] = "Skills CLI updates installed .agents skills by name; disabling is modeled as removal or .agents manifest intent."
            enrichSkillsCLIMetadata(
                &metadata,
                capabilityName: name,
                skillDirectory: url.deletingLastPathComponent(),
                scope: scope,
                projectRoot: projectRoot,
                lock: skillsLock,
                canonicalRoot: skillsCanonicalRoot
            )
            statuses = [.enabled]
        } else if sourceKind == "codex-skill" {
            metadata["manager"] = "codex"
            metadata["codexSkillName"] = name
            metadata["lifecycleNote"] = "Codex native skill lifecycle uses .codex/skills for project skills and CODEX_HOME/skills for user skills."
            statuses = [.enabled]
        } else if let codexCacheInfo, scope == .user {
            let selector = "\(codexCacheInfo.pluginName)@\(codexCacheInfo.marketplace)"
            let configPath = codexConfigPath ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/config.toml").path
            metadata["manager"] = "codex"
            metadata["pluginSelector"] = selector
            metadata["marketplace"] = codexCacheInfo.marketplace
            metadata["installedVersion"] = codexCacheInfo.version
            metadata["configPath"] = configPath
            metadata["checkCommand"] = "codex plugin marketplace upgrade \(shellQuoted(codexCacheInfo.marketplace)) && codex plugin list --marketplace \(shellQuoted(codexCacheInfo.marketplace))"
            metadata["updateCommand"] = "codex plugin marketplace upgrade \(shellQuoted(codexCacheInfo.marketplace)) && codex plugin add \(shellQuoted(selector))"
            metadata["enableMode"] = "plugin-add"
            metadata["enableCommand"] = "codex plugin add \(shellQuoted(selector))"
            metadata["disableMode"] = "config"
            metadata["disableCommand"] = "Set [plugins.\"\(selector)\"].enabled = false in \(configPath)"
            metadata["deleteCommand"] = "codex plugin remove \(shellQuoted(selector))"
            metadata["lifecycleNote"] = "This skill is bundled inside the \(pluginDisplayName(codexCacheInfo.pluginName)) Codex plugin; enable, disable, update, and delete apply to the plugin package."
            statuses = statusList(enabled: codexPluginStates[selector])
        } else if sourceKind == "claude-skill" {
            let overrideState = claudeSkillStates[name]
            let settingsPath = overrideState?.settingsPath ?? claudeSettingsPath(forSkill: url, scope: scope, projectRoot: projectRoot)
            let enabled = overrideState?.enabled ?? true
            metadata["claudeSkillName"] = name
            metadata["claudeSettingsPath"] = settingsPath
            metadata["claudeSkillEnabled"] = String(enabled)
            metadata["claudeSkillDeletePath"] = url.deletingLastPathComponent().path
            metadata["claudeSkillDisableCommand"] = "Set skillOverrides.\(name) = \"off\" in \(settingsPath)"
            metadata["claudeSkillEnableCommand"] = "Remove skillOverrides.\(name) from \(settingsPath)"
            metadata["claudeSkillDeleteCommand"] = "Remove \(url.deletingLastPathComponent().path)"
            metadata["lifecycleNote"] = "Claude Code native skill lifecycle uses skillOverrides for enablement; delete removes this skill directory."
            statuses = enabled ? [.enabled] : [.disabled]
        } else if forcedPackageInfo != nil {
            statuses = statusList(enabled: inheritedEnabled)
        } else {
            statuses = [.discovered]
        }

        let usesPluginLifecycle = forcedPackageInfo != nil
            || codexCacheInfo != nil
            || sourceKind.contains("plugin-skill")
            || (metadata["manager"] == "codex" && metadata["pluginSelector"] != nil)
        if !usesPluginLifecycle {
            if let configPath = codexConfigPath {
                metadata["codexConfigPath"] = configPath
                metadata["codexSkillConfigPath"] = url.path
                metadata["codexDisableCommand"] = "Set [[skills.config]] path = \(shellQuoted(url.path)) enabled = false in \(configPath)"
                metadata["codexEnableCommand"] = "Set [[skills.config]] path = \(shellQuoted(url.path)) enabled = true in \(configPath)"
            }

            if let codexSkillEnabled = codexSkillState(for: url, states: codexSkillStates) {
                let configPath = codexConfigPath ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/config.toml").path
                metadata["codexSkillEnabled"] = String(codexSkillEnabled)
                metadata["codexConfigPath"] = configPath
                metadata["codexSkillConfigPath"] = url.path
                metadata["codexDisableCommand"] = "Set [[skills.config]] path = \(shellQuoted(url.path)) enabled = false in \(configPath)"
                metadata["codexEnableCommand"] = "Set [[skills.config]] path = \(shellQuoted(url.path)) enabled = true in \(configPath)"
                if codexSkillEnabled == false, sourceKind == "user-skill" || sourceKind == "codex-skill" {
                    statuses = [.disabled]
                }
            }
        }

        return Capability(
            id: stableID(type: .skill, path: url.path),
            name: name,
            type: .skill,
            scope: scope,
            statuses: statuses,
            risks: scope == .user ? [.read, .global] : [.read],
            source: CapabilitySource(kind: sourceKind, path: url.path, packageName: packageInfo?.packageName),
            pluginID: packageInfo?.pluginID,
            summary: frontmatter["description"],
            metadata: metadata
        )
    }

    private struct SkillsAgentInstall {
        var id: String
        var displayName: String
        var relationship: String
        var path: String
    }

    private func enrichSkillsCLIMetadata(
        _ metadata: inout [String: String],
        capabilityName: String,
        skillDirectory: URL,
        scope: CapabilityScope,
        projectRoot: URL,
        lock: SkillsLockFile?,
        canonicalRoot: URL?
    ) {
        let canonicalDirectory = skillsCanonicalDirectory(
            capabilityName: capabilityName,
            skillDirectory: skillDirectory,
            canonicalRoot: canonicalRoot
        )

        if let canonicalDirectory {
            metadata["skillsCanonicalPath"] = canonicalDirectory.path
            metadata["skillsCanonicalStatus"] = directoryExists(canonicalDirectory) ? "present" : "missing"
        }

        if let lock {
            metadata["skillsLockPath"] = lock.path
            if let entry = skillsLockEntry(in: lock, capabilityName: capabilityName, skillDirectory: skillDirectory) {
                metadata["skillsLockStatus"] = "locked"
                metadata["skillsLockSource"] = entry.source
                metadata["skillsLockSourceType"] = entry.sourceType
                let installCommand = skillsInstallCommand(
                    source: entry.sourceUrl ?? entry.source,
                    capabilityName: capabilityName,
                    scope: scope
                )
                metadata["skillsInstallCommand"] = installCommand
                metadata["installCommand"] = installCommand
                if let ref = entry.ref, !ref.isEmpty {
                    metadata["skillsLockRef"] = ref
                }
                if let sourceUrl = entry.sourceUrl, !sourceUrl.isEmpty {
                    metadata["skillsLockSourceURL"] = sourceUrl
                }
                if let skillPath = entry.skillPath, !skillPath.isEmpty {
                    metadata["skillsLockSkillPath"] = skillPath
                }
                if let hash = entry.updateHash {
                    metadata["skillsLockHash"] = hash
                }
                if let installedAt = entry.installedAt, !installedAt.isEmpty {
                    metadata["skillsLockInstalledAt"] = installedAt
                }
                if let updatedAt = entry.updatedAt, !updatedAt.isEmpty {
                    metadata["skillsLockUpdatedAt"] = updatedAt
                }
                if let pluginName = entry.pluginName, !pluginName.isEmpty {
                    metadata["skillsLockPluginName"] = pluginName
                }
            } else {
                metadata["skillsLockStatus"] = "missing-entry"
            }
        } else {
            metadata["skillsLockStatus"] = "missing-lock"
        }

        let installs = skillsAgentInstallations(
            capabilityName: capabilityName,
            skillDirectory: skillDirectory,
            scope: scope,
            projectRoot: projectRoot,
            canonicalDirectory: canonicalDirectory,
            canonicalRoot: canonicalDirectory?.deletingLastPathComponent()
        )
        guard !installs.isEmpty else { return }
        metadata["skillsInstalledAgentIDs"] = installs.map(\.id).joined(separator: ",")
        metadata["skillsInstalledAgents"] = installs.map(\.displayName).joined(separator: ", ")
        metadata["skillsInstallTargets"] = installs
            .map { "\($0.id)=\($0.relationship):\($0.path)" }
            .joined(separator: "\n")
    }

    private func skillsLockEntry(
        in lock: SkillsLockFile,
        capabilityName: String,
        skillDirectory: URL
    ) -> SkillsLockEntry? {
        if let entry = lock.entries[capabilityName] {
            return entry
        }
        if let entry = lock.entries[skillDirectory.lastPathComponent] {
            return entry
        }

        let normalizedName = skillsSanitizedName(capabilityName)
        return lock.entries.first { key, _ in
            skillsSanitizedName(key) == normalizedName
        }?.value
    }

    private func skillsInstallCommand(source: String, capabilityName: String, scope: CapabilityScope) -> String {
        let scopeFlag = scope == .user ? " -g" : ""
        return "npx skills add \(shellQuoted(source)) --skill \(shellQuoted(capabilityName))\(scopeFlag) -y"
    }

    private func skillsCanonicalDirectory(
        capabilityName: String,
        skillDirectory: URL,
        canonicalRoot: URL?
    ) -> URL? {
        guard let canonicalRoot else { return nil }
        let root = canonicalRoot.standardizedFileURL.resolvingSymlinksInPath()
        let parent = skillDirectory.deletingLastPathComponent().standardizedFileURL.resolvingSymlinksInPath()
        if parent.path == root.path {
            return skillDirectory
        }

        let sanitized = root.appendingPathComponent(skillsSanitizedName(capabilityName))
        if directoryExists(sanitized) {
            return sanitized
        }
        return root.appendingPathComponent(skillDirectory.lastPathComponent)
    }

    private func skillsAgentInstallations(
        capabilityName: String,
        skillDirectory: URL,
        scope: CapabilityScope,
        projectRoot: URL,
        canonicalDirectory: URL?,
        canonicalRoot: URL?
    ) -> [SkillsAgentInstall] {
        let candidateNames = uniquePreservingOrder([
            skillDirectory.lastPathComponent,
            skillsSanitizedName(capabilityName)
        ])
        let canonicalPath = canonicalDirectory?.standardizedFileURL.resolvingSymlinksInPath().path
        var installs: [SkillsAgentInstall] = []

        for agent in SkillsAgentCatalog.agents {
            guard let base = skillsAgentBaseURL(agent: agent, scope: scope, projectRoot: projectRoot) else {
                continue
            }
            for name in candidateNames {
                let candidate = base.appendingPathComponent(name)
                guard let relationship = skillsInstallRelationship(
                    candidate: candidate,
                    canonicalPath: canonicalPath,
                    canonicalDirectory: canonicalDirectory
                ) else {
                    continue
                }
                installs.append(SkillsAgentInstall(
                    id: agent.id,
                    displayName: agent.displayName,
                    relationship: relationship,
                    path: candidate.path
                ))
                break
            }
        }

        return installs.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }

    private func skillsAgentBaseURL(
        agent: SkillsAgentDefinition,
        scope: CapabilityScope,
        projectRoot: URL
    ) -> URL? {
        if scope == .user {
            guard let globalSkillsDir = agent.globalSkillsDir else { return nil }
            return URL(fileURLWithPath: globalSkillsDir)
        }
        return projectRoot.appendingPathComponent(agent.projectSkillsDir)
    }

    private func skillsInstallRelationship(
        candidate: URL,
        canonicalPath: String?,
        canonicalDirectory: URL?
    ) -> String? {
        if let destination = try? fileManager.destinationOfSymbolicLink(atPath: candidate.path) {
            let resolved = resolveSymlink(destination: destination, from: candidate.deletingLastPathComponent())
            guard fileManager.fileExists(atPath: resolved.path) else {
                return "broken-symlink"
            }
            if let canonicalPath,
               resolved.standardizedFileURL.resolvingSymlinksInPath().path == canonicalPath {
                return "symlink"
            }
            return "symlink-other"
        }

        guard directoryExists(candidate) else { return nil }
        if let canonicalDirectory,
           candidate.standardizedFileURL.resolvingSymlinksInPath().path == canonicalDirectory.standardizedFileURL.resolvingSymlinksInPath().path {
            return "canonical"
        }
        return "copy"
    }

    private func directoryExists(_ url: URL) -> Bool {
        var isDirectory = ObjCBool(false)
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    private func uniquePreservingOrder(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for value in values where !value.isEmpty {
            if seen.insert(value).inserted {
                result.append(value)
            }
        }
        return result
    }

    private func codexSkillState(for url: URL, states: [String: Bool]) -> Bool? {
        let candidates = [
            url.path,
            url.standardizedFileURL.path,
            url.standardizedFileURL.resolvingSymlinksInPath().path
        ]
        for candidate in candidates {
            if let state = states[candidate] {
                return state
            }
        }
        return nil
    }

    private func claudeSettingsStateURLs(projectRoot: URL, options: ScanOptions) -> [URL] {
        var urls = options.includeUserScope ? options.claudeSettingsURLs : []
        urls.append(projectRoot.appendingPathComponent(".claude/settings.json"))
        urls.append(projectRoot.appendingPathComponent(".claude/settings.local.json"))
        return uniqueURLs(urls)
    }

    private func claudeSkillOverrideStates(at urls: [URL]) -> [String: ClaudeSkillOverrideState] {
        urls.reduce(into: [String: ClaudeSkillOverrideState]()) { result, url in
            guard let object = jsonObject(at: url),
                  let overrides = object["skillOverrides"] as? [String: Any] else {
                return
            }
            for (name, value) in overrides {
                if let string = value as? String {
                    result[name] = ClaudeSkillOverrideState(enabled: string.lowercased() != "off", settingsPath: url.path)
                } else if let bool = value as? Bool {
                    result[name] = ClaudeSkillOverrideState(enabled: bool, settingsPath: url.path)
                }
            }
        }
    }

    private func claudeDisabledMcpjsonServerSettingsPaths(at urls: [URL]) -> [String: String] {
        urls.reduce(into: [String: String]()) { result, url in
            guard let object = jsonObject(at: url),
                  let servers = object["disabledMcpjsonServers"] as? [String] else {
                return
            }
            for server in servers {
                result[server] = url.path
            }
        }
    }

    private func uniqueURLs(_ urls: [URL]) -> [URL] {
        var seen: Set<String> = []
        var result: [URL] = []
        for url in urls {
            let key = url.standardizedFileURL.path
            if seen.insert(key).inserted {
                result.append(url)
            }
        }
        return result
    }

    private func claudeSettingsPath(forSkill url: URL, scope: CapabilityScope, projectRoot: URL) -> String {
        if scope == .user,
           let claudeRoot = ancestorDirectory(named: ".claude", from: url) {
            return claudeRoot.appendingPathComponent("settings.json").path
        }
        return projectRoot.appendingPathComponent(".claude/settings.json").path
    }

    private func ancestorDirectory(named name: String, from url: URL) -> URL? {
        var current = url.deletingLastPathComponent().standardizedFileURL
        while current.path != current.deletingLastPathComponent().path {
            if current.lastPathComponent == name {
                return current
            }
            current = current.deletingLastPathComponent()
        }
        return current.lastPathComponent == name ? current : nil
    }

    private func scanNativePluginRegistries(
        projectRoot: URL,
        options: ScanOptions,
        into capabilities: inout [Capability],
        issues: inout [ScanIssue]
    ) {
        let projectCodexConfig = projectRoot.appendingPathComponent(".codex/config.toml")
        let projectCodexStates = codexPluginStates(at: projectCodexConfig)
        scanCodexPluginManifests(
            at: projectRoot.appendingPathComponent("plugins"),
            scope: .project,
            configPath: projectCodexConfig.path,
            states: projectCodexStates,
            into: &capabilities,
            issues: &issues
        )

        guard options.includeUserScope else { return }

        let codexConfig = options.codexConfigURL
        let codexStates = codexPluginStates(at: codexConfig)
        scanCodexPluginManifests(
            at: options.codexPluginCacheRoot,
            scope: .user,
            configPath: codexConfig.path,
            states: codexStates,
            into: &capabilities,
            issues: &issues
        )

        scanClaudeInstalledPlugins(
            projectRoot: projectRoot,
            options: options,
            installedPluginsURL: options.claudeInstalledPluginsURL,
            settingsURLs: options.claudeSettingsURLs + [
                projectRoot.appendingPathComponent(".claude/settings.json"),
                projectRoot.appendingPathComponent(".claude/settings.local.json")
            ],
            into: &capabilities,
            issues: &issues
        )
    }

    private struct CodexPluginManifest {
        var selector: String
        var marketplace: String
        var pluginName: String
        var version: String
        var manifestURL: URL
        var pluginRoot: URL
        var metadata: [String: String]
    }

    private func scanCodexPluginManifests(
        at root: URL,
        scope: CapabilityScope,
        configPath: String,
        states: [String: Bool],
        into capabilities: inout [Capability],
        issues: inout [ScanIssue]
    ) {
        let root = root.standardizedFileURL.resolvingSymlinksInPath()
        var isDirectory = ObjCBool(false)
        guard fileManager.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return
        }

        let manifests = latestCodexPluginManifests(at: root, scope: scope, issues: &issues)
        for manifest in manifests {
            let enabled = states[manifest.selector]
            var metadata = manifest.metadata
            metadata["manager"] = "codex"
            metadata["pluginSelector"] = manifest.selector
            metadata["marketplace"] = manifest.marketplace
            metadata["installedVersion"] = manifest.version
            metadata["configPath"] = configPath
            if scope == .user {
                metadata["checkCommand"] = "codex plugin marketplace upgrade \(shellQuoted(manifest.marketplace)) && codex plugin list --marketplace \(shellQuoted(manifest.marketplace))"
                metadata["updateCommand"] = "codex plugin marketplace upgrade \(shellQuoted(manifest.marketplace)) && codex plugin add \(shellQuoted(manifest.selector))"
                metadata["enableMode"] = "plugin-add"
                metadata["enableCommand"] = "codex plugin add \(shellQuoted(manifest.selector))"
                metadata["deleteCommand"] = "codex plugin remove \(shellQuoted(manifest.selector))"
                metadata["lifecycleNote"] = "Codex Desktop requires codex plugin add to install the plugin cache and mark it enabled; disabling keeps the cache and writes enabled=false."
            } else {
                metadata["enableMode"] = "config"
                metadata["enableCommand"] = "Set [plugins.\"\(manifest.selector)\"].enabled = true in \(configPath)"
                metadata["lifecycleNote"] = "Project-local Codex plugin enablement is tracked in the project config.toml."
            }
            metadata["disableMode"] = "config"
            metadata["disableCommand"] = "Set [plugins.\"\(manifest.selector)\"].enabled = false in \(configPath)"

            let pluginID = "plugin:codex-cache:\(normalized(manifest.marketplace)):\(normalized(manifest.pluginName))"
            capabilities.append(Capability(
                id: pluginID,
                name: pluginDisplayName(manifest.pluginName),
                type: .plugin,
                scope: scope,
                statuses: statusList(enabled: enabled),
                risks: scope == .user ? [.info, .read, .global] : [.info, .read],
                source: CapabilitySource(kind: "codex-plugin", path: manifest.pluginRoot.path, packageName: manifest.pluginName),
                summary: metadata["description"],
                metadata: fileMetadata(for: manifest.manifestURL, merging: metadata)
            ))

            scanPluginHooks(
                pluginRoot: codexPluginVersionRoot(for: manifest),
                scope: scope,
                sourceKind: "codex-plugin-hook",
                manager: "codex",
                enabled: enabled,
                pluginID: pluginID,
                pluginSelector: manifest.selector,
                pluginName: manifest.pluginName,
                marketplace: manifest.marketplace,
                installedVersion: manifest.version,
                into: &capabilities,
                issues: &issues
            )
        }
    }

    private func latestCodexPluginManifests(
        at root: URL,
        scope: CapabilityScope,
        issues: inout [ScanIssue]
    ) -> [CodexPluginManifest] {
        var isDirectory = ObjCBool(false)
        guard fileManager.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return []
        }

        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: []
        ) else {
            issues.append(ScanIssue(severity: .warning, path: root.path, message: "Unable to enumerate Codex plugin cache"))
            return []
        }

        var latestBySelector: [String: CodexPluginManifest] = [:]
        for case let url as URL in enumerator {
            guard url.lastPathComponent == "plugin.json",
                  [".codex-plugin", ".claude-plugin"].contains(url.deletingLastPathComponent().lastPathComponent),
                  let manifest = codexPluginManifest(at: url, cacheRoot: root, scope: scope) else {
                continue
            }

            if let existing = latestBySelector[manifest.selector] {
                if isNewerPluginManifest(manifest, than: existing) {
                    latestBySelector[manifest.selector] = manifest
                }
            } else {
                latestBySelector[manifest.selector] = manifest
            }
        }

        return latestBySelector.values.sorted(by: { $0.selector < $1.selector })
    }

    private func codexPluginVersionRoot(for manifest: CodexPluginManifest) -> URL {
        manifest.manifestURL.deletingLastPathComponent().deletingLastPathComponent()
    }

    private func codexPluginManifest(at url: URL, cacheRoot: URL, scope: CapabilityScope) -> CodexPluginManifest? {
        guard let object = jsonObject(at: url) else { return nil }
        let rootPath = cacheRoot.standardizedFileURL.resolvingSymlinksInPath().path
        let urlPath = url.standardizedFileURL.resolvingSymlinksInPath().path
        guard urlPath.hasPrefix(rootPath + "/") else { return nil }
        let relativeComponents = String(urlPath.dropFirst(rootPath.count + 1))
            .split(separator: "/")
            .map(String.init)
        var pluginRoot = url.deletingLastPathComponent().deletingLastPathComponent()
        let marketplace: String
        let pluginName: String
        let version: String
        if scope == .user, relativeComponents.count >= 5 {
            marketplace = relativeComponents[0]
            let pathPluginName = relativeComponents[relativeComponents.count - 4]
            let pathVersion = relativeComponents[relativeComponents.count - 3]
            pluginName = object["name"] as? String ?? pathPluginName
            version = object["version"] as? String ?? pathVersion
            pluginRoot = url
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
        } else if relativeComponents.count >= 3 {
            marketplace = "project"
            pluginName = object["name"] as? String ?? pluginRoot.lastPathComponent
            version = object["version"] as? String ?? "local"
        } else {
            return nil
        }
        let selector = "\(pluginName)@\(marketplace)"
        let interface = object["interface"] as? [String: Any]
        let displayName = interface?["displayName"] as? String
        let shortDescription = interface?["shortDescription"] as? String
        var metadata: [String: String] = [
            "description": (shortDescription ?? object["description"] as? String ?? ""),
            "displayName": displayName ?? pluginDisplayName(pluginName),
            "manifestKind": url.deletingLastPathComponent().lastPathComponent
        ].filter { !$0.value.isEmpty }
        if let repository = object["repository"] as? String {
            metadata["repository"] = repository
        }
        if let homepage = object["homepage"] as? String {
            metadata["homepage"] = homepage
        }
        return CodexPluginManifest(
            selector: selector,
            marketplace: marketplace,
            pluginName: pluginName,
            version: version,
            manifestURL: url,
            pluginRoot: pluginRoot,
            metadata: metadata
        )
    }

    private func isNewerPluginManifest(_ candidate: CodexPluginManifest, than existing: CodexPluginManifest) -> Bool {
        let versionComparison = candidate.version.compare(existing.version, options: [.caseInsensitive, .numeric])
        if versionComparison != .orderedSame {
            return versionComparison == .orderedDescending
        }
        let candidateIsPluginInstall = candidate.pluginRoot.pathComponents.contains { $0.hasPrefix("plugin-install-") }
        let existingIsPluginInstall = existing.pluginRoot.pathComponents.contains { $0.hasPrefix("plugin-install-") }
        if candidateIsPluginInstall != existingIsPluginInstall {
            return !candidateIsPluginInstall
        }
        return candidate.manifestURL.path > existing.manifestURL.path
    }

    private func codexPluginStates(at url: URL) -> [String: Bool] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [:] }
        var states: [String: Bool] = [:]
        var currentPlugin: String?

        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[plugins.\""), line.hasSuffix("\"]") {
                currentPlugin = String(line.dropFirst("[plugins.\"".count).dropLast(2))
                continue
            }
            if line.hasPrefix("["), !line.hasPrefix("[plugins.\"") {
                currentPlugin = nil
                continue
            }
            guard let plugin = currentPlugin, line.hasPrefix("enabled") else { continue }
            let value = line.split(separator: "=", maxSplits: 1).dropFirst().first?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            if value == "true" {
                states[plugin] = true
            } else if value == "false" {
                states[plugin] = false
            }
        }
        return states
    }

    private func codexSkillStates(at url: URL) -> [String: Bool] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [:] }
        var states: [String: Bool] = [:]
        var inSkillConfig = false
        var currentPath: String?
        var currentEnabled: Bool?

        func flushCurrent() {
            guard let currentPath, let currentEnabled else { return }
            let standardized = URL(fileURLWithPath: currentPath)
                .standardizedFileURL
                .resolvingSymlinksInPath()
                .path
            states[currentPath] = currentEnabled
            states[standardized] = currentEnabled
        }

        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line == "[[skills.config]]" {
                flushCurrent()
                inSkillConfig = true
                currentPath = nil
                currentEnabled = nil
                continue
            }
            if line.hasPrefix("["), line != "[[skills.config]]" {
                flushCurrent()
                inSkillConfig = false
                currentPath = nil
                currentEnabled = nil
                continue
            }
            guard inSkillConfig else { continue }

            if line.hasPrefix("path") {
                currentPath = tomlStringValue(from: line)
            } else if line.hasPrefix("enabled") {
                currentEnabled = tomlBoolValue(from: line)
            }
        }

        flushCurrent()
        return states
    }

    private func tomlStringValue(from line: String) -> String? {
        guard let value = line.split(separator: "=", maxSplits: 1).dropFirst().first else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count >= 2,
           let first = trimmed.first,
           let last = trimmed.last,
           (first == "\"" && last == "\"" || first == "'" && last == "'") {
            return String(trimmed.dropFirst().dropLast())
        }
        return trimmed.isEmpty ? nil : trimmed
    }

    private func tomlBoolValue(from line: String) -> Bool? {
        guard let value = line.split(separator: "=", maxSplits: 1).dropFirst().first else { return nil }
        switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "true":
            return true
        case "false":
            return false
        default:
            return nil
        }
    }

    private func scanClaudeInstalledPlugins(
        projectRoot: URL,
        options: ScanOptions,
        installedPluginsURL: URL,
        settingsURLs: [URL],
        into capabilities: inout [Capability],
        issues: inout [ScanIssue]
    ) {
        guard let root = jsonObject(at: installedPluginsURL),
              let plugins = root["plugins"] as? [String: Any] else {
            return
        }

        let enabledPlugins = settingsURLs.reduce(into: [String: Bool]()) { result, url in
            for (key, value) in claudeEnabledPlugins(at: url) {
                result[key] = value
            }
        }
        let isEnvironmentScan = isInternalEnvironmentRoot(projectRoot)

        for (selector, value) in plugins.sorted(by: { $0.key < $1.key }) {
            guard let installs = value as? [[String: Any]] else { continue }
            for install in installs {
                let scopeValue = install["scope"] as? String ?? "user"
                let scope = capabilityScope(forClaudeScope: scopeValue)
                let projectPath = install["projectPath"] as? String
                if isEnvironmentScan, scope == .project {
                    continue
                }
                if !isEnvironmentScan, scope != .user, projectPath != projectRoot.path {
                    continue
                }
                guard let installPath = install["installPath"] as? String else { continue }
                guard fileManager.fileExists(atPath: installPath) else {
                    issues.append(ScanIssue(severity: .warning, path: installPath, message: "Claude plugin registry points to a missing install path"))
                    continue
                }
                let enabled = enabledPlugins[selector]
                let pluginName = selector.split(separator: "@", maxSplits: 1).first.map(String.init) ?? selector
                let marketplace = selector.split(separator: "@", maxSplits: 1).dropFirst().first.map(String.init) ?? ""
                var metadata: [String: String] = [
                    "manager": "claude-code",
                    "pluginSelector": selector,
                    "marketplace": marketplace,
                    "installedVersion": install["version"] as? String ?? "",
                    "installedAt": install["installedAt"] as? String ?? "",
                    "lastUpdated": install["lastUpdated"] as? String ?? "",
                    "managerScope": scopeValue,
                    "projectPath": projectPath ?? "",
                    "checkCommand": "(claude plugin update \(shellQuoted(selector)) --scope \(shellQuoted(scopeValue)) --dry-run 2>/dev/null) || claude plugin list --json --available",
                    "enableCommand": "claude plugin enable \(shellQuoted(selector)) --scope \(shellQuoted(scopeValue))",
                    "disableCommand": "claude plugin disable \(shellQuoted(selector)) --scope \(shellQuoted(scopeValue))",
                    "updateCommand": "claude plugin update \(shellQuoted(selector)) --scope \(shellQuoted(scopeValue))",
                    "deleteCommand": "claude plugin remove \(shellQuoted(selector)) --scope \(shellQuoted(scopeValue)) -y",
                    "lifecycleNote": "Claude Code CLI exposes native plugin enable, disable, update, delete, and list commands."
                ].filter { !$0.value.isEmpty }
                if let gitCommitSha = install["gitCommitSha"] as? String {
                    metadata["gitCommitSha"] = gitCommitSha
                }

                let pluginID = "plugin:claude:\(normalized(selector)):\(scopeValue):\(normalized(projectPath ?? "global"))"
                capabilities.append(Capability(
                    id: pluginID,
                    name: pluginDisplayName(pluginName),
                    type: .plugin,
                    scope: scope,
                    statuses: statusList(enabled: enabled),
                    risks: scope == .user ? [.info, .read, .global] : [.info, .read],
                    source: CapabilitySource(kind: "claude-plugin", path: installPath, packageName: pluginName),
                    summary: "Claude Code plugin",
                    metadata: metadata
                ))

                let pluginRoot = URL(fileURLWithPath: installPath)
                let childMetadata = [
                    "manager": "claude-code",
                    "pluginSelector": selector,
                    "pluginName": pluginName,
                    "marketplace": marketplace,
                    "installedVersion": install["version"] as? String ?? "",
                    "managerScope": scopeValue,
                    "projectPath": projectPath ?? "",
                    "checkCommand": "(claude plugin update \(shellQuoted(selector)) --scope \(shellQuoted(scopeValue)) --dry-run 2>/dev/null) || claude plugin list --json --available",
                    "enableCommand": "claude plugin enable \(shellQuoted(selector)) --scope \(shellQuoted(scopeValue))",
                    "disableCommand": "claude plugin disable \(shellQuoted(selector)) --scope \(shellQuoted(scopeValue))",
                    "updateCommand": "claude plugin update \(shellQuoted(selector)) --scope \(shellQuoted(scopeValue))",
                    "deleteCommand": "claude plugin remove \(shellQuoted(selector)) --scope \(shellQuoted(scopeValue)) -y",
                    "lifecycleNote": "This capability is bundled inside the \(pluginDisplayName(pluginName)) Claude Code plugin; lifecycle actions apply to the plugin package."
                ].filter { !$0.value.isEmpty }
                scanSkillFiles(
                    at: pluginRoot.appendingPathComponent("skills"),
                    options: options,
                    into: &capabilities,
                    issues: &issues,
                    scope: scope,
                    sourceKind: "claude-plugin-skill",
                    projectRoot: projectRoot,
                    forcedPackageInfo: (pluginName, pluginID),
                    inheritedEnabled: enabled,
                    metadata: childMetadata
                )
                scanRootSkill(
                    at: pluginRoot.appendingPathComponent("SKILL.md"),
                    projectRoot: projectRoot,
                    scope: scope,
                    sourceKind: "claude-plugin-skill",
                    packageInfo: (pluginName, pluginID),
                    inheritedEnabled: enabled,
                    metadata: childMetadata,
                    into: &capabilities
                )
                scanCodexMarkdownFiles(
                    at: pluginRoot.appendingPathComponent("commands"),
                    type: .command,
                    sourceKind: "claude-plugin-command",
                    scope: scope,
                    statuses: statusList(enabled: enabled),
                    packageName: pluginName,
                    pluginID: pluginID,
                    metadata: childMetadata,
                    into: &capabilities,
                    issues: &issues
                )
                scanAgentFiles(
                    at: pluginRoot.appendingPathComponent("agents"),
                    options: options,
                    into: &capabilities,
                    issues: &issues,
                    scope: scope,
                    sourceKind: "claude-plugin-agent",
                    packageName: pluginName,
                    pluginID: pluginID,
                    inheritedEnabled: enabled,
                    metadata: childMetadata
                )
                scanPluginHooks(
                    pluginRoot: pluginRoot,
                    scope: scope,
                    sourceKind: "claude-plugin-hook",
                    manager: "claude-code",
                    enabled: enabled,
                    pluginID: pluginID,
                    scopeValue: scopeValue,
                    pluginSelector: selector,
                    pluginName: pluginName,
                    marketplace: marketplace,
                    installedVersion: install["version"] as? String ?? "",
                    into: &capabilities,
                    issues: &issues
                )
            }
        }

        if fileManager.fileExists(atPath: installedPluginsURL.path),
           plugins.isEmpty {
            issues.append(ScanIssue(severity: .warning, path: installedPluginsURL.path, message: "Claude plugin registry contains no plugins"))
        }
    }

    private func claudeEnabledPlugins(at url: URL) -> [String: Bool] {
        guard let object = jsonObject(at: url),
              let enabledPlugins = object["enabledPlugins"] as? [String: Any] else {
            return [:]
        }
        return enabledPlugins.compactMapValues { $0 as? Bool }
    }

    private func scanPluginHooks(
        pluginRoot: URL,
        scope: CapabilityScope,
        sourceKind: String,
        manager: String,
        enabled: Bool?,
        pluginID: String,
        scopeValue: String? = nil,
        pluginSelector: String,
        pluginName: String,
        marketplace: String,
        installedVersion: String,
        into capabilities: inout [Capability],
        issues: inout [ScanIssue]
    ) {
        let hookURLs = [
            pluginRoot.appendingPathComponent("hooks/hooks.json"),
            pluginRoot.appendingPathComponent("hooks.json"),
            pluginRoot.appendingPathComponent(".claude-plugin/plugin.json")
        ]
        var scannedPaths = Set<String>()
        for hookURL in hookURLs {
            let standardizedPath = hookURL.standardizedFileURL.resolvingSymlinksInPath().path
            guard !scannedPaths.contains(standardizedPath) else { continue }
            scannedPaths.insert(standardizedPath)
            var metadata = [
                "pluginSelector": pluginSelector,
                "pluginName": pluginName,
                "marketplace": marketplace,
                "installedVersion": installedVersion
            ]
            if manager == "claude-code" {
                let pluginScope = scopeValue ?? scope.rawValue
                metadata["managerScope"] = pluginScope
                metadata["checkCommand"] = "(claude plugin update \(shellQuoted(pluginSelector)) --scope \(shellQuoted(pluginScope)) --dry-run 2>/dev/null) || claude plugin list --json --available"
                metadata["enableCommand"] = "claude plugin enable \(shellQuoted(pluginSelector)) --scope \(shellQuoted(pluginScope))"
                metadata["disableCommand"] = "claude plugin disable \(shellQuoted(pluginSelector)) --scope \(shellQuoted(pluginScope))"
                metadata["updateCommand"] = "claude plugin update \(shellQuoted(pluginSelector)) --scope \(shellQuoted(pluginScope))"
                metadata["deleteCommand"] = "claude plugin remove \(shellQuoted(pluginSelector)) --scope \(shellQuoted(pluginScope)) -y"
                metadata["lifecycleNote"] = "This capability is bundled inside the \(pluginDisplayName(pluginName)) Claude Code plugin; lifecycle actions apply to the plugin package."
            }
            _ = scanHooksConfig(
                at: hookURL,
                scope: scope,
                sourceKind: sourceKind,
                manager: manager,
                into: &capabilities,
                issues: &issues,
                inheritedEnabled: enabled,
                pluginID: pluginID,
                metadata: metadata
            )
        }
    }

    private func capabilityScope(forClaudeScope value: String) -> CapabilityScope {
        switch value {
        case "user":
            return .user
        case "project", "local":
            return .project
        default:
            return .installed
        }
    }

    private func statusList(enabled: Bool?) -> [CapabilityStatus] {
        switch enabled {
        case .some(true):
            return [.enabled]
        case .some(false):
            return [.disabled]
        case .none:
            return [.discovered]
        }
    }

    private func jsonObject(at url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return object
    }

    private func fileMetadata(for url: URL, merging metadata: [String: String] = [:]) -> [String: String] {
        var result = metadata
        if let hash = contentHash(for: url) {
            result["contentHash"] = hash
        }
        if let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
           let modifiedAt = attributes[.modificationDate] as? Date {
            result["modifiedAt"] = ISO8601DateFormatter().string(from: modifiedAt)
        }
        return result
    }

    private func contentHash(for url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func parseFrontmatter(_ text: String) -> [String: String] {
        var lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard lines.first == "---" else { return [:] }
        lines.removeFirst()

        var result: [String: String] = [:]
        for line in lines {
            if line == "---" { break }
            guard let separator = line.firstIndex(of: ":") else { continue }
            let key = line[..<separator].trimmingCharacters(in: .whitespaces)
            let value = line[line.index(after: separator)...].trimmingCharacters(in: .whitespacesAndNewlines)
            if !key.isEmpty, !value.isEmpty {
                result[key] = value.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            }
        }
        return result
    }

    private func packageInfo(for url: URL, projectRoot: URL) -> (packageName: String, pluginID: String)? {
        let components = url.pathComponents
        if let nodeModulesIndex = components.firstIndex(of: "node_modules"),
           nodeModulesIndex + 1 < components.count {
            let first = components[nodeModulesIndex + 1]
            let packageName: String
            if first.hasPrefix("@"), nodeModulesIndex + 2 < components.count {
                packageName = "\(first)/\(components[nodeModulesIndex + 2])"
            } else {
                packageName = first
            }

            return (packageName, "plugin:\(normalized(packageName))")
        }

        guard let cacheInfo = codexPluginCacheInfo(for: url) else {
            return nil
        }

        return (cacheInfo.pluginName, cacheInfo.pluginID)
    }

    private func codexPluginCacheInfo(for url: URL) -> (marketplace: String, pluginName: String, version: String, pluginID: String)? {
        let components = url.pathComponents
        guard let cacheIndex = codexPluginCacheIndex(in: components),
              cacheIndex + 3 < components.count else {
            return nil
        }
        let marketplace = components[cacheIndex + 1]
        if let manifest = nearestCodexPluginManifest(from: url, cacheIndex: cacheIndex, components: components) {
            let pluginID = "plugin:codex-cache:\(normalized(marketplace)):\(normalized(manifest.pluginName))"
            return (marketplace, manifest.pluginName, manifest.version, pluginID)
        }

        let suffix = Array(components[(cacheIndex + 1)...])
        let pluginName: String
        let version: String
        if let skillsIndex = suffix.firstIndex(of: "skills"), skillsIndex >= 3 {
            pluginName = suffix[skillsIndex - 2]
            version = suffix[skillsIndex - 1]
        } else if suffix.count >= 4, suffix[1].hasPrefix("plugin-install-") {
            pluginName = suffix[2]
            version = suffix[3]
        } else {
            pluginName = suffix[1]
            version = suffix[2]
        }
        let pluginID = "plugin:codex-cache:\(normalized(marketplace)):\(normalized(pluginName))"
        return (marketplace, pluginName, version, pluginID)
    }

    private func nearestCodexPluginManifest(
        from url: URL,
        cacheIndex: Int,
        components: [String]
    ) -> (pluginName: String, version: String)? {
        let cacheRootPath = NSString.path(withComponents: Array(components[...cacheIndex]))
        var directory = url
        if directory.pathExtension == "md" || directory.lastPathComponent.contains(".") {
            directory.deleteLastPathComponent()
        }

        while directory.path.hasPrefix(cacheRootPath + "/") {
            for manifestDirectory in [".codex-plugin", ".claude-plugin"] {
                let manifestURL = directory
                    .appendingPathComponent(manifestDirectory)
                    .appendingPathComponent("plugin.json")
                guard let object = jsonObject(at: manifestURL) else { continue }
                let pluginName = object["name"] as? String ?? directory.deletingLastPathComponent().lastPathComponent
                let version = object["version"] as? String ?? directory.lastPathComponent
                return (pluginName, version)
            }
            let parent = directory.deletingLastPathComponent()
            guard parent.path != directory.path else { break }
            directory = parent
        }
        return nil
    }

    private func codexPluginCacheIndex(in components: [String]) -> Int? {
        components.indices.first { index in
            index >= 2
                && components[index] == "cache"
                && components[index - 1] == "plugins"
                && components[index - 2] == ".codex"
        }
    }
}

func stableID(type: CapabilityType, path: String) -> String {
    "\(type.rawValue):\(path)"
}

func normalized(_ value: String) -> String {
    value
        .lowercased()
        .replacingOccurrences(of: "@", with: "")
        .replacingOccurrences(of: "/", with: "-")
        .replacingOccurrences(of: "_", with: "-")
}

func pluginDisplayName(_ rawName: String) -> String {
    let raw = rawName.split(separator: "/").last.map(String.init) ?? rawName
    let trimmed = raw
        .replacingOccurrences(of: "-skills", with: "")
        .replacingOccurrences(of: "-plugin", with: "")
        .replacingOccurrences(of: "agent-", with: "")
    return trimmed
        .split(separator: "-")
        .map { word in word.prefix(1).uppercased() + String(word.dropFirst()) }
        .joined(separator: " ")
}

func shellQuoted(_ value: String) -> String {
    "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
}
