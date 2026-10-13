import SwiftUI
import AppKit

// NSVisualEffectView is a genuine macOS material, not a painted or blurred
// screenshot. It automatically follows the active appearance and desktop.
struct MacMaterial: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    // Behind-window sampling preserves the user's actual desktop colors.
    // No synthetic wallpaper, gradients, or fixed window-wide color wash.
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow
    // Control translucency on native material, not an artificial gradient.
    var opacity: CGFloat = 1.0
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        view.isEmphasized = false
        view.alphaValue = opacity
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        // Avoid telling WindowServer to reconfigure an unchanged backdrop
        // after each unrelated @Published host/draft mutation.
        if view.material != material { view.material = material }
        if view.blendingMode != blendingMode { view.blendingMode = blendingMode }
        if view.alphaValue != opacity { view.alphaValue = opacity }
    }
}
final class ChromeView: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window = window else { return }
        window.title = "Warp SSH 管理器"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.isOpaque = false
        // NSWindow and the titlebar must not inject a solid gray backing.
        // NSVisualEffectView is responsible for the native material.
        window.backgroundColor = .clear
        // Restore genuine traffic-light buttons in full-size-content windows.
        window.styleMask.formUnion([.titled, .closable, .miniaturizable,
                                    .resizable, .fullSizeContentView])
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            window.standardWindowButton(button)?.isHidden = false
            window.standardWindowButton(button)?.alphaValue = 1
        }
        // Dragging belongs to the actual titlebar, not interactive cards
        // or input backgrounds; the latter should respond to clicks at once.
        window.isMovableByWindowBackground = false
        window.minSize = NSSize(width: 1110, height: 740)
        window.hasShadow = true
        // SwiftUI ScrollView uses NSScrollView underneath. Remove only its
        // scroller chrome, not scrolling, including when the user's system
        // preference is "Always" show scroll bars.
        DispatchQueue.main.async { [weak self] in self?.hideWindowScrollChrome() }
        // SwiftUI mounts the LazyVStack after viewDidMoveToWindow. A single
        // delayed pass catches that first tree, without the per-click traversal
        // that previously made the app sluggish.
        DispatchQueue.main.asyncAfter(deadline:.now() + 0.6) {
            [weak self] in self?.hideWindowScrollChrome()
        }
        // Configure the initial window once; preserve the user's resized bounds.
        if window.identifier?.rawValue != "wsm.native.configured" {
            window.setContentSize(NSSize(width: 1280, height: 816))
            window.center()
            window.identifier = NSUserInterfaceItemIdentifier("wsm.native.configured")
        }
        // Never guess the main window using NSApp.windows.first: Dock and
        // status-menu actions must target this exact SwiftUI WindowGroup window.
        (NSApp.delegate as? StatusBarDelegate)?.registerManagerWindow(window)
    }

    func hideWindowScrollChrome() {
        guard let root = window?.contentView else { return }
        func visit(_ view: NSView) {
            if let scroll = view as? NSScrollView {
                scroll.scrollerStyle = .overlay
                scroll.autohidesScrollers = true
                scroll.hasVerticalScroller = false
                scroll.hasHorizontalScroller = false
            }
            view.subviews.forEach(visit)
        }
        visit(root)
    }
}
struct NativeWindowConfiguration: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { ChromeView() }
    // Do not traverse the entire AppKit window on every @Published
    // state change: selecting a host should never enqueue O(view count) work.
    func updateNSView(_ nsView: NSView, context: Context) {}

}

enum Design {
    static let blue = Color(red:0.055, green:0.455, blue:0.98)
    // Decode and cache the logo once; re-reading PNG data on every sidebar
    // invalidation made appearance changes and clicks unnecessarily expensive.
    static let brandIcon: NSImage = {
        guard let path = Bundle.main.resourceURL?.appendingPathComponent("brand-app-icon.png").path,
              let image = NSImage(contentsOfFile:path) else { return NSImage() }
        return image
    }()
    // Labels follow the resolved system appearance.
    // Without this, the "深色" segmented control produced white text on
    // permanently white fields, making the native UI unreadable.
    static let primary = Color(nsColor:.labelColor)
    static let secondary = Color(nsColor:.secondaryLabelColor)
    static let muted = Color(nsColor:.tertiaryLabelColor)
    static let hairline = adaptive(
        NSColor(calibratedRed:0.60,green:0.69,blue:0.82,alpha:0.26),
        NSColor(calibratedWhite:0.67,alpha:0.31))
    static let paneBorder = Color(nsColor:.separatorColor).opacity(0.38)
    static let inputBorder = adaptive(
        NSColor(calibratedRed:0.64,green:0.72,blue:0.84,alpha:0.48),
        NSColor(calibratedWhite:0.68,alpha:0.38))
    private static func adaptive(_ light:NSColor,_ dark:NSColor) -> Color {
        Color(nsColor:NSColor(name:nil,dynamicProvider: { appearance in
            appearance.bestMatch(from:[.darkAqua,.aqua]) == .darkAqua ? dark : light
        }))
    }
    // Reserve controlled color for interactive content, never entire panes.
    // Opaque white cards made the natural desktop colors disappear.
    static let cardSurface = surface(0.58)
    static let searchSurface = surface(0.34)
    static let selectedSurface = adaptive(
        NSColor(calibratedRed:0.840,green:0.925,blue:1,alpha:0.78),
        NSColor(calibratedRed:0.15,green:0.28,blue:0.46,alpha:0.82))
    static func surface(_ opacity:Double = 0.82) -> Color {
        adaptive(NSColor(calibratedWhite:1,alpha:opacity),
                 NSColor(calibratedRed:0.19,green:0.24,blue:0.33,alpha:opacity))
    }
    static func font(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size:size, weight:weight, design:.default)
    }
}

