import Foundation

public struct SkillsAgentDefinition: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var displayName: String
    public var projectSkillsDir: String
    public var globalSkillsDir: String?
    public var showInAddAgent: Bool

    public init(
        id: String,
        displayName: String,
        projectSkillsDir: String,
        globalSkillsDir: String?,
        showInAddAgent: Bool = true
    ) {
        self.id = id
        self.displayName = displayName
        self.projectSkillsDir = projectSkillsDir
        self.globalSkillsDir = globalSkillsDir
        self.showInAddAgent = showInAddAgent
    }

    public var usesSharedProjectSkills: Bool {
        projectSkillsDir == ".agents/skills"
    }
}

public enum SkillsAgentCatalog {
    public static var agents: [SkillsAgentDefinition] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let environment = ProcessInfo.processInfo.environment
        let configHome = environment["XDG_CONFIG_HOME"].flatMap { $0.isEmpty ? nil : $0 } ?? "\(home)/.config"
        let codexHome = environment["CODEX_HOME"].flatMap { $0.isEmpty ? nil : $0 } ?? "\(home)/.codex"
        let claudeHome = environment["CLAUDE_CONFIG_DIR"].flatMap { $0.isEmpty ? nil : $0 } ?? "\(home)/.claude"
        let vibeHome = environment["VIBE_HOME"].flatMap { $0.isEmpty ? nil : $0 } ?? "\(home)/.vibe"

