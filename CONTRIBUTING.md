# 参与开发

欢迎通过 Issue 描述问题或提交 PR。应用目前使用中文界面；文档同时提供中英文入口。

## 本地检查

需要 Swift 6 和 macOS 26+ SDK。从仓库根目录运行：

```bash
./scripts/verify.sh
```

这会检查 Shell 语法、Info.plist、运行离线 `MeterChecks`，然后构建并打包应用。项目没有 XCTest test target，不能用 `swift test` 替代。没有 Codex 账号也可以完成这些检查。

`swift run CodexMeter --check` 会访问本机 Codex，是可选的集成检查，不属于 CI。请勿提交真实账号响应、凭据、个人目录或真实账户截图；新增场景使用合成数据。

## 项目结构

| 目录 | 职责 |
| --- | --- |
| `Sources/MeterCore` | 额度解析、展示规则、stdio RPC 通信 |
| `Sources/CodexMeter` | SwiftUI 视图、AppKit 窗口、设置和刷新模型 |
| `Tests/main.swift` | 无账号依赖的可执行检查，包括模拟 CLI 通信 |
| `Resources` | 应用元数据、原创图标 |
| `scripts` | 构建、打包、验证和图标生成 |
| `docs` | 展示图和维护者发布说明 |

## 变更约定

- 保留未知值和旧数据的区别，不根据本地时间推断额度恢复。
- 窗口名称依据实际时长，不能把 `primary` 固定当成 5 小时。
- 界面变化检查深色 / 浅色、最小 / 最大圆环、多屏、睡眠唤醒及降低透明度设置；说明实际测试范围。
- 网络和数据逻辑变更补充针对行为的离线检查。
- 保持 README、CHANGELOG 和用户可见行为一致。
- 提交信息描述具体功能；一个 PR 尽量解决一个问题。

## 展示图和图标

```bash
swift run CodexMeter --render-previews docs/images
./scripts/generate-icon.swift
```

预览由真实视图和合成额度生成，使用独立临时偏好域，不访问账号。详情离屏渲染使用纯色背景，因为 WindowServer 的玻璃合成无法由普通视图快照完整复现。菜单栏图是字号和格式示意。生成后应目视检查图片。图标源为 Swift 绘图代码，输出 ICNS 和 README PNG。

## 许可证

提交贡献即表示你有权按项目的 [MIT 许可证](LICENSE) 提供这些内容。
