# v0.2 UI update

- Replaced fixed dark, card-based panel arrangement with the approved full-width three-column macOS design.
- Implemented two complete app palettes: dark charcoal/navy and light white/gray; retained the blue action accent.
- Added Auto/Dark/Light preference selector with persisted state, and system appearance observer in the main view.
- Made group hierarchy collapsible and added All Servers/Favorites/Recent filters and inline star toggle.
- Made right-side inspector a compact horizontal-label form; added tags and multiline notes.
- Added a backward-compatible SQLite `host_annotations` table and an annotation cascade-delete test.
- Added GPUI Quick Connect floating search window, accessible through the native status-item menu.
- Added the approved design images and an independent, interactive HTML theme preview for review without macOS compilation.

Outstanding: exact menu-bar icon anchored popover, native appearance override of the titlebar during manual theme switching, AppKit focus lifecycle/polish, macOS compilation, notarized `.app` delivery.
