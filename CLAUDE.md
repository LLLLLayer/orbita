# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Orbita is a macOS console for managing Coding Agent capabilities (Skills, Plugins, Commands, Hooks, MCP servers, Rules, Instructions) across Codex Desktop, Claude Code, Cursor, Trae, and the cross-agent `.agents` workspace. The repository ships three things from one SwiftPM package: a core library, a `orbita` CLI, and a SwiftUI macOS app.

The canonical agent list is the `AgentID` enum in `Models.swift`: `codex`, `claude-code`, `cursor`, `trae`. The App's default tab strip (`AgentSelection.defaultAgents`) is `.agents`, Codex, Claude Code, Trae — Cursor is still a fully scannable/resolvable agent but is intentionally omitted from the default tabs.

Targets:

- `OrbitaCore` — scan/resolve/agent-view/overview/adapter-preview/drift/doctor/apply-plan logic. All semantics live here.
- `OrbitaCLI` — produces the `orbita` executable. Thin wrapper that calls into `OrbitaCore` and prints text or `--json`.
- `OrbitaApp` — SwiftUI macOS app. Reuses `OrbitaCore` and adds Sparkle (auto-update) and Textual (in-app Markdown rendering). `OrbitaApp` is the SwiftPM executable product name; the Xcode scheme that builds the app is **`Orbita`** (`script/xcode_build.sh` sets `APP_SCHEME="Orbita"`), and the CLI is the `orbita` SwiftPM executable.

Platform: macOS 15+, Swift 6 (Xcode with `swift-tools-version: 6.0`).

## Build, run, test

```bash
swift build                       # SwiftPM build of all targets
swift test                        # OrbitaCoreTests + OrbitaCLITests
swift test --filter <name>        # single test
./script/xcode_build.sh build     # xcodebuild against Orbita.xcodeproj (App scheme)
./script/xcode_build.sh test      # delegates to swift test
./script/build_and_run.sh         # build + open Orbita.app
./script/build_and_run.sh --verify     # build + open + assert process is running
./script/build_and_run.sh --telemetry  # stream OSLog subsystem dev.orbita.app
swift run orbita <command>        # run the CLI from source
```

Releases are tag-driven. `script/release_github.sh vX.Y.Z` builds, signs (if `DEVELOPER_ID_APPLICATION` is set), packages a DMG, optionally notarizes (`NOTARIZE=1` with `APPLE_*` secrets), generates a Sparkle appcast (with `SPARKLE_*_ED_KEY`), tags, and pushes. Pushing the tag triggers `.github/workflows/release.yml`. See `docs/release.md`.

**Adding a source file:** `Orbita.xcodeproj` registers each file explicitly (`PBXFileReference` + Sources build phase), not via Xcode file-system-synchronized groups. `swift build`/`swift test` auto-discover new `.swift` files, but `./script/xcode_build.sh` (the App build) silently omits any file not added to `project.pbxproj`. After creating a new `OrbitaCore`/`OrbitaApp`/`OrbitaCLI` source, add its three pbxproj entries (build-file, file-reference, group child) or the App target won't compile it.

## CLI commands

The CLI is the canonical product surface — the App is a viewer over the same logic. Common shapes:

```bash
swift run orbita help                                       # or --help / -h / no args
swift run orbita scan     --project-root <path> [--json]
swift run orbita status   --project-root <path> [--json]
swift run orbita graph    --project-root <path> [--json]
swift run orbita overview --project-root <path> [--json]
swift run orbita drift    --project-root <path> [--json]
swift run orbita agent    --project-root <path> [--agent codex|claude-code|cursor|trae] [--json]
swift run orbita explain  --project-root <path> <capability-id> [--json]
swift run orbita preview  --project-root <path> --agent <id> [--json]
swift run orbita doctor   [--project-root <path>] [--json]
swift run orbita plan     --project-root <path> --merge|--rollback|--clean|--enable <id>|--disable <id>|--delete <id> [--apply] [--json]
swift run orbita plan     --project-root <path> --sync <id> --agent <id> [--mode copy|symlink] [--scope project|user] [--apply] [--json]
swift run orbita plan     --project-root <path> --resync <id> --agent <id> [--scope project|user] [--apply] [--json]
```

`--resync <id> --agent <id>` refreshes an existing **copied** fork whose source has since changed (a `copiedMirror` marked `drifted`): it backs the diverged copy up into the scope-correct `.orbita/fork-backups` store, then overwrites it with a fresh copy from the source. Pass the same source id/agent/scope the original `--sync` used. `--no-user-scope` restricts scanning to the project. `--project-root <path>` and `--project <path>` are synonyms; the path can also be a positional argument. `plan` without `--apply` prints a dry run; with `--apply` it returns completed/failed/pending operations. `agent` defaults to `codex` and its text output lists hidden capabilities too. Exit codes: `0` success, `1` runtime error, `2` a resolved graph carries an `.error` issue (e.g. malformed `.agents/manifest.json`) — emitted by every read-only graph-consuming command (`scan`/`status`/`graph`/`drift`/`overview`/`agent`/`explain`/`preview`); `plan` is excluded by design (it may repair the manifest and owns its own `0`/`1` exit codes).

