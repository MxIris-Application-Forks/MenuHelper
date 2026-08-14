# 0001 - 更改 Finder 所选符号链接目标

- **状态**: Implemented
- **作者**: JH
- **创建日期**: 2026-08-14
- **最后更新**: 2026-08-14
- **所属愿景**: 无
- **关联提案**: 无
- **实现分支 / PR**: `release/4.0` / 待定
- **配套文档**: [符号链接目标替换实现说明](SymbolicLinkTargetReplacement.md)

## 摘要

为 MenuHelper 增加一个可配置的 Finder 动作菜单“更改符号链接目标”。用户在 Finder 中选中单个 symbolic link（符号链接）后，先通过系统文件选择器选择新的文件或文件夹目标；随后确认框同时显示旧目标和新目标；点击“更改”后以不会先删除原链接的方式替换其指向，并通过结果弹窗明确提示成功或失败。

本提案中的“更改位置”指修改 symbolic link 指向的目标，不移动 symbolic link 文件本身。

## 动机

MenuHelper 当前只能复制路径、复制文件名、前往上层文件夹和新建文件，不能直接修改 Finder 所选 symbolic link 的目标。用户需要离开 Finder 菜单并使用 Terminal 重新创建链接，且常见的 `removeItem` 后再 `createSymbolicLink` 写法会在第二步失败时丢失原链接。

用户要求的交互顺序是：选择新位置 → 查看旧位置和新位置 → 点击更改 → 查看成功或失败结果。本提案把这条完整链路放进现有 Finder Sync 动作菜单，同时保留 App Sandbox（应用沙盒）边界，不引入 shell 命令或特权 helper。

## 前期调研

- **现有动作入口**：`Shared/Model/ActionMenuItem.swift:29` 的 `ActionMenuItem.all` 定义四个内置动作；`MenuHelperExtension/FinderSync.swift:163` 把启用的动作生成 Finder 菜单；`MenuHelperExtension/FinderSync.swift:178` 获取 `targetedURL()` 与 `selectedItemURLs()` 后把实际选择传给动作。
- **现有动作执行**：`MenuHelperExtension/MenuItemClickable.swift:85` 用持久化的 `actionIndex` 映射 `ActionKind`，并在 `MainActor` 上执行 AppKit 交互。新功能可以沿用该入口，不需要新进程间协议。
- **已有用户配置不会自动出现新动作**：`Shared/ViewModel/MenuItemStore.swift:133` 在存在 `ACTION_ITEMS` 时完整采用解码结果。仅把新动作加入 `ActionMenuItem.all` 只对首次安装或手动重置菜单的用户生效，因此需要按稳定的 `key` 补齐缺失动作，同时保留已有顺序和启用状态。
- **Foundation 能读取和创建链接**：`FileManager.destinationOfSymbolicLink(atPath:)` 返回 symbolic link 保存的目标字符串，旧链接使用相对路径时返回值也仍是相对路径；`FileManager.createSymbolicLink(atPath:withDestinationPath:)` 不遍历目标路径，也不会跟随 `path` 的最后一个 symbolic link。
- **`FileManager.replaceItemAt` 不适合作为链接替换原语**：在 `/tmp` 创建两个有效目标和两个 symbolic link 的本地探查中，`replaceItemAt(_:withItemAt:)` 返回 `NSCocoaErrorDomain Code=4`，称原 symbolic link 不存在；两个链接在失败后实际都仍存在。不能把该 API 的普通文件语义直接假设为 symbolic link 语义。
- **同目录 `rename` 已通过探查**：同样的测试改用 Darwin `rename` 后返回 `0`，原链接路径仍存在且目标已变为新位置，临时链接名称消失。macOS `rename(2)` 明确保证替换过程中目标名称始终存在，并明确说明最后一个路径组件为 symbolic link 时移动的是链接本身，而不是链接指向的文件或文件夹。
- **沙盒边界**：`MenuHelperExtension/MenuHelperExtension.entitlements` 已启用 `com.apple.security.files.user-selected.read-write`；Apple 文档说明 `NSOpenPanel` 会把用户选择的 URL 扩展进当前进程的沙盒作用域。实际替换仍可能受链接父目录权限、POSIX 权限、访问控制列表或只读文件系统限制，因此所有失败都必须保留原链接并向用户显示系统错误。Finder 选择是否对链接父目录提供足够的写入作用域仍需在签名后的扩展中做运行验证，当前静态分析不能替代该结论。
- **当前基线**：调研时位于 `release/4.0`，与 `origin/release/4.0` 一致，工作区无未提交改动。

## 提议方案

新增内置动作 `Change Symbolic Link Target`，中文显示为“更改符号链接目标”，默认启用并追加到动作列表末尾。动作只对 Finder 中恰好选中一个 symbolic link 的场景可用；执行入口再次验证选择，避免菜单生成后文件状态发生变化。

