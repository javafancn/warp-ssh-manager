# v0.3 — confirmed design implementation

- Updated actual GPUI main window: macOS-style toolbar, continuous 222/340/fluid three-column design, compact server rows and theme-consistent controls.
- Added group count pills, first-host selection, a cleaner empty state, a settings area for SSH setup/import/sync, and a condensed sidebar group creation flow.
- Added visual tag chips linked to editable SQLite annotations.
- Updated Quick Connect window with environment badges, stars and a compact search layout.
- Preserved System / Dark / Light state in the Rust theme system; updated interactive HTML preview with all three modes.
- Preserved macOS 12.0 and dual-architecture *targets*; no claim of verified builds or runtime support until tested on a Mac.

Limitations: menu popover is floating rather than status-item anchored; Mac compilation and visual diff are still pending.
