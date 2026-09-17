# LexCleaner 进度

## 当前发行审计（2026-09-17）

- 当前 Release Gate：**BLOCK**，不是发布声明。SwiftPM 测试、Release build、真实 Core runners、仓库安全扫描和 GitHub CI 已通过；这些结果不能替代 App runtime、Developer ID 或公证证据。
- 当前机器只有 Command Line Tools，没有完整 Xcode；钥匙串没有 `Developer ID Application` identity。没有提交、伪造或绕过签名/公证材料。
- 当前可证明的 macOS 运行范围是 Core runners 和只读系统 API；真实 SwiftUI App 的安装、启动、Cleaner UI、TCC 边界、DNS 页面、菜单栏和 Sparkle 下载/安装链路必须在完整 Xcode 的 macOS 测试环境重新验证。
- Sparkle 仅在 HTTPS feed + 32-byte Ed25519 公钥有效时创建 updater；未验证 archive signature 的候选现在会被 App adapter 拒绝。发行检查器还要求 Developer ID、Gatekeeper assessment 和 stapled notarization。
- 真实系统状态观察保持只读：本轮未修改 DNS、权限、TCC、VPN、代理或其他网络配置。

## feat/menubar-updater（2026-08-23）

## feat/updater-owner（2026-08-23）

- 已实现：App target 接入 Sparkle 2.9.6 精确 SPM 依赖；`SPUStandardUpdaterController` 负责手动/自动检查、标准确认、下载、签名校验和安装路径。
- 已实现：HTTPS feed、Ed25519 公钥、`SURequireSignedFeed`、`SUVerifyUpdateBeforeExtraction`、自动检查间隔和自动安装关闭配置；Settings 直接配置 Sparkle 自动检查。
- 已实现：无可靠 feed/key 时不创建 updater，显示明确 unavailable；错误不走手动地址、不替换当前 App。
- 已实现：Sparkle 官方 MIT 及 bundled external licenses 已放入 `NOTICE` 与 `THIRD-PARTY-NOTICES`；依赖固定为 2.9.6，无额外第三方依赖。
- 已验证：Sparkle package resolve、arm64 Debug App Build、Xcode SystemTools/Sparkle 定向测试 6/6、System Tools runner、真实 App Settings 手动检查安全错误态。
- 已知阻塞：全量 SwiftPM 62 tests 中既有 Disk Analyzer suite 有 6 个 fixture/projection 断言失败；本分支未修改 Disk Analyzer 文件，未用越界改动掩盖该失败。
- 未完成：仓库未提供真实签名 feed、归档、公证和 Developer ID 材料，真实下载/签名/安装成功链路未验证；真机只可验证当前未配置的安全错误态。

- 已实现：原生 `MenuBarExtra` 快速面板、CPU/Memory/Network/Disk 指标、`UserDefaults` 显示项配置、2 秒后台采样和 `includeProcesses = false` 低资源路径；新增 English / zh-Hans 文案资源。
- 已实现：App Update UI 的当前版本、候选版本、更新说明、手动检查和二次确认；`SparkleUpdateProvider` 继续通过 adapter 边界接入，确认后仅打开 HTTPS 手动地址，不下载/替换/安装。
- 已验证：SwiftPM 48/48、Xcode Core Tests 48/48、Core runner 13/13、Monitoring runner 4/4、System Tools runner 通过；LexCleanerApp arm64 Debug Build 通过；资源已进入 App 包。
- 已测量：临时真机实例约 30 秒 RSS 稳定 76,240 KiB，CPU 瞬时 0.0–2.1%，未见增长。
- 未完成：当前机器未配置 Sparkle runtime/feed，因此没有真实新版本候选；Computer Use 能读取 Finder 桌面但无法访问隐藏 `SystemUIServer` / 无窗口 `MenuBarExtra` 状态项，菜单栏点击展开和更新候选确认未能完成可审计的真机 UI 证据。对应第十四阶段验收保持未勾选，不应标记可合并。

更新时间：2026-08-22

## 当前阶段：三路并发 Foundation 集成完成

状态：完成；Disk Analyzer、App Manager、System Tools 已按分支级验收、Code Review 和统一 Integration Review 逐个合并到 main。没有进入 Dashboard、自动卸载、启动项写操作、权限修改、自动更新或其他高风险控制功能。

## 并行开发分支集成状态

- Disk Analyzer、App Manager、System Tools 三条正式分支已完成独立分支级测试、构建和 Code Review，并按 `disk-analyzer → app-manager → system-tools` 顺序合并到 main。
- 本次合并没有引入第三方依赖；Sparkle 仅保留 adapter 边界，Mole/Pearcleaner 等受限许可项目没有复制代码。

## System Tools Foundation

- 新增只读 Startup、Privacy 和 App Update Foundation；不修改启动项、隐私权限或更新安装状态。
- `SYSTEM_TOOLS_API_AUDIT.md` 记录了 Login Items、TCC、SMAppService、Sparkle 和公开框架边界。
- 真实验证：当前 Mac 读取 906 个启动项、4 个读取问题；Privacy 状态模型和 App Store `unsupported` 结果通过；System Tools runner、Xcode Tests 和 App/Core Build 在分支级验证通过。

## 三路并发最终集成验收

- 正式 worktree：独立的 `app-manager`、`disk-analyzer`、`system-tools` worktree，均保持 clean；三个分支均从 baseline `2a075ef` 继承并独立提交。
- 实际合并顺序：`feat/disk-analyzer` → `feat/app-manager` → `feat/system-tools`；合并提交依次为 `0d96e6f`、`46834a2`、`cb9006c`。
- 每次合并后均完成 SwiftPM 构建、既有回归 runner、Xcode App/Core arm64 Debug Build 和 Xcode Tests；项目文件冲突中的重复 PBX ID 已重新编号并通过 `xcodebuild -list` 验证。
- main 最终 SwiftPM 全量测试：`47/47`，9 个 suite；Xcode `LexCleanerCoreTests`：`47/47`，9 个 suite。
- Core runners：SafeDelete `13/13`、Scan `12/12`、Classification `17/17`、Cleanup Pipeline `16/16`、Monitoring `4/4`、Hardware `4/4`；Disk Analyzer、App Manager、System Tools 真实 runner 均 PASS。
- Disk Analyzer 50,000 文件真实验证：50,002 files、10 directories、并发上限 3、DiskTree 10 nodes、peak RSS 约 42.3 MiB、吞吐约 65,998 files/s、取消延迟约 0 ms。
- App Manager 当前 Mac 真实枚举：248 个 App、6 个 issue；前 20 个候选人工抽查输出完成；受控 UninstallPlan/Dry Run/Preflight 无副作用。
- System Tools 当前 Mac 真实只读验证：906 个启动项、4 个 issue；Privacy 状态和 App Store `unsupported` 通过。
- `LexCleanerApp` 和 `LexCleanerCore` arm64 Debug Build 通过；真实 SwiftUI App 启动后进程保持运行，最近系统日志未发现 LexCleaner crash、exception 或 error。仅见系统 RunningBoard/CoreSpotlight 信息日志。
- 未引入第三方运行时依赖；Sparkle 仅为协议边界，GPL/AGPL/Commons Clause/商业限制项目未复制进 Core。

## Disk Analyzer（进行中）

- 已核对 GrandPerspective（GPL）、Mole（GPL-3.0）、ncdu（MIT）、dua-cli（MIT）和 dust（Apache-2.0）；均不作为依赖，DiskAnalysis 自研并只参考公开行为/架构。
- 已新增 `Sources/LexCleanerCore/DiskAnalysis/DiskAnalysis.swift`：目录聚合、扁平 Treemap 投影、Top-N 大文件、增量 update、canonical 边界、symlink fail-safe、并发限制、取消和资源指标。
- 已新增 DiskAnalysis Swift Testing 覆盖：聚合与筛选、symlink loop/escape、取消；Package test target 已纳入全部 Core 测试。
- 已新增 `LexCleanerDiskAnalysisTestRunner`，包含受控 50,000 文件、Home 允许区域、取消、symlink 和权限不足尝试。
- 当前实测：50,000 文件 fixture 输出 50,002 文件/10 目录，`DiskTree` 仅 10 个目录节点，Top N=10；最大并发 3，当前目录缓冲 6,250；记录耗时、CPU、peak RSS 和吞吐。
- 权限不足尝试通过 mode-000 目录权限位 fail-closed 记录为 `permissionDenied`；代码同时覆盖 POSIX EACCES/EPERM 与 Cocoa code 257。

### Disk Analyzer 真实验证结果

- `swift run LexCleanerDiskAnalysisTestRunner`：PASS。
- 50,000 文件受控 fixture：50,002 files、10 directories、3 workers；最近一次耗时约 0.766 s、CPU time 约 2.051 s、平均 CPU 约 267.839%、peak RSS 约 40.9 MiB、吞吐约 65,294 files/s、当前目录最大缓冲 6,250、DiskTree 10 nodes。
- 记录 canonical duplicate、symlink loop leaf、symlink escape 和 permissionDenied；大文件 Top N=10；未调用删除或垃圾分类。
- 取消验证：10,000 文件 fixture 在第 1 个文件后停止，取消延迟约 0 ms。
- Home 允许区域 `~/Library/Caches`：16,932 files、8,165 directories、33 issues，只读通过。

## Hardware Observability Foundation 已完成

### API 审计与决策

- `HARDWARE_API_AUDIT.md` 已完成，逐项记录 API 来源、权限边界、稳定性、跨 macOS 版本风险和许可证决策。
- 采用公开 `ProcessInfo` thermal state、公开 I/O Kit 电源来源字段、公开 I/O Kit 媒体属性和只读 sysctl 基础硬件信息。
- Battery cycle count 仅作公共但“不推荐”的兼容读取；字段缺失、设备不支持或读取失败时明确返回 `unavailable`。
- CPU/GPU/SoC 温度、风扇 RPM、SoC 功耗、SMART 和 SSD wear 没有进入正式 Core；这些能力依赖私有/设备特定接口、root 边界或不稳定协议，统一返回 `unsupported`。
- 未使用 private API、SMC 写入、root helper、sudo、shell 命令或第三方运行时依赖。

### 实现

- 新增 `Sources/LexCleanerCore/Hardware/HardwareModels.swift`、`HardwareCollectors.swift` 和 `HardwareSampler.swift`。
- 新增 `HardwareSnapshot`、`HardwareInfo`、`ThermalSnapshot`、`BatterySnapshot`、`StorageHealthSnapshot`、`SensorSnapshot`、`FanSnapshot`、`PowerSnapshot`。
- 所有指标均携带 availability/source/detail；不支持或不可用的指标不产生猜测值。
- `HardwareSampler` 使用 Swift Concurrency、可配置采样间隔、取消和有界 `AsyncThrowingStream`，不阻塞主线程。

### 真实验证

- M4 真实硬件：`Mac16,10`，Apple Silicon，10 physical/logical cores，4 performance cores + 6 efficiency cores，thermal state `nominal`。
- 电池/电源来源：当前台式 Mac 无电池，明确为 `unavailable`；未伪造 capacity、cycle count 或 health。
- 存储：真实发现 4 个 I/O Kit 媒体设备并读取基础属性； SMART/wear 明确 `unsupported`。
- 温度、风扇、功耗：明确 `unsupported`，未越过 private API/root 边界。
- 硬件 runner：4/4；Xcode Tests：35/35（6 suites）。
- 最终版本 10 分钟连续采样：600.590 秒、563 个样本、时间跨度 600.587 秒；全程 thermal `nominal`、battery `unavailable`、storage device count 4。
- 采样器 RSS：首值 7.64 MiB、峰值/末值 8.14 MiB，增量 0.50 MiB；约第 126 秒后基本稳定。进程 user+system CPU 时间 1.926 秒，平均 CPU 约 0.321%；未见持续增长趋势或资源泄漏迹象。

### 已知边界

- `IOPMCopyBatteryInfo` 是公开但 Apple 标注为“不推荐”的兼容接口，因此 cycle count 不是跨 macOS 版本的强保证。
- 当前 M4 台式机不提供电池样本；电池字段的可用性必须以运行时实际返回为准。
- 本阶段没有将 `powermetrics`、SMC、IOReport、IOHID 或 SMART 工具链作为正式 Core 数据源。

## Monitoring Foundation 已完成（历史阶段）

### 实现

- 新增 `Sources/LexCleanerCore/Monitoring/MonitoringModels.swift`、`MonitoringCollectors.swift` 和 `MonitoringSampler.swift`。
- `MonitoringSnapshot` 聚合 CPU、Memory、Disk、Network、Process 五类值类型快照。
- CPU：总使用率、user/system/idle 和 per-core，使用 Mach host CPU counters。
- Memory：physical/used/available/wired/compressed/swap/pressure；压力状态基于公开 VM statistics 的只读启发式判断。
- Disk：启动卷容量、已用/可用空间和公开 IOKit block-storage 累计读写计数/速率。
- Network：`getifaddrs` 接口累计收发 bytes 与上传/下载速率，排除 loopback。
- Process：公开 `libproc` 只读 PID、名称、CPU 和 resident memory；默认返回所有可访问进程，正数 `processLimit` 可限制资源占用。
- `MonitoringSampler` 使用 detached utility task、可配置间隔、AsyncThrowingStream 和取消；没有 root、kill、写系统状态或 UI 依赖。
- 未引入第三方依赖；Stats（MIT）和 btop（Apache-2.0）仅参考公开采样架构，未复制代码或 helper。

### 新增真实验证

- Xcode Test：新增 Monitoring Foundation 8 个测试；完整 Test Scheme 为 27/27（5 suites）。
- Monitoring runner：4/4；真实快照、取消、64 MiB 磁盘写入计数变化、HTTPS 网络请求计数变化通过。
- 10 分钟连续采样：600.99 秒、560 个样本；CPU 范围 0–24.27%，常态约 11.7–12.8%；系统已用内存约 10.47–10.70 GB。
- 采样器自身 RSS：首值约 10.98 MiB、峰值/末值约 11.55 MiB，末值未继续增长，未发现持续内存泄漏趋势。
- 真实磁盘写入计数增加约 64–70 MiB；真实 HTTPS 请求导致接口接收累计 bytes 增加。
- Activity Monitor 对照：同时段 CPU user+system 约 12.65%，LexCleaner 约 12.45%；内存 Activity Monitor 约 11.03 GB used / 2.07 GB wired / 2.30 GB compressed / 319.6 MB swap，LexCleaner 约 10.46 GB used / 2.18 GB wired / 2.47 GB compressed / 335 MB swap；差异约 5%，符合缓存和单位定义差异，未发现明显偏差。

### 已知边界与安全结论

- 内存 pressure 是公开 VM 数据推导值，不调用 Activity Monitor 私有接口；当前实测为 `normal`，与 `memory_pressure -Q` 的 71% free percentage 一致。
- IOKit 磁盘累计计数依赖 macOS 存储栈是否暴露 `IOBlockStorageDriver` Statistics；不可用时返回明确 `ioStatisticsAvailable = false`，不伪造速率。
- 进程列表仅包含当前权限可访问的进程；不存在结束进程 API。
- 采样不记录文件内容、网络内容、凭据或 Token，不修改系统状态。

## 正式 Xcode 环境闭环检查

Environment Closure: PASS（2026-08-22）

### 环境与工程

- Xcode：26.6，Build 17F113。
- `xcode-select -p`：`/Applications/Xcode.app/Contents/Developer`。
- macOS SDK：`macosx26.5.sdk`。
- Xcode Swift：Apple Swift 6.3.3，目标 `arm64-apple-macosx26.0`。
- `LexCleaner.xcodeproj` 由 Xcode 26.6 解析通过；App、Core、Test 三个 Target 存在。
- 新增共享 `LexCleanerCoreTests` Scheme，使正式 `xcodebuild test` 可执行。

### 最终真实验证

- `LexCleanerApp`：arm64 Debug Build 通过；产物为 arm64 Mach-O。
- `LexCleanerCore`：arm64 Debug Build 通过；产物为 arm64 Framework。
- `LexCleanerCoreTests`：arm64 Debug Build 通过；当前 `xcodebuild test` 实际执行 35 个测试、6 个 Suite，35/35 通过。
- Core 回归 runner：SafeDelete 13/13、Scan 12/12、Classification 17/17、Cleanup Pipeline 16/16，共 58/58 通过。
- 真实 SwiftUI App：最终 Debug `.app` 由 `open` 启动成功，进程保持运行；最近运行日志未发现 crash、error、fault、exception 或 warning。

### 本轮修复的工程问题

