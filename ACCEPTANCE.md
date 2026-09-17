# 当前阶段验收标准

## 发行审计边界（2026-09-17）

历史条目保留其当时的时间范围和证据，不自动代表当前发行物已验证。当前发行
必须同时具备 exact-tree 的完整 Xcode App build、真实安装/启动和关键用户路径、
TCC/权限边界、Developer ID 签名、Gatekeeper assessment、notarization/stapling、
以及 Sparkle signed appcast/update 安装证据；缺少任一必需证据时保持 **BLOCK**。

## 必须通过

- [x] 创建正式 LexCleaner macOS 工程与 SwiftUI App 入口。
- [x] 建立 `LexCleanerCore` 模块和后续服务扩展目录边界。
- [x] 创建项目目标、架构、验收、进度和项目级 AGENTS 文档。
- [x] 空路径、相对路径和不存在路径拒绝。
- [x] 根目录、当前用户 Home 和系统关键目录拒绝。
- [x] 白名单边界检查，且白名单不能覆盖硬保护目录。
- [x] 标准化路径与实际 symlink 解析。
- [x] 用户 symlink 越界拒绝，内部 symlink 标记 Elevated 风险。
- [x] Dry Run 不改变文件系统。
- [x] 真实模式使用 `FileManager.trashItem`，不直接永久删除。
- [x] 成功、拒绝和失败路径写操作日志。
- [x] Trash 执行前二次 canonicalize/resolve、保护检查和目标/symlink 身份比较。
- [x] 路径或对象身份变化时 fail-closed；真实路径替换测试通过。
- [x] 真实测试覆盖正常路径和危险路径。
- [x] Apple Silicon Swift 构建与真实测试 runner 通过。
- [x] 完整 Xcode/xcodebuild 构建、App/Core arm64 Debug、19 个 Xcode 测试和真实 SwiftUI App 启动已通过。

## 原生 API 限制

`FileManager.trashItem` 的最终路径操作无法由应用在检查与系统调用之间提供跨进程原子保证。当前策略已通过二次评估、inode/device 身份比较和变化即拒绝把风险降到 fail-closed；该残余限制不应在后续产品文档中被描述为“完全消除”。

## 第二阶段 ScanEngine 验收

- [x] `ScanRule`、`ScanTarget`、`ScanResult`、`ScanIssue`、`RiskLevel`、`Category` 模型。
- [x] 多目录扫描、文件/目录统计、大小、修改时间、文件类型。
- [x] User Cache、Application Cache、Logs、Temporary Files 首批规则。
- [x] symlink 叶子处理、越界记录、循环不递归。
- [x] 权限错误记录、不可访问目录跳过、不存在/系统/个人数据路径保护。
- [x] Swift Concurrency、取消、进度回调、并发上限、canonical 去重。
- [x] 流式条目回调；ScanResult 不保存整棵文件树。
- [x] 大量文件真实测试、耗时和 resident-memory high-water 趋势记录。
- [x] ScanEngine 与 SafeDeleteEngine 完全解耦。
- [x] 不实现 Cleaner UI、Dashboard 或删除按钮。

## 第三阶段 ClassificationEngine 验收

- [x] `CleanerRule`、`CleanerCandidate`、`CleanerCategory`、`CleanupSafetyLevel`、`CleanupReason`、`ExclusionRule`、`AgePolicy`、`SizePolicy` 模型。
- [x] 四类首批分类规则：User Cache、Application Cache、Logs、Temporary Files。
- [x] 每个候选输出路径、类别、大小、修改时间、应用归属、风险级别、原因、匹配规则和估算可回收空间。
- [x] safe / reviewRequired / protected / unknown 四级安全级别，默认 fail-closed。
- [x] 保护个人数据、浏览器 Profile、Git、凭据、数据库、系统路径、未知路径和 symlink。
- [x] 缓存区分可重新生成缓存与 App 状态/数据库/下载内容/Session/Credential/Extension Data；后者不进入 safe。
- [x] 日志年龄、活跃日志、Crash/Diagnostic 日志和临时文件新旧时间策略。
- [x] 临时文件正在使用检查的执行前能力边界已设计；本阶段不确认使用状态时不进入 `safe`，过新的文件默认 protected。
- [x] 分类只读、与 SafeDeleteEngine 解耦，不自动传递结果或执行删除。
- [x] 17 个分类测试、13 个 SafeDelete 回归测试、12 个 ScanEngine 回归测试全部通过。
- [x] 真实 macOS 目录只读扫描并分类；至少 30 个候选人工抽查，无明显用户数据误判。
- [x] 未开发 UI、Dashboard、Cleaner 删除按钮。

