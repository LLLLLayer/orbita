---
created_at: 2026-05-23
created_by: Codex
updated_at: 2026-05-27
updated_by: Codex
tags:
  - docs
  - product
  - orbita
summary: Public documentation index for the Orbita project. Internal research notes are intentionally ignored by Git.
version: 0.1.0
---

# Orbita 文档

Orbita 是一个 CLI-first 的 macOS 工具方向，用于统一管理 Coding Agent 的能力，包括 Skills、Plugins、MCP servers、项目本地配置，以及通过包管理器安装的扩展。

当前工程采用 SwiftPM 组织，并提供 `Orbita.xcworkspace` 作为 Xcode 入口：

- `OrbitaCore`：扫描、解析、聚合、Agent view、Agent overview、adapter preview、adapter mapping、drift report、doctor、解释、drift/shadowed 状态和 Apply Plan 的核心库。
- `orbita`：命令行产品面，先跑通诊断、overview 差异摘要、JSON 输出、doctor checks 和显式 `.agents` merge/enable/disable/rollback/clean 写入；enable/disable 支持 capability id 或能力名，enable、disable、merge 和 rollback 会同步 adapter preview，clean 会清理 broken skill symlink 和引用 missing/disabled 能力的 stale adapter，Apply 失败会返回 completed/failed/pending 操作。
- `OrbitaApp`：复用 `OrbitaCore` 的 SwiftUI macOS App shell，支持项目打开、搜索、Overview 差异摘要、状态概览、能力级 Apply Plan sheet；Apply Plan 会展示每个操作的 path、target、risk 和说明。

当前 scanner 已覆盖 Codex、Claude Code、Cursor 的主要项目级入口，包括 `.codex/commands`、`.codex/hooks`、`.claude/commands`、`.claude/settings.json`、`.cursor/rules`、legacy `.cursorrules`、`.mcp.json` 和项目 instructions。

Hook 解析规则见 `docs/hook-logic.md`：Orbita 按具体 handler 建模 Hook，而不是把 `settings.json` 或 `hooks.json` 当成单个 Hook。

Resolver 会回读 `.agents/manifest.json` 的 enabled/disabled intent；当能力在 `.agents` 中 disabled 但原始来源仍能被扫描到时，会标记为 drifted 并在 Drift Report 中解释原因。Agent view 和 adapter preview 会把 disabled capability 视为 hidden，而不是继续暴露为可见能力。单能力 enable、disable 和 rollback 会保留 manifest 中其他能力的 intent。

Apply Plan 只允许写入项目 `.agents` 内部。`--apply` 执行 remove/create symlink 时会处理断链 symlink，并在 macOS `/var` 与 `/private/var` 路径等价场景下保持 `.agents` 写入边界校验。

## Xcode 入口

双击或用命令打开 workspace：

```bash
open Orbita.xcworkspace
```

在 Xcode 中选择 `OrbitaApp` scheme 可构建和调试当前 SwiftUI App target。命令行 Xcode 验证使用：

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

内部调研和产品规划资料放在 `docs/internal/` 目录下。

`docs/internal/` 目录 **MUST NOT** 被提交到 Git。仓库根目录的 `.gitignore` 已经忽略该路径。

当前内部文档包括：

- `docs/internal/research-and-goals.md`：市场调研、差异化策略和项目目标。
- `docs/internal/product-design.md`：Git-like macOS 能力管理器的产品形态、`.agents` 工作区和 MVP 切分。
- `docs/internal/capability-model.md`：`.agents` 工作区、启停、清理、Codex 适配、添加和升级规则。
- `docs/internal/external-validation.md`：基于外部生态和竞品的校准结论。
- `docs/internal/mvp-architecture.md`：MVP 架构、Resolver、Adapter、Apply Plan、Trust Model 和交付切片。
- `docs/internal/development-plan.md`：开发计划、技术选型、里程碑、批次、测试策略和风险决策。
- `docs/internal/cli-design.md`：CLI-first 架构、命令设计、输出协议和 App 边界。

## 生命周期规范

- `docs/capability-lifecycle.md`：记录 `.agents`、Codex Desktop、Claude Code 在电脑维度和项目维度的启用、禁用、更新检查、更新触发和 GitHub 自动发版逻辑。
