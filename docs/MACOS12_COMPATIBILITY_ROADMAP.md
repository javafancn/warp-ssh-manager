# Warp SSH Manager — macOS 12+ Compatibility and UI Roadmap

**Decision date:** 2026-10-09  
**Baseline:** v0.2 Rust workspace (GPUI `=0.2.2`, GPUI Component `=0.5.1`)  
**Status:** Compatibility **target**, not certified macOS 12 support. Desktop code has **not** been compiled and exercised on a Mac in this environment.

## Non-negotiable product decisions

- Native Rust application; GPUI UI and `objc2` / AppKit where operating-system APIs are required; no SwiftUI, Electron or WebView UI.
- Deploy target **macOS 12.0 Monterey** with native `x86_64-apple-darwin` and `aarch64-apple-darwin` slices; eventual **Universal 2** release bundle.
- Continue using **the matched published GPUI 0.2.2 / gpui-component 0.5.1 pair**, pinned in `apps/wsm-desktop/Cargo.toml`, and a committed `Cargo.lock` once resolved on a Mac. No `gpui-kit 0.7.1` migration for this compatibility branch because its current documentation targets macOS 15+.
- Pixel-level intent: `docs/reference/approved-themes.png` and `docs/UI_DESIGN.md`. Main surface has contiguous Folders / Connections / Server Details columns, search, favorites, tags, notes, Open in Warp and restrained theme-dependent colors.
- SSH authentication stays with OpenSSH/Warp. Never handle credentials, and never label a URI dispatch as successful SSH login.

## Actual code audit (v0.2)

| Area | Existing implementation | Gap / risk |
|---|---|---|
| UI | Three-column GPUI window, group filter, search, editor | Real macOS layout/focus/accessibility unverified |
| Themes | `Palette` with dark/light tokens; preference `system/dark/light` persisted to `appearance.txt` | Native titlebar and component-kit widgets may ignore manual override; contrast/IME testing needed |
| Quick Connect | Floating GPUI searchable window; menu-bar item launches it | Not anchored to `NSStatusItem`; dismissal/focus/multiple-screen behavior unverified |
| SSH | Existing import, managed Include, Warp Tab Configs and URI launch | Ensure import/rollback/multi-config safety on Monterey |
| Build | `cargo-bundle` single-architecture script, previous metadata macOS 14 | Deployment target changed to 12 **in this roadmap snapshot**; separate per-arch builds and universal merge added as candidate packaging script |
| Distribution | Local project bundle path | No Developer ID signature, notarization, automated updates or real-machine test |

## Milestone 0 — compile and lock dependencies (release gate)

1. On a supported macOS build host, install stable Rust, Xcode Command Line Tools, both Rust Darwin targets.
2. Run `cargo fmt --all -- --check`, `cargo test --workspace --exclude wsm-desktop`, `cargo check -p wsm-desktop`, `cargo check -p wsm-desktop --features tray`.
3. Resolve any **real** GPUI API mismatch (GPUI 0.2.2 and component 0.5.1), then generate/commit `Cargo.lock`. Run `cargo tree -d` for duplicate GPUI branches.
4. Verify launch, text rendering, Input widgets, view updates, Quick Connect event dispatch on a real Mac. Do not substitute a browser mockup for runtime GUI verification.

**Exit criterion:** Both CLI and desktop compile; basic UI opens and a dry-run generates the correct Warp Tab Config.

## Milestone 1 — macOS 12 architecture and API audit (release gate)

1. Verify `MACOSX_DEPLOYMENT_TARGET=12.0` is respected by each compiled Mach-O slice using `otool -l`; `minimum_system_version` in package metadata is **not enough** by itself.
2. Build native x86_64 and ARM64 binaries; inspect `otool -L` for third-party dylibs requiring bundling; merge using `lipo`.
3. Enumerate every `objc2`, tray, native window, font/IME and Metal API used by desktop. Gate any >12 API with `respondsToSelector` or OS-version availability; supply a Monterey-safe fallback.
4. Test launch/close/reopen; live theme switching; system theme changes; default window chrome; keyboard focus; multi-monitor; sleep/wake; full-screen; accessibility.
5. Compatibility testing must include **actual macOS 12** (physical machines or a faithful VM). A binary declaring 12.0 in `otool` is **not** proof it executes correctly.

**Exit criterion:** Successful macOS 12 app launch + core workflows on both architectures, no unresolved crash or fatal rendering defect.

## Milestone 2 — approved UI parity

### Main window (1320×810 reference)

- Header: macOS traffic lights and title, New Host, Import, Sync, automatic/manual theme selector.
- Sidebar (~235px): All Servers, Favorites, Recents, nested groups; selected state, collapse, new-group workflow, counts.
- Connections (~360px): keyboard-searchable list, star control, environment badge, hostname/alias summary, sort by recent/favorite, useful empty/error/loading states.
- Inspector (flexible width): display name, alias, address, user, port, identity path, group, tags, ProxyJump, multiline notes; disabled connection fields for imported hosts; confirmation before delete.
- Footer: last config sync result, local SSH config validation state, host/group counts. **No invented online indicator**.

