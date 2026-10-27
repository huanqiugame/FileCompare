## 安装

1. 下载 `.dmg`，打开后把 `FileCompare` 拖入「应用程序」。
2. 要求 macOS 27 或更高版本、Apple Silicon。当前包仅面向 arm64。

## 首次打开

本项目使用 ad-hoc 签名，未经 Apple 公证，macOS 首次打开会提示「无法验证开发者」：

- 在 Finder 中右键 App →「打开」→ 再次「打开」；或
- 执行 `xattr -dr com.apple.quarantine /Applications/FileCompare.app` 后再打开。

## 从源码构建

```sh
xcodebuild -project FileCompare.xcodeproj -scheme FileCompare -configuration Release \
  -destination 'platform=macOS' build
```
