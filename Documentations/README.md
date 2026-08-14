# MenuHelper 内部文档

- [Evolution 提案状态](Evolution/README.md)：列出需要审批的功能与架构提案，并保留早期演进记录入口。
- [更改 Finder 所选符号链接目标](Evolution/0001-change-symbolic-link-target.md)：设计选择新目标、确认旧/新位置、原子替换链接及结果提示的完整流程。
- [符号链接目标替换实现说明](Evolution/SymbolicLinkTargetReplacement.md)：记录为何使用 Darwin `rename`、如何保留旧链接以及配置迁移边界。
- [访达菜单图标性能优化](Evolution/FinderMenuIconPerformance.md)：说明菜单图标缓存的延迟原因、缩略图方案、迁移方式与回归测试。
- [Swift 并发隔离改造](Evolution/SwiftConcurrencyIsolation.md)：记录主应用与 Finder 扩展采用不同隔离策略的原因、实现边界和验证方式。
