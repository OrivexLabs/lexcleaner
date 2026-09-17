# LexCleaner 架构

## 分层

```text
LexCleanerApp (SwiftUI)
        ↓ 依赖 Core Services 协议/值类型
LexCleanerCore
  ├─ SafeDelete
  ├─ Scan
  ├─ Classification
  ├─ Cleanup
  ├─ Cleaner (后续)
  ├─ Uninstaller (后续)
  ├─ DiskAnalysis
  ├─ Monitoring
  ├─ Hardware
  ├─ StartupItems (后续)
  ├─ Privacy (后续)
  ├─ AppUpdates (后续)
  ├─ Displays (后续)
  └─ Automation (后续)
```

## 当前实现

- `SafeDeletePolicy`：声明白名单、Home 和系统关键路径硬保护。
- `SafeDeleteEngine`：`actor`，串行化同一服务实例的安全检查与文件操作；使用 Foundation `FileManager` 和 Darwin `lstat`/`realpath`。
- `SafeDeleteRiskAssessment`：输出标准化路径、解析后路径、文件类型、symlink 状态和风险等级。
- `SafeDeleteRiskAssessment` 同时记录目标 `lstat` 身份、解析后目标身份和白名单内 symlink 身份签名。
- `SafeDeleteOperationLogging`：异步日志协议；生产实现使用 `OSLog`，测试使用内存 logger。
- `SafeDeleteCoreTestRunner`：无 Xcode 时可直接运行的真实测试入口，使用临时文件和真实 Trash API。

## 删除数据流

```text
原始路径
  → 空/相对路径拒绝
  → 标准化路径
  → 存在性检查
  → realpath/lstat 解析
  → 根/Home/系统关键路径检查
  → 白名单与解析后边界检查
  → symlink 越界检查
  → Trash 模式再次 canonicalize/resolve、重做保护检查并比较对象身份
  → Dry Run 结果 或 FileManager.trashItem
  → OSLog / 测试 logger
```

## 边界与取舍

- 白名单是调用方显式配置的允许边界；没有白名单的路径不会进入删除流程。
- `/var -> /private/var` 是 macOS 系统路径别名，解析时按物理路径比较，避免误报；实际用户 symlink 仍需满足解析后白名单。
- Trash 操作仍受 macOS 权限、用户会话和 Trash 状态影响；失败会返回明确错误并写失败日志。
- Trash 执行前会进行两次重新评估；路径、解析结果、目标 inode/device、symlink 签名或保护状态任一变化即 `pathChanged`/fail-closed。
- `FileManager.trashItem` 是 macOS 的路径 API，检查通过到系统调用之间无法由本服务获得跨进程原子锁；该原生 TOCTOU 残余限制已明确记录，不能宣称被完全消除。
- 当前服务不提供 UI 确认流程；调用方必须在未来 UI 中展示 Dry Run 风险结果后再选择 Trash 模式。

## ScanEngine

- `ScanEngine` 是独立的发现服务，不导入、不调用 `SafeDeleteEngine`，也不返回可直接执行的删除命令。
- 扫描结果通过 `ScanProgress.item` 流式交付；`ScanResult` 只保存汇总、问题和性能指标，不把整棵文件树一次性放入内存。
- `DirectoryWorkQueue` 维护 canonical directory 去重集合，并用固定 worker 数限制并发；单次只加载当前目录的直接子项。
- 内置规则：`User Cache`、`Application Cache`、`Logs`、`Temporary Files`。Application Cache 只在限定深度发现明确的 cache 目录，不把 Application Support 当作可清理个人数据。
- 所有 symlink 都作为叶子节点处理，不递归；解析后越界记录 `symlinkEscape` 并跳过。
- `/System`、系统关键目录、Home 本身，以及 Home 下的 `Documents`、`Desktop`、`Projects` 默认硬排除。
- `ScanPerformanceMetrics` 记录耗时、固定上限的 resident-memory high-water 样本趋势和实际最大并发目录数。

## ClassificationEngine

