---
created_at: 2026-05-24
created_by: Codex
updated_at: 2026-05-24
updated_by: Codex
tags:
  - docs
  - plugins
  - agents
  - codex
  - claude
summary: Orbita capability lifecycle rules for .agents, Codex Desktop, Claude Code, update checks, and release automation.
version: 0.1.0
---

# Capability lifecycle

Orbita treats every agent extension as a capability with four lifecycle dimensions:

- Scope: `user` for this Mac, `project` for the current repository, `local` when a client supports a non-shared project-local install, and `installed` when the source is known but the effective scope is not writable by Orbita.
- Status: `enabled`, `disabled`, `discovered`, `broken`, `shadowed`, `drifted`, or `risky`.
- Source of truth: the native client config where possible; `.agents` only owns Orbita-managed intent and generated adapter indexes.
- Maintenance command: the check/update/enable/disable command or config write that Orbita can run from the app.

## .agents

`.agents` is Orbita's shared project index. It is not a replacement for every native client config; it is the cross-agent intent layer.

Computer dimension:

- Global skills live under `~/.agents/skills`.
- The Skills CLI records install/update metadata in the global skill lock file, commonly `~/.agents/.skill-lock.json`.
- Global skill update is triggered with `npx skills update <skill> -g -y`.
- Global skills do not have a native enabled/disabled toggle. A global disable is modeled as removal from the target agent or as project-level intent that hides the capability.

Project dimension:

- Project intent lives in `<repo>/.agents/manifest.json`.
- Resolved source/hash/risk metadata lives in `<repo>/.agents/lock.json`.
- Enabled project skills are linked under `<repo>/.agents/skills/<name>`.
- Disable removes the managed `.agents/skills/<name>` link and records `status: "disabled"` in the manifest without deleting the source.
- Update is triggered with `npx skills update <skill> -p -y` for project installs.

Orbita implementation:

- Scan `~/.agents/skills`, `<repo>/.agents/skills`, and project manifest intent.
- Generate adapter previews under `<repo>/.agents/adapters/<agent>/capabilities.json`.
- Apply writes only inside project `.agents` for merge/enable/disable/delete/clean/rollback.
- Expose `.agents` skill update commands in the inspector.

## Codex Desktop

Codex Desktop and the Codex CLI keep plugin installation and enablement in Codex-owned locations.

Computer dimension:

- Installed plugin cache is under `~/.codex/plugins/cache/<marketplace>/<plugin>/<version>/`.
- A Codex plugin manifest is `<plugin-root>/.codex-plugin/plugin.json`; some compatible marketplace entries may use `.claude-plugin/plugin.json`.
- Enabled state is stored in `~/.codex/config.toml` as `[plugins."<plugin>@<marketplace>"] enabled = true|false`.
- Marketplace update check is `codex plugin marketplace upgrade [marketplace]`.
- Reinstall/update trigger is `codex plugin add <plugin>@<marketplace>` after marketplace snapshots are refreshed.

Project dimension:

- Project-level Codex commands and hooks remain native files under `<repo>/.codex/commands` and `<repo>/.codex/hooks`.
- If a repository contains project plugin sources, Orbita treats them as project scope only when they are inside `<repo>/plugins/` and have a `.codex-plugin/plugin.json` or `.claude-plugin/plugin.json` manifest.
- Project `.codex/config.toml`, when present, is the project-level native config Orbita can inspect for plugin enablement.

Orbita implementation:

- Scan Codex plugin cache manifests and map `config.toml` enablement into `enabled`/`disabled`.
- For Codex enable/disable, update the relevant `[plugins."<selector>"] enabled` key in the config file.
- For update check, run `codex plugin marketplace upgrade <marketplace>`.
- For update trigger, run `codex plugin marketplace upgrade <marketplace> && codex plugin add <plugin>@<marketplace>`.

## Claude Code

Claude Code has native plugin lifecycle commands and explicit install scopes.

Computer dimension:

- Installed plugin registry is `~/.claude/plugins/installed_plugins.json`.
- User enablement is stored in `~/.claude/settings.json` under `enabledPlugins`.
- User scope applies across projects.
- Native commands:
  - `claude plugin list --json`
  - `claude plugin enable <plugin>@<marketplace> --scope user`
  - `claude plugin disable <plugin>@<marketplace> --scope user`
  - `claude plugin update <plugin>@<marketplace> --scope user`

Project dimension:

- Claude supports `project` and `local` plugin scopes.
- Project scope is shared through repository settings; local scope is for one user's checkout.
- Orbita only shows project/local installs for the active repository unless the user is viewing This Mac.
- Native commands use `--scope project` or `--scope local`.

Update semantics:

- Claude Code uses plugin version as the cache key. If `plugin.json` or the marketplace entry has a version, that value must change before updates are detected.
- If no explicit version is present, the git commit SHA can be used as the effective update key.
- After install/enable/disable/update inside a Claude Code session, `/reload-plugins` applies changes without restarting the whole client.

Orbita implementation:

- Scan `installed_plugins.json` and `enabledPlugins`.
- Preserve scope in capability metadata: `user`, `project`, or `local`.
- Expose native `list`, `enable`, `disable`, and `update` commands in the inspector.
- Never write Claude plugin files directly; use Claude's CLI for lifecycle mutation.

## Sorting and Sections

The main capability grid is sectioned by effective status:

- Enabled: native or `.agents` intent is enabled.
- Disabled: native config or `.agents` intent is disabled.
- Discovered: visible but not explicitly enabled/disabled.

Each section supports these stable sort modes:

- Name: case-insensitive name, then id.
- Modified newest: newest `modifiedAt`, then name.
- Modified oldest: oldest `modifiedAt`, then name.

Grouping still happens before section placement so plugin tiles keep their child capabilities together.

## Update Checks and Triggers

Orbita stores maintenance commands in capability metadata:

- `checkCommand`: list or refresh command that verifies installed/current state.
- `updateCommand`: command that updates this plugin or skill.
- `enableCommand` and `disableCommand`: native lifecycle command, or a Codex config write description.

The settings Plugins page provides broad maintenance commands:

- Codex: `codex plugin marketplace upgrade`
- Claude Code: `claude plugin list --json`
- .agents: `npx skills update -p -y` for an opened project, otherwise `npx skills update -y`

The inspector provides targeted commands for the selected plugin or skill.

## GitHub Release Automation

Orbita releases are tag-driven.

- Local trigger: `script/release_github.sh vX.Y.Z`
- CI trigger: push a tag matching `v*`, or run the Release workflow manually.
- CI workflow: `.github/workflows/release.yml`
- Build: Xcode Release build with `CODE_SIGNING_ALLOWED=NO`
- Package: `script/package_dmg.sh <Orbita.app> vX.Y.Z <output.dmg>` creates a compressed DMG with `Orbita.app` and an `/Applications` shortcut.
- Artifact: `Orbita-vX.Y.Z.dmg`
- Publish: GitHub Release with generated release notes.

Version information displayed in Settings comes from the app bundle:

- `CFBundleShortVersionString`
- `CFBundleVersion`
- `CFBundleIdentifier`

Before publishing a signed public release, add Developer ID signing and notarization. The current workflow creates an unsigned developer artifact suitable for internal validation.

## References

- Claude Code plugin reference: https://code.claude.com/docs/en/plugins-reference
- Claude Code plugin discovery and management: https://code.claude.com/docs/zh-CN/discover-plugins
- Skills CLI repository reference: https://github.com/vercel-labs/skills?lang=zh-CN&open_in_browser=true
