# Hardware Observability API Audit

审计基线：macOS 26.5.1、Xcode 26.6 (17F113)、Mac16,10 / Apple Silicon M4、MacOSX26.5 SDK。

本阶段只允许只读、无需 root、可长期维护的能力进入 `LexCleanerCore`。任何 API 缺少公开契约、依赖设备私有 key、需要 helper/root，或在当前硬件上无法区分“不可用”和“读数为零”时，统一返回 `unsupported` 或 `unavailable`，不填充猜测值。

## Apple API feasibility matrix

| 能力 | 来源/权限 | 稳定性判断 | 决策 |
|---|---|---|---|
| Apple Silicon 型号/架构/核心数/内存 | `sysctl` (`hw.model`, `hw.ncpu`, `hw.logicalcpu`, `hw.physicalcpu`, `hw.memsize`, `hw.optional.arm64`)；无需 root | stable low-level API；值可能随硬件/功耗模式变化 | **自研**，实现 `HardwareSnapshot` |
| Thermal state | Foundation `ProcessInfo.thermalState`；无需 root | Public API；Apple 明确支持 nominal/fair/serious/critical 和变更通知 | **自研**，实现 `ThermalSnapshot` |
| Thermal pressure | 以 `ProcessInfo.thermalState` 表示系统热压力 | Public API；不读取私有传感器 | **自研**，只暴露离散状态 |
| 电源来源、充电、当前/最大/设计/标称容量、电压/电流、电池温度、健康字符串 | IOKit `IOPowerSources` / SDK `IOPSKeys.h`；无需 root | Public API；Apple 文档说明字典字段可能缺失，逐字段可选 | **自研**，字段缺失返回 `unavailable` |
| Battery cycle count | SDK `IOPMCopyBatteryInfo` + `kIOBatteryCycleCountKey`；旧的、Apple 标注 supported but not recommended；无需 root 的只读尝试 | Stable low-level API，但不如 `IOPowerSources` 推荐；硬件无电池时无结果 | **部分实现**，只在 API 返回合法非负值时提供，否则 `unavailable` |
| Battery health / capacity | 容量与 `BatteryHealth`/`BatteryHealthCondition` 为 SDK 公共 key；无需 root | Public API，但供应商/硬件可能不发布全部字段 | **部分实现**，不推导未提供的健康百分比 |
| CPU/GPU/SoC 温度 | SMC、IOHID 传感器服务或 `IOReport` 私有/设备特定 key | Private or undocumented；Apple Silicon key 随 SoC/OS 改变 | **不实现**，`unsupported` |
| Fan RPM | SMC/设备特定 key；读取与写入边界紧密相关 | Private or undocumented；无风扇设备也常见 | **不实现**，`unsupported`；禁止控制 |
| CPU/GPU/ANE/SoC 功耗 | `powermetrics` 是命令行工具且常要求 root；`IOReport` 为未公开框架/符号 | Private or undocumented / root required for supported tool path | **不实现**，`unsupported`；不调用 shell |
| SSD/NVMe 型号、容量、BSD 名称、可移除/可写等基础信息 | IOKit `IOMedia`、`IORegistryEntryCreateCFProperties`、公开 storage headers；无需 root | Stable low-level API；属性可缺失，设备树结构可能不同 | **自研**，实现基础 `StorageHealthSnapshot` |
| SMART / NVMe SMART | SDK 存在 user-client headers，但跨 Apple 内置 SSD/OS 版本的公开稳定保证不足；smartmontools 为 GPL-2.0-or-later 外部工具 | Private or undocumented / unsupported as product contract | **不实现**，不引入 smartmontools 代码或二进制 |
| Storage wear / health | 没有适用于 Apple 内置 SSD 的稳定公开产品 API | unsupported | **不实现**，`unsupported` |

### Storage topology decision

