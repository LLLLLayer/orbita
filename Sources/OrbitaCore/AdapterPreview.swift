import Foundation

public struct GeneratedAdapterFile: Codable, Hashable, Sendable {
    public var path: String
    public var content: String

    public init(path: String, content: String) {
        self.path = path
        self.content = content
    }
}

public struct AdapterCapabilityMapping: Codable, Hashable, Sendable {
    public var capabilityID: String
    public var supported: Bool
    public var targetPath: String?
    public var reason: String

    public init(capabilityID: String, supported: Bool, targetPath: String?, reason: String) {
        self.capabilityID = capabilityID
        self.supported = supported
        self.targetPath = targetPath
        self.reason = reason
    }
}

public struct AdapterPreview: Codable, Sendable {
    public var schemaVersion: Int
    public var projectRoot: String
    public var agent: AgentID
    public var appliesChanges: Bool
    public var supportedCapabilities: [Capability]
    public var unsupportedCapabilities: [Capability]
    public var capabilityMappings: [AdapterCapabilityMapping]
    public var generatedFiles: [GeneratedAdapterFile]

    public init(
        schemaVersion: Int = 1,
        projectRoot: String,
        agent: AgentID,
        appliesChanges: Bool = false,
        supportedCapabilities: [Capability],
        unsupportedCapabilities: [Capability],
        capabilityMappings: [AdapterCapabilityMapping],
        generatedFiles: [GeneratedAdapterFile]
    ) {
        self.schemaVersion = schemaVersion
        self.projectRoot = projectRoot
        self.agent = agent
        self.appliesChanges = appliesChanges
        self.supportedCapabilities = supportedCapabilities
        self.unsupportedCapabilities = unsupportedCapabilities
        self.capabilityMappings = capabilityMappings
        self.generatedFiles = generatedFiles
    }
}

public final class AdapterPreviewBuilder {
    public init() {}

    public func preview(for agent: AgentID, graph: CapabilityGraph) -> AdapterPreview {
        let view = AgentViewResolver().view(for: agent, graph: graph)
        let mappings = graph.capabilities
            .map { mapping(for: agent, capability: $0, projectRoot: graph.projectRoot) }
            .sorted { $0.capabilityID < $1.capabilityID }
        let generatedFile = GeneratedAdapterFile(
            path: adapterFilePath(for: agent, projectRoot: graph.projectRoot),
            content: capabilitiesJSON(agent: agent, capabilities: view.visibleCapabilities, mappings: mappings)
        )

        return AdapterPreview(
            projectRoot: graph.projectRoot,
            agent: agent,
            supportedCapabilities: view.visibleCapabilities,
            unsupportedCapabilities: view.hiddenCapabilities,
            capabilityMappings: mappings,
            generatedFiles: [generatedFile]
        )
    }

    private func adapterFilePath(for agent: AgentID, projectRoot: String) -> String {
        URL(fileURLWithPath: projectRoot)
            .appendingPathComponent(".orbita/adapters")
            .appendingPathComponent(agent.rawValue)
            .appendingPathComponent("capabilities.json")
            .path
    }

    private func mapping(for agent: AgentID, capability: Capability, projectRoot: String) -> AdapterCapabilityMapping {
        guard !capability.statuses.contains(.broken) else {
            return AdapterCapabilityMapping(
                capabilityID: capability.id,
                supported: false,
                targetPath: nil,
                reason: "Broken capabilities are not mapped until their source path is fixed."
            )
        }

        switch agent {
        case .codex:
            return codexMapping(for: capability, projectRoot: projectRoot)
        case .claudeCode:
            return claudeCodeMapping(for: capability, projectRoot: projectRoot)
        case .cursor:
            return cursorMapping(for: capability)
        case .trae:
            return traeMapping(for: capability)
        }
    }