- `ClassificationEngine` 是 `ScanEngine` 之后的只读规则层，输入 `ScanItem` 和显式规则，输出 `CleanerCandidate` 与四级统计；不依赖、不调用 `SafeDeleteEngine`。
- `CleanerRule` 通过来源类别、允许根、路径提示、数据用途、年龄/大小策略和排除规则匹配；多个规则同时命中时输出 `unknown/ruleConflict`。
- 硬保护优先于分类：系统/个人/凭据/浏览器/Git/数据库/Session/下载和未知数据用途不会进入 `safe`。
- User Cache 只有明确可重新生成、满足年龄/大小且源元数据未变化时才可为 `safe`；Application Cache、Logs 和 Temporary Files 默认至少 `reviewRequired`，新临时文件和活跃日志为 `protected`。
- 临时文件的“正在使用”检查保留为执行前能力边界：未来执行层应基于当前进程/系统打开句柄等 macOS 原生信息重新检查；本阶段分类层不把任何 Temporary File 标为 `safe`，使用状态无法确认时必须保持 `protected` 或 `reviewRequired`。
- 分类前重新读取 `lstat` 元数据并比较文件类型、大小和修改时间；差异输出 `unknown/sourceChanged`。本阶段不执行删除，因此不把候选自动交给删除服务。
- 真实验证通过独立 runner 对 macOS 用户缓存、Application Support、Logs 和系统临时目录只读扫描，输出四级数量/大小并抽查 30 项。

## CleanupPlanner

- `CleanupPlanner` 接收 `CleanerCandidate` 和 `CleanupSelection`，生成包含候选身份、原始/canonical path、device/inode/type、元数据、规则、原因、选择状态和 Trash 方法的 `CleanupPlan`。
- 不符合执行资格的候选仍可出现在计划中用于 Dry Run 拒绝报告，但 `eligibleItems` 只包含 `safe` 或明确选择并确认的 `reviewRequired`。
- Preflight 重新读取 lstat/realpath，调用 `SafeDeleteEngine.assess`，重新运行 ClassificationEngine，并比较路径、canonical path、类型、device/inode、symlink、保护状态和分类结果；任一变化即拒绝。
- `execute` 在调用 SafeDeleteEngine 前再次逐项 Revalidation，防止 Preflight 之后的变更绕过安全门禁；执行只使用 `.trash`，不支持永久删除。
- 每项独立产出 success/skipped/rejected/failed，并通过 `CleanupAuditLogging` 记录计划、Dry Run、Preflight、执行、选择、失败原因和 reclaimed bytes；路径日志由 OSLog hash 隐私处理。

## Monitoring Foundation

- `Monitoring` 是 Core-only、UI 无关的只读采样模块，不依赖或调用清理/删除服务。
- `MonitoringSnapshot` 聚合 `CPUSnapshot`、`MemorySnapshot`、`DiskSnapshot`、`NetworkSnapshot` 和 `ProcessSnapshot`；值类型不保存敏感内容。
- CPU/内存使用 macOS 原生公开接口；磁盘使用容量资源值和 I/O 统计；网络使用接口统计；进程使用公开的进程信息接口。
- `MonitoringSampler` 使用 Swift Concurrency，采样间隔可配置，任务可取消，采样在后台执行并通过异步流/回调交付结果，不阻塞 SwiftUI 主线程；`processLimit = 0` 表示返回完整可访问进程列表，正数可作为资源保护上限。
- 只读能力不要求 root；不使用 private API，不实现 kill、风扇控制、系统优化、自动化或任何系统状态写入。
- Stats（MIT）与 btop（Apache-2.0）只作为公开架构和采样思路参考，不复制代码或特权 helper，不新增第三方依赖。

## Hardware Observability Foundation

