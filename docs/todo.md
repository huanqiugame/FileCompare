# 待办事项

记录 FileCompare 的后续计划、临时想法与已知问题。按优先级分区，确认完成的条目应移除。

## 高优先级

## 功能

## 界面与体验

## 工程与文档

## 已知问题

- macOS 14–15 兼容路径尚未在对应系统实机验证；目前仅在 macOS 27 上完成构建与测试。旧系统使用普通半透明卡片替代 Liquid Glass，并用 `scrollPosition(id:)` 回退滚动位置记录。
- RTF/HTML 转换目前未在 macOS 14/15 实机验证；`NSAttributedString` 的 RTF 导入和 HTML 导出在 macOS 27 上可在后台线程运行。