        return [
            .init(id: "aider-desk", displayName: "AiderDesk", projectSkillsDir: ".aider-desk/skills", globalSkillsDir: "\(home)/.aider-desk/skills"),
            .init(id: "amp", displayName: "Amp", projectSkillsDir: ".agents/skills", globalSkillsDir: "\(configHome)/agents/skills"),
            .init(id: "antigravity", displayName: "Antigravity", projectSkillsDir: ".agents/skills", globalSkillsDir: "\(home)/.gemini/antigravity/skills"),
            .init(id: "augment", displayName: "Augment", projectSkillsDir: ".augment/skills", globalSkillsDir: "\(home)/.augment/skills"),
            .init(id: "bob", displayName: "IBM Bob", projectSkillsDir: ".bob/skills", globalSkillsDir: "\(home)/.bob/skills"),
            .init(id: "claude-code", displayName: "Claude Code", projectSkillsDir: ".claude/skills", globalSkillsDir: "\(claudeHome)/skills"),
            .init(id: "openclaw", displayName: "OpenClaw", projectSkillsDir: "skills", globalSkillsDir: "\(home)/.openclaw/skills"),
            .init(id: "cline", displayName: "Cline", projectSkillsDir: ".agents/skills", globalSkillsDir: "\(home)/.agents/skills"),
            .init(id: "codearts-agent", displayName: "CodeArts Agent", projectSkillsDir: ".codeartsdoer/skills", globalSkillsDir: "\(home)/.codeartsdoer/skills"),
            .init(id: "codebuddy", displayName: "CodeBuddy", projectSkillsDir: ".codebuddy/skills", globalSkillsDir: "\(home)/.codebuddy/skills"),
            .init(id: "codemaker", displayName: "Codemaker", projectSkillsDir: ".codemaker/skills", globalSkillsDir: "\(home)/.codemaker/skills"),
            .init(id: "codestudio", displayName: "Code Studio", projectSkillsDir: ".codestudio/skills", globalSkillsDir: "\(home)/.codestudio/skills"),
            .init(id: "codex", displayName: "Codex", projectSkillsDir: ".agents/skills", globalSkillsDir: "\(codexHome)/skills"),
            .init(id: "command-code", displayName: "Command Code", projectSkillsDir: ".commandcode/skills", globalSkillsDir: "\(home)/.commandcode/skills"),
            .init(id: "continue", displayName: "Continue", projectSkillsDir: ".continue/skills", globalSkillsDir: "\(home)/.continue/skills"),
            .init(id: "cortex", displayName: "Cortex Code", projectSkillsDir: ".cortex/skills", globalSkillsDir: "\(home)/.snowflake/cortex/skills"),
            .init(id: "crush", displayName: "Crush", projectSkillsDir: ".crush/skills", globalSkillsDir: "\(home)/.config/crush/skills"),
            .init(id: "cursor", displayName: "Cursor", projectSkillsDir: ".agents/skills", globalSkillsDir: "\(home)/.cursor/skills"),
            .init(id: "deepagents", displayName: "Deep Agents", projectSkillsDir: ".agents/skills", globalSkillsDir: "\(home)/.deepagents/agent/skills"),
            .init(id: "devin", displayName: "Devin for Terminal", projectSkillsDir: ".devin/skills", globalSkillsDir: "\(configHome)/devin/skills"),
            .init(id: "dexto", displayName: "Dexto", projectSkillsDir: ".agents/skills", globalSkillsDir: "\(home)/.agents/skills"),
            .init(id: "droid", displayName: "Droid", projectSkillsDir: ".factory/skills", globalSkillsDir: "\(home)/.factory/skills"),
            .init(id: "firebender", displayName: "Firebender", projectSkillsDir: ".agents/skills", globalSkillsDir: "\(home)/.firebender/skills"),
            .init(id: "forgecode", displayName: "ForgeCode", projectSkillsDir: ".forge/skills", globalSkillsDir: "\(home)/.forge/skills"),
            .init(id: "gemini-cli", displayName: "Gemini CLI", projectSkillsDir: ".agents/skills", globalSkillsDir: "\(home)/.gemini/skills"),
            .init(id: "github-copilot", displayName: "GitHub Copilot", projectSkillsDir: ".agents/skills", globalSkillsDir: "\(home)/.copilot/skills"),
            .init(id: "goose", displayName: "Goose", projectSkillsDir: ".goose/skills", globalSkillsDir: "\(configHome)/goose/skills"),
            .init(id: "hermes-agent", displayName: "Hermes Agent", projectSkillsDir: ".hermes/skills", globalSkillsDir: "\(home)/.hermes/skills"),
            .init(id: "iflow-cli", displayName: "iFlow CLI", projectSkillsDir: ".iflow/skills", globalSkillsDir: "\(home)/.iflow/skills"),
            .init(id: "junie", displayName: "Junie", projectSkillsDir: ".junie/skills", globalSkillsDir: "\(home)/.junie/skills"),
            .init(id: "kilo", displayName: "Kilo Code", projectSkillsDir: ".kilocode/skills", globalSkillsDir: "\(home)/.kilocode/skills"),
            .init(id: "kimi-cli", displayName: "Kimi Code CLI", projectSkillsDir: ".agents/skills", globalSkillsDir: "\(home)/.config/agents/skills"),
            .init(id: "kiro-cli", displayName: "Kiro CLI", projectSkillsDir: ".kiro/skills", globalSkillsDir: "\(home)/.kiro/skills"),
            .init(id: "kode", displayName: "Kode", projectSkillsDir: ".kode/skills", globalSkillsDir: "\(home)/.kode/skills"),
            .init(id: "mcpjam", displayName: "MCPJam", projectSkillsDir: ".mcpjam/skills", globalSkillsDir: "\(home)/.mcpjam/skills"),
            .init(id: "mistral-vibe", displayName: "Mistral Vibe", projectSkillsDir: ".vibe/skills", globalSkillsDir: "\(vibeHome)/skills"),
            .init(id: "mux", displayName: "Mux", projectSkillsDir: ".mux/skills", globalSkillsDir: "\(home)/.mux/skills"),
            .init(id: "neovate", displayName: "Neovate", projectSkillsDir: ".neovate/skills", globalSkillsDir: "\(home)/.neovate/skills"),
            .init(id: "opencode", displayName: "OpenCode", projectSkillsDir: ".agents/skills", globalSkillsDir: "\(configHome)/opencode/skills"),
            .init(id: "openhands", displayName: "OpenHands", projectSkillsDir: ".openhands/skills", globalSkillsDir: "\(home)/.openhands/skills"),
            .init(id: "pi", displayName: "Pi", projectSkillsDir: ".pi/skills", globalSkillsDir: "\(home)/.pi/agent/skills"),
            .init(id: "pochi", displayName: "Pochi", projectSkillsDir: ".pochi/skills", globalSkillsDir: "\(home)/.pochi/skills"),
            .init(id: "qoder", displayName: "Qoder", projectSkillsDir: ".qoder/skills", globalSkillsDir: "\(home)/.qoder/skills"),
            .init(id: "qwen-code", displayName: "Qwen Code", projectSkillsDir: ".qwen/skills", globalSkillsDir: "\(home)/.qwen/skills"),
            .init(id: "replit", displayName: "Replit", projectSkillsDir: ".agents/skills", globalSkillsDir: "\(configHome)/agents/skills", showInAddAgent: false),
            .init(id: "roo", displayName: "Roo Code", projectSkillsDir: ".roo/skills", globalSkillsDir: "\(home)/.roo/skills"),
            .init(id: "rovodev", displayName: "Rovo Dev", projectSkillsDir: ".rovodev/skills", globalSkillsDir: "\(home)/.rovodev/skills"),
            .init(id: "tabnine-cli", displayName: "Tabnine CLI", projectSkillsDir: ".tabnine/agent/skills", globalSkillsDir: "\(home)/.tabnine/agent/skills"),
            .init(id: "trae", displayName: "Trae", projectSkillsDir: ".trae/skills", globalSkillsDir: "\(home)/.trae/skills"),
            .init(id: "trae-cn", displayName: "Trae CN", projectSkillsDir: ".traecn/skills", globalSkillsDir: "\(home)/.traecn/skills"),
            .init(id: "warp", displayName: "Warp", projectSkillsDir: ".agents/skills", globalSkillsDir: "\(home)/.agents/skills"),
            .init(id: "windsurf", displayName: "Windsurf", projectSkillsDir: ".windsurf/skills", globalSkillsDir: "\(home)/.codeium/windsurf/skills"),
            .init(id: "zencoder", displayName: "Zencoder", projectSkillsDir: ".zencoder/skills", globalSkillsDir: "\(home)/.zencoder/skills"),
            .init(id: "adal", displayName: "AdaL", projectSkillsDir: ".adal/skills", globalSkillsDir: "\(home)/.adal/skills"),
            .init(id: "universal", displayName: "Universal", projectSkillsDir: ".agents/skills", globalSkillsDir: "\(configHome)/agents/skills", showInAddAgent: false)
        ]
    }

    public static var addableAgents: [SkillsAgentDefinition] {
        agents.filter(\.showInAddAgent).sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }

    public static func defaultGlobalLockURL() -> URL {
        let environment = ProcessInfo.processInfo.environment
        if let stateHome = environment["XDG_STATE_HOME"], !stateHome.isEmpty {
            return URL(fileURLWithPath: stateHome).appendingPathComponent("skills/.skill-lock.json")
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".agents/.skill-lock.json")
    }
}

