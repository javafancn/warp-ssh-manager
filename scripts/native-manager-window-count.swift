import Foundation
import CoreGraphics

// macOS WindowServer regression: detect two ACTUAL visible manager windows.
// Status bar icons and the separate floating quick panel are not managers.
let windows = CGWindowListCopyWindowInfo(
    [.optionOnScreenOnly,.excludeDesktopElements],kCGNullWindowID
) as? [[String:Any]] ?? []
let managers = windows.compactMap { info -> Int? in
    guard let owner=info[kCGWindowOwnerName as String] as? String,
          owner.contains("Warp SSH"),
          let id=info[kCGWindowNumber as String] as? Int,
          let layer=info[kCGWindowLayer as String] as? Int, layer == 0,
          let bounds=info[kCGWindowBounds as String] as? [String:Any],
          let w=bounds["Width"] as? NSNumber,
          let h=bounds["Height"] as? NSNumber,
          w.doubleValue >= 900, h.doubleValue >= 600 else { return nil }
    return id
}
print("Visible main manager windows: \(managers.count) (window IDs: \(managers))")
if managers.count != 1 {
    fputs("FAILED: Dock reopen must leave exactly one visible main window\n",stderr)
    exit(1)
}
