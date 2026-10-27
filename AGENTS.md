# AGENTS.md

## 项目简介

- 项目：`FileCompare`（macOS 27，AppKit 窗口/菜单外壳 + SwiftUI 内容）
- Bundle ID：`com.huanqiu.FileCompare`；最低系统 macOS 27.0；仅 arm64。
- Scheme：`FileCompare`（shared）；测试 target：`FileCompareTests`（Swift Testing，host 为 FileCompare.app）。
- 源码：
  - `FileCompare/App`：应用入口、AppDelegate、窗口控制器、菜单、协调器
  - `FileCompare/Models`：Diff 模型、ComparisonSession、LauncherModel、AppSettings
  - `FileCompare/Engine`：原生 diff、Tokenizer、TextFileLoader、FileChangeMonitor
  - `FileCompare/UI`：启动器与比较页 SwiftUI 视图
  - `FileCompare/Resources/Localizable.xcstrings`：中英文
  - `FileCompareTests`：单元测试与离屏窗口快照
- 签名：目标使用手动 ad-hoc 签名（`CODE_SIGN_IDENTITY = "-"`），不依赖开发者账号；正常构建与测试均可在本机完成。
- Sandbox：启用 App Sandbox，仅 `com.apple.security.files.user-selected.read-only`；不执行沙盒外进程，diff 为原生实现。
- 测试生成快照路径会打印为 `SNAPSHOT_DIRECTORY ...`，位于 App 容器 `Data/tmp/FileCompareSnapshots-*`。

## Xcode MCP 工具（优先使用）

本项目已在 `opencode.json` 里配置了 Xcode 的 MCP 服务器：

```json
{ "mcp": { "servers": { "xcode": { "type": "local", "command": ["xcrun", "mcpbridge"] } } } }
```

Code Mode 下通过 `tools.xcode.<ToolName>` 调用（共 54 个工具）。相比直接读写文件或 `xcodebuild`，优先用这些工具，因为它们操作的是 Xcode 已打开的工程状态（编辑器文档、构建系统、scheme、destination、测试计划、运行中的应用）。

### 前置条件

1. Xcode 必须正在运行，且**本项目已在 Xcode 中打开**；否则先调用 `XcodeOpenWorkspace`。
2. Xcode → Settings → Intelligence → Model Context Protocol → 勾选 “Allow external agents to use Xcode tools”。
3. 首次连接需要用户在 Xcode 弹窗中批准该 agent。

### 关键约定

- **必须传 `workspaceIdentifier`**：工作区一旦打开，绝大多数工具都要求显式传入（例：`workspace-yJlRtrakhS`）。不确定时先调用 `XcodeListWorkspaces()`；该 ID 随 Xcode 会话变化，不要写死在代码或脚本里，每次会话重新获取。
- 传入已失效的 identifier 时，工具报错里会列出当前可用的 identifier 与路径，据此更新即可。
- 项目内路径使用 Xcode 工程组织路径（如 `FileCompare/ContentView.swift`），而不是文件系统绝对路径。

### 常用工具

| 用途 | 工具 |
| --- | --- |
| 打开/列出/关闭工程 | `XcodeOpenWorkspace`、`XcodeListWorkspaces`、`XcodeCloseWorkspace` |
| 浏览与搜索 | `XcodeLS`、`XcodeGlob`、`XcodeGrep` |
| 读取/编辑文件 | `XcodeRead`、`XcodeUpdate`、`XcodeWrite`、`XcodeMV`、`XcodeRM`、`XcodeMakeDir` |
| 编译诊断 | `XcodeRefreshCodeIssuesInFile`、`GetFileCompilerFlags`、`GetBuildLog` |
| 构建与运行 | `BuildProject`、`RunProject`、`StopProject`、`GetConsoleOutput` |
| Scheme / 目标 / 测试 | `XcodeListSchemes`、`XcodeSwitchScheme`、`XcodeListRunDestinations`、`XcodeSwitchRunDestination`、`XcodeListTargets`、`GetTestList`、`RunAllTests`、`RunSomeTests` |
| 构建设置 | `GetTargetBuildSettings`、`UpdateTargetBuildSetting` |
| 调试与预览 | `InvokeDebuggerCommand`、`RenderPreview`、`RunCodeSnippet` |
| 真机/模拟器交互 | `DeviceInteractionStartSession`、`DeviceInteractionStartWorkspaceSession`、`DeviceInteractionSynthesize` |
| 文档与本地化 | `DocumentationSearch`、`StringCatalogRead`、`StringCatalogEdit`、`LocalizationPlanner` |

## 其他约定

- 修改后验证顺序：`XcodeRefreshCodeIssuesInFile` 查诊断 → `BuildProject` 确认编译 → `RunAllTests` → 需要时 `RunProject` 并读 `GetConsoleOutput`。
- 正常构建用 `BuildProject(buildForTesting: false)`；测试构建用 `buildForTesting: true`。测试构建会注入测试专用 entitlements，不能据此判断沙盒实际权限。
- 命令行 `xcodebuild test` 前先 `killall FileCompare`，否则运行中的 App 会与测试 host 冲突，导致测试 host 提前退出、大量测试显示 0.000 秒失败。
- App 使用 `AppLog`（OSLog subsystem `com.huanqiu.FileCompare`）记录打开事件、比较加载与失败；排查 Finder 打开/自动重载可用 `/usr/bin/log stream --predicate 'subsystem == "com.huanqiu.FileCompare"'`。
- 窗口可用 `CGWindowListCopyWindowInfo(.optionAll, ...)` 检查标题、大小与位置，无需屏幕录制权限。
- 不要用外部 `delta`/`git` 进程：当前沙盒设计为纯原生 diff；如需接入，必须先打包自包含 helper。
- 用 `XcodeUpdate` 改文件时，`oldString` / `newString` 用字面字符（`XcodeRead` 输出里的 `\\d` 对应参数里的 `\d`）。
- 多个 Xcode 实例同时运行时，可用环境变量 `MCP_XCODE_PID` 固定连接目标。
