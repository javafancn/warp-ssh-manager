# 构建可运行的 macOS 应用

**GitHub Actions 云端构建、Universal 2 `.app`/`.dmg`：请先阅读 [BUILD_APP.md](BUILD_APP.md)。** 此包依然是源码，尚未在 macOS 上编译验证；只有工作流真正成功后才有可用程序。

---

# Warp SSH Manager — v0.3 设计图还原版

> **目标平台：macOS 12+ / Intel x86_64 & Apple Silicon ARM64。** 目标系统版本与 Universal 2 并不等于已经完成兼容性验证。当前环境没有 macOS、Xcode 或 Rust/Cargo，因此本包为**待 Mac 编译验证的源码**，不包含经过签名/公证的可安装应用。

本版以 `docs/reference/approved-themes.png` 为唯一视觉标准，直接修改了 `apps/wsm-desktop` 的 **GPUI 界面实现**：更紧凑的三栏布局、现代化列表和表单、右侧标签 chips、简洁顶部栏与配置管理展开、三态主题切换和收藏/分组清晰呈现；Quick Connect 增加环境标签及收藏星标。原有 SSH Core / OpenSSH / Warp Tab Configs 的职责保持不变。

- **设计对照及验收清单**：[`docs/DESIGN_FIDELITY.md`](docs/DESIGN_FIDELITY.md)
- **深浅/系统主题互动预览**：[`docs/theme-preview.html`](docs/theme-preview.html)，为静态视觉演示，不会访问真实 SSH 主机
- **Monterey 兼容路线**：[`docs/MACOS12_COMPATIBILITY_ROADMAP.md`](docs/MACOS12_COMPATIBILITY_ROADMAP.md)

### Mac 本机编译验证

```bash
rustup target add aarch64-apple-darwin x86_64-apple-darwin
export MACOSX_DEPLOYMENT_TARGET=12.0
cargo test -p wsm-core
cargo check -p wsm-desktop --features tray
cargo run -p wsm-desktop --features tray
```

如需制作本地 Universal 2 测试用 `.app`：

```bash
bash scripts/build-universal-macos.sh
```

**仍需要在真实 macOS 12 的两种处理器上验证 GUI、主题、菜单栏、OpenSSH/Warp 连接与文件权限。**

---

# Warp SSH Manager

> macOS-first, pure-Rust SSH host manager that uses **Warp Tab Configs** for terminal sessions. No embedded terminal or custom SSH protocol implementation.