struct SoftButtonStyle: ButtonStyle {
    var prominent: Bool = false
    var destructive: Bool = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(prominent ? .white : destructive ? .red : Design.primary)
            .background(
                RoundedRectangle(cornerRadius:10,style:.continuous)
                    .fill(prominent ? Design.blue : destructive ? Color.red.opacity(0.10) : Design.surface(0.80))
            )
            .overlay(
                RoundedRectangle(cornerRadius:10,style:.continuous)
                    .strokeBorder(prominent ? Color.clear : Design.hairline,lineWidth:1)
            )
            .shadow(color:Color.black.opacity(configuration.isPressed ? 0.015 : 0.06),
                    radius:configuration.isPressed ? 1 : 5,y:2)
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

@main
struct WarpSSHNativeApp: App {
    @NSApplicationDelegateAdaptor(StatusBarDelegate.self) private var menuBar
    var body: some Scene {
        WindowGroup {
            ManagerShell()
                .frame(minWidth:1110,minHeight:740)
                .background(NativeWindowConfiguration())
                .windowToolbarStyle()
        }
        // Retain a genuinely titled NSWindow so macOS paints the three
        // traffic-light controls. ChromeView hides only the title text and
        // extends the translucent content behind the titlebar.
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
        // Display the SwiftUI content behind the native traffic lights.
        // The default macOS WindowGroup style reserves a separate 28-32pt
        // gray titlebar even when NSWindow.titleVisibility is hidden.
        // This scene-level style removes its backing and reserved strip.
        .windowStyle(HiddenTitleBarWindowStyle())
    }
}

// SwiftUI ScrollView indicators can remain permanently visible when macOS
// Accessibility is configured to always show scrollbars. The reference design
// hides the indicator chrome but not the actual trackpad/mouse scrolling.
// Introspect the backing NSScrollView from *inside* its content hierarchy.
struct NativeScrollbarCleaner: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        ScrollbarProbe(frame:.zero)
    }
    func updateNSView(_ nsView: NSView, context: Context) {
        // Scrollers are configured when mounted, not on each SwiftUI update.
    }
    private final class ScrollbarProbe: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            DispatchQueue.main.async { [weak self] in self?.apply() }
            DispatchQueue.main.asyncAfter(deadline:.now() + 0.6) {
                [weak self] in self?.apply()
            }
        }
        func apply() {
            var parent = superview
            while let current = parent {
                if let scroll = current as? NSScrollView {
                    scroll.scrollerStyle = .overlay
                    scroll.autohidesScrollers = true
                    scroll.hasVerticalScroller = false
                    scroll.hasHorizontalScroller = false
                    return
                }
                parent = current.superview
            }
        }
    }
}

// No fake window buttons: macOS manages the traffic lights and resizing.
extension View {
    func windowToolbarStyle() -> some View { self }

    // Scroll indicators are normally hidden by macOS on modern desktops.
    // Preserve the macOS 12 deployment target by guarding the newer API.
    @ViewBuilder
    func hideNativeScrollIndicators() -> some View {
        if #available(macOS 13.0, *) {
            self.scrollIndicators(.hidden)
        } else {
            self
        }
    }
}

