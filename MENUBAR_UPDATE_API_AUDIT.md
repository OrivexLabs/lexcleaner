# Menu Bar / App Update API Audit

日期：2026-08-23。目标：macOS 13+、Apple Silicon 优先。

## 决策

- Menu Bar 使用 SwiftUI `MenuBarExtra`，不引入 SwiftBar 的脚本插件执行器；指标来自现有只读 `MonitoringSampler`。
- 菜单栏采样间隔固定为 2 秒，`includeProcesses = false`，保留 CPU/内存/网络/磁盘快照并避免无关进程枚举。
- App Update 复用 Core 的 `UpdateProvider` 与 `SparkleUpdateAdapter` 协议边界。当前构建不携带 Sparkle 二进制、下载器或安装器；没有 feed/runtime 时返回 `unavailable`。
- 更新 UI 只允许用户触发检查；候选动作必须经确认后打开 HTTPS 手动地址。不会自动下载、解包、替换、重启或安装。

## License

本轮未引入第三方依赖、二进制或复制代码，因此没有新增 License/NOTICE 文件。Sparkle 后续真正接入前必须锁定版本、审查 bsdiff/sais/Ed25519 等外部许可，并随发行物保留全部要求；GPL、AGPL、Commons Clause 和商业限制项目不进入核心。
