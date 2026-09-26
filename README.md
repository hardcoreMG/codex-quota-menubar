# Codex 额度菜单显示小工具

一个极简的 macOS 菜单栏小工具，用来直接显示 Codex 账户可用的额度窗口。

原项目由嘉文钱开发并开源。本仓库由 [hardcoreMG](https://github.com/hardcoreMG) 持续维护，基于 [kevinchin12/codex-quota-menubar](https://github.com/kevinchin12/codex-quota-menubar)。工程内部名称保留为 `CodexQuotaBar`。

本维护版本包含菜单栏外观、构建路径兼容性及额度窗口识别修复。后续问题和 PR 请提交到 [本仓库](https://github.com/hardcoreMG/codex-quota-menubar)，版本变化见 [CHANGELOG.md](CHANGELOG.md)。

<img width="2500" height="3333" alt="幻灯片12" src="https://github.com/user-attachments/assets/17b1d78e-0c44-4e8b-a82f-177e8e5ee2dd" />

## 适合用在

- 想在 macOS 顶部菜单栏里一直看到 Codex 剩余额度。
- 想快速确认账户可用额度窗口的刷新时间。
- 想在额度低于或等于 20% 时有一个明显提醒。
- 自己日常使用 Codex，希望少打开一个页面或少进一次 Codex 面板。

## 功能

- 菜单栏按账户实际限制显示剩余额度百分比：Plus 显示 `5H` 和 `W`，Pro 只显示 `W`。
- 菜单里显示对应额度窗口的刷新时间，精确到分钟；周额度同时显示倒计时，所有倒计时统一为 `x天 HH:mm`。
- 展示 重置卡 可用数量及每笔到期时间（本地时区），左侧显示到期时间、右侧显示剩余倒计时，均精确到分钟；按到期先后排序，菜单展开时每分钟更新剩余倒计时和额度数据；接口仅返回部分明细时会明确提示。
- 默认启用低额度提醒：剩余额度低于或等于 20% 时，胶囊标记变红。
- 每 5 分钟自动读取一次额度，打开菜单时也会读取一次，展开期间每分钟读取一次。
- 使用 macOS 原生模板图自动跟随菜单栏前景色，无需屏幕录制权限或壁纸取色。
- 不直接读取 `auth.json`、cookie、浏览器 session 或账号敏感文件。

## 重要说明

这个仓库推荐以源码方式分享，不默认发布预构建的 `.app` 或 `.dmg` 安装包。

原因是 macOS Gatekeeper 会拦截未经过 Apple Developer ID 签名和 notarization 公证的第三方二进制文件。别人直接下载未公证的安装包时，系统可能提示“无法打开”或识别为风险软件。

推荐使用方式是：下载源码后，在自己的 Mac 上本地构建成自用 app。

## 环境要求

- macOS 13 或更新版本。
- 已安装并登录 Codex Desktop。
- Codex Desktop 可通过 bundle id `com.openai.codex` 找到，或者本机存在：
  - `/opt/homebrew/bin/codex`
  - `/usr/local/bin/codex`

工具通过 Codex 本地 app-server 协议读取额度：

- `account/rateLimits/read`

## 从源码运行

```bash
git clone https://github.com/hardcoreMG/codex-quota-menubar.git
cd codex-quota-menubar
./script/build_and_run.sh
```

这会在本机编译并启动菜单栏 app。

## 构建自用 DMG

```bash
./script/package_dmg.sh
```

生成文件：

```text
dist/CodexQuotaBar-0.1.5.dmg
```

注意：这个脚本默认使用 ad-hoc 签名，只适合本机自用或开发测试。不要把这个未公证的 DMG 当成正式安装包分发给其他人。

## 图标

App 图标源文件和 `.icns` 文件在：

```text
Assets/
```

## 已知限制

- Codex 的本地 app-server 协议不是公开稳定 API，未来 Codex 更新后可能需要适配。
- 默认打包脚本不会做 Apple Developer ID 签名和 notarization。
- 如果 Codex 安装在非标准位置，并且 Launch Services 找不到，需要调整 `CodexAppServerClient.swift` 里的 `codexExecutableURL()`。

## 开源协议

MIT License。

Copyright (c) 2026 Kevin Chin / 嘉文钱
