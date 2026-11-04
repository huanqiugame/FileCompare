# FileCompare

专门面向文档工作的 macOS 图形化文件比较工具。使用 Swift、SwiftUI 与 macOS 27 SDK 构建，兼容 macOS 14 Sonoma 及以上版本。

相比于其他绝大多数面对代码场景开发的文档比较工具，此工具小巧（4MB左右）、简洁、美观，移除了绝大多数冗余功能，尽量保证文档的阅读体验。

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
- 支持忽略纯格式差异。
- 支持任意纯文本和 Markdown (.md)、 RTF (.rtf)、 HTML (.html) 等富文本文档。
- 支持文件修改后自动重新读取并尽量保留阅读位置。

## 系统要求

- 搭载 Apple 芯片的 Mac
- macOS 14 Sonoma 或更高版本

## 构建与运行

项目目前使用本人自己的 Apple Development 证书。若要自行编译，请前往 Xcode 中选择本项目，将 Team 修改为 None，Signing Certificate 设置为 Sign to Run Locally。

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
- `FileCompare/Engine`: 原生 diff 引擎（Foundation `CollectionDifference`）、中文/英文 tokenizer、文件解码、自动重载监听、RTF/HTML → Markdown 转换（AppKit `NSAttributedString` + Kanna/系统 libxml2 + 内置 `HTMLMarkdownRenderer`）、Markdown 语义规范化（基于 `swift-markdown`）。
- `FileCompare/UI`: 启动器与比较页 SwiftUI 视图、玻璃标题、查找栏、状态视图。
- `FileCompareTests`: Swift Testing 单元测试与离屏窗口快照。

## 限制

- **.doc(x)/.pdf/.rtfd 等**：暂不支持，可期待后续版本。
- **富文本**：图片和嵌入媒体会被忽略；HTML 的 CSS 隐藏内容、颜色、字体等纯样式信息也不会参与比较。
- **只读**：暂不提供编辑或保存功能。
- **大文件**：纯文本超过 50 MiB、200,000 行或单行 50,000 字节会被拒绝；HTML 上限 20 MiB，RTF 上限 30 MiB。
- **编码识别**：没有 BOM 的编码、极端短文本或罕见字符可能被误判。