- `Hardware` 是 Core-only、UI 无关、只读的硬件可观测性模块，不依赖清理/删除服务，也不提供系统控制能力。
- 所有硬件结果通过 `HardwareAvailability` 显式表达 `available`、`unavailable`、`unsupported`；不可用指标没有伪造的零值或默认值。
- 首期允许的来源是 Foundation `ProcessInfo`、IOKit `IOPowerSources` / SDK battery keys、`IOPMCopyBatteryInfo`（仅 cycle count 兼容读取）以及 IOKit `IOMedia`/公开 storage properties 和审计通过的 `sysctl` 基本硬件键。
- SMC、IOReport、设备特定 sensor keys、`powermetrics` shell、fan control、root helper 和 SMART/wear 读取不进入正式 Core；详见 `HARDWARE_API_AUDIT.md`。
- `HardwareSampler` 使用 Swift Concurrency 和可配置间隔，在 detached utility task 中采样，支持取消，不阻塞主线程；各 collector 独立失败并返回明确 availability，不能因单项不支持而伪造整组数据。
- Storage topology is normalized as `Physical Disk → APFS Container → Volume`; synthetic APFS media, physical-store partitions and APFS snapshots are not separate disks. Physical/container capacities own user-facing totals, while System/Data and other APFS volume sizes are marked shared and never summed.
- Storage snapshots rebuild the topology from the current IOKit registry on each sample, so external media changes replace the complete list without stale disk-number state. Ordinary UI shows model/kind/capacity and volume roles; BSD names, UUIDs and physical stores are advanced details only. SMART/wear remain explicit `unsupported`.

## DiskAnalysis

- `DiskAnalysisEngine` 是 Core-only、只读、独立于删除/分类服务的目录分析器；调用方必须显式提供 `allowedRoots`，目标和所有解析后的路径都必须落在允许根内。
- 使用 `lstat` 识别节点、`realpath` 做 canonical 边界检查；symlink 只作为叶子节点记录，不能递归，因此 loop 不会形成递归或重复遍历。
- 固定 worker 数和 canonical directory queue 限制并发；每次只保留当前目录条目数组，结果仅保存目录聚合、权限/路径 issue 和受 `Top N` 限制的大文件，绝不保存完整文件树。
- `DiskTree.nodes` 只包含目录聚合节点；`TreemapNode` 是扁平、UI 无关的目录与 Top-N 大文件投影。大文件没有垃圾/删除语义。
- `DiskAnalysisSnapshot` 包含流式 update 已交付的最终汇总，并记录耗时、CPU time/平均 CPU、peak RSS、文件吞吐、最大目录并发、当前目录最大缓冲和取消延迟。

### SwiftUI 性能边界（2026-08-23）

- `DiskAnalyzerViewModel` 不保留 `DiskAnalysisSnapshot`；Core 完成结果在主线程桥接为有界 `DiskCompletedProjection`，仅包含当前层 Treemap、Top-N 大文件、内容统计和有限 issue 样本。
- Treemap 导航缓存最多保留 4 层，页面外层和大文件区使用惰性栈，避免把历史层或不可视行建立为 SwiftUI ViewGraph。
- 该边界不改变 Core 的 symlink、volume、权限、identity、watchdog、logical/allocated 统计与取消语义；实际执行删除仍与 Disk Analyzer 完全解耦。
- 真实 Profile 后 Home UI RSS 从约 229MB 降至约 160.1MiB，但仍未达到项目 ≤150MB 验收；不能将此优化标记为性能 PASS。
- 目录队列去重优先使用 getattrlistbulk 已返回且随后由 `fstat` 验证的 device+inode；元数据缺失时保留 canonical path 回退。该优化只压缩 transient queue memory，不替代执行前 identity 校验，也不改变 symlink/volume 边界。
- 完成 projection 在后台从 Core snapshot 派生，主线程只接收当前层、Top-N 和有限 issue；Dashboard/Cleaner/App Manager 模型按页面懒创建。真实 Home UI RSS 在约 149.89–151.22 MiB 间波动，仍以稳定 ≤150 MiB 未达标处理。

## AppManager

