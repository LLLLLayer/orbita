<div align="center">
  <a href="https://github.com/LLLLLayer/orbita/releases/latest">
    <img src="docs/assets/orbita-logo.png" alt="Orbita" width="128" />
  </a>
  <h1>Orbita</h1>
  <p><strong>See what every coding agent on your Mac actually loads — and what drifted, conflicts, or carries risk.</strong></p>
  <p>A local macOS console and CLI that reconciles Codex Desktop, Claude Code, Trae, Cursor, plugin caches, and the cross-agent <code>.agents</code> workspace into one source of truth. <strong>Not a plugin store.</strong></p>

  <p>
    <a href="https://github.com/LLLLLayer/orbita/releases/latest"><strong>Download for macOS</strong></a> ·
    <a href="#quickstart">Quickstart</a> ·
    <a href="#what-it-does">What it does</a> ·
    <a href="#cli--same-engine-scriptable">CLI</a> ·
    <a href="docs/capability-lifecycle.md">Docs</a>
  </p>

  <p>
    <a href="https://github.com/LLLLLayer/orbita/releases/latest"><img alt="Latest release" src="https://img.shields.io/github/v/release/LLLLLayer/orbita?sort=semver&label=release"></a>
    <a href="LICENSE"><img alt="License: MIT" src="https://img.shields.io/badge/license-MIT-blue"></a>
    <img alt="Platform: macOS 15+" src="https://img.shields.io/badge/macOS-15%2B-black">
  </p>

  <p>
    English ·
    <a href="README.zh-CN.md">简体中文</a> ·
    <a href="README.zh-TW.md">繁體中文</a>
  </p>

  <!-- HERO SCREENSHOT — NEEDED (no product screenshot exists in the repo yet).
       Capture: the App's main window on the Overview tab — the project name and summary
       stat row above the capability grid, with the agent tab strip (Agents · Codex ·
       Claude Code · Trae) visible. Ship light + dark, drop them in docs/assets/screenshots/,
       and uncomment this <picture> block. Until then it stays a comment so the README
       never renders a broken image.
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/assets/screenshots/overview-dark.png">
    <source media="(prefers-color-scheme: light)" srcset="docs/assets/screenshots/overview-light.png">
    <img alt="Orbita Overview: one console showing what every agent loads across Codex, Claude Code, Trae, and the .agents workspace" src="docs/assets/screenshots/overview-light.png" width="860">
  </picture>
  -->
</div>

---

You run Codex Desktop, Claude Code, and Trae side by side. The same Skill is enabled for
one and invisible to another, a plugin path quietly broke, and your project's `.agents`
intent no longer matches what's actually on disk — and nothing tells you.

**Orbita is a local source of truth for what each agent actually loads.** It reads your
machine and your repo, reconciles each agent's native config, plugin caches, and the
cross-agent `.agents` layer into one view, and shows **where every capability comes from,
which agent can see it, and whether it drifted, conflicts, or carries risk.**

It is **not** a plugin store and never takes ownership of your config: lifecycle changes go
through each agent's own tools (`codex` / `claude` / `npx skills`), so the native client
stays the source of truth. Three products ship from one SwiftPM package — **OrbitaCore**
(all the scan / resolve / apply semantics), the **`orbita` CLI** (the canonical surface),
and **OrbitaApp** (a SwiftUI viewer over the same engine, with Sparkle auto-update).

## Download & install

Pre-built, signed and notarized DMGs are published by the tag-driven GitHub Release workflow.

