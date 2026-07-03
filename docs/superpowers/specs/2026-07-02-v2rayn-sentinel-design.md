# V2rayN Sentinel — 设计文档

> 一个常驻 macOS 菜单栏应用,实时监控 v2rayN 的日志输出,发现 error 即分级弹窗报警。
> 应用名 **V2rayN Sentinel(哨兵)** 为暂定,可改。

- 日期:2026-07-02
- 平台:macOS(Apple Silicon,arm64)
- 状态:设计已定稿,待用户复审 → 进入实现计划(writing-plans)

---

## 1. 目标

在后台实时盯住本机 v2rayN 的日志,一旦出现错误就用弹窗提醒用户,并按严重程度分两级处理,避免漏看真故障、也不被日常噪音打扰。做成一个"值得长期用"的正经应用,而不是裸脚本。

## 2. 环境事实(已在本机实测)

- **v2rayN**:`/Applications/v2rayN.app`,macOS 版 V7.20.4(Avalonia 跨平台版),当前运行中。
- **内核**:`xray`(代理)+ `sing-box`(TUN,经 sudo,root 运行),均正常。
- **日志落点**:`~/Library/Application Support/v2rayN/guiLogs/`,**按天一个纯文本文件**,文件名即日期,如 `2026-07-02.txt`,内容持续追加。
- **日志行格式**:`YYYY-MM-DD HH:MM:SS.ffff-LEVEL 内容`,级别有 `INFO / DEBUG / ERROR`(未见 WARN/FATAL,但按可能出现处理)。
  - ERROR 示例:
    ```
    2026-06-25 10:51:33.7293-ERROR CliWrap.Exceptions.CommandExecutionException: Command execution failed because the underlying process (mihomo#2615) returned a non-zero exit code (1).
    ```
  - 多行异常:异常堆栈的后续行**没有时间戳前缀**(如 `Standard error:` 续行),解析时需归属到上一条带时间戳的记录。
- **现有 ERROR 全是两类噪音**(过去一周 14 条,全部属于以下两类):
  1. `mihomo#NNNN` 非零退出码(1)—— 节点测速失败。
  2. `bash#NNNN` 退出码 127 —— 订阅更新脚本。
- **工具链**:Xcode 26 + Swift 6.3.3 已装;`osascript / afplay / launchctl` 系统自带。
- **屏幕**:双显示器(内置 Retina 3024×1964 + 外接 1920×1080)——"左上角"需指定落屏。

## 3. 需求(来自用户)

### 功能需求
- **F1 全部 error → 左上角小弹窗**:每出现一条 `-ERROR` 行,在指定屏幕左上角弹一个轻量小 toast,自动消失、不打断操作、可堆叠。
- **F2 重要 error → 醒目常驻**:被判定为"重要"的错误,弹更醒目的红色卡片 + 播放提示音 + **必须手动关闭**(不自动消失)。
- **F3 "重要"判定**:非噪音的 ERROR/FATAL 一律算重要;已知噪音(mihomo 测速、订阅 bash 退出码)降级为"普通",只走小 toast。判定规则在设置里可编辑。
- **F4 正经应用形态**:菜单栏常驻 App,有图标、状态、设置界面、错误历史。
- **F5 运行方式可选**:用户可在 App 内切换"开机自启"或"手动启动"。

### 非功能需求
- 零运行时依赖(原生 Swift,标准 `.app`)。
- 对 v2rayN **零侵入**——只读日志,不改其任何配置或文件。
- 低资源占用(轻量轮询)。

## 4. 非目标(v1 明确不做)

- **不监控 xray 逐条连接日志**(如"连接被拒""握手超时")。这类日志默认走 v2rayN 的应用内实时窗口、不落到 guiLogs 文件。留作 **v2 扩展**(让 xray 把 error 日志写到文件,再一并 tail)。
- 不做统计报表、不做通知历史云同步、不做多语言(v1 中文界面即可)。
- 不监控除 v2rayN 之外的其它应用。

## 5. 技术选型

**原生 Swift + SwiftUI/AppKit**(已选定)。

理由:工具链现成、零运行时依赖、原生质感最好,并且能精确控制弹窗的**位置(左上角)、样式(红色)、置顶、是否自动消失、手动关闭**——这些正是需求核心,Web/脚本方案难以同等精细地做到。

打包为标准 `.app` bundle,`LSUIElement = true`(纯菜单栏 App,不在 Dock 显示)。

## 6. 架构