交互流程如下：

1. 读取 symbolic link 当前保存的目标。若它是相对路径，则以链接父目录为基准解析成绝对路径，仅用于向用户展示；不要求旧目标当前存在，因此也支持修复 broken symbolic link（目标已不存在的符号链接）。
2. 弹出 `NSOpenPanel`，允许选择一个现有文件或文件夹作为新目标。用户取消时不做任何写入，也不显示成败弹窗。
3. 弹出确认框，明确显示“旧位置”和“新位置”，按钮为“更改”和“取消”。
4. 用户点击“更改”后，在原链接父目录创建指向新绝对路径的唯一临时 symbolic link，再用 Darwin `rename` 原子替换原链接名称。失败时清理临时链接；由于不会先删除原链接，替换失败不会留下缺失状态。
5. 重新读取原链接的目标并核对。成功时显示“更改成功”和新位置；任何验证、权限或文件系统错误都显示“更改失败”及可读的系统原因。

已有用户加载 `ACTION_ITEMS` 时，按 `ActionMenuItem.key` 找出缺失的内置动作并追加；不重排、不重新启用用户已经配置过的旧动作。补齐结果直接写回共享 `UserDefaults`，避免 `MenuItemStore` 初始化期间通过尚未完成初始化的全局通知通道发送刷新消息。

### 非目标

- 不移动、重命名或删除 symbolic link 文件本身。
- 不批量修改多个 symbolic link；一次只处理一个，避免一个新目标如何映射多个旧目标的歧义。
- 不创建指向用户手工输入的不存在路径；新目标必须通过 `NSOpenPanel` 选择。
- 不增加任意 shell 命令、自定义脚本、特权 helper 或 Full Disk Access（完全磁盘访问）要求。
- 不在失败时静默请求更宽权限；当前批次先报告准确错误，签名扩展的运行验证若证明 Finder 选择未授予父目录写权限，再单独提案设计权限恢复流程。

## 详细设计

文件系统操作从 AppKit 弹窗代码中拆开，形成可独立测试的 Foundation 类型：

```swift
struct SymbolicLinkTargetInformation: Equatable, Sendable {
    let storedDestinationPath: String
    let displayedDestinationLocation: URL
}

enum SymbolicLinkTargetChanger {
    static func targetInformation(
        for symbolicLinkLocation: URL,
        fileManager: FileManager = .default
    ) throws -> SymbolicLinkTargetInformation

    static func replaceTarget(
        of symbolicLinkLocation: URL,
        with newTargetLocation: URL,
        fileManager: FileManager = .default
    ) throws
}
```

`targetInformation` 使用 `destinationOfSymbolicLink(atPath:)` 同时承担类型验证：普通文件和文件夹会抛错；broken symbolic link 仍能返回目标字符串。相对旧目标按 `symbolicLinkLocation.deletingLastPathComponent()` 解析后标准化，绝对旧目标直接标准化。

`replaceTarget` 使用隐藏且唯一的同目录临时名称。临时链接创建成功后调用 Darwin `rename`；若返回非零值，立即保存 `errno` 并抛出带 `NSPOSIXErrorDomain` 的错误。`defer` 只清理仍存在的临时链接，不删除原链接。新目标统一保存为绝对路径，使确认框看到的路径与最终链接内容一致。

动作模型增加新的稳定 `key` 和未复用的 `actionIndex`。Finder 菜单构建时只对该动作执行单链接可用性检查，其余动作保持现有行为。点击入口仍会重复验证，避免依赖菜单显示时的过期状态。

用户可见字符串同时进入主应用和 Finder 扩展的 String Catalog：主应用负责动作设置名称，扩展负责动作名称、选择器提示、确认框、按钮以及成功和失败提示。英文为 source language，补齐 Simplified Chinese（简体中文）翻译。

## 替代方案考量

- **先删除旧链接，再创建新链接**：实现最短，但创建失败时原链接已经丢失，不满足失败安全，否决。
- **使用 `FileManager.replaceItemAt`**：Apple 将它描述为防止普通项目替换数据丢失的 API，但本地 symbolic link 探查稳定返回“文件不存在”，否决。该反例需要保留，避免后续维护者把代码“简化”回不可用路径。
- **执行 `/bin/ln -sfn`**：需要从沙盒扩展启动外部进程，引入参数转义、可执行文件权限和 App Store 审核面，且没有比直接系统调用提供更多能力，否决。
- **通过主应用或特权 helper 修改**：需要跨进程传递安全作用域并新增通信、安装和授权生命周期；本功能只修改用户主动选择的普通文件系统项，不值得扩大架构与权限，否决。
- **保留新目标的相对路径形式**：`NSOpenPanel` 返回明确的文件 URL，而“相对哪个目录、何时应跨卷”没有用户输入。默认写入绝对路径能使确认内容与落盘内容完全一致；本批次不自动推导相对路径。
- **批量修改所有已选链接**：单个新目标可能让多个链接全部指向同一项目，也可能本意是逐项选择，需求不明确且确认界面会复杂化，留待独立需求。