**Status: v0.2 UI redesign source / macOS build verification required.** The core, CLI, GPUI window and optional menu-bar feature are included, but this repository was generated in a Linux environment without `rustc`, `cargo`, Xcode or access to crates.io. It has **not been compiled or tested on macOS**. See [Verification](#verification) before daily use. Do not treat it as a signed production release.

## UI redesign (v0.2)

The GPUI desktop app now follows the approved **dark/light design reference** in `docs/reference/` and includes a native-status-menu-launched searchable Quick Connect floating window. Theme preferences are **Auto / Dark / Light** and persist across launches. The UI layout and interactions are also available as a **standalone browser-only design preview** in [`docs/theme-preview.html`](docs/theme-preview.html) (demo data; it does not access your SSH configuration). See [`docs/UI_DESIGN.md`](docs/UI_DESIGN.md) for behavior and macOS visual acceptance criteria.

## Implemented scope

| Feature | Where | Notes |
| --- | --- | --- |
| Persist hosts, groups, favorites, last launch | `wsm-core` SQLite | Groups can have parent groups |
| Import existing SSH configuration | `wsm import` / Desktop Import | Reads `Host` / `Include`; `ssh -G` resolves settings |
| Manage SSH configuration | `wsm init`, managed hosts | One explicit Include, original file backed up |
| Generate Warp Tab Configs | `wsm-core::warp` | TOML file keyed by host UUID, correct schema |
| One-click Warp opening | `wsm connect` / GUI | `warp://tab_config/<stem>` on macOS |
| Manage hosts in GPUI window | `wsm-desktop` | Three-column dark/light UI, nested group navigation, search, metadata edit, favorites |
| macOS menu-bar icon | `wsm-desktop --features tray` | Native tray menu, Quick Connect floating search window, favorites snapshot |
| Appearance selection | `wsm-desktop` | Dark / Light / Follow System, preference saved in application data |
| Host annotations | `wsm-core` SQLite | Tags and notes in separate metadata table, never written to SSH config |
| Core unit tests | `wsm-core` | Validation, import parsing, file safety, DB life cycle |
| CLI smoke test | `scripts/macos-smoke.sh` | Uses temporary config paths only |

### Deliberate boundaries

- **Warp**, not this app, executes `ssh` and handles terminal sessions. A dispatched Warp URL does not imply a successful SSH login.
- Imported hosts are **read-only for connection fields**. Edits belong in the user's SSH config; display name, group and favorite may be changed here.
- First use of `wsm init` explicitly adds an `Include` directive in the user's `~/.ssh/config`; a backup is created. The app subsequently manages **only** `~/.ssh/config.d/warp-ssh-manager.conf`.
- Tab Configs for favorites and previously opened hosts are regenerated on Sync. `wsm sync --all` creates persistent entries for every host (can crowd Warp's `+` menu).
- The native menu favorites list is populated at startup. To reflect new favorites there, restart the app. The separate Quick Connect window queries the current database on every open.
- Desktop v0.2 follows the design reference, with dark/light/system appearance and editable notes/tags. The status-bar indicators represent local configuration state, **not successful SSH login**.
- Quick Connect is currently a **floating GPUI search window** launched from a native status menu, not yet an NSStatusItem-anchored auto-dismiss popover. Native window chrome may continue to follow the system theme when the content has a manual override.

## macOS 12+ compatibility decision

The product now **targets macOS 12 Monterey and later** on both Intel and Apple Silicon, without changing the pinned GPUI/UI-component versions. This is an **unverified target**, not a claim of operating-system support. The bundle metadata and candidate build scripts set a 12.0 deployment target. The two-architecture build, runtime compatibility and notarization must be validated on Macs. See [Compatibility roadmap](docs/MACOS12_COMPATIBILITY_ROADMAP.md).

## Requirements

- **Target:** macOS 12 or newer, Warp Terminal installed. **Unverified:** actual Monterey/Intel/ARM64 desktop compatibility; compile and runtime tests still required.
- Rust stable (`rustup`), Xcode command-line tools, and initial internet access to download Rust crates.
- The GUI uses the matched published dependencies **gpui 0.2.2** / **gpui-component 0.5.1**. Do **not** mix with a newer Zed GPUI git version without migrating both dependencies together.
- Existing OpenSSH (`/usr/bin/ssh`).

## Quick start

```bash
# From the repository root:
cargo test -p wsm-core
cargo run -p wsm-cli -- doctor

# Explicit opt-in: backs up ~/.ssh/config, then adds a managed Include.
cargo run -p wsm-cli -- init

# Import configured aliases without changing existing connection definitions.
cargo run -p wsm-cli -- import
cargo run -p wsm-cli -- list

# Create a managed SSH host.
cargo run -p wsm-cli -- add \
  --name "Development API" --alias dev-api \
  --hostname 192.168.1.100 --user deploy \
  --port 22 --identity ~/.ssh/id_ed25519 --favorite

# Launch GUI; only performs local config and macOS open actions.
cargo run -p wsm-desktop

# With a native macOS menu-bar item + favorites (optional).
cargo run -p wsm-desktop --features tray
```

The identity path example uses a typical key location: **do not copy it unless the file is already yours**. Prefer ssh-agent and existing keys; no passwords are stored.

### CLI commands

```bash
wsm init
wsm doctor
wsm import
wsm list --search prod
wsm group add Production
wsm group add Backend --parent <UUID>
wsm group list
wsm add --name "Prod API" --alias prod-api --hostname prod.example.com --user deploy --group <UUID>
wsm edit <UUID> --name "Prod API New"
wsm favorite <UUID>
wsm connect <UUID> --dry-run       # print TOML + URI, no effects
wsm connect <UUID>                 # writes TOML and asks macOS to open Warp
wsm connect <UUID> --new-window
wsm connect <UUID> --preview
wsm sync                           # favorites + previously generated
wsm sync --all                     # generate entries for all hosts
wsm delete <UUID>
```

### Where files live

```text
~/Library/Application Support/WarpSSHManager/hosts.sqlite3
~/.ssh/config                                      (one-time Include, after consent)
~/.ssh/config.wsm-backup-<UUID>                   (backup on init)
~/.ssh/config.d/warp-ssh-manager.conf              (managed connection details)
~/.warp/tab_configs/wsm_<UUID_WITHOUT_DASHES>.toml (generated, no secrets)
```

For test isolation, set `WSM_HOME`, `WSM_SSH_CONFIG`, `WSM_WARP_CONFIG_DIR` to absolute paths. The GUI and CLI honor them.

## Architecture

```text
Desktop UI (GPUI) / Menu bar / CLI
                │
                ▼
       Manager (wsm-core)
        ├── SQLite Repository     groups / host metadata / favorites
        ├── SSH Config Engine     parse / import / write scoped Include
        └── Warp Adapter         tab-config TOML / open URI
                    │
      ┌─────────────┴───────────────┐
      ▼                             ▼
   OpenSSH                    Warp Terminal
   ~/.ssh/config              warp://tab_config/...
```

## Verification

Execute on an actual Mac:

```bash
cargo fmt --all -- --check
cargo test --workspace --exclude wsm-desktop
cargo check -p wsm-desktop
cargo check -p wsm-desktop --features tray
bash scripts/macos-smoke.sh
```

Then launch Warp and verify GUI → click host → **Warp opens the correct Tab Config**; separately verify that SSH authentication succeeds, and verify importing complex `Include`/`Match`/`Host *` rules with your real config. `wsm import` invokes `ssh -G`: user-authored `Match exec` config may execute local commands as part of OpenSSH's normal evaluation. Import only trusted SSH configs.

For packaging: `bash scripts/build-macos.sh` runs core checks and `cargo-bundle`. Developer ID signing, Apple notarization, menu bar focus, VoiceOver and system appearance still require manual verification.

## Security notes

- SSH alias restricted to alphanumerics / dots / underscores / hyphens to avoid shell command injection.
- For managed files, control characters, quotes and whitespace in SSH token fields are rejected; **paths containing spaces currently aren't supported for managed identity files**.
- No SSH keys or passwords are ever copied into the database (key *path* only). OpenSSH/ssh-agent authenticates.
- Managed file writes are atomic and owner-only (`0600`) on Unix; original user file is preserved through backup. Do not configure `WSM_*` paths in world-writable directories.
- Generated Tab Configs are only deleted/overwritten when they bear the manager's ownership marker.
- No remote host authentication checks are performed by the Manager (Warp owns that session).

## Known limitations / planned work

- Native status-item-anchored popover, drag-and-drop group reordering, deleting groups via GUI, dynamically rebuilding native favorites menu, global keyboard launcher, signed updates, and VoiceOver auditing remain future work.
- The GUI now has distinct light and dark design tokens, three-pane layout, group collapse/expand, favorites/recent filters, editable notes/tags, and persistent appearance choice. Pixel-perfect visual parity and macOS accessibility require a real Mac to assess.
- SSH config import only lists literal `Host` aliases, follows Include globs with a depth limit; some quoted Include paths, wildcard `Host` entries, and SSH `Match` behavior are deferred to `ssh -G` resolution, with compatibility limitations.
- GPUI / tray-code source is uncompiled in this delivery environment. Address compiler diagnostics on macOS before deploying; see `docs/UI_DESIGN.md` for visual acceptance tests.

## References

- [Warp Tab Configs](https://docs.warp.dev/terminal/windows/tab-configs)
- [Warp URI Scheme](https://docs.warp.dev/terminal/more-features/uri-scheme)
- [GPUI Component](https://github.com/longbridge/gpui-component)
- [Deck](https://github.com/hellno/deck) (architectural inspiration, no code copied)

MIT licensed. Not affiliated with Warp.


## GitHub 自动构建

上传至独立的 `warp-ssh-manager` 仓库后，每次推送 `main` 分支会自动运行 `.github/workflows/build-macos-app.yml`，在 Intel 与 Apple Silicon macOS runner 上分别构建并尝试合并 Universal 2 `.app` 与 `.dmg`。也可手动运行 workflow。

**重要：** 本项目尚未通过实际的 macOS Rust/GPUI 编译验证。GitHub Actions 可能首先报告源码/依赖编译错误，这时不会生成应用。构建成功也不代表通过 macOS 12 真机验收或 Apple 公证。

首次编译成功后，应提交 `Cargo.lock` 固定依赖。**不要提交任何 SSH 私钥、实际服务器配置或个人认证信息。**
