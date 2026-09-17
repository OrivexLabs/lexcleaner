# Disk Analyzer 集成请求

## 公共接口

本分支新增 `DiskAnalysis` 模块的只读公共模型与 actor：

- `DiskNode` / `DiskTree` / `TreemapNode`
- `FileCategory` / `LargeFileEntry` / `DiskAnalysisSnapshot`
- `DiskAnalysisEngine`

## 集成边界

该模块只遍历并报告文件系统信息，不产生 `CleanerCandidate`，不调用
`CleanupPlanner` 或 `SafeDeleteEngine`，也不把大文件判定为垃圾。合并时只需将
模块源码、测试和 Xcode/SwiftPM target 文件保留；没有对既有 Core 删除接口的要求。

## 许可证

未引入第三方依赖；实现使用 Swift Concurrency、Foundation 和 Darwin 原生能力。

## App Manager 集成请求

新增只读 `AppManager` 公共类型：`InstalledApp`、`AppMetadata`、`AppResidualCandidate`、
`ResidualConfidence`、`UninstallPlan` 和 `UninstallPlanItem`。`InstalledApp` 还提供可选
大小/修改时间、来源和公开 Security 签名状态；无法可靠取得时保持 unknown/unavailable。
该模块不修改 Classification/Cleanup/SafeDelete 公共接口，不自动卸载、删除或修改系统。

## System Tools 集成请求

新增只读 `StartupReader`、`PrivacyReader` 和 `UpdateProvider`/metadata 模型；本分支不修改
系统状态，不启用/禁用/删除启动项，不申请或修改隐私权限，不自动安装更新。Sparkle
只保留 adapter 协议边界，未加入依赖；未知状态保持 `unsupported`/`unavailable`。