## 第四阶段 CleanupPlanner 验收

- [x] `CleanupPlan`、`CleanupPlanItem`、`CleanupSelection`、`CleanupPreflightResult`、`CleanupExecutionResult`、`CleanupFailureReason` 模型。
- [x] 计划记录候选身份、原始/canonical path、device/inode/type、大小、类别、风险、规则、原因、创建时间、可回收空间和明确选择状态。
- [x] 只有 safe 或明确选择并确认的 reviewRequired 可进入 eligible execution items；protected/unknown/sourceChanged/rule conflict/identity mismatch 永不执行。
- [x] Dry Run 输出处理数量、大小、逐项路径/分类/风险/Trash 方法和拒绝原因，且无文件系统副作用。
- [x] Preflight 重新校验 canonical path、身份、类型、symlink、保护状态、分类和源身份；执行前再做一次逐项 Revalidation。
- [x] 第一版只允许 Trash，不提供永久删除。
- [x] Partial failure、cancellation、duplicate candidate 和审计日志逐项隔离记录。
- [x] 受控真实链路完成：扫描 → 分类 → 计划 → Dry Run → 制造 sourceChanged → Preflight → Trash；只允许身份未变化的文件进入 Trash。
- [x] 16 个 CleanupPlanner 测试、13 个 SafeDelete 回归、12 个 ScanEngine 回归、17 个 Classification 回归全部通过。
- [x] 未使用真实用户缓存作为删除测试目标。

## 不得进入下一模块的条件

- 任一真实安全测试失败。
- 存在直接永久删除路径。
- 任何危险路径可以通过白名单绕过。
- Dry Run 产生文件系统副作用。
- 日志吞掉错误或泄漏敏感凭据。

## 第五阶段 Monitoring Foundation 验收

- [x] Core-only `MonitoringSnapshot`、`CPUSnapshot`、`MemorySnapshot`、`DiskSnapshot`、`NetworkSnapshot`、`ProcessSnapshot` 模型。
- [x] CPU 总使用率、per-core、system/user/idle；内存 physical/used/available/wired/compressed/swap/pressure。
- [x] 磁盘 total/used/available/read-write throughput；网络接口、累计 bytes、upload/download throughput。
- [x] 只读进程列表：PID、CPU、内存、名称；不存在 kill 或系统修改路径。
- [x] Swift Concurrency、可取消采样、可配置间隔、不阻塞主线程、不要求 root、Apple Silicon 原生。
- [x] 不使用 private API；不引入未经 License 审查的第三方代码或依赖。
- [x] 真实当前 Mac 采样至少 10 分钟，记录 CPU/内存趋势和采样器内存趋势；取消行为真实通过。
- [x] 真实网络流量和磁盘 I/O 变化测试通过，并与 Activity Monitor 做合理性对照。
- [x] 全部 SafeDelete/Scan/Classification/Cleanup 回归、Xcode Tests 和 App Build 保持通过。
- [x] 不开发 Dashboard UI、风扇控制、系统优化、进程结束或自动化。

## 第六阶段 Hardware Observability Foundation 验收

