import Foundation
import CoreGraphics

// Return the id of the frontmost real Warp SSH Manager window so macOS
// screencapture can image the ENTIRE window, even on a 1024x768 CI display.
let windows = CGWindowListCopyWindowInfo(
    [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
) as? [[String: Any]] ?? []
let candidates = windows.compactMap { item -> (id: Int, layer: Int, name: String)? in
    guard let owner = item[kCGWindowOwnerName as String] as? String,
          owner.contains("Warp SSH"),
          let id = item[kCGWindowNumber as String] as? Int else { return nil }
    let layer = item[kCGWindowLayer as String] as? Int ?? 0
    // Ignore 22x22 menu-bar icon windows when requesting a quick-panel
    // screenshot: the real panel is roughly 510x556 points.
    if CommandLine.arguments.dropFirst().first == "quick",
       let bounds = item[kCGWindowBounds as String] as? [String: Any],
       let width = bounds["Width"] as? NSNumber,
       let height = bounds["Height"] as? NSNumber,
       width.doubleValue < 400 || height.doubleValue < 400 { return nil }
    return (id, layer, owner)
}
// Floating borderless panels have a positive CGWindow layer. The default
// query intentionally selects the manager rather than the menu-bar panel.
let wantsQuick = CommandLine.arguments.dropFirst().first == "quick"
let selected = wantsQuick
    ? (candidates.first(where: { $0.layer > 0 }) ?? candidates.first)
    : (candidates.first(where: { $0.layer == 0 }) ?? candidates.first)
if let window = selected {
    print(window.id)
} else {
    fputs("No visible native Warp SSH window found\n", stderr)
    exit(1)
}
