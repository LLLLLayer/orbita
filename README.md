<div align="center">
  <img src="docs/assets/orbita-logo.png" alt="Orbita" width="160" />
  <h1>Orbita</h1>
  <p><strong>A macOS console for managing Coding Agent capabilities.</strong></p>
  <p>
    <a href="https://github.com/LLLLLayer/orbita/releases/latest">Download</a> ·
    <a href="docs/capability-lifecycle.md">Lifecycle</a> ·
    <a href="docs/release.md">Release</a>
  </p>
  <p>
    English ·
    <a href="README.zh-CN.md">简体中文</a> ·
    <a href="README.zh-TW.md">繁體中文</a>
  </p>
</div>

---

Orbita scans your machine and the current project to show what Codex Desktop, Claude Code, the cross-agent `.agents` workspace, and Cursor will actually load — Skills, Plugins, Commands, Hooks, MCP servers, Rules, and Instructions. It is not another plugin store; it's a local source of truth for **where a capability comes from, which agent can see it, and whether anything has drifted, conflicts, or carries risk**.

The repository ships three things from one SwiftPM package:

- **OrbitaCore** — scan / resolve / agent-view / overview / adapter-preview / drift / doctor / apply-plan logic.
- **`orbita` CLI** — thin wrapper around `OrbitaCore` with text and `--json` output.
- **OrbitaApp** — SwiftUI macOS app over the same core, with Sparkle auto-update.

## Download

Pre-built signed and notarized DMGs are published on every tag.

- **Latest release:** [github.com/LLLLLayer/orbita/releases/latest](https://github.com/LLLLLayer/orbita/releases/latest)
- **All releases:** [github.com/LLLLLayer/orbita/releases](https://github.com/LLLLLayer/orbita/releases)
- The app updates itself in place via [Sparkle](https://sparkle-project.org).

Requirements: macOS 15 or newer.

## What Orbita can manage

- `SKILL.md`-based Agent Skills.
- Codex Desktop Plugins, Skills, Commands, Hooks, MCP configs, and project files.
- Claude Code Plugins, Commands, Hooks, Settings, and project Instructions.
- `.agents` capability intent, generated adapter previews, and lock data.
- Cursor rules, legacy `.cursorrules`, `.mcp.json`, and shared project metadata.
- Virtual Plugins inferred from package contents, local directories, and plugin caches.

## Core capabilities

- **Capability graph.** Unified scan across user scope, project scope, native agent configs, plugin caches, and `.agents` intent.
- **Agent perspective.** Overview, Agents, Codex, and Claude Code views show what each agent can actually see.
- **Lifecycle management.** `merge`, `enable`, `disable`, `delete`, `clean`, `rollback`, update checks, and triggers for native plugin updates.
- **Skills CLI compatibility.** Reads `skills-lock.json` / `.skill-lock.json`, surfaces source / ref / hash / skillPath, canonical paths, and inferred install targets.
- **Drift diagnostics.** Explains broken paths, duplicates, shadowed entries, disabled-but-still-discovered, and review flags.
- **Risk visibility.** Flags read-file, write-file, command execution, network access, secrets, and global scope.
- **Three-layer model.** Source (real files / cache / package) vs. Intent (`.agents/manifest.json`) vs. Visibility (per-agent) — never conflated.
- **Release automation.** GitHub Release workflow with code signing, notarized DMG, and Sparkle appcast.

## Build and debug from source

```bash
swift build                       # SwiftPM build of all targets
swift test                        # OrbitaCoreTests + OrbitaCLITests
swift test --filter <name>        # single test
./script/xcode_build.sh build     # xcodebuild against Orbita.xcodeproj (App scheme)
./script/build_and_run.sh         # build + open Orbita.app
./script/build_and_run.sh --verify     # build + open + assert process is running
./script/build_and_run.sh --telemetry  # stream OSLog subsystem dev.orbita.app
swift run orbita <command>        # run the CLI from source
```

Debug tips:

- **Stream telemetry:** `./script/build_and_run.sh --telemetry` tails the `dev.orbita.app` OSLog subsystem (`App`, `Scan`, `Apply` categories). Scan log lines (`scan.start`, `scan.phase`, `scan.finish`, `scan.failed`) include capability counts, issue counts, and duration.
- **Drive from the CLI:** the App is a viewer over the same logic — `swift run orbita scan|status|graph|overview|drift|agent|explain|preview|doctor|plan` exercises every code path the App does. Add `--json` for machine output.
- **Inspect a single capability:** `swift run orbita explain --project-root <path> <capability-id>`.
- **Dry-run a change:** `swift run orbita plan --project-root <path> --merge` (or `--enable`, `--disable`, `--delete`, `--rollback`, `--clean`). Add `--apply` to write.
- **Open in Xcode:** `open Orbita.xcodeproj`.

## CLI overview

```bash
swift run orbita scan     --project-root <path> [--json]
swift run orbita status   --project-root <path> [--json]
swift run orbita graph    --project-root <path> [--json]
swift run orbita overview --project-root <path> [--json]
swift run orbita drift    --project-root <path>
swift run orbita agent    --project-root <path> --agent codex|claude-code|cursor
swift run orbita explain  --project-root <path> <capability-id>
swift run orbita preview  --project-root <path> --agent <id>
swift run orbita doctor   [--project-root <path>]
swift run orbita plan     --project-root <path> --merge|--rollback|--clean|--enable <id>|--disable <id>|--delete <id> [--apply] [--json]
```

`--no-user-scope` restricts scanning to the project. `plan` without `--apply` prints a dry run; with `--apply` it returns completed / failed / pending operations.

## Project structure

```text
Sources/
  OrbitaCore/   scan, resolve, graph model, Apply Plan, status reports
  OrbitaCLI/    scan/status/overview/plan/doctor entry points
  OrbitaApp/    SwiftUI macOS app and capability console
Support/        bundle metadata, entitlements, release config
Tests/          scanner, resolver, Apply Plan, CLI, fixtures
docs/           public docs, lifecycle spec, release checklist
script/         local build, run, package, sign, release scripts
```

## Documentation

- [docs/capability-lifecycle.md](docs/capability-lifecycle.md) — authoritative per-agent enable / disable / update / delete contract.
- [docs/hook-logic.md](docs/hook-logic.md) — hook scanner contract (event / matcher / handler model, host inference).
- [docs/release.md](docs/release.md) — signing, notarization, DMG, Sparkle appcast checklist.

## License

Orbita is released under the [MIT License](LICENSE).

## Acknowledgements

Orbita is built on the work of the open-source community. In particular it depends on:

- [**Sparkle**](https://github.com/sparkle-project/Sparkle) — software update framework for macOS apps. MIT License.
- [**Textual**](https://github.com/gonzalezreal/textual) — Markdown rendering for SwiftUI. MIT License.

The project also takes inspiration from Codex Desktop, Claude Code, Cursor, and the broader Coding Agent ecosystem whose capability formats Orbita reads.