- [x] 已完成 `HARDWARE_API_AUDIT.md`，逐项记录 Apple API、权限、稳定性和 GitHub License 决策。
- [x] Core-only 硬件模型与可取消采样器；不开发 Dashboard 或系统控制。
- [x] 已实现并验证 Apple Silicon 基本信息、thermal state、电池/电源来源（设备支持时）和存储基础属性。
- [x] cycle count/health/capacity 只在公共 API 返回合法数据时提供；不支持指标明确返回 `unsupported`/`unavailable`。
- [x] CPU/GPU/SoC 温度、风扇 RPM、功耗、SMART、wear 未使用 private API/root/shell 伪造，未进入正式 Core。
- [x] 测试覆盖正常、unavailable、unsupported、异常、取消、连续采样、范围校验和无假数据。
- [x] 当前 M4 Mac 真实采样至少 10 分钟，记录 CPU、RSS、资源泄漏与各指标稳定性。
- [x] SafeDelete 13/13、Scan 12/12、Classification 17/17、Cleanup 16/16、Core 回归 58/58、Xcode Tests 和 App/Core arm64 Debug Build 全部通过。

### Storage topology refinement

- [x] 存储值类型按 `Physical Disk → APFS Container → Volume` 归类，不把 disk0/disk1/disk2/disk3 当作多块物理磁盘。
- [x] 同一物理 SSD 去重；System/Data、APFS snapshot 和共享容器容量不重复计算。
- [x] 普通存储页只展示用户可理解的磁盘名称、内置/外接类型、十进制容量和卷角色；BSD Name、UUID、physical store 仅在高级信息中展示。
- [x] 每次采样从当前公开 IOKit storage registry 重建拓扑，外接磁盘变化不会保留 stale entries。
- [x] SMART/wear 不可用时显示 `unsupported`/`unavailable` 及原因，不提供伪造读数。

## 第七阶段 Disk Analyzer 验收

- [x] `DiskNode`、`DiskTree`、`TreemapNode`、`FileCategory`、`LargeFileEntry`、`DiskAnalysisSnapshot` Core 模型。
- [x] 只读、低内存、可取消、固定并发的目录分析；快照不保存完整文件树。
- [x] 显式 allowed roots、absolute/canonical 边界校验和 canonical directory 去重。
- [x] symlink 叶子处理、symlink loop 不递归、越界 symlink fail-safe。
- [x] 权限错误和元数据/枚举失败记录，不静默吞错。
- [x] 大文件阈值、Top N、年龄、类型、路径/大小结果；不把大文件标记为垃圾或执行删除。
- [x] 增量 update 回调输出目录完成、大文件、issue 和最终 snapshot。
- [x] 真实验证 Home 允许区域、大型目录、至少 50,000 文件、取消、权限不足尝试和 symlink loop；记录耗时、peak RSS、CPU、吞吐、取消延迟。
- [x] 独立 build、DiskAnalysis tests、全量回归和 Code Review 通过。

## 第八阶段 App Manager Foundation 验收

- [x] 只读枚举当前 Mac 可发现的 `.app`，读取 bundle identifier、名称、版本、大小、修改时间、来源和公开签名状态（不可用时显式返回 unknown/unavailable）。
- [x] 基于 bundle identifier 精确分析 Application Support、Caches、Preferences、Saved Application State、Logs、WebKit、HTTPStorages、Containers 等已知 residual 位置。
- [x] unknown/shared/低置信度关联 fail-closed，并通过值类型适配既有 Classification → CleanupPlanner → Dry Run → Preflight → SafeDeleteEngine。
- [x] Sentinel 仅提供只读可行性提示；没有自动卸载、永久删除、系统修改或特权 helper。
- [x] 当前 Mac 真实扫描至少 20 个 App；受控测试 App 完成 inventory、residual analysis、UninstallPlan、Dry Run 和 Preflight；未删除真实重要 App。
- [x] SwiftPM/Xcode 测试、App/Core 构建和分支 Code Review 通过。

## 第九阶段 System Tools Foundation 验收