- **Latest release:** [github.com/LLLLLayer/orbita/releases/latest](https://github.com/LLLLLayer/orbita/releases/latest)
- **All releases:** [github.com/LLLLLayer/orbita/releases](https://github.com/LLLLLayer/orbita/releases)
- The app updates itself in place via [Sparkle](https://sparkle-project.org).
- Requirements: **macOS 15 or newer.**

Orbita reads your home directory and project to discover capabilities, so macOS may prompt
for **Full Disk Access** on first scan — all access is local and read-only except the narrow
[write boundary](#risk--trust) described below. Prefer the terminal? Jump to the
[CLI](#cli--same-engine-scriptable).

## Quickstart

**In the app**

1. **Open Orbita** and pick a project folder (or open one from the sidebar).
2. Orbita **scans** your machine and the project and builds a unified capability graph.
3. Switch the **Agents · Codex · Claude Code · Trae** tabs to see what each agent loads, then
   click any capability to inspect its source, scope, status, access/risk flags, and
   skills-lock metadata. (Cursor is fully scannable but is not one of the default tabs.)

**From the CLI** — the same scan, one command:

```bash
swift run orbita overview --project-root <path>
```

## What it does

- 🗺️ **Unified capability graph** — one scan across user scope, project scope, native agent configs, plugin caches, and `.agents` intent.
- 👁️ **Per-agent perspective** — see exactly what Codex, Claude Code, and Trae each load, and what stays hidden.
- 🌊 **Drift & conflict detection** — broken paths, duplicates, shadowed entries, disabled-but-still-discovered, and review flags, each explained.
- ⚠️ **Risk visibility** — flags for reading files, writing files, command execution, network access, secrets, and global scope.
- 🔁 **Safe lifecycle** — dry-runnable `merge` / `enable` / `disable` / `delete` / `clean` / `rollback`, plus triggers for native plugin updates.
- 🍴 **Agent sync (fork)** — copy or symlink a Skill / command / agent into another agent's directory as a lock-less, Orbita-managed install.
- 📦 **Skills-CLI aware** — reads `skills-lock.json` / `.skill-lock.json` and surfaces source / ref / hash / skillPath, canonical paths, and inferred install targets.
- ⌨️ **Same engine as the CLI** — every view is backed by `OrbitaCore`; the `orbita` CLI exercises the same code paths with `--json` output.

What Orbita reads for each agent:

| Agent | Where Orbita reads from |
|-------|--------------------------|
| **`.agents`** (cross-agent) | `manifest.json` intent, generated adapter previews, lock data |
| **Codex Desktop** | plugin cache, `~/.codex/config.toml`, project `.codex/` commands & hooks, MCP configs |
| **Claude Code** | `~/.claude/…` + `installed_plugins.json`, project `.claude/` commands, `settings.json` hooks, instructions |
| **Trae** | project `.trae/skills` |
| **Cursor** *(scannable, not a default tab)* | `.cursor/rules`, legacy `.cursorrules`, `.mcp.json`, shared project metadata |
| **Virtual Plugins** | inferred from package contents, local directories, and plugin caches |

## How intent works: Source · Intent · Visibility

Orbita keeps three layers strictly separate — conflating them is what makes multi-agent
setups confusing.

| Layer | Lives in | What it is | What "disable" means here |
|-------|----------|------------|---------------------------|
| **Source** | real files / plugin cache / package | the capability as it physically exists | nothing — the file stays on disk |
| **Intent** | `.agents/manifest.json` | your cross-agent enable/disable choices | the capability is hidden via intent; **the source file stays put** |
| **Visibility** | per-agent view | what a given agent actually loads | the capability no longer appears for that agent |

When intent says "disabled" but the source is still discoverable on disk, that mismatch **is
drift** — and Orbita's drift report explains exactly why.

## Risk & trust

- **Local-only.** Orbita reads your machine and repo to build the graph; it doesn't phone home.
- **The native client stays the source of truth.** Enablement for Codex lives in `~/.codex/config.toml` + the plugin cache; for Claude in `~/.claude/settings.json` + `installed_plugins.json`. Orbita drives those through `codex` / `claude` / `npx skills` rather than editing them behind your back.
- **A narrow write boundary.** With `--apply`, Orbita writes only inside the project's `.agents/` and `.orbita/`, **plus** — for agent-sync (fork) only — the destination agent's own skills / commands / agents directories. Everything else is emitted as a shell command for you (or the native CLI) to run.
- **Risk labels.** Capabilities are flagged for reading files, writing files, command execution, network access, secrets, and global scope, so you can see what a capability can reach before enabling it.

## Lifecycle & Apply Plan

Every change is a **typed plan you can dry-run first**. The plan lists each operation with its
path, target, risk, and a description — so you see precisely what will happen before anything
touches disk.

- **Actions:** `merge`, `enable`, `disable`, `delete`, `clean`, `rollback`, and **agent-sync (fork)**.
- **Dry run vs apply:** `plan` without `--apply` prints the dry run; with `--apply` it executes and returns completed / failed / pending operations.
- **Hooks:** a Claude `settings.json` / `hooks.json` registers many handlers and Orbita models each one separately; since Claude has no per-hook disable, the only single-hook action is delete.

See [docs/capability-lifecycle.md](docs/capability-lifecycle.md) for the authoritative per-agent
enable / disable / update / delete contract.

## CLI — same engine, scriptable

The App is a viewer over `OrbitaCore`; the `orbita` CLI exercises the same code paths and is
the canonical product surface. Add `--json` to any command for machine-readable output.

```bash
swift run orbita scan     --project-root <path> [--json]
swift run orbita status   --project-root <path> [--json]
swift run orbita graph    --project-root <path> [--json]
swift run orbita overview --project-root <path> [--json]
swift run orbita drift    --project-root <path>
swift run orbita agent    --project-root <path> --agent codex|claude-code|cursor|trae
swift run orbita explain  --project-root <path> <capability-id>
swift run orbita preview  --project-root <path> --agent <id>
swift run orbita doctor   [--project-root <path>]
swift run orbita plan     --project-root <path> --merge|--rollback|--clean|--enable <id>|--disable <id>|--delete <id> [--apply] [--json]
swift run orbita plan     --project-root <path> --sync <id> --agent <id> [--mode copy|symlink] [--scope project|user] [--apply] [--json]
```

`plan --sync` physically copies (or symlinks, the default) a Skill / command / agent into the
destination agent's directory as a lock-less, Orbita-managed install.

<details>
<summary>Flags & conventions</summary>

- `--no-user-scope` restricts scanning to the project.
- `--project-root <path>` and `--project <path>` are synonyms; the path can also be a positional argument.
- `plan` without `--apply` prints a dry run; with `--apply` it returns completed / failed / pending operations.
- `--json` returns structured output (errors as a structured `CLIErrorPayload` / `CLIApplyExecutionErrorPayload`).

</details>

<details>
<summary><strong>How it works (architecture)</strong></summary>

The pipeline is one-directional and lives in `Sources/OrbitaCore/`:

```text
Scan ──▶ Resolve ──▶ Project layers ──────────────▶ Apply
 │          │              │                          │
 │          │              │   ApplyPlanBuilder builds a typed plan;
 │          │              │   ApplyPlanExecutor is the only disk mutator
 │          │              │
 │          │              └─ AgentView · Overview · AdapterPreview · Drift · Doctor · Explain
 │          │
 │          └─ CapabilityResolver → CapabilityGraph (marks duplicate / shadowed / drifted)
 │
 └─ CapabilityScanner → raw Capability records + ScanIssues
```

Three products ship from one SwiftPM package:

- **OrbitaCore** — scan / resolve / agent-view / overview / adapter-preview / drift / doctor / apply-plan logic. All semantics live here.
- **`orbita` CLI** — a thin wrapper that calls into `OrbitaCore` and prints text or `--json`.
- **OrbitaApp** — SwiftUI macOS app over the same core, with Sparkle auto-update and Textual Markdown rendering.

The canonical agents are `codex`, `claude-code`, `cursor`, `trae`. The detailed lifecycle
contract is in [docs/capability-lifecycle.md](docs/capability-lifecycle.md); the hook model is
in [docs/hook-logic.md](docs/hook-logic.md).

</details>

<details>
<summary><strong>Build & contribute</strong></summary>

```bash
swift build                       # SwiftPM build of all targets
swift test                        # OrbitaCoreTests + OrbitaCLITests
swift test --filter <name>        # single test
./script/xcode_build.sh build     # xcodebuild against Orbita.xcodeproj (scheme: Orbita)
./script/build_and_run.sh         # build + open Orbita.app
./script/build_and_run.sh --verify     # build + open + assert process is running
./script/build_and_run.sh --telemetry  # stream OSLog subsystem dev.orbita.app
swift run orbita <command>        # run the CLI from source
```

- **Xcode:** `open Orbita.xcodeproj` and select the **`Orbita`** scheme (an `Orbita.xcworkspace` also exists).
- **Telemetry:** `--telemetry` tails the `dev.orbita.app` OSLog subsystem (`App`, `Scan`, `Apply` categories). Scan log lines (`scan.start`, `scan.phase`, `scan.finish`, `scan.failed`) include capability counts, issue counts, and duration.
- **Adding/changing an agent's discovery rules** lives in `Sources/OrbitaCore/CapabilityScanner.swift`; most behavioral changes need a new fixture under `Tests/OrbitaCoreTests/Fixtures/` and an assertion in `CapabilityScannerTests.swift`.

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

</details>

## Documentation

- [docs/capability-lifecycle.md](docs/capability-lifecycle.md) — authoritative per-agent enable / disable / update / delete contract.
- [docs/hook-logic.md](docs/hook-logic.md) — hook scanner contract (event / matcher / handler model, host inference).
- [docs/release.md](docs/release.md) — signing, notarization, DMG, Sparkle appcast checklist.

<details>
<summary>FAQ</summary>

- **macOS blocks the app on first open.** It's signed and notarized via the release workflow; if Gatekeeper still warns, right-click the app → **Open**.
- **The scan finds nothing.** Point Orbita at a project that has `.agents/`, `.codex/`, `.claude/`, `.trae/`, `.cursor/`, or `.mcp.json`, and grant Full Disk Access so user-scope sources are visible.
- **Why isn't Cursor a tab?** Cursor is fully scannable and resolvable; it is just omitted from the default tab strip. Use `orbita agent --agent cursor` or `preview --agent cursor`.
- **Where does `--apply` write?** Only inside the project's `.agents/` and `.orbita/`, plus agent-sync destination directories. Everything else is emitted as a command for you to run.

</details>

## License

Orbita is released under the [MIT License](LICENSE).

## Acknowledgements

Orbita is built on the work of the open-source community. In particular it depends on:

- [**Sparkle**](https://github.com/sparkle-project/Sparkle) — software update framework for macOS apps. MIT License.
- [**Textual**](https://github.com/gonzalezreal/textual) — Markdown rendering for SwiftUI. MIT License.

The project also takes inspiration from Codex Desktop, Claude Code, Trae, Cursor, and the
broader Coding Agent ecosystem whose capability formats Orbita reads.
