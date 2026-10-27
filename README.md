<p align="center">
  <img src="assets/brand-app-icon.png" alt="Warp SSH Manager logo" width="104">
</p>

<h1 align="center">Warp SSH Manager</h1>

<p align="center">A native macOS SSH host manager designed for Warp Terminal.</p>

<p align="center">
  <a href="README.md"><strong>English</strong></a> ·
  <a href="README.zh-CN.md">简体中文</a>
</p>

<p align="center">
  macOS 12+ build target · Apple Silicon &amp; Intel · SwiftUI / AppKit + Rust
</p>

<p align="center">
  <a href="https://github.com/javafancn/warp-ssh-manager/releases/latest">Download latest release</a> ·
  <a href="https://github.com/javafancn/warp-ssh-manager/actions/workflows/build-macos-app.yml">Development builds</a> ·
  <a href="https://github.com/javafancn/warp-ssh-manager/actions/workflows/ci.yml">CI</a> ·
  <a href="LICENSE">MIT License</a>
</p>

> **Community project, not affiliated with Warp.** Warp SSH Manager organizes SSH hosts and launches connections in Warp. The actual SSH transport and interactive terminal are still provided by **OpenSSH and Warp**. This app does not implement a separate SSH client.

> **v1.0.6 release:** The W menu bar icon is reduced from 19 pt to 16 pt for better alignment with adjacent macOS status icons. Dock hide/restore, menu bar background mode and ⌃⌥⌘K Quick Connect remain unchanged.

## Features

| SSH host management | Authentication and credentials | Warp integration |
| --- | --- | --- |
| Search, favorites, recent connections | OpenSSH automatic negotiation, key-only or password mode | Open hosts in Warp using native `ssh <alias>` |
| **Nested groups** with expand/collapse, rename and move | macOS Keychain for SSH and sudo passwords | **Spotlight-style quick launcher (⌃⌥⌘K)** |
| **Reusable tags:** Pick labels already used by another host, or type a new tag | Saved/copied/deleted password success notices auto-dismiss after about 3 seconds | Warp/OpenSSH transport unchanged |
| Group-aware filtering and descendant host counts | Optional one-time SSH password Askpass assistance | Dedicated Warp Tab Config files |
| Color-coded tags, notes, ports, jump hosts | Copy passwords; no automatic sudo entry | Import existing `~/.ssh/config` hosts |

The native three-pane interface offers automatic, light, and dark appearances.

### Interface language

In the **sidebar settings (gear icon)**, choose **Language → Follow System / 简体中文 / English**. The main window, host inspector, group editor, quick launcher, and menu-bar commands switch language without restarting the app. Your choice is stored in macOS user defaults and restored at the next launch. User-defined host names, aliases, group names and tags are never translated. Some server/SSH diagnostic output remains in its original language.

### App update checks (v1.0.4)

Open the sidebar **gear → Software Updates → Check for Updates** to compare this installed version with the latest **stable** GitHub Release. When enabled (the default), the app checks once at launch and prompts if a newer version is available. Turn off **Automatically Check for Updates at Launch** to disable these automatic network requests; manual checks remain available.

**Download Update** opens the official Apple Silicon or Intel DMG link in your default browser. No background installer runs, and host records, SSH configuration and Keychain passwords are not modified by the update check. Install manually by opening the DMG and replacing the app. If the expected architecture-specific DMG is missing, only the release notes link is offered.

### Spotlight-style Quick Connect (v1.0.3)

Press **Control + Option + Command + K (⌃⌥⌘K)** from anywhere while Warp SSH Manager is running to toggle the floating quick launcher. This deliberately avoids more widely used shortcuts such as ⌘Space and ⌘K. A system-wide hotkey is registered with macOS (without Accessibility/Input Monitoring permissions); if another app has already claimed the chord, open **Quick Connect** from the menu-bar icon instead. The launcher appears near the top center of the display under your pointer, including when working in other apps or Spaces.

Start typing to search host names, SSH aliases, IPs, tags, or group paths. With an empty query, recently connected hosts appear first. Use **↑ / ↓** to change selection, **Return** to open the selected host in Warp, or **Esc** to dismiss the launcher. Click a row to connect directly. Opening a host still uses the original Warp/OpenSSH integration.

### Keep running in the menu bar

Closing the main window with the **red macOS close button** (or **⌘W**) hides both the manager window and the **running application's Dock icon** without quitting Warp SSH Manager. The menu bar icon and global **⌃⌥⌘K** shortcut stay available; Quick Connect does not bring back the Dock icon. Choose **Open Host Manager** from the menu bar to restore the same window and Dock icon (no duplicate windows). A Dock shortcut you pinned manually may remain visible and can also reopen the manager. Choose **Quit Warp SSH Manager** or use **⌘Q** while active to exit completely. Automatic login launch is not enabled.

## Installation

**Recommended stable release:**

