import SwiftUI
import AppKit

// A borderless NSPanel is a keyboard-capable quick launcher, not another
// document window. ESC dismisses it without touching the main manager.
final class QuickConnectWindow: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { orderOut(nil) }
}

// macOS 12-compatible status menu; the main WindowGroup remains in the Dock.
// Registration is explicit so both entries can never resolve to the wrong UI.
final class StatusBarDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var item: NSStatusItem?
    private var quickPanel: QuickConnectWindow?
    private var managerWindow: NSWindow?
    // A presentation request can arrive before SwiftUI mounts WindowGroup.
    // Defer it until the scene registers, never create a competing NSWindow.
    private var pendingManagerPresentation = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Keep the app a regular Dock app even though it also has a status item.
        NSApp.setActivationPolicy(.regular)
        let status = NSStatusBar.system.statusItem(withLength:NSStatusItem.squareLength)
        let artwork = Bundle.main.resourceURL?.appendingPathComponent("brand-mark.png")
        let icon = artwork.flatMap { NSImage(contentsOf:$0) } ??
                   NSImage(systemSymbolName:"terminal",accessibilityDescription:"Warp SSH")
        icon?.size = NSSize(width:19,height:19)
        icon?.isTemplate = true
        status.button?.image = icon
        status.button?.toolTip = "Warp SSH 管理器"
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title:"快速连接…",action:#selector(showQuickPanel),keyEquivalent:"k"))
        menu.addItem(NSMenuItem(title:"打开主机管理器",action:#selector(showMainWindow),keyEquivalent:""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title:"退出 Warp SSH 管理器",action:#selector(quitApp),keyEquivalent:"q"))
        for entry in menu.items { entry.target = self }
        item = status
        status.menu = menu

        // SwiftUI owns the initial manager window. Only discover/register
        // that scene: launching a second native NSWindow here races WindowGroup.
        DispatchQueue.main.asyncAfter(deadline:.now()+1.2) {
            if let window = self.findManagerWindow() {
                self.registerManagerWindow(window)
            }
        }

        // Only the isolated macOS CI GUI fixture enables this routing probe.
        // Test both menu actions and Dock reopening through the same methods
        // production uses, without clicking or modifying a user's data.
        if ProcessInfo.processInfo.environment["WSM_WINDOW_ROUTING_SMOKE_RESULT"] != nil {
            DispatchQueue.main.asyncAfter(deadline:.now()+3) {
                self.runWindowRoutingSmoke()
            }
        }
    }

    private func managerCandidates() -> [NSWindow] {
        NSApp.windows.filter {
            !($0 is NSPanel) && $0.level == .normal &&
            ($0.identifier?.rawValue == "wsm.native.configured" ||
                ($0.frame.width >= 900 && $0.frame.height >= 650))
        }
    }

    private func findManagerWindow() -> NSWindow? {
        if let registered = managerWindow,
           NSApp.windows.contains(where: { $0 === registered }) { return registered }
        if let named = NSApp.windows.first(where: {
            $0.identifier?.rawValue == "wsm.native.configured"
        }) { return named }
        // In the brief SwiftUI scene-mount interval the identifier has not
        // yet been applied. Screen-sized normal-level non-panel windows are
        // manager candidates, unlike our small floating QuickConnectWindow.
        return managerCandidates().first
    }

    func registerManagerWindow(_ window: NSWindow) {
        guard managerWindow !== window else { return }
        managerWindow = window
        // Closing the sole manager window hides it instead of destroying the
        // SwiftUI scene; clicking Dock or the tray can restore it reliably.
        window.isReleasedWhenClosed = false
        window.delegate = self
        if pendingManagerPresentation {
            pendingManagerPresentation = false
            DispatchQueue.main.async { [weak self] in self?.showMainWindow() }
        }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if sender === managerWindow {
            sender.orderOut(nil)
            return false
        }
        return true
    }

    func applicationShouldHandleReopen(_ sender: NSApplication,
                                       hasVisibleWindows flag: Bool) -> Bool {
        // Dock click must open the manager even when only the quick panel
        // is visible, or the user previously closed the main window.
        showMainWindow()
        // Essential: 'true' also allows AppKit/SwiftUI WindowGroup's default
        // reopen behavior, which creates a SECOND main window on Dock clicks.
        // The delegate has already fulfilled the request, so suppress it.
        return false
    }

    @objc func showMainWindow() {
        quickPanel?.orderOut(nil)
        NSApp.activate(ignoringOtherApps:true)
        if let main = findManagerWindow() {
            registerManagerWindow(main)
            main.deminiaturize(nil)
            main.makeKeyAndOrderFront(nil)
            return
        }
        // WindowGroup creates its sole window asynchronously on launch.
        // If called before ChromeView registration, show it once registered.
        // NEVER create an independent manager NSWindow beside WindowGroup.
        pendingManagerPresentation = true
    }

    @objc func showQuickPanel() {
        if let existing = quickPanel {
            // Rebuild the view on each opening so the host list is refreshed.
            existing.contentView = NSHostingView(rootView:
                QuickConnectPanel(onDismiss: { [weak self] in
                    self?.quickPanel?.orderOut(nil)
                }))
            NSApp.activate(ignoringOtherApps:true)
            existing.makeKeyAndOrderFront(nil)
            return
        }
        let panel = QuickConnectWindow(
            contentRect:NSRect(x:0,y:0,width:510,height:556),
            styleMask:[.borderless],
            backing:.buffered,defer:false)
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = true
        panel.isOpaque = false
        panel.hasShadow = true
        panel.backgroundColor = .clear
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.moveToActiveSpace,.transient]
        let host = NSHostingView(rootView:QuickConnectPanel(onDismiss: { [weak self] in
            self?.quickPanel?.orderOut(nil)
        }))
        host.wantsLayer = true
        host.layer?.cornerRadius = 17
        host.layer?.masksToBounds = true
        panel.contentView = host
        panel.center()
        quickPanel = panel
        NSApp.activate(ignoringOtherApps:true)
        panel.makeKeyAndOrderFront(nil)
    }

    private func runWindowRoutingSmoke() {
        guard let path = ProcessInfo.processInfo.environment["WSM_WINDOW_ROUTING_SMOKE_RESULT"] else {return}
        let mainBefore = findManagerWindow()
        let initialCount = managerCandidates().count
        showQuickPanel()
        let quickOpened = quickPanel?.isVisible == true && NSApp.keyWindow === quickPanel
        // Give the CI *shell* a chance to capture the real floating panel.
        // Screen Recording may be unavailable to the sandboxed GUI process,
        // while the runner shell has permission to call screencapture.
        if let ready = ProcessInfo.processInfo.environment["WSM_ROUTING_QUICK_READY"] {
            try? "ready\n".write(toFile:ready,atomically:true,encoding:.utf8)
        }
        DispatchQueue.main.asyncAfter(deadline:.now()+6) {
            self.showMainWindow()
            let menuOpenedMain = self.managerWindow?.isVisible == true
                                 && NSApp.keyWindow === self.managerWindow
                                 && self.quickPanel?.isVisible == false
            // Exercise the *real* close path rather than only orderOut().
            // The manager must be retained and hidden by windowShouldClose.
            self.managerWindow?.performClose(nil)
            let hiddenAfterClose = self.managerWindow?.isVisible == false
            var suppressesDefaultReopen = true
            var reopenedSingleWindow = true
            // Simulate repeated Dock reopen callbacks. No WindowGroup scene
            // should be created by AppKit's default reopen handler.
            for _ in 0..<3 {
                let result = self.applicationShouldHandleReopen(NSApp,hasVisibleWindows:false)
                suppressesDefaultReopen = suppressesDefaultReopen && !result
                reopenedSingleWindow = reopenedSingleWindow &&
                    self.managerCandidates().count == 1 &&
                    self.managerWindow?.isVisible == true &&
                    NSApp.keyWindow === self.managerWindow
            }
            let dockRestoredMain = self.managerWindow?.isVisible == true
                                   && NSApp.keyWindow === self.managerWindow
            let managerCount = self.managerCandidates().count
            let passed = mainBefore != nil && initialCount == 1 &&
                         quickOpened && menuOpenedMain && hiddenAfterClose &&
                         dockRestoredMain && suppressesDefaultReopen &&
                         reopenedSingleWindow && managerCount == 1
            let report = "quickPanel=\(quickOpened) managerMenu=\(menuOpenedMain) dockReopen=\(dockRestoredMain) initialManager=\(mainBefore != nil) initialCount=\(initialCount) managerCount=\(managerCount) closeHides=\(hiddenAfterClose) suppressDefaultReopen=\(suppressesDefaultReopen) repeatDockSingle=\(reopenedSingleWindow) PASS=\(passed)\n"
            try? report.write(toFile:path,atomically:true,encoding:.utf8)
            NSLog("WSM window routing audit: %@",report)
        }
    }

    @objc private func quitApp() {NSApp.terminate(nil)}
}

