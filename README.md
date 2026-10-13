<p align="center">
  <img src="assets/brand-app-icon.png" alt="Warp SSH Manager" width="104" />
</p>

<h1 align="center">Warp SSH Manager</h1>

<p align="center">
  面向 macOS 的 SSH 主机管理器 · 原生毛玻璃界面 · 一键在 Warp 中连接
</p>

<p align="center">
  <strong>macOS 12+（构建目标）</strong> · <strong>Apple Silicon / Intel</strong> · <strong>SwiftUI + AppKit + Rust</strong>
</p>

> **当前版本：v0.4.25。** 应用负责管理 SSH 主机和生成 Warp Tab Configs；实际 SSH 会话、身份验证和终端窗口由 [Warp](https://www.warp.dev/) 与 OpenSSH 处理。项目并非 Warp 官方产品。

## 功能

- **原生 macOS 界面**：SwiftUI / AppKit 三栏管理器、系统毛玻璃、自动／深色／浅色外观。
- **主机管理**：搜索、分组、收藏、最近连接、端口／用户名／密钥路径／跳板配置，以及标签与备注。
- **快速连接**：菜单栏「快速连接…」提供独立搜索浮层；按 **Esc** 关闭，选择主机后交给 Warp 打开。
- **桌面入口**：Dock 图标及菜单栏「打开主机管理器」用于唤起主窗口。
- **OpenSSH 兼容**：导入已有的 <code>~/.ssh/config</code> 主机；导入主机的连接参数由原配置管理。
- **安全地管理 SSH 配置**：用户明确初始化后，才在 SSH 配置中添加 <code>Include</code>，自建主机写入单独的托管文件。
- **Warp Tab Configs**：为连接生成配置并调用 Warp URI Scheme；不内置 SSH 终端。

## 下载安装

1. 打开 [GitHub Actions · macOS 原生安装包](https://github.com/javafancn/warp-ssh-manager/actions/workflows/build-macos-app.yml)，选择最近一次**成功**的构建（也可以从 **Run workflow** 手动触发）。
2. 在该次运行页面的 **Artifacts** 中，根据 Mac 芯片选择对应的包：

   | Mac 类型 | 构建产物 |
   | --- | --- |
   | Apple Silicon（M 系列） | `WarpSSHManager-Native-0.4.25-apple-silicon-macOS12` |
   | Intel | `WarpSSHManager-Native-0.4.25-intel-macOS12` |

3. 解压下载的 Artifact，打开其中的 `.dmg`，将 **Warp SSH Manager.app** 拖入 **Applications（应用程序）**。
4. 确保已安装 [Warp Terminal](https://www.warp.dev/)，并且本机 OpenSSH 可用。

**关于安装包：** GitHub Actions 当前分别构建 Apple Silicon 与 Intel 的 **独立 DMG**，不是 Universal 2。构建使用 macOS 15 runner，二进制目标最低版本设为 macOS 12；这**不等于**已经在所有 macOS 12 真机上完成兼容性测试。安装包采用 **Ad-hoc 签名，未经 Apple Developer ID 签名或公证**，从网络下载后可能受到 Gatekeeper 限制；请自行确认构建来源及安全性。

## 快速上手

### 1. 导入已有 SSH 主机

启动应用后，从主界面的更多操作或高级设置中选择 **导入 SSH 配置**。管理器读取本机的 SSH 别名、地址、用户、端口等信息，并保留你原有的 OpenSSH 配置文件。

> 导入的主机连接字段在应用内为只读；需要修改时请编辑原始 SSH 配置，然后重新导入。导入会调用 `ssh -G` 解析配置，如果你的配置含有 `Match exec`，OpenSSH 可能执行其中的本地命令，请只导入可信配置。

### 2. 添加自管主机

首次创建自管 SSH 主机前，点击 **初始化 SSH 集成**（或在 CLI 运行 `wsm init`）。此操作会：

- 为已有的 `~/.ssh/config` 创建备份；
- 在主配置中添加指向托管配置文件的一条 `Include`（重复初始化不会重复添加）；
- 将自管主机保存到 `~/.ssh/config.d/warp-ssh-manager.conf`。

之后在右上角点击 **新建主机**，填写 SSH 别名、IP／域名、用户名和端口；需要时指定已有的密钥文件路径。应用不会复制或存储私钥内容。

### 3. 在 Warp 中连接

从列表中选中主机，点击 **在 Warp 中打开**；也可以通过菜单栏的 **快速连接…** 搜索并打开。

管理器会创建／更新对应的 Warp Tab Config，再向 macOS 发送 Warp URI 打开请求。**成功唤起 Warp 不代表 SSH 已登录成功**；连通性、密钥、授权等错误请以 Warp 和 OpenSSH 的反馈为准。

## 命令行（可选）

安装包内附带 Rust CLI `wsm`，也可以从源码运行。以下示例在仓库根目录执行：

```bash
# 检查本机环境和配置路径
cargo run -p wsm-cli -- doctor

# 导入现有 SSH 配置（不修改已有 Host 定义）
cargo run -p wsm-cli -- import
cargo run -p wsm-cli -- list

# 创建自管主机前，明确授权安装 Include
cargo run -p wsm-cli -- init
cargo run -p wsm-cli -- add \
  --name "Dev API" \
  --alias dev-api \
  --hostname example.com \
  --user deploy \
  --port 22

# 列出与搜索主机
cargo run -p wsm-cli -- list --search dev

# 测试 Warp 配置与 URI，不实际发起打开请求
cargo run -p wsm-cli -- connect <HOST_UUID> --dry-run

# 收藏主机以及已有的 Warp Tab Configs 同步
cargo run -p wsm-cli -- favorite <HOST_UUID>
cargo run -p wsm-cli -- sync
```

还支持 `edit`、`delete`、`group add/list/delete`、`connect --new-window`、`connect --preview` 和 `sync --all` 等命令。查看完整用法：

```bash
cargo run -p wsm-cli -- --help
cargo run -p wsm-cli -- connect --help
```

安装后的应用也可以直接使用内置 CLI：

```bash
"/Applications/Warp SSH Manager.app/Contents/MacOS/wsm" doctor
```

> DMG 中应用包的文件名为 `Warp SSH Manager.app`，Finder 可能按本地化的应用显示名呈现；若自行重命名过应用，请以实际 `.app/Contents/MacOS/wsm` 路径为准。

## 本地构建原生 macOS 应用

需要 **macOS、Xcode Command Line Tools、Rust/Cargo**，首次安装依赖需要联网。以下命令根据当前机器架构生成**对应架构**的安装包：

```bash
xcode-select --install  # 若已安装，可跳过

case "$(uname -m)" in
  arm64)
    rust_target="aarch64-apple-darwin"
    swift_target="arm64-apple-macos12.0"
    arch="apple-silicon"
    ;;
  x86_64)
    rust_target="x86_64-apple-darwin"
    swift_target="x86_64-apple-macos12.0"
    arch="intel"
    ;;
  *)
    echo "Unsupported macOS architecture" >&2
    exit 1
    ;;
esac

rustup target add "$rust_target"
cargo test -p wsm-core -p wsm-cli
cargo build -p wsm-cli --release --target "$rust_target"

mkdir -p dist
xcrun swiftc -O -target "$swift_target" \
  -framework SwiftUI -framework AppKit \
  apps/wsm-native/Sources/*.swift \
  -o dist/warp-ssh-manager

bash scripts/package-macos-app.sh \
  --single dist/warp-ssh-manager "$arch"
```

输出在 `dist/` 下，包含相应架构的 `.dmg` 和 `.app.zip`。本仓库只维护 SwiftUI / AppKit 原生界面，CLI 与 SSH 数据逻辑仍由 Rust 提供。

### 项目结构

```text
apps/wsm-native/Sources/  SwiftUI + AppKit 原生主窗口、详情和快速连接
crates/wsm-core/         主机数据、SQLite、OpenSSH、Warp 配置逻辑
crates/wsm-cli/          wsm 命令行及原生应用使用的 JSON 桥接
examples/               SSH 配置与 Warp Tab Config 示例
scripts/                macOS 打包、功能测试和截图验收脚本
.github/workflows/      Rust 检查与双架构原生打包 CI
assets/                 应用图标和品牌资源
```

原生应用通过内置 `wsm ui ...` JSON 接口调用 Rust 核心，避免在 SwiftUI 和 CLI 中分别实现 SSH 配置写入逻辑。

## 配置与数据

| 位置 | 内容 |
| --- | --- |
| `~/Library/Application Support/WarpSSHManager/hosts.sqlite3` | 主机、分组、收藏及标签、备注等本地数据 |
| `~/.ssh/config` | 原有 OpenSSH 主配置；显式初始化时添加 Include |
| `~/.ssh/config.wsm-backup-<UUID>` | 初始化时对已有 SSH 主配置创建的备份 |
| `~/.ssh/config.d/warp-ssh-manager.conf` | 管理器维护的自管 SSH Host 定义 |
| `~/.warp/tab_configs/wsm_<UUID>.toml` | 管理器生成的 Warp Tab Config；文件名中的 UUID 不含连字符 |

可用环境变量 **`WSM_HOME`、`WSM_SSH_CONFIG`、`WSM_WARP_CONFIG_DIR`** 覆盖数据目录、SSH 主配置与 Warp Tab Config 目录。运行测试时建议使用独立临时目录，避免碰到个人的真实 SSH 配置。

## 测试与 CI

- [Rust checks](https://github.com/javafancn/warp-ssh-manager/actions/workflows/ci.yml)：Rust 格式检查、核心和 CLI 测试、静态检查，以及 macOS 相关检查。
- [macOS 原生安装包](https://github.com/javafancn/warp-ssh-manager/actions/workflows/build-macos-app.yml)：Apple Silicon / Intel 分别编译 SwiftUI 和 Rust 核心、打包独立 DMG。
- Apple Silicon 的视觉 smoke test 使用**实际 SwiftUI 窗口截图**，检查三栏毛玻璃随桌面背景响应、透明缝隙，以及菜单栏与 Dock 主窗口的路由和重复窗口数量。
- 本机可运行 `bash scripts/macos-smoke.sh`（隔离临时配置）及 `bash scripts/native-ui-bridge-smoke.sh <PATH_TO_WSM>`。

CI 通过证明指定 runner、构建和模拟场景下的结果；**不等于**已完成全部 macOS 版本、物理 Dock 点击、真实 SSH 服务器认证或 Apple 公证验收。

## 注意事项

- 项目不保存账号密码或私钥文件本身；只记录 SSH 连接信息和身份文件**路径**。妥善保管你的本地 SQLite 数据库及 SSH 配置。
- 删除从 SSH 配置导入的主机，不会删除原始 OpenSSH Host 定义。
- `wsm sync --all` 会为所有主机生成 Warp Tab Configs，可能增加 Warp 菜单中的条目。
- 不要将个人 `~/.ssh/config`、私钥、令牌或真实服务器清单提交到公共仓库。
- 若应用能打开但 Warp 无法连接，请先检查 Warp 是否已安装、`ssh <ALIAS>` 能否连接，以及高级设置中的 SSH 集成状态。

## 许可证

[MIT License](LICENSE)。与 Warp 官方无隶属关系。