- `InstalledAppCatalog` 只读取允许的标准 Application roots，使用 bundle identifier、canonical path 和公开 `Info.plist` 元数据去重；无法读取的条目记录 issue，不猜测。
- `InstalledApp` 的大小、修改时间、来源和 Security 签名状态均为只读可选/枚举值；无法可靠获得时保持 `nil`、`unknown` 或 `unavailable`。
- `AppResidualAnalyzer` 只检查 bundle identifier 精确匹配的已知 residual 位置；共享容器、未知用途和不完整身份信息保持 protected/unknown，不能仅凭模糊文件名关联。
- `UninstallPlanItem.asCleanerCandidate()` 只是值类型适配，不触发卸载。任何未来执行仍必须经过既有 Classification、CleanupPlanner、Dry Run、Preflight 和 SafeDeleteEngine。

## System Tools

- `StartupReader` 只读取标准 LaunchAgents/LaunchDaemons plist 和可可靠查询的 `SMAppService` 状态；Login Items 或 BTM 私有状态不可可靠获得时返回 issue/unsupported，不使用写操作。
- `PrivacyReader` 只调用公开 AVFoundation、ApplicationServices 和 CoreGraphics 能力；Full Disk Access、未知 TCC 状态和设备当前摄像头/麦克风使用状态不猜测。
- `UpdateProvider` 是只读 metadata 协议；Sparkle 仅通过 adapter 边界接入设计，当前不将 Sparkle 二进制或安装器耦合到 Core，也没有自动更新 API。

## Network Optimizer

- `NetworkHealthCollector` 是 UI 无关、只读优先的 Core 服务，使用 `NWPathMonitor` 获取路径状态，Darwin `getifaddrs` 获取接口地址/累计字节/错误计数，SystemConfiguration 获取当前 DNS 和默认 IPv4 路由，CFNetwork 获取代理状态。
- 延迟使用可取消、有超时的 `NWConnection` TCP connect probe；DNS Benchmark 使用 Network.framework UDP DNS 查询包，单独记录 median、P95、jitter、timeout 和 failure rate。未实现 raw ICMP，因此“packet loss”不会被 TCP 探测结果冒充；UI 明确标为 probe failure 或 unavailable。
- `NetworkStatistics` 只包含无副作用的 percentile、median、jitter、failure-rate 和可解释评分函数；评分在缺少必要样本时返回 unavailable，不补零或猜测。
- `NetworkOptimizationService` 通过 `NetworkDNSConfigurationStore` 读取并绑定单一目标网络服务（service ID/interface），Apply 必须显式传入用户确认后才会请求 `AuthorizationCopyRights` 管理员授权；SystemConfiguration 事务只替换目标服务的 DNS server addresses，并在提交后重新读取验证。修改前后分别执行 DNS median/P95/jitter/timeout/failure 与 TCP latency/jitter/failure A/B；未改善自动恢复原配置，改善结果才返回 `applied`。
- DNS 修改前写入受保护的本地恢复 journal；修改失败、测量失败或应用在事务中断后，下次启动可识别 pending transaction 并 fail-closed 恢复且验证完整配置。Rollback 必须匹配当前候选配置，并逐字段验证原 DNS 配置；无授权、用户取消、服务变化、验证失败或 journal 失败均不扩大修改范围。
- 逐进程网络用量、VPN 精确状态和 ICMP 丢包不通过不稳定 shell 输出伪造；若没有受支持的公开 API 或权限，返回 unavailable/unsupported。Network 页面消费真实 Core 值类型，与既有 Monitoring 的接口累计 bytes/吞吐保持分工，不复制采样任务。
- NetworkMonitor（MIT）只参考菜单栏/应用用量 UX；Stats（MIT）只参考模块化采样；Mole（GPL-3.0）仅参考公开诊断思路。核心实现自研，不新增第三方依赖。

### 正式 Sparkle 更新链路（App target）

