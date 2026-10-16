<p align="center">
  <img src="assets/brand-app-icon.png" alt="Warp SSH Manager" width="104">
</p>

<h1 align="center">Warp SSH Manager</h1>

<p align="center">
  <a href="README.md">English</a> ·
  <a href="README.zh-CN.md"><strong>简体中文</strong></a>
</p>

<p align="center">
  为 Warp 打造的 macOS 原生 SSH 主机管理器
</p>

<p align="center">
  <strong>v1.0.2</strong> · macOS 12+（构建目标） · Apple Silicon / Intel · SwiftUI + AppKit + Rust
</p>

<p align="center">
  <a href="https://github.com/javafancn/warp-ssh-manager/actions/workflows/build-macos-app.yml">下载 macOS 安装包</a>
  ·
  <a href="https://github.com/javafancn/warp-ssh-manager/actions/workflows/ci.yml">持续集成</a>
  ·
  <a href="LICENSE">MIT License</a>
</p>

> **v1.0.2 更新：** 快速打开升级为 Spotlight 风格，新增全局快捷键 **⌃⌥⌘K**、最近连接优先及上方居中窗口定位。保留 v1.0.1 的多级嵌套分组、界面优化及双语文档。

> **关于项目**：Warp SSH Manager 是社区项目，并非 Warp 官方应用。它管理本地 SSH 主机和 Warp 的启动配置；SSH 传输与交互式终端仍由 **OpenSSH + Warp** 提供，而不是在应用内重新实现 SSH 客户端。

## 为什么使用它

不必反复打开文本编辑器管理大量 SSH Host。使用原生三栏界面组织服务器、切换连接认证方式，并在 Warp 中快速打开目标主机。

| 主机管理 | 登录认证 | Warp 集成 |
| --- | --- | --- |
| 搜索、收藏、最近连接、分组 | 自动选择、SSH 密钥、用户名密码 | **Spotlight 快速打开（⌃⌥⌘K）** |
| **标签复用：** 添加标签时可直接点选其他主机已经使用的标签，也可输入新标签 | 保存、复制、删除密码后的成功提示约 3 秒自动消失 | Warp / OpenSSH 连接行为不变 |
| 标签配色、备注、SSH 参数 | Keychain 保存 SSH / sudo 密码 | 保留原生 `ssh <别名>` 命令 |
| 导入已有 `~/.ssh/config` | 按需复制密码、尝试自动登录 | 独立生成 Warp Tab Config |

界面提供自动、浅色、深色外观，支持 Apple Silicon 和 Intel 独立构建。

### Spotlight 风格快速打开

只要 Warp SSH Manager 正在运行，随时按下 **⌃⌥⌘K（Control + Option + Command + K）** 即可从其他应用唤出快速打开面板，再按一次可关闭。该组合键特意避开系统 Spotlight（⌘Space）和应用中常见的 ⌘K。项目使用 macOS 原生全局热键接口注册，不要求辅助功能或键盘监听权限；如果快捷键已被其他软件占用，也可从菜单栏图标中选择「快速打开」。面板出现在鼠标所在屏幕的上部居中位置。

无需输入关键词时，最近连接的主机排在最前面；输入后可搜索主机名称、SSH 别名、IP、标签和分组路径。使用 **↑ / ↓** 切换选择，按 **Enter** 在 Warp 打开，按 **Esc** 关闭，也可直接点击结果。连接实现保持原生 Warp/OpenSSH 方式不变。

### 关闭窗口后继续在菜单栏运行

点击主窗口左上角的**红色关闭按钮**（或按 **⌘W**）只会隐藏主窗口，**不会退出 Warp SSH Manager**。菜单栏图标会保留，全局快捷键 **⌃⌥⌘K** 仍可随时唤出快速打开。需要重新打开管理界面时，选择菜单栏里的「**打开主机管理器**」或者点击 Dock 图标，恢复原来的窗口而不会重复创建。只有通过菜单栏的「**退出 Warp SSH 管理器**」或应用激活时按 **⌘Q** 才会真正退出并注销快捷键。此功能不会自动设置登录时启动。


## 下载安装

