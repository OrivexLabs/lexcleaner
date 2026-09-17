# LexCleaner 目标

## 产品目标

LexCleaner 是面向 Apple Silicon 优先的原生 macOS 系统管理工具，长期整合：

- 安全清理
- 深度卸载
- 磁盘分析
- 系统与硬件监控
- 启动项管理
- 隐私管理
- App 更新
- 显示器管理
- 自动化能力

## 当前阶段目标

本阶段交付 Core-only 的只读 `Hardware Observability Foundation`：以 Swift Concurrency 和已审计的 macOS 原生公开/稳定低层 API 采集 Apple Silicon 硬件信息、thermal state、电池/电源来源和存储基础信息。不得实现 Dashboard UI、系统控制、风扇控制、功耗 shell 采样、SMC/IOReport 私有接口、root helper 或自动化。

## 当前成功标准

1. 工程使用 Swift、SwiftUI、Swift Concurrency 和 macOS 原生 API。
2. Core 与 UI 解耦，具备后续模块化扩展边界。
3. `SafeDeleteEngine` 在真实文件系统上完成路径安全检查、Dry Run、Trash 优先和日志记录。
4. 危险路径与正常路径测试真实通过。
5. 在当前环境中完成可执行构建和测试；完整 Xcode 构建若受环境限制必须明确记录。

## `feat/monitoring-hardware-ui` UI 交付目标

在既有只读 Core 数据基础上交付可运行的 Monitoring + Hardware SwiftUI 页面：展示 CPU、Memory、Disk、Network、Processes、Thermal、Hardware Info、Battery（设备支持时）、Storage Info 和实时趋势；直接消费真实 Core 快照，明确显示 unsupported/unavailable；页面离开停止采样；刷新频率可控；支持 zh-Hans/English、Light/Dark 和窗口缩放；完成独立 App Build、Core Tests、真实运行与 CPU/RSS 检查。

## 第二阶段目标：ScanEngine

在不触发任何删除操作的前提下，交付可真实运行的安全扫描发现服务：支持四类首批规则、并发受限的多目录遍历、流式进度/条目回调、权限与 symlink fail-safe、取消、去重和性能观测。

## 第三阶段目标：Cleaner Rules / Classification Engine

在不触发任何删除操作的前提下，交付默认 fail-closed 的规则层：支持 User Cache、Application Cache、Logs、Temporary Files，区分可重新生成缓存、App 状态、数据库、下载内容、Session、Credential 和 Extension Data，输出风险级别、原因、规则、应用归属和估算可回收空间。真实 macOS 目录只读验证，并人工抽查至少 30 个候选。

## 第四阶段目标：Cleaner Pipeline / Cleanup Plan

建立 `ScanEngine → ClassificationEngine → CleanupPlanner → User Selection → Dry Run → Preflight Revalidation → SafeDeleteEngine → Result / Audit` 的 Core-only 管线。第一版只允许 Trash，不提供永久删除；所有真实删除验证只使用受控临时目录。

## 第五阶段目标：Read-only Monitoring Foundation

建立与 SwiftUI 解耦的 `Monitoring` Core 模块，提供可取消、可配置采样间隔、非阻塞主线程的 CPU、Memory、Disk、Network、Process 快照；只读、不要求 root、不使用 private API，不自动触发任何系统修改。

## 第六阶段目标：Hardware Observability Foundation

建立与 SwiftUI 解耦的 `Hardware` Core 模块，提供显式 availability 的 `HardwareSnapshot`、`ThermalSnapshot`、`BatterySnapshot`、`StorageHealthSnapshot`、`SensorSnapshot`、`FanSnapshot` 和 `PowerSnapshot`。只实现审计通过的只读指标；无法可靠获得的指标返回 `unsupported` 或 `unavailable`，不伪造数据。

## 第七阶段目标：Disk Analyzer

在不触发任何删除操作、不给出垃圾判定的前提下，交付 Core-only 的只读磁盘分析：以低内存、可取消、并发受限的目录遍历增量生成目录聚合和 Treemap 数据模型，安全处理 canonical 去重、symlink loop/escape、权限错误和允许根边界。大文件结果仅是信息展示，支持阈值、Top N、年龄、类型、路径与大小字段，不自动传给 `ClassificationEngine` 或 `SafeDeleteEngine`。

## 第八阶段目标：App Manager Foundation

在不触发任何卸载或删除操作的前提下，交付 Core-only 的只读 App Manager：枚举可发现的 `.app`、读取 bundle metadata、大小、来源和公开签名状态，并基于 bundle identifier 精确分析 residual。未知、共享和低置信度关联必须 fail-closed；结果只能通过既有 Classification → CleanupPlanner → Dry Run → Preflight → SafeDeleteEngine 边界适配，不能自动执行。