### Theme design system

- Keep the two palette sets in `apps/wsm-desktop/src/theme.rs` and use semantic tokens instead of hard-coded one-off colors.
- Supported choices: `System`, `Dark`, `Light`. Persist to application data; apply consistently to **main window + Quick Connect + GPUI components + native chrome where APIs allow**.
- React live to system appearance events, and support contrast, focus indicators, selection state, hover feedback, keyboard navigation, VoiceOver labels and reduced motion.
- Test truncation and scrolling on narrower windows instead of shrinking form controls to unreadable widths. At a minimum width threshold, allow inspector to become a toggleable view.

**Exit criterion:** UI compare checklist against both reference renders, feature parity in both themes, no unusable forms at tested sizes.

## Milestone 3 — native macOS Quick Connect

- Retain current floating GPUI window as the reliable fallback on macOS 12.
- Provide a native `NSStatusItem` menu-bar action; explore anchoring a GPUI window to the status item position **without embedding unsupported event loops**.
- Dismiss reliably on focus loss and Escape; keyboard Up/Down, Enter, Cmd+K; avoid lost focus on second display and after app switching.
- Refresh favorites without relaunching the app. Keep preview/start semantics honest: "Open request sent" rather than "Connected".

**Exit criterion:** A user can open Quick Connect, type a host, press Enter and see Warp create the expected Tab Config on macOS 12 Intel and ARM64.

## Milestone 4 — production hardening

- Import-only mode for existing SSH config; managed Include and backup only after explicit opt-in.
- Backup/atomic write/ownership marker/collision prevention for managed SSH and Warp config files.
- Migrations for SQLite annotations/tags; verify not corrupted on upgrades/rollback.
- Release tests: multiple Include files, host aliases, ProxyJump, invalid paths, untrusted Match exec, duplicate hosts, no-Warp-installed state, read-only home directory, failing Warp URI handler.
- Add CI for Rust checks, basic macOS build jobs and architecture merge validation. Keep Monterey runtime verification in manual QA until a suitable runner exists.
- Package signed + notarized Universal 2 `.app` and `.dmg`; verify `lipo -archs`, Mach-O minOS, app `LSMinimumSystemVersion`, launch on each hardware family.

## Compatibility acceptance matrix

| Platform | Build | App launch | Themes | Native tray/Quick Connect | Warp launch | SSH Config safety |
|---|---|---|---|---|---|---|
| macOS 12 Intel x86_64 | Required | Required | Required | Required | Required | Required |
| macOS 12 Apple Silicon | Required | Required | Required | Required | Required | Required |
| macOS 13 Intel/ARM64 | Required | Required | Required | Required | Required | Required |
| macOS 14 Intel/ARM64 | Required | Required | Required | Required | Required | Required |
| macOS 15+ Apple Silicon | Required | Required | Required | Required | Required | Required |

**Release gate:** No system may be advertised as supported until its row has been tested. A single Universal 2 executable does not establish OS-version compatibility.

## Concrete build verification commands

```bash
rustup target add x86_64-apple-darwin aarch64-apple-darwin
export MACOSX_DEPLOYMENT_TARGET=12.0
cargo fmt --all -- --check
cargo test --workspace --exclude wsm-desktop
cargo check -p wsm-desktop --features tray
bash scripts/macos-smoke.sh
bash scripts/build-universal-macos.sh
bash scripts/verify-macos-binary.sh "target/universal/Warp SSH Manager.app" --universal
```

The new universal build script is a **candidate local development bundle**, not an Apple Developer ID signed release. Do not ship without runtime QA, signing and notarization.

## Implementation order and issue-level tasks

| Issue | Priority | Work item | Dependency |
|---|---|---|---|
| WSM-101 | P0 | Resolve desktop compile and lock dependency graph | none |
| WSM-102 | P0 | Monterey deployment target and native API compatibility audit | 101 |
| WSM-103 | P0 | Intel/ARM64 build and Universal 2 packaging | 101,102 |
| WSM-104 | P0 | Dark/Light/System theme consistency in chrome, inputs, quick panel | 101 |
| WSM-105 | P1 | Reference UI spacing, keyboard navigation, narrow layouts | 104 |
| WSM-106 | P1 | Quick Connect status-item / floating fallback lifecycle | 101,102 |
| WSM-107 | P1 | SSH import/config safety regression tests | 101 |
| WSM-108 | P1 | Monterey Intel/Apple Silicon real-machine QA | 102–107 |
| WSM-109 | P2 | Developer ID signing, notarized dmg and release CI | 103,108 |

## Explicit exclusions for this phase

No embedded terminal, no password vault, no SFTP file explorer, no cloud synchronization, no new UI framework, and no optimistic claim that a new Warp URI means SSH login succeeded.
