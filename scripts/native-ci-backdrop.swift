import AppKit

// Visual-regression fixture ONLY. This process is launched by
// scripts/native-visual-smoke.sh and never included in the user-facing app.
// A separate AppKit window behind the target NSWindow makes behind-window
// vibrancy testable even on hosted CI desktops without Finder wallpapers.
final class TestBackdrop: NSView {
    override func draw(_ rect: NSRect) {
        let warm = ProcessInfo.processInfo.environment["WSM_CI_BACKDROP_STYLE"] == "warm"
        let bg = NSGradient(
            starting: warm
                ? NSColor(calibratedRed: 0.96, green: 0.70, blue: 0.36, alpha: 1)
                : NSColor(calibratedRed: 0.37, green: 0.64, blue: 0.98, alpha: 1),
            ending: warm
                ? NSColor(calibratedRed: 0.97, green: 0.82, blue: 0.43, alpha: 1)
                : NSColor(calibratedRed: 0.65, green: 0.37, blue: 0.91, alpha: 1)
        )
        bg?.draw(in: bounds, angle: 130)

        // A subtle color variation lets visual smoke identify real backdrop
        // sampling. All colors live in this separate testing process.
        (warm
            ? NSColor(calibratedRed: 0.98, green: 0.40, blue: 0.12, alpha: 0.26)
            : NSColor(calibratedRed: 0.19, green: 0.78, blue: 0.95, alpha: 0.26)
        ).setFill()
        NSBezierPath(ovalIn: NSRect(x: bounds.midX * 0.6, y: bounds.midY * 0.5,
                                   width: bounds.width * 0.72,
                                   height: bounds.height * 0.82)).fill()
    }
}
let reduceTransparency = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
print("CI Accessibility.reduceTransparency=\(reduceTransparency)")
fflush(stdout)
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let screen = NSScreen.main ?? NSScreen.screens.first
let bounds = screen?.frame ?? NSRect(x: 0, y: 0, width: 1600, height: 1000)
let backgroundWindow = NSWindow(contentRect: bounds, styleMask: .borderless,
                                backing: .buffered, defer: false)
backgroundWindow.backgroundColor = .clear
backgroundWindow.isOpaque = true
backgroundWindow.hasShadow = false
backgroundWindow.ignoresMouseEvents = true
backgroundWindow.level = NSWindow.Level(rawValue: NSWindow.Level.normal.rawValue - 1)
backgroundWindow.contentView = TestBackdrop(frame: NSRect(origin: .zero, size: bounds.size))
backgroundWindow.orderFrontRegardless()
app.run()
