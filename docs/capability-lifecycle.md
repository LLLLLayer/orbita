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
- Read project `skills-lock.json` and the global Skills CLI lock file (`$XDG_STATE_HOME/skills/.skill-lock.json` or `~/.agents/.skill-lock.json`) when present.
- Surface Skills CLI source metadata on each locked skill, including source, source type, ref, skill path, update hash, canonical path, and inferred agent install targets.
- Use the Skills CLI agent path catalog for read-only install-target inference and for the Add Agent preset list.
- Generate adapter previews under `<repo>/.agents/adapters/<agent>/capabilities.json`.
- Apply writes only inside project `.agents` for merge/enable/disable/delete/clean/rollback.
- Expose `.agents` skill check, reinstall, update, and remove commands in the inspector while leaving installation and update execution to `npx skills`.
- Skip nested `Tests/**/Fixtures` directories during broad project Skill discovery so Orbita does not treat its own or a repository's fixture dependencies as active project capabilities.

## Codex Desktop

Codex Desktop and the Codex CLI keep plugin installation and enablement in Codex-owned locations.

Computer dimension:

- Installed plugin cache is under `~/.codex/plugins/cache/<marketplace>/<plugin>/<version>/`.
- A Codex plugin manifest is `<plugin-root>/.codex-plugin/plugin.json`; some compatible marketplace entries may use `.claude-plugin/plugin.json`.
- Enabled state is stored in `~/.codex/config.toml` as `[plugins."<plugin>@<marketplace>"] enabled = true|false`.
- Marketplace-visible enablement must go through `codex plugin add <plugin>@<marketplace>`. This creates or refreshes the installed plugin cache and writes the local enablement state. Only writing `enabled = true` is a config fallback and can leave Codex Desktop's marketplace UI showing the plugin as off.
- Disable currently has no public `codex plugin disable` CLI command. Orbita keeps the installed cache and writes `enabled = false` in `config.toml`.
- Delete/uninstall should use `codex plugin remove <plugin>@<marketplace>` when the intent is to remove the installed plugin cache and local config entry.
- Marketplace update check is `codex plugin marketplace upgrade [marketplace]`.
- Reinstall/update trigger is `codex plugin add <plugin>@<marketplace>` after marketplace snapshots are refreshed.

Project dimension:

- Project-level Codex commands, hooks, plugin config, and other Codex-native project settings remain under `<repo>/.codex`.
- Project-level Codex skills use `<repo>/.agents/skills`. Codex scans `.agents/skills` from the current working directory up to the repository root, so root-level `<repo>/.agents/skills` is visible to Codex sessions launched anywhere inside that repo.
- Codex does not consume every file in `.agents`; Orbita's `<repo>/.agents/manifest.json`, `<repo>/.agents/lock.json`, adapters, and logs are Orbita management metadata.
- Codex can disable non-plugin `SKILL.md` paths with `[[skills.config]] path = ".../SKILL.md" enabled = false` in `~/.codex/config.toml`. This is Codex-specific visibility, not deletion and not necessarily a disable for Claude Code or other agents.
- Capabilities bundled inside a Codex plugin follow the plugin lifecycle. Disabling one of those skills, hooks, or commands in Orbita updates `[plugins."<selector>"] enabled = false` rather than writing a per-skill override.
- If a repository contains project plugin sources, Orbita treats them as project scope only when they are inside `<repo>/plugins/` and have a `.codex-plugin/plugin.json` or `.claude-plugin/plugin.json` manifest.
- Project `.codex/config.toml`, when present, is the project-level native config Orbita can inspect for plugin enablement.

Orbita implementation:

- Scan Codex plugin cache manifests and map `config.toml` enablement into `enabled`/`disabled`.
- Scan non-plugin `[[skills.config]]` path entries in `~/.codex/config.toml` and hide matching skills only from Codex when `enabled = false`.
- For user-scope Codex enable, run `codex plugin add <selector>` so Codex owns both installed-cache creation and enabled state.
- For project-local Codex plugin enablement, update the relevant project `[plugins."<selector>"] enabled` key because there is no marketplace install command for raw project plugin sources.
- For Codex disable, update the relevant `[plugins."<selector>"] enabled = false` key until the Codex CLI exposes a native disable command.
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
  - `claude plugin remove <plugin>@<marketplace> --scope user -y`

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
- Expose native `list`, `enable`, `disable`, `update`, and `delete` commands in the inspector.
- Never write Claude plugin files directly; use Claude's CLI for lifecycle mutation.
- Claude plugin children inherit plugin lifecycle actions; deleting or disabling a plugin child acts on the plugin package.
- Claude native skills use `skillOverrides` for enablement. Project skills write `.claude/settings.json`; user skills write `~/.claude/settings.json`; enable removes the matching override from the settings file where it was found.
- Claude `.mcp.json` project servers use `disabledMcpjsonServers` for enablement and remove the named server from `.mcp.json` for delete.
- Claude settings hooks do not expose per-hook disable. Orbita only supports deleting a single scanned hook entry from its settings JSON.

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
- `deleteCommand`: native delete command when the host owns deletion.

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
- Build: Xcode Release build signed with a Developer ID Application certificate.
- Package: `script/package_dmg.sh <Orbita.app> vX.Y.Z <output.dmg>` creates a compressed DMG with `Orbita.app` and an `/Applications` shortcut.
- Notarize: GitHub Actions submits the DMG with `xcrun notarytool`, staples the ticket with `xcrun stapler`, and validates the final DMG with `spctl`.
- Artifact: `Orbita-vX.Y.Z.dmg`
- Publish: GitHub Release with generated release notes.

Public releases require these GitHub secrets before the workflow can run:

- `APPLE_DEVELOPER_ID_CERTIFICATE_BASE64`
- `APPLE_DEVELOPER_ID_CERTIFICATE_PASSWORD`
- `DEVELOPER_ID_APPLICATION`
- `APPLE_ID`
- `APPLE_TEAM_ID`
- `APPLE_APP_SPECIFIC_PASSWORD`
- `SPARKLE_PRIVATE_ED_KEY`
- `SPARKLE_PUBLIC_ED_KEY`

Sparkle is the intended updater model for automatic version checks:

- The app embeds Sparkle and adds a `Check for Updates...` app menu action.
- Sparkle starts only when `SUFeedURL` is HTTPS and `SUPublicEDKey` contains a real EdDSA public key.
- `SUFeedURL` must point to an HTTPS appcast.
- `SUPublicEDKey` must contain the EdDSA public key generated by Sparkle.
- Every published update archive must be signed for Sparkle, then Developer ID signed and notarized for Gatekeeper.
- CI publishes `appcast.xml` as a GitHub Release asset next to the DMG.

Version information displayed in Settings comes from the app bundle:

- `CFBundleShortVersionString`
- `CFBundleVersion`
- `CFBundleIdentifier`

See `docs/release.md` for the complete release checklist.

## References

- Claude Code plugin reference: https://code.claude.com/docs/en/plugins-reference
- Claude Code plugin discovery and management: https://code.claude.com/docs/zh-CN/discover-plugins
- Codex skills reference: https://developers.openai.com/codex/skills
- Skills CLI repository reference: https://github.com/vercel-labs/skills?lang=zh-CN&open_in_browser=true
- Apple Developer ID: https://developer.apple.com/developer-id/
- Apple notarization: https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution
- Sparkle documentation: https://sparkle-project.org/documentation/