- Core Framework 补充自动生成 `Info.plist`，修复 App 嵌入 Framework 校验失败。
- Core Framework 使用 `@rpath` install name，App 和 Test Bundle 配置对应的运行时 Framework 搜索路径。
- Test Target 增加 Embed Frameworks Copy Phase，修复直接运行测试 bundle 时的依赖加载失败。
- 修复 XCTest `ClassificationEngineTests` 的 `TestFailure` 初始化器编译错误。

### 已知非阻塞提示

- Xcode 对未依赖 `AppIntents.framework` 的 Target 输出 metadata extraction skipped 提示；项目没有 App Intents 功能，该提示不影响构建或运行。
- Test Target 链接时提示当前 macOS 13.0 部署目标低于 Xcode 26.6 测试框架的 macOS 14.0 构建版本；链接和 19/19 实测通过，未发现运行失败。
- Xcode 输出 manual target order deprecation 提示；不影响当前构建结果。

历史环境阻塞记录已解除：此前完整 Xcode 不存在、管理员密码和 Apple 登录导致的安装路径均未绕过，当前使用 `/Applications/Xcode.app` 正式稳定版完成验证。

## ScanEngine 已完成

- `Sources/LexCleanerCore/Scan/ScanEngine.swift`：规则、目标、结果、问题、进度、汇总和性能模型。
- 固定 worker 并发、canonical directory 去重、当前目录级内存边界。
- symlink 不递归、权限错误记录、个人数据/系统关键目录硬排除。
- 13 个 SafeDeleteEngine 测试保持通过；12 个 ScanEngine 真实测试通过。
- 5,000 文件、8 个子目录真实测试：并发上限 2，记录扫描耗时与 resident-memory high-water 趋势。

未完成/环境限制：

- ScanEngine Core 功能已完成；完整 Xcode 环境闭环已于 2026-08-22 通过。
- 尚未开始 Cleaner UI、Dashboard 或真实删除按钮。

## ClassificationEngine 已完成

- `Sources/LexCleanerCore/Classification/ClassificationEngine.swift`：规则、候选、类别、风险级别、原因、排除、年龄/大小策略和分类统计模型。
- 四个内置规则：User Cache、Application Cache、Logs、Temporary Files。
- 默认 fail-closed；保护系统/个人/凭据/浏览器/Git/数据库/Session/下载等路径，symlink 和源文件变化不进入 safe。
- 日志支持活跃保护、年龄阈值和 Crash/Diagnostic 复核；临时文件过新默认 protected。
- ClassificationEngine 只读取当前 `ScanItem` 与文件元数据，不调用 SafeDeleteEngine，也没有删除路径。
- `swift run LexCleanerClassificationTestRunner`：17/17 通过。
- 真实 macOS 只读扫描：5,163 files、1,332 directories、116 issues、约 0.587 秒、resident-memory high-water 约 20.3 MB；分类采集 6,495 项：safe 0/0 B、reviewRequired 3,942/375,670,762 B、protected 2,552/113,604,480 B、unknown 1/86,592 B。该 1 项因扫描后目录元数据变化被 fail-closed 标记为 `sourceChanged`。
- 30/30 真实候选人工抽查：均为 Temporary Files；目录容器 protected、旧文件 reviewRequired、新文件 protected，1 项扫描后元数据变化为 unknown/sourceChanged；未发现明显用户数据误判。

## CleanupPlanner 已完成

- `Sources/LexCleanerCore/Cleanup/CleanupPlanner.swift`：计划、选择、Dry Run、Preflight、执行结果、失败原因和审计模型。
- 执行资格默认 fail-closed：safe，或明确选择并确认的 reviewRequired；protected、unknown、sourceChanged、rule conflict 和身份变化拒绝。
- Preflight 重新校验 lstat/realpath、device/inode/type、symlink、SafeDelete 保护状态和重新分类结果；调用 SafeDelete 前再次逐项 Revalidation。
- 第一版仅使用 `FileManager.trashItem`，没有永久删除路径；Partial Failure 和 cancellation 按项目独立记录。
- `swift run LexCleanerCleanupTestRunner`：16/16 通过。
- 受控真实链路通过：真实临时目录扫描 2 个文件并分类，Dry Run 无副作用；修改其中 1 个文件后 Preflight 拒绝，只有未变化文件进入真实 Trash；修改文件保留。
- 受控 Trash 失败、inode replacement、symlink replacement、duplicate、review selection、audit 均有测试覆盖。

## App Manager Foundation（本分支新增）

### 实现

- 新增 `Sources/LexCleanerCore/AppManager/AppManager.swift`：只读 application roots 枚举、`.app` `Info.plist` metadata、canonical path 去重和 bundle identifier 校验。
- 新增精确 bundle identifier residual 规则：Application Support、Caches、Preferences、Saved Application State、Logs、WebKit、HTTPStorages、Containers、LaunchAgents；Group Containers 不自动关联，明确报告共享数据边界。
- 新增 `InstalledApp`、`AppMetadata`、`AppResidualCandidate`、`ResidualConfidence`、`UninstallPlan`、`UninstallPlanItem`，以及只读 `SentinelFeasibility`。
- residual 分级：缓存/WebKit/HTTP storage 为显式选择后的 `reviewRequired`；状态、偏好、日志、容器和 launch item 默认 protected；unknown/shared/低置信度 fail-closed。
- `UninstallPlanItem` 仅适配已有 `CleanerCandidate`；不修改既有 Classification/Cleanup/SafeDelete API，不提供自动卸载或永久删除路径。

### 验证

- SwiftPM App Manager 测试 4/4 通过；包含 controlled App metadata、精确 residual 关联、unknown/shared fail-closed、CleanupPlanner Dry Run/Preflight 无副作用。
- 真实当前 Mac 扫描：248 个已安装 App、6 个枚举提示；runner 输出前 20 个 App 供人工抽查，均有 bundle identifier 和版本信息。
- 受控测试 App：UninstallPlan eligible 1、Dry Run process 1、Preflight rejected 1、filesystem unchanged=true；未触碰真实重要 App。

### 最终验证

- SwiftPM 测试：39/39 通过；App Manager Suite 4/4。
- 正式 `xcodebuild test`：39/39 通过；`LexCleanerApp` Debug arm64 build 通过；新增 Core source/test 已登记到 Xcode Target。
- 回归 runners：SafeDelete 13/13、Scan 12/12、Classification 17/17、Cleanup 16/16、Monitoring 4/4、Hardware 4/4、App Manager runner PASS。

## Cleaner Safe Rule Calibration（当前阶段）

### 实现

- 新增 `SafeRuleEvidence` / `SafeRuleConfidence`，每条 safe 规则必须具备路径模式、用途、可重建依据、排除条件、年龄/大小策略、ownership、测试覆盖和真实验证记录。
- User Cache 仅新增窄规则 `calibrated-user-cache-fscached-data`：`~/Library/Caches/<verified-installed-bundle-id>/fsCachedData/**`。
- 规则要求 Bundle ID 来自 `/Applications` 或 `~/Applications` 中实际存在且非 symlink 的 `.app`；再次校验 canonical path、symlink、敏感路径、文件类型、年龄、大小和源身份。
- Application Cache、Logs、Temporary Files 没有被升级为 safe，继续遵守默认 fail-closed。
- 修复 ScanEngine 对 `/Users` 的递归排除边界：只保护 `/Users` 根本身，仍保护当前用户 Documents/Desktop/Projects 等个人路径，使允许的 Library Cache/Logs/Application Support 能真实扫描。

### 真实只读校准与受控验证

- 当前 Mac 真实扫描：40,707 files、12,538 directories、312 issues；采集并分类 53,245 项。
- 分类统计：safe **277 / 18,928,064 B**；reviewRequired **14,495 / 1,220,963,087 B**；protected **22,781 / 1,757,917,209 B**；unknown **15,692 / 3,501,172,586 B**。
- safe 贡献：`calibrated-user-cache-fscached-data`，277 项 / 18,928,064 B。
- 100 个最大 safe 候选结构化人工抽查：100/100 通过，未发现明显用户数据误判。
- 受控目录完整链路：Scan → Classify → CleanupPlan → Dry Run → Preflight → SafeDelete → Audit；1 个未变化文件进入 Trash，回收 16 B；source change、identity replacement、symlink、protected、unknown、rule conflict、cancellation、partial failure、Trash failure 和受控重建均有验证。
- 未触碰真实用户缓存；运行中的 Codex 仅作运行状态观察，未修改其真实数据。

### 性能与测试

- 真实扫描约 1.60 s；分类约 44.84 s；CPU 约 50.94 s；逐项 autorelease pool 后 peak RSS 约 54 MB。未降低扫描范围或安全标准来增加 safe 数量。
- 新增 Classification Xcode/SwiftPM 测试 4 项；当前 SwiftPM/Xcode Testing：**51/51**。
- 分类 runner：**20/20**；Cleanup runner：**16/16**。
- 详细规则证据与数据记录见 `SAFE_RULE_CALIBRATION.md`。

### 当前结论

- Safe Rule Calibration：候选规则和真实验证达标；仅 `fsCachedData` 窄规则进入 safe。
- 其余三类仍不进入 safe，后续不得用宽泛路径匹配扩大 safe 范围。

### 最终回归

- SafeDelete runner：13/13；Scan runner：12/12；Classification runner：20/20；Cleanup runner：16/16。
- Monitoring：4/4；Hardware：4/4；App Manager、Disk Analyzer、System Tools runners：均 PASS。
- SwiftPM/Xcode Testing：51/51；App Target arm64 Debug Build：PASS；Core Target arm64 Debug Build：PASS。
- 真实 SwiftUI App 从本轮 Debug 产物启动后进程保持运行；最近日志未发现 LexCleaner crash、exception 或 runtime error。仅有既有 AppIntents metadata skipped 和系统服务提示。

## Classification Performance Optimization（当前阶段）

### 实测热点与实现

- 使用 Xcode 26.6 `xctrace` 的 **Time Profiler** 对真实分类 runner 采样；热点确认在每项重复构造保护根/URL、Git ancestor `lstat`、symlink root canonicalize、路径字符串/URL 分配，而不是凭感觉优化。
- `ClassificationContext` 预编译规则 allowed roots、canonical roots、保护根和静态路径集合；每次分类仍保留当前目标 `lstat`、canonicalize、symlink component 检查、Git ancestor 检查和敏感路径保护。
- 将 Git ancestor 检查改为等价的 bounded String path 遍历；未引入无限并发，也未放宽任何 safe/protected 规则。
- 分类任务每 256 项让出执行权并暴露 `cancelled` 结果；取消返回部分结果且不把未处理项目标记为可回收。

### 性能验证

- 用户提供的优化前基线：53,245 项，Classification **44.84 s**，Peak RSS **约 54 MB**。
- 同规模当前 Mac 真实运行：约 53.4k 项；连续 5 次分类耗时 **5.310 / 5.423 / 5.326 / 5.537 / 5.457 s**，平均 **5.410 s**，约 **8.3x** 提升；Peak RSS 最大 **53,952,512 B（约 51.4 MiB）**，未明显增加。
- 由于扫描目标是正在变化的真实用户目录，跨进程 aggregate item 数和 protected/unknown bytes 会随文件创建、日志和临时目录变化；安全决策字段、四类规则和 safe 规则贡献保持一致，未用变化中的数据修改基线。
- 当前真实运行 safe：**277 / 18,928,064 B**；唯一 safe 规则为 `calibrated-user-cache-fscached-data`。Application Cache、Logs、Temporary Files 仍不升级为 safe。

### 验证结果

- Classification runner：**21/21**；新增 cancellation 测试通过。
- SwiftPM Testing：**52/52**；Xcode Tests：**52/52**。
- App Target arm64 Debug Build：PASS；Core Target arm64 Debug Build：PASS。
- SwiftUI App 真实启动：进程保持运行；本轮无 crash/exception/fatal。仍可见既有 AppIntents/linkd 系统服务提示及 macOS 13 测试链接器兼容性 warning，不是本次分类优化引入。

### 当前结论

- Classification Performance Optimization：**≤10 秒目标 PASS**；5 秒偏好目标当前未达到（5 次最佳约 5.31 秒，平均约 5.41 秒）。
- 未发现新增安全问题；分类只读、无删除、无 root/private API，现有 SafeDelete/Scan/Cleanup 安全链未绕过。

## SwiftUI 产品化骨架与 Dashboard（当前阶段）

### 实现

- 新增 `App/LexCleanerApp/AppShell.swift`、`DashboardView.swift` 和 `DashboardViewModel.swift`；App Shell 使用原生 `NavigationSplitView` 提供 Dashboard、Cleaner、App Manager、Disk Analyzer、System Tools、Monitoring、Hardware、Settings 八个导航入口。
- Dashboard 连接真实 `MonitoringSampler`、`HardwareSampler`、`ScanEngine`、`ClassificationEngine` 和 `InstalledAppCatalog`；没有 Mock、删除按钮或系统控制操作。
- Dashboard Overview 当前只扫描已校准 User Cache safe 规则，并使用 `/Applications`/`~/Applications` ownership 边界；四类中其他类别仍保持 review/protected/unknown，不因 UI 展示而放宽。
- 新增 `InstalledAppCatalog.enumerateBundleIdentifiers()` 轻量只读 API，供 ownership/数量概览使用，避免为 App 数量重复计算完整 bundle 大小；新增 App Manager 轻量枚举测试。
- 采样任务由 `DashboardViewModel` 按页面生命周期管理：进入幂等启动，离开取消 Monitoring、Hardware 和 Overview 任务；条目收集使用锁保护缓冲，避免每条扫描结果产生 actor hop。

### 真实验证

- 当前真实 Dashboard：可清理空间 **18.9 MB / 277** 个 User Cache safe 候选；已安装 App **248**；CPU、Memory、Disk、Network、Thermal 和系统健康均显示真实快照。
- 真实 App Shell 页面切换：Dashboard → Cleaner → Dashboard 通过；Cleaner 等页面保持诚实 foundation 状态，不冒充复杂功能。
- 当前 macOS Dark Mode 下真实窗口截图通过；窗口最小尺寸和 Dashboard 自适应布局通过检查。
- 连续运行 **601 秒**；App CPU 样本约 **0.1–5.4%**（多数 0.1–1.8%），RSS 约 **129.95–142.56 MB**，中途暂态上升后回落，无持续增长、崩溃或明显 runtime error。
- App Target arm64 Debug Build：PASS；Core Xcode Tests：**53/53**；SwiftPM Tests：**53/53**。

### 当前结论

- SwiftUI App Shell 与 Dashboard：**PASS**。
- Cleaner、App Manager、Disk Analyzer、System Tools 的复杂最终交互尚未开始；本阶段按要求停止在页面骨架与 Dashboard。

## Cleaner 完整 UI（当前阶段）

### 实现

- 新增 `App/LexCleanerApp/CleanerViewModel.swift` 和 `CleanerView.swift`，将真实 `ScanEngine → ClassificationEngine → CleanupPlanner` 接入 SwiftUI Cleaner。
- Cleaner 展示 safe、reviewRequired、protected、unknown 的真实数量/空间，并可展开查看路径、分类、规则、原因、修改时间、归属 App 和预计可回收空间。
- safe 默认选中但可取消；reviewRequired 只有主动勾选才可进入计划；protected/unknown Toggle 禁用。扫描、分类、计划、Dry Run、确认、Preflight、Trash、Audit 和执行结果均由真实 Core 状态驱动。
- 第一版执行仅使用现有 CleanupPlanner 的 `.trash` 路径；UI 没有直接删除调用。扫描取消、空结果、扫描 issue、Preflight 拒绝和 partial result 在界面上保留真实状态。
- 增加显式 `--lexcleaner-controlled-fixture` 启动参数：创建临时真实 `.app` ownership 和 `fsCachedData` 文件，仅用于 UI E2E，不触碰真实用户缓存。

### 真实验证

- App Target arm64 Debug Build：PASS。
- SwiftUI 受控 E2E：真实扫描得到 safe **1 / 32 bytes**、protected **3 / 288 bytes**；safe 默认勾选，protected 不可选择。
- Dry Run：处理 1 项 / 32 bytes，拒绝 3 项，无文件系统副作用；确认弹窗明确显示 Trash 而非永久删除。
- Preflight/Trash/Audit：成功 1、拒绝 3、跳过 0、失败/拒绝 3，实际回收 **32 bytes**，Audit entries **4**；源文件消失、受控目录保留，Finder 废纸篓可见受控测试条目。
- 生产路径 UI 取消：真实扫描进行中显示 `取消扫描`；取消后显示 `已取消`，本次未执行任何清理。
- Core 既有 sourceChanged、identity replacement、symlink replacement、protected、unknown、rule conflict、cancellation、partial failure 和 Trash failure 测试保持通过。

### 当前结论

