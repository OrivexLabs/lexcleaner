# LexCleaner 项目规则

本文件是全局 Codex 工程规则的项目级补充，不能降低全局规则要求。

## 当前阶段边界

- 当前阶段维护 Core Services、`SafeDeleteEngine`、`ScanEngine`、`ClassificationEngine`、`CleanupPlanner`、只读 Monitoring/Hardware Foundation，以及已授权的 SwiftUI App Shell、Dashboard 和 Cleaner 完整 UI。
- App Shell/Dashboard/Cleaner 只能连接真实 Core 值类型和服务；Cleaner 是唯一已授权的执行编排入口，必须严格经过 CleanupPlan、Dry Run、明确确认、Preflight 和 SafeDeleteEngine，不能绕过 Core。
- App Manager、Disk Analyzer、System Tools 等后续最终交互仍只保留诚实页面骨架；不得由 Cleaner UI 扩大到卸载、永久删除或系统控制。
- App Manager UI 允许对用户明确选择的 App 本体和高置信度 residual 生成 UninstallPlan，并严格复用 CleanupPlanner → Dry Run → Confirmation → Preflight → SafeDeleteEngine。应用本体仅允许精确路径、reviewRequired、显式选择后移入 Trash；shared/protected/unknown、symlink、路径或身份变化必须拒绝。不得永久删除、使用特权 helper、删除用户个人目录或自动卸载。
- System Tools 本阶段只允许读取启动项、公开隐私状态和更新 metadata；禁止 enable/disable/delete、权限修改、自动安装更新或私有 TCC/BTM 读取。
- `Monitoring Foundation` 仅允许只读采样与值类型结果；禁止风扇/系统设置控制、进程结束、系统优化、自动化和任何需要 root 的路径。
- `Hardware Observability Foundation` 仅允许经过 API 审计的只读硬件信息、电池、电源来源、thermal state 和存储基础属性；SMC/IOReport/private API、root helper、sudo、风扇控制、功耗 shell 采样和系统写入均禁止。
- 硬件指标必须显式区分 `available`、`unavailable`、`unsupported`；不得以零值、默认值或推测值冒充不可用数据。
- `ClassificationEngine` 只负责只读分类和风险判断，不调用删除服务、不提供删除按钮，也不执行真实删除。
- 任何新增模块必须先更新 `GOAL.md`、`ARCHITECTURE.md` 和 `ACCEPTANCE.md`。

## `feat/monitoring-hardware-ui` 分支边界

- 本分支在既有只读 Monitoring/Hardware Foundation 之上仅新增 SwiftUI 展示层；不扩展 Core 数据源，不新增 private API、root helper、shell 采样或系统写操作。
- UI 必须直接消费 Core 的真实快照；`unsupported`、`unavailable` 和取消/错误状态必须显式展示，不得补零、猜测或使用 mock 数据。
- 采样任务由页面生命周期管理：页面/场景离开时取消，刷新频率必须受控，进程列表必须有资源上限，趋势历史必须有界。
- 新增的 UI 交互只允许展示、刷新频率、外观和栏目选择，不提供进程结束、风扇控制、优化或任何系统修改。

## SafeDeleteEngine 安全要求

- 所有路径必须是绝对路径，且经过标准化和实际 symlink 解析。
- 根目录、当前用户 Home 和系统关键目录永远拒绝删除；白名单不能覆盖这些硬保护。
- 目标必须同时满足白名单边界和解析后路径边界检查。
- 默认只允许 Dry Run 或移动到系统 Trash；禁止直接 `removeItem` 作为产品删除路径。
- 任何真实删除测试只能使用临时测试目录和真实 `FileManager.trashItem`。
- 新增删除策略时必须增加正常路径和危险路径测试。

## ClassificationEngine 安全要求

- 默认 fail-closed；未知路径、规则冲突、源文件变化和未知数据用途不得进入 `safe`。
- 不得仅按扩展名、大小或 `Library` 位置把对象标记为安全。
- Documents、Desktop、Downloads、Projects、Git、SSH/GPG、Keychains、浏览器 Profile、邮件、Messages、Photos、Music、iCloud Drive 和系统路径必须保护。
- symlink 叶节点和允许根之后的 symlink 组件必须保护；macOS `/var` 等系统别名只能在允许根边界之前解析，不得误放行越界目标。
- 分类结果不得自动传给 `SafeDeleteEngine`。

## CleanupPlanner 安全要求

- 只有 `safe`，或用户明确选择且确认的 `reviewRequired`，可以成为执行候选。
- `protected`、`unknown`、`sourceChanged`、规则冲突和任何身份不一致必须拒绝。
- Dry Run 只生成报告；任何 Trash 操作必须经过计划、明确选择、Dry Run、Preflight 和 `SafeDeleteEngine`。
- Preflight 通过后、调用 `SafeDeleteEngine` 前仍必须逐项重新校验；不得把旧 Preflight 当作永久授权。
- 永远不提供自动永久删除路径；每项结果和审计事件独立记录。

## Cleaner UI 安全边界

- 默认扫描只使用四类内置 ScanRule；UI 不创建 Mock 候选，也不直接调用 `FileManager.trashItem`、`removeItem` 或 SafeDelete 删除 API。
- safe 项默认选中但必须允许用户取消；reviewRequired 只有用户主动选择才可进入计划；protected/unknown 永远不可选择。
- UI 的受控 Trash 验证只能由显式测试启动参数创建临时 fixture，禁止将真实用户缓存作为 E2E 删除目标。
- 取消、空结果、扫描问题、Preflight 拒绝和 Partial Failure 必须在界面上诚实显示，不得将拒绝伪装为成功。

## 工程与验证

- Swift 6、SwiftUI、Swift Concurrency，优先 Apple Silicon 和 macOS 原生 API。
- Core 服务保持 UI 无关；跨模块状态通过明确协议或值类型传递。
- Monitoring 采样不得阻塞主线程；必须可取消、限制资源占用、不依赖 private API；任何第三方参考必须遵守 `TECH_DECISION_MATRIX.md` 的 License 决策。
- Hardware 采样必须使用 Swift Concurrency、可取消、不阻塞主线程、不要求 root；新增 API 先记录到 `HARDWARE_API_AUDIT.md` 并完成 License/风险判断。
- 真实测试必须在进入下一模块前通过；不能以编译成功替代运行验证。
- 操作日志不得记录 Token、密码或未必要的敏感内容；路径由日志后端按隐私级别处理。