- [x] 只读读取用户/系统 LaunchAgents、LaunchDaemons；Login Items 不可可靠枚举时明确返回 unsupported，不读取私有 BTM 数据。
- [x] Privacy 状态模型区分 authorized、denied、notDetermined、unavailable 和 unsupported；不伪造 Full Disk Access 或当前设备使用状态。
- [x] `UpdateProvider`、Sparkle adapter 边界、App Store/非 App Store source metadata 完成；无自动安装更新路径。
- [x] 未引入第三方依赖；Sparkle 仅作受控协议边界，许可证和集成风险已记录。

## 第十四阶段 Menu Bar + App Update UI 验收

- [ ] Menu Bar 真机显示 CPU、Memory、Network、Disk，并可从快速面板配置显示项。
- [ ] Menu Bar 点击可展开快速面板；采样为后台可取消任务，进程列表采样关闭，记录 CPU/RSS 实测结果。
- [ ] App Update 展示当前版本、新版本和更新说明；检查动作真实调用 `UpdateProvider`。
- [ ] 更新候选必须经过用户确认；不存在静默下载、静默替换或静默安装路径。
- [ ] zh-Hans / English 菜单栏与更新 UI 文案可切换。
- [ ] Xcode App/Core Build、Core Tests、Core runners 和真机菜单栏交互验证通过。
- [ ] 未复制 GPL/AGPL/Commons Clause/商业限制项目代码；Sparkle 未锁定并引入前不提交二进制，使用时保留完整 License/NOTICE。
- [x] 当前 Mac 真实只读验证、SwiftPM/Xcode 测试、App/Core 构建和分支 Code Review 通过。

## 第十四阶段正式 Sparkle 更新链路补充验收

- [x] Sparkle 2.9.6 通过 Xcode Swift Package Manager 精确锁定；Core 不导入 Sparkle。
- [x] `SUFeedURL`、`SUPublicEDKey`、自动检查间隔、自动安装关闭、feed 签名和 extraction 前校验已配置；feed/key 由发行构建注入。
- [x] 手动检查调用 Sparkle 标准更新 UI；不再把打开 HTTPS 手动地址作为正式更新路径。
- [x] 自动检查设置直接读写 Sparkle updater 的持久化属性，未复制第二份默认值。
- [x] 缺少 feed/key、非 HTTPS feed 或错误公钥时 fail-closed 为 `unavailable`；网络/feed/签名/安装错误保留当前 App 并显示错误。
- [x] Sparkle MIT License 与其官方外部组件 notices 随仓库保留在 `NOTICE` 和 `THIRD-PARTY-NOTICES/Sparkle-LICENSE.txt`。
- [ ] 真实新版本下载、归档签名校验、Developer ID 签名、公证、安装后重启：当前仓库没有可靠发行材料，未宣称通过。

## 第十阶段 SwiftUI 产品化骨架与 Dashboard 验收

- [x] 正式 SwiftUI App Shell 提供 Sidebar、Dashboard、Cleaner、App Manager、Disk Analyzer、System Tools、Monitoring、Hardware 和 Settings 页面边界。
- [x] Dashboard 使用真实 Core 数据展示 CPU、Memory、Disk、Network、Thermal、可清理空间、已安装 App 数量、磁盘使用和系统健康概览。
- [x] Overview 的 safe-space 仅来自已校准 User Cache safe 规则与明确 Bundle ownership，不扫描或升级其他 review/protected 类别。
- [x] Monitoring/Hardware 采样使用 Swift Concurrency，不阻塞主线程；Dashboard 离开时取消采样与 Overview 任务，重复进入不创建重复采样流。
- [x] Light/Dark Mode、最小窗口尺寸和页面切换完成真实 SwiftUI 验证；不提供删除、卸载、进程结束、风扇控制或系统修改入口。
- [x] App Target arm64 Debug Build、Core 全量测试、SwiftPM 全量测试和真实 App 启动通过。
- [x] Dashboard 连续运行至少 10 分钟；记录 CPU/RSS 趋势且无持续增长或启动崩溃。

## 第十一阶段 Cleaner 完整 UI 验收

