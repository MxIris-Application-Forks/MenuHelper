# Evolution 提案

- **项目类型**: App

本目录沿用项目已有的 `Documentations/Evolution/` 路径。编号且使用 kebab-case 文件名的是需要审批的 Evolution 提案；既有 PascalCase 文件为早期演进记录。

## 提案状态

| 编号 | 标题 | 状态 |
|------|------|------|
| 0001 | [更改 Finder 所选符号链接目标](0001-change-symbolic-link-target.md) | Implemented |

## 早期演进记录

- [访达菜单图标性能优化](FinderMenuIconPerformance.md)
- [Swift 并发隔离改造](SwiftConcurrencyIsolation.md)

## 配套实现说明

- [符号链接目标替换](SymbolicLinkTargetReplacement.md)：记录原子替换、路径表示、配置迁移与验证边界。
