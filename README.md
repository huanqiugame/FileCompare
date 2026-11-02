# FileCompare

专门面向文档工作的 macOS 图形化文件比较工具。使用 Swift、SwiftUI 与 macOS 27 SDK 构建，兼容 macOS 14 Sonoma 及以上版本。

相比于其他绝大多数面对代码场景开发的文档比较工具，此工具小巧（仅不到4MB）、简洁、美观，移除了绝大多数冗余功能，尽力保证文档的阅读体验。

> [!IMPORTANT]
>
> 该项目仍处于开发起步阶段，基本功能可用，但有大量 Bug 和可优化空间。欢迎提交反馈！

## 特性

- 支持中英双语。
- 支持在访达 “使用 FileCompare 打开” 两个文件直接进入比较。
- 支持多窗口。
- 支持从程序坞图标的右键菜单快速重新打开最近的对比（以 A vs B 列出）。
- 重新设计的比较界面：主要功能全部浓缩到标题栏，为内容预留最大空间。
- 提供忽略空白、忽略大小写、查找、差异跳转、重新载入、自动重新载入、行号开关、字号调整、交换左右等操作。
- 比较一对 Markdown 文件时，可按 CommonMark/GFM 语法解析并比较渲染后的结构：标题写法、强调标记、列表符号、代码块形式和段落换行等纯格式差异不再被报告。可在「比较」菜单中用 `⌘⇧M` 开关。
- 支持文件修改后自动重新读取并尽量保留阅读位置。

## 系统要求

- 搭载 Apple 芯片的 Mac
- macOS 14 Sonoma 或更高版本

## 构建与运行

在 Xcode 中打开 `FileCompare.xcodeproj`，选择 `FileCompare` scheme 与 `My Mac` 运行即可。

或使用命令行构建：

```sh
xcodebuild \
  -project FileCompare.xcodeproj \
  -scheme FileCompare \
  -configuration Debug \
  -destination 'platform=macOS' \
  build
```

项目使用手动签名：macOS 构建使用 Apple Development 证书（Team `X422JUDN4K`）并启用 Hardened Runtime。首次从源码构建前，请确保本机已安装该 Team 的 Apple Development 证书；也可以把 `CODE_SIGN_IDENTITY[sdk=macosx*]` 改为 `-` 使用 ad-hoc 签名。

测试（运行前请先退出正在运行的 FileCompare）：

```sh
xcodebuild test \
  -project FileCompare.xcodeproj \
  -scheme FileCompare \
  -destination 'platform=macOS'
```

## 架构

- `FileCompare/App`: AppKit 窗口/菜单外壳，SwiftUI 通过 `NSHostingController` 承载。
- `FileCompare/Models`: diff 文档模型、比较会话、启动器状态、全局显示设置。
- `FileCompare/Engine`: 原生 diff 引擎（Foundation `CollectionDifference`）、中文/英文 tokenizer、文件解码、自动重载监听、Markdown 语义规范化（基于 `swift-markdown`）。
- `FileCompare/UI`: 启动器与比较页 SwiftUI 视图、玻璃标题、查找栏、状态视图。
- `FileCompareTests`: Swift Testing 单元测试与离屏窗口快照。

## 限制

- **Markdown**：仅当左右两侧都是 Markdown 文件（`.md`、`.markdown`、`.mdown`、`.mkd` 等）且「按 Markdown 语法渲染」开启时启用语义比较；混合文件对仍按纯文本比较。行号对应渲染后的块行，而非原始源码行。
- **.doc(x)/.pdf/.rtf/.html等**：暂不支持，可期待后续版本。
- **只读**：暂不提供编辑或保存功能。
- **大文件**：超过 50 MiB、200,000 行或单行 50,000 字节的文件会被拒绝。
- **编码识别**：没有 BOM 的编码、极端短文本或罕见字符可能被误判。
