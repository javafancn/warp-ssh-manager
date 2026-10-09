# Warp SSH Manager 0.3 — UI Implementation Guide

This iteration implements the **approved design** as GPUI application code (not as a static image). The two visual references are bundled in `docs/reference/`.

## Main window

- Default size **1320 × 810 px**, resizable native macOS window.
- Three contiguous columns: **222 px groups**, **340 px connections**, fluid details inspector.
- Left: all hosts / favorites / recently launched, nested expandable groups, new subgroup control.
- Center: host search (name, alias, IP), color-coded environment badges, stars (click to favorite), selected blue row, empty state.
- Right: display name, SSH alias, hostname, user, port, identity, group dropdown, tags, ProxyJump, multiline notes, favorite switch, **Open in Warp** / Save / Delete.
- Top: compact title, **Auto / Dark / Light** selector, New Host, and a settings button revealing SSH setup/import/sync.
- Bottom: local configuration status with count + actual last-operation message. **Not** a live SSH session monitor.

## Themes

| Component | Dark | Light |
| --- | --- | --- |
| Application background | `#101722` | `#F7F9FC` |
| Sidebar | `#1B2432` | `#F0F3F8` |
| Connections | `#131B27` | `#FFFFFF` |
| Inspector | `#18212E` | `#FFFFFF` |
| Blue accent | `#3079F5` | `#246DF2` |
| Selected row | `#1A3D75` | `#E6EFFF` |

Theme state is saved as `appearance.txt` under `WSM_HOME` / `~/Library/Application Support/WarpSSHManager`.
Available values are `system`, `dark`, and `light`. Auto responds to macOS window appearance changes in the main manager. The component library's color theme is changed together with the custom GPUI palette.

## Quick Connect

With `--features tray`, select **Quick Connect…** from the native status menu. A GPUI floating window opens with a live search field, recently used/favorite-first ordering, click-to-connect, and Enter-to-connect-first-result. It uses the saved appearance. The menu-bar icon is not yet an exact anchored macOS popover; keyboard focus/dismiss behaviors require Mac validation.

## Data migration

The `host_annotations` SQLite table is created on startup using `CREATE TABLE IF NOT EXISTS`, with a foreign key to existing `hosts` and `ON DELETE CASCADE`. This adds `tags` and `notes` without altering existing `Host` or `HostInput` layouts and without modifying OpenSSH files.

## macOS visual/functional acceptance checklist

- [ ] Compile: `cargo check -p wsm-desktop` and `cargo check -p wsm-desktop --features tray`.
- [ ] Launch on Apple Silicon Mac and compare against `reference/approved-themes.png`.
- [ ] Toggle Dark → Light → System, restart, verify persisted preference.
- [ ] In System mode, switch macOS Appearance while app is running.
- [ ] Verify all Input widgets and scrollbar colors match each theme.
- [ ] Verify 1320×810 layout, narrow window behavior, full-height scroll and no footer overlap.
- [ ] Group nesting/collapse, favorites and recent navigation; star updates stored data.
- [ ] Add managed host, update managed host, import existing SSH alias, edit tags/notes, delete safely.
- [ ] Menu bar → Quick Connect → search, Enter, and click; actual Warp Tab opens.
- [ ] With a real host, verify authentication takes place in Warp, never in Manager.
- [ ] Accessibility: VoiceOver, focus navigation, contrast, reduced motion.

## Implementation boundaries

Current builds cannot be claimed macOS-tested from this Linux-only artifact authoring environment, which has neither Rust/Cargo nor Xcode installed. This is source code and a design preview, not a signed or notarized `.app`.
