# 维护与发布

项目名称：Codex / Grok Bot 额度菜单显示小工具。原作者：嘉文钱；本仓库维护者：hardcoreMG。Swift 工程名及应用包名保留为 `CodexQuotaBar`。

## 日常维护

日常功能开发和修复默认在本仓库 `main` 分支进行，验证后提交并推送到 `origin/main`。提交按功能或修复拆分，采用 Conventional Commits，描述和正文使用中文。

- `origin`：`hardcoreMG/codex-quota-menubar`
- `upstream`：`kevinchin12/codex-quota-menubar`

用 `git fetch upstream` 查看上游更新，审查后按需合并并重新验证。普通开发改动记入 `CHANGELOG.md` 的“未发布”；正式发布时再更新打包脚本的版本号、README 中的产物名称和 CHANGELOG，并创建对应版本 tag。

## 构建验证

在仓库根目录运行：

```bash
swift test
swift build -c release
bash -n script/build_and_run.sh script/package_dmg.sh
./script/build_and_run.sh --verify
```

`--verify` 会重启 `dist/CodexQuotaBar.app` 并检查进程存在；菜单布局、点击和系统配色需要在应用中检查。

自动化测试覆盖：

- Codex 额度窗口映射、app-server 初始化顺序、分段响应、提前退出及超时阶段。
- Grok 当前账号缓存隔离、登录状态、schema、长缓存键、过期时间及试用额度。
- 单独安装、同时安装、均未安装以及安装状态变化时的数据读取。
- 单侧失败或仍在等待时，另一侧能独立更新。
- 今日预算结转、本机零点增加份额、最多七份、颜色阈值与重置卡 72 小时边界。

## 界面验收

| 场景 | 预期 |
| --- | --- |
| 两者均已安装 | 左侧 Codex 图标，右侧 Grok 图标；下拉菜单单列，两个应用区域以粗横线分隔 |
| 仅安装其中一个 | 只显示对应应用的额度和菜单项 |
| 两者均未安装 | 隐藏菜单栏项 |
| 有周额度及重置时间 | 上行 `D` 显示今日剩余，下行 `W` 显示周剩余 |
| Codex 同时有 5 小时和周额度 | 菜单栏显示 `D` / `W`；悬停保留 `5H` 剩余，菜单保留其刷新时间 |
| Codex 只有 5 小时额度 / Grok 试用 | 显示对应 `5H` / `试用`，不推算日预算 |
| 今日剩余 51% / 50% / 20% / 19% | 整行依次为绿色 / 默认 / 默认 / 红色 |
| 周剩余 20% | `W` 胶囊标红 |
| 重置卡距到期 72 小时 / 小于 72 小时 | 前者默认颜色，后者日期和倒计时整行标红 |
| Grok 缓存没有更新 | “上次刷新”保持原查询时间；过期后额度显示 `--` 及提示 |
| 菜单展开超过一分钟 | 额度和倒计时继续更新 |
| 浅色、深色菜单栏 | 默认文字跟随系统前景色，应用图标和红绿提醒清晰可见 |

## 构建自用 DMG

```bash
./script/package_dmg.sh
```

当前输出：

```text
dist/CodexQuotaBar.app
dist/CodexQuotaBar-0.1.5.dmg
```

脚本使用 release 构建和 ad-hoc 签名。两个构建脚本都会把 SwiftPM 的 `CodexQuotaBar_CodexQuotaBar.bundle` 复制到 `.app/Contents/Resources/`，其中包含 Codex 和 Grok 菜单栏图标。检查应用包时应确认这两个文件存在：

```text
Contents/Resources/CodexQuotaBar_CodexQuotaBar.bundle/Contents/Resources/CodexProvider.png
Contents/Resources/CodexQuotaBar_CodexQuotaBar.bundle/Contents/Resources/GrokProvider.icns
```

安装或升级时，先退出旧版，再将完整 `.app` 复制到 `/Applications` 并打开。不要只替换可执行文件。

## 对外分发

GitHub 仓库默认发布源码，用户 clone 后在自己的 Mac 上构建。ad-hoc 签名的 DMG 适合本机自用或开发测试；其他用户下载后可能被 Gatekeeper 拦截。

正式分发安装包前：

1. 使用 Apple Developer ID Application 证书签名 `.app`，开启 hardened runtime。
2. 使用 Apple Developer ID 签名 `.dmg`。
3. 提交 Apple notarization，通过后执行 `xcrun stapler staple`。
4. 用 `spctl` 验证 Gatekeeper 接受情况，并在目标 Mac 上完成启动和菜单验收。