## Architecture (read this before changing scanner/apply behavior)

Pipeline is one-directional and lives in `Sources/OrbitaCore/`:

1. **Scan** — `CapabilityScanner` walks user-scope and project-scope sources (Codex plugin cache, `~/.codex/config.toml`, `~/.claude/...`, project `.codex/`, `.claude/`, `.cursor/`, `.cursorrules`, `.mcp.json`, `.agents/`, package skills, etc.) and emits raw `Capability` records plus `ScanIssue`s. The scanner is large by design (~3k lines) — each agent's discovery rules are concentrated here. Skill-file discovery is capped per source by `ScanOptions.maxSkillFiles` (default 500; App-configurable in Settings, `0` = no limit); when the cap is hit the scanner emits a `.warning` `ScanIssue` ("Stopped after N skill files") rather than silently truncating.
2. **Resolve** — `CapabilityResolver` overlays `.agents/manifest.json` intent onto scanned capabilities, infers virtual plugin tiles from package metadata, and marks `duplicate`/`shadowed`/`drifted`. The resolver consumes a `ScanResult` and returns a `CapabilityGraph`.
3. **Project layers** — `AgentViewResolver` produces per-agent visible/hidden views; `AgentOverviewBuilder` summarizes diffs across agents; `AdapterPreviewBuilder` produces the `<repo>/.orbita/adapters/<agent>/capabilities.json` previews; `DriftReportBuilder` and `DoctorReportBuilder` produce diagnostics; `CapabilityExplainer` answers "why does agent X see capability Y."
4. **Apply** — `ApplyPlanBuilder` builds a typed `ApplyPlan` (`enable | disable | delete | merge | rollback | clean`) of `ApplyOperation`s. `ApplyPlanExecutor` is the only thing that mutates disk.

Core data model is in `Sources/OrbitaCore/Models.swift`: `Capability` (id/name/type/scope/statuses[]/risks[]/source/pluginID/metadata) is the single shape passed between layers. A capability can hold multiple `CapabilityStatus` values simultaneously (e.g. `[disabled, drifted]`).

### App layer (SwiftUI over Core)

The App never reimplements pipeline logic — it drives `OrbitaCore` and renders the result. Three things to know before changing App code:

- **`ProjectCapabilityStore`** is the central `@MainActor` view-model: it runs the scan→resolve→view pipeline for the selected project and publishes the graph/views to SwiftUI. Most App features hang off this store.
- **Orbita's own state lives in `~/.orbita/`** (distinct from the agent dotdirs it manages): `CapabilitySnapshotStore` persists scan snapshots (`CapabilitySnapshot`, schema-versioned), and `ProjectLibraryStore` persists the recent-projects list. Bump the schema version when changing those shapes.
- **Real in-app i18n** via `LocalizationManager.shared` (English, Simplified Chinese, Traditional Chinese). User-facing strings go through `L("key")` / `String.localized("key")` with a key added to all three dictionaries; missing keys fall back to English then the raw key. The three `README.*.md` files mirror these languages.

### Invariants to preserve

