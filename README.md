# Orbita

Orbita 是一个面向 Coding Agent 的 macOS 能力管理控制台。它会扫描本机和当前项目，解释 Codex、Claude Code、`.agents` 等环境实际会加载哪些 Skills、Plugins、Commands、Hooks、MCP servers、Rules 和 Instructions。

Orbita 的目标不是再做一个插件商店，而是提供一个本地事实来源：能力从哪里来、属于哪个作用域、是否启用、哪些 Agent 能看到、有没有冲突、漂移或安全风险。

## 能管理什么

- 基于 `SKILL.md` 的 Agent Skills。
- Codex Desktop 的 Plugins、Skills、Commands、Hooks、MCP 配置和项目文件。
- Claude Code 的 Plugins、Commands、Hooks、Settings 和项目 Instructions。
- `.agents` 项目能力意图、生成的 adapter preview 和 lock 数据。
- Cursor rules、legacy `.cursorrules`、`.mcp.json` 和共享项目元数据。
- 从 package 内容、本地目录和插件缓存中推断出来的虚拟 Plugin。

## 核心能力

- **能力图谱**：统一扫描用户级、项目级、原生 Agent 配置、Plugin cache 和 `.agents` intent。
- **Agent 视角**：展示 Overview、Agents、Codex、Claude Code 分别能看到什么能力。
- **生命周期管理**：支持 merge、enable、disable、delete、clean、rollback、更新检查和原生 Plugin 更新触发。
- **Skills CLI 兼容**：读取 `skills-lock.json` / `.skill-lock.json`，展示 source/ref/hash/skillPath、canonical 路径和基于 `skills` agent 路径表推断的安装目标。
- **漂移诊断**：解释 broken path、duplicate、shadowed、disabled 但仍被发现、以及 review flag。
- **风险可见性**：标记读文件、写文件、执行命令、网络访问、secrets 和全局作用域等风险。
- **发版自动化**：内置 GitHub Release 工作流，支持签名、notarized DMG 和 Sparkle appcast。

## 产品模型

Orbita 把容易混在一起的三件事拆开处理：

- **Source**：真实文件、目录、Plugin cache 或 package。
- **Intent**：项目或原生客户端是否希望启用这个能力。
- **Visibility**：某个具体 Agent 是否真的能加载这个能力。

例如 Codex Plugin 的启用不能只写 `config.toml`。用户级 Codex Plugin 需要通过 `codex plugin add <plugin>@<marketplace>` 安装或刷新 Plugin cache，并记录启用状态；禁用在当前 Codex CLI 没有公开 disable 命令时才回退为写 `enabled = false`。

Codex 项目维度要分开看：commands、hooks、plugin config 等 Codex 原生项目配置仍在 `<repo>/.codex`；基于 `SKILL.md` 的 repo skills 按 Codex 官方规则放在 `<repo>/.agents/skills`，Codex 会从当前工作目录向上扫描 `.agents/skills` 直到仓库根。Codex 还支持在 `~/.codex/config.toml` 里通过 `[[skills.config]]` 禁用单个 `SKILL.md` 路径，Orbita 会把这种状态识别为 Codex 专属可见性。

## 项目结构

```text
Sources/
  OrbitaCore/   扫描、解析、图谱模型、Apply Plan、状态报告
  OrbitaCLI/    scan/status/overview/plan/doctor 等命令行入口
  OrbitaApp/    SwiftUI macOS App 和交互式能力控制台
Support/        App bundle metadata、entitlements 和发版配置
Tests/          Scanner、Resolver、Apply Plan、CLI 和 fixture 覆盖
docs/           公开文档、生命周期规范和发版清单
script/         本地构建、运行、打包、签名和发版脚本
```

## 环境要求

- macOS 14 或更新版本。
- 支持 Swift 6 的 Xcode。
- Git。
- 可选：Codex Desktop / Codex CLI、Claude Code CLI、`npx skills`。

## 构建和运行

打开 Xcode 工程：

```bash
open Orbita.xcodeproj
```

命令行构建：

```bash
./script/xcode_build.sh build
```

运行 macOS App：

```bash
./script/build_and_run.sh --verify
```

调试扫描和 Apply 行为时查看统一日志：

```bash
./script/build_and_run.sh --telemetry
```

## CLI 用法

SwiftPM 会构建 `orbita` executable target：

```bash
swift run orbita status --project-root /path/to/project
swift run orbita overview --project-root /path/to/project
swift run orbita graph --project-root /path/to/project --json
swift run orbita drift --project-root /path/to/project
swift run orbita doctor
```

生成或执行项目 `.agents` 变更计划：

```bash
swift run orbita plan --merge --project-root /path/to/project
swift run orbita plan --disable "capability-name" --project-root /path/to/project
swift run orbita plan --rollback --project-root /path/to/project --apply
swift run orbita plan --clean --project-root /path/to/project --apply
```

Apply Plan 会在写入前展示 operation kind、path、target、risk 和说明。

## 生命周期规范

详细规范见 [docs/capability-lifecycle.md](docs/capability-lifecycle.md)，包括：

- `.agents` 在电脑维度和项目维度的启用、禁用和更新逻辑。
- Codex Desktop Plugin 的 install、enable、disable、remove 和 update 行为。
- Claude Code Plugin 的作用域和原生命令。
- Plugin 更新检查和触发命令。
- signed DMG、notarization 和 Sparkle 更新流程。

## 发版

本地发版验证：

```bash
script/release_github.sh v0.1.0
```

正式公开发版通过 GitHub Actions 的 tag workflow 触发，需要 Apple Developer ID 签名、notarization 凭据和 Sparkle EdDSA key。完整清单见 [docs/release.md](docs/release.md)。

## 开发检查

```bash
swift test
./script/xcode_build.sh build
./script/xcode_build.sh test
```

## 文档

- [docs/README.md](docs/README.md)：文档索引。
- [docs/capability-lifecycle.md](docs/capability-lifecycle.md)：Agent 能力生命周期规范。
- [docs/release.md](docs/release.md)：签名、notarization、DMG 和自动更新流程。