- `SparkleUpdateConfiguration` 只接受 HTTPS feed 和可解码为 32 字节的 Ed25519 公钥；缺少任一发行材料时 App target 不创建 Sparkle updater，Core 返回明确 `unavailable`。
- `SparkleUpdaterService` 使用 Sparkle 2.9.6 `SPUStandardUpdaterController`。Core 仍只看到 `SparkleUpdateAdapter`/`UpdateProvider`，不导入 Sparkle 或安装 API。
- `Info.plist` 开启 feed 签名和 extraction 前校验，自动检查默认关闭、自动安装默认关闭；Settings 只修改 Sparkle 自己持久化的 `automaticallyChecksForUpdates`，不维护第二份偏好。
- 手动检查进入 Sparkle 标准 UI，由 Sparkle 负责用户确认、HTTPS 下载、EdDSA/归档校验、解包和安装；feed、下载、签名或安装失败只产出错误，不替换当前 App。
- 发布所需的 appcast、签名归档、Developer ID 和 notarization 不在仓库中伪造；`Updates/README.md` 是发行边界和核验清单。

## SwiftUI App Shell 与 Dashboard

- `AppShellView` 是 App 层导航壳，使用 `NavigationSplitView` 管理 Dashboard、Cleaner、App Manager、Disk Analyzer、System Tools、Monitoring、Hardware 和 Settings 页面选择；非 Dashboard 页面当前仅展示明确的 foundation 状态，不冒充已完成的详细功能。
- `DashboardViewModel` 是 `@MainActor` 的生命周期协调器，只持有 App 层展示状态；`MonitoringSampler`、`HardwareSampler`、`ScanEngine`、`ClassificationEngine` 和 `InstalledAppCatalog` 仍保持 Core 与 SwiftUI 解耦。
- Dashboard 实时卡片使用 `MonitoringSnapshot` 与 `HardwareSnapshot`；Overview 的可清理空间严格只扫描当前已校准 User Cache safe 规则，并复用 `/Applications`/`~/Applications` ownership 证据。Application Cache、Logs、Temporary Files 不因展示需要被升级为 safe。
- Overview 使用轻量 Bundle ID 枚举避免为“App 数量”重复计算所有 App bundle 大小；扫描条目通过锁保护的同步收集器进入分类输入，避免每个条目产生不必要 actor hop。扫描、分类和 App 枚举均在异步任务中运行，不阻塞 SwiftUI 主线程。
- Dashboard 进入时幂等启动 Monitoring/Hardware stream，离开时取消 sampling/overview tasks；没有 kill、Trash、永久删除、系统控制、root helper 或 private API 路径。
- 视觉系统使用 SwiftUI 原生控件、语义颜色和 `Color(nsColor:)` 系统背景，支持 Light/Dark Mode 与可缩放窗口；不复制第三方清理产品 UI 或素材。

## Cleaner 完整 UI

- `CleanerViewModel` 是 `@MainActor` 的 App 层编排器；它只调用 `ScanEngine`、`ClassificationEngine` 和 `CleanupPlanner`，不直接调用 `SafeDeleteEngine` 或 `FileManager` 删除 API。
- Cleaner 默认使用四类内置 ScanTarget/ScanRule；扫描条目通过受锁保护的收集器交给 ClassificationEngine，实时进度可取消，页面离开会取消任务。
- 选择状态按候选路径保存：safe 默认选中但可取消，reviewRequired 只有明确选择才进入计划，protected/unknown 的 Toggle 禁用。CleanupPlanner 在显式选择阶段也会拒绝取消选择的 safe 项。
- 执行状态严格依次为 `plan → dryRun → confirmation → preflight → execute → audit`；UI 只展示 Core 返回的计划、拒绝原因、Preflight、执行结果和 reclaimed bytes。
- 第一版执行方法固定为 Trash；受控 UI E2E 通过 `--lexcleaner-controlled-fixture` 创建临时真实文件，仅用于验证完整链路，不改变生产扫描范围。

## App Manager 完整 UI