1. Open the [latest GitHub Release](https://github.com/javafancn/warp-ssh-manager/releases/latest).
2. Choose the `apple-silicon` DMG for an Apple Silicon Mac or the `intel` DMG for an Intel Mac.
3. Open the DMG and move **Warp SSH Manager.app** to `/Applications`.
4. Install [Warp Terminal](https://www.warp.dev/) separately. macOS includes OpenSSH; make sure the `ssh` command is available.

**Development builds:** The [macOS Actions workflow](https://github.com/javafancn/warp-ssh-manager/actions/workflows/build-macos-app.yml) offers installers from newer main commits. Artifacts can expire; use Releases for a stable download.

**Compatibility and signing:** The build targets macOS 12 or later and produces separate Apple Silicon and Intel packages, not a Universal Binary. Installers are **ad-hoc signed and not Apple-notarized**, so macOS Gatekeeper may display a warning. Review the download source and follow macOS security guidance rather than disabling Gatekeeper indiscriminately. Compatibility across all macOS versions has not been verified on physical Macs.

## Getting started

### 1. Import or create a host

**Import an existing host:** Import aliases from your existing `~/.ssh/config`. Imported connection parameters continue to be managed by the original SSH configuration: edit the source file and re-import instead of expecting Warp SSH Manager to rewrite it.

**Create a managed host:** Run the app's SSH integration initialization, or `wsm init`, before your first managed connection. Initialization backs up the existing top-level SSH config and adds an `Include` pointing to a dedicated WSM-managed file. Then add a host with:

- Display name and unique SSH alias
- Hostname/IP address, login username and port
- Optional identity file **path**, ProxyJump, group, labels and notes

The app stores the path to an SSH private key, not a copy of the key material.

> Imports may invoke `ssh -G` to evaluate an SSH configuration. Only import configurations you trust; OpenSSH configurations can contain executable `Match exec` conditions.

### 2. Choose an SSH authentication mode

Open **Host details → Connection settings → SSH authentication**:

| Mode | Behavior | Typical use |
| --- | --- | --- |
| **Automatic** | Lets OpenSSH negotiate based on existing SSH configuration and ssh-agent; default for previously configured hosts | Existing SSH setups |
| **SSH key** | For managed hosts, enables public-key authentication and disables password-based authentication | Key-only servers |
| **Username + password** | For managed hosts, enables password and keyboard-interactive authentication instead of public-key authentication | Password-based servers |

Imported hosts keep their original `~/.ssh/config` parameters. Any applicable OpenSSH configuration may still affect the actual authentication behavior.

**Automatic does not mean automatic password injection.** WSM only attempts saved-password Askpass assistance when password authentication is explicitly selected and an SSH password has been saved.

### 3. Save a password and connect

1. Save the host first.
2. In **Connection settings → Credentials**, select **SSH login password** and save the secret in macOS Keychain.
3. Choose **Open in Warp**, double-click a host, or use the menu-bar shortcut.
4. When eligible, WSM prepares a short-lived, single-use `SSH_ASKPASS` authorization. The helper attempts to retrieve the saved secret from Keychain and answer **one recognized password prompt**.
5. If a password is incorrect, the server requires MFA or another interactive response, or helper authorization fails, complete the SSH prompt manually. **Manual connect** is also available to bypass assistance.

WSM still launches the ordinary `ssh <alias>` command in Warp; it does not intercept Warp's PTY stream. **Launching Warp is not proof of successful SSH authentication.** Saved-password login and Warp SSH Extension/other enhanced terminal features still require end-to-end validation with real servers.

### 4. Organize hosts with nested groups

The sidebar supports arbitrarily nested groups:

1. Select **New group**, enter a group name and optionally choose a parent. Choose **Top-level group** for a root group.
2. Right-click any group and select **New subgroup** to create a child directly.
3. Use the disclosure arrow to expand or collapse a branch. Right-click a group and select **Rename or move** to change its name or parent.
4. Selecting a parent group shows its own hosts **and all descendant-group hosts**; the sidebar count includes descendants. Host details show full group paths to distinguish equally named groups under different parents.
5. Sibling names must be unique. A group cannot be moved beneath itself or one of its descendants. **Groups with children cannot be deleted** until their children are moved or removed. Deleting a leaf group does not delete its hosts; the hosts become ungrouped.

Nested groups reuse the existing SQLite `parent_id` column; existing flat groups remain top-level and require no schema migration. Group structure is local metadata and does not modify SSH host configuration.

Tags such as `production`, `test` and `dev` use recognizable colors; other tags have stable colors derived from their names. Tags support inline editing and duplicate checks. Host lists also support favorites, search and recent connections.

### 5. sudo passwords

You can optionally store a different **sudo password** for a host. If not configured, the app can copy the saved SSH password instead. sudo passwords are **copy-only**: they are not automatically detected or typed into remote terminals. SSH passwords can also be copied from the host's action menu.

## Security and privacy

- **macOS Keychain:** SSH and sudo passwords are saved as generic-password entries with `WhenUnlockedThisDeviceOnly` accessibility. Passwords are **not** written in plaintext to SQLite, SSH config, Warp Tab Config or Rust JSON snapshots.
- **One-time Askpass authorization:** Temporary credential requests use restricted-permission files with a 120-second expiry and attempted single consumption. This is not isolation from a malicious process already running as the same macOS user.
- **Prompt checks:** The Askpass helper attempts to respond only to recognized password prompts. Host-key confirmation, MFA and unrelated prompts are not silently answered.
- **Clipboard:** After copying a password, the app attempts to clear the clipboard after about 30 seconds **only if it has not changed**. Clipboard history or other programs may still retain copied data.
- **No automatic sudo entry:** Remote sudo behavior and server authentication policies remain unchanged.
- **Testing limits:** Passing CI does **not** imply real Keychain authorization on all machines, successful password login against all SSH servers, or verified Warp SSH enhancements.

## Command-line usage

The app bundle contains the Rust `wsm` CLI. From the repository root:

```bash
# Basic diagnostics, import and enumeration
cargo run -p wsm-cli -- doctor
cargo run -p wsm-cli -- import
cargo run -p wsm-cli -- list

# Initialize WSM-managed SSH configuration
cargo run -p wsm-cli -- init
cargo run -p wsm-cli -- add \
  --name "Dev API" \
  --alias dev-api \
  --hostname example.com \
  --user deploy \
  --port 22

# Search, dry-run connection and regenerate Warp config
cargo run -p wsm-cli -- list --search dev
cargo run -p wsm-cli -- connect <HOST_UUID> --dry-run
cargo run -p wsm-cli -- sync

# Nested group operations (replace UUID placeholders)
cargo run -p wsm-cli -- group add "Production"
cargo run -p wsm-cli -- group add "Databases" --parent <PARENT_GROUP_UUID>
cargo run -p wsm-cli -- group edit <GROUP_UUID> --name "DB" --root
cargo run -p wsm-cli -- group list
```

Other commands include `edit`, `delete`, `favorite`, `group`, `connect` and `sync --all`:

```bash
cargo run -p wsm-cli -- --help
"/Applications/Warp SSH Manager.app/Contents/MacOS/wsm" --version
```

## Build from source

You need **macOS, Xcode Command Line Tools and Rust/Cargo**. The application is built with SwiftUI/AppKit and Rust.

```bash
xcode-select --install  # Skip if already installed
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

Packages are written to `dist/` and include architecture-specific DMGs and `.app.zip` files. Packaging also compiles the separate Askpass helper and validates bundle metadata and architectures.

## Repository layout

```text
apps/
  wsm-native/Sources/      Native SwiftUI/AppKit interface
  wsm-askpass/             macOS Keychain and SSH_ASKPASS helper
crates/
  wsm-core/                SQLite, SSH hosts, Warp Tab Config
  wsm-cli/                 Command line and native JSON bridge
scripts/                   Build, verification and macOS smoke tests
.github/workflows/         CI and macOS packaging workflows
assets/                    Branding
examples/                  Example SSH/Warp configuration
```

## Local data and upgrades

| Location | Purpose |
| --- | --- |
| `~/Library/Application Support/WarpSSHManager/hosts.sqlite3` | Host/group metadata, favorites, labels and authentication preferences (**not passwords**) |
| `~/.ssh/config` | Existing SSH configuration; an `Include` is added only after explicit initialization |
| `~/.ssh/config.d/warp-ssh-manager.conf` | Managed host definitions |
| `~/.warp/tab_configs/wsm_<UUID>.toml` | Generated Warp launch tabs |
| macOS Keychain | SSH and sudo credentials indexed by host UUID |
| `~/Library/Application Support/WarpSSHManager/askpass_sessions/` | Short-lived single-use authentication files |

`WSM_HOME`, `WSM_SSH_CONFIG` and `WSM_WARP_CONFIG_DIR` can override data locations. Before upgrading, back up `hosts.sqlite3` and your SSH config. SQLite backups do not include Keychain entries. Existing hosts are migrated to the default `auto` authentication preference when required; the app does not provide cross-device Keychain credential migration.

## Tests and contributions

- [Rust / SwiftUI CI](https://github.com/javafancn/warp-ssh-manager/actions/workflows/ci.yml): tests, linting, native typechecking and isolated SSH checks.
- [macOS packaging workflow](https://github.com/javafancn/warp-ssh-manager/actions/workflows/build-macos-app.yml): Intel/Apple Silicon builds and an actual-window screenshot smoke test on Apple Silicon.
- Local checks: `bash scripts/macos-smoke.sh` and `bash scripts/native-ui-bridge-smoke.sh <PATH_TO_WSM>`.

Bug reports should include the macOS and Warp versions, redacted SSH configuration, authentication mode and reproduction steps. **Never attach passwords, private keys, tokens or production host inventories.**

## License

[MIT License](LICENSE). Not affiliated with Warp.