- **Apply Plan write boundary.** Apply writes inside the project's `.agents/` and `.orbita/`, **plus** two anchored carve-outs: (1) for agent-sync (fork) — the destination agent's own skills/commands/agents directories in the project and under the user's agent home (validated against the project root, the user-home agent dotdirs, and the `SkillsAgentCatalog` global roots); (2) for the **disabled-store fallback** — the scope-correct quarantine roots `<repo>/.orbita/disabled` and the user's own `~/.orbita/disabled` (anchored via `isDisabledStorePath`; `~/.orbita` is Orbita's own state dir, never an agent's). The guard is anchored, not a "path contains `.codex`/`.orbita`" membership test. The fork carve-out exists because synced `skill`/`command`/`agent` files have no native enable-state; the disabled-store carve-out exists because a host with **no native disable** (e.g. Trae/Cursor skills) can only be disabled by moving its source aside — see the next bullet. A third, parallel store — the **fork-backup store** `<repo>/.orbita/fork-backups` and `~/.orbita/fork-backups` (anchored via `isForkBackupStorePath`) — receives the diverged copy that `plan --resync` moves aside (via the `.backupPath` op) before overwriting a copied fork; it is scope-bound to the copy's own base exactly like the disabled store, and is write-only/never read back as a capability. The executor handles the macOS `/var` ↔ `/private/var` symlink case explicitly — do not bypass that check. Everything else (`~/.codex/config.toml`, `~/.claude/settings.json`, plugin caches) must be expressed as an emitted shell command for the user/native CLI, not a direct write. See `docs/capability-lifecycle.md` for the exact allowed write set.
- **Three layers, three locations.** Source = real files / cache / package; Intent = `.agents/manifest.json`; Visibility = per-agent. Don't conflate them. A `.agents` "disable" hides the capability via intent; the source file stays where it is. **Exception — the disabled-store fallback:** a host with no native off-switch ignores `.agents` intent entirely, so for those Orbita physically moves the source into the scope-correct, data-grade `OrbitaDisabledStore` (`.orbita/disabled`, never a "cache") with a co-located `.orbita-restore.json` sidecar, and the scanner reads the store back so the disabled tile survives loss of the manifest. This fallback is **native-first gated** (`hasNativeDisable`): a capability the host *can* disable in place (Codex `[[skills.config]]`, Claude `skillOverrides`) is never moved.
- **Source of truth = native client.** For Codex enablement the truth lives in `~/.codex/config.toml` and the plugin cache; for Claude it's `~/.claude/settings.json` + `installed_plugins.json`. Lifecycle mutations on those go through `codex plugin …` / `claude plugin …`. See `docs/capability-lifecycle.md` for the full per-agent table.
- **Hooks are flattened per handler.** A `settings.json` or `hooks.json` registers many handlers; the scanner emits one capability per `event → matcher group → hooks[]` entry, keyed by `<source>:<event>:<matcherIdx>:<handlerIdx>`. Claude has no per-hook disable, so the only Apply action on a single hook is delete. See `docs/hook-logic.md`.
- **Skills CLI is read-only here.** Orbita reads `skills-lock.json` / `.skill-lock.json` and exposes `npx skills …` commands in the inspector — it does not run installs/updates itself. The one exception is agent-sync (fork), which physically copies/symlinks a skill into an agent's dir as a deliberately **lock-less, Orbita-managed** install: it never runs `npx skills` and never writes a skills-lock file, so the lock files stay read-only.
- **Skip nested `Tests/**/Fixtures`.** Scanner ignores fixture dependencies during broad project Skill discovery so the repo's own test fixtures aren't surfaced as live capabilities.
- **Shared single-definition modules (anti-drift).** Several cross-cutting rules are centralized in one small module each, every one created to kill a *drifted duplicate* where a one-sided edit had silently desynced two callers: `CapabilityClassifier` (`CapabilityClassification.swift`) backs both `AgentViewResolver` visibility and `AdapterPreviewBuilder` mapping, so view-visible and preview-`supported` agree by construction; `AgentSyncPolicy` (`AgentSyncPolicy.swift`) is the single fork-compatibility rule shared by `ApplyPlanBuilder` (enforces, throws on violation) and the App's sync sheet (greys out incompatible agents); `ClaudePluginResolution` (`ClaudePluginResolution.swift`) is the single "which cached plugin install does a Claude session actually load" precedence rule (highest precedence per `pluginSelector`, shadowed installs and their children dropped), shared by `CapabilityResolver` (graph-wide) and `AgentViewResolver` (Claude view). The methods left on the resolver/preview/planner are thin delegating wrappers — extend the shared module, do not re-fork the logic into a caller.

## Tests and fixtures

- `Tests/OrbitaCoreTests/CapabilityScannerTests.swift` is the dominant test file (~5k lines). Most behavioral changes need a new fixture and a new scanner/resolver assertion here. Fixtures live under `Tests/OrbitaCoreTests/Fixtures/` and are copied into the test bundle via the package manifest.
- `Tests/OrbitaCLITests/OrbitaCLIErrorTests.swift` exercises the CLI argument parser and error-payload shape (`--json` returns a structured `CLIErrorPayload` / `CLIApplyExecutionErrorPayload`).
- `OrbitaCLI.runForTesting(arguments:)` is the supported entry point for CLI tests — it returns stdout/stderr/exit code without touching real `FileHandle`s.

## Telemetry

Logging subsystem is `dev.orbita.app`. Notable categories: `App`, `Scan`, `Apply`. Scan log lines (`scan.start`, `scan.phase`, `scan.finish`, `scan.failed`) include capability counts, issue counts, and duration. Use `./script/build_and_run.sh --telemetry` to stream them.

## Documentation map

- `docs/capability-lifecycle.md` — authoritative per-agent enable/disable/update/delete contract for `.agents`, Codex Desktop, Claude Code, plus release automation. Read before changing lifecycle behavior.
- `docs/hook-logic.md` — hook scanner contract (event/matcher/handler model, host inference heuristics).
- `docs/agent-extension-landscape.zh-CN.md` — public research reference (Simplified Chinese): how Codex/Claude Code/Cursor/Trae each *discover* and *disable* extensions, the `npx skills`/`.agents/` convention (official spec vs community), and how Orbita's three-layer model reconciles it. Notes known scanner-vs-official-docs divergences.
- `docs/agent-capability-control-plane.zh-CN.md` — public research reference (Simplified Chinese) on capability-*context* governance: what each capability type injects into an agent's context, and when each governance lever (default-hide, lazy-load, scoping) is worth pulling. The "why" behind Orbita's visibility model; read before changing what counts as visible vs hidden.
- `docs/release.md` — signing, notarization, DMG, Sparkle appcast checklist.
- `docs/internal/` — gitignored research/planning notes; do not add internal-only material outside this folder.