- `AppManagerViewModel` 只从 `AppManager` 获取真实 inventory/residual 数据；搜索和排序在内存中进行，不创建 Mock 候选。
- App 本体与 residual 分开显示。应用本体由 `InstalledApp.appBundleCleanupCandidate` 表达为 reviewRequired，并由 `CleanerRuleScope.installedAppBundle` 仅允许精确 bundle 路径；residual 使用 `CleanerRuleScope.appResidual` 仅允许精确关联路径。
- 两类目标都只能进入既有 `CleanupPlanner`，经 Dry Run、明确确认、Preflight、SafeDeleteEngine 的 `.trash` 模式和 Audit；`SafeDeletePolicy` 对 `/Applications` 的保护只对显式传入的单个无 symlink App bundle 建立窄例外，其他系统路径和个人数据保护不变。
- UI 只允许选择 reviewRequired；shared/protected/unknown、symlink、身份变化和 sourceChanged 由 Core 拒绝。受控 UI E2E 使用 `--lexcleaner-app-manager-fixture` 临时 App，不触碰真实重要应用。

## Disk Analyzer 完整 UI

- `DiskAnalyzerViewModel` 是 `@MainActor` 的 UI 生命周期协调器；`DiskAnalysisEngine` 仍是只读 Core，不依赖 SwiftUI，也不接收任何删除命令。
- 默认扫描当前用户 Home，所有目标仍通过 Core 的 `allowedRoots`、canonical、symlink 和权限边界；卷总容量/已用/可用来自 macOS URL resource values，不把卷统计混入扫描结果。
- 增量更新通过锁保护的受限实时投影交付给 UI：目录节点和 Top-N 大文件在扫描中可见，完成快照由 Core 作为唯一权威结果，避免轮询时重复复制完整字典。取消会取消任务并丢弃不完整的实时投影。
- Treemap 仅消费 `TreemapNode` 并在 App 层执行 slice-and-dice 布局；点击目录只改变当前查看路径。大文件列表支持搜索、类型筛选和大小/修改时间/名称排序，但不产生垃圾或可清理语义。
- 文件类型统计由 Core 依据扩展名归类，只用于空间分析展示；不会传给 Classification、CleanupPlanner 或 SafeDeleteEngine。页面没有删除按钮、Trash 调用、永久删除、root helper 或系统写操作。
- 当前默认扫描 Home 在真实 Mac 上出现远高于 50k fixture 的 RSS 峰值，属于待优化的真实性能风险；Mole 仅完成 Cache 同范围对照，Home 同范围基线因无输出而未形成。

### Disk Analyzer UI 性能收口记录

- Profile 结果显示完成态重复保存 `DiskNode` 全量 Treemap 投影会放大 RSS；`DiskAnalysisSnapshot.treemapNodes` 现在由 `tree.nodes + largeFiles` 派生，UI 只保留当前目录的一层 `TreemapNode`。
- 扫描中的 UI 投影只保留根目录可见聚合节点、Top-N 大文件和有限 issue；进度/投影统一约 0.75 秒节流，避免 SwiftUI/Accessibility 图每 150ms 重建。
- Core 目录遍历使用公共 Darwin `opendir/readdir` 单项流式读取；每个条目继续执行 `lstat`、`realpath`、allowed-root、symlink 和 canonical duplicate 检查。`maxDirectoryEntriesBuffered` 在真实 50k fixture 中为 1。
- 真实 Home 当前仍可能在用户目录中的特殊/超大目录 `opendir` 长时间阻塞；该状态必须显示扫描中或允许取消，不能当作完成快照。Cache scope 验证参数仅用于测试 Treemap 闭环，不改变生产默认 Home 范围。

### getattrlistbulk 与懒加载重构

- 目录枚举改用 macOS SDK 公开的 `getattrlistbulk`，以 64 KiB 可复用 buffer 分批取得名称、对象类型、修改时间、device/inode、逻辑大小、分配大小和 link count；真实目录在 canonical 父目录下使用相对拼接，symlink/非目录仍执行 `realpath`，并保留全部 allowed-root/权限检查。
- 普通文件不再逐项 `realpath`；canonical path 由已 canonical 的父目录加批量返回名称构成。目录和 symlink 仍必须 `realpath`，没有放宽越界保护。
- 扫描持久化结构只保留每个 target 的根和一级可视目录聚合；深层目录由 UI 点击后重新只读分析目标子树，支持懒加载、返回和取消，不把完整文件树交给 SwiftUI。
- Treemap 使用一级聚合、Top-N 大文件和 `Others` 节点；普通文件不进入持久化树。logical size 与 filesystem-reported allocated size 分离；只有 `nlink > 1` 的对象进入精确 device+inode 去重集合。
- Home issue 只保留前 1,024 条样本并记录 suppressed count，避免重复问题导致 UI RSS 无界增长；单目录 `open` 使用共享 100ms watchdog，超时记录 `enumerationFailed` 并跳过，不能把未扫描内容伪装为已扫描。watchdog 只使用公开 GCD/Darwin 能力，不修改系统状态。