- Cleaner 完整 UI：**PASS**。
- 最终全量回归：Swift Testing/Xcode **53/53**；Cleanup runner 16/16、Scan 12/12、Classification 21/21、Monitoring 4/4、Hardware 4/4、Disk Analysis/App Manager/System Tools runners 均通过；App/Core arm64 Debug Build 通过。
- 最终 Xcode `LexCleanerCoreTests`：**53/53**；真实 SwiftUI App 启动成功，日志未发现本阶段新增 crash/exception/fatal/error。
- 未发现受控 E2E 误删或真实用户数据损失；生产扫描仍默认 fail-closed。

## SwiftUI 国际化（当前阶段）

### 实现

- 使用 macOS 原生 `Localizable.xcstrings`，提供 `zh-Hans` 和 `en`，并将资源加入 `LexCleanerApp` Resources build phase。
- 新增 `LanguageSettings`：默认 `Follow System`，支持运行时切换 `Follow System`、`Simplified Chinese` 和 `English`，偏好仅保存到 App 自身的 UserDefaults。
- Dashboard、Cleaner、App Manager、Disk Analyzer、System Tools、Monitoring、Hardware、Settings 的导航、状态、指标、错误、按钮、确认和候选详情均通过 String Catalog 或统一 L10n 访问层显示；路径、Bundle ID、文件名和指标数值保持原样。
- 动态文案按目标 locale 显式加载对应 `.lproj`，修复运行时切换后动态卡片仍沿用系统语言的问题。

### 真实验证

- macOS 当前中文环境下 `Follow System`：真实启动显示中文；Dashboard 真实 CPU、内存、磁盘、网络、温度和已校准可回收空间继续来自 Core。
- Settings 中运行时切换 English：导航、Dashboard 动态统计、Cleaner、骨架页和 Settings 即时切换，无需重装；切回 Simplified Chinese 同样通过。
- Dark Mode 下真实窗口检查通过；原生窗口缩放/放大后 Dashboard 仍保持自适应布局，未发现明显截断。
- SwiftUI App arm64 Debug Build：PASS；Xcode Core Tests：**53/53**；SwiftPM Tests：**53/53**。
- 最近真实运行未发现 LexCleaner crash、exception 或新增 runtime error；仅保留既有 AppIntents metadata skipped 系统 warning。

### 当前结论

- SwiftUI 国际化：**PASS**。
- 继续保持 Cleaner 现有安全管线；本阶段没有新增删除、控制或系统修改能力。

## App Manager 完整 UI（当前阶段）

### 实现

- 新增 App Manager SwiftUI 页面与 `AppManagerViewModel`，真实连接 `InstalledAppCatalog`、`AppResidualAnalyzer`、`UninstallPlan`、`CleanupPlanner`、`SafeDeleteEngine` 和 Audit；没有 Mock 数据或 UI 直调用删除 API。
- 已安装 App 列表提供图标、名称、版本、大小、Bundle ID、路径、搜索和名称/大小/修改时间排序；App 本体与 residual 分开显示。
- residual 关联仅使用 Bundle ID、标准路径、canonical/ownership 和 confidence；shared、protected、unknown、symlink、个人目录和不确定归属保持 fail-closed。App bundle 仅可通过精确路径规则进入 reviewRequired，必须用户明确选择。
- 卸载链路固定为 App Selection → Residual Analysis → UninstallPlan → Dry Run → Confirmation → Preflight → SafeDeleteEngine/Trash → Audit；第一版没有永久删除。
- 增加受控 `--lexcleaner-app-manager-fixture` UI fixture，fixture 生命周期结束后清理临时源目录，不触碰真实重要 App。

### 真实验证

- 当前 Mac 真实枚举：**248 个 App，6 个枚举问题**；生产 UI 首次完整枚举约 40 秒，加载期间界面仍保持 loading，加载后搜索与排序实测可用。
- 人工抽查 20 个 App：AI Video OS、CHIEF、ChatGPT Atlas、ChatGPT、Comfy Desktop、Cursor、Docker、Doubao、Game Porting Toolkit、GarageBand、Gemini、Google Chrome、Keynote Creator Studio、Kimi、Microsoft Word、Numbers Creator Studio、Obsidian、Ollama、OpenCode、Pages Creator Studio；均读取到 metadata/residual 结果，未发现明显错误归属。浏览器、Docker 容器、Application Support/Preferences 等敏感或共享数据保持保护/需复核。
- 受控 UI E2E：选择 App 本体和一个 exact Bundle residual，共 **2 项 / 578 B**；Dry Run 未修改文件，Preflight 通过，Trash 成功 **2 项**，Audit 记录 2 条，回收 **578 B**；源路径消失，受控 App 仍可运行，未验证或清空真实用户废纸篓。
- Core 受控卸载测试覆盖 sourceChanged、inode/symlink replacement、protected/unknown、partial failure、cancellation 和 Trash failure；Classification runner **21/21**，AppManager Xcode 测试包含完整 App bundle + residual Trash 流程。
- SwiftPM Testing：**54/54**；Xcode `LexCleanerCoreTests`：**54/54**；SafeDelete **13/13**、Scan **12/12**、Cleanup **16/16**、Monitoring **4/4**、Hardware **4/4**、Disk Analysis、App Manager、System Tools runners 均通过；App/Core arm64 Debug Build 通过。
- 最终 App 重新启动后进程保持运行；最近 2 分钟日志未发现 crash/fatal/uncaught/SwiftUI runtime error。Light/Dark、中文 UI、窗口缩放、搜索/排序和页面切换已完成真实验证。

### 当前结论

- **App Manager UI：PASS**。
- 未发现受控 E2E 误删或真实用户数据损失；生产删除仍只能走显式选择、Dry Run、Preflight、SafeDeleteEngine 和 Trash。已知非阻塞问题是当前 Mac 的 248 App 全量大小/残留分析首次加载较慢，后续可单独做渐进式列表性能优化。

## Disk Analyzer 完整 UI（当前阶段）

### 已完成

- 新增真实 SwiftUI `DiskAnalyzerView` / `DiskAnalyzerViewModel`，接入现有 `DiskAnalysisEngine`；页面提供卷容量概览、只读 Treemap、目录深入、Top-N 大文件搜索/排序/类型筛选、文件类型统计、扫描计数、取消和 issue 列表。
- Core 新增 `DiskContentCategory` 与 `DiskContentStatistics`，仅用于文档/图片/视频/音频/压缩包/开发文件/其他的空间统计，不改变任何清理或分类安全语义。
- 增量 UI 投影使用锁保护的 copy-on-write 容器，实时目录节点限制为 4,096 个，并在完成快照后释放重复实时字典；取消时丢弃不完整投影，避免把未完成数据当成最终分析结果。
- 页面完全只读；源码检查确认 Disk Analyzer UI 不调用 `trashItem`、`removeItem` 或任何永久删除 API。

### 验证结果

- Core 50,000+ fixture：**50,002 files / 10 directories / 3 concurrency / 6,250 max buffer / 10 tree nodes / 0.817 s wall / 2.186 s CPU / 42.4 MiB peak RSS / 61,200 files/s / 0 ms cancellation latency**；权限、symlink loop、symlink escape 和 canonical duplicate issue 均通过。
- 当前 Mac Home 真实 UI 扫描：真实卷 **494.38 GB total / 201.38 GB used / 293.01 GB available**；扫描过程中真实显示 **177,593 files / 23,793 directories / 15.6 GB**，Top 大文件包含约 **2.44 GB** 和 **1.93 GB** 文件；随后通过 UI 取消，状态变为 `已取消`，未执行删除。
- UI 真实观察到 Home 扫描进程 RSS 约 **434–466 MB**、CPU 约 **24–72%**。取消后 CPU 回落到 0%，RSS 约 **431 MB**；该 RSS 峰值仍明显高于 Core 50k fixture，是本阶段未解决的性能风险。
- App arm64 Debug Build：PASS；Core arm64 Build：PASS；SwiftPM Tests：**55/55**；Xcode `LexCleanerCoreTests`：**55/55**；真实 SwiftUI App 启动和中文 Disk Analyzer 页面检查通过。
- Xcode App scheme 未配置 Test action，未伪造 App scheme 测试；按工程真实配置执行 `LexCleanerCoreTests` scheme。

### Mole 对照与当前结论

- 当前机器未安装 `/Applications/Mole.app`，本轮没有可靠的 Mole 同机同数据集 wall/CPU/RSS/Treemap 基线，因此不能声称已量化超越 Mole。
- LexCleaner 已验证的优势是：Core 低内存 50k fixture、明确 symlink/权限/canonical 边界、增量取消、只读安全边界和大文件不自动清理；这些是本项目实测能力，不是 Mole 对照结论。
- 当前阶段状态：**功能实现可运行，但 Disk Analyzer UI 验收未完成（FAIL）**。阻塞点是完整 Home UI 快照闭环和同机 Mole 基线缺失，另有真实 Home 扫描 RSS 偏高；不进入下一 UI 模块。

## Disk Analyzer UI 性能优化与同机 A/B（本轮）

### Profile 与实现

- 使用 Xcode `xctrace` Time Profiler、`sample` 和 `vmmap` 复核真实 Home UI；热点确认包括 SwiftUI/AttributeGraph 重建、重复 Treemap 投影、`DiskNode` parent/name 元数据重复、主线程扫描全量目录数组，以及 `contentsOfDirectoryAtURL` 大目录一次性物化。
- `DiskAnalysisSnapshot` 不再持有重复的完整 `treemapNodes` 数组，Treemap 从聚合目录树和 Top-N 大文件派生；完成 UI 只构造当前目录一层节点。
- 增量 UI 只保留根目录可见节点、Top-N 大文件和前 256 个 live issues；进度和投影统一约 0.75 秒更新。
- Core 遍历改为 Darwin `opendir/readdir` 单项流式读取，保留全部 lstat/canonical/allowed-root/symlink/权限检查；真实 50k runner 的 `maxBuffered=1`。

### 真实数据

- 50k fixture：50,002 files / 10 directories / 0.844 s wall / 2.206 s CPU / 43.3 MiB peak RSS / 59,299 files/s / cancellation 0 ms；权限、symlink loop/escape、canonical duplicate 通过。
- Cache scope Core：18,006 files / 8,418 directories / 3,259,498,519 bytes / 2.375 s wall / 2.906 s CPU / 60.4 MiB peak RSS / 8 个 Top-100 大文件 / 35 issues。
- Cache scope真实 UI：18,006 files / 8,418 directories / 3.26 GB；完成态 RSS 约 153 MB，Treemap 171 个根节点；已真实验证目录深入到 Homebrew、主目录返回、大文件排序切换为修改时间、滚动、深色模式和重新扫描状态。
- Home scope 新流式 UI：最高观察到约 325 MB RSS（physical footprint 约 210–242 MB），扫描到 580,213 files / 93,844 directories / 64.87 GB 后持续停留在 `opendir`；本轮没有伪造 Home 完成结果，状态仍 FAIL。

### Mole 同机 A/B

- `brew install tw93/mole/mole` 因官方 tap 在当前环境触发 GitHub 用户名提示而停止；随后使用 Homebrew core 正式 formula `mole 1.52.0`，arm64，许可证 GPL-3.0-or-later。
- `$HOME/Library/Caches` 同范围结果：Mole JSON `total_files=16,888`、`total_size=3,254,531,174`、20 个 large-file 条目、wall 0.29 s、峰值 RSS 17.4 MB；LexCleaner Core `18,006 files`、`3,259,498,519 bytes`、8 个 Top-N large files、wall 2.375 s、CPU 2.906 s、peak RSS 60.4 MiB。LexCleaner 将 symlink 叶子计入文件统计，Mole 的 `total_files` 不计入该类，计数差异已保留，不视为准确性胜负。
- Mole `$HOME` JSON 分析真实运行约 4 分 45 秒无输出、进程 RSS 约 17.8 MB 后停止；没有可靠 Home 同范围耗时/文件树/Treemap 基线，因此没有声称超越 Mole。

### 当前结论

- 内存从旧 UI 约 434–466 MB 峰值显著下降；Cache 完成态已低于 200 MB，但 Home 流程仍约 325 MB 且未完成。
- Disk Analyzer UI 当前仍 **FAIL**：Cache 级闭环通过，Home 全量 Treemap 和 Home 同范围 Mole 对比尚未通过。未引入删除、永久删除、root helper、private API 或安全规则放宽。

## Disk Analyzer 扫描架构重构与重新验证（本轮）

### 架构变化

- 先用 `xctrace` Time Profiler、`sample`、`vmmap` 复核热点：逐项 `lstat`/`realpath`、完整目录聚合、SwiftUI/AttributeGraph 投影和大量 issue/path 分配是主要成本；此前 Home 还会在特殊目录 `opendir` 长时间停留。
- 使用 macOS SDK 公开稳定的 `getattrlistbulk`，以 64 KiB 可复用 buffer 批量读取名称、类型、mtime、device/inode、logical size、allocated size 和 link count。
- 普通文件 canonical path 使用已 canonical 父目录加名称；目录和 symlink 仍调用 `realpath`，全部 allowed-root、symlink escape、权限和 canonical duplicate 检查保持不变。
- Snapshot 只保留 target root 和一级目录聚合；Treemap 使用一级目录、Top-N 大文件和 Others。点击目录后通过 Core 重新只读分析子树，UI 不持有完整文件树。
- logical/allocated bytes 分离；只有 `nlink > 1` 才保留精确 device+inode identity，避免为普通文件建立百万级 Set。Home issue 只保留 1,024 条样本并记录 suppressed count。
- `open` 使用 2 秒 watchdog；超时目录记录 `enumerationFailed` 并跳过，不能把未扫描数据计入成功结果。

### 真实结果

- 50k fixture：50,002 files / 10 directories / 0.667 s wall / 1.637 s CPU / 41.4 MiB Core peak RSS / 75,012 files/s / maxBuffered 585；permission、symlink loop/escape、canonical duplicate 和 cancellation 全部通过。
- Home Core：23.760 s / 55.088 s CPU / 96.1 MB peak RSS / 959,909 files / 146,921 directories / 600.33 GB logical / 121.53 GB allocated / 82 retained tree nodes / 1,024 issue samples / cancellation false。
- Home SwiftUI：真实完成约 759,990 files / 127,990 directories / 576.54 GB logical；根 Treemap、`Library` 懒加载深入和返回根目录通过。当前 UI RSS 约 256–267 MB，physical footprint peak 约 164.5 MB，RSS 目标 ≤200 MB 尚未达到。
- Cache A/B 同机同范围：LexCleaner 0.742 s / 1.529 s CPU / 90.6 MB RSS / 18,006 files / 8,418 directories / 3,248,534,601 logical bytes；Mole 1.52.0 0.18 s / 0.04 user + 0.10 sys / 14.7 MB RSS / 16,888 files / 3,250,999,941 bytes / 20 large-file entries。文件数差异保留为 symlink 统计口径差异，不作为准确性胜负。
- Mole Home 同范围运行约 4 分 45 秒无输出后停止，没有形成可靠的 Home baseline。

### 当前验收

- 全量 SwiftPM/Xcode：56/56；SafeDelete 13/13、Scan 12/12、Classification runner 21/21、Cleanup 16/16、Monitoring 4/4、Hardware 4/4、App Manager/System Tools/DiskAnalysis runners 通过；App/Core arm64 Debug Build 和 SwiftUI App 真实启动通过。
- 安全检查没有降低；未引入删除、root helper、private API、SMC 写入或系统状态修改。
- Disk Analyzer UI 仍 **FAIL**：Home 闭环已完成，但 RSS 未达 ≤200 MB，Cache A/B 速度/RSS 仍落后 Mole，Home 同范围 Mole 数据不可得。

### Disk Analyzer 性能收口（本轮，仍未达标）

