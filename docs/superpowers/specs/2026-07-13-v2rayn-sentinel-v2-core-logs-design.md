# V2rayN Sentinel v2 — 内核日志监控 设计文档

> 在 v1(只盯 v2rayN GUI 日志)之上,扩展监控 **xray / sing-box 内核的连接级错误**(如 `i/o timeout`、连接被拒),并对高频连接错误做聚合与突发升级,避免刷屏。

- 日期:2026-07-13
- 状态:设计定稿,待用户复审 → 实现计划(writing-plans)
- 前置:v1 已完成(SentinelCore 逻辑层 + AppLogic 协调 + UI + 打包)

---

## 1. 背景与动机

v1 上线后发现:v2rayN 报的大量 `dial tcp 172.18.0.1:7881: i/o timeout` 这类**内核连接错误 Sentinel 没报警**。根因(已取证):

1. 这些是 **sing-box/xray 内核的连接级日志**,不写进 v1 监控的 GUI 日志(`guiLogs/YYYY-MM-DD.txt`)。
2. 默认它们**只打到内核 stdout、被 v2rayN 实时窗口显示、不落盘**。
3. 即便落盘,格式也与 GUI 的 Serilog 完全不同,v1 解析器不认。

**关键突破**:v2rayN 有原生开关 `CoreBasicItem.LogEnabled`。开启后 v2rayN 会给内核配置注入 `log` 段,把内核日志**写到 `guiLogs/` 目录**下带前缀的文件里(已实测):

| 文件名 | 来源 | 说明 |
|---|---|---|
| `sbox_YYYY-MM-DD.txt` | sing-box | 连接错误主战场(TUN) |
| `Verror_YYYY-MM-DD.txt` | xray | xray 错误日志 |
| `Vaccess_YYYY-MM-DD.txt` | xray | 每连接访问日志(无级别、量极大)——**不监控** |
| `YYYY-MM-DD.txt`(无前缀) | v2rayN GUI | v1 已监控 |

v2 的任务:让 Sentinel 也监控 `sbox_*` 与 `Verror_*`,并妥善处理其高频、异格式、连接级的特性。

## 2. 环境事实(已实测)

- **开启方式**:v2rayN 界面 设置→参数设置→Core 基础设置,勾选"启用日志";对应 `guiNConfig.json` 的 `CoreBasicItem.LogEnabled=true`、`Loglevel="warning"`。
- **副作用**:应用该设置时 v2rayN **重启内核**(代理短暂闪断)。这是 v2rayN 行为,与 Sentinel 无关。
- **注入的配置**(实测):
  - xray `config.json`:`"log": {"access": ".../guiLogs/Vaccess_<date>.txt", "error": ".../guiLogs/Verror_<date>.txt", "loglevel": "warning"}`
  - sing-box `configPre.json`:`"log": {"level": "warn", "output": ".../guiLogs/sbox_<date>.txt", "timestamp": true}`
- **真实格式样例**:
  - sing-box(`timestamp:true`):
    ```
    +0530 2026-07-06 19:31:37 ERROR [1456328237 5.0s] connection: open connection to 172.18.0.1:7881 using outbound/direct[direct]: dial tcp 172.18.0.1:7881: i/o timeout
    ```
  - xray(`Verror_`):
    ```
    2026/07/13 06:59:56.054278 [Warning] core: Xray 26.6.1 started
    ```

## 3. 需求(已与用户确认 A/B/C)

- **A · 监控范围**:监控 `sbox_*`(sing-box)+ `Verror_*`(xray 错误);**跳过** `Vaccess_*`。
- **B · 严重度**:连接错误**默认普通**(左上角小 toast、自动消失、无声);**突发升级**——同一目标在窗口内失败达到阈值时升级为**重要**(红色+声音+手动关)。
- **C · 聚合**:按「**错误类型 + 目标地址**」聚合成一条 `目标 类型 ×N`,边来边更新计数。
- **默认参数(用户已接受,均可配)**:突发窗口 **30s / 20 次**;升级冷却 **5 分钟**;内核报警级别门槛 **Error 及以上**(默认不报 WARN/[Warning]);聚合 toast 空闲 **10s** 后消失。

## 4. 非目标(v2 明确不做)

