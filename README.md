# LexCleaner

原生 macOS 系统管理工具，Swift + SwiftUI + Swift Concurrency，Apple Silicon 优先。

## 当前状态

当前仓库包含模块化 Core、SwiftUI App、Cleaner/App Manager/Disk Analyzer/System Tools/Network 页面，以及受控的 Sparkle 更新适配器。清理只允许经过 Dry Run、明确确认、Preflight 后移入 Trash；没有永久删除、特权 helper、启动项写操作或静默安装更新路径。正式分发仍要求 Developer ID 签名、公证、stapling 和真实签名 appcast，缺少这些材料时更新功能保持 unavailable。

## 本地验证

```sh
swift build
swift run LexCleanerCoreTestRunner
swift run LexCleanerScanTestRunner
swift run LexCleanerClassificationTestRunner
swift run LexCleanerCleanupTestRunner
swift run LexCleanerDiskAnalysisTestRunner
swift run LexCleanerAppManagerTestRunner
swift run LexCleanerSystemToolsTestRunner
```

测试 runner 使用真实临时文件、真实 symlink、权限变更、路径替换和目录扫描；SafeDelete 测试还使用真实 `FileManager.trashItem`，不是 Mock 删除流程。

工程入口：`LexCleaner.xcodeproj`。完整 Xcode 环境下打开后构建 `LexCleanerApp`。

## 数据与权限边界

LexCleaner 是 local-first 工具，不自动上传扫描结果、诊断报告、文件内容或网络数据，且不包含分析/遥测 SDK。它只在用户触发对应页面或操作时读取所需的公开系统状态和用户可访问文件元数据；详见 [`PRIVACY.md`](PRIVACY.md)。

网络页的 DNS benchmark 只执行网络探测；DNS 修改必须经过用户确认和管理员授权，并保留可恢复的本地事务记录。没有授权、配置变化、验证失败或回滚失败时，操作不会被宣称成功。

## 分发

发行前必须使用完整 Xcode、Developer ID Application 证书和已配置的 `notarytool` 凭据；发行检查器会在缺少任一前置条件时失败。具体步骤见 [`Updates/README.md`](Updates/README.md) 和 `scripts/verify_macos_distribution.py`。仓库不提交私钥、真实 feed 地址、签名归档或公证票据。