### 性能收口修正

- 普通文件在 canonical 父目录下不再逐项构造 normalized/canonical URL；getattrlistbulk 已提供对象类型和 compact metadata，普通文件只以 basename 进入流式聚合。大文件路径和 canonical URL 仅在命中筛选、需要 issue 或进入结果时创建。
- 目录使用已 canonical 的父路径进行相对 canonical 拼接，symlink/非目录仍执行 realpath；两者都保留 allowed-root 和 symlink-leaf 检查。目录打开仍由独立 GCD blocking queue + watchdog 执行，避免慢目录占满 Swift Concurrency cooperative executor。
- 扫描完成后释放目录队列的 pending/seen transient state；UI live collector 仅保留根级可视聚合、Top-N 大文件和有限 issue，不保留百万级文件明细。
- 最新 Home Core 实测 12.459 s / 72.5 MB peak RSS；Caches 独立进程 0.37–0.42 s / 20.3–20.5 MB peak RSS。Swift 进程基线本身约 21.8 MB，故 14.7 MB RSS 目标对当前 SwiftPM runner 不可达，仍须以实测结果标记 FAIL。

### 容量口径与 volume 边界

- `DiskAnalysisSnapshot.totalBytes` 表示 logical `st_size` 累计；`allocatedBytes` 表示去除 hard link 后的 filesystem-reported allocation。两者不得在 UI 中混用。
- `TreemapNode`、`DiskNode`、`LargeFileEntry` 和内容统计同时携带 logical/allocated；Treemap 默认按 allocated 排序和布局，UI 同时展示 logical 参考值。
- 扫描入口记录 volume device/capacity，默认不跨 volume；跨 volume target/entry 记录 `volumeBoundary` 并跳过。allocated snapshot 以 volume capacity fail-safe bounded。
- 当前 APFS 公共 API 无法可靠将 clone/shared extents 的唯一物理占用归属到单个文件，因此 allocation status 明确为 `filesystemReportedSharedExtentsUnknown`，不伪造精确值。
- 真实 Home 校验：logical 约 600.55 GB、allocated 约 121.77 GB；验证使用 `$HOME`，结果为 121,771,278,336 bytes，APFS container/`df` 容量约 494.38 GB。

### 性能收口边界

- Time Profiler 证明主要热点为目录打开调度、普通目录重复 `realpath` 和 Swift 聚合/路径对象分配；普通目录现使用 canonical parent + relative basename，symlink 与非目录安全路径保持 canonicalization。
- 目录打开使用独立阻塞队列和共享 watchdog registry；晚到的 FD 会被关闭，超时条目只记录 issue，不把部分结果伪装为完整结果。
- 同机 Release Caches warm：LexCleaner 约 0.199–0.202 s / 13.8–14.1 MiB peak RSS；Mole 约 0.18 s / 14.7 MiB。RSS 已低于 Mole，但速度仍未达到严格 `<0.18 s`。
- Home Core Release：9.03 s / 43.5 MiB peak RSS / 960,377 files / 147,022 directories；allocated 约 121.78 GB，仍与 du/volume 口径一致。
- SwiftUI Home 最新真实启动 15 秒内仍未完成扫描，峰值 RSS 约 238.6 MB；该指标仍高于 ≤150 MB 目标，因此 Disk Analyzer UI 继续 FAIL。

### Disk Analyzer 最后性能攻坚最终口径（2026-08-23）