- 不监控 `Vaccess_*`(每连接访问日志,纯噪音)。
- 默认不对 sing-box `WARN` / xray `[Warning]` 报警(启动告警等噪音多),仅作可配开关。
- 不做连接错误的地理/统计分析、不做导出。
- 不自动开启 v2rayN 的 `LogEnabled`(那是用户在 v2rayN 里的操作,涉及内核重启)。

## 5. 架构

在 v1 基础上,把"监控"从**单文件**抽象为**多日志源(LogSource)**。

```
                         ┌──────────────── MultiWatcher(每秒轮询所有源)────────────────┐
 guiLogs/ ── 文件名匹配 ──▶│  LogSource(gui)      : Serilog 解析 → 简单去重(v1 行为)     │
          ── 文件名匹配 ──▶│  LogSource(singbox)  : sing-box 解析 → 分类+目标提取 → 聚合  │──▶ AppModel
          ── 文件名匹配 ──▶│  LogSource(xrayError): xray 解析     → 分类+目标提取 → 聚合  │
                         └──────────────────────────────────────────────────────────────┘
 AppModel ──▶ Aggregator(聚合/计数/突发升级/冷却) ──▶ Alerting(ToastManager 键控更新 + SoundPlayer)+ ErrorHistory
```

### 5.1 LogSource 抽象
```
LogSource {
    name: String                         // "gui" | "singbox" | "xrayError"
    matches: (filename: String) -> Bool  // 该源认领哪些 guiLogs 文件
    parser: LineParser                   // 该格式的解析器
    policy: SourcePolicy                 // 分类 + 是否走聚合
}
```
- `gui`:匹配 `^\d{4}-\d{2}-\d{2}\.txt$`(与 v1 一致),解析器 = 现有 Serilog,策略 = 简单去重(低频)。
- `singbox`:匹配 `^sbox_\d{4}-\d{2}-\d{2}\.txt$`,sing-box 解析器,策略 = 聚合。
- `xrayError`:匹配 `^Verror_\d{4}-\d{2}-\d{2}\.txt$`,xray 解析器,策略 = 聚合。

### 5.2 MultiWatcher
- 每秒对每个源:用 `LogFileLocator`(泛化为接受"文件名匹配"闭包)选出该源当天最新文件 → 用现有 `WatchDecision` 增量读取 → 该源的 `LineParser` 出记录 → 交 AppModel(带 source 标签)。
- 每个源各自维护 `currentFile / offset / parser 状态`(复用 v1 的 `LogWatcher` 单源逻辑,MultiWatcher 只是持有多个)。
- 若某源当天文件不存在(如 LogEnabled 未开)→ 该源静默,不报错。

### 5.3 解析器(小重构:header matcher 可插拔)
把 v1 `LogParser` 里写死的 Serilog 正则抽成 `HeaderMatcher` 协议,`LogParser(headerMatcher:)` 复用多行/增量机制。三个 matcher:
- **Serilog(gui)**:`^(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d+)-([A-Za-z]+) ?(.*)$`(现有)。
- **sing-box**:`^([+-]\d{2}:?\d{2}) (\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}) ([A-Z]+) (.*)$` → 时间戳、级别(ERROR/WARN/INFO/DEBUG/TRACE/FATAL/PANIC)、正文(含 `[连接id 时长]` 前缀)。
- **xray**:`^(\d{4}/\d{2}/\d{2} \d{2}:\d{2}:\d{2}(?:\.\d+)?) \[([A-Za-z]+)\] (.*)$` → 时间戳、级别([Debug]/[Info]/[Warning]/[Error])、正文。

产出统一的 `LogRecord`(复用 v1 结构)。

### 5.4 分类 + 目标提取
- **是否算错误(可配级别门槛)**:sing-box `ERROR/FATAL/PANIC`;xray `Error`。`coreAlertIncludesWarning=true` 时把 sing-box `WARN` / xray `Warning` 也纳入。
- **`ConnectionError` 提取**:从正文抠 `target(host:port)` 与 `kind`:
  - sing-box:`dial (?:tcp|udp) (\S+?:\d+): (.+)$` → target、kind(如 `i/o timeout`、`connection refused`)。
  - 抠不出时 → target=nil,聚合 key 退回"归一化后的整条正文"。
- **聚合 key**:`source + 归一化正文`;归一化 = 去掉 sing-box 的 `^\[\d+ [\d.]+s?\] ` 连接id 前缀、去掉易变的临时端口等。同目标同错误 ⇒ 同 key。