## 影响

### 用户可见变化

Finder 的动作菜单和主应用“Action Menu Items”设置中新增“更改符号链接目标”。有效场景会依次出现新目标选择器、旧/新位置确认框和执行结果弹窗；取消选择或取消确认不会写入文件。

### 可发现性

新动作默认开启并排在已有动作之后。它会出现在主应用的动作列表中；Finder 仅在恰好选择一个 symbolic link 时提供该动作，避免普通文件场景出现不可执行入口。

### 数据与配置兼容

首次安装继续使用完整默认动作数组。已有 `ACTION_ITEMS` 会保留原顺序、开关状态和应用菜单配置，只在末尾补入缺失的新动作并持久化。

当前 `release/4.0` 对未知 `actionIndex` 有保护，因此回退到该版本后点击新动作只会记录未知动作错误，不会数组越界。更早、仍以闭包数组直接下标执行动作的历史版本不保证安全回退；发布说明如支持跨多个旧版本降级，需要单独标注。

### 平台与最低版本

仅影响 macOS 主应用和 Finder Sync 扩展。继续使用项目现有 macOS 14 最低版本，不改变其他平台支持。

### 发布

不新增 entitlement、privacy manifest、管理员授权、helper 或网络能力。操作继续依赖现有用户选择文件读写权限及文件系统自身权限。需要在签名后的 Finder Sync 扩展中验证至少一个用户目录内链接、broken symbolic link、只读位置和无写权限位置；未获得用户对交互式 Finder 验证的明确授权前，只执行非交互式构建与单元测试。

## 落地步骤

1. 新增可独立测试的 `SymbolicLinkTargetChanger`，覆盖相对旧目标解析、普通文件拒绝、broken symbolic link 修复、文件目标与文件夹目标替换，以及原链接路径保持不变。
2. 将新文件加入 Finder 扩展 target；在 `Package.swift` 增加只承载文件系统逻辑的内部 test target 和永久回归测试，不把 AppKit 弹窗耦合进测试模块。
3. 扩展 `ActionMenuItem` 与动作执行分支，加入单选 symbolic link 的二次验证、`NSOpenPanel`、旧/新位置确认和结果弹窗。
4. 在 Finder 菜单构建阶段加入新动作的适用性过滤；其余动作的显示逻辑不变。
5. 在 `MenuItemStore` 加入按稳定 `key` 补齐缺失内置动作的迁移，并验证旧顺序与开关状态保持不变。
6. 更新主应用和 Finder 扩展 String Catalog 的英文与 Simplified Chinese 字符串。
7. 先运行 `swift package update`，再用 `/tmp/codex/SwiftPM/MenuHelper` 作为独立 scratch path 执行全部 Swift Package 测试，并以 `swift test` 原始退出码判断成败。
8. 按 XcodeBuildMCP CLI 的既定三级回退规则，用 `/tmp/codex/DerivedData/MenuHelper` 完成 Debug 和 Release 构建；检查编译错误、警告和沙盒签名配置。
9. 若用户另行明确授权 Finder 交互式验证，再安装并运行签名扩展，按发布一节的场景检查实际弹窗、权限与结果；否则在交付总结中明确标注未执行该验证。
10. 收尾时判断文档：Darwin `rename` 的 symbolic link 语义与 `FileManager.replaceItemAt` 反例属于代码签名看不出的维护决策，若实现最终沿用本方案，应补一篇实现说明并从本提案双向链接；本功能没有引入项目自造术语，预计无需新增术语表。

## 决策日志

| 日期 | 变更 | 说明 |
|------|------|------|
| 2026-08-14 | Created as Draft | 用户要求新增 Finder 所选 symlink 的目标修改流程：选择新位置、确认旧/新位置、执行后提示成功或失败。 |
| 2026-08-14 | Accepted | 用户明确回复“接受提案，开始实现”。 |
| 2026-08-14 | In Progress | 按已接受方案开始实现文件操作、Finder 交互、配置迁移、本地化与回归测试。 |
| 2026-08-14 | Implemented | 完成单选 symbolic link 过滤、新目标选择、旧/新位置确认、Darwin `rename` 原子替换、结果弹窗、已有配置补齐与中英文本地化；8 个 Swift Package 测试、Debug 和 Release 构建均通过。未执行签名 Finder 扩展交互式验证。 |
| 2026-08-14 | Documentation review | 已新增[符号链接目标替换实现说明](SymbolicLinkTargetReplacement.md)并更新公开 README；没有引入项目自造术语，无需新增术语表。 |