struct SkillsLockFile: Sendable {
    var path: String
    var entries: [String: SkillsLockEntry]
}

struct SkillsLockEntry: Decodable, Sendable {
    var source: String
    var ref: String?
    var sourceType: String
    var sourceUrl: String?
    var skillPath: String?
    var computedHash: String?
    var skillFolderHash: String?
    var installedAt: String?
    var updatedAt: String?
    var pluginName: String?

    var updateHash: String? {
        guard let value = computedHash ?? skillFolderHash, !value.isEmpty else {
            return nil
        }
        return value
    }
}

enum SkillsLockReader {
    /// Size-bounded so a hostile repo shipping a multi-GB `skills-lock.json` / `.skill-lock.json` cannot
    /// OOM the scanner. The default cap matches the scanner's config-file cap; over-cap files read as nil.
    static func read(at url: URL, maxBytes: Int = 8 * 1024 * 1024) -> SkillsLockFile? {
        if let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize, size > maxBytes {
            return nil
        }
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONDecoder().decode(RawSkillsLockFile.self, from: data) else {
            return nil
        }
        return SkillsLockFile(path: url.path, entries: object.skills)
    }

    private struct RawSkillsLockFile: Decodable {
        var version: Int
        var skills: [String: SkillsLockEntry]
    }
}

func skillsSanitizedName(_ name: String) -> String {
    var result = ""
    var previousWasDash = false
    for scalar in name.lowercased().unicodeScalars {
        let character = Character(scalar)
        let isAllowed = (65...90).contains(Int(scalar.value))
            || (97...122).contains(Int(scalar.value))
            || (48...57).contains(Int(scalar.value))
            || scalar.value == 46
            || scalar.value == 95
        if isAllowed {
            result.append(character)
            previousWasDash = false
        } else if !previousWasDash {
            result.append("-")
            previousWasDash = true
        }
    }
    result = result.trimmingCharacters(in: CharacterSet(charactersIn: ".-"))
    if result.count > 255 {
        result = String(result.prefix(255))
    }
    return result.isEmpty ? "unnamed-skill" : result
}