- [x] Cleaner 页面连接真实 ScanEngine、ClassificationEngine 和 CleanupPlanner，无 Mock 候选或直接删除 API。
- [x] safe、reviewRequired、protected、unknown 显示真实数量、空间、分类、规则、原因和路径详情。
- [x] safe 默认选中且可取消；reviewRequired 必须主动选择；protected/unknown 永远不可选择。
- [x] 扫描进度、取消、空状态、扫描问题和错误/拒绝状态诚实显示。
- [x] 任何执行严格经过 CleanupPlan、Dry Run、明确确认、Preflight 和 SafeDeleteEngine；source/identity/symlink 变化按项拒绝。
- [x] 第一版仅允许 Trash；执行结果显示成功、跳过、失败/拒绝、Audit entries 和实际回收空间。
- [x] 受控真实临时 fixture 完成 UI Scan → Classification → Selection → Dry Run → Confirmation → Preflight → Trash → Audit E2E；未批量删除真实用户数据。
- [x] 真实验证覆盖 UI 扫描取消、Core sourceChanged/identity/symlink/protected/unknown/rule conflict/cancellation/partial failure/Trash failure。
- [x] Light/Dark Mode、窗口缩放、页面切换和 App 启动无明显崩溃或新增严重 runtime 问题。
- [x] App/Core arm64 Debug Build 和全量回归通过。

## 第十二阶段 App Manager 完整 UI 验收

- [x] 真实枚举当前 Mac 已安装 App，支持图标、metadata、大小、Bundle ID、路径、搜索和排序。
- [x] App 本体与 residual 分开显示；残留展示 confidence、风险等级、归属原因和保护状态。
- [x] 卸载严格经过 App Selection → Residual Analysis → UninstallPlan → Dry Run → Confirmation → Preflight → SafeDeleteEngine → Trash → Audit。
- [x] shared/protected/unknown、个人目录、symlink、sourceChanged 和 identity mismatch 永远不可执行；禁止永久删除。
- [x] 至少人工抽查 20 个真实 App；受控测试 App 完成完整 UI E2E，不触碰真实重要 App。
- [x] 取消、partial failure、sourceChanged、Light/Dark Mode、窗口缩放、App/Core Build 和全量 Tests 通过。

## 第十三阶段 Disk Analyzer 完整 UI 验收

- [x] 真实 SwiftUI 页面展示启动卷总容量、已用、可用和当前扫描字节数；数据来自 macOS resource values/Core，不使用 Mock。
- [x] 接入现有 `DiskAnalysisEngine`，展示受限增量目录聚合、Top-N 大文件、文件类型统计、权限/symlink issue，并支持扫描取消。
- [x] Treemap 使用 Core `TreemapNode` 做原生 SwiftUI slice-and-dice 布局，目录点击深入；大文件只作信息展示，不自动判定为垃圾。
- [x] 大文件支持阈值、搜索、文件类型筛选、大小/修改时间/名称排序；排序和筛选不修改文件。
- [x] 页面没有直接删除 API；任何未来清理必须继续走 CleanupPlan → Dry Run → Preflight → SafeDeleteEngine，protected/unknown 不可直接删除。
- [x] Core 50,000+ 受控真实测试：50,002 files，wall 0.817 s，CPU 2.186 s，peak RSS 42.4 MiB，吞吐约 61,200 files/s，取消延迟 0 ms；symlink loop/escape、权限 issue 和 canonical duplicate 验证通过。
- [x] SwiftUI App arm64 Debug Build、Core arm64 Build、SwiftPM/Xcode 55/55 和真实 App 启动通过；真实 UI 扫描显示实时计数、Top 大文件、issue，并通过取消进入明确空状态。
- [x] Home UI 内存 Profile 已定位到重复 Treemap/目录元数据、主线程投影刷新和 `contentsOfDirectory` 大目录物化热点；完成态 Treemap 改为派生投影，扫描遍历改为 `getattrlistbulk` 批量 metadata + 流式聚合，不一次性加载完整文件树。
- [x] 真实 `$HOME/Library/Caches` UI 闭环：18,006 files / 8,418 directories / 3.26 GB，完成态 RSS 约 153 MB；Treemap 171 个根节点，已验证目录深入/返回、大文件排序切换、窗口滚动和深色模式；取消控件和 Core cancellation 保持真实。
- [x] 新架构 Home UI 全量扫描真实完成：约 759,990 files / 127,990 directories / 576.54 GB logical bytes；Treemap 根视图、`Library` 懒加载深入和返回根目录通过，扫描取消控件与 Core cancellation 保持可用。
- [ ] Home UI RSS 仍约 256–267 MB（physical footprint peak 约 164.5 MB），未达到 RSS ≤200 MB；Core-only Home runner 为约 23.8 s、peak RSS 约 96 MB。
- [x] Mole 已通过 Homebrew core 安装并真实运行；同机 `$HOME/Library/Caches` A/B：LexCleaner 0.742 s / 90.6 MB RSS / 18,006 files / 8,418 directories；Mole 0.18 s / 14.7 MB RSS / 16,888 files。LexCleaner 的额外 issue、symlink 和 identity 语义已保留。
- [ ] Home 同范围 Mole 仍无法形成可靠结果（约 4 分 45 秒无输出后停止）；缓存范围 LexCleaner 速度和 RSS 仍落后，不能声称整体超越 Mole，本阶段整体不能标记 PASS。

