<div align="center">
  <a href="https://github.com/LLLLLayer/orbita/releases/latest">
    <img src="docs/assets/orbita-logo.png" alt="Orbita" width="128" />
  </a>
  <h1>Orbita</h1>
  <p><strong>看清你 Mac 上每個 Coding Agent 實際載入了什麼 —— 以及哪些漂移、衝突或帶有風險。</strong></p>
  <p>一個本地的 macOS 主控台與 CLI，把 Codex Desktop、Claude Code、Trae、Cursor、外掛快取以及跨 Agent 的 <code>.agents</code> 工作區，統一成一個事實來源。<strong>它不是外掛商店。</strong></p>

  <p>
    <a href="https://github.com/LLLLLayer/orbita/releases/latest"><strong>下載 macOS 版</strong></a> ·
    <a href="#quickstart">快速上手</a> ·
    <a href="#what-it-does">能做什麼</a> ·
    <a href="#cli--same-engine-scriptable">CLI</a> ·
    <a href="docs/capability-lifecycle.md">文件</a>
  </p>

  <p>
    <a href="https://github.com/LLLLLayer/orbita/releases/latest"><img alt="Latest release" src="https://img.shields.io/github/v/release/LLLLLayer/orbita?sort=semver&label=release"></a>
    <a href="LICENSE"><img alt="License: MIT" src="https://img.shields.io/badge/license-MIT-blue"></a>
    <img alt="Platform: macOS 15+" src="https://img.shields.io/badge/macOS-15%2B-black">
  </p>

  <p>
    <a href="README.md">English</a> ·
    <a href="README.zh-CN.md">简体中文</a> ·
    繁體中文
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

你同時在用 Codex Desktop、Claude Code 與 Trae。同一個 Skill 在一個 Agent 裡啟用、在另一個裡
卻看不到，某個外掛路徑悄悄失效，而專案裡的 `.agents` 意圖也早已和磁碟上的實際情況對不上 ——
卻沒有任何東西提醒你。

**Orbita 是一個本地事實來源，告訴你每個 Agent 實際載入了什麼。** 它掃描你的本機與儲存庫，把每個
Agent 的原生設定、外掛快取以及跨 Agent 的 `.agents` 層統一成一個視圖，呈現**每項能力從哪裡來、
哪個 Agent 能看到它、以及它有沒有漂移、衝突或帶有風險。**

它**不是**外掛商店，也從不接管你的設定：生命週期變更都透過各 Agent 自己的工具
（`codex` / `claude` / `npx skills`）完成，原生用戶端始終是事實來源。整個 repo 由一個 SwiftPM
套件同時產出三件事 —— **OrbitaCore**（全部 scan / resolve / apply 語意）、**`orbita` CLI**
（正統產品面），以及 **OrbitaApp**（重用同一引擎的 SwiftUI 視覺化層，內建 Sparkle 自動更新）。

## Download & install

每次發佈都會由標籤驅動的 GitHub Release 工作流產出已簽署、已公證的 DMG。