### 5.5 Aggregator(新组件:聚合 + 突发升级)
对每条"错误"记录(来自聚合策略的源):
- 维护 per-key:`count`、`windowStart`、`windowCount`、`lastSeen`、`escalatedUntil`。
- **聚合展示**:调 `Alerting.presentAggregated(key, target, kind, count, …)` → ToastManager **键控**:该 key 有活的普通 toast 就更新其 `×N` 文案并重置空闲计时;否则新建。
- **突发升级(B)**:定长窗口计数——`now - windowStart > burstWindow` 则重置 `windowStart=now, windowCount=0`;每条 `windowCount += 1`;当 `windowCount ≥ burstThreshold` 且 `now ≥ escalatedUntil` → 触发一次**重要**报警(红色+声音+手动关),置 `escalatedUntil = now + escalationCooldown`。
- **空闲消失**:普通聚合 toast 在该 key `aggregatedToastIdle` 秒无新错误后自动消失(ToastManager 按 key 的活动重置计时)。
- 注入 `now: Date` 便于测试。GUI 源**不走** Aggregator,沿用 v1 `Deduper` + 历史。

### 5.6 协调器(AppModel)变化
- `handle(_ record:, source:, now:)`:按 source 的策略路由——`gui` 走 v1 路径(分类→去重→弹窗+历史);`singbox/xrayError` 走 Aggregator。
- 历史记录:聚合类错误按 key 记一条(带 count),不逐行灌历史。

### 5.7 UI 变化
- **ToastManager**:新增"键控 toast"——`showOrUpdate(key:, view:)` 更新已存在的同 key toast;空闲计时按 key。重要升级 toast 仍是持久、手动关。
- **MenuContent**:历史里聚合错误显示 `目标 类型 ×N`。可选:若三个内核源当天文件都不存在,菜单提示"内核日志未开启(可在 v2rayN 里开启)"。
- **SettingsView**:新增内核监控相关设置(见 5.8)。

### 5.8 配置新增(Settings)
```
coreMonitoringEnabled: Bool = true       // 内核源总闸
burstWindowSeconds: Double = 30
burstThreshold: Int = 20
escalationCooldownSeconds: Double = 300
coreAlertIncludesWarning: Bool = false
aggregatedToastIdleSeconds: Double = 10
// 现有 noisePatterns / importantKeywords 同样作用于内核源
```

## 6. 与 v1 的兼容

- v1 的 `gui` 源行为**完全不变**;文件名匹配互斥(`^\d…\.txt$` vs `^sbox_…` / `^Verror_…`),不会误选。
- LogEnabled 未开时,内核源找不到文件 → 静默,App 正常工作(等同 v1)。
- v2 是**纯增量扩展**,不回改 v1 已加固的逻辑。

## 7. 测试策略(TDD,离线)

- **解析器**:sing-box / xray 各格式解析、级别提取、时区/小数秒变体、非 header 续行。
- **目标提取**:sing-box dial 超时/被拒、抠不出时回退整条正文。
- **Aggregator(注入时钟)**:计数累加、达阈值升级一次、冷却内不重复升级、窗口重置、空闲消失、多 key 独立。
- **MultiWatcher**:多源各自偏移、跨天、某源文件缺失时静默。
- **协调器**:gui→简单路径、core→聚合;升级只弹一次重要。
- UI(ToastManager 键控)以编译 + 手动冒烟为准(沿用 v1 口径)。

## 8. 边界与风险

- **格式演化**:sing-box/xray 版本升级可能微调格式;解析器匹配失败的行按"续行/忽略"处理,不崩。
- **时区前缀**:sing-box `+0530` / `+05:30` 两种写法都要容忍。
- **目标抠不出**:回退整条正文当 key,仍能聚合(只是显示为整条)。
- **依赖用户开关**:内核监控依赖 v2rayN 的 LogEnabled;App 不自动开(避免内核重启),仅可提示。
- **只读不变**:仍然只读 guiLogs、不写不锁不联网,安全性同 v1(见仓库 CLAUDE.md)。

## 9. 待用户确认 / 默认

- 默认参数:突发 30s/20 次、冷却 5 分钟、门槛 Error、聚合空闲 10s(均可在设置改)。
- 是否需要"内核日志未开启"的菜单提示(可选,默认做一个轻量提示)。

## 10. 未来

- 通知中心横幅作为可选渠道。
- 连接错误按目标的趋势统计。
- 自动识别当前活跃内核类型,动态启用对应源。