### 性能收口复核（2026-08-23）

- [x] Profile 后完成普通文件 URL/canonical 延迟构造、getattrlistbulk compact metadata 流程和 watchdog executor 修正；安全检查与统计口径未降低。
- [x] Home Core 完整扫描：9.03 s / 43.5 MB peak RSS / 960,377 files / 147,022 directories；logical 600.56 GB、allocated 121.78 GB、volume capacity 494.38 GB。
- [x] Caches 独立 Release 进程 5 次：warm 0.199–0.202 s / 13.8–14.1 MB；冷启动约 0.397 s；Mole 0.18 s / 14.7 MB。
- [ ] Caches 速度严格 `<0.18 s` 且 RSS `<14.7 MB`：RSS 已满足，速度未满足。
- [ ] Home SwiftUI ≤150 MB 且稳定在验证窗口内完整结束：未满足；最新 15 秒观察约 238.6 MB RSS，未完成扫描。
- [ ] 关键指标超过 Mole：未满足；Disk Analyzer UI 最终保持 **FAIL**。
- [x] 全量回归：SwiftPM/Xcode 57/57，所有既有 Core runners 通过，App/Core arm64 Debug Build 通过。
- [ ] 最新 App 启动：无崩溃，但 15 秒时 Home UI RSS 约 238.6 MB 且未完成扫描；为避免无必要长时间运行停止，故不计为 UI 性能通过。
- [x] 容量校准：logical 与 allocated 已分离，Treemap 默认 allocated，Home allocated 与 du/df/APFS 口径一致且不超过 volume capacity；APFS shared extents 限制已明确标注。

### 性能收口复核（2026-08-23，本轮）

- [x] SwiftUI Profile 后，ViewModel 只保留有界当前层投影；外层页面和大文件区使用 `LazyVStack`，Treemap 导航缓存最多 4 层。
- [x] Home UI 在真实 20 秒窗口完成 Core 返回并保持运行；最新 RSS 峰值约 163,984 KB（160.1 MiB），无崩溃或明显 runtime 错误。
- [ ] Home SwiftUI RSS ≤150 MB：未满足。
- [x] Caches 20 次 A/B：LexCleaner median 0.208310 s / P95 0.209490 s / RSS 14,237,696 B；Mole median 0.101786 s / P95 0.105475 s / RSS 14,868,480 B。
- [ ] LexCleaner Caches median 速度超过 Mole：未满足；仅 RSS 低于 Mole，Disk Analyzer 不得标记 PASS。
- [x] SwiftPM/Xcode 57/57、App/Core arm64 Debug Build 和真实启动通过。
- [ ] 第十三阶段最终验收：继续 **FAIL**。

