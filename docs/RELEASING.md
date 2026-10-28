# 发布指南

## 版本和验证

1. 在 `Resources/Info.plist` 设置 `CFBundleShortVersionString`（如 `0.1.0`）并递增 `CFBundleVersion`。应用 RPC 客户端版本读取该元数据；`swift run` 使用 `development`。
2. 更新 `CHANGELOG.md` 和对应的 `docs/releases/v<版本>.md`，填写实际变化、资产类型和验证范围。正式发布日期在发布时填写。
3. 运行 `./scripts/verify.sh`。它会完成离线检查、Release 构建、签名校验和 ZIP 打包，产物保存在 `dist/`。
4. 在目标设备验证首次启动、CLI 查找、未登录、网络断开、刷新、睡眠唤醒、多屏和外观；未覆盖的平台明确标注。

默认使用当前架构。`CODEX_METER_ARCH=arm64` 或 `x86_64` 可显式指定单一架构；交叉编译通过不等于目标设备已验证。首发工作流仅提供 arm64 包。

```bash
CODEX_METER_TAG=v0.1.0 ./scripts/package-release.sh
```

`CODEX_METER_TAG` 可选；设置后必须与 Info.plist 版本一致。安装包内包含许可证和图标，签名前剥离调试符号并检查本机路径。包名标注架构和签名状态，同目录提供 SHA-256 校验文件。

## GitHub 工作流

- `ci.yml`：main 分支提交、PR 或手动触发，运行检查并上传 14 天保留的 ZIP 和校验值。不需要账号或发布密钥。
- `release.yml`：推送 `v*` 标签后，校验版本及发布说明，检查和打包，随后创建 **Draft Release**。不会自动公开 Release。
- Actions 制品是临时构建结果；发布后的 Release 附件独立保存，不受上述 14 天保留设置影响，适合作为长期下载入口。删除仓库、Release 或附件会使下载失效。
- 两个工作流均选择 `macos-15` / Xcode 26.2；更新 runner 时核对 [官方镜像工具列表](https://github.com/actions/runner-images/blob/main/images/macos/macos-15-arm64-Readme.md)。
- 默认只生成 ad-hoc 包。CI 不导入开发者证书，不读取 Codex 登录信息。

仓库尚未创建时，先在 GitHub 创建目标仓库并配置远程。完成首次提交和 main 分支推送后，再为已检查的提交添加标签：

```bash
git tag -a v0.1.0 -m "发布 Codex Meter v0.1.0"
git push origin v0.1.0
```

标签推送是上述工作流的触发点。工作流成功后，在 GitHub Releases 核对草稿，再由维护者点击 Publish。若标签已有 Release，工作流会失败，避免覆盖已存在的版本；修复失败构建后，在没有已有 Release 的情况下可重新运行工作流。

## Developer ID 签名和公证

要提供普通用户方便打开的包，需要维护者自己的 Apple Developer ID Application 证书及公证凭据。相关流程见 [Apple Developer ID](https://developer.apple.com/developer-id/) 和 [公证说明](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)。

先将证书导入本机 Keychain，并使用 `xcrun notarytool store-credentials` 按交互提示保存公证凭据到自选 profile。证书和凭据不要加入仓库。

```bash
export CODEX_METER_SIGN_IDENTITY='Developer ID Application: Your Name (TEAMID)'
export CODEX_METER_NOTARY_PROFILE='codex-meter-notary'
CODEX_METER_TAG=v0.1.0 ./scripts/package-release.sh
```

脚本按顺序完成 hardened runtime 签名、时间戳、提交公证并等待、staple、票据验证、Gatekeeper 评估，最后生成 `notarized.zip` 与校验值。失败会停止，不会把失败产物标成已公证。

只设置 `CODEX_METER_SIGN_IDENTITY` 时输出 `signed.zip`；两者都不设置时输出 `adhoc.zip`。公证 profile 存在但没有签名 identity 时，脚本会在构建前报错。

在 Release 草稿中上传已公证 ZIP 和对应校验值，并移除不打算公开的旧附件，随后修正说明。首次签名分发需要在另一台 Mac 上下载验证；本机 ad-hoc 校验无法替代该检查。

## 发布材料

- 根目录：README、中英文说明、MIT LICENSE、CHANGELOG、贡献指南。
- `docs/images/`：原创图标和使用合成数据的界面预览。
- `docs/releases/`：每个版本的发布说明。
- `.github/`：CI、Release 草稿工作流、Issue 与 PR 模板。

源码仓库不提交 `.build/`、`dist/`、签名证书或公证凭据。预编译 ZIP 应作为 Release 附件发布。