## 第九阶段目标：System Tools Foundation

在不修改系统状态的前提下，交付只读 Startup、Privacy 和 App Update Foundation：读取标准 LaunchAgents/LaunchDaemons 与可靠的公开权限状态，区分 unsupported/unavailable/notDetermined/denied/authorized，并通过不耦合 Core 的 `UpdateProvider`/Sparkle adapter 边界提供更新 metadata。禁止启动项写操作、权限修改和自动安装更新。

## 第十阶段目标：SwiftUI 产品化骨架与 Dashboard

建立正式 macOS SwiftUI App Shell，包含 Sidebar、Dashboard、Cleaner、App Manager、Disk Analyzer、System Tools、Monitoring、Hardware 和 Settings 导航边界。首期 Dashboard 只展示现有 Core 的真实 Monitoring、Hardware、扫描分类与 App 枚举值；实时采样必须可取消，页面离开时停止无意义任务。Cleaner、卸载、磁盘分析和系统工具的详细交互后置，不在本阶段增加删除、控制或自动化路径。

## 第十一阶段目标：Cleaner 完整 UI

将现有真实 Core 管线连接到 macOS SwiftUI Cleaner 页面：

`Scan → Classification → Result → Selection → Dry Run → Confirmation → Preflight → Trash → Audit → Reclaimed Space`

本阶段只完成 Cleaner 的第一个完整可用工作流。safe、reviewRequired、protected、unknown 必须显示数量、空间、分类、规则和原因；safe 默认选中但可取消，reviewRequired 必须主动选择，protected/unknown 永远不可执行。第一版只能移动到 Trash，不提供永久删除，不批量触碰真实用户数据；真实 UI E2E 只使用显式受控临时 fixture。

## 第十二阶段目标：App Manager 完整 UI

将 App Manager Core 连接到原生 SwiftUI 产品界面：真实枚举已安装 App、搜索排序、metadata 和 residual 分析。卸载必须使用 `App Selection → Residual Analysis → UninstallPlan → Dry Run → Explicit Confirmation → Preflight → SafeDeleteEngine(.trash) → Audit`；应用本体与 residual 分开展示，应用本体只能作为精确、明确选择的 reviewRequired 目标。shared、protected、unknown、个人目录、symlink、sourceChanged 和 identity mismatch 永远 fail-closed；不提供永久删除、自动卸载或特权 helper。

## 第十三阶段目标：Disk Analyzer 完整 UI

将现有 `DiskAnalysisEngine` 连接到原生 SwiftUI Disk Analyzer 页面，提供真实卷容量、只读目录 Treemap、Top-N 大文件、文件类型统计、增量进度和可取消扫描。UI 不得把大文件或目录自动解释为垃圾，也不得绕过 `CleanupPlan`、Preflight 或 `SafeDeleteEngine`。

本阶段必须使用真实 macOS 数据验证 50,000+ 文件规模、Treemap 层级深入、大文件排序筛选、权限/symlink issue、取消、CPU/RSS 和 App 启动；与 Mole 的性能和可用性比较必须基于同一机器的可复现实测，不能凭功能数量宣称超越。

## 第十四阶段目标：正式 Sparkle 更新链路

在 App target 接入锁定版本的 Sparkle 2.x：使用 HTTPS appcast、Ed25519
feed/archive 签名校验、Sparkle 标准更新确认与安装器；支持手动检查、用户可配置
的自动检查、更新说明展示和安全失败状态。Feed URL、公钥、Developer ID 签名及
公证材料由发行构建注入，不提交私钥或伪造地址；缺少可靠材料时必须保持
`unavailable`，不得打开手动下载地址冒充正式更新。

## 第十五阶段目标：Network Optimizer

建立只读优先、可解释、可取消的 Network Health、DNS Benchmark、网络诊断和应用网络用量能力。
优先使用 `Network.framework`、`SystemConfiguration`、`CFNetwork` 和 Darwin 接口；无法可靠获得的网关、VPN、逐进程网络用量或 ICMP 丢包必须明确显示 unavailable/unsupported。
    任何 DNS 或网络配置修改都必须先生成 `NetworkOptimizationPlan`，记录原配置、候选配置和回滚信息，经用户确认及管理员授权后才可执行；当前首版不静默修改系统配置，不改变防火墙、IPv6、MTU 或系统安全策略。

## Friends Beta 反馈阶段

提供用户主动触发的诊断报告导出、诊断信息复制和 GitHub 反馈入口。报告只包含版本、构建、公开系统环境、模块能力状态、有限错误摘要和崩溃报告数量/时间；不包含用户名、私人路径、文件名、文件内容、Token、密码或凭据，也不自动上传任何数据。该阶段不改变 CPU、Disk 或 Network 核心算法。
