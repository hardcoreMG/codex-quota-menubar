# Codex / Grok Bot 额度菜单显示小工具

在 macOS 菜单栏查看 Codex 和 Grok Bot 的今日预算、周剩余额度及重置时间。左侧是 Codex，右侧是 Grok Bot，以应用图标区分；只安装其中一个时，只显示对应应用。

原项目由嘉文钱开发并开源。本仓库由 [hardcoreMG](https://github.com/hardcoreMG) 持续维护，基于 [kevinchin12/codex-quota-menubar](https://github.com/kevinchin12/codex-quota-menubar)。工程内部名称保留为 `CodexQuotaBar`。问题和 PR 请提交到 [本仓库](https://github.com/hardcoreMG/codex-quota-menubar)，版本变化见 [CHANGELOG.md](CHANGELOG.md)。

## 从源码运行

环境要求：

- macOS 13 或更新版本。
- Swift 5.9 或更新的工具链，可通过 Xcode 或 Xcode Command Line Tools 安装。
- 按需安装并登录 Codex 或 Grok Bot，可仅安装其中一个。
- 显示 Grok 额度时，至少在 Grok Bot 中打开过一次用量菜单。

```bash
git clone https://github.com/hardcoreMG/codex-quota-menubar.git
cd codex-quota-menubar
./script/build_and_run.sh
```

脚本会构建 `dist/CodexQuotaBar.app` 并启动。要安装到本机，先从菜单退出正在运行的版本，再将整个 `.app` 复制到 `/Applications` 后打开；应用包内包含菜单栏所需的图标资源。

## 额度与提醒

| 位置 | 含义 | 颜色规则 |
| --- | --- | --- |
| 上行 `D` | 今日剩余预算，包含前几天结转的预算 | 高于 50% 整行绿色，低于 20% 整行红色，20%～50% 保持默认颜色 |
| 下行 `W` | 本周剩余额度 | 低于或等于 20% 时，`W` 胶囊标红 |
| Codex `5H` | 只有 5 小时窗口时直接显示；同时有周额度时可在悬停提示查看 | 直接显示时，低于或等于 20% 的胶囊标红 |
| Grok `试用` | 试用额度的剩余百分比 | 低于或等于 20% 时胶囊标红，不计算今日预算 |
| 重置卡 | Codex 可用次数、每笔到期时间及倒计时 | 距到期不足 3 天（72 小时）时，日期和倒计时整行标红 |

菜单保留单列布局，Codex 和 Grok 区域以粗横线分隔，显示各自的重置时间和倒计时。Codex 的周额度标为“Codex 周额度”；Grok 显示“Grok 上次刷新”。日期按本机时区显示，精确到分钟；倒计时统一为 `x天 HH:mm`。

重置卡按到期时间排序；接口仅返回部分明细时，菜单会提示尚未提供的次数。菜单栏的默认文字使用 macOS 模板图跟随系统前景色。

### 今日预算如何计算

每份日预算等于周总额度的 `1/7`。以周重置时间减去 7 天作为本周开始，重置当天分配一份，此后按本机时区每过一次零点增加一份，一周最多分配七份。减去本周已用额度后，得到截至今天的累计预算余额。

设截至今天已分配 `k` 份日预算，本周已用百分比为 `u`，则菜单中的今日剩余为：

```text
D = round(100 × k − 7 × min(u, 100))%
```

例如，已分配 3 天预算、本周已用 30% 时，`D = 300 − 210 = 90%`，`W = 70%`。`D` 的 100% 代表一份日预算；前几天没用完时可以超过 100%，例如已分配 2 天且本周只用了 10%，会显示 `D 130%`。

超过截至今天的累计预算时，`D` 保留负数并标红。例如已分配 3 天预算、本周已用 50%，会显示 `D -50%`、`W 50%`，表示已超用半份日预算。

今日预算是本工具按周额度计算的使用参考。缺少用量或周重置时间、已到重置时间时显示 `--`；Grok 试用额度不参与计算。

## 数据来源与刷新

### Codex

通过本地 `codex app-server` 的 `account/rateLimits/read` 查询额度。按额度窗口时长识别 5 小时和周额度，并读取可用重置卡信息。

应用通过 bundle id `com.openai.codex` 查找 Codex Desktop，或使用以下位置的 CLI：

- `/opt/homebrew/bin/codex`
- `/usr/local/bin/codex`

初始化和额度查询分别最多等待 15 秒、30 秒，超时后自动重试一次；失败时显示对应阶段。

### Grok Bot

已适配 Grok Bot 0.79.2 的本地 `weekly-usage.cache`（schema 2）。从以下位置读取当前账号标记和额度缓存，并检查本地登录状态：

```text
~/Library/Application Support/Grok Bot/sand-client-persistence
~/Library/Application Support/Grok Bot/desktop-status.json
```

本工具读取当前账号的缓存，不读取登录令牌、cookie 或浏览器 session，也不主动请求 Grok 服务端。Grok Bot 打开用量菜单后会更新缓存；需要最新额度时，先在 Grok Bot 中打开用量菜单，再展开本工具菜单。

“上次刷新”表示 **Grok Bot 上次查询额度的时间**。本工具重新读取同一份缓存时，该时间与额度数值保持不变。缓存达到自身过期时间、距上次查询满 24 小时或到达额度重置时间时失效，取三者中最早的时间。

### 自动刷新与安装检测

- 后台每轮读取完成后等待 60 秒再次刷新；打开菜单时立即读取，菜单展开期间每 60 秒更新额度和倒计时。
- Codex 和 Grok 独立读取；一方等待或失败时，另一方仍可显示。
- 启动及刷新时检查安装情况，只查询、显示已安装的应用；两者均未安装时隐藏菜单栏项。
- Grok 检查应用包和可执行文件，不把残留缓存当成已安装。未登录、暂无缓存或缓存过期时显示 `--`，并在菜单中给出具体提示。

## 构建与验证

```bash
swift test
swift build -c release
./script/build_and_run.sh --verify
```

`--verify` 会启动应用并检查进程是否存在。测试覆盖额度窗口映射、app-server 通信、Grok 缓存与账号隔离、安装检测、独立刷新、今日预算结转及颜色阈值。

生成本机自用 DMG：

```bash
./script/package_dmg.sh
```

当前脚本生成 `dist/CodexQuotaBar-0.1.5.dmg`，使用 ad-hoc 签名。仓库默认分享源码；向其他用户分发安装包前，需要 Apple Developer ID 签名和 notarization，详见 [RELEASE.md](RELEASE.md)。

## 资源与兼容性

- App 图标位于 `Assets/`；菜单栏应用标识位于 `Sources/CodexQuotaBar/Resources/`，取自 Codex 与 Grok Bot 的应用图标资源，相关品牌标识归各自权利人所有。
- Codex 的本地 app-server 协议和 Grok Bot 的缓存格式可能随应用更新变化，需要相应适配。
- 如果 Codex 安装在非标准位置且 Launch Services 无法找到，可调整 `Sources/CodexQuotaBar/Services/CodexAppServerClient.swift` 的 `codexExecutableURL()`。

## 开源协议

MIT License，见 [LICENSE](LICENSE)。

Copyright (c) 2026 Kevin Chin / 嘉文钱
