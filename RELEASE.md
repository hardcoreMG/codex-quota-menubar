# 发布说明

项目名称：Codex 额度菜单显示小工具

开发者：嘉文钱

工程名：`CodexQuotaBar`

## 推荐发布方式

GitHub 仓库默认只发布源码，不发布预构建的 `.app` 或 `.dmg`。

原因：未经过 Apple Developer ID 签名和 notarization 公证的 macOS 二进制文件，会被 Gatekeeper 识别为不可信来源。别人直接下载后可能无法正常打开。

推荐用户自己 clone 源码后，在本机运行：

```bash
./script/build_and_run.sh
```

如果用户想生成自用安装包：

```bash
./script/package_dmg.sh
```

生成产物：

```text
dist/CodexQuotaBar-0.1.1.dmg
```

这个 DMG 默认是 ad-hoc 签名，只适合本机自用或开发测试。

## 本地验证

```bash
open dist/CodexQuotaBar.app
pgrep -fl CodexQuotaBar
```

菜单栏应该显示：

```text
5H <percent>
W  <percent>
```

打开菜单后检查：

- `5H 刷新` 和 `W 刷新` 显示具体日期和时间，精确到分钟。
- `低额度提醒` 是可见的滑块开关。
- 开启低额度提醒后，低于或等于 20% 的额度胶囊变红。
- 深色菜单栏下文字和胶囊仍然清晰可读。

## 如果要发布正式安装包

正式分发 `.dmg` 前需要：

1. 使用 Apple Developer ID Application 证书签名 `.app`。
2. 开启 hardened runtime。
3. 使用 Apple Developer ID 签名 `.dmg`。
4. 提交 Apple notarization。
5. notarization 通过后执行 `xcrun stapler staple`。
6. 用 `spctl` 做 Gatekeeper 验证。

未完成以上步骤时，不建议把 `.dmg` 上传到 GitHub Releases 作为面向其他用户的安装包。
