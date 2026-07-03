# V2rayN Sentinel(哨兵)

一个常驻 macOS 菜单栏应用,实时监控本机 **v2rayN** 的日志输出,发现 error 即分级弹窗报警。

- **所有 error** → 屏幕左上角小 toast(自动消失、不打断)。
- **重要 error** → 红色卡片 + 提示音 + 必须手动关闭。
- 菜单栏常驻、可查最近错误历史、运行方式可选(开机自启 / 手动启动)。
- 原生 Swift,零运行时依赖,对 v2rayN 零侵入(只读日志)。

> 当前处于**设计阶段**,尚未实现。完整设计见:
> [`docs/superpowers/specs/2026-07-02-v2rayn-sentinel-design.md`](docs/superpowers/specs/2026-07-02-v2rayn-sentinel-design.md)

## 状态

- [x] 需求与方案设计
- [ ] 实现计划
- [ ] 编码实现
- [ ] 测试与打包

## 平台

macOS(Apple Silicon),需已安装并运行 v2rayN(macOS 版)。