1. 前往 [GitHub Releases](https://github.com/javafancn/warp-ssh-manager/releases/latest)，下载 Apple Silicon 或 Intel 对应的 v1.0.2 DMG。
2. 如果使用 [GitHub Actions](https://github.com/javafancn/warp-ssh-manager/actions/workflows/build-macos-app.yml) 的测试构建，请在 **Artifacts** 下载对应架构的构建产物，并解压：
   - Apple Silicon（M 系列）：`WarpSSHManager-Native-1.0.2-apple-silicon-macOS12`
   - Intel（x86_64）：`WarpSSHManager-Native-1.0.2-intel-macOS12`
3. 打开 DMG，将 **Warp SSH Manager.app** 拖入 `/Applications`。
4. 安装 [Warp Terminal](https://www.warp.dev/)。macOS 自带 OpenSSH；确保终端能使用 `ssh`。

**发布与系统要求**：项目目前分别构建两个架构的 DMG，并非 Universal Binary。CI 的编译目标为 **macOS 12+**，实际操作系统兼容性仍需实机验证。安装包采用 **Ad-hoc 签名，尚未使用 Apple Developer ID 签名或 Apple 公证**；如果 Gatekeeper 阻止打开，应先确认下载来源并遵循 macOS 的安全提示，不要盲目关闭系统安全功能。Actions 的 Artifacts 可能过期。

## 快速开始

### 1. 导入 SSH 主机或初始化新主机

**已有 SSH 配置**：从应用中选择「导入 SSH 配置」，导入 `~/.ssh/config` 里的主机别名。导入主机的主机名、用户、端口等信息仍由原始 SSH 配置管理；要修改连接参数，请编辑原文件再重新导入。

**自建主机**：首次使用前通过应用的「初始化 SSH 集成」或执行 `wsm init`。它会先备份主 SSH 配置，再加入一个指向专用托管配置的 `Include`；后续由 WSM 维护自己的 SSH Host。接着新建主机，填写：

- 显示名称及 SSH 别名
- 主机 IP / 域名、用户名、端口
- 可选的身份文件路径、代理跳板、分组、标签和备注

应用仅保存私钥**路径**，不会复制 SSH 私钥内容。

> 导入过程使用 `ssh -G` 解析有效配置；请只导入可信任的 SSH 配置，尤其应注意可能包含的 `Match exec` 指令。

### 2. 选择认证方式

在主机详情的「连接配置 → SSH 认证方式」中选择：

| 模式 | 实际效果 | 建议场景 |
| --- | --- | --- |
| **自动选择** | 保留 OpenSSH 原有的认证协商与配置，旧主机默认使用 | 已有配置、ssh-agent、组合认证 |
| **SSH 密钥** | 自管主机明确使用公钥认证、关闭密码认证 | 使用密钥的服务器 |
| **用户名 + 密码** | 自管主机启用密码 / keyboard-interactive、关闭公钥；可配合 Keychain 尝试自动输入密码 | 使用账号密码的服务器 |

**导入主机**：不改写其原始 `~/.ssh/config`。即使在 WSM 选择「用户名 + 密码」，外部 SSH Config 的认证规则仍可能决定最终行为。

**注意**：自动选择不等于自动从 Keychain 注入密码；只有明确选择「用户名 + 密码」且保存 SSH 密码的主机，WSM 才会尝试辅助登录。

### 3. 保存密码并连接

1. 先保存主机。
2. 进入「连接配置 → 凭据管理」，点击「SSH 登录密码」，填写并保存密码。
3. 点击「在 Warp 中打开」或使用菜单栏快速连接。
4. 选择密码模式且已保存凭据时，WSM 会创建短期、一次性 Askpass 授权；OpenSSH 请求密码时，辅助程序尝试从 macOS Keychain 取出密码并提交**一次**。
5. 若遇到密码错误、指纹确认、MFA 或其他交互式认证问题，需要用户手动完成认证。主机操作菜单提供「手动连接」以绕开辅助登录。

连接入口仍是 Warp 执行的原生 `ssh <别名>`，而不是自建终端或 SSH 代理。**Warp 成功打开不代表服务器登录成功。自动密码登录及 Warp SSH Extension 的完整兼容性仍需要在真实 Warp + SSH 服务器环境下验证。**

### 4. 多级分组、标签与 sudo 密码

使用分组、收藏、搜索和标签组织主机。常见环境标签（如 `production`、`test`、`dev`）具有语义配色；其他标签按名称生成稳定颜色。新增标签支持连续输入和重复校验。

**多级嵌套分组（当前 main 源码）**：

1. 点击侧栏「＋ 新建分组」，在表单中输入名称并选择上级分组；选择「顶级分组」则创建根分组。
2. 也可右键已有分组 → **新建子分组**。点击分组前的箭头展开/折叠任意层级。
3. 右键分组 → **重命名或移动**，可以调整名称或上级分组；不允许移动到自身或自己的子分组中。
4. 点击父分组时，会显示该分组及所有后代分组的主机；侧栏计数也包含后代主机。主机详情中的分组选择显示完整路径，便于区分同名子分组。
5. 删除非叶子分组前须先移走/删除其子分组；删除一个没有子分组的分组不会删除其中的主机，而是把主机设为「未分组」。

分组与层级只存储在本地数据库，不会更改 SSH Host 或私钥。旧版平铺分组无需数据迁移，原分组会作为顶级分组显示。

可为每台主机另存 **sudo 密码**，也可以默认复用已保存的 SSH 密码。sudo 只提供**一键复制**，不做自动检测或自动填写，以避免改变远端终端的交互行为。主机菜单还支持复制 SSH 登录密码。

## 安全与隐私

- **钥匙串存储**：SSH 和 sudo 密码直接保存在当前 Mac 的 **macOS Keychain**（通用密码条目），使用 `WhenUnlockedThisDeviceOnly` 访问属性；不作为明文写入 SQLite、SSH Config、Warp Tab Config 或 Rust JSON 快照。
- **自动登录辅助**：Askpass 会话授权文件使用受限权限、120 秒有效期，并在读取前尝试一次性消费。它不是强沙箱：同一个 macOS 用户下的恶意进程可能利用短期令牌竞争；不要把这视为对本机已入侵进程的完整防护。
- **提示验证**：自动回答仅面向识别到的密码提示；MFA、指纹或其他询问不会无条件返回保存的密码。
- **剪贴板**：复制密码后，应用会在约 30 秒时尝试清空**没有被更改**的系统剪贴板。剪贴板历史、同步软件或恶意进程可能已经读取内容。
- **sudo**：只复制，不自动填写。若管理员禁止密码登录、使用 MFA 或限制 sudo，WSM 不会绕过这些限制。
- **真实环境验收**：CI 能覆盖 Rust 单元测试、SwiftUI 编译、Askpass 提示识别、隔离的 SSH 配置及窗口冒烟检查；**不等于**真实 Keychain 授权、密码服务器端到端登录和 Warp SSH 增强功能都已验证。

## 命令行

应用包包含 Rust CLI `wsm`。在源码仓库根目录可以这样使用：

```bash
# 环境检查
cargo run -p wsm-cli -- doctor

# 导入和列出已有 SSH 主机
cargo run -p wsm-cli -- import
cargo run -p wsm-cli -- list

# 初始化托管 SSH Config，再添加服务器
cargo run -p wsm-cli -- init
cargo run -p wsm-cli -- add \
  --name "Dev API" \
  --alias dev-api \
  --hostname example.com \
  --user deploy \
  --port 22

# 查询、预览 Warp 连接和同步 Tab Config
cargo run -p wsm-cli -- list --search dev
cargo run -p wsm-cli -- connect <HOST_UUID> --dry-run
cargo run -p wsm-cli -- sync
```

分组命令示例（`<父分组UUID>`、`<分组UUID>` 应替换为真实 UUID）：

```bash
cargo run -p wsm-cli -- group add "生产环境"
cargo run -p wsm-cli -- group add "数据库" --parent <父分组UUID>
cargo run -p wsm-cli -- group edit <分组UUID> --name "DB" --root
cargo run -p wsm-cli -- group list
```

更多命令包括 `edit`、`delete`、`favorite`、`group`、`connect` 和 `sync --all`。查看：

```bash
cargo run -p wsm-cli -- --help
"/Applications/Warp SSH Manager.app/Contents/MacOS/wsm" --version
```

## 本地编译

需要 **macOS、Xcode Command Line Tools、Rust / Cargo**。本项目的构建工具链使用 SwiftUI / AppKit 和 Rust；在仓库根目录执行：

```bash
xcode-select --install  # 已安装时可跳过
cargo test -p wsm-core -p wsm-cli

if [ "$(uname -m)" = "arm64" ]; then
  rust_target=aarch64-apple-darwin
  swift_target=arm64-apple-macos12.0
  arch=apple-silicon
else
  rust_target=x86_64-apple-darwin
  swift_target=x86_64-apple-macos12.0
  arch=intel
fi

rustup target add "$rust_target"
cargo build -p wsm-cli --release --target "$rust_target"
mkdir -p dist
xcrun swiftc -O -target "$swift_target" \
  -framework SwiftUI -framework AppKit \
  apps/wsm-native/Sources/*.swift -o dist/warp-ssh-manager

bash scripts/package-macos-app.sh --single dist/warp-ssh-manager "$arch"
```

安装包写入 `dist/`，包含对应架构的 DMG 和 `.app.zip`。打包过程也会编译专用 Askpass 辅助程序、验证捆绑架构及 macOS 版本元数据。

## 项目结构

```text
apps/
  wsm-native/Sources/      SwiftUI / AppKit 主机管理界面
  wsm-askpass/             macOS Keychain / SSH_ASKPASS 辅助程序
crates/
  wsm-core/                SQLite、SSH Host、Warp Tab Config 核心
  wsm-cli/                 wsm CLI 以及原生应用的 JSON 桥接
scripts/                   本地构建、检查与 macOS GUI 冒烟测试
.github/workflows/         Rust CI、Intel / Apple Silicon 安装包
assets/                    品牌图标
examples/                  SSH 与 Warp 配置示例
```

## 配置文件与升级

| 路径 | 用途 |
| --- | --- |
| `~/Library/Application Support/WarpSSHManager/hosts.sqlite3` | 主机、分组、收藏、标签和认证方式等数据（**不包含密码**） |
| `~/.ssh/config` | 用户原有 SSH 配置，仅在明确初始化后写入 `Include` |
| `~/.ssh/config.d/warp-ssh-manager.conf` | WSM 自管 SSH Host |
| `~/.warp/tab_configs/wsm_<UUID>.toml` | WSM 生成的 Warp Tab Config |
| macOS Keychain | 按主机 UUID 存储 SSH 和 sudo 凭据 |
| `~/Library/Application Support/WarpSSHManager/askpass_sessions/` | 短期、一次性自动认证会话文件 |

支持环境变量 `WSM_HOME`、`WSM_SSH_CONFIG` 和 `WSM_WARP_CONFIG_DIR` 重定向路径。升级时请**先备份** SSH 配置及 `hosts.sqlite3`；应用的数据库迁移会给旧主机添加默认的 `auto` 认证方式，但不可把数据库备份当作 Keychain 密码备份。应用本身不支持跨设备迁移 Keychain 凭据。

## 测试与贡献

- [Rust / SwiftUI CI](https://github.com/javafancn/warp-ssh-manager/actions/workflows/ci.yml) — 格式、测试、静态检查、类型检查及受控的 SSH 集成检查。
- [macOS 构建](https://github.com/javafancn/warp-ssh-manager/actions/workflows/build-macos-app.yml) — 两种架构单独打包，并在 Apple Silicon Runner 上执行实际窗口截图冒烟检查。
- 本地功能检查：`bash scripts/macos-smoke.sh`；原生 JSON 桥接：`bash scripts/native-ui-bridge-smoke.sh <PATH_TO_WSM>`。

如需提交问题或改进，请附上 macOS / Warp 版本、主机的**脱敏配置**、认证模式及复现步骤。**请勿上传密码、私钥、访问令牌或生产服务器清单。**

## 许可证

本项目采用 [MIT License](LICENSE)，与 Warp 官方无隶属关系。