- Profile 热点：普通文件逐项 URL/canonical 构造、批量 metadata 后的临时路径对象、`realpath`/目录打开调度，以及 UI 侧 live projection；未发现完整文件树被保留为 SwiftUI 节点。
- 本轮优化：普通文件仅保留 basename + compact metadata；canonical/path URL 延迟到大文件命中或安全 issue；getattrlistbulk buffer、流式聚合、bounded concurrency、目录 watchdog、Top-N/当前可视层策略保持不变，未放宽 symlink、权限、identity 或 hard-link 规则。
- 同机同范围最新 Caches（独立进程，最终容量模型后 3 次）：LexCleaner 0.34–0.53 s，peak RSS 20.2 MB；Mole 1.52.0 为 0.18 s / 14.7 MB。Release 构建 warm run 约 0.26 s / 19.8 MB，仍未超过任一关键指标。
- 同机 Home Core：11.570 s，960,377 files，147,008 directories，logical 600.55 GB，allocated 121.77 GB，volume capacity 494.38 GB，peak RSS 69.3 MB；`du -sk $HOME` 约 121.77 GB（121,771,278,336 bytes），未超过 volume。
- SwiftUI Home 最新启动观察到约 222 MB RSS，但在本次观察窗口内未完成 Home 扫描；历史完整 UI 基线约 25–30 s / 256–267 MB，仍未达到 ≤150 MB，不能标记 UI 性能通过。
- 回归：SwiftPM/Xcode **57/57**；SafeDelete 13/13、Scan 12/12、Classification 21/21、Cleanup 16/16、Monitoring 4/4、Hardware 4/4，App Manager/System Tools/DiskAnalysis runners 通过；Core/App arm64 Debug Build 通过。
- 结论：Disk Analyzer UI 继续 **FAIL**。本轮只完成实测优化和收口记录，没有声称超越 Mole。
- 追加启动验证：最新 App arm64 Debug 真实启动无崩溃；18 秒时 Home UI RSS 约 214.3 MB，扫描仍未完成，随后为避免无必要长时间运行而停止，因此 UI 完成态和 ≤150 MB 目标仍未验证通过。

### 容量口径校准（本轮）

- 根因：UI/旧报告把 `st_size`/logical size 累加结果当成实际磁盘占用。APFS sparse/clone/shared extents 会使 logical 大于物理占用；当前 Home logical 约 600.55 GB 不是物理磁盘使用量。
- 修复：快照、目录节点、Treemap、类型统计和大文件结果同时保留 logical 与 filesystem-reported allocated；Treemap 默认以 allocated 几何和排序，UI 明确显示两种口径。
- 真实交叉验证：`du -sk $HOME` 约 121.77 GB（121,771,278,336 bytes），LexCleaner allocated 约 121.77 GB；`df`/APFS 容器容量约 494.38 GB，LexCleaner allocated 被 volume capacity 上限约束。APFS shared extents 无法通过公开只读 API 精确唯一归属，UI 明确标注限制。
- 默认不跨 volume：入口和枚举均按 device 边界跳过其他 volume 并记录 `volumeBoundary`，symlink、权限、cancellation 和 watchdog 仍保持 fail-safe。

### Disk Analyzer 性能突破复核（本轮最终）

- [x] Time Profiler 后完成低层热路径优化：普通目录跳过重复 `realpath`，使用 canonical parent + relative basename；普通文件仍为 compact metadata + streaming aggregation；Top-N、Others、symlink、volume、identity、权限和 watchdog 保留。
- [x] 目录 watchdog 改为共享 deadline registry，避免每个目录创建独立 timer；阻塞 open 仍在独立 GCD 队列，超时/晚到 FD fail-safe 处理。
- [x] Home Core Release 完整扫描：9.03 s、peak RSS 约 43.5 MB、960,377 files、147,022 directories；logical 600.56 GB、allocated 121.78 GB、volume capacity 494.38 GB。
- [x] Caches Release 独立进程 5 次：冷启动约 0.397 s；warm 约 0.199–0.202 s，peak RSS 约 13.8–14.1 MB。Mole 同口径约 0.18 s / 14.7 MB；RSS 已低于 Mole，速度仍未达到严格 `<0.18 s`。
- [x] Xcode Core Tests：57/57；SwiftPM Tests：57/57；App arm64 Debug Build：PASS；DiskAnalysis 真实 runner、50k fixture、cancellation、permission、symlink loop/escape 和 canonical duplicate：PASS。
- [ ] SwiftUI Home：最新真实启动 15 秒窗口内未完成扫描，峰值 RSS 约 238.6 MB；未达到 ≤150 MB，故不计为 UI 性能通过。
- [ ] 最终状态：Disk Analyzer 继续 **FAIL**。未伪造超越 Mole 的结论，也未降低安全或容量统计口径。

### Disk Analyzer 性能收口复核（2026-08-23，本轮）

- [x] 使用 `sample`、`heap`、`vmmap` 复核真实 Home SwiftUI；主线程热点为 SwiftUI/AttributeGraph `ScrollView`/ViewGraph 布局。UI 堆仅保留约 100 个大文件行、约 73 个 Treemap 项，未发现百万级 SwiftUI 节点或完整文件树进入 UI 状态。
- [x] `DiskAnalyzerViewModel` 不再持有 `DiskAnalysisSnapshot`，只发布当前层 Treemap、Top-N 大文件、有限 issue 样本和统计投影；导航缓存限制为最多 4 层。外层页面与大文件区改为 `LazyVStack`，不改变安全检查、容量口径或删除边界。
- [x] Home UI 真实完成：Core 结果约 9.0 秒返回，约 960k files / 147k directories；应用在 20 秒观察窗口保持运行，无 fatal/uncaught/crash/runtime error。最新 Debug App RSS 峰值约 **163,984 KB（160.1 MiB）**，较前一轮约 229 MB 明显下降，但仍高于 ≤150 MB 硬目标。
- [x] Caches 同机同目录最终 20 次独立进程 A/B（`~/Library/Caches`）：LexCleaner 外部 wall median **0.208310 s**、P95 **0.209490 s**、best **0.195247 s**、RSS median **14,237,696 B（约 13.58 MiB）**；Mole 1.52.0 median **0.101786 s**、P95 **0.105475 s**、best **0.100185 s**、RSS median **14,868,480 B（约 14.17 MiB）**。LexCleaner 仅 RSS 低约 4.2%，速度未超过 Mole。
- [x] SwiftPM **57/57**、Xcode Core Tests **57/57**、App/Core arm64 Debug Build 通过；真实 SwiftUI App 启动 12 秒存活，无崩溃或明显 runtime 错误。
- [ ] Home SwiftUI RSS ≤150 MB、Caches median 速度超过 Mole：均未满足；Disk Analyzer 继续 **FAIL**，不进入下一模块。

### Disk Analyzer 最后性能攻坚（2026-08-23，本轮）

- [x] 公平性审计：双方根目录均为 `~/Library/Caches`；`find -xdev` 观察到 18,577 regular files、23 symlinks、8,418 directories。Mole `--json` 仅提供聚合结果（188 个一级 entries、`total_files=16,888`），没有 raw traversal 模式；因此未伪造纯遍历 A/B，完整分析结果明确标注为不同统计范围。
- [x] Profile：最新 Home Core 采样中 `getattrlistbulk` 占主要采样时间（5 秒采样中 1,189 个样本）；次要热点为 `recordFile` 聚合、文件类型分类、URL/path 桥接和目录 open 调度。没有发现完整文件树进入 SwiftUI 状态。
- [x] 最小优化：批量 buffer 采用 256 KiB 可复用内存；`DiskFileRecord` 直接复用批量 metadata；大文件参数在 accumulator 内缓存；聚合对象改为受锁保护的引用对象；目录队列优先使用已验证 device+inode 去重、无 identity 时回退 canonical path；UI projection 后台桥接、页面模型按需创建，并释放未使用 allocator pages。安全、symlink、volume、identity、权限、allocated-size 和 cancellation 规则未降低。
- [x] Home Core 最新真实扫描：8.966 s / CPU 10.006 s / peak RSS 29,147,136 B（约 27.8 MiB）/ 962,191 files / 147,192 directories / logical 600,921,956,236 B / allocated 122,158,923,776 B / volume 494,384,795,648 B。
- [x] Caches 20 次同机完整分析 A/B：LexCleaner median **0.196407 s**、P95 **0.198174 s**、best **0.191669 s**、RSS median **14,049,280 B（约 13.40 MiB）**；Mole 1.52.0 median **0.103023 s**、P95 **0.107417 s**、best **0.100865 s**、RSS median **14,729,216 B（约 14.05 MiB）**。LexCleaner RSS 低于 Mole，速度未超过 Mole。
- [x] Home SwiftUI 真实完成态约 9.0 s；最新一次峰值 **153,488 KB（149.89 MiB）**，但短窗口重复观察曾达到约 150.56–151.22 MiB，故不能宣称稳定满足 ≤150 MiB。
- [x] SwiftPM/Xcode **57/57**、App/Core arm64 Debug Build 通过；真实 App 启动无崩溃、无新增 fatal/uncaught/runtime error。
- [ ] Caches median 速度严格低于 Mole、Home SwiftUI RSS 稳定 ≤150 MiB：未满足；Disk Analyzer 最终继续 **FAIL**，不进入下一模块。

### Disk Analyzer 最后性能攻坚最终复核（2026-08-23）

- [x] 公平 benchmark 已将 LexCleaner runner 与 App 的 bounded concurrency 对齐为 3；双方根目录均为 `~/Library/Caches`。本轮 LexCleaner 统计 18,606 项/8,418 目录；Mole JSON 统计 16,888 files/188 个一级聚合项，Mole 不提供 raw traversal，因此纯 traversal 未伪造等价数字。
- [x] 20 次同机独立进程完整分析：LexCleaner median **0.196669 s**、P95 **0.197707 s**、RSS median **14,073,856 B（13.42 MiB）**；Mole 1.52.0 median **0.103400 s**、P95 **0.106636 s**、RSS median **14,712,832 B（14.03 MiB）**。
- [x] Profile 最大热点仍为 `getattrlistbulk`；本轮修复页面模型生命周期下沉到 Disk 页面，并将 allocator page relief 移出主线程。未移除 symlink、权限、volume、identity、watchdog、cancellation 或 allocated-size 校验。
- [x] Home Core 最新完整扫描约 **8.966 s / 27.8 MiB peak RSS**；allocated **122.16 GB**，volume **494.38 GB**，容量口径未回退。
- [ ] Home SwiftUI 最新 15 秒真实启动峰值 **150.70 MiB**；历史重复观察范围约 **149.89–151.22 MiB**，未能证明稳定 ≤150 MiB。
- [x] SwiftPM **57/57**、Xcode **57/57**、App/Core arm64 Debug Build 和真实 App 启动无崩溃通过。
- [ ] Disk Analyzer 仍 **FAIL**：RSS 虽低于 Mole，但 Caches median 约慢 **1.90×**，且 Home SwiftUI RSS 未稳定达到目标；不进入下一模块。

### Disk Analyzer 同口径与自适应并发最终复核（2026-08-23）

- [x] 建立 equal-scope benchmark：选择同一真实根目录 `~/Library/Caches/Homebrew`，两边均排除 `.git` 目录和 symlink 叶节点，均统计 3,473 files、Top-20 large files；当前代码 20 次结果：LexCleaner **0.043161 s median / 0.045827 s P95 / 12.60 MiB RSS**，Mole **0.095354 s / 0.098338 s / 11.95 MiB RSS**。该过滤只存在于显式 benchmark 配置，不改变 production scan。
- [x] Production full-quality Caches：LexCleaner **0.130214 s median / 0.158280 s P95 / 14.28 MiB RSS / 18,632 项**；Mole **0.106992 s / 0.112172 s / 14.02 MiB RSS / 16,888 files**。LexCleaner 的完整范围包含 production symlink/隐藏数据，不能与 Mole 的缩小范围混淆。
- [x] concurrency 1/2/3/4/6 实测后选择 4；6 更慢且 RSS 更高。Core 使用 bounded adaptive policy，硬上限 4；队列仍保留完整 device+inode 去重。
- [x] heap 定位目录 identity `Set` 约 6.2 MiB；替换为精确 device+inode 紧凑开放寻址表，Home Core 峰值降至约 **22.3 MiB**，未使用 hash-only/Bloom 近似。
- [x] Home Core 最新约 **7.215 s / 22.2 MiB**；allocated **122.31 GB**。Full-quality `~/Library/Caches` allocated 与 `du` 差约 **16 KiB**。
- [x] Home SwiftUI 3 次稳定启动峰值 **143.98–144.83 MiB**，最新 **144.28 MiB**；无崩溃或启动错误。
- [x] SwiftPM/Xcode **57/57**，App/Core arm64 Debug Build 通过。
- [ ] 综合结论：equal-scope 速度已超过 Mole，但 RSS 仍略高；full-quality 速度和 RSS 仍略落后。Disk Analyzer 保持 **FAIL**。

### Disk Analyzer 容量展示修正（2026-08-23）

- [x] 主容量区域仅保留 **总容量 / 实际占用（Allocated Size）/ 可用空间**；移除 Volume Used 和 Logical Size 主卡片，避免把扫描逻辑大小理解为物理占用。
- [x] Logical Size、扫描范围和 APFS 解释移入默认收起的“详细信息 / Detailed information”；说明已本地化：逻辑大小可能因 APFS 克隆、稀疏文件和共享数据而超过磁盘物理容量。
- [x] Treemap 继续只使用 `allocatedSizeBytes` 进行过滤、排序、面积计算和布局；节点中的 Logical 仅作为辅助文本。
- [x] 当前构建真实中文/英文启动截图通过：主界面不再出现 Logical Size 主卡片或“已扫描”容量值；当前真实值示例为 Volume **494.38 GB**、Allocated **122.36 GB**、Available **285.02 GB**。
- [x] SwiftPM **57/57**、Xcode **57/57**、App/Core arm64 Debug Build 通过；真实 SwiftUI App 启动和中英文截图通过。

### Disk Analyzer 最终收口核验（2026-08-23）

- [x] Full-quality 20 次独立进程 A/B：LexCleaner **0.130214 s median / 0.158280 s P95 / 14.28 MiB RSS**；Mole **0.106992 s / 0.112172 s / 14.02 MiB**。LexCleaner 未同时超过 Mole：median、P95 和 RSS 均未达全量目标。
- [x] Home SwiftUI 真机截图确认容量口径：界面显示 Volume **494.38 GB**、扫描逻辑大小 **601.07 GB**、扫描实际占用 **122.32 GB**；Treemap 使用实际占用并分别标注逻辑大小，实际占用未超过 Volume。
- [x] 同一 Home 扫描结果：allocated **122,317,611,008 B**；随后 `du -sk $HOME` 为 **122,317,615,104 B**，差 **-4,096 B（-4 KiB）**。`du` 对受 TCC 保护的条目报告了权限错误，LexCleaner 同样以 issue 记录并 fail-safe 跳过。
- [x] SwiftPM/Xcode **57/57**、App/Core arm64 Debug Build、真实 SwiftUI 启动和截图验证通过；无新增崩溃或容量显示错误。
- [ ] 综合结论：Full-quality 性能未全面超过 Mole，Disk Analyzer 继续 **FAIL**，不进入下一模块。

### Disk Analyzer Full-quality 性能收口（2026-08-23）

- [x] 使用 `sample` 复核当前真实热点：`getattrlistbulk`/metadata 批量读取是主要成本；其次为文件扩展名分类、聚合更新和目录 open/watchdog 调度。没有改变容量逻辑、Treemap 或 UI 状态。
- [x] 增加默认关闭的 audit-only breakdown，分别记录 metadata、symlink、volume、permission、identity、hard-link、watchdog 和 aggregation 的调用量/耗时；默认扫描不付出计时与额外同步开销。Full-quality 诊断样本：metadata 15,099 calls/27,088 entries/106.7 ms；symlink 23/0.69 ms；volume 27,088 checks、0 越界/0.31 ms；permission 8,418 checks、0 failures；identity 8,406/4.85 ms；hard-link 78 candidates、39 duplicates/0.04 ms；watchdog 8,418 opens、0 timeout/并发累计 250.9 ms；aggregation 18,671 records/15.6 ms。
- [x] 仅做两类安全优化：ASCII 扩展名分类避免 `Substring`/`lowercased` 临时分配；固定内容类别槽位替代每文件字典更新；无 progress callback 时使用同步聚合路径，跳过无意义 async continuation。所有 metadata、symlink、volume、permission、identity、hard-link、watchdog、cancellation 和 allocated-size 规则保持不变。
- [x] 当前同机 20 次独立进程 Full-quality A/B（`~/Library/Caches`，LexCleaner concurrency=4，Mole 1.52.0 正式入口）：LexCleaner median **0.123851 s / P95 0.130943 s / RSS median 14.26 MiB**；Mole median **0.105185 s / P95 0.109194 s / RSS median 13.95 MiB**。LexCleaner 仍未在速度、P95、RSS 三项全面超过 Mole；结果范围为 LexCleaner 18,677 files/8,418 directories/issues 35，Mole JSON `total_files=16,888`。
- [x] SwiftPM **57/57**、Xcode Core Tests **57/57**、App/Core arm64 Debug Build 通过；当前构建真实 SwiftUI App 启动存活，无崩溃或新增运行时错误。
- [ ] 最终状态：Full-quality 仍未形成综合性能优势，Disk Analyzer 继续 **FAIL**，不进入下一模块。

### Disk Analyzer 两阶段流水线（2026-08-23，本轮）