### 最后性能攻坚复核（2026-08-23）

- [x] 公平性审计完成：双方使用同一 `~/Library/Caches` 根目录；LexCleaner 完整安全分析统计 18,601 项、8,418 目录，Mole JSON 报告 16,888 files/188 一级聚合项，Mole 不提供 raw traversal 输出，因此未把不同范围宣布为等价。
- [x] Profile 与最小优化完成：getattrlistbulk 仍是最大热点；批量 buffer、compact record、聚合引用对象、identity queue key、后台 projection 和页面懒创建已验证，安全与容量口径不变。
- [x] Home Core 完整通过：8.966 s、约 27.8 MiB peak RSS、allocated 122.16 GB，不超过 494.38 GB volume。
- [x] 20 次完整 Caches A/B：LexCleaner 0.196407 s median / 0.198174 s P95 / 13.40 MiB RSS；Mole 0.103023 s median / 0.107417 s P95 / 14.05 MiB RSS。LexCleaner 仅 RSS 胜出，速度未胜出。
- [ ] Home SwiftUI RSS 稳定 ≤150 MiB：未满足；实测范围约 149.89–151.22 MiB。
- [ ] Disk Analyzer UI 性能验收：**FAIL**。未形成“速度、RSS、完整性”三项同时优于 Mole 的实际优势。

### 最后性能攻坚最终复核（2026-08-23）

- [x] benchmark 口径审计完成：同一 `~/Library/Caches` 根目录、同一机器、独立进程、完整分析输出；本轮 LexCleaner 统计 18,606 项、8,418 目录，Mole JSON 为 16,888 files/188 个一级聚合项。Mole 不暴露 raw traversal，因此不把纯 traversal 或文件覆盖范围宣布为等价。
- [x] 20 次 A/B：LexCleaner **0.196669 s median / 0.197707 s P95 / 13.42 MiB RSS**；Mole **0.103400 s median / 0.106636 s P95 / 14.03 MiB RSS**。
- [x] Home Core **8.966 s / 27.8 MiB peak RSS**，allocated **122.16 GB**，未超过 volume **494.38 GB**。
- [ ] Home SwiftUI RSS 稳定 ≤150 MiB：未满足；最新观察 **150.70 MiB**，重复观察范围 **149.89–151.22 MiB**。
- [x] SwiftPM/Xcode **57/57**、App/Core arm64 Debug Build、真实启动和页面生命周期代码通过。
- [ ] 验收结论：速度未超过 Mole，Home RSS 未稳定达标，Disk Analyzer 保持 **FAIL**。

### 同口径与性能最终复核（2026-08-23）

- [x] Equal-scope：同一 `~/Library/Caches/Homebrew`、同一文件范围（`.git` 与 symlink 均排除）、同一 3,473 files、Top-20 输出。当前代码 20 次：LexCleaner **0.043161 s median / 0.045827 s P95 / 12.60 MiB**；Mole **0.095354 s / 0.098338 s / 11.95 MiB**。
- [x] Full-quality：Caches LexCleaner **0.130214 s / 0.158280 s / 14.28 MiB / 18,632 项**；Mole **0.106992 s / 0.112172 s / 14.02 MiB / 16,888 files**。Mole 范围较小，未用它的数字掩盖 production 差距。
- [x] 自适应并发选择 4；6 变慢且更耗内存。精确 identity 去重表优化后 Home Core **7.215 s / 22.2 MiB**；full-quality `~/Library/Caches` allocated 与 `du` 差约 16 KiB。
- [x] Home SwiftUI 稳定启动峰值 **143.98–144.83 MiB**，≤145 MiB；App/Core Build、SwiftPM/Xcode **57/57** 通过。
- [ ] 验收结论：equal-scope 速度胜出但 RSS 略高；full-quality 尚未同时胜出，Disk Analyzer **FAIL**。

