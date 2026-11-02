## 安装

1. 下载 `.dmg`，打开后把 `FileCompare` 拖入「应用程序」。
2. 要求 macOS 14 Sonoma 或更高版本、搭载 Apple 芯片的 Mac。

## 首次打开

本项目使用 Apple Development 证书签名（不是 Developer ID 分发证书），且未经 Apple 公证，macOS 首次打开仍会提示「无法验证开发者」：

- 在 Finder 中右键 App →「打开」→ 再次「打开」；或
- 执行 `xattr -dr com.apple.quarantine /Applications/FileCompare.app` 后再打开。

## 从源码构建

```sh
xcodebuild -project FileCompare.xcodeproj -scheme FileCompare -configuration Release \
  -destination 'platform=macOS' build
```