```
┌─────────────────────────── V2rayN Sentinel.app (LSUIElement) ───────────────────────────┐
│                                                                                          │
│  MenuBarController (NSStatusItem)                                                         │
│    ├─ 状态项:监控中 / 已暂停   (点击切换 pause)                                          │
│    ├─ 最近错误历史子菜单       (点开看全文;toast 会截断/消失,这里留底)                  │
│    ├─ 打开设置窗口                                                                        │
│    └─ 退出                                                                                │
│                                                                                          │
│  SettingsWindow (SwiftUI)                                                                 │
│    开机自启开关 · 声音开关+选音效 · 普通 toast 停留秒数 · 规则编辑 · 落屏选择             │
│                                                                                          │
│  ┌──────────────┐   error 行    ┌──────────────┐  分级   ┌──────────────────────────┐   │
│  │ LogWatcher   │ ───────────▶ │ Classifier   │ ──────▶ │ AlertCoordinator         │   │
│  │ 轮询 guiLogs │              │ 噪音/普通/重要│         │  ├─ ToastManager (窗口栈) │   │
│  │ 增量+跨天    │              └──────────────┘         │  ├─ SoundPlayer (NSSound) │   │
│  └──────────────┘                                       │  └─ ErrorHistory (留底)   │   │
│                                                                                          │
│  SettingsStore (UserDefaults + Codable)  ← 所有开关/规则/停留秒数/落屏                    │
│  LoginItemManager (SMAppService)         ← 开机自启注册/注销                              │
└──────────────────────────────────────────────────────────────────────────────────────┘
```

### 组件职责
- **LogWatcher**:定位 guiLogs 中"当天"文件,轮询(默认 1s)读取新增字节;记住字节偏移只处理增量;跨天时切到新文件;文件被截断(v2rayN 重启)时偏移复位。把完整的一条日志记录(含多行续行)交给 Classifier。
- **Classifier**:解析级别;判断是否 error(ERROR/FATAL);匹配噪音白名单 → 普通;否则 → 重要。规则来自 SettingsStore。
- **AlertCoordinator**:据分级触发 ToastManager / SoundPlayer / ErrorHistory;做**去重节流**(同类错误默认 60s 冷却)。
- **ToastManager**:管理左上角弹窗窗口栈(NSPanel);普通 toast 定时淡出,重要 toast 常驻等手动关。
- **ErrorHistory**:环形缓存最近 N 条(默认 200),供菜单栏历史查看。
- **SettingsStore / LoginItemManager**:持久化配置、管理登录项。

## 7. 详细行为

### 7.1 日志监控(LogWatcher)
- 每 1s(可配)扫描 guiLogs,取文件名日期最大的 `.txt` 作为当前文件。
- 首次启动:定位到当前文件**末尾**开始监控(不回放历史,避免启动即刷一堆旧弹窗)。
- 用字节偏移增量读;仅当读到**下一条带时间戳的行**或 EOF 稳定后,才认为上一条记录完整(以正确合并多行异常)。
- 跨天:发现更"新"日期的文件出现,切换并从其开头读。
- 截断检测:文件大小 < 上次偏移 → 判为轮转/重启,偏移归零。

### 7.2 分级(Classifier)
```
是 error 吗?  →  行级别 ∈ {ERROR, FATAL}     (大小写不敏感)
   否 → 忽略(INFO/DEBUG 不弹)
   是 → 命中"噪音白名单"?
          是 → 普通 error(小 toast)
          否 → 重要 error(红色 + 声音 + 手动关闭)
```
- **噪音白名单默认项**(正则,可在设置增删):
  - `mihomo#\d+.*non-zero exit code`
  - `bash#\d+.*exit code \(127\)`
- 未来可选:额外"重要关键词"表(如 `panic|fatal|crash`)强制升级,即便未来出现新噪音也不误降。

### 7.3 两级弹窗 UX(ToastManager)
- **落点**:主屏(带菜单栏那块,可在设置改为指定屏)左上角,菜单栏下方留 ~12pt 边距,向下堆叠。
- **普通 toast**:
  - 窄卡片(约 360×64),深色半透明圆角,白字:`时间 · 错误摘要(截断 ~80 字)`。
  - 无声音;默认 **5s** 后淡出(秒数可配);点击立即关闭。
  - 非激活窗口(`NSWindow.isMovableByWindowBackground = false`,`level = .statusBar`,`collectionBehavior` 含 `.canJoinAllSpaces`,不抢焦点)。
- **重要 toast**:
  - 更大卡片(约 420×，自适应高度),**红色标题栏/红边框**,右上角 **✕** 关闭按钮。
  - 播放提示音(NSSound,可选系统音);**不自动消失**。
  - 内容更全:时间 + 级别 + 首行摘要 +(可展开看多行详情)。
  - 堆积多个时,顶部提供"全部关闭"。