- **最新版本：** [github.com/LLLLLayer/orbita/releases/latest](https://github.com/LLLLLayer/orbita/releases/latest)
- **所有版本：** [github.com/LLLLLayer/orbita/releases](https://github.com/LLLLLayer/orbita/releases)
- App 透過 [Sparkle](https://sparkle-project.org) 原地自動更新。
- 系統需求：**macOS 15 或更新版本。**

Orbita 需要讀取你的家目錄與專案來探索能力，因此首次掃描時 macOS 可能會請求**完全磁碟存取權限**
（Full Disk Access）—— 除下文那條很窄的[寫入邊界](#risk--trust)外，所有存取都是本地、唯讀的。
更喜歡命令列？直接看 [CLI](#cli--same-engine-scriptable)。

## Quickstart

**在 App 裡**

1. **開啟 Orbita**，選一個專案目錄（或從側邊欄開啟既有專案）。
2. Orbita 會**掃描**你的本機與該專案，建立一張統一的能力圖譜。
3. 切換 **Agents · Codex · Claude Code · Trae** 這幾個標籤，看每個 Agent 實際載入了什麼，
   再點開任一項能力，查看它的 source、scope、status、access/risk 標記與 skills-lock 中繼資料。
   （Cursor 完全可被掃描，只是不在預設標籤裡。）

**用 CLI** —— 同一次掃描，一條指令：

```bash
swift run orbita overview --project-root <path>
```

## What it does

- 🗺️ **統一能力圖譜** —— 在使用者層、專案層、原生 Agent 設定、外掛快取與 `.agents` intent 之間做一次統一掃描。
- 👁️ **Agent 視角** —— 精確看到 Codex、Claude Code、Trae 各自載入了什麼、又有什麼被隱藏。
- 🌊 **漂移與衝突診斷** —— broken path、duplicate、shadowed、已停用但仍被發現、review flag，逐項給出解釋。
- ⚠️ **風險可見性** —— 標記讀檔、寫檔、執行指令、網路存取、secrets 與全域作用域等風險。
- 🔁 **安全的生命週期** —— 可試跑的 `merge` / `enable` / `disable` / `delete` / `clean` / `rollback`，並能觸發原生外掛更新。
- 🍴 **Agent sync（fork）** —— 把一個 Skill / command / agent 以 copy 或 symlink 方式裝進另一個 Agent 的目錄，作為一次 lock-less、由 Orbita 託管的安裝。
- 📦 **相容 Skills CLI** —— 讀取 `skills-lock.json` / `.skill-lock.json`，呈現 source / ref / hash / skillPath、canonical 路徑與推斷出的安裝目標。
- ⌨️ **與 CLI 同一套引擎** —— 每個視圖都由 `OrbitaCore` 驅動；`orbita` CLI 走的是同樣的程式路徑，並支援 `--json` 輸出。

Orbita 為每個 Agent 讀取的來源：

| Agent | Orbita 讀取的來源 |
|-------|--------------------|
| **`.agents`**（跨 Agent） | `manifest.json` intent、產生的 adapter preview、lock 資料 |
| **Codex Desktop** | 外掛快取、`~/.codex/config.toml`、專案 `.codex/` commands 與 hooks、MCP 設定 |
| **Claude Code** | `~/.claude/…` + `installed_plugins.json`、專案 `.claude/` commands、`settings.json` hooks、instructions |
| **Trae** | 專案 `.trae/skills` |
| **Cursor**（可掃描，但不在預設標籤） | `.cursor/rules`、legacy `.cursorrules`、`.mcp.json`、共享專案中繼資料 |
| **虛擬 Plugin** | 從 package 內容、本地目錄與外掛快取中推斷 |

## How intent works: Source · Intent · Visibility

Orbita 嚴格區分三個層 —— 把它們混在一起，正是多 Agent 設定讓人困惑的根源。

| 層 | 存放位置 | 它是什麼 | 這裡「disable」意味著 |
|----|----------|----------|------------------------|
| **Source** | 真實檔案 / 外掛快取 / package | 能力在磁碟上的物理存在 | 什麼都不變 —— 檔案仍在磁碟上 |
| **Intent** | `.agents/manifest.json` | 你的跨 Agent 啟停意圖 | 透過 intent 把能力隱藏；**原始檔案原地不動** |
| **Visibility** | 每個 Agent 的視圖 | 某個 Agent 實際載入了什麼 | 該能力不再出現在這個 Agent 裡 |

當 intent 標記為「disabled」、而原始檔案在磁碟上仍可被掃描到時，這種不一致**就是漂移（drift）**
—— Orbita 的 drift report 會準確解釋原因。

## Risk & trust

- **只在本地。** Orbita 讀取你的本機與儲存庫來建立圖譜，不會回傳任何資料。
- **原生用戶端始終是事實來源。** Codex 的啟用狀態存在 `~/.codex/config.toml` + 外掛快取裡，Claude 存在 `~/.claude/settings.json` + `installed_plugins.json` 裡。Orbita 透過 `codex` / `claude` / `npx skills` 去驅動它們，而不是在背後偷改。
- **一條很窄的寫入邊界。** 帶 `--apply` 時，Orbita 只會寫入專案的 `.agents/` 與 `.orbita/`，**外加** —— 僅限 agent-sync（fork）—— 目標 Agent 自己的 skills / commands / agents 目錄。其餘一切都以 shell 指令的形式輸出，交給你（或原生 CLI）執行。
- **風險標記。** 能力會被標記讀檔、寫檔、執行指令、網路存取、secrets 與全域作用域，讓你在啟用前就能看清它能觸及什麼。

## Lifecycle & Apply Plan

每一次變更都是**一份可以先試跑的、帶型別的計畫（plan）**。計畫會列出每個操作的 path、target、
risk 與說明 —— 在任何東西落盤之前，你就能看清究竟會發生什麼。

- **動作：** `merge`、`enable`、`disable`、`delete`、`clean`、`rollback`，以及 **agent-sync（fork）**。
- **試跑 vs 套用：** `plan` 不帶 `--apply` 是試跑；帶 `--apply` 後會執行並回傳 completed / failed / pending 操作集。
- **Hook：** 一份 Claude `settings.json` / `hooks.json` 會註冊很多 handler，Orbita 對每個 handler 單獨建模；由於 Claude 沒有按單個 hook 停用的能力，單個 hook 唯一的動作是 delete。

各 Agent 的 enable / disable / update / delete 權威規範見
[docs/capability-lifecycle.md](docs/capability-lifecycle.md)。

## CLI — same engine, scriptable

App 只是 `OrbitaCore` 的視覺化層；`orbita` CLI 走的是同樣的程式路徑，也是正統的產品面。給任一指令
加上 `--json` 即可得到機器可讀輸出。

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

`plan --sync` 會把一個 Skill / command / agent 以 copy（或預設的 symlink）方式裝進目標 Agent
的目錄，作為一次 lock-less、由 Orbita 託管的安裝。

<details>
<summary>參數與慣例</summary>

- `--no-user-scope` 只掃描專案作用域。
- `--project-root <path>` 與 `--project <path>` 是同義寫法，路徑也可以作為位置參數直接傳入。
- `plan` 不帶 `--apply` 是試跑；帶 `--apply` 後回傳 completed / failed / pending 操作集。
- `--json` 回傳結構化輸出（錯誤以結構化的 `CLIErrorPayload` / `CLIApplyExecutionErrorPayload` 給出）。

</details>

<details>
<summary><strong>它是怎麼運作的（架構）</strong></summary>

整條流水線是單向的，全部位於 `Sources/OrbitaCore/`：

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

整個 repo 由一個 SwiftPM 套件同時產出三件事：

- **OrbitaCore** —— scan / resolve / agent-view / overview / adapter-preview / drift / doctor / apply-plan 的全部語意都在這裡。
- **`orbita` CLI** —— 呼叫 `OrbitaCore`、輸出文字或 `--json` 的輕量包裝。
- **OrbitaApp** —— 重用同一份 Core 的 SwiftUI macOS App，內建 Sparkle 自動更新與 Textual Markdown 渲染。

正式支援的 Agent 是 `codex`、`claude-code`、`cursor`、`trae`。完整的生命週期契約見
[docs/capability-lifecycle.md](docs/capability-lifecycle.md)；Hook 模型見
[docs/hook-logic.md](docs/hook-logic.md)。

</details>

<details>
<summary><strong>建置與貢獻</strong></summary>

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

- **Xcode：** `open Orbita.xcodeproj`，選擇 **`Orbita`** scheme（儲存庫裡也有一個 `Orbita.xcworkspace`）。
- **遙測：** `--telemetry` 會跟隨 `dev.orbita.app` 的 OSLog subsystem（`App`、`Scan`、`Apply` category）。掃描 log（`scan.start`、`scan.phase`、`scan.finish`、`scan.failed`）附帶能力數、issue 數與耗時。
- **新增 / 修改某個 Agent 的探索規則**在 `Sources/OrbitaCore/CapabilityScanner.swift`；多數行為變更都需要在 `Tests/OrbitaCoreTests/Fixtures/` 下加一個 fixture，並在 `CapabilityScannerTests.swift` 裡補斷言。

```text
Sources/
  OrbitaCore/   掃描、解析、圖譜模型、Apply Plan、狀態報告
  OrbitaCLI/    scan/status/overview/plan/doctor 等指令入口
  OrbitaApp/    SwiftUI macOS App 與能力主控台
Support/        App bundle metadata、entitlements、發版設定
Tests/          Scanner、Resolver、Apply Plan、CLI 與 fixture
docs/           公開文件、生命週期規範、發版清單
script/         本地建置、執行、打包、簽署與發版腳本
```

</details>

## 文件

- [docs/capability-lifecycle.md](docs/capability-lifecycle.md) —— 各 Agent enable / disable / update / delete 的權威規範。
- [docs/hook-logic.md](docs/hook-logic.md) —— Hook 掃描契約（event / matcher / handler 模型與 host 推斷）。
- [docs/release.md](docs/release.md) —— 簽署、公證、DMG、Sparkle appcast 清單。

<details>
<summary>FAQ</summary>

- **首次開啟被 macOS 攔截。** App 經由發佈工作流簽署並公證；若 Gatekeeper 仍然警告，右鍵點擊 App → **開啟**。
- **掃描結果為空。** 把 Orbita 指向一個含有 `.agents/`、`.codex/`、`.claude/`、`.trae/`、`.cursor/` 或 `.mcp.json` 的專案，並授予完全磁碟存取權限，以便看到使用者層來源。
- **為什麼 Cursor 不是一個標籤？** Cursor 完全可被掃描與解析，只是沒有放進預設標籤條。可用 `orbita agent --agent cursor` 或 `preview --agent cursor`。
- **`--apply` 會寫到哪裡？** 只寫專案的 `.agents/` 與 `.orbita/`，外加 agent-sync 的目標目錄。其餘一切都以指令形式輸出，交給你執行。

</details>

## 授權

Orbita 以 [MIT License](LICENSE) 發佈。

## 開源致謝

Orbita 是站在開源社群的肩膀上完成的，特別依賴以下專案：

- [**Sparkle**](https://github.com/sparkle-project/Sparkle) —— macOS App 的軟體更新框架。MIT License。
- [**Textual**](https://github.com/gonzalezreal/textual) —— SwiftUI 的 Markdown 渲染。MIT License。

同時也從 Codex Desktop、Claude Code、Trae、Cursor 以及更廣義的 Coding Agent 生態汲取靈感
—— Orbita 讀取的能力格式皆源自這些工具。