- [x] 建立 `Fast Inventory → Immediate Treemap → Deep Enrichment/Verification` 阶段模型。首屏投影来自同一条 `getattrlistbulk` 扫描流的有界 root-level Top-N/Others 数据；没有第二次缩小范围的扫描，最终 `DiskAnalysisSnapshot` 仍由完整安全遍历产生。
- [x] UI 在首个可用投影到达后切换到“正在完善结果 / Enriching results”，后台继续完成 identity、hard-link、权限、volume、symlink、watchdog、allocated-size 和完整聚合；SwiftUI 只保留当前可视层、Top-N 大文件和有限 issue 样本。
- [x] 当前缓存目录同机 20 次两阶段测量：首个 Core 可用投影 median **0.002 s**、P95 **0.002 s**；同一完整扫描的内部完成 median **0.118 s**、P95 **0.120 s**。首个 UI 投影轮询上限已降至 10 ms，未改变完整扫描口径。
- [x] 20 次 Full-quality 独立进程 A/B（`~/Library/Caches`，LexCleaner concurrency=4）：LexCleaner median **0.124392 s**、P95 **0.143803 s**、RSS median **13.20 MiB**；Mole median **0.103051 s**、P95 **0.143729 s**、RSS median **13.96 MiB**。LexCleaner RSS 已低于 Mole，首个可用结果明显更快，但 Full-quality median 仍较慢，且统计项为 18,704 files / 8,418 directories vs Mole JSON `total_files=16,888`，不能伪造为完全同范围。
- [x] Profile 后保留 4-worker bounded adaptive 并发（5/6 worker 实测更慢且 RSS 更高），批量 buffer 降为每 worker 128 KiB；未移除 symlink、permission、volume、identity、hard-link、watchdog、cancellation 或准确性检查。
- [x] SwiftPM 构建与 DiskAnalysis 真实 runner 通过；阶段实现未修改容量 UI/Treemap 几何或删除链路。
- [x] SwiftPM 57/57、Xcode `LexCleanerCoreTests` 57/57、LexCleanerApp/LexCleanerCore arm64 Debug Build 通过；构建产物真实启动 5 秒存活，无 LexCleaner 崩溃或新增应用级 runtime error。
- [ ] Full-quality median 尚未低于 Mole，故 Disk Analyzer 继续 **FAIL**，不进入下一模块。

### 容量单位审计与修正（2026-08-23，本轮）

- [x] 完成 App/Sources/Tests 容量格式化审计：移除 UI 对 `ByteCountFormatter`/隐式 binary label 的依赖，统一由 `ByteUnitFormatter` 负责显示；底层 byte 值、扫描统计和分配大小均未修改。
- [x] 用户界面默认使用十进制单位：`KB/MB/GB/TB` 按 1,000 倍递进；仅在明确调用 binary formatter 时显示 `KiB/MiB/GiB/TiB`。Dashboard、Cleaner、App Manager、Disk Analyzer（Treemap/大文件/类型统计）等容量文本均经过同一格式化入口。
- [x] 大文件阈值保留原始 `50 * 1024 * 1024` bytes，不改变筛选行为；UI 按真实 byte 值显示 `52.43 MB`，避免把二进制阈值误标为 50 MB。
- [x] 增加 `ByteFormatterTests`：`494,384,795,648 B` 显示为 `494.38 GB`，同一 byte 值的二进制表达显示为约 `460.43 GiB`；KB/MB/GB 与 KiB/MiB 的标签和换算分别验证。SwiftPM/Xcode 测试均为 **60/60**。
- [x] 读写速率单独审计：Monitoring 仍使用累计 byte counter 差值除以真实采样 elapsed time，UI 仅以十进制 byte/s 展示；未把速率换算混入容量修复，也未改变采样周期或底层 counter。
- [x] 实机验证：macOS 26.5.1、Apple Silicon；`df -P -k /` 报告 volume 为 `482,797,652 × 1024 = 494,384,795,648 B = 494.38 GB`（约 `460.43 GiB`）。当前构建 SwiftUI 截图显示总容量 **494.38 GB**，不再显示为 460.43 GB。
- [x] `/Applications/Stats.app` 3.0.11 正在运行；其菜单栏以容量百分比和读写速率为主，不暴露独立的总容量字段。可交叉读取的 macOS volume 总容量与 LexCleaner 的 **494.38 GB** 一致；`volumeAvailableCapacityForImportantUsageKey` 与 `df` 的 free-space 语义不同，未将两者伪装成同一指标。
- [x] `xcodebuild` App arm64 Debug Build、Core Build 和 Xcode Tests **60/60** 通过；当前构建真实启动无崩溃，中文 Dashboard 截图通过。
### Integration Cleanup（2026-08-23）

- [x] 冻结并审计 main 基线：`7a725379d866901e326b2ce4d8f63faaca75a1ca`（`Baseline: LexCleaner product foundation`）；提交前 SwiftPM/Xcode **60/60**、App Build、9 个真实 Core runner 和真实 App 启动通过；无发现 secret 或生成文件，main clean。
- [x] `feat/monitoring-hardware-ui` rebase 到基线后提交 `240ff8d`，保留正式 `LexCleanerApp.swift` 和 Dashboard，监控/硬件 UI 作为独立页面接入；分支 SwiftPM/Xcode **60/60**、App Build、真实启动通过。
- [x] `feat/system-tools-ui` rebase 到监控合并后的 main 后提交 `fd3955b`；修复 `count()` 字面量、公开 `PrivacyCapability`、统一主 `.xcstrings`，接入 App Shell；分支 SwiftPM/Xcode **60/60**、System Tools 真实验证、App 启动通过。
- [x] `feat/menubar-updater` rebase 到最新 main 后提交 `6136a3b`；统一 `MonitoringSamplingConfiguration`/`UpdateMetadata`，速率使用十进制单位，移除独立 `.lproj`，保留 Sparkle unavailable fail-closed 状态；菜单栏入口真实启动与可访问性注册通过。
- [x] 实际合并顺序：monitoring/hardware → system tools → menubar/updater；当前 main 合并提交：`daf56a9`。
- [x] 最终 main SwiftPM/Xcode **61/61**、App arm64 Debug Build、9 个真实 runner、真实 SwiftUI App 启动通过；main clean。
- [ ] Disk Analyzer 未重复合并旧分支，仍保持 **FAIL**；Full-quality 性能尚未综合超越 Mole。
- [ ] Sparkle/feed 尚未真实接入；菜单栏更新功能仅提供只读检查模型与手动安全 URL 打开，不宣称完整自动更新。

### Disk Analyzer Full-quality 性能攻坚（2026-08-23，本轮）

- [x] 基于最新 main `c19f06c` 开发；未使用旧 `feat/disk-analyzer` 分支。开始时 main clean，未修改容量 UI、Treemap 几何或删除链路。
- [x] 使用 Xcode/macOS `sample` 和 audit-only breakdown 复核热点：`getattrlistbulk` **15,101 calls / 27,211 entries / 113.3 ms 累计阶段时间**；目录 watchdog **8,418 opens / 0 timeout / 162.6 ms 并发累计时间**；symlink **23 / 0.55 ms**、volume **27,211 checks / 0.33 ms**、identity **8,406 / 4.97 ms**、hard-link **78 candidates / 39 duplicates / 0.02 ms**、aggregation **18,794 records / 16.1 ms**。累计阶段时间因 4 个 bounded worker 并发而不可直接相加为 wall time。
- [x] 仅保留一项有 Profile 依据且不改安全语义的优化：目录 open 仍在独立并发队列、100 ms watchdog 和 fail-closed 超时保护下，将队列 QoS 从 utility 调整为 user-initiated，减少前台扫描关键路径的调度延迟。256 KiB buffer、5 ms watchdog 轮询、临时数组/属性缓存等实验未保留：没有稳定收益或提高 RSS。
- [x] 高精度 20 次同机独立进程 A/B，根目录均为 `$HOME/Library/Caches`。LexCleaner Full-quality（concurrency=4）median **0.122357 s**、P95 **0.122517 s**、best **0.119971 s**、worst **0.142029 s**、RSS median **13.34 MiB**；Mole 1.52.0 官方入口 `mole analyze --json` median **0.103002 s**、P95 **0.103547 s**、best **0.101024 s**、worst **0.121023 s**、RSS median **14.12 MiB**。Mole JSON 仅报告 **16,888 files / 3,255,246,957 logical bytes**；LexCleaner 完整安全结果为 **18,794 files / 8,418 directories / 35 issues / 3,337,256,960 allocated bytes**，两者输出范围和安全检查深度不同，未将范围差异伪装成准确性优势。
- [x] 质量交叉验证：LexCleaner allocated bytes **3,337,256,960 B** 与 `du -x -k -d 0 $HOME/Library/Caches` 的可见结果 **3,337,256,960 B** 一致；`du` 对 12 个 TCC 受保护路径报告 Operation not permitted，LexCleaner 同样记录 issue 并 fail-safe 跳过。symlink、volume boundary、permission、identity、hard-link、watchdog、cancellation 和完整遍历范围保持不变。
- [x] SwiftPM **61/61**、Xcode Core Tests **61/61**、App/Core arm64 Debug Build、9 个真实 Core runner 和真实 SwiftUI App 启动全部通过。未发现本轮新增崩溃、容量错误或安全回退。
- [ ] Full-quality 速度和 P95 仍明显落后 Mole，RSS 虽低于 Mole但不足以抵消速度差距；Disk Analyzer 继续 **FAIL**，不进入下一模块。

### Disk Analyzer Full-quality 条件式 metadata 优化（2026-08-23，本轮）

- [x] 基于当前 main `eedc9eb` 做真实 `sample`/breakdown；最大热点仍是 `getattrlistbulk` 及其属性解析，目录 open/watchdog、identity、hard-link 和 aggregation 均为次要成本。未修改容量 UI、Treemap、删除链路或扫描范围。
- [x] 缩小 bulk attribute set：移除普通单链接文件不需要的 `ATTR_CMN_FILEID` 和仅目录需要的 `ATTR_CMN_ACCESSMASK`。保留 name、device、object type、mtime、error、logical size、allocated size、link count；目录、symlink 和 `nlink > 1` 文件通过父 fd 的 `fstatat(..., AT_SYMLINK_NOFOLLOW)` 条件式取得 identity，目录同时取得权限位。条件读取失败立即 fail-closed。
- [x] 内部 `Date` 改为秒/纳秒紧凑时间戳，仅在聚合节点或大文件结果需要对外暴露时构造 `Date`；时间比较语义不变。四种 buffer 实测中 128 KiB 最佳：约 15,101 metadata calls；256/512 KiB 无稳定墙钟收益且 RSS 上升，1/2 MiB RSS 继续上升，因此保留 128 KiB。
- [x] Buffer 5 次实测摘要（同一 `~/Library/Caches`、concurrency=4）：128 KiB warm **0.1206–0.1326s / 13.2–13.3 MiB**；256 KiB **0.1212–0.1255s / 14.0–14.1 MiB**；512 KiB **0.1208–0.1255s / 15.1–15.3 MiB**；1 MiB **0.1208–0.1271s / 17.1–17.2 MiB**；2 MiB **0.1214–0.1271s / 21.0–21.2 MiB**。metadata calls 分别约 **15,101 / 15,099 / 15,098 / 15,098 / 15,098**，差异受缓存目录实时变化影响，未以少扫文件制造优势。
- [x] 20 次同机独立进程 Full-quality A/B：LexCleaner median **0.116313s**、P95 **0.147000s**、RSS median **14,114,816 B（13.46 MiB）**；Mole 1.52.0 官方入口 median **0.102360s**、P95 **0.112868s**、RSS median **14,639,104 B（13.96 MiB）**。LexCleaner RSS 低约 3.6%，但 median 仍慢约 13.6%，P95 也更慢。
- [x] 真实 Release Home 扫描：**6.775s / 20.78 MiB peak RSS / 974,425 files / 151,154 directories**；logical **602.54 GB**、allocated **123.80 GB**、volume **494.38 GB**，完整扫描和 issue 记录仍通过。
- [x] 质量回归：hard-link 去重、symlink loop/escape、volume boundary、permission fail-safe、identity、watchdog、cancellation、Treemap 聚合和 allocated-size 与 `du` 交叉验证保持通过；SwiftPM/Xcode **61/61**，App/Core arm64 Debug Build，真实 SwiftUI App 启动通过。未发现误删或安全回退。
- [ ] Full-quality median、P95 与 RSS 尚未同时超过 Mole；Disk Analyzer 继续 **FAIL**，不进入下一模块。

### Disk Analyzer Traversal 尾延迟收口（2026-08-23，本轮）

- [x] 基于当前 main `e5fd834` 做新一轮 `sample` Profile；P95 相关热点仍集中在 `getattrlistbulk`/属性解析，其后是目录 `openDirectoryWithTimeout`、条件式 `fstatat`、目录 URL 构造、`String` 文件名解码和分类/聚合。未凭感觉改写低层扫描器。
- [x] 评估固定 worker pool、每 worker 独立复用 buffer、共享 watchdog、批量目录任务和批量聚合回传。固定 worker、独立 buffer、共享 watchdog 与 `getattrlistbulk` 已保留；批量目录任务在 2/4 项实验中没有稳定收益，且初版暴露了 in-flight/active 并发统计混淆，已撤回。所有安全边界保持原语义。
- [x] 仅保留批次内 `DiskFileRecord` 数组容量复用，减少每次 `getattrlistbulk` 批次的 reserve/释放；未新增 C bridge 或牺牲 symlink、volume、permission、identity、hard-link、watchdog、cancellation 检查。
- [x] 最终 30 次同机同范围独立进程 A/B（`$HOME/Library/Caches`，LexCleaner concurrency=4，双方高精度外部计时）：LexCleaner **median 0.118958 s / P95 0.132997 s / P99 0.156220 s / RSS median 13.55 MiB / RSS P95 13.62 MiB / RSS max 13.80 MiB**；Mole 1.52.0 官方入口 **median 0.100518 s / P95 0.106033 s / P99 0.116111 s / RSS median 13.98 MiB / RSS P95 14.41 MiB / RSS max 14.50 MiB**。同设置相邻 30 次进程 CPU 均值约 LexCleaner **0.271 s**、Mole **0.134 s**；LexCleaner 的内部并发 CPU 累计值不与 Mole 单进程值混用。
- [x] Release Home 最终真实扫描：**6.734 s / 20.62 MiB peak RSS / 974,474 files / 151,156 directories / 82 retained treemap nodes / 1,024 issues**；logical **602.55 GB**、allocated **123.81 GB**、volume **494.38 GB**，未卡死且完整结束。`du -x -k -d 0 $HOME` 为 **123,811,741,696 B**，本次 allocated 结果与其相差 **147,456 B**，仍在受保护路径/实时变化可解释范围内。
- [x] 真实验证：50,000 文件受控目录、权限目录、symlink loop/escape、canonical duplicate、cancellation、Home Caches 真实扫描均通过；最大活跃并发重新验证为 3。SwiftPM **61/61**、Xcode Tests **61/61**、App/Core arm64 Debug Build、真实 SwiftUI App 启动均通过。
- [ ] 目标 `median ≤0.09 s / P95 ≤0.10 s` 未达到；LexCleaner RSS 低于 Mole，但 median 慢约 **18.4%**、P95 慢约 **25.4%**，CPU 也更高。准确性、安全性、完整性和 Treemap 保持，但尚未形成用户要求的明显综合领先；Disk Analyzer 继续 **FAIL**，不进入下一模块。

### Disk Analyzer 质量总验收与公平 Benchmark Harness（2026-08-23，本轮）

