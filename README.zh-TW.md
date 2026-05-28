<div align="center">
  <img src="docs/assets/orbita-logo.png" alt="Orbita" width="160" />
  <h1>Orbita</h1>
  <p><strong>面向 Coding Agent 的 macOS 能力管理主控台。</strong></p>
  <p>
    <a href="https://github.com/LLLLLayer/orbita/releases/latest">下載</a> ·
    <a href="docs/capability-lifecycle.md">生命週期</a> ·
    <a href="docs/release.md">發佈流程</a>
  </p>
  <p>
    <a href="README.md">English</a> ·
    <a href="README.zh-CN.md">简体中文</a> ·
    繁體中文
  </p>
</div>

---

Orbita 會掃描你的本機與目前的專案，呈現 Codex Desktop、Claude Code、跨 Agent 的 `.agents` 工作區以及 Cursor 實際會載入哪些能力 —— Skills、Plugins、Commands、Hooks、MCP servers、Rules 與 Instructions。它的目標不是再做一個外掛商店，而是提供一個本地事實來源：**能力從哪裡來、哪個 Agent 能看到它、有沒有漂移、衝突或安全風險**。

整個 repo 由同一個 SwiftPM 套件同時產出三件事：

- **OrbitaCore** —— 掃描 / 解析 / Agent 視圖 / 概覽 / Adapter 預覽 / Drift / Doctor / Apply Plan 的全部語意。
- **`orbita` CLI** —— `OrbitaCore` 的輕量包裝，支援文字與 `--json` 輸出。
- **OrbitaApp** —— 重用同一份 Core 的 SwiftUI macOS App，整合 Sparkle 自動更新。

## 下載

每次發佈版本都會簽署、公證並提供 DMG。

- **最新版本：** [github.com/LLLLLayer/orbita/releases/latest](https://github.com/LLLLLayer/orbita/releases/latest)
- **所有版本：** [github.com/LLLLLayer/orbita/releases](https://github.com/LLLLLayer/orbita/releases)
- App 透過 [Sparkle](https://sparkle-project.org) 原地自動更新。

系統需求：macOS 15 或更新版本。

## 能管理什麼

- 基於 `SKILL.md` 的 Agent Skills。
- Codex Desktop 的 Plugins、Skills、Commands、Hooks、MCP 設定與專案檔案。
- Claude Code 的 Plugins、Commands、Hooks、Settings 與專案 Instructions。
- `.agents` 專案能力意圖、產生的 adapter preview 與 lock 資料。
- Cursor rules、legacy `.cursorrules`、`.mcp.json` 與共享的專案中繼資料。
- 從 package 內容、本地目錄與外掛快取推斷出的虛擬 Plugin。

## 核心能力

- **能力圖譜。** 在使用者層、專案層、原生 Agent 設定、Plugin cache 與 `.agents` intent 之間做統一掃描。
- **Agent 視角。** Overview、Agents、Codex、Claude Code 等視圖，分別展示每個 Agent 實際能看到什麼。
- **生命週期管理。** 支援 `merge`、`enable`、`disable`、`delete`、`clean`、`rollback`，也能觸發原生 Plugin 更新。
- **Skills CLI 相容。** 讀取 `skills-lock.json` / `.skill-lock.json`，呈現 source / ref / hash / skillPath、canonical 路徑與推斷出的安裝目標。
- **漂移診斷。** 解釋 broken path、duplicate、shadowed、已停用但仍被發現、以及 review flag。
- **風險可見性。** 標記讀檔、寫檔、執行指令、網路存取、secrets 與全域作用域等風險。
- **三層模型不混淆。** Source（真實檔案 / cache / package）、Intent（`.agents/manifest.json`）、Visibility（每個 Agent 實際能載入什麼）一律拆開處理。
- **發版自動化。** 內建 GitHub Release 工作流，包含簽署、公證 DMG 與 Sparkle appcast。

## 從原始碼建置與除錯

```bash
swift build                       # 以 SwiftPM 建置全部 target
swift test                        # OrbitaCoreTests + OrbitaCLITests
swift test --filter <name>        # 跑單一測試
./script/xcode_build.sh build     # 以 xcodebuild 建置 Orbita.xcodeproj（App scheme）
./script/build_and_run.sh         # 建置後開啟 Orbita.app
./script/build_and_run.sh --verify     # 建置 + 開啟 + 驗證行程仍在執行
./script/build_and_run.sh --telemetry  # 監聽 OSLog subsystem dev.orbita.app
swift run orbita <command>        # 直接從原始碼跑 CLI
```

除錯建議：

- **觀察遙測 log：** `./script/build_and_run.sh --telemetry` 會跟隨 `dev.orbita.app` 的 OSLog subsystem（`App`、`Scan`、`Apply` category）。掃描相關的 `scan.start` / `scan.phase` / `scan.finish` / `scan.failed` 皆附帶能力數、issue 數與耗時。
- **以 CLI 重現 App 行為：** App 只是同一套邏輯的視覺化層 —— `swift run orbita scan|status|graph|overview|drift|agent|explain|preview|doctor|plan` 已涵蓋 App 走過的全部路徑。加上 `--json` 即可拿到機器可讀輸出。
- **追蹤單一能力：** `swift run orbita explain --project-root <path> <capability-id>`。
- **試跑變更：** `swift run orbita plan --project-root <path> --merge`（也可以是 `--enable` / `--disable` / `--delete` / `--rollback` / `--clean`）。加 `--apply` 才會真的寫入。
- **以 Xcode 開啟：** `open Orbita.xcodeproj`。

## CLI 總覽

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

`--no-user-scope` 會把掃描限制在專案作用域內。`plan` 不帶 `--apply` 是試跑；帶 `--apply` 之後回傳 completed / failed / pending 操作集。

## 目錄結構

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

## 文件

- [docs/capability-lifecycle.md](docs/capability-lifecycle.md) —— 各 Agent enable / disable / update / delete 的權威規範。
- [docs/hook-logic.md](docs/hook-logic.md) —— Hook 掃描契約（event / matcher / handler 模型與 host 推斷）。
- [docs/release.md](docs/release.md) —— 簽署、公證、DMG、Sparkle appcast 清單。

## 授權

Orbita 以 [MIT License](LICENSE) 發佈。

## 開源致謝

Orbita 是站在開源社群的肩膀上完成的，特別依賴以下專案：

- [**Sparkle**](https://github.com/sparkle-project/Sparkle) —— macOS App 的軟體更新框架。MIT License。
- [**Textual**](https://github.com/gonzalezreal/textual) —— SwiftUI 的 Markdown 渲染。MIT License。

同時也從 Codex Desktop、Claude Code、Cursor 以及更廣義的 Coding Agent 生態汲取靈感 —— Orbita 讀取的能力格式皆源自這些工具。