- Caches benchmark 使用与 App 相同的 bounded concurrency=3；Mole 仅提供聚合 JSON，不能据此推导纯 traversal 等价结果。
- Disk 页面现在按需拥有 `DiskAnalyzerViewModel`；离开页面时不再由 AppShell 保持扫描上下文。完成投影后 allocator page relief 在后台执行，避免把释放动作放进主线程。
- 当前性能结论：LexCleaner Caches 0.196669 s median / 13.42 MiB RSS，Mole 0.103400 s / 14.03 MiB；本轮统计分别为 LexCleaner 18,606 项、Mole JSON 16,888 files，范围差异已明确记录。Home Core 8.966 s / 27.8 MiB，Home SwiftUI 观察范围 149.89–151.22 MiB。安全与 allocated-size 口径不变，尚未形成超越 Mole 的完整优势。

### Disk Analyzer 同口径与并发策略（2026-08-23）

- `DiskAnalysisConfiguration` 支持显式 scope filter；production 默认扫描 symlink 与 `.git`，只有 equal-scope benchmark 显式排除它们。配置增加向后兼容解码，旧配置缺失新字段时回到完整扫描默认值。
- M4/APFS benchmark 对 1/2/3/4/6 并发实测后，adaptive policy 使用不超过 4 的 bounded worker 上限；6 的吞吐下降且 RSS 上升。队列仍是中心化 bounded work queue，identity 使用完整 device+inode，不使用近似去重。
- 目录去重采用紧凑开放寻址表，减少 Home 扫描目录 identity 内存；Home UI 只接 bounded projection，Core snapshot 不进入 SwiftUI 状态。
- Equal-scope Homebrew：LexCleaner 0.043161 s / 12.60 MiB，Mole 0.095354 s / 11.95 MiB；Full-quality Caches：LexCleaner 0.130214 s / 14.28 MiB，Mole 0.106992 s / 14.02 MiB。因此只能报告 equal-scope 速度优势，不能宣布 full-quality 全面超过。

### 两阶段扫描与 UI 数据边界（2026-08-23）

- `DiskAnalysisUpdate.stage` 区分 `fastInventory` 和 `deepEnrichment`。前者是同一 `getattrlistbulk` 遍历过程中的 compact、bounded 当前层投影，后者以完整 `DiskAnalysisSnapshot` 作为最终权威结果。
- Fast Inventory 不拥有独立的缩小扫描范围，也不把部分结果交给删除链路；它只让 Treemap 先显示。后台继续执行原有 symlink、volume、permission、identity、hard-link、watchdog、cancellation 和 allocated-size 逻辑。
- `DiskAnalyzerViewModel` 首先只接收 root-level 目录聚合、Top-N 大文件和有限 issue 样本；扫描结束后只发布 `DiskCompletedProjection`，不把完整文件树或 Core snapshot 放入 SwiftUI 状态。
- 两阶段完成时间与 Full-quality 结果必须分别测量。当前首个投影明显早于完整结果，但 Full-quality median 尚未低于 Mole，因此 Disk Analyzer 仍为 FAIL；此阶段不改变容量展示和 Treemap allocated-size 口径。

## Friends Beta 诊断与反馈

- `DiagnosticsReportBuilder` 位于 `LexCleanerCore`，只接收明确的值类型快照并生成文本；输出经过路径、文件名、用户名和凭据模式脱敏，不读取或输出用户文件内容。
- `DiagnosticsStore` 位于 App 层，默认只保留有界的最近错误摘要；报告、复制和反馈页面都必须由用户主动触发。崩溃信息只读取当前 App 相关 DiagnosticReports 的数量和最新时间，不输出报告文件名或路径。
- Settings 提供导出文本、复制诊断信息和打开 GitHub Issues 三个入口。反馈 URL 只附带 App version/build 和通用模板，不自动上传诊断报告；用户可自行粘贴已复制的报告。
- 诊断能力不依赖、也不修改 SafeDelete、Scan、Classification、Cleanup、Monitoring、Hardware、Disk 或 Network 的算法与安全边界。