struct QuickConnectPanel: View {
    let onDismiss: () -> Void
    @StateObject private var store = ManagerStore()
    @State private var launched = false
    @State private var hoveredID: String?
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(alignment:.leading,spacing:0) {
            HStack(spacing:13) {
                Image(nsImage: Design.brandIcon)
                    .resizable().interpolation(.high)
                    .frame(width:47,height:47)
                    .clipShape(RoundedRectangle(cornerRadius:12))
                VStack(alignment:.leading,spacing:4) {
                    Text("快速连接")
                        .font(Design.font(22,.semibold))
                        .foregroundColor(Design.primary)
                    Text("选择主机，在 Warp 中打开 SSH")
                        .font(Design.font(13))
                        .foregroundColor(Design.secondary)
                }
                Spacer()
                if store.busy {ProgressView().controlSize(.small)}
                Button(action:onDismiss) {
                    Image(systemName:"xmark")
                        .font(.system(size:12,weight:.semibold))
                        .foregroundColor(Design.secondary)
                        .frame(width:29,height:29)
                }
                .buttonStyle(.plain)
                .help("关闭快速连接 (Esc)")
                .accessibilityLabel("关闭快速连接")
            }
            .padding(.top,24)
            .padding(.bottom,21)

            HStack(spacing:10) {
                Image(systemName:"magnifyingglass")
                    .font(.system(size:16))
                    .foregroundColor(Design.secondary)
                TextField("搜索主机、SSH 别名或 IP",text:$store.search)
                    .textFieldStyle(.plain)
                    .font(Design.font(15))
                    .focused($searchFocused)
                    .accessibilityLabel("搜索主机")
                if !store.search.isEmpty {
                    Button {
                        store.search = ""
                    } label: {
                        Image(systemName:"xmark.circle.fill")
                            .foregroundColor(Design.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("清除搜索")
                }
            }
            .padding(.horizontal,14)
            .frame(height:44)
            .background(.thinMaterial,in:RoundedRectangle(cornerRadius:11))
            .overlay(RoundedRectangle(cornerRadius:11).strokeBorder(Design.hairline))
            .padding(.bottom,14)

            ScrollView(.vertical,showsIndicators:false) {
                LazyVStack(spacing:8) {
                    ForEach(store.filtered) { host in
                        Button { store.connect(host) } label: {
                            HStack(spacing:12) {
                                TerminalIcon(name:host.name,tags:host.tagNames,size:43)
                                VStack(alignment:.leading,spacing:5) {
                                    Text(host.name)
                                        .font(Design.font(16,.semibold))
                                        .foregroundColor(Design.primary)
                                        .lineLimit(1)
                                    Text(host.hostname)
                                        .font(Design.font(13))
                                        .foregroundColor(Design.secondary)
                                        .lineLimit(1)
                                    if !host.tagNames.isEmpty {
                                        HStack(spacing:5) {
                                            ForEach(Array(host.tagNames.prefix(2)),id:\.self) { tag in
                                                TerminalBadge(tag:tag,scale:0.83)
                                            }
                                        }
                                    }
                                }
                                Spacer(minLength:4)
                                Image(systemName:host.favorite ? "star.fill" : "arrow.up.right")
                                    .font(.system(size:15,weight:.medium))
                                    .foregroundColor(host.favorite ? .orange : Design.secondary)
                                    .frame(width:23)
                            }
                            .padding(.horizontal,14)
                            .padding(.vertical,12)
                            .frame(maxWidth:.infinity,alignment:.leading)
                            .background(hoveredID == host.id
                                            ? Design.selectedSurface : Design.cardSurface,
                                        in:RoundedRectangle(cornerRadius:12))
                            .overlay(RoundedRectangle(cornerRadius:12)
                                .strokeBorder(hoveredID == host.id
                                    ? Design.blue.opacity(0.60) : Design.hairline,lineWidth:1))
                        }
                        .buttonStyle(.plain)
                        .disabled(store.busy)
                        .onHover { hovering in
                            if hovering { hoveredID = host.id }
                            else if hoveredID == host.id { hoveredID = nil }
                        }
                    }
                    if store.filtered.isEmpty {
                        VStack(spacing:10) {
                            Image(systemName:"magnifyingglass")
                                .font(.system(size:25))
                            Text(store.hosts.isEmpty ? "暂无主机" : "没有匹配的主机")
                                .font(Design.font(15,.medium))
                        }
                        .frame(maxWidth:.infinity)
                        .foregroundColor(Design.secondary)
                        .padding(.vertical,45)
                    }
                }
                .padding(.bottom,10)
                .background(NativeScrollbarCleaner())
            }
            .hideNativeScrollIndicators()
            .frame(maxWidth:.infinity,maxHeight:.infinity)

            if let message = store.errorMessage {
                Text(message)
                    .font(Design.font(12))
                    .foregroundColor(.red)
                    .lineLimit(3)
                    .padding(.vertical,7)
            }
            Rectangle().fill(Design.hairline).frame(height:1)
                .padding(.top,7)
            HStack {
                Text("单击主机即可在 Warp 中打开")
                    .font(Design.font(12))
                    .foregroundColor(Design.secondary)
                Spacer()
                Text("\(store.filtered.count) 台主机")
                    .font(Design.font(12,.medium))
                    .foregroundColor(Design.secondary)
            }
            .padding(.top,13)
            .padding(.bottom,18)
        }
        .padding(.horizontal,20)
        .frame(width:510,height:556)
        // Native popover blur and real wallpaper sampling, without a
        // screenshot or an artificial background gradient.
        .background {
            MacMaterial(material:.popover,blendingMode:.behindWindow)
        }
        .clipShape(RoundedRectangle(cornerRadius:17,style:.continuous))
        .onExitCommand(perform:onDismiss)
        .preferredColorScheme(store.appearance == "dark" ? .dark :
                              (store.appearance == "light" ? .light : nil))
        .onAppear {
            if !launched { launched = true; store.refresh() }
            DispatchQueue.main.async { searchFocused = true }
        }
    }
}