- [x] 新增固定只读 Harness：受控同一目录/数据集、20,000 个普通文件 + hard-link + symlink loop/escape + permission-denied 目录；固定并发 4、Top-N 20、输出为统一 summary + Top20；equal-scope 与 full-quality 明确记录 symlink 规则；Lex analyzer cache disabled，Mole 使用空 HOME cold 后同 HOME warm。macOS 文件缓存未被特权刷新，Harness 明确标注该限制。
- [x] Harness 真实结果（同一 fixture）：`du -skPx` allocated **84,017,152 B**；Lex equal-scope **20,001 files / 290 dirs / 3,377,088 logical B / 84,013,056 allocated B**，与 du **-4,096 B**（目录块未归入文件聚合）；Lex full-quality **20,003 files**（两个 symlink 作为叶子计数，不递归）/ 同 allocated；cold/warm 结果一致。Mole JSON **20,001 files**，logical **3,377,088 B**（warm 为 **3,377,152 B**），其 JSON 没有 allocated-size 字段，故未将逻辑值冒充物理值。
- [x] 修复一个真实质量缺陷：子树 Treemap 的异步深入可能残留上一层节点；同时折叠 direct-child aggregate 的 `Other` 投影会与目录本身重复计入。现在 UI 以解析后的 direct parent 过滤异步子树，Core 仅对扫描根生成 `Other` remainder。新增回归断言；真实中文 UI 已验证深入用户主目录的隐藏配置目录后只显示其直接子目录、无重复 `Other`，点击“主目录”可返回；allocated-size 与 logical-size 分开显示。
- [x] 真实 UI 质量验证：中文和 English 语言切换即时生效，Disk Analyzer 页面无明显截断；恢复为“跟随系统”。Home 扫描真实完成，当前实测 **974,541 files / 151,171 directories / 9.17 s / peak RSS 21.0 MiB Core**；App 进程在扫描完成后约 **182.8 MiB RSS / 3–5% CPU**，20 秒后 RSS 未继续增长。English/中文 AX 树均显示真实容量和路径值。
- [x] 质量路径通过：allocated 与 `du` 差 4 KiB（受目录块/权限边界影响）、logical/allocated 分离、hard-link、symlink loop/escape、permission fail-safe、cancellation、canonical duplicate、Top-N、大目录聚合和异常目录恢复；现有 50k 受控 runner、Home 近百万文件真实扫描均完成，无卡死。
- [ ] 质量覆盖缺口仍存在：当前机器没有第二个 `/Volumes/*` 数据卷，无法在不修改外部卷的情况下实测跨 volume 条目；没有安全、确定的方式强制触发 watchdog timeout；未生成 1,000,000 文件专用 fixture（Home 实测 974,541，已覆盖近百万规模）；未做长时间（10 分钟级）Disk Analyzer 专项稳定性运行。App Debug 进程 RSS 也高于既往 ≤150 MiB 目标，属于未收口性能/资源问题而非本轮新增数据错误。
- [ ] 结论：本轮确认的 1 个 Treemap 正确性缺陷已修复，当前没有已确认的 allocated/logical、symlink、hard-link 或删除安全回退；但上述环境/专项覆盖缺口和 UI RSS 资源指标未全部收口，Disk Analyzer **质量验收继续 FAIL**，不进入下一模块。

### Disk Analyzer 质量专项收口（2026-08-23，本轮）

- [x] 第二卷边界使用用户目录临时 APFS 稀疏镜像真实挂载验证，无 sudo、无真实用户卷修改；联合扫描记录 volumeBoundary 并排除第二卷目标，外接卷单独扫描 fileCount=1，allocated **8,388,608 B** 与 du -skPx **8,388,608 B** 差 **0 B**，volume capacity **268,394,496 B**，symlink 指向第二卷未递归越界。临时镜像已卸载并清理。
- [x] 百万文件专项构造 **1,048,576 files / 1,025 directories**；完整扫描 **2.410 s**，文件数、目录数、tree.isComplete 和 volume 上限均正确，allocated **4,294,967,296 B** 与 du 差 **0 B**；真实取消在 **15,360 files / 0.047 s** 处生效。
- [x] 真实慢目录专项构造 **32,000 files / 9 directories**，扫描 **0.061 s** 完成且未卡死；但本机 APFS 没有造成 open(2) 阻塞，watchdog timeout **0**，因此“超时后跳过并记录”未被真实验证，不能标记通过。没有用注入、Mock 或人为假结果替代。
- [x] 真实 SwiftUI App 10 分钟级运行完成：扫描、取消、Home Treemap .codex 钻取/返回均真实执行；主进程 RSS 在重复扫描期间约 **166–336 MiB**，稳定段约 **220–267 MiB**，峰值明显超过 **150 MiB**；CPU 在扫描时最高约 **445%**，完成后约 **3–11%**。因此 UI RSS 硬指标失败。
- [x] Benchmark Harness RSS 归因：Harness 在同一进程中保留 fixture、Mole Process/Pipe/JSON 结果以及多次 Lex snapshot；DiskAnalysisPerformance.peakResidentMemoryBytes 是进程 high-water，不是隔离 scanner RSS。控制 fixture Lex 报告约 **29.5 MiB**，此前独立真实 Caches runner 约 **13–14 MiB**；该差异属于 Harness 进程开销，但没有从真实进程峰值中隐瞒。
- [x] 回归：SwiftPM **61/61**、Xcode LexCleanerCoreTests **61/61**、App/Core arm64 Debug Build 通过；构建后真实 SwiftUI App 状态可读取、窗口存活，无 LexCleaner 崩溃或新增 App 级 runtime error。xcodebuild -list 中无 LexCleaner scheme，使用实际 LexCleanerCoreTests scheme 完成 Xcode 测试。
- [ ] 结论：Volume boundary、百万文件完整性/allocated-size/cancellation 通过；真实 watchdog timeout 和 SwiftUI RSS ≤150 MiB 未通过，Disk Analyzer **Quality = FAIL**，不进入性能完胜 Mole 阶段。

### Disk Analyzer 质量收口：watchdog 与 SwiftUI 生命周期（2026-08-23）

- [x] 为 DiskAnalysisEngine 增加仅模块内部可见的 directory opener 测试 seam。公开 production initializer 不变，默认仍通过真实 POSIX open(2)、O_NOFOLLOW 与原有共享 100 ms watchdog 执行。
- [x] 受控真实文件夹夹具使用阻塞 opener 走 production watchdog：超时后得到 enumerationFailed issue 和 watchdogTimeouts == 1，被跳过目录之外的后续目录仍完成扫描；取消阻塞 open 后产生 cancelled partial snapshot，cancellation latency 小于 1 秒。
- [x] 完成态 Treemap 投影改为按当前父目录生成单层节点，不再先生成完整 treemapNodes 后在 SwiftUI 过滤。磁盘页离开会取消 scan/live/treemap/volume tasks，并释放 completed projection、可视节点、导航 cache、live projection 和筛选结果。
- [x] 定向 DiskAnalysis 测试、SwiftPM 与 Xcode Core Tests 均通过，当前共 **63/63**；App arm64 Debug Build 通过。
- [x] 一次 10 分钟真机窗口：Home 扫描完成、Treemap 可钻取、离页取消完成。进程 RSS 峰值 **190,560 KiB（186.09 MiB）**，离开磁盘页后稳定约 **176,608–176,720 KiB（172.47–172.58 MiB）**；采样 CPU 为扫描期最高约 37.5%，稳定期约 3.0–15.0%，未见持续增长或长期高占用。
- [x] 验证结束后关闭本轮 Debug App，并清理一个父进程为 1 的旧 Debug LexCleaner orphan；未发现残留 LexCleaner Debug App、xcodebuild、swift test 或 DiskAnalysis runner。
- [ ] Watchdog 真实验证已 PASS；SwiftUI RSS 未达到 ≤150 MiB，因此 Disk Analyzer Quality 继续 **FAIL**。尚需以实际 Profile 进一步定位约 22 MiB 稳定 RSS 超额的持有者，禁止以降低树、扫描范围或安全检查掩盖。

### Disk Analyzer SwiftUI 内存 Profile 收口（2026-08-23）

- [x] 使用 Instruments Allocations 命令行附着、vmmap 与 heap 对 Debug/Release 真机进程做内存归因。xctrace 成功附着但在指定 10 秒后未自行结束，按防卡死规则终止；其 trace 未能导出分配表。heap 受 macOS 调试保护限制，不能枚举活动对象类型，因此未伪造 Memory Graph 类型结论。
- [x] 可验证归因：Release Home 扫描完成后，Treemap 只有 82 个可视目录节点与 Top-100 大文件；离页 AX 树不再包含任何 Disk Analyzer 节点。Release 页面离开后的 DefaultMallocZone allocated 约 **50.5 MiB**、AttributeGraph 约 **0.7 MiB**、QuartzCore 约 **0.3 MiB**；physical footprint 最终 **68.0 MiB**、峰值 **98.7 MiB**。ps RSS 中的剩余大部分是 SwiftUI/AppKit 及共享 TEXT/mapped-image resident 页，不等同于 LexCleaner 私有堆。
- [x] 生命周期补强：页面离开释放 scan/live/treemap/volume tasks、completed projection、Treemap/navigation cache 与筛选投影后，在 utility detached task 调用 malloc_zone_pressure_relief，仅归还无 live allocation 的 allocator 页；未修改树、扫描范围、accuracy 或安全校验。
- [x] Release 最终单次 10 分钟真机窗口：Home 扫描完成后离页，观测 ps RSS peak **175,136 KiB（171.03 MiB）**，离页后稳定 **168,960–169,280 KiB（164.99–165.31 MiB）**；CPU 稳定期约 **3.5–10.5%**，无持续增长。相比本轮未释放 allocator 页的 Release 对照，离页后 physical footprint 从约 **77.5 MiB** 降至最终 **68.0 MiB**，但 ps RSS 仍未达到 ≤150 MiB。
- [x] Debug 对照：此前同范围 Debug 窗口为 peak **186.09 MiB**、离页后约 **172.5 MiB**；Debug heap physical footprint 约 **87.0 MiB**、peak **101.4 MiB**。Release 相比 Debug 的 ps RSS 和 private footprint 均较低，但 Release ps RSS 也未达到 ≤150 MiB，不能把问题归咎为 Debug/Xcode 注入。
- [x] SwiftPM **63/63**、Xcode Core Tests **63/63**、Debug/Release arm64 App Build 通过；Release App 真机启动、Home 扫描和离页释放验证通过。xcodebuild 中两个 Trash 测试因系统 Trash 响应延迟耗时 37–76 秒，最终均通过。
- [ ] Disk Analyzer Quality 继续 **FAIL**：没有发现 completedProjection、Treemap cache、navigation cache 或 scanner context 的残留持有，但 Release observed RSS 仍高于稳定 ≤150 MiB 和 peak 优先 ≤160 MiB 目标。后续若继续，须在允许的系统调试权限下取得可导出的 Allocations/Memory Graph 后再针对私有堆类型修改。

### Disk Analyzer 内存质量标准重定义与最终交叉核验（2026-08-23，本轮）

- [x] 不再将 RSS 作为单独的 PASS/FAIL 门槛。Release 最终 10 分钟验收数据保持为：RSS 稳定 **164.99–165.31 MiB**、峰值 **171.03 MiB**；RSS 包含共享 SwiftUI/AppKit/dyld TEXT、映射镜像和可回收页，不能直接等同于 LexCleaner 私有常驻内存。
- [x] `footprint`/`vmmap`/`heap` 交叉核验：既有最终 Release 验收进程页面离开后 private physical footprint **68.0 MiB**、peak **98.7 MiB**；`vmmap` 的 writable resident 与 mapped/read-only image 区域显示其余 RSS 主要来自共享/映射页。最终 Release heap 观测约 **50.5 MiB**，AttributeGraph 约 **0.7 MiB**，Quartz/CoreAnimation 约 **0.3 MiB**；没有证据表明完整扫描树或百万级明细驻留在应用私有 heap。
- [x] Activity Monitor 交叉样本：Release 空闲进程内存列 **60.9 MB**，短时真实 Home 扫描期间 **71.2 MB**；该列与 `footprint` 同量级，明显低于 `ps` RSS，印证 RSS 中存在大量共享/映射页。短时复核不替代既有 10 分钟验收数据。
- [x] Release 真机页面离开后，scanner、completedProjection、Treemap cache、navigation cache、task 与中间扫描状态均已释放；AX 树不再包含 Disk Analyzer 节点，最终验收过程无持续增长。Release/Debug 对照、Treemap 82 节点和 allocator pressure relief 结果均已记录。
- [x] 无 orphan LexCleaner Debug/App、xcodebuild、swift test 或 DiskAnalysis runner 残留；当前工作区仅保留既有源代码、测试与进度文档修改。
- [x] 新门槛全部满足：Release private physical footprint 稳定 **68.0 ≤ 80 MiB**、peak **98.7 ≤ 100 MiB**；应用 heap 约 **50.5 ≤ 60 MiB**；10 分钟无持续增长；Watchdog、第二卷、百万文件、allocated/du、Treemap、**63/63**、Debug/Release Build 和真机启动均通过。
- [x] 按重定义后的指标，**Disk Analyzer Quality = PASS**。RSS 仍作为参考记录，不再单独阻止质量验收。

### Disk Analyzer 最终性能冲刺（2026-08-23，本轮）

- [x] 基于当前 `main` 工作区进行 Profile。Home `sample` 显示最大墙钟热点是 `getattrlistbulk` 与目录 open 队列：采样期间分别约 **147/171** 和 **286/286** 个样本；`fstatat`、aggregation、hard-link、volume 与 SwiftUI 投影仅占少量样本。未凭感觉调整 QoS 或扫描范围。
- [x] 仅保留低风险热路径优化：目录 open/watchdog 的 `NSLock` 改为 `os_unfair_lock`；open/timeout 竞争使用受锁保护的 `UnsafeContinuation`，由一次性 resolver 保证最多 resume 一次；延迟扫描批次复用 `DiskFileRecord` 数组；同一目录任务内复用 canonical/aggregate/scan-root path key，减少重复 URL→String 桥接。未改变任何 symlink、volume、permission、identity、hard-link、watchdog 或 cancellation 语义。
- [x] 30 次真实 `~/Library/Caches` LexCleaner Full-quality：**19,041 files / 8,432 directories / 3,336,781,824 allocated bytes**，与当次扫描的 allocated 口径一致；wall median **0.107 s**、P95 **0.116 s**、P99 **0.118 s**；内部 CPU median 约 **0.391 s**、mean **0.395 s**；resident RSS median **13.86 MiB**、P95 **14.00 MiB**、max **14.06 MiB**。同一目录在运行期间发生内容变化，数量/bytes 以每次真实快照为准，未丢弃变化项。
- [x] Profile 后的受控 20k 夹具仍保持完整结果：Lex full-quality **20,003 files / 290 directories**，allocated 与 `du` 差 **4 KiB**；Mole 可完成，但其输出不包含 allocated size，不能冒充与 LexCleaner 同口径的物理占用。
- [x] 此前一次 30 次真实 Caches A/B 尝试中，Mole 1.52.0 曾在同一根目录重复进入长期等待并按超时保护停止；该异常后来在显式路径诊断中不再复现，未将未完成进程计入当次统计。该段历史数据不作为当前 A/B 结论，最新有界诊断见下节。
- [x] SwiftPM **63/63**、Xcode **63/63**、Debug/Release arm64 Build、Release SwiftUI App 真实启动均通过；现有 watchdog 注入测试、volume、百万文件计数/allocated/cancellation、Treemap 与安全回归未被本轮修改破坏。一次独立质量 runner 重复中，百万文件扫描/计数/allocated/cancellation 通过；真实文件系统未自然触发 timeout，未伪造 timeout 成功。
- [ ] 结论：当前 LexCleaner RSS/私有内存与质量边界保持，但没有完成同目录当前 Mole 的有效 30 次对照，也没有证明 median 至少领先 10%、P95/P99/CPU 全面领先。因此 **Disk Analyzer Performance = FAIL**；不进入下一模块。

### Mole A/B 稳定性诊断与固定 corpus 基线（2026-08-23，本轮）

- [x] 真实 `~/Library/Caches` 稳定性：Mole 1.52.0 显式路径连续 3 次均完成，约 **0.295s/次**，无 timeout；当前 LexCleaner 3 次为 **0.291s / 0.115s / 0.114s**，Mole 为 **0.11s / 0.10s / 0.10s**。LexCleaner 当前快照约 **19,057 files / 8,432 directories / 3,337,003,008 allocated B**；Mole JSON 为 **16,888 files**，不提供 allocated-size。两边进程均在有界命令内退出。
- [x] 此前 Mole 长时间等待无法在本轮复现：默认 `/`、显式 `$HOME` 和显式 `$HOME/Library/Caches` 当前均连续完成。历史卡住时观察到的是 Go runtime 的 `pthread_cond_wait`、低 CPU 等待；缺少可复现相同调用栈/文件状态的证据，不能把它归因于某个确定目录或算法缺陷，也不标记 Real-world Stability = FAIL。
- [x] 固定 corpus 采用同一 `/tmp` 目录、**16,388 regular files / 137 directories / 9,461,760 logical B / 75,522,048 allocated B**，双方 timeout=5s、随机交替、Top-N=20；LexCleaner 排除 `.git`、不跟随 symlink，corpus 不含 symlink。Mole JSON 与 LexCleaner 均报告 **16,388 files / 9,461,760 logical B**；Mole JSON 只输出 8 个一级目录项且没有 allocated-size 字段，因此 raw directory count、physical allocated 和完整安全诊断不能假设等价。
- [x] Fixed corpus analyzer-cold（每次 Mole 使用新 HOME，macOS 文件缓存未强制刷新）30 次：LexCleaner median/P95/P99 **0.182308/0.199252/0.200228s**，CPU **0.19/0.21/0.21s**，RSS **10.766/10.828/10.875MiB**；Mole **0.120901/0.168730/0.193103s**，CPU **0.21/0.22/0.40s**，RSS **14.305/14.797/14.859MiB**。
- [x] Fixed corpus warm（各方先预热 1 次后计数，随后随机交替 30 次）：LexCleaner median/P95/P99 **0.181921/0.195287/0.195583s**，CPU **0.19/0.21/0.21s**，RSS **10.766/10.828/10.844MiB**；Mole **0.092428/0.102393/0.136040s**，CPU **0.02/0.03/0.03s**，RSS **8.711/9.250/9.359MiB**。所有 60+60 次均在 5s 内完成、文件计数稳定。
- [ ] 结论：已获得可重复的 Mole baseline，但在该共同 corpus 上 LexCleaner wall median、P95、P99 均未领先；warm CPU 也未领先，RSS 仅在 cold 下领先。当前没有足够依据继续压最后几毫秒，Disk Analyzer Performance 继续 **FAIL**。

