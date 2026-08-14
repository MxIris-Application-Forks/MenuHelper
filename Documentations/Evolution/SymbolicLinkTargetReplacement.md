# 符号链接目标替换：实现说明

> 配套提案见 [0001 - 更改 Finder 所选符号链接目标](0001-change-symbolic-link-target.md)。
> 本文记录实际落地的实现、维护时不能省略的文件系统约束，以及当前验证边界。面向维护者。

## 背景与目标

Finder 扩展新增“更改符号链接目标”动作：仅处理一个已选 symbolic link，允许用户选择文件或文件夹作为新目标，在确认旧位置和新位置后执行替换，并显示成功或失败。

文件系统层的目标不是“尽量完成替换”，而是失败时不能因为先删除旧链接而留下缺失状态。完整需求与备选方案见配套提案，本文只记录实际实现中容易被误改的部分。

## 关键设计决策

### 使用 Darwin `rename`，不使用 `FileManager.replaceItemAt`

本地对照测试创建了两个真实目标和两个有效 symbolic link。`FileManager.replaceItemAt(_:withItemAt:)` 返回 `NSCocoaErrorDomain Code=4`，称原 symbolic link 不存在；失败后两个链接实际都还存在。它对普通文件的数据保护说明不能直接推导到 symbolic link。

实际实现先在原链接父目录创建临时 symbolic link，再调用 Darwin `rename` 把临时名称替换到原名称。`rename(2)` 在 macOS 上明确保证替换期间目标名称始终存在，并明确规定最后一个路径组件是 symbolic link 时操作链接本身，而不是链接指向的项目。

不要把这段实现改成下面任一路径：

- `removeItem` 后 `createSymbolicLink`：第二步失败会丢失原链接。
- `FileManager.replaceItemAt`：已被真实 symbolic link 探查证伪。
- `/bin/ln -sfn`：会扩大沙盒外部进程、参数转义和分发审核范围。

### 临时链接必须与原链接同目录

同目录保证 `rename` 的两个名称位于同一文件系统，也让替换具备原子语义。临时名称使用 `.MenuHelper-SymbolicLink-Target-` 加唯一标识；创建或 `rename` 失败时由 `defer` 清理，成功后临时名称已经被移动，不再执行删除。

### 新目标落盘为绝对路径，旧相对目标只在展示时解析

`FileManager.destinationOfSymbolicLink(atPath:)` 会原样返回相对目标。确认框需要向用户展示实际位置，因此相对旧目标以链接父目录为基准解析成标准化绝对位置；保存旧值不被改写。

`NSOpenPanel` 返回明确的文件 URL，新链接统一保存其标准化绝对路径。这样确认框中的新位置与最终链接内容一致，也避免自动推导相对路径时产生跨卷和基准目录歧义。

### 配置迁移按稳定 `key` 补齐，不重置动作数组

已有用户的 `ACTION_ITEMS` 包含自定义顺序和启用状态。加载时只按 `ActionMenuItem.key` 找出缺失的内置动作并追加，不能用 `ActionMenuItem.all` 覆盖整个数组。

迁移结果直接写回共享 `UserDefaults`，不调用完整的 `save()`。原因是 `MenuItemStore` 是 Finder 扩展的全局对象，初始化时通知通道尚未完成初始化；在加载路径发送刷新消息会引入全局初始化顺序风险。

## 模块结构

```text
Shared/FileSystem/
└── SymbolicLinkTargetChanger.swift
    读取和展示旧目标，创建临时链接，执行原子替换并验证结果

MenuHelperExtension/
├── FinderSync.swift
│   仅在恰好选择一个 symbolic link 时生成新动作
└── MenuItemClickable.swift
    选择新目标、确认旧/新位置、调用文件系统层并显示结果

Shared/Model/ActionMenuItem.swift
└── 定义持久化的新动作及稳定 actionIndex

Shared/ViewModel/MenuItemStore.swift
└── 为已有 ACTION_ITEMS 补齐缺失动作
```

## 核心算法与数据流

1. `FinderSync.menu(for:)` 取得当前选择；新动作只在单选且 `destinationOfSymbolicLink` 可读取时加入菜单。
2. 点击后再次验证选择，防止菜单显示后文件类型发生变化。
3. 读取旧目标；broken symbolic link 仍可继续，因为读取链接内容不要求目标存在。
4. `NSOpenPanel` 选择一个现有文件或文件夹；取消时不执行写入。
5. `NSAlert` 显示解析后的旧位置和标准化新位置；取消时不执行写入。
6. 文件系统层确认原项目仍是 symbolic link、新目标仍存在，然后在原父目录创建临时链接。
7. Darwin `rename` 原子替换原链接名称；随后重新读取目标并与新绝对路径核对。
8. 成功与所有错误都通过结果弹窗反馈；系统权限错误保留原始 `NSError` 描述。

## 与提案的差异

无。实际实现采用提案中的单链接范围、绝对新目标、同目录临时链接、Darwin `rename`、已有配置补齐和中英文本地化方案。

## 验证

永久回归测试位于 `Tests/MenuHelperFileOperationsTests/SymbolicLinkTargetChangerTests.swift`，覆盖：

- 相对旧目标按链接父目录解析展示。
- 替换后链接名称不变，旧目标与新目标内容不变。
- broken symbolic link 可以改指向现有文件夹。
- 普通文件被拒绝且内容保持不变。
- 新目标已消失时拒绝替换并保留旧链接。

Swift Package 全部测试在独立 scratch path 下通过，原始 `swift test` 退出码为 `0`。`MenuHelper` scheme 的 Debug 和 Release 构建均使用独立 DerivedData 通过。

尚未执行签名 Finder 扩展的交互式验证，因此构建成功不能证明真实 Finder 菜单可见性、`NSOpenPanel` 展示效果或每个目录的沙盒写权限。

## 已知降级

- 一次只支持一个 symbolic link；多选时不显示动作。
- 新目标必须在选择后仍然存在；不存在时显示失败并保留原链接。
- 只读文件系统、父目录无写权限、App Sandbox、POSIX 权限或访问控制列表都可能阻止替换；此时显示系统错误，不尝试提升权限。
- 新目标写成绝对路径；不保留或自动生成相对路径形式。

## 延伸阅读

- [0001 - 更改 Finder 所选符号链接目标](0001-change-symbolic-link-target.md)
- [`FileManager.destinationOfSymbolicLink(atPath:)`](https://developer.apple.com/documentation/foundation/filemanager/destinationofsymboliclink(atpath:))
- [`FileManager.createSymbolicLink(atPath:withDestinationPath:)`](https://developer.apple.com/documentation/foundation/filemanager/createsymboliclink(atpath:withdestinationpath:))
