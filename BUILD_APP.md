# Warp SSH Manager — 可安装应用构建版

> **状态：本包提供自动生成 macOS `.app`、`.dmg` 和 `.app.zip` 的构建流程，但当前并不包含已编译的可执行应用。** 源码尚未通过真实 macOS GPUI 编译、运行及 Monterey 验收；若构建报错，应根据 Actions 的真实编译日志修复代码，不能把工作流文件当作已成功发布的应用。

## 不想安装 Cargo？使用 GitHub Actions 构建

1. 将本文件夹作为 Git 仓库上传到自己的 GitHub 仓库（例如用 GitHub Desktop 创建、提交并 Publish）。请先清理个人 SSH 配置、令牌等敏感信息，本项目示例不含你的 SSH 密钥。
2. 打开仓库的 **Actions → Build macOS App (Universal 2) → Run workflow**。
3. **仅在工作流全部变绿且构建成功后**，打开这次运行页面底部的 **Artifacts**，下载 `WarpSSHManager-Universal2-macOS12-plus`。
4. 解压后可以找到 `WarpSSHManager-0.3.1-macOS.dmg` 和 `.app.zip`。这是本地测试候选版，尚未经过 Apple Developer ID 公证。

工作流分别在 `macos-15`（ARM64）和 `macos-15-intel`（x86_64）编译，用 `lipo` 合并为 Universal 2，检查二进制的系统最低部署版本，并创建独立的 `.app`、`.dmg`、`.app.zip`。

**使用 macOS 15 构建机不表示最低运行版本变为 macOS 15**。打包声明和二进制目标都是 macOS 12，仍需在 Monterey 真机上进行运行与 SSH 集成测试。

## 想自己 Mac 双击构建

在 macOS Finder 中双击项目根目录的 `Build Warp SSH Manager.command`，此操作**需要事先安装** Xcode Command Line Tools 和 Rust/Cargo，且第一次构建需要联网下载依赖。若成功，`dist/` 下会生成 `.app`、`.app.zip`、`.dmg`。不满足先决条件时脚本会明确报错，不会擅自安装系统开发工具。

## 必须区分的限制

- GPUI GUI 代码**此前只经过静态检查**，没有 Mac 真正编译通过的证据。Actions 构建可能失败，此时产物不会上传。
- `.app` 为临时 Ad-Hoc 签名，不等于 Apple Developer ID 签名/公证。macOS Gatekeeper 可能对来自互联网的应用显示安全提示；不建议向其他用户分发未经公证的构建。
- 仅打包不会改变项目的现有功能范围：三栏 SSH 管理界面、三种主题、Quick Connect、Warp Tab Configs 集成，仍以真实环境验证为准。
- 不要将真实 SSH 私钥、用户配置和登录信息提交到 GitHub。

项目原有的设计说明与开发文档仍在 `docs/` 中。
