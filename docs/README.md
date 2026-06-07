---
created_at: 2026-05-23
created_by: Codex
updated_at: 2026-06-01
updated_by: Codex
tags:
  - docs
  - product
  - orbita
summary: Public documentation index for the Orbita project. Internal research notes are intentionally ignored by Git.
version: 0.1.0
---

# Orbita 文档

Orbita 是一个已发布的 macOS 能力管理产品，用于统一管理 Coding Agent 的能力，包括 Skills、Plugins、Commands、Hooks、MCP servers、Rules、Instructions，以及通过包管理器安装的扩展。它由一个 SwiftPM 包同时产出三件事：`OrbitaCore` 库、`orbita` CLI 和 `OrbitaApp`（SwiftUI macOS App）。CLI 是正统的产品面，App 是同一份 Core 之上的可视化层。

三个 target 的职责（Xcode 入口见下文「Xcode 入口」一节）：

- `OrbitaCore`：扫描、解析、聚合、Agent view、Agent overview、adapter preview、adapter mapping、drift report、doctor、解释、drift/shadowed 状态和 Apply Plan 的核心库。
- `orbita`：命令行产品面，先跑通诊断、overview 差异摘要、JSON 输出、doctor checks 和显式 `.agents` merge/enable/disable/delete/rollback/clean 写入（以及 `--sync` 的 agent-sync/fork）；enable/disable 支持 capability id 或能力名，enable、disable、merge 和 rollback 会同步 adapter preview，clean 会清理 broken skill symlink 和引用 missing/disabled 能力的 stale adapter，Apply 失败会返回 completed/failed/pending 操作。
- `OrbitaApp`：复用 `OrbitaCore` 的 SwiftUI macOS App shell，支持项目打开、搜索、Overview 差异摘要、状态概览、能力级 Apply Plan sheet；Apply Plan 会展示每个操作的 path、target、risk 和说明。

当前 scanner 已覆盖 Codex、Claude Code、Trae、Trae CN、Cursor 的主要项目级入口，包括 `.codex/commands`、`.codex/hooks`、`.claude/commands`、`.claude/settings.json`、`.trae/skills`、`.traecn/skills`、`.cursor/rules`、legacy `.cursorrules`、`.mcp.json` 和项目 instructions。正式支持的 Agent 是 `codex`、`claude-code`、`cursor`、`trae`、`trae-cn`。

Hook 解析规则见 `docs/hook-logic.md`：Orbita 按具体 handler 建模 Hook，而不是把 `settings.json` 或 `hooks.json` 当成单个 Hook。

Resolver 会回读 `.agents/manifest.json` 的 enabled/disabled intent；当能力在 `.agents` 中 disabled 但原始来源仍能被扫描到时，会标记为 drifted 并在 Drift Report 中解释原因。Agent view 和 adapter preview 会把 disabled capability 视为 hidden，而不是继续暴露为可见能力。单能力 enable、disable 和 rollback 会保留 manifest 中其他能力的 intent。

Apply Plan 默认只允许写入项目的 `.agents/` 和 `.orbita/` 内部，外加三处锚定的 carve-out：(1) agent-sync（fork）—— 把 skill/command/agent 物理 copy/symlink 进目标 Agent 自己的 skills/commands/agents 目录（针对项目根、用户级 Agent 主目录和 `SkillsAgentCatalog` 全局根做锚定校验）；(2) disabled-store fallback —— 无原生 disable 的能力会被移进 scope-correct 的 `<repo>/.orbita/disabled` 或用户自己的 `~/.orbita/disabled`（`isDisabledStorePath` 锚定）；(3) fork-backup store —— `plan --resync` 在覆盖 copied fork 前，把发散的副本移进 `<repo>/.orbita/fork-backups` 或 `~/.orbita/fork-backups`（`isForkBackupStorePath` 锚定）。其余一切（`~/.codex/config.toml`、`~/.claude/settings.json`、插件缓存等）都以 shell 命令形式输出，而非直接写盘。`--apply` 执行 remove/create symlink 时会处理断链 symlink，并在 macOS `/var` 与 `/private/var` 路径等价场景下保持写入边界校验。

## Xcode 入口

双击或用命令打开工程：

```bash
open Orbita.xcodeproj
```

在 Xcode 中选择 `Orbita` scheme 可构建和调试 SwiftUI App target（仓库里也有一个 `Orbita.xcworkspace`）。命令行 Xcode 验证使用：

```bash
./script/xcode_build.sh list
./script/xcode_build.sh build
./script/xcode_build.sh test
```

`Support/OrbitaApp/Info.plist` 是本地 `.app` bundle 使用的持久化 Info.plist；`Support/OrbitaApp/OrbitaApp.entitlements` 预留给后续签名和分发配置。

本地运行 App 使用：

```bash
./script/build_and_run.sh --verify
```

排查打开项目或扫描卡顿时，使用统一日志流：

```bash
./script/build_and_run.sh --telemetry
```

日志 subsystem 是 `dev.orbita.app`，关键 category 包括 `App`、`Scan` 和 `Apply`。扫描日志会记录 `scan.start`、各扫描阶段的 `scan.phase`、`scan.finish`、`scan.failed`、capability 数量、issue 数量和耗时。

Codex app 的 Run action 已指向同一个脚本。

## 内部资料

内部调研和产品规划资料放在 `docs/internal/` 目录下。该目录 **MUST NOT** 被提交到 Git —— 仓库根目录的 `.gitignore` 已忽略该路径，因此这里不再逐一列出其文件。

## 生命周期规范

- `docs/capability-lifecycle.md`：记录 `.agents`、Codex Desktop、Claude Code 在电脑维度和项目维度的启用、禁用、更新检查、更新触发和 GitHub 自动发版逻辑。

## 扩展机制调研

- `docs/agent-extension-landscape.zh-CN.md`：面向公开的调研参考，讲清 Codex、Claude Code、Cursor、Trae 各自如何在磁盘上**发现**扩展组件、各类型的**禁用**策略，以及 `npm` / `npx skills` 生态与 `.agents/` 目录的关系（区分官方规范与社区约定）。同时说明 Orbita 如何用「三层、三处位置」模型协调这一切，并明确标注与官方文档的已知分歧及待核实项。

## 能力治理

- `docs/agent-capability-control-plane.zh-CN.md`：面向公开的知识文档，讲清 Agent 接入大量 Skills / 工具 / MCP / 子 agent 后为什么会「选错工具、撑爆上下文」，以及业界如何按痛点选治理手段（精简描述、按需加载、检索路由、分级触发、结果预算……），并收敛到一个理想的「控制面治理」参考架构。面向公司同学与团队 leader，vendor-neutral。
