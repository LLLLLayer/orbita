<div align="center">
  <img src="docs/assets/orbita-logo.png" alt="Orbita" width="160" />
  <h1>Orbita</h1>
  <p><strong>面向 Coding Agent 的 macOS 能力管理控制台。</strong></p>
  <p>
    <a href="https://github.com/LLLLLayer/orbita/releases/latest">下载</a> ·
    <a href="docs/capability-lifecycle.md">生命周期</a> ·
    <a href="docs/release.md">发布流程</a>
  </p>
  <p>
    <a href="README.md">English</a> ·
    简体中文 ·
    <a href="README.zh-TW.md">繁體中文</a>
  </p>
</div>

---

Orbita 会扫描你的本机和当前项目，展示 Codex Desktop、Claude Code、跨 Agent 的 `.agents` 工作区以及 Cursor 实际会加载哪些能力 —— Skills、Plugins、Commands、Hooks、MCP servers、Rules 和 Instructions。它的目标不是再做一个插件商店，而是提供一个本地事实来源：**能力从哪里来、哪个 Agent 能看到它、有没有漂移、冲突或安全风险**。

整个仓库由一个 SwiftPM 包同时产出三件事：

- **OrbitaCore** —— 扫描 / 解析 / Agent 视图 / 概览 / Adapter 预览 / Drift / Doctor / Apply Plan 的全部语义。
- **`orbita` CLI** —— `OrbitaCore` 的轻量包装，支持文本和 `--json` 输出。
- **OrbitaApp** —— 复用同一份 Core 的 SwiftUI macOS App，集成 Sparkle 自动更新。

## 下载

每次发布版本都会签名、公证并提供 DMG。

- **最新版本：** [github.com/LLLLLayer/orbita/releases/latest](https://github.com/LLLLLayer/orbita/releases/latest)
- **全部版本：** [github.com/LLLLLayer/orbita/releases](https://github.com/LLLLLayer/orbita/releases)
- App 通过 [Sparkle](https://sparkle-project.org) 自动原地更新。

系统要求：macOS 15 或更新版本。

## 能管理什么

- 基于 `SKILL.md` 的 Agent Skills。
- Codex Desktop 的 Plugins、Skills、Commands、Hooks、MCP 配置和项目文件。
- Claude Code 的 Plugins、Commands、Hooks、Settings 和项目 Instructions。
- `.agents` 项目能力意图、生成的 adapter preview 和 lock 数据。
- Cursor rules、legacy `.cursorrules`、`.mcp.json` 和共享项目元数据。
- 从 package 内容、本地目录和插件缓存中推断出的虚拟 Plugin。

## 核心能力

- **能力图谱。** 在用户级、项目级、原生 Agent 配置、Plugin cache 和 `.agents` intent 之间做统一扫描。
- **Agent 视角。** 用 Overview、Agents、Codex、Claude Code 几个视图，分别展示每个 Agent 实际能看到什么。
- **生命周期管理。** 支持 `merge`、`enable`、`disable`、`delete`、`clean`、`rollback`，并能触发原生 Plugin 更新。
- **Skills CLI 兼容。** 读取 `skills-lock.json` / `.skill-lock.json`，展示 source / ref / hash / skillPath、canonical 路径以及推断出的安装目标。
- **漂移诊断。** 解释 broken path、duplicate、shadowed、已禁用但仍被发现、以及 review flag。
- **风险可见性。** 标记读文件、写文件、执行命令、网络访问、secrets 和全局作用域等风险。
- **三层模型不混淆。** Source（真实文件 / cache / package）、Intent（`.agents/manifest.json`）、Visibility（每个 Agent 实际能加载什么）始终拆开处理。
- **发版自动化。** 内置 GitHub Release 工作流，包含签名、notarized DMG 和 Sparkle appcast。

## 从源码构建和调试

```bash
swift build                       # 用 SwiftPM 构建全部 target
swift test                        # OrbitaCoreTests + OrbitaCLITests
swift test --filter <name>        # 跑单个测试
./script/xcode_build.sh build     # 用 xcodebuild 构建 Orbita.xcodeproj（App scheme）
./script/build_and_run.sh         # 构建并打开 Orbita.app
./script/build_and_run.sh --verify     # 构建 + 打开 + 校验进程在运行
./script/build_and_run.sh --telemetry  # 监听 OSLog subsystem dev.orbita.app
swift run orbita <command>        # 直接从源码运行 CLI
```

调试建议：

- **看遥测日志：** `./script/build_and_run.sh --telemetry` 会跟随 `dev.orbita.app` 的 OSLog subsystem（`App`、`Scan`、`Apply` category）。扫描相关的 `scan.start` / `scan.phase` / `scan.finish` / `scan.failed` 都附带能力数、issue 数和耗时。
- **用 CLI 复现 App 行为：** App 只是同一套逻辑的可视化层 —— `swift run orbita scan|status|graph|overview|drift|agent|explain|preview|doctor|plan` 涵盖了 App 所走的全部路径。加 `--json` 得到机器可读输出。
- **追溯单个能力：** `swift run orbita explain --project-root <path> <capability-id>`。
- **干跑变更：** `swift run orbita plan --project-root <path> --merge`（也可以是 `--enable` / `--disable` / `--delete` / `--rollback` / `--clean`）。加 `--apply` 才会真正写入。
- **Xcode 打开：** `open Orbita.xcodeproj`。

## CLI 总览

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

`--no-user-scope` 限制只扫描项目作用域。`--project-root <path>` 与 `--project <path>` 是同义写法，路径也可以作为位置参数直接传。`plan` 不带 `--apply` 是干跑；带 `--apply` 后返回 completed / failed / pending 操作集。

## 目录结构

```text
Sources/
  OrbitaCore/   扫描、解析、图谱模型、Apply Plan、状态报告
  OrbitaCLI/    scan/status/overview/plan/doctor 等命令行入口
  OrbitaApp/    SwiftUI macOS App 和能力控制台
Support/        App bundle metadata、entitlements、发版配置
Tests/          Scanner、Resolver、Apply Plan、CLI 和 fixture
docs/           公开文档、生命周期规范、发版清单
script/         本地构建、运行、打包、签名和发版脚本
```

## 文档

- [docs/capability-lifecycle.md](docs/capability-lifecycle.md) —— 各 Agent enable / disable / update / delete 的权威规范。
- [docs/hook-logic.md](docs/hook-logic.md) —— Hook 扫描契约（event / matcher / handler 模型与 host 推断）。
- [docs/release.md](docs/release.md) —— 签名、notarization、DMG、Sparkle appcast 清单。

## 许可证

Orbita 以 [MIT License](LICENSE) 发布。

## 开源致谢

Orbita 站在开源社区的肩膀上，特别依赖以下项目：

- [**Sparkle**](https://github.com/sparkle-project/Sparkle) —— macOS App 的软件更新框架。MIT License。
- [**Textual**](https://github.com/gonzalezreal/textual) —— SwiftUI 的 Markdown 渲染。MIT License。

同时也从 Codex Desktop、Claude Code、Cursor 以及更广义的 Coding Agent 生态中汲取灵感 —— Orbita 读取的能力格式都来自这些工具。