Storage collection uses only the audited read-only IOKit storage surface: `IOServiceMatching("IOMedia")`, `IORegistryEntryCreateCFProperties`, registry parent traversal, `IORegistryEntryGetRegistryEntryID`, `IOObjectGetClass` and `IORegistryEntryGetName`. The collector reads the documented IOMedia properties (`Whole`, `Leaf`, `BSD Name`, `UUID`, `Content`, `Content Hint`, `Size`, `Removable`, `Ejectable`, `Writable`) and APFS volume metadata exposed by the storage stack (`FullName`, `Role`, `VolGroupUUID`).

The value model is `Physical Disk → APFS Container → APFS Volume`. A physical disk is the whole non-APFS media root; an APFS container is the whole APFS media node; APFS volumes are attached through the registry parent chain. Synthetic container media, physical-store partitions, APFS snapshots and volume nodes are not presented as separate physical disks. Container UUID/volume UUID are preferred for snapshot-local de-duplication, while BSD names remain advanced attachment details only. APFS volume-reported sizes are retained as advanced/raw metadata with `sharedContainer` scope; user-facing capacity totals are owned by the physical disk/container and never sum System/Data or other shared APFS volumes.

The topology is rebuilt from the current IOKit registry on every sample. No disk-number cache is retained, so external media insertion/removal is reflected by the next snapshot and stale devices are removed. There is no shell, `diskutil`, private API, helper or SMART probe in the product path.

Storage UI capacity labels use decimal units (1 GB = 1,000,000,000 bytes; 1 TB = 1,000,000,000,000 bytes), matching macOS user-facing disk capacity. SMART and wear remain explicitly `unsupported` with the audit reason; no zero/default value is substituted.

## GitHub reference decisions

| 项目 | License | 活跃度/能力 | 风险 | 最终策略 |
|---|---|---|---|---|
| [Stats](https://github.com/exelban/stats) | MIT | 持续发布；覆盖 battery/sensors/fan/power；README 明确 Apple Silicon sensor key 会随 SoC 改变 | SMC/私有 key、helper 安全边界、跨版本漂移 | **部分复用思路**；不复制传感器/控制代码，不引入 helper |
| [iStats](https://github.com/Chris911/iStats) | MIT | 老 Ruby 工具；提供旧 macOS battery/fan/temp 命令 | 旧架构、Ruby/SMC、Apple Silicon 适配不足 | **仅参考** |
| [osx-cpu-temp](https://github.com/lavoiesl/osx-cpu-temp) | GPL-2.0 | 维护规模小；直接使用 Apple SMC | GPL；私有 SMC；不适合闭源 Core | **不采用，仅参考风险** |
| [macmon](https://github.com/vladkens/macmon) | MIT | Apple Silicon 活跃监控；覆盖 power/temperature/fan | README 明确依赖 private macOS API、SMC、IOReport | **仅参考实现边界**；禁止 private API 进入本阶段 Core |
| [mactop](https://github.com/metaspartan/mactop) | MIT | Apple Silicon 活跃 Go 工具；读取 SMC/IOReport/IOHID，另含 kill/fan control | 与本项目只读边界冲突；私有接口和控制能力混合 | **仅参考**；不引入代码 |
| [smartmontools](https://github.com/smartmontools/smartmontools) | GPL-2.0-or-later | 成熟 SMART/NVMe 工具，支持 Darwin | GPL；外部 CLI、设备访问、产品权限/签名复杂 | **仅参考协议/能力**；不复制核心代码，不作为依赖 |

## Rules recorded for this phase

1. 不使用 `powermetrics`、SMC、IOReport 私有接口或 shell 输出作为稳定 Core 数据源。
2. 不使用 `sudo`、root helper、SMC 写入、风扇控制或系统参数修改。
3. 模型必须携带 availability；`unsupported` 与 `unavailable` 不得折叠成零值。
4. 读数范围校验失败时返回 unavailable/error，不修正成看似合理的数值。
5. 仅保留 Apple SDK public headers 和明确可验证的稳定低层 API；所有不可可靠指标延期到单独的风险评估阶段。