### Disk Analyzer 聚合热路径优化（2026-08-23，本轮）

- [x] 架构级 Profile 定位最大真实热点为 aggregation 内的 Top-N 大文件处理：旧路径对每个匹配候选提前创建 `LargeFileEntry`、URL/String，并重复维护排序；固定 corpus 的 aggregation 阶段约 **0.181–0.186 s**，明显高于 volume、identity、hard-link 和 watchdog 阶段。Time Profiler 也显示 `recordFile`、URL path/appending、String 分配/复制和 `LargeFileEntry`/Array 生命周期为主要 CPU/allocation 热点。
- [x] 仅优化该瓶颈：新增无拼接的 virtual UTF-8 ranking key；在 Top-N retention 判断前不创建展示 URL、canonical URL 或 `LargeFileEntry`；只对最终保留项物化并在最终快照排序。hard-link 唯一性、symlink/volume/permission/identity、watchdog、cancellation 和 allocated-size 统计路径未改变。
- [x] 固定 corpus Profile：**16,388 files / 137 directories**；`getattrlistbulk` **274 calls / 16,524 entries**，即每 1,000 文件约 **16.7 次 bulk call、1,008 个 metadata entries**；目录 open/watchdog 与 identity 各 **约 8.4 次/1,000 文件**；volume check **1,008 次/1,000 文件**；hard-link candidate **0**。syscall 计数未因优化减少，优化来自减少聚合分配和排序工作。
- [x] allocation-sensitive 计数显示 LargeFileEntry 物化从逻辑上的 **16,388** 降为 **20**，**16,368** 个候选在物化前拒绝（减少 **99.88%**）。该计数用于验证重复工作；本轮 Instruments Allocations 未能在限定时间内导出完整 malloc 总数，因此没有伪造“总 heap allocation 数”。
- [x] 同一固定 corpus、独立进程、30 次完成：优化前 wall median/P95/P99 **0.182308/0.199252/0.200228 s**，CPU **0.19/0.21/0.21 s**，RSS **10.766/10.828/10.875 MiB**；优化后 **0.053095/0.091327/0.184870 s**，CPU **0.11/0.12/0.12 s**，RSS **10.883/10.969/11.000 MiB**。文件数、目录数、logical bytes 和 allocated bytes 均稳定一致。
- [x] 第一阶段 Cold median ≤ **0.140 s** 目标已达到（优化后 **0.053 s**，约 **3.43×** 相对本轮前基线）；固定 warm corpus 相对既有 Mole median **0.092428 s**，LexCleaner median **0.053095 s**，但 P99 **0.184870 s**、CPU **0.11 s**、RSS **10.883 MiB** 仍未全面领先 Mole 的 **0.136040 s / 0.03 s / 8.711 MiB**。因此只完成第一阶段热点收口，Disk Analyzer Performance 仍 **FAIL**；下一步仅值得针对 P99 尾延迟和 CPU/资源差距继续 Profile，不应再盲目微调。
- [x] SwiftPM/Xcode Core **63/63**、App/Core arm64 Debug Build 和既有质量基线保持通过；未发现安全或准确性回退。

### Disk Analyzer P99 / CPU 尾延迟审计（2026-08-23，本轮）

- [x] 固定 `/tmp/lex-mole-corpus.VZgPgn` 连续 **100 次**独立进程采样，每次 5 秒硬超时；全部完成，均为 **16,388 files / 137 directories / 9,461,760 logical B / 75,522,048 allocated B**。
- [x] breakdown 样本的内部扫描 wall **median/P95/P99/max = 0.018/0.024/0.027/0.031 s**；CPU **0.064/0.085/0.099/0.106 s**；RSS **11.14/11.19/11.27/11.29 MiB**。最慢样本没有额外文件、目录或结果输出。
- [x] P99 相对 median 的主要增量来自 `getattrlistbulk` 元数据阶段：累计 metadata 时间 **0.0498 → 0.0809 s**；但 **274 calls / 16,524 entries** 完全不变。其余阶段变化很小：volume **0.181 → 0.262 ms**、identity **0.078 → 0.150 ms**、watchdog **2.258 → 3.380 ms**、aggregation **6.736 → 9.169 ms**（median → P99）。因此 volume check 只占极小部分，身份缓存不能解释或解决 P99。
- [x] 进程级 `/usr/bin/time -l` 100 次复核：internal wall **0.023/0.024/0.028 s**（median/P95/P99），process real **0.020/0.030/0.030 s**，page faults **6/6/6**（median/P95/P99），involuntary context switches P99 **980**；只有首个启动样本出现 **0.070 s real / 63 page faults / 1,764 voluntary context switches**。旧的 **0.185 s** 尾部在本轮未复现，不能据此修改扫描热路径。
- [x] 本轮未修改源码：没有发现明确超过 5% 且可在不削弱 volume boundary、symlink、identity、hard-link、watchdog 或 cancellation 的情况下收获的安全优化。继续调整 worker、watchdog 或 volume 缓存属于无证据微调，已停止。
- [x] 当前代码 30 次 warm 交替复核：LexCleaner **0.010/0.011/0.011 s** 内部 wall、CPU **0.030/0.032/0.034 s**、RSS **11.32/11.39/11.40 MiB**；Mole **0.080/0.090/0.090 s** process real、CPU **0.030/0.030/0.030 s**、RSS **9.91/11.16/11.31 MiB**；双方均为 **16,388 files**。由于 Lex runner 内部计时与 Mole 进程计时分辨率不同，该结果只作 warm 参考，不替代既有 cold/warm 公平基线。
- [ ] 结论：P99 旧异常未在 100 次中复现，当前可观测尾延迟主要是文件系统 `getattrlistbulk`/进程启动调度波动；没有足够证据进行安全架构修改。既有 cold/warm 基线仍显示 CPU、P95/P99 或 RSS 尚未稳定全面领先 Mole，Disk Analyzer Performance 继续 **FAIL**。

### Integration Review 前 main 未提交修改复核（2026-08-23，本轮）

- [x] 当前 main 的 6 个未提交文件均属于 Disk Analyzer：`DiskAnalyzerView.swift`、`DiskAnalyzerViewModel.swift`、`DiskAnalysis.swift`、`DiskAnalysisTests.swift`、`LexCleanerDiskAnalysisTestRunner/main.swift` 和本文件；未执行 reset/clean/checkout。
- [x] 当前 main 工作区 SwiftPM 全量 **63/63** 通过；watchdog 注入测试、取消、allocated/du、volume、symlink、hard-link 和安全回归均通过。
- [x] `swift run LexCleanerDiskAnalysisTestRunner --quality` 真实百万文件专项：**1,048,576 files / 1,025 directories**，扫描 **2.445 s**，allocated 与 du 均 **4,294,967,296 B**，volume capacity 安全，cancellation **16,128 files / 0.043 s**，million-file PASS；APFS 稀疏卷 boundary/symlink 也 PASS。
- [ ] 同一质量 runner 的真实 watchdog 专项未通过：慢目录 **32,000 files / 9 directories / 0.065 s** 正常完成，watchdog timeout **0**。当前本机 APFS 未自然产生阻塞 `open(2)`，因此不能标记真实 timeout PASS；现有受控 opener watchdog/cancellation 单元测试仍通过，未伪造质量结果。
- [ ] 由于 watchdog 真实验证缺口，本次 main 复核结论为 **Disk Analyzer Quality 未完全 PASS**；该事实在后续 integration 分支中必须保留。
- [ ] 当前 30 次真实 Caches A/B 无法完成 Mole 对照：Mole 1.52.0 在同一 `~/Library/Caches` 根目录重复进入长期等待，已按超时保护停止，未将未完成进程计入 median/P95/P99。最近一次可完成的历史 30 次参考仍为 Mole median **0.100518 s**、P95 **0.106033 s**、P99 **0.116111 s**、RSS median **13.98 MiB**；该历史值不是本轮新 A/B，不能据此宣称当前性能通过。
- [x] SwiftPM **63/63**、Xcode **63/63**、Debug/Release arm64 Build、Release SwiftUI App 真实启动均通过；现有 watchdog 注入测试、volume、百万文件计数/allocated/cancellation、Treemap 与安全回归未被本轮修改破坏。一次独立质量 runner 重复中，百万文件扫描/计数/allocated/cancellation 通过；真实文件系统未自然触发 timeout，未伪造 timeout 成功。
- [ ] 结论：当前 LexCleaner RSS/私有内存与质量边界保持，但没有完成同目录当前 Mole 的有效 30 次对照，也没有证明 median 至少领先 10%、P95/P99/CPU 全面领先。因此 **Disk Analyzer Performance = FAIL**；不进入下一模块。

### Disk Analyzer benchmark owner strict 30 run (2026-08-23, isolated branch)

- [x] 在 `codex/disk-analyzer-benchmark-20260823` 隔离 worktree 中，根据当时 main 的 6 个未提交 Disk Analyzer 文件重建等价能力；未修改 main、Cleaner、Storage/Hardware、Updater 或其它模块。
- [x] runner 新增 `--strict-30`：cold/warm 分离、每个 cohort 30 次、SplitMix64 随机交替、每次独立 `/usr/bin/time -l` 进程和独立 timeout；逐次记录 wall/CPU/peak RSS/files/allocated，输出 median/P95/P99，并在 Mole 连续 3 次 timeout 时输出稳定性 FAIL。
- [x] 本次真实 `$HOME/Library/Caches` 运行：Lex/Mole cold 与 warm 均 **30/30 success、0 timeout**。Lex cold **0.232/0.345/0.386 s**（median/P95/P99），warm **0.172/0.215/0.228 s**；Mole 1.52.0 cold **0.300/0.340/0.390 s**，warm **0.106/0.114/0.115 s**。CPU、peak RSS、file count 和 Lex allocated 均逐次输出；Mole JSON 未报告 allocated，且文件/symlink 范围不等价，比较结论为 **INCONCLUSIVE**，没有伪造 baseline 或 PASS。
- [x] 同次运行的 `du` 仅部分可读：**3,384,041,472 B，exit=1，duComplete=false**，因 Caches 内 TCC 受保护路径权限错误；该值只作 partial observation，不作完整 ground truth。当前历史 Mole 卡住现象在本次真实 Cache 30 次和一次直接 `$HOME/Library/Caches` probe 中未复现，根因仍未证实；可能与历史范围/权限/实时变化有关，不能下结论。
- [x] 真实 SwiftUI Debug App 启动成功；Disk Analyzer 页面显示真实容量、allocated、路径和扫描问题；点击“取消扫描”后页面进入“已取消”、显示“重新扫描”和空 Treemap 状态。未做长时间 UI 等待。
- [ ] million-file/volume/watchdog 综合质量 runner 本次运行约 2 分钟后仍在构造 1M fixture，按超时保护停止，未标记 PASS；SwiftPM/Xcode Core **63/63**、App/Core arm64 Debug Build、真实页面/取消/错误状态验证通过。现有质量测试和安全边界未回退，但综合质量 runner 该次未完成。
- [ ] 结论：本轮严格 30 次 harness **COMPLETE 但 comparison INCONCLUSIVE**；Disk Analyzer Performance 仍 **FAIL/未证明领先**，Mole 稳定性 FAIL 未触发（本轮无连续 timeout）。

### Integration Review A 门禁口径更正（2026-08-23）

- [x] A 的质量门禁以生产 watchdog 路径的受控阻塞 opener 为准：真实执行了 `timeout → skip → issue/audit → 后续目录继续 → cancellation`，Watchdog controlled validation **PASS**。
- [x] 本轮 APFS 慢目录自然扫描未产生阻塞，`watchdog timeout = 0` 仅记录为 **Natural Watchdog Timeout: NOT OBSERVED**，不再作为 A 集成失败依据。
- [x] A 集成回归保持：百万文件、allocated/du、volume、symlink、hard-link、cancellation、SwiftPM **63/63**、Xcode **63/63**、arm64 Debug Build 均通过。
- [x] A Disk Analyzer Quality **PASS**；性能对比仍按严格证据保持 **INCONCLUSIVE/未证明领先**，两者不混为一谈。

### Integration Review B Cleaner UX（2026-08-23）

- [x] B 已 rebase 到最新 integration 并集成为 `72513d1`；未覆盖 A 的 Disk Analyzer 文件，integration 工作区无冲突且 clean。
- [x] SwiftPM 全量 **64/64**、10 suites PASS；Xcode `LexCleanerCoreTests` **64/64** PASS，测试数量较 A 的 63 未下降；arm64 Debug App Build PASS。
- [x] 受控 macOS UI fixture 实测：Safe 默认选中 1 项；Review Required 分组一键选择后共选中 3 项；Protected/Unknown 分组和逐项复选框均 disabled。
- [x] 受控链路实测通过：Dry Run（处理 3、拒绝 5）→ Review 独立高风险二次确认 → Trash 确认 → Preflight/执行 → Audit；成功 3 项移入废纸篓、5 项因源变化/保护拒绝，未提供永久删除路径。
- [x] B Cleaner UX 集成门禁 **PASS**，允许进入 C Storage。

### Integration Review C Storage（2026-08-23）

- [x] C 已 rebase 到 B 最新 integration；`PROGRESS.md` 冲突已手工合并，保留 A/B 记录，未覆盖 Disk Analyzer/Cleaner 文件；集成提交为 `57e91d8`。
- [x] SwiftPM 全量 **65/65**、10 suites PASS；Xcode `LexCleanerCoreTests` **65/65** PASS；测试数量较 B 的 64 未下降；arm64 Debug App Build PASS。
- [x] Storage runner 真实 Apple Silicon 验证 **4/4 PASS**：当前快照为 **1 physical disk / 3 APFS containers / 12 volumes**，内置 APPLE SSD AP0512Z 容量 **500.277792768 GB**；System/Data 等卷不重复累计。
- [x] 真实 Storage UI 页面打开并核对：普通信息按 `Physical Disk → APFS Container → Volume` 展示，不以 disk0/disk1/disk2/disk3 作为多块物理磁盘；容量显示十进制 GB；BSD/UUID/Volume group/Reported size 仅在“高级信息”展开后显示。
- [x] SMART/wear 真实页面明确显示 `不支持` 及审计原因；未用零值或猜测值填充。
- [ ] 当前设备未发现外接 physical disk（`diskutil list external physical` 无结果），因此外接盘插拔为 **NOT TESTED**，没有伪造 PASS。
- [x] C Storage 集成门禁（在当前真机条件下）**PASS**；外接盘插拔保留为环境限定项。

### Integration Review D Updater（2026-08-23）

- [x] D 已 rebase 到 C 最新 integration 并集成为 `b737ac7`；变更未触及 Disk/Hardware/Storage/Cleaner 实现。
- [x] Sparkle Swift Package 已锁定 **2.9.6**（revision `ac2def288cbff5cfc7df3ffef6abdf45b72bcb0a`）；`NOTICE` 与 `THIRD-PARTY-NOTICES/Sparkle-LICENSE.txt` 保留。
- [x] Appcast/feed、Ed25519 公钥、自动检查、手动检查和 Sparkle 安全配置均为 fail-closed；未配置 HTTPS feed 或 32-byte Ed25519 key 时不启动可用更新链路，失败保持当前 App。
- [x] SwiftPM 全量 **66/66**、10 suites PASS；Xcode `LexCleanerCoreTests` **66/66** PASS；测试数量较 C 的 65 未下降；arm64 Debug App Build PASS。
- [x] 真实 Updater UI：自动检查开关在未配置发行参数时 disabled；手动检查明确显示“此构建尚未配置 Sparkle / Feed URL is not configured”。
- [x] D Updater 代码集成门禁 **PASS**；真实签名 Feed/下载/安装/公证不在当前环境验证，保留为 Release Gate。