struct ManagerShell: View {
    @StateObject private var store = ManagerStore()
    @State private var loaded = false
    var body: some View {
        GeometryReader { geometry in
            // Respect the reference's ~22%/37%/41% three-pane rhythm across
            // laptop resolutions while keeping the inspector comfortable.
            let sidebarWidth = max(258, min(300, geometry.size.width * 0.225))
            let listWidth = max(415, min(525, geometry.size.width * 0.378))
            let inspectorWidth = max(310, geometry.size.width - sidebarWidth - listWidth - 2)
            let chromeScale = max(CGFloat(0.79), min(CGFloat(1), geometry.size.width / 1410))
            HStack(spacing:0) {
                ManagerSidebar(paneWidth:sidebarWidth)
                    .frame(width:sidebarWidth)
                Rectangle().fill(Design.hairline).frame(width:1)
                VStack(spacing:0) {
                    // The title row belongs to the SAME continuous glass as
                    // the connection list and inspector. A second .titlebar
                    // NSVisualEffectView made it appear as a detached pale bar.
                    ConnectionToolbar(scale:chromeScale)
                        .frame(height:70 * chromeScale)
                    Rectangle().fill(Design.hairline).frame(height:1)
                    HStack(spacing:0) {
                        ConnectionList(listWidth:listWidth)
                            .frame(width:listWidth)
                        Rectangle().fill(Design.hairline).frame(width:1)
                        HostInspector(paneWidth:inspectorWidth)
                            .frame(maxWidth:.infinity,maxHeight:.infinity)
                    }
                }
            }
        }
        .frame(maxWidth:.infinity,maxHeight:.infinity)
        // One uninterrupted AppKit material covers the whole NSWindow,
        // including 1pt dividers and the seam beneath the toolbar.
        // Keep its alpha near-opaque: a previous 0.81 setting let raw desktop
        // windows and desktop file labels show clearly THROUGH form controls.
        // 0.96 keeps wallpaper-sampled vibrancy while preventing that ghosting.
        // Content and inspector panes stay clear to avoid double blur.
        .background {
            MacMaterial(material:.underWindowBackground,
                        blendingMode:.behindWindow,opacity:0.96)
                .ignoresSafeArea(.container,edges:.all)
        }
        // Hidden-titlebar windows reserve a top safe area unless the content
        // explicitly occupies it; otherwise a dark 22px stripe appears above
        // the SwiftUI toolbar on macOS.
        .ignoresSafeArea(.container,edges:.top)
        .environmentObject(store)
        .preferredColorScheme(store.appearance == "dark" ? .dark :
                            (store.appearance == "light" ? .light : nil))
        .overlay(alignment:.top) {
            if let message = store.errorMessage {
                HStack(spacing:12) {
                    Image(systemName:"exclamationmark.triangle.fill").foregroundColor(.orange)
                    Text(message).font(Design.font(13)).lineLimit(3)
                    Spacer()
                    Button("关闭") {store.errorMessage = nil}.buttonStyle(.plain)
                }
                .padding(14)
                .frame(maxWidth:650)
                .background(.regularMaterial,in:RoundedRectangle(cornerRadius:12))
                .shadow(radius:12)
                .padding(.top,76)
                .zIndex(10)
            }
        }
        .onAppear {
            if !loaded {
                loaded = true
                store.refresh()
                // Isolated GUI screenshot fixture only: exercise the advanced
                // layout without clicking tabs in a real user's session.
                if ProcessInfo.processInfo.environment["WSM_CI_ADVANCED_INSPECTOR"] == "1" {
                    DispatchQueue.main.asyncAfter(deadline:.now()+4) {
                        store.tab = .advanced
                    }
                }
            }
        }
    }
}

struct ConnectionToolbar: View {
    var scale: CGFloat = 1
    @EnvironmentObject private var store: ManagerStore
    var body: some View {
        HStack(spacing:14 * scale) {
            Text("连接列表")
                .font(Design.font(24 * scale,.semibold))
                .foregroundColor(Design.primary)
            Spacer(minLength:12 * scale)
            HStack(spacing:3 * scale) {
                appearanceSegment("auto","自动")
                appearanceSegment("dark","深色")
                appearanceSegment("light","浅色")
            }
            .padding(3 * scale)
            .frame(width:258 * scale,height:42 * scale)
            // Light control chrome, not another material pane.
            .background(Design.surface(0.24),in:RoundedRectangle(cornerRadius:11 * scale))
            .overlay(RoundedRectangle(cornerRadius:11 * scale)
                .strokeBorder(Design.hairline.opacity(0.75),lineWidth:1))
            .accessibilityLabel("外观设置")
            Button(action:{store.newHost()}) {
                Label("新建主机",systemImage:"plus")
                    .font(Design.font(16 * scale,.semibold))
                    .padding(.horizontal,31 * scale)
                    .frame(height:42 * scale)
            }
            .buttonStyle(SoftButtonStyle(prominent:true))
        }
        .padding(.leading,23 * scale)
        .padding(.trailing,21 * scale)
        // The scene now uses HiddenTitleBarWindowStyle; additional titlebar
        // clearance would push these controls below the reference position.
    }

    private func appearanceSegment(_ value: String,_ label: String) -> some View {
        let selected = store.appearance == value
        return Button {
            store.appearance = value
        } label: {
            Text(label)
                .font(Design.font(16 * scale,selected ? .semibold : .medium))
                .foregroundColor(selected ? Design.blue : Design.secondary)
                .frame(maxWidth:.infinity).frame(height:36 * scale)
                .background(selected ? Design.surface(0.86) : .clear,
                            in:RoundedRectangle(cornerRadius:9 * scale,style:.continuous))
                .shadow(color:.black.opacity(selected ? 0.09 : 0),radius:3,y:1)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}
