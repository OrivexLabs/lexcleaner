# LexCleaner GitHub 技术决策矩阵

调研日期：2026-08-22

本文件是路线决策记录，不是业务代码，也不授权复制任何第三方实现。活跃度按调研时 GitHub 仓库的提交、Release、Issue/PR 和维护者公告判断；具体版本、提交和 License 在真正引入前必须重新锁定并复核。

## 总体决策

| 能力 | 候选项目 → License | 活跃度 / macOS 与 Apple Silicon | 可复用能力 | 风险 | 最终策略 |
|---|---|---|---|---|---|
| macOS Cleaner / cache cleaner | [Mole](https://github.com/tw93/Mole) → GPL-3.0；[Pearcleaner](https://github.com/alienator88/Pearcleaner) → Apache-2.0 + Commons Clause | Mole 持续发布、macOS 原生；Pearcleaner 功能覆盖高、支持 macOS 13+，但维护者已声明项目 On Hold | Mole 的安全边界、Dry Run、分类组织和产品流程；Pearcleaner 的应用残留搜索、Sentinel 思路 | GPL/Commons Clause 不适合闭源核心；Pearcleaner 曾有高危未认证 privileged XPC helper；两者都涉及高风险文件操作 | **仅参考实现/架构**；继续使用 LexCleaner 自研 SafeDelete/Scan/Classification/Pipeline |
| App uninstall / residual scanner | Pearcleaner、Mole；AppCleaner 为商业/非 GitHub 参考 | Pearcleaner 残留搜索和应用关联覆盖较完整；Mole 仍活跃 | Bundle 识别、残留路径分组、应用/插件/Launch 项关联、用户预览流程 | 残留路径可能是用户状态、凭据、数据库或共享组件；特权 helper 风险；许可证不兼容 | **仅参考**；卸载核心自研，复用 macOS bundle、Launch Services、Trash 原生能力 |
| Disk analyzer / Treemap | [GrandPerspective](https://sourceforge.net/p/grandperspectiv/source/ci/master/) → GPL；Mole → GPL-3.0 | GrandPerspective 成熟但官方源码不在 GitHub，macOS 取向明确；Mole 分析功能活跃 | Treemap 布局、层级聚合、增量统计、外部卷边界 | GPL；全树加载会造成内存压力；系统别名、权限和 symlink 容易误计 | **仅参考布局/算法**；扫描数据模型和 UI 自研，采用流式/增量聚合 |
| Disk analyzer / CLI reference | [ncdu](https://github.com/rofl0r/ncdu) → MIT；[dua-cli](https://github.com/Byron/dua-cli) → MIT；[dust](https://github.com/bootandy/dust) → Apache-2.0 | ncdu 为 POSIX curses 工具；dua-cli 并行扫描且包含交互删除；dust 为活跃 Rust CLI、支持 macOS/arm64 发布 | 终端展示、并行遍历、Top-N/JSON 思路、权限提示 | CLI/终端模型不适合作为 Core API；dua 的删除路径和第三方 Rust 依赖扩大安全/许可证边界；Apache/MIT 复用仍需保留 NOTICE | **仅参考公开行为/架构**；不复制代码、不引入依赖，LexCleaner DiskAnalysis 用 Swift 原生 API 自研 |
| Duplicate file finder | [dupeGuru](https://github.com/arsenetar/dupeguru) → GPL-3.0 | 长期存在、Issue/PR 较多；macOS 支持存在，但 Cocoa UI 已不再维护，构建依赖 Python/Qt | 分阶段比较：尺寸/指纹/内容哈希、重复组模型和用户选择流程 | GPL；跨平台旧技术栈；硬链接、包内容、权限、稀疏文件和 symlink 处理复杂 | **仅参考算法思路**；核心自研 Swift/原生 API，默认不扫描用户个人目录 |
| CPU / GPU / RAM / Network monitor | [Stats](https://github.com/exelban/stats) → MIT；[btop](https://github.com/aristocratos/btop) → Apache-2.0；Mole → GPL-3.0 | Stats 原生 Swift、macOS 12+、功能覆盖广；btop 活跃、提供 arm64 发布物但 GPU/macOS 能力存在平台差异 | Stats 的模块拆分、采样周期、SMC/IOKit 读取经验；btop 的终端采样和进程聚合思路 | Stats 单维护者、传感器成本高、风扇控制为 legacy；btop 不是 SwiftUI/macOS 专项；权限与采样耗电 | **部分复用**：优先评估 Stats MIT 的独立、只读模块；不得复制其特权 helper；平台采集协议和产品层自研 |
| Temperature / sensor / power monitor | Stats、[mactop](https://github.com/metaspartan/mactop) → License/版本需逐 commit 复核；Mole → GPL-3.0 | Stats 有温度/电压/功率/SMC；mactop 面向 Apple Silicon 并覆盖 SMC/IOReport，项目较新 | 传感器枚举、Apple Silicon SMC key 发现、IOReport 采样和运行时能力检测 | Apple 更换传感器 key；不同 SoC/OS 结果不可假设；新项目 License/硬件覆盖需锁定；读取与写入边界不同 | **部分复用/自研**：只在确认兼容 License 后参考读取适配；建立 LexCleaner 只读 capability matrix，不复制控制逻辑 |
| Fan control | [smcFanControl](https://github.com/hholtmann/smcFanControl) → GPL-2.0；[fanctl](https://github.com/erogol/fanctl) → MIT，但作者标注 personal prototype | smcFanControl 老牌但以 Intel 为主；fanctl 面向 Apple Silicon、带 daemon，但硬件覆盖有限且明确非生产级 | SMC key 编码、自动模式恢复、目标 RPM 限制、sleep/wake 处理 | 写 SMC 会绕过系统热管理；root daemon、socket、模型差异和崩溃恢复风险极高 | **自研且延后**；先做只读监控，风扇写入默认不纳入近期路线；不复制任何 fan-control daemon |
| Battery health | [WhatBattery](https://github.com/darrylmorley/whatbattery) → MIT；Stats → MIT；Mole → GPL-3.0 | WhatBattery 为 Swift/SwiftUI、Apple Silicon 取向；Stats 活跃但属综合工具 | 电量、循环次数、健康度计算、功率读数和菜单栏展示 | 电池健康字段随 macOS/硬件变化；“健康度”是估算，不能冒充 Apple 诊断结论 | **部分复用**：仅考虑 MIT 数据模型/计算思路；读取和健康定义自研并标注不确定性 |
| SSD / SMART health | [smartmontools](https://github.com/smartmontools/smartmontools) → GPL-2.0-or-later；macOS 发行支持由 Homebrew 维护 | 长期成熟、持续维护，Apple Silicon Homebrew bottle 可用；macOS 对内置 NVMe/SMART 有限制 | smartctl 数据解析、设备能力识别、外置 SATA/NVMe/SAT 场景 | GPL；Apple 不保证第三方获得完整内置 SSD SMART；驱动/IOCTL/权限差异 | **仅参考协议/CLI 输出**；优先 macOS 原生 Disk Arbitration/IOKit；若引入必须隔离 GPL 进程边界并做许可证审查，否则自研只读有限健康模型 |
| Login Items / LaunchAgents / LaunchDaemons | [LaunchManager](https://github.com/Sean10000/LaunchManager) → MIT；Apple `launchd` / `launchctl` 原生 | LaunchManager 是较新的 SwiftUI 项目，覆盖 User/System scope；macOS 14+ | plist 解析、scope 分层、状态展示、权限提示、日志查看 | 修改或卸载启动项可能造成持久化、启动失败或 root 影响；项目规模/活跃度尚有限 | **部分复用**：参考数据模型和安全 UX；实际发现/状态以 `SMAppService`、`launchctl`、Login Items 原生接口为准；写操作自研且默认保护系统项 |
| Process manager | [ActivityManager](https://github.com/eve0415/ActivityManager) → MIT；btop → Apache-2.0；macOS Activity Monitor 原生 | ActivityManager 是 Swift 6/SwiftUI 新项目；btop 更成熟但跨平台 | 按 App 聚合子进程、树状关系、CPU/内存采样、结束进程确认流程 | 新项目维护规模小；进程权限、root/系统进程、采样准确性和 kill 语义敏感 | **自研**，只参考聚合 UX；采样采用 macOS 原生 proc_pid/NSWorkspace/系统接口，结束进程默认二次确认 |
| Network connection monitor | `nettop` macOS 原生；[NetworkMonitor](https://github.com/kevinabouhanna/NetworkMonitor) → MIT；Mole → GPL-3.0 | `nettop` 随系统；NetworkMonitor 为 SwiftUI 菜单栏项目；Mole 有按进程网络展示 | nettop 输出/进程聚合、接口速率、连接时间线 | `nettop` 解析格式可能变；逐进程归因受系统限制；网络数据属于敏感信息 | **自研**，优先调用 macOS 原生 `nettop`/Network framework/Network Extension 能力；MIT 项目只参考展示，不直接依赖 |
| Privacy / microphone / camera monitoring | [OverSight](https://github.com/objective-see/OverSight) → GPL-3.0 | 专业安全工具，功能明确但仓库提交量较少；macOS 权限/系统机制深度相关 | 设备访问告警、进程身份展示、事件审计和用户通知 | GPL；隐私监控需要高权限/系统事件，误报和兼容性风险；不得复制其安全工具实现 | **仅参考产品行为/威胁模型**；监控层自研，尽量使用 Apple 原生权限状态/API；默认只读、最小化日志 |
| App updater | [Sparkle](https://github.com/sparkle-project/Sparkle) → MIT（仓库同时列出 bsdiff、sais、Ed25519 等外部许可）；[Latest](https://github.com/mangerlahn/Latest) → GPL-3.0 | Sparkle 长期维护、4,000+ commits、签名/沙盒/增量更新成熟；Latest 功能完整但 README 标注业余维护、构建依赖旧 Xcode | Sparkle 的 EdDSA/代码签名、appcast、原子安装、权限与回滚边界；Latest 的本机 App inventory 和更新聚合 | 自动更新是供应链高风险；Latest GPL；Sparkle 版本、签名密钥、macOS 26 兼容性要单独验证 | **直接复用 Sparkle**（锁定兼容版本并保留 License/NOTICE 及外部许可）；**仅参考 Latest**，不复制其代码 |
| Menu bar monitoring | [SwiftBar](https://github.com/swiftbar/SwiftBar) → MIT；Stats → MIT | SwiftBar macOS 12+、活跃且插件生态成熟；Stats 原生菜单栏模块成熟 | 菜单栏生命周期、刷新策略、插件/快捷入口、更新与错误展示 | SwiftBar 执行外部脚本，权限/注入/插件供应链风险；不适合作为 LexCleaner 核心运行时 | **部分复用**：仅参考菜单栏状态与刷新模型；LexCleaner 自研原生 menu bar extra，不引入脚本插件执行器 |
| External display / DDC control | [MonitorControl](https://github.com/MonitorControl/MonitorControl) → MIT | 大型活跃 macOS/Swift 项目、支持 Apple Silicon 和多种 DDC/软件调光协议 | DDC/CI、Apple display protocol、Gamma/shade fallback、OSD 和多显示器同步 | 私有 API/Accessibility 权限；显示器、接口和 macOS 版本兼容性差异；仓库明确记录部分版本崩溃与 DDC 限制 | **部分复用**：先评估 MIT 的独立 DDC/显示抽象；产品策略、能力检测和 fallback 自研；不复制私有素材/品牌 |
| Automation / scheduled maintenance | [Hammerspoon](https://github.com/Hammerspoon/hammerspoon) → MIT；Apple `launchd`/Shortcuts 原生 | Hammerspoon 长期活跃、16k stars、103 releases；覆盖广但依赖 Lua/Accessibility | 事件驱动、定时器、脚本扩展、网络/电源/窗口事件模型 | 引入 Lua runtime 过重；自动化可产生文件删除、命令执行和权限扩大；用户脚本是供应链边界 | **自研**：调度使用 `launchd`、`SMAppService`、Shortcuts/系统 API；Hammerspoon 仅参考事件模型，不引入完整 runtime |

## 按复用策略归类

### 未来可直接复用

- **Sparkle**：唯一当前明确建议直接作为依赖评估的项目，原因是其更新签名、appcast、增量更新、沙盒和原子安装能力高度专业化；本轮只建立 Core bridge，真正引入前仍需锁定具体版本并保留 License/NOTICE。

### 部分复用

- **Stats**：仅限 MIT 许可、只读、可独立隔离的监控模块；不复制其特权 helper 或未维护的风扇控制。
- **MonitorControl**：仅评估 DDC/显示抽象和 Apple Silicon 兼容经验；保留自身能力检测与故障降级。
- **SwiftBar**：只参考菜单栏刷新和状态呈现，不引入外部脚本插件执行模型。
- **LaunchManager**：只参考 launchd scope/模型与 UI 安全提示，核心改用 Apple 原生接口。
- **WhatBattery**：只参考电池健康计算与数据模型，健康结论由 LexCleaner 明确标为估算。

### 仅参考实现 / 架构

- Mole、Pearcleaner、GrandPerspective、dupeGuru、OverSight、Latest、Hammerspoon、btop、mactop、smcFanControl、fanctl、smartmontools、ActivityManager、NetworkMonitor。
- 可参考的内容限于公开功能、数据流、边界条件和测试思路；不复制受限代码、私有资源、品牌、图标或专有交互素材。

### 自研

- SafeDelete、Scan、Classification、CleanupPlanner 已自研并继续作为核心安全边界。
- 卸载/残留安全判定、重复文件安全策略、进程管理、网络连接归因、隐私监控、风扇写入控制、定时维护编排、显示器能力探测和统一审计必须自研或基于 Apple 原生 API。

## License 与安全结论

1. **Mole 不进入闭源核心**：当前仓库明确为 GPL-3.0；其公开安全设计可参考，但不得把代码复制到 LexCleaner。
2. **Pearcleaner 不进入核心，也不作为商业依赖**：Apache-2.0 叠加 Commons Clause，明确限制 Pearcleaner 或修改版的商业化；仓库当前还标记为 On Hold。其 2025 年高危 privileged XPC helper 漏洞说明了“root helper + 任意命令”设计不可接受，LexCleaner 不采用该模式。
3. **GPL/AGPL/Commons Clause 项目**：GrandPerspective、dupeGuru、OverSight、Latest、smartmontools、smcFanControl 等只做思路或隔离进程层研究；未完成许可证边界与组合方式审查前，不复制进核心。
4. **MIT/BSD/Apache-2.0 也不是无条件复制**：必须保留版权、NOTICE、许可证文本并锁定依赖版本；还要检查第三方依赖、资源和生成物的许可证。
5. **商业闭源产品**：只研究公开功能和交互，不逆向私有代码、素材或协议实现。
6. **特权与供应链**：root helper、XPC、SMC 写入、自动更新、外部脚本和网络监控都必须单独威胁建模；“开源”不等于可以直接嵌入或默认安全。

## 路线重新判断

第五阶段暂不开始。下一阶段若恢复开发，推荐顺序为：

1. 先完成 App Target 的完整 Xcode/xcodebuild 验证（环境允许时），不改变当前 Core 安全边界。
2. 单独建立 **Research-backed Monitoring Foundation**：先做只读 CPU/RAM/磁盘/网络/电池能力探测，优先 macOS 原生 API，Stats 只作为 MIT 参考来源。
3. 再做 **Disk Analysis** 的流式聚合和只读 Treemap 数据模型；不要先做删除联动。
4. App updater 若进入产品，直接评估 Sparkle，并建立签名密钥、更新源、回滚和供应链安全验收。
5. 风扇控制、SSD SMART、隐私监控、启动项修改、自动维护和显示器 DDC 均应后置，逐项完成硬件/权限/安全验证后再立项。

在上述工作之前，不应以增加模块数量为目标继续开发；现有 SafeDelete、Scan、Classification 和 Cleanup Pipeline 保持冻结并作为后续所有模块的安全边界。
