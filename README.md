# FileCompare

面向文档工作的 macOS 图形化文件比较工具。使用 Swift、SwiftUI 与 macOS 27 SDK 构建。

## 系统要求

- macOS 27 或更高版本
- Xcode 27
- Apple Silicon

## 构建与运行

在 Xcode 中打开 `FileCompare.xcodeproj`，选择 `FileCompare` scheme 与 `My Mac` 运行。

命令行构建：

```sh
xcodebuild \
  -project FileCompare.xcodeproj \
  -scheme FileCompare \
  -configuration Debug \
  -destination 'platform=macOS' \
  build
```

项目使用手动 ad-hoc 签名，便于本机运行。App Sandbox 已启用，仅申请“用户选择文件读取”权限，不访问沙盒外目录，也不启动外部进程。

测试（运行前请先退出正在运行的 FileCompare，避免与测试 host 冲突）：

```sh
xcodebuild test \
  -project FileCompare.xcodeproj \
  -scheme FileCompare \
  -destination 'platform=macOS'
```

## 功能

- 两个文件的行级 + 字词级差异高亮；中文按单字，英文/数字按词。
- 自动换行，单一滚动容器保证左右两侧严格同步。
- 启动器双拖放区，可点击选择文件；两侧就绪后点击“比较”。
- Finder “使用 FileCompare 打开”：一个文件进入启动器左侧，两个文件直接打开比较页。
- 多窗口；每个比较独立。
- 标题为 `文件名A vs 文件名B`；文件名可点击更换，悬浮显示真实文件图标并可拖出；`vs` 悬浮变为交换按钮。
- 菜单栏提供忽略空白、忽略大小写、查找、差异跳转、重新载入、自动重新载入、行号开关、字号调整、交换左右等操作。
- 自动重新载入使用 `stat(2)` 轮询，支持原地写入、删除重建与原子替换，并尽量保留阅读位置。
- 支持 UTF-8、UTF-16（含 BOM）、GB18030；拒绝二进制文件。
- 界面跟随系统语言，提供简体中文与英文；控件优先使用 SF Symbol。

## 架构

- `FileCompare/App`: AppKit 窗口/菜单外壳，SwiftUI 通过 `NSHostingController` 承载。
- `FileCompare/Models`: diff 文档模型、比较会话、启动器状态、全局显示设置。
- `FileCompare/Engine`: 原生 diff 引擎（Foundation `CollectionDifference`）、中文/英文 tokenizer、文件解码、自动重载监听。
- `FileCompare/UI`: 启动器与比较页 SwiftUI 视图、玻璃标题、查找栏、状态视图。
- `FileCompareTests`: Swift Testing 单元测试与离屏窗口快照。

## 说明与限制

- **沙盒与 delta**：App Sandbox 不允许执行沙盒外的 `/opt/homebrew/bin/delta`，因此当前使用沙盒安全的原生 diff 引擎。若后续需要 delta，可打包自包含 helper 并接入现有 diff 接口。
- **Markdown**：按源文本比较，保留标记，以保证逐行对齐和词级定位；不内联渲染 Markdown。
- **只读**：不提供编辑或保存。
- **末尾换行差异**：当前不单独标记“文件末尾缺少换行”。
- **大文件**：超过 50 MiB、200,000 行或单行 50,000 字节会拒绝。大文件先用两侧唯一的公共行做锚点分段，再对每个小段做 diff，避免把整段未变化内容误标为修改；只有找不到锚点的极端差异密集区才退化为线性兜底。
- **编码识别**：没有 BOM 的编码只能启发式判断；极端短文本或罕见字符可能被误判。
