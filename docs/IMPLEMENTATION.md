# Warp SSH Manager — implementation notes

## Target

- macOS 14+, Apple Silicon preferred
- Rust 2021, GPUI 0.2.2, GPUI Component 0.5.1, SQLite (bundled)
- Runtime: Warp Terminal stable and system OpenSSH
- UI: desktop window with basic dark theme; optional native status-item menu

## Core invariants

1. `Host.id` is a UUID and is the only input to the generated Tab Config file stem. Host rename leaves URI stable.
2. Imported hosts are **not** written to `config.d/warp-ssh-manager.conf`.
3. Managed connections use OpenSSH's `Host` aliases. Config is always generated from DB records; it is not the master copy.
4. User SSH file is modified **only after** `init` is explicitly requested and a backup is saved.
5. No password, private key body or SSH session data is persisted.
6. `warp://` dispatching is best-effort: launch success cannot infer remote connectivity.
7. Generated `.toml` deletion/overwrite must confirm application ownership marker.
8. Arbitrary user strings are not used as command arguments in a shell. The command embedded in a Warp pane uses a strict validated SSH alias.

## DB schema

- `groups(id, name, parent_id, sort_order)` with self-referential foreign key for hierarchies.
- `hosts(id, name, alias UNIQUE NOCASE, hostname, username, port, identity_file, proxy_jump, group_id, favorite, source, last_connected)`.

## One-click flow

1. `Manager::prepare_connection(host_id)` reads the DB and asserts that managed SSH Include is available.
2. `warp::write_tab` serializes a valid single-pane TOML under `~/.warp/tab_configs/wsm_<uuid>.toml`.
3. `warp::open_tab` executes `/usr/bin/open warp://tab_config/wsm_<uuid>` **as an argv array** (no shell interpolation).
4. macOS dispatches Warp's registered URL handler; Warp opens Tab Config and runs `ssh <safe-alias>`.
5. DB records last **launch request**, not verified online status.

## File mutation

- `ssh::atomic_write` uses same-directory temporary file, `sync_all`, `rename` and 0600 permissions.
- Existing `~/.ssh/config` gets a backup with a unique suffix before adding an Include at the beginning.
- Include insertion is idempotent for the manager's exact normalized line.
- No bulk cleanup of Tab Configs in response to timeouts: users could still be opening a tab.

## Remaining hardening before public release

- Build and test on an actual Mac; pin a tested Cargo.lock.
- Review all GPUI 0.2.2 and gpui-component 0.5.1 API usage, especially custom buttons and tray callback lifetimes.
- Move DB operations off the GPUI main thread for large SSH configurations.
- Native NSText accessibility, keyboard focus and WCAG testing, macOS automatic appearance.
- Stronger concurrent DB/process locking and atomic multi-file transaction/reconciliation.
- Confirm Warp installed or explain it in the UI; support Warp Preview in the GUI.
- Implement robust Include tokenizer and `Match exec` safety warning in onboarding.
- Unit tests with actual `ssh -G -F <fixture>` to cover complex alias evaluation (current `-G` loads user's default config).
- Harden path traversal symlink/ownership checks for hostile local filesystem environments.
- Build-time app icon, Developer ID signature and Apple notarization.