    private func codexMapping(for capability: Capability, projectRoot: String) -> AdapterCapabilityMapping {
        switch capability.type {
        case .plugin:
            return AdapterCapabilityMapping(
                capabilityID: capability.id,
                supported: true,
                targetPath: adapterFilePath(for: .codex, projectRoot: projectRoot),
                reason: "Codex can see plugin-provided capabilities through the generated adapter index."
            )
        case .skill:
            guard isCodexSkillCapability(capability) else {
                return AdapterCapabilityMapping(
                    capabilityID: capability.id,
                    supported: false,
                    targetPath: nil,
                    reason: "Codex does not load this skill source directly; sync it into .agents/skills or CODEX_HOME/skills first."
                )
            }
            return AdapterCapabilityMapping(
                capabilityID: capability.id,
                supported: true,
                targetPath: capability.source.path,
                reason: "Codex loads repo skills from .agents/skills and user skills from configured Codex skill roots."
            )
        case .agent:
            if capability.source.kind == "codex-agent" {
                return AdapterCapabilityMapping(
                    capabilityID: capability.id,
                    supported: true,
                    targetPath: capability.source.path,
                    reason: "Codex loads project subagents from .codex/agents."
                )
            }
            return AdapterCapabilityMapping(
                capabilityID: capability.id,
                supported: false,
                targetPath: nil,
                reason: "Codex does not load Claude Code subagents."
            )
        case .mcpServer:
            return AdapterCapabilityMapping(
                capabilityID: capability.id,
                supported: true,
                targetPath: capability.source.path,
                reason: "Codex can read MCP server configuration through project and user configuration sources."
            )
        case .instruction:
            return AdapterCapabilityMapping(
                capabilityID: capability.id,
                supported: true,
                targetPath: capability.source.path,
                reason: "Codex loads project instructions from supported instruction files."
            )
        case .hook:
            guard capability.source.kind == "codex-hook" else {
                return AdapterCapabilityMapping(
                    capabilityID: capability.id,
                    supported: false,
                    targetPath: nil,
                    reason: "Codex does not load \(capability.source.kind) hooks through this adapter."
                )
            }
            return AdapterCapabilityMapping(
                capabilityID: capability.id,
                supported: true,
                targetPath: capability.source.path,
                reason: "Codex can use project hooks after explicit Apply Plan confirmation."
            )
        case .command:
            guard capability.source.kind == "codex-command" else {
                return AdapterCapabilityMapping(
                    capabilityID: capability.id,
                    supported: false,
                    targetPath: nil,
                    reason: "Codex does not load \(capability.source.kind) commands through this adapter."
                )
            }
            return AdapterCapabilityMapping(
                capabilityID: capability.id,
                supported: true,
                targetPath: capability.source.path,
                reason: "Codex loads project commands from .codex/commands."
            )
        case .rule, .unknown:
            return AdapterCapabilityMapping(
                capabilityID: capability.id,
                supported: false,
                targetPath: nil,
                reason: "Codex does not load Cursor rules as executable capabilities."
            )
        }
    }

    private func claudeCodeMapping(for capability: Capability, projectRoot: String) -> AdapterCapabilityMapping {
        switch capability.type {
        case .plugin where isClaudeNativeCapability(capability):
            return AdapterCapabilityMapping(
                capabilityID: capability.id,
                supported: true,
                targetPath: adapterFilePath(for: .claudeCode, projectRoot: projectRoot),
                reason: "Claude Code can see native .claude plugin groups through the generated adapter index."
            )
        case .skill where isClaudeNativeCapability(capability):
            return AdapterCapabilityMapping(
                capabilityID: capability.id,
                supported: true,
                targetPath: capability.source.path,
                reason: "Claude Code loads native skills from .claude/skills."
            )
        case .agent where isClaudeNativeCapability(capability):
            return AdapterCapabilityMapping(
                capabilityID: capability.id,
                supported: true,
                targetPath: capability.source.path,
                reason: "Claude Code loads custom subagents from .claude/agents and plugin agents directories."
            )
        case .mcpServer:
            return AdapterCapabilityMapping(
                capabilityID: capability.id,
                supported: true,
                targetPath: capability.source.path,
                reason: "Claude Code can read MCP servers, with approval semantics preserved by the client."
            )
        case .instruction:
            return AdapterCapabilityMapping(
                capabilityID: capability.id,
                supported: true,
                targetPath: capability.source.path,
                reason: "Claude Code can read supported project instruction files."
            )
        case .command where capability.source.kind == "claude-command":
            return AdapterCapabilityMapping(
                capabilityID: capability.id,
                supported: true,
                targetPath: capability.source.path,
                reason: "Claude Code loads project slash commands from .claude/commands."
            )
        case .hook where capability.source.kind == "claude-settings":
            return AdapterCapabilityMapping(
                capabilityID: capability.id,
                supported: true,
                targetPath: capability.source.path,
                reason: "Claude Code reads project settings and hooks from .claude/settings.json."
            )
        default:
            return AdapterCapabilityMapping(
                capabilityID: capability.id,
                supported: false,
                targetPath: nil,
                reason: "Claude Code does not load \(capability.type.rawValue) capabilities through this adapter."
            )
        }
    }

    private func isClaudeNativeCapability(_ capability: Capability) -> Bool {
        capability.source.kind == "claude-skill"
            || capability.source.kind == "claude-agent"
            || capability.source.kind == "claude-plugin-agent"
            || sourcePathComponents(for: capability).contains(".claude")
    }

