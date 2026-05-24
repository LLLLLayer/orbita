import Foundation
import CryptoKit

public struct ScanOptions: Sendable {
    public var includeUserScope: Bool
    public var maxSkillFiles: Int
    public var userSkillRoots: [URL]
    public var ignoredDirectoryNames: Set<String>
    public var progressHandler: (@Sendable (ScanProgressEvent) -> Void)?

    public init(
        includeUserScope: Bool = true,
        maxSkillFiles: Int = 200,
        userSkillRoots: [URL]? = nil,
        ignoredDirectoryNames: Set<String> = Self.defaultIgnoredDirectoryNames,
        progressHandler: (@Sendable (ScanProgressEvent) -> Void)? = nil
    ) {
        self.includeUserScope = includeUserScope
        self.maxSkillFiles = maxSkillFiles
        self.userSkillRoots = userSkillRoots ?? Self.defaultUserSkillRoots()
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

    public static let defaultIgnoredDirectoryNames: Set<String> = [
        ".build",
        ".git",
        ".swiftpm",
        ".xcodeproj",
        ".xcworkspace",
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

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func scan(projectRoot: URL, options: ScanOptions = ScanOptions()) throws -> ScanResult {
        let root = projectRoot.standardizedFileURL.resolvingSymlinksInPath()
        emitProgress("scan.start", path: root.path, options: options)
        try validateProjectRoot(root)

        var capabilities: [Capability] = []
        var issues: [ScanIssue] = []

        emitProgress("scan.instructions.start", path: root.path, options: options)
        scanInstructionFiles(at: root, into: &capabilities)
        emitProgress("scan.instructions.finish", path: root.path, count: capabilities.count, options: options)

        emitProgress("scan.codex.start", path: root.appendingPathComponent(".codex").path, options: options)
        scanCodexWorkspace(at: root, into: &capabilities, issues: &issues)
        emitProgress("scan.codex.finish", path: root.appendingPathComponent(".codex").path, count: capabilities.count, options: options)

        emitProgress("scan.claude.start", path: root.appendingPathComponent(".claude").path, options: options)
        scanClaudeWorkspace(at: root, options: options, into: &capabilities, issues: &issues)
        emitProgress("scan.claude.finish", path: root.appendingPathComponent(".claude").path, count: capabilities.count, options: options)

        emitProgress("scan.cursor.start", path: root.appendingPathComponent(".cursor").path, options: options)
        scanCursorRules(at: root, into: &capabilities, issues: &issues)
        emitProgress("scan.cursor.finish", path: root.appendingPathComponent(".cursor").path, count: capabilities.count, options: options)

        emitProgress("scan.mcp.start", path: root.appendingPathComponent(".mcp.json").path, options: options)
        scanMCPConfig(at: root.appendingPathComponent(".mcp.json"), scope: .project, into: &capabilities, issues: &issues)
        emitProgress("scan.mcp.finish", path: root.appendingPathComponent(".mcp.json").path, count: capabilities.count, options: options)

        emitProgress("scan.agents.start", path: root.appendingPathComponent(".agents").path, options: options)
        scanAgentsWorkspace(at: root, options: options, into: &capabilities, issues: &issues)
        emitProgress("scan.agents.finish", path: root.appendingPathComponent(".agents").path, count: capabilities.count, options: options)

        scanSkillFiles(at: root, options: options, into: &capabilities, issues: &issues)
        scanUserSkillRoots(projectRoot: root, options: options, into: &capabilities, issues: &issues)

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

    private func scanCodexWorkspace(at root: URL, into capabilities: inout [Capability], issues: inout [ScanIssue]) {
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
    }

    private func scanClaudeWorkspace(at root: URL, options: ScanOptions, into capabilities: inout [Capability], issues: inout [ScanIssue]) {
        scanCodexMarkdownFiles(
            at: root.appendingPathComponent(".claude/commands"),
            type: .command,
            sourceKind: "claude-command",
            into: &capabilities,
            issues: &issues
        )
        scanClaudeSettings(
            at: root.appendingPathComponent(".claude/settings.json"),
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
            projectRoot: root
        )
    }

    private func scanClaudeSettings(at url: URL, into capabilities: inout [Capability], issues: inout [ScanIssue]) {
        guard fileManager.fileExists(atPath: url.path) else { return }
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
            scope: .project,
            statuses: risks.contains(.exec) || risks.contains(.secret) ? [.discovered, .risky] : [.discovered],
            risks: risks.sorted { $0.rawValue < $1.rawValue },
            source: CapabilitySource(kind: "claude-settings", path: url.path),
            summary: "Claude Code project settings",
            metadata: fileMetadata(for: url)
        ))
    }

    private func scanCodexMarkdownFiles(
        at directory: URL,
        type: CapabilityType,
        sourceKind: String,
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
            capabilities.append(Capability(
                id: stableID(type: type, path: url.path),
                name: frontmatter["name"] ?? url.deletingPathExtension().lastPathComponent,
                type: type,
                scope: .project,
                statuses: [.discovered],
                risks: type == .hook ? [.exec, .read] : [.info, .read],
                source: CapabilitySource(kind: sourceKind, path: url.path),
                summary: frontmatter["description"],
                metadata: fileMetadata(for: url, merging: frontmatter)
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
                    capabilities.append(Capability(
                        id: stableID(type: .mcpServer, path: "\(url.path)#\(serverName)"),
                        name: serverName,
                        type: .mcpServer,
                        scope: scope,
                        statuses: risks.contains(.secret) || risks.contains(.network) ? [.discovered, .risky] : [.discovered],
                        risks: risks,
                        source: CapabilitySource(kind: "mcp-config", path: url.path),
                        summary: "MCP server",
                        metadata: compactMetadata(server)
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

    private func scanAgentsWorkspace(at root: URL, options: ScanOptions, into capabilities: inout [Capability], issues: inout [ScanIssue]) {
        let agentsRoot = root.appendingPathComponent(".agents")
        let manifest = agentsRoot.appendingPathComponent("manifest.json")
        if fileManager.fileExists(atPath: manifest.path) {
            capabilities.append(Capability(
                id: stableID(type: .instruction, path: manifest.path),
                name: ".agents manifest",
                type: .instruction,
                scope: .project,
                statuses: [.enabled],
                risks: [.info, .read],
                source: CapabilitySource(kind: "agents-manifest", path: manifest.path)
            ))
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
            projectRoot: root
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

    private func scanSkillFiles(
        at root: URL,
        options: ScanOptions,
        into capabilities: inout [Capability],
        issues: inout [ScanIssue],
        scope: CapabilityScope = .project,
        sourceKind: String = "skill",
        projectRoot: URL? = nil
    ) {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return
        }

        emitProgress("scan.skills.start", path: root.path, options: options)

        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            issues.append(ScanIssue(severity: .warning, path: root.path, message: "Unable to enumerate project files"))
            emitProgress("scan.skills.failed", path: root.path, options: options)
            return
        }

        var count = 0
        for case let url as URL in enumerator {
            let last = url.lastPathComponent
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if isDirectory && options.ignoredDirectoryNames.contains(last) {
                enumerator.skipDescendants()
                continue
            }

            guard last == "SKILL.md" else { continue }
            count += 1
            if count > options.maxSkillFiles {
                issues.append(ScanIssue(severity: .warning, path: root.path, message: "Stopped after \(options.maxSkillFiles) skill files"))
                break
            }

            capabilities.append(scanSkill(at: url, projectRoot: projectRoot ?? root, scope: scope, sourceKind: sourceKind))
        }

        emitProgress("scan.skills.finish", path: root.path, count: count, options: options)
    }

    private func scanUserSkillRoots(projectRoot: URL, options: ScanOptions, into capabilities: inout [Capability], issues: inout [ScanIssue]) {
        guard options.includeUserScope else { return }
        for root in options.userSkillRoots {
            let standardizedRoot = root.standardizedFileURL.resolvingSymlinksInPath()
            scanSkillFiles(
                at: standardizedRoot,
                options: options,
                into: &capabilities,
                issues: &issues,
                scope: .user,
                sourceKind: userSkillSourceKind(for: standardizedRoot),
                projectRoot: projectRoot
            )
        }
    }

    private func userSkillSourceKind(for root: URL) -> String {
        let components = root.pathComponents
        if components.contains(".agents") {
            return "agents-skill"
        }
        if components.contains(".claude") {
            return "claude-skill"
        }
        return "user-skill"
    }

    private func scanSkill(at url: URL, projectRoot: URL, scope: CapabilityScope, sourceKind: String) -> Capability {
        let frontmatter = (try? String(contentsOf: url, encoding: .utf8)).flatMap(parseFrontmatter) ?? [:]
        let parentName = url.deletingLastPathComponent().lastPathComponent
        let name = frontmatter["name"] ?? parentName
        let packageInfo = packageInfo(for: url, projectRoot: projectRoot)

        return Capability(
            id: stableID(type: .skill, path: url.path),
            name: name,
            type: .skill,
            scope: scope,
            statuses: [.discovered],
            risks: scope == .user ? [.read, .global] : [.read],
            source: CapabilitySource(kind: sourceKind, path: url.path, packageName: packageInfo?.packageName),
            pluginID: packageInfo?.pluginID,
            summary: frontmatter["description"],
            metadata: fileMetadata(for: url, merging: frontmatter)
        )
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

        guard let cacheIndex = codexPluginCacheIndex(in: components),
              cacheIndex + 2 < components.count else {
            return nil
        }

        let marketplace = components[cacheIndex + 1]
        let pluginName = components[cacheIndex + 2]
        let packageName = pluginName
        let pluginID = "plugin:codex-cache:\(normalized(marketplace)):\(normalized(pluginName))"
        return (packageName, pluginID)
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
