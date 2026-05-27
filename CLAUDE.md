# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Orbita is a macOS console for managing Coding Agent capabilities (Skills, Plugins, Commands, Hooks, MCP servers, Rules, Instructions) across Codex Desktop, Claude Code, Cursor, and the cross-agent `.agents` workspace. The repository ships three things from one SwiftPM package: a core library, a `orbita` CLI, and a SwiftUI macOS app.

Targets:

- `OrbitaCore` — scan/resolve/agent-view/overview/adapter-preview/drift/doctor/apply-plan logic. All semantics live here.
- `OrbitaCLI` — produces the `orbita` executable. Thin wrapper that calls into `OrbitaCore` and prints text or `--json`.
- `OrbitaApp` — SwiftUI macOS app. Reuses `OrbitaCore` and adds Sparkle update integration. `OrbitaApp` is the Xcode scheme name; the CLI scheme is `Orbita`/`orbita` via SwiftPM.

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

## CLI commands

The CLI is the canonical product surface — the App is a viewer over the same logic. Common shapes:

```bash
swift run orbita scan     --project <path> [--json]
swift run orbita status   --project <path> [--json]
swift run orbita graph    --project <path> [--json]
swift run orbita overview --project <path> [--json]
swift run orbita drift    --project <path>
swift run orbita agent    --project <path> --agent codex|claude-code|cursor
swift run orbita explain  --project <path> <capability-id>
swift run orbita preview  --project <path> --agent <id>
swift run orbita doctor   [--project <path>]
swift run orbita plan     --project <path> --merge|--rollback|--clean|--enable <id>|--disable <id>|--delete <id> [--apply] [--json]
```

`--no-user-scope` restricts scanning to the project. `plan` without `--apply` prints a dry run; with `--apply` it returns completed/failed/pending operations.

## Architecture (read this before changing scanner/apply behavior)

Pipeline is one-directional and lives in `Sources/OrbitaCore/`:

1. **Scan** — `CapabilityScanner` walks user-scope and project-scope sources (Codex plugin cache, `~/.codex/config.toml`, `~/.claude/...`, project `.codex/`, `.claude/`, `.cursor/`, `.cursorrules`, `.mcp.json`, `.agents/`, package skills, etc.) and emits raw `Capability` records plus `ScanIssue`s. The scanner is large by design (~2.7k lines) — each agent's discovery rules are concentrated here.
2. **Resolve** — `CapabilityResolver` overlays `.agents/manifest.json` intent onto scanned capabilities, infers virtual plugin tiles from package metadata, and marks `duplicate`/`shadowed`/`drifted`. The resolver consumes a `ScanResult` and returns a `CapabilityGraph`.
3. **Project layers** — `AgentViewResolver` produces per-agent visible/hidden views; `AgentOverviewBuilder` summarizes diffs across agents; `AdapterPreviewBuilder` produces the `<repo>/.agents/adapters/<agent>/capabilities.json` previews; `DriftReportBuilder` and `DoctorReportBuilder` produce diagnostics; `CapabilityExplainer` answers "why does agent X see capability Y."
4. **Apply** — `ApplyPlanBuilder` builds a typed `ApplyPlan` (`enable | disable | delete | merge | rollback | clean`) of `ApplyOperation`s. `ApplyPlanExecutor` is the only thing that mutates disk.

Core data model is in `Sources/OrbitaCore/Models.swift`: `Capability` (id/name/type/scope/statuses[]/risks[]/source/pluginID/metadata) is the single shape passed between layers. A capability can hold multiple `CapabilityStatus` values simultaneously (e.g. `[disabled, drifted]`).

### Invariants to preserve

- **Apply Plan write boundary.** Apply only writes inside the project's `.agents/`. The executor handles the macOS `/var` ↔ `/private/var` symlink case explicitly — do not bypass that check. Anything else (`~/.codex/config.toml`, `~/.claude/settings.json`, plugin caches) must be expressed as an emitted shell command for the user/native CLI, not a direct write.
- **Three layers, three locations.** Source = real files / cache / package; Intent = `.agents/manifest.json`; Visibility = per-agent. Don't conflate them. A `.agents` "disable" hides the capability via intent; the source file stays where it is.
- **Source of truth = native client.** For Codex enablement the truth lives in `~/.codex/config.toml` and the plugin cache; for Claude it's `~/.claude/settings.json` + `installed_plugins.json`. Lifecycle mutations on those go through `codex plugin …` / `claude plugin …`. See `docs/capability-lifecycle.md` for the full per-agent table.
- **Hooks are flattened per handler.** A `settings.json` or `hooks.json` registers many handlers; the scanner emits one capability per `event → matcher group → hooks[]` entry, keyed by `<source>:<event>:<matcherIdx>:<handlerIdx>`. Claude has no per-hook disable, so the only Apply action on a single hook is delete. See `docs/hook-logic.md`.
- **Skills CLI is read-only here.** Orbita reads `skills-lock.json` / `.skill-lock.json` and exposes `npx skills …` commands in the inspector — it does not run installs/updates itself.
- **Skip nested `Tests/**/Fixtures`.** Scanner ignores fixture dependencies during broad project Skill discovery so the repo's own test fixtures aren't surfaced as live capabilities.

## Tests and fixtures

- `Tests/OrbitaCoreTests/CapabilityScannerTests.swift` is the dominant test file (~3k lines). Most behavioral changes need a new fixture and a new scanner/resolver assertion here. Fixtures live under `Tests/OrbitaCoreTests/Fixtures/` and are copied into the test bundle via the package manifest.
- `Tests/OrbitaCLITests/OrbitaCLIErrorTests.swift` exercises the CLI argument parser and error-payload shape (`--json` returns a structured `CLIErrorPayload` / `CLIApplyExecutionErrorPayload`).
- `OrbitaCLI.runForTesting(arguments:)` is the supported entry point for CLI tests — it returns stdout/stderr/exit code without touching real `FileHandle`s.

## Telemetry

Logging subsystem is `dev.orbita.app`. Notable categories: `App`, `Scan`, `Apply`. Scan log lines (`scan.start`, `scan.phase`, `scan.finish`, `scan.failed`) include capability counts, issue counts, and duration. Use `./script/build_and_run.sh --telemetry` to stream them.

## Documentation map

- `docs/capability-lifecycle.md` — authoritative per-agent enable/disable/update/delete contract for `.agents`, Codex Desktop, Claude Code, plus release automation. Read before changing lifecycle behavior.
- `docs/hook-logic.md` — hook scanner contract (event/matcher/handler model, host inference heuristics).
- `docs/release.md` — signing, notarization, DMG, Sparkle appcast checklist.
- `docs/internal/` — gitignored research/planning notes; do not add internal-only material outside this folder.
