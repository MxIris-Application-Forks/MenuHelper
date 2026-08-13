# Swift 并发隔离改造

## 动机

项目启用严格并发检查后，完整 Debug 构建会产生 19 条 Swift 并发警告。警告主要来自三类问题：可观察状态没有明确的执行器归属、值类型没有声明可安全跨隔离域传递，以及 Finder 回调直接访问主执行器状态。

这些警告在未来切换到 Swift 6 language mode 后可能升级为编译错误，因此本次改造先在现有 Swift 5 language mode 下明确隔离边界，并保持现有运行行为。

## 范围

本次改造覆盖：

- 主应用和 Finder 扩展的 target 级默认 actor isolation。
- 菜单与文件夹数据模型的 `Sendable` 边界。
- `MenuItemStore`、`FolderItemStore`、StoreKit 状态和进程间通知通道的 `MainActor` 隔离。
- Finder 菜单构建回调读取数据的线程安全快照。
- AppKit 和 StoreKit 异步操作的执行器切换及任务生命周期。

不包含切换到 Swift 6 language mode，也不改变菜单功能、应用间通知名称或持久化格式。

## 关键设计与取舍

### 主应用默认使用 MainActor

`MenuHelper` target 的默认 actor isolation 设置为 `MainActor`。主应用的大部分代码直接维护 SwiftUI、AppKit 和 StoreKit 界面状态，这些状态本来就只能在主执行器上修改。采用 target 级默认值可以让未显式标注的界面代码获得一致的隔离语义，同时减少重复标注。

### Finder 扩展保持 nonisolated

`MenuHelperExtension` target 的默认 actor isolation 保持 `nonisolated`。项目历史中曾经把 `FIFinderSync.menu(for:)` 隔离到 `MainActor`，随后因为 Finder 调用该入口时发生扩展崩溃而撤销。因此不能把整个扩展默认隔离到主执行器。

`menu(for:)` 和菜单点击入口继续作为非隔离边界。它们不再直接访问 `MainActor` 隔离的 store，而是读取 `FinderMenuSnapshot`。该快照内部用 `NSLock` 保护完整的菜单值数组；store 刷新完成后一次性替换快照，Finder 回调只取得一份值副本。

### 值模型显式声明 Sendable

菜单项和文件夹项是用于持久化和跨隔离域传递的值类型，因此相关协议及结构体显式采用 `Sendable` 和 `nonisolated`。它们不持有可变共享引用；图标是按需计算的派生值，不参与跨线程共享存储。

### AppKit 操作显式回到 MainActor

菜单点击可以从 Finder 的非隔离入口进入，但打开应用、写入 pasteboard、弹出 panel、更新 store 等 AppKit 操作都在 `Task { @MainActor in ... }` 内执行。动作菜单不再保存闭包数组，而是把持久化的 action index 映射到值语义枚举后执行，避免把 actor-isolated closure 存进共享静态状态。

### 通知和 StoreKit 任务具有明确归属

进程间通知使用 block observer，并指定主队列；回调通过 `MainActor.assumeIsolated` 断言该队列契约后更新 store。StoreKit listener 继承 `Store` 的 `MainActor`，并使用 `isolated deinit` 在同一隔离域取消任务，避免 detached task 捕获可变状态。

### 受控使用 unchecked Sendable

只有自行提供同步保证的引用类型使用 `@unchecked Sendable`：`FinderMenuSnapshot` 和 `AppIconCache` 都以锁保护全部可变状态。`UserDefaults.group` 使用定点的 `nonisolated(unsafe)`，依据是 Apple 将 `UserDefaults` 列为线程安全类型；没有把这一豁免扩散到业务状态。

## 影响面

- 主应用的界面状态修改现在由编译器约束在主执行器上。
- Finder 菜单仍可从系统提供的任意回调上下文同步创建，不依赖 actor hop，因此不会引入等待主执行器的延迟或恢复历史崩溃。
- 菜单配置刷新后会同时替换 Finder 快照；菜单动作从同一快照解析对应项。
- 持久化数据结构和通知协议保持不变，现有用户无需迁移数据。

## 迁移与后续注意事项

- 新增主应用界面状态时，优先沿用默认 `MainActor`；只有纯计算或明确的并发边界才使用 `nonisolated`。
- 新增 Finder 回调时，不要直接读取 `menuStore` 或 `folderStore`；需要同步读取的数据应先复制进受保护快照。
- 新增跨隔离域模型时，应优先使用不可变的 `Sendable` 值，而不是添加 `@unchecked Sendable`。
- 将来切换 Swift 6 language mode 时，应重新执行完整 Debug 与 Release 构建，并把新出现的诊断作为独立迁移处理。

## 验证

使用 agent 专属 DerivedData 对 Debug 和 Release 配置分别执行 clean build，并检查构建诊断中没有 Swift warning 或 error。Swift Package 回归测试使用独立 scratch path，避免与用户正在进行的构建共享缓存或锁。