- **堆叠上限**:屏幕放不下时,超出的排队,旧的关闭后补位(避免糊满屏幕)。

### 7.4 去重节流(AlertCoordinator)
- 以"归一化错误签名"(去掉 `#\d+` 进程号、时间戳后的稳定文本)为 key。
- 同一 key 在冷却窗口(默认 60s,可配)内只弹一次;窗口内重复次数在历史里累加计数。

### 7.5 菜单栏与历史
- 图标:正常态 = 常规图标;有未读重要错误 = 变色/带红点。
- 下拉:监控开关、最近错误(点条目看全文、可复制)、清空历史、打开设置、退出。

### 7.6 开机自启(LoginItemManager)
- 用 **SMAppService.mainApp**(macOS 13+ 现代 API)注册/注销登录项。
- 设置里一个开关;状态与系统"登录项"保持一致。

## 8. 配置模型(SettingsStore,持久化到 UserDefaults)

```
Settings {
  monitoringEnabled: Bool = true
  launchAtLogin: Bool = false            // 用户可选,默认关
  soundEnabled: Bool = true
  soundName: String = "Basso"            // 系统音,可选
  ordinaryToastSeconds: Double = 5
  dedupeCooldownSeconds: Double = 60
  targetScreen: "main" | <displayID>     // 默认 main
  noisePatterns: [String]                // 默认见 7.2,可增删
  importantKeywords: [String] = []       // 可选强制升级词
  historyLimit: Int = 200
  logDirOverride: String? = nil          // 默认自动定位 guiLogs
}
```

## 9. 项目结构(建议)

```
v2rayN-sentinel/
├─ V2rayNSentinel.xcodeproj  (或 Swift Package + xcodegen)
├─ Sources/
│  ├─ App.swift                 // @main, AppDelegate/LSUIElement
│  ├─ MenuBar/MenuBarController.swift
│  ├─ Watch/LogWatcher.swift
│  ├─ Watch/LogRecord.swift     // 一条记录(含多行合并)
│  ├─ Classify/Classifier.swift
│  ├─ Alert/AlertCoordinator.swift
│  ├─ Alert/ToastManager.swift
│  ├─ Alert/ToastWindow.swift   // NSPanel 子类
│  ├─ Alert/SoundPlayer.swift
│  ├─ History/ErrorHistory.swift
│  ├─ Settings/SettingsStore.swift
│  ├─ Settings/SettingsWindow.swift
│  └─ System/LoginItemManager.swift
├─ Tests/
│  ├─ ClassifierTests.swift     // 噪音/普通/重要判定
│  ├─ LogParserTests.swift      // 多行合并、跨天、截断
│  └─ DedupeTests.swift         // 归一化签名、冷却
└─ docs/superpowers/specs/2026-07-02-v2rayn-sentinel-design.md
```

## 10. 测试策略

- **纯逻辑单测**(不依赖真实 v2rayN):
  - Classifier:两类噪音降级、其它 ERROR 升级、大小写、FATAL。
  - LogParser:多行异常合并、无时间戳续行归属、跨天切换、文件截断复位、启动定位到末尾。
  - Dedupe:进程号/时间戳归一化、冷却窗口计数。
- **手动/集成验证**:用一个"喂日志"测试脚本往临时目录按格式追加行,观察弹窗与声音表现(用 `logDirOverride` 指向临时目录,不动真日志)。

## 11. 边界与风险

- **多行异常**:靠"下一条时间戳行"界定记录边界,末条可能延迟到下一行到达才判定——可接受(秒级)。
- **多显示器**:落屏用 displayID;显示器热插拔后目标屏消失 → 回退到主屏。
- **日志目录变动**:v2rayN 若升级改路径 → `logDirOverride` 兜底 + 找不到时菜单栏提示。
- **权限**:guiLogs 属当前用户,读取无需特殊权限;App 无需 sudo。
- **noise 误判**:若真故障恰好文本像噪音而被降级 → 由 importantKeywords 强制升级兜底。

## 12. 未来扩展(v2+)

- 纳入 xray/sing-box 连接级 error(启用内核文件日志或捕获 stdout)。
- 通知中心横幅作为可选报警渠道之一。
- 错误分类统计与趋势、导出。
- 可点弹窗直接"重启内核/切换节点"等一键动作(需与 v2rayN 交互,评估可行性)。

## 13. 待用户确认 / 已知留空

- 应用名 **V2rayN Sentinel** 暂定,可改。
- 重要 toast 的位置沿用左上角(用户未单独指定,取与普通一致的合理默认)。
- 提示音默认 `Basso`,可在设置改。
