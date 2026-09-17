# System Tools API / GitHub / License Audit

审计日期：2026-08-22。目标平台：macOS 13+、Apple Silicon 优先。

本阶段只实现只读状态采集。任何 API 无法提供公开、稳定、可区分的状态时，结果必须是 `unavailable` 或 `unsupported`，不得通过私有数据库、逆向格式、root helper 或猜测填充。

## Apple API feasibility matrix

| 能力 | 公开来源与权限 | 结论 |
|---|---|---|
| 应用已知 Login Item / LaunchAgent / LaunchDaemon | `ServiceManagement.SMAppService`（macOS 13+）；`status`、`statusForLegacyPlist(at:)` 为只读查询；不要求 root | **实现受限查询**。只查询调用方明确提供的 bundle identifier、plist 或当前应用服务，不声称枚举全机 Login Items。 |
| 所有 Login Items 枚举 | 旧 Shared File List 文档已归档/弃用；Background Task Management 数据库和相关工具没有稳定的公开应用 API | **不实现枚举**，返回 `unsupported`/审计问题；不读取私有 BTM 数据。 |
| LaunchAgents / LaunchDaemons 发现 | Foundation `FileManager` 只读列举标准目录，`PropertyListSerialization` 只读解析 plist | **实现**。目录和 plist 的 `Disabled` 字段只表示声明状态；未通过公开 API 验证 launchd 运行态时保持 `unknown`。 |
| 摄像头/麦克风授权 | `AVCaptureDevice.authorizationStatus(for:)`；只查询，不触发授权弹窗 | **实现当前应用授权状态**：`notDetermined`、`denied`、`authorized`；不实现当前使用进程监控。 |
| 摄像头/麦克风设备能力 | 公开 `AVCaptureDevice.default(for:)`；只发现设备，不启动 capture session、不请求授权 | **实现 capability**：设备可发现为 `available`，无设备为 `unavailable`；不以授权状态推断设备存在。 |
| 当前摄像头/麦克风使用进程 | 没有适合 Core 产品契约的公开、稳定、无需额外系统扩展的枚举 API | **不实现**；仅记录可行性边界。 |
| Accessibility | `AXIsProcessTrustedWithOptions`；本阶段传入不弹窗选项 | **实现**为 `authorized`/`denied`。 |
| Screen Recording | `CGPreflightScreenCaptureAccess` | **实现**为 `authorized`/`denied`；不触发请求。 |
| Full Disk Access | Apple 没有公开的“当前应用 FDA 授权状态”查询 API | **实现为 `unsupported`**，不通过访问文件或 TCC 数据库推断。 |
| App Store 更新状态 | App Store 的更新管理由系统控制；本 Core 层没有可依赖的公开、统一更新查询 API | **实现来源模型**并返回 `unsupported`，不伪造 App Store 更新结果。 |
| 直接分发更新元数据 | Core 只定义元数据/来源/验证结果模型，不下载、不安装 | **实现 `UpdateProvider` 协议**，由 App 层接入具体提供者。 |

## GitHub / License decisions

| 项目 | 审计事实 | 最终策略 |
|---|---|---|
| [LaunchManager](https://github.com/Sean10000/LaunchManager) | MIT；覆盖 LaunchAgents/LaunchDaemons 与 scope 展示；同时提供写操作和权限提升，目标 macOS 14+ | **仅参考模型/UX**。不复制代码，不采用其写操作、日志 shell 或提权路径；LexCleaner 只读实现。 |
| [Sparkle](https://github.com/sparkle-project/Sparkle) | MIT；长期维护的 macOS 更新框架，仓库同时列出 bsdiff、sais、Ed25519 等外部许可；截至审计时 GitHub 显示 2.9.2 发布 | **保留为 App 层可选适配器**。本轮不将 Sparkle 加入 Core 或构建依赖；不复制代码、不提交其二进制，因此本轮不新增第三方 License/NOTICE。未来真正引入时必须锁定版本、核对全部外部许可证并随发行物保留 License/NOTICE。 |
| [OverSight](https://github.com/objective-see/OverSight) | GPL-3.0；涉及更深的隐私事件监控/系统扩展边界 | **仅参考威胁模型**，不复制、不作为依赖。 |

## 记录的安全边界

1. Startup reader 不调用 `register`、`unregister`、`enable`、`disable`、`delete`、`launchctl load/unload` 或任何写操作。
2. Privacy reader 不请求权限、不访问 TCC 数据库、不读取私有状态、不把“无法查询”降级为“已授权”。
3. Update foundation 不自动下载、自动安装、替换 App、执行脚本或修改更新源；`UpdateProvider` 只返回已验证的元数据和候选动作。
4. Sparkle 适配器保持在 Core 之外：Core 通过协议/值类型接收结果，不导入 Sparkle，也不持有 Sparkle 对象。

## References

- Apple `SMAppService`: https://developer.apple.com/documentation/servicemanagement/smappservice
- Apple `AVCaptureDevice.authorizationStatus(for:)`: https://developer.apple.com/documentation/avfoundation/avcapturedevice/authorizationstatus%28for%3A%29
- Apple `AXIsProcessTrustedWithOptions`: https://developer.apple.com/documentation/applicationservices/1459186-axisprocesstrustedwithoptions
- Apple `PHPhotoLibrary.authorizationStatus(for:)` and EventKit authorization APIs were reviewed but deferred until product scope and entitlements are defined.
- Sparkle project: https://github.com/sparkle-project/Sparkle