    private func isCodexSkillCapability(_ capability: Capability) -> Bool {
        if capability.source.kind == "codex-skill"
            || capability.source.kind == "agents-skill"
            || capability.source.kind == "user-skill" {
            return true
        }
        if capability.source.kind == "claude-skill" || capability.source.kind.hasPrefix("claude-plugin-") {
            return false
        }
        if capability.source.kind.hasPrefix("agents-") || sourcePathComponents(for: capability).contains(".agents") {
            return true
        }
        return capability.source.kind == "skill" || sourcePathComponents(for: capability).contains(".codex")
    }

    private func sourcePathComponents(for capability: Capability) -> [String] {
        URL(fileURLWithPath: capability.source.path).pathComponents
    }

    private func cursorMapping(for capability: Capability) -> AdapterCapabilityMapping {
        switch capability.type {
        case .rule:
            return AdapterCapabilityMapping(
                capabilityID: capability.id,
                supported: true,
                targetPath: capability.source.path,
                reason: "Cursor loads project rules from .cursor/rules."
            )
        case .mcpServer:
            return AdapterCapabilityMapping(
                capabilityID: capability.id,
                supported: true,
                targetPath: capability.source.path,
                reason: "Cursor can read MCP server configuration."
            )
        case .instruction:
            return AdapterCapabilityMapping(
                capabilityID: capability.id,
                supported: true,
                targetPath: capability.source.path,
                reason: "Cursor can use supported project instruction files as context."
            )
        default:
            return AdapterCapabilityMapping(
                capabilityID: capability.id,
                supported: false,
                targetPath: nil,
                reason: "Cursor does not load \(capability.type.rawValue) capabilities through this adapter."
            )
        }
    }

    private func traeMapping(for capability: Capability) -> AdapterCapabilityMapping {
        switch capability.type {
        case .skill:
            let kind = capability.source.kind
            if isCodexPluginBundledCapability(capability)
                || kind == "codex-skill"
                || kind == "claude-skill"
                || kind.hasPrefix("claude-plugin-") {
                return AdapterCapabilityMapping(
                    capabilityID: capability.id,
                    supported: false,
                    targetPath: nil,
                    reason: "Trae does not load this skill source directly; sync it into .agents/skills or ~/.trae/skills first."
                )
            }
            return AdapterCapabilityMapping(
                capabilityID: capability.id,
                supported: true,
                targetPath: capability.source.path,
                reason: "Trae loads SKILL.md-based skills from .agents/skills and ~/.trae/skills."
            )
        case .mcpServer:
            return AdapterCapabilityMapping(
                capabilityID: capability.id,
                supported: true,
                targetPath: capability.source.path,
                reason: "Trae can read MCP server configuration from project and user sources."
            )
        case .instruction, .rule:
            return AdapterCapabilityMapping(
                capabilityID: capability.id,
                supported: true,
                targetPath: capability.source.path,
                reason: "Trae uses supported project instruction and rule files as context."
            )
        default:
            return AdapterCapabilityMapping(
                capabilityID: capability.id,
                supported: false,
                targetPath: nil,
                reason: "Trae does not load \(capability.type.rawValue) capabilities through this adapter."
            )
        }
    }

    private func isCodexPluginBundledCapability(_ capability: Capability) -> Bool {
        guard capability.pluginID != nil else {
            return false
        }
        return capability.metadata["manager"] == "codex"
            || capability.pluginID?.hasPrefix("plugin:codex-cache:") == true
    }

    private func capabilitiesJSON(agent: AgentID, capabilities: [Capability], mappings: [AdapterCapabilityMapping]) -> String {
        let object: [String: Any] = [
            "schemaVersion": 1,
            "agent": agent.rawValue,
            "capabilities": capabilities.map { capability in
                [
                    "id": capability.id,
                    "name": capability.name,
                    "type": capability.type.rawValue,
                    "scope": capability.scope.rawValue,
                    "sourcePath": capability.source.path,
                    "statuses": capability.statuses.map(\.rawValue),
                    "risks": capability.risks.map(\.rawValue)
                ] as [String: Any]
            },
            "mappings": mappings.map { mapping in
                [
                    "capabilityID": mapping.capabilityID,
                    "supported": mapping.supported,
                    "targetPath": mapping.targetPath as Any,
                    "reason": mapping.reason
                ] as [String: Any]
            }
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
              let text = String(data: data, encoding: .utf8) else {
            return "{}\n"
        }
        return text.replacingOccurrences(of: "\\/", with: "/") + "\n"
    }
}