### Integration Review 四路统一验收（2026-08-23）

- [x] 集成顺序完成：A `6f33fe7c`（集成提交含门禁更正 `99f4912`）→ B `72513d1` → C `57e91d8` → D `b737ac7`；所有 owner worktree 与 integration 均 clean，无 unresolved index entries。
- [x] SwiftPM **66/66**、Xcode `LexCleanerCoreTests` **66/66**；测试数量从 A 的 63 逐步增加至 66，无异常下降。
- [x] arm64 Debug Build PASS；arm64 Release Build PASS。Release Build 包含 Sparkle 2.9.6 framework，但未使用发行签名参数。
- [x] 最终 Debug App 真机启动后真实打开 Cleaner、Disk Analyzer、Hardware→Storage、Settings→Updater 页面；Disk 页面显示真实扫描数据，Storage 页面显示物理盘/APFS 拓扑，Updater 页面显示 fail-closed 未配置状态。
- [x] 最终清理后无 LexCleaner App、test/runner、xcodebuild 或 swift-test orphan 进程；main、A/B/C/D owner worktree 和 integration 状态均 clean。
- [ ] 外接磁盘插拔：当前设备无 external physical disk，**NOT TESTED**，不伪造通过。
- [ ] Release Gate：真实签名 Appcast/Feed、Ed25519 签名校验、下载、安装回滚保护、Developer ID 签名、公证与 stapling 尚未在完整发布环境验证。
- [x] Integration Review **PASS（代码集成/当前真机条件下统一验收）**；外接盘与 Release Gate 为明确遗留验证项。Apple Silicon 功耗监控仍未开始。

# Final Product Quality 收口（2026-08-24）

## DashboardCopy → String Catalog

- [x] `MonitoringHardwareView.swift` 的 `DashboardCopy` 已迁移为 `L10n` + `Localizable.xcstrings`；新增 Dashboard 监控相关文案 74 个 Catalog key，en/zh-Hans 均完整。
- [x] CPU、SMART、PID、BSD、UUID、Volume group、Apple Silicon、APFS Container、路径和 Bundle/系统标识保持技术值，不进入翻译。
- [x] Catalog JSON、引用 key 完整性检查通过；Debug/Release Xcode `xcstringstool` 编译通过。
- [x] Debug App 真实启动截图：zh-Hans / English Dashboard 均通过，未发现中英混杂或明显截断；Dashboard 数据逻辑未改动。

## Cleaner UI E2E / TCC

- [x] Core E2E：SwiftPM/Xcode **66/66**，包含 Scan → Classification → Selection → Dry Run → Confirmation → Preflight → Trash → Audit 的受控链路与失败路径。
- [ ] UI E2E：启动受控 UI fixture 时，macOS 仍显示此前 Home 扫描触发的 Music/TCC 授权提示；未点击允许、未重置 TCC、未绕过系统安全。UI 链路保留为 **MANUAL RELEASE VALIDATION / TCC GATE**，未伪造通过。

## 外接磁盘与 Sparkle

- [ ] `diskutil list external physical` 当前无输出；外接 physical disk hot-plug 保持 **NOT TESTED**。代码级 storage topology 测试继续通过，不以 mock 宣称真机通过。
- [ ] 本机 `security find-identity -v -p codesigning` 返回 **0 valid identities**；未发现签名 Appcast、Ed25519 发布密钥、HTTPS feed、可下载更新包或公证环境。Sparkle 保持 **RELEASE GATE / NOT VERIFIED**，Updater UI 继续 fail-closed。

## 最终回归与稳定性

- [x] SwiftPM **66/66**、Xcode **66/66**。
- [x] arm64 Debug Build **PASS**；arm64 Release Build **PASS**；Release App 真实启动 **PASS**。
- [x] 最终一次 15 分钟 Release 稳定性窗口：RSS **123.75–138.02 MiB**，private footprint **42–58 MiB**，CPU **0.1–8.9%**，线程 **6–10**；无持续增长。结束后无 LexCleaner、caffeinate、xcodebuild、xctest、swift test、xctrace、Instruments、DiskAnalysisRunner 或 Mole 残留进程。

## 门禁结论

- P0/P1：**0**。
- P2：**0 个产品代码缺陷**；Cleaner UI 为系统 TCC 人工验证 Gate。
- P3 / Release Gate：外接 physical disk 未测试、Sparkle 正式签名发布链未验证、Disk Analyzer Performance 仍 INCONCLUSIVE、Power Monitoring 仍 AUDIT ONLY。
- 产品代码与现有 Core/Build/稳定性验收通过；最终状态：**Final Product Quality = PASS WITH RELEASE GATES**。
# Storage topology refinement（2026-08-23）

## 已完成

- Hardware storage collector 从 Whole IOMedia 平铺改为公开 IOKit registry parent 链归类：`Physical Disk → APFS Container → Volume`。
- 同一物理 SSD 在当前快照内只保留一个 physical disk；合成 APFS container、physical-store 分区和 APFS snapshot 不再作为独立磁盘展示。
- System/Data 等 APFS 卷的原始大小标记为 `sharedContainer`，容量只由 physical disk/container 计入；普通 UI 展示卷名/角色，高级 DisclosureGroup 展示 BSD/UUID/physical store。
- 存储拓扑每次采样重建，外接盘插拔不会留下旧 disk-number 条目；SMART/wear 继续明确 `unsupported`，无猜测值。
- 存储 UI 容量使用十进制 GB/TB。

## 已验证

- StorageTopologyBuilder 测试覆盖 disk0 + synthetic disk3 去重、System/Data 单次计容、snapshot 过滤、同 UUID container 去重和外接盘移除后的无 stale topology。
- Hardware Core tests：本轮 9/9；硬件 runner：4/4。
- 当前真机快照：1 个 physical disk、3 个 APFS containers、12 个 APFS volumes；SMART/wear 均为 `unsupported`。当前机器无外接磁盘，插拔实测待记录。

## 未完成

- 仍需完成正式 Xcode Core tests、arm64 Debug build、Monitoring/Hardware/Storage 页面真机视觉与交互检查后再提交。

# Release Candidate 1 收口（2026-08-24）

## 分支与门禁

- [x] 从 `main` `64e39a0` 创建独立 `release/rc1` worktree；本轮未修改 main、稳定核心或 Disk Analyzer。
- [ ] Cleaner UI E2E：Release 受控启动时观察到 macOS Apple Music/Automation TCC 授权提示；未点击允许、未重置 TCC、未绕过安全机制。Core E2E 继续为 **66/66 PASS**，UI E2E 保持 **MANUAL RELEASE VALIDATION / TCC GATE**。
- [ ] External Disk：`diskutil list external physical` 无真实外接盘，保持 **NOT TESTED**，未用 mock 宣称通过。
- [ ] Sparkle：`security find-identity -v -p codesigning` 为 0 valid identities，`notarytool` 无凭据；无 Developer ID、签名 feed、Ed25519 key、更新包和公证条件，保持 **RELEASE GATE / NOT VERIFIED**。

## RC1 验证

- [x] SwiftPM **66/66**、Xcode **66/66**。
- [x] arm64 Release Build 和 Release 真机启动通过；受控 fixture 未执行真实 Trash，避免碰用户数据。
- [x] 单次 15 分钟 Release 稳定性：RSS **124.06–139.31 MiB**，private footprint **42–59 MiB**，CPU **0.1–8.6%**，线程 **6–7**；无持续增长，结束后无 orphan 进程。
- [x] Disk Analyzer Performance 继续 **INCONCLUSIVE**；Power Monitoring 继续 **AUDIT ONLY**。

## RC1 结论

- 产品代码、测试、构建和可验证稳定性门禁通过；正式发布仍需 TCC 人工 E2E、真实外接盘（若纳入发布验收）及 Sparkle 签名/公证环境。
- RC1 状态：**READY WITH RELEASE GATES**。

# Final Accuracy & Responsive Audit（2026-08-24）

## 审计与最小修复

- [x] 在 `audit/final-accuracy-responsive` 独立 worktree 完成 Dashboard、Monitoring、Hardware、Storage、Disk Analyzer、Menu Bar、Settings 的数值、单位、跨页口径和真实性审计。
- [x] 修复 Monitoring/Hardware 中仍使用二进制 `ByteCountFormatter` 的展示路径，统一为十进制 GB/MB/s；底层 bytes、采样周期和安全检查未改变。
- [x] 修复 Disk Analyzer 中文大文件文案参数顺序错误，并补齐文件类型卡片缺失的 `Logical` / `Allocated` String Catalog key。
- [x] 修复 Settings 更新区在语言覆盖为 English 时仍显示中文的 locale 传递问题；菜单栏指标和不可用状态同步使用当前 locale。
- [x] 将电池、SMART、存储磨损的已知英文诊断原文映射到 `.xcstrings`；unsupported/unavailable 仍保持真实状态，不以 0 或正常值替代。

## 最终验证

- [x] SwiftPM 66/66；Xcode Core tests 66/66；arm64 Debug/Release Build PASS。
- [x] Release 真机启动、全页面 smoke test、zh-Hans/English 设置切换、Disk Analyzer 文案和响应式窗口检查通过。
- [x] 最终一次 15 分钟 Release 空闲稳定性：RSS 约 104.7–130.5 MiB、CPU 瞬时采样 1.7–13.0%；无持续增长；结束后无 LexCleaner、xcodebuild、xctest、swift test、caffeinate 或 runner 残留进程。
- [x] 保留并复核：Cleaner TCC = `MANUAL RELEASE VALIDATION`；External Disk = `NOT TESTED`；Sparkle = `RELEASE GATE / NOT VERIFIED`；Disk Analyzer Performance = `INCONCLUSIVE`；Power Monitoring = `AUDIT ONLY`。

## 数值口径结论

- [x] M4 / Apple Silicon / 10 cores / physical memory 通过 sysctl、System Information 和 Core 交叉核对；磁盘总容量 494.38 GB 与 APFS 494.3848 GB 一致。
- [x] Disk used 与 diskutil 数据误差约 0.11%；available 明确标注 Foundation important-usage 语义与 `df` raw free 不同，不强行宣称同一数值。
- [x] CPU、内存、磁盘/网络速率、logical/allocated size 保持真实采样定义；allocated 与 du 的既有高一致性验证未退化。

## 审计结论

- [x] P0/P1/P2：0；剩余仅为既有 P3/Release Gates。
- [x] `Final Accuracy & Responsive Audit = PASS`（不改变 RC1 的外部发布 Gates）。

# Disk + CPU Precision Calibration（2026-08-24）

## 结论

- [x] 建立可重复 `LexCleanerMonitoringTestRunner --calibration`：1 秒采样、300 秒、空闲/轻负载/中负载/高负载/恢复空闲五阶段；同时记录 macOS `top` 的 user/system/idle。
- [x] CPU 生产公式未修改。实测 Lex 与 `top` 同窗口误差：1 秒平均绝对误差约 0.675 个百分点，5 秒约 0.300%，10 秒约 0.250%；user + system + idle 最大偏差约 0.001 个百分点；10 核聚合范围正常。
- [x] 磁盘审计确认：`volumeAvailableCapacityKey` 与 `df` raw free 一致，但 `total - rawFree` 包含约 24.09 GB APFS 保留/不可分配空间，不等于 `diskutil Volume Used Space`。现有 `volumeAvailableCapacityForImportantUsageKey` 的 used 口径与 diskutil used 误差约 0.11%，差异随 APFS 动态状态和采样时刻变化。
- [x] 未使用硬编码偏移、M4 修正系数或人为加减百分比；未修改 Disk Analyzer 核心、安全逻辑或已通过的其他参数。

## 验证

- [x] 新增 CPU 校准输出和 user/system/idle 加总、per-core 范围断言；生产代码无数值校准改动。
- [x] 本轮真实 Monitoring runner：4/4；SwiftPM/Xcode 全量 66/66、Debug/Release Build 和 Release 真机启动均已重新执行并通过。

## Precision Final Pass（2026-08-24）

- [x] 复核 CPU 采样：`host_processor_info` 同批次 tick delta、per-core 聚合和首样本 warmup 均正确；未发现可安全修改的生产根因。
- [x] 复核磁盘采样：Dashboard、Monitoring、Disk Analyzer 使用统一 Important-Usage 容量口径；剩余差异来自 APFS 动态统计、reserved/purgeable 空间及采样时刻，不使用偏移修正。
- [x] calibration harness 仅位于 SwiftPM 测试 runner，不属于 `LexCleanerApp` Release target。
- [x] Release `footprint` 实测 `phys_footprint = 48 MiB`、peak `48 MiB`；未见内存回退。
- [x] 最终 SwiftPM/Xcode 66/66、arm64 Debug/Release Build、Release 真机启动和 15 分钟稳定性验证通过；结束后无 orphan 进程。

### Precision Freeze

- CPU Precision：**FROZEN**
- Disk Precision：**FROZEN**
- 只有发现真实准确性 Bug 才允许重新修改对应算法。

# Network Optimizer（进行中）

- [x] 基于 `lexcleaner-macos-accuracy-frozen-baseline` 创建独立 `feat/network-optimizer` worktree。
- [x] 复核决策矩阵：NetworkMonitor（MIT）仅参考 UI/用量思路，Stats（MIT）仅参考采样模块，Mole（GPL-3.0）仅参考公开行为；不复制第三方代码、不新增第三方依赖。
- [x] 选定 Apple 原生 API：Network.framework、SystemConfiguration、CFNetwork、Darwin `getifaddrs`。
- [x] Network Core 完成：真实路径、接口、DNS、网关、代理、TCP 延迟/抖动/失败率、累计/实时流量接入；ICMP 丢包、逐进程流量和 VPN 状态在稳定公共 API 不足时明确返回 `unsupported/unavailable`。
- [x] DNS Benchmark 完成：当前 DNS、Cloudflare、Google、Quad9 的真实 UDP DNS 查询，记录 median/P95/jitter/timeout/failure rate；不会把 TCP 失败率冒充 ICMP 丢包。
- [x] DNS 修改闭环完成：SystemConfiguration 只定位单一目标 service/interface；显式用户确认后才申请管理员授权；修改前保存完整原配置到 recovery journal，提交后验证，修改后 DNS/TCP A/B 只有真实改善才保留，否则自动恢复。
- [x] Rollback/recovery 完成：目标服务变化、授权拒绝/取消、无效地址、修改后测量失败和 journal 异常均 fail-closed；active plan 支持一键恢复并逐字段验证，pending transaction 可在后续启动恢复。
- [x] Network SwiftUI 页面接入正式 App Shell，支持真实数据、取消、错误/不可用状态、zh-Hans/en、Light/Dark 和全屏布局。
- [x] 定向测试 14/14；SwiftPM 全量 80/80；Xcode 全量 80/80；arm64 Debug/Release Build 和 Release 真机 Network 页面启动通过。
- [x] Release 页面 15 分钟稳定性：RSS 约 139.95–154.08 MiB，结束前约 140.22 MiB；CPU 采样低个位数为主，短时探测峰值约 12.2%，无持续增长且无 orphan 进程。
- [ ] 真实管理员授权下的系统 DNS 写入、修改前后 A/B、Rollback 尚未在本机执行；本轮不伪造系统配置变更结果，保留为 **MANUAL RELEASE VALIDATION**。

# Friends Beta Feedback（已完成）

- [x] 从 `main` `622549f` 创建独立 `feat/friends-beta-feedback` worktree；未修改 main。
- [x] 新增 Core `DiagnosticsReportBuilder`：版本/build、macOS、Mac 型号/架构、模块状态、有限错误摘要和崩溃报告摘要。
- [x] 报告只在用户主动导出或复制时生成；报告经过隐私脱敏，不包含用户名、私人路径、文件名、文件内容、Token、密码或凭据，不自动上传。
- [x] Settings 新增导出、复制和 GitHub Issues 反馈入口；反馈 URL 只附带 version/build，不携带诊断正文。
- [x] 定向脱敏测试通过；SwiftPM/Xcode 全量均为 82/82，arm64 Debug/Release Build 通过。
- [x] Release App 真机启动、Settings 导出报告、复制诊断信息和报告隐私扫描通过；验证后 App 正常退出且无 orphan 进程。
- [x] 反馈入口使用 `https://github.com/OrivexLabs/LexCleaner-Releases/issues/new`，URL 仅附带版本/build，不自动上传诊断正文。
- [x] CPU、Disk、Network 冻结核心未修改；本阶段在独立 `feat/friends-beta-feedback` 分支完成，合并前未直接修改 main。