### 最终性能与容量 UI 收口（2026-08-23）

- [x] Full-quality：LexCleaner **0.130214 s median / 0.158280 s P95 / 14.28 MiB**；Mole **0.106992 s / 0.112172 s / 14.02 MiB**。性能未全面超过 Mole。
- [x] 真机截图确认 UI 使用 allocated 作为“实际占用”（**122.32 GB**），logical 单独显示为“扫描逻辑大小”（**601.07 GB**）；Volume 为 **494.38 GB**，实际占用没有超过容量，Treemap 使用 allocated。
- [x] Home allocated 与 `du` 交叉验证差 **4 KiB**（符号为扫描值低于 `du`）；受保护目录的 `du` 权限错误已明确记录，未放宽扫描权限。
- [x] SwiftPM/Xcode **57/57**、App/Core arm64 Debug Build、真实启动通过。

## 第十五阶段 Network Optimizer 验收

- [x] Core 提供真实接口、路径、DNS、代理、网关、延迟、抖动、探测失败率和可解释健康评分；不可用数据显式返回 unavailable/unsupported。
- [x] DNS Benchmark 记录当前 DNS、公共候选 DNS 的 median/P95/jitter/timeout/failure rate；不自动修改 DNS。
- [x] Network Diagnostics 覆盖路径、DNS、代理、接口错误、探测失败和可验证异常；不把 TCP probe failure 冒充 ICMP packet loss。
- [x] App Network Usage 对没有稳定公开 API 的逐进程数据明确 unavailable，不伪造或解析不稳定输出冒充准确结果。
- [x] OptimizationPlan 记录原配置、候选配置、授权要求和 rollback；无用户确认或管理员授权不修改系统设置。
- [x] SwiftUI Network 页面支持真实数据、取消、错误/空状态、zh-Hans/en、Light/Dark 和窗口尺寸。
- [x] 新增 Core/UI 测试、SwiftPM/Xcode 全量测试、arm64 Debug/Release Build、真机页面验证和 15 分钟稳定性通过。
- [x] Core 已实现真实 SystemConfiguration 目标服务读取/写入边界、显式用户确认门、管理员授权、修改前后 DNS/TCP A/B、无改善自动恢复、完整配置验证和 pending journal 恢复；注入式测试覆盖无权限、用户取消、无效 DNS、源变化、修改后测量失败、成功与回滚。
- [ ] 当前环境未执行真实管理员授权下的系统 DNS 写入、A/B 和 rollback；Network Optimizer 保持 **PASS WITH ADMIN RELEASE GATE**，不宣称发布条件已完成。

## Friends Beta 反馈验收

- [x] Settings 可由用户主动导出 UTF-8 诊断报告，并包含 App version/build、macOS、Mac 型号/架构、模块状态、有限错误摘要和崩溃报告摘要。
- [x] 诊断报告不包含用户名、私人路径、文件名、文件内容、Token、密码或凭据；不会自动上传任何数据。
- [x] 用户可复制诊断信息，反馈入口打开 GitHub Issues 并自动附带版本/build；诊断正文不通过 URL 自动发送。
- [x] Core redaction tests、SwiftPM/Xcode 全量、Debug/Release Build 和 Release 真机导出报告验证通过。
- [x] CPU/Disk/Network 冻结算法与既有安全边界无变化。

### 容量展示修正（2026-08-23）

- [x] 主界面只突出显示 Volume 总容量、Allocated 实际占用和可用空间。
- [x] Logical Size、扫描覆盖范围及 APFS 克隆/稀疏文件/共享数据说明移入默认收起的详细信息区，并提供 zh-Hans / en 文案。
- [x] Treemap 面积继续严格使用 Allocated Size；Logical 只作为节点辅助信息。
- [x] 当前构建中英文真实启动截图通过，普通用户不会在主容量区域看到 Logical Size 被当作实际占用。
- [x] SwiftPM/Xcode **57/57**、App/Core arm64 Debug Build 通过。
