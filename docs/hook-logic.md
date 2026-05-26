---
created_at: 2026-05-26
created_by: Codex
updated_at: 2026-05-26
updated_by: Codex
tags:
  - docs
  - hooks
  - codex
  - claude-code
summary: Hook discovery and parsing contract for Orbita.
version: 0.1.0
---

# Hook Logic

Orbita treats a Hook as a concrete lifecycle handler, not as a config file. A single `settings.json` or `hooks.json` can register many handlers, so the scanner creates one capability per `event -> matcher group -> hooks[]` handler.

## Claude Code

Claude Code defines hooks under a top-level `hooks` object. The schema has three levels:

1. Event name, for example `PreToolUse`, `PermissionRequest`, `PostToolUse`, `UserPromptSubmit`, or `Stop`.
2. Matcher group, optionally with `matcher`. Tool events match against `tool_name`; events like `UserPromptSubmit` and `Stop` always fire.
3. Handler object in `hooks[]`. Claude Code supports command, HTTP, MCP tool, prompt, and agent handlers.

Claude hook sources include user settings `~/.claude/settings.json`, project `.claude/settings.json`, local `.claude/settings.local.json`, managed policy, and plugin `hooks/hooks.json`.

Vibe Notch is a good concrete reference implementation. It resolves the Claude config directory from `CLAUDE_CONFIG_DIR`, `~/.config/claude`, or legacy `~/.claude`; copies `claude-island-state.py` into the hooks directory; then writes command handlers into `settings.json`. The hook script reads Claude's JSON event payload from stdin and sends state to the app over `/tmp/claude-island.sock`; for `PermissionRequest`, it can return allow or deny JSON.

## Codex

Codex uses a Claude-style hook shape loaded from `hooks.json` files and config layers. In the current Codex source, the `hooks` feature is stable and enabled by default. Codex's typed event set includes:

- `PreToolUse`
- `PermissionRequest`
- `PostToolUse`
- `PreCompact`
- `PostCompact`
- `SessionStart`
- `UserPromptSubmit`
- `SubagentStart`
- `SubagentStop`
- `Stop`

Codex config defines command, prompt, and agent handler variants, but the runtime discovery path currently executes command handlers and skips prompt or agent handlers with warnings. Plugin hook sources can come from `hooks/hooks.json`, manifest-declared hook paths, or inline manifest hook blocks. Plugin handlers receive compatibility environment variables such as `PLUGIN_ROOT`, `CLAUDE_PLUGIN_ROOT`, `PLUGIN_DATA`, and `CLAUDE_PLUGIN_DATA`.

Codex hook state is keyed by source path, event, matcher group index, and handler index. Orbita mirrors this shape with metadata like:

```toml
[hooks.state."<source-path>:post_tool_use:0:0"]
enabled = true
trusted_hash = "sha256:..."
```

## Orbita Parser Contract

Orbita scans these Hook sources:

- Project and user Codex `hooks.json`.
- Project and user Claude `settings.json` hook sections.
- Codex and Claude plugin `hooks/hooks.json` and `hooks.json`.

For every concrete handler, Orbita records:

- `manager`: `codex` or `claude-code`.
- `event`: lifecycle event name.
- `matcher`: matcher group text, if any.
- `handlerKind`: `command`, `http`, `mcp_tool`, `prompt`, `agent`, or fallback `hook`.
- `handlerHost`: display host inferred from the handler.
- `handlerRunner`: command runner such as `bash`, `python3`, `node`, `npx`, or `swift`.
- `handlerScript`: script or package executed by the runner when detectable.
- `handlerExecutable`: executable basename.
- `entryIndex`, `hookIndex`, `stateKey`, `timeout`, and optional `filter`.

Host extraction is intentionally heuristic:

- Known signatures win first. `claude-island-state.py` maps to `Vibe Notch`.
- Plugin hooks use the plugin name as the host.
- Runner commands use the script/package name when present, for example `python3 ~/.claude/hooks/foo.py` becomes `Foo`.
- Plain commands fall back to the executable name.

The UI should display the host in the row title, for example `Vibe Notch - PermissionRequest (*)`, while the detail pane can show event, matcher, source path, command, runner, script, and state key.

## References

- [Claude Code Hooks reference](https://code.claude.com/docs/en/hooks)
- [Claude Code hooks guide](https://code.claude.com/docs/en/hooks-guide)
- [Vibe Notch HookInstaller.swift](https://github.com/farouqaldori/vibe-notch/blob/main/ClaudeIsland/Services/Hooks/HookInstaller.swift)
- [Vibe Notch claude-island-state.py](https://github.com/farouqaldori/vibe-notch/blob/main/ClaudeIsland/Resources/claude-island-state.py)
- [Vibe Notch ClaudePaths.swift](https://github.com/farouqaldori/vibe-notch/blob/main/ClaudeIsland/Core/ClaudePaths.swift)
- [Codex hook_config.rs](https://github.com/openai/codex/blob/main/codex-rs/config/src/hook_config.rs)
- [Codex hook discovery](https://github.com/openai/codex/blob/main/codex-rs/hooks/src/engine/discovery.rs)
- [Codex plugin hook loader](https://github.com/openai/codex/blob/main/codex-rs/core-plugins/src/loader.rs)
