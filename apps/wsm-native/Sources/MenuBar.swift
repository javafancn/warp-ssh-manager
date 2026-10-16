import SwiftUI
import AppKit
import Carbon

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
    private var quickHotKey: EventHotKeyRef?
    private var quickHotKeyHandler: EventHandlerRef?
    private let quickHotKeySignature: OSType = 0x57534D51 // WSMQ
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
        let quickItem = NSMenuItem(title:"快速打开…",action:#selector(showQuickPanel),
                                   keyEquivalent:"k")
        quickItem.keyEquivalentModifierMask = [.control,.option,.command]
        menu.addItem(quickItem)
        menu.addItem(NSMenuItem(title:"打开主机管理器",action:#selector(showMainWindow),keyEquivalent:""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title:"退出 Warp SSH 管理器",action:#selector(quitApp),keyEquivalent:"q"))
        for entry in menu.items { entry.target = self }
        item = status
        status.menu = menu
        refreshMenuLanguage()
        NotificationCenter.default.addObserver(self,selector:#selector(refreshMenuLanguage),
                                               name:AppLanguage.didChange,object:nil)
        registerQuickHotKey()

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

    // Carbon RegisterEventHotKey is a real, system-wide hotkey even when Warp
    // or another app is frontmost. Unlike a global event tap, it does not
    // request Accessibility or Input Monitoring permissions.
    // Ctrl+Option+Command+K is intentionally less common than Cmd+K/Spotlight.
    private func registerQuickHotKey() {
        var kind=EventTypeSpec(eventClass:OSType(kEventClassKeyboard),
                               eventKind:UInt32(kEventHotKeyPressed))
        let callback:EventHandlerUPP = { _, event, userData in
            guard let event=event,let userData=userData else {
                return OSStatus(eventNotHandledErr)
            }
            var identity=EventHotKeyID(signature:0,id:0)
            let result=GetEventParameter(event,EventParamName(kEventParamDirectObject),
                                         EventParamType(typeEventHotKeyID),nil,
                                         MemoryLayout<EventHotKeyID>.size,nil,&identity)
            guard result == noErr,identity.signature == 0x57534D51,identity.id == 1 else {
                return OSStatus(eventNotHandledErr)
            }
            let delegate=Unmanaged<StatusBarDelegate>.fromOpaque(userData).takeUnretainedValue()
            delegate.toggleQuickPanel()
            return noErr
        }
        let handlerStatus=InstallEventHandler(GetApplicationEventTarget(),callback,1,
                                              &kind,Unmanaged.passUnretained(self).toOpaque(),
                                              &quickHotKeyHandler)
        guard handlerStatus == noErr else {
            NSLog("WSM: failed to install global hotkey handler (%d)",handlerStatus)
            return
        }
        let identity=EventHotKeyID(signature:quickHotKeySignature,id:1)
        let status=RegisterEventHotKey(UInt32(kVK_ANSI_K),
                                       UInt32(cmdKey | optionKey | controlKey),
                                       identity,GetApplicationEventTarget(),0,&quickHotKey)
        if status != noErr {
            NSLog("WSM: Ctrl+Option+Command+K unavailable (%d); menu remains usable",status)
        }
    }

    @objc private func refreshMenuLanguage() {
        guard let entries=item?.menu?.items else {return}
        for entry in entries {
            switch entry.action {
            case #selector(showQuickPanel):
                entry.title=AppLanguage.text("快速打开…")
            case #selector(showMainWindow):
                entry.title=AppLanguage.text("打开主机管理器")
            case #selector(quitApp):
                entry.title=AppLanguage.text("退出 Warp SSH 管理器")
            default: break
            }
        }
    }

    func applicationWillTerminate(_ notification:Notification) {
        NotificationCenter.default.removeObserver(self)
        if let ref=quickHotKey {UnregisterEventHotKey(ref)}
        if let handler=quickHotKeyHandler {RemoveEventHandler(handler)}
    }

    private func toggleQuickPanel() {
        if quickPanel?.isVisible == true && NSApp.keyWindow === quickPanel {
            quickPanel?.orderOut(nil)
        } else {
            showQuickPanel()
        }
    }

    // Align to the visible desktop's upper center like Spotlight, not NSWindow.center()
    // (which is the vertical midpoint). Prefer the screen containing the pointer.
    private func positionQuickPanel(_ panel:QuickConnectWindow) {
        guard let screen=NSScreen.screens.first(where:{$0.frame.contains(NSEvent.mouseLocation)})
              ?? NSScreen.main ?? NSScreen.screens.first else {return}
        let visible=screen.visibleFrame
        let topInset=max(55,min(125,visible.height * 0.14))
        let x=visible.midX-panel.frame.width/2
        let y=max(visible.minY+12,visible.maxY-topInset-panel.frame.height)
        panel.setFrameOrigin(NSPoint(x:x,y:y))
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
            positionQuickPanel(existing)
            NSApp.activate(ignoringOtherApps:true)
            existing.makeKeyAndOrderFront(nil)
            return
        }
        let panel = QuickConnectWindow(
            contentRect:NSRect(x:0,y:0,width:650,height:536),
            styleMask:[.borderless],
            backing:.buffered,defer:false)
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = true
        panel.isOpaque = false
        panel.hasShadow = true
        panel.backgroundColor = .clear
        panel.isMovableByWindowBackground = false
        // Support invoking the launcher over fullscreen apps / different Spaces.
        panel.collectionBehavior = [.canJoinAllSpaces,.fullScreenAuxiliary,.transient]
        let host = NSHostingView(rootView:QuickConnectPanel(onDismiss: { [weak self] in
            self?.quickPanel?.orderOut(nil)
        }))
        host.wantsLayer = true
        host.layer?.cornerRadius = 21
        host.layer?.masksToBounds = true
        panel.contentView = host
        positionQuickPanel(panel)
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
    @State private var selectedIndex = 0
    @State private var hoveredID: String?
    @State private var monitor: Any?
    @FocusState private var searchFocused: Bool

    // With no query, prioritize actual recent sessions; if no host has yet been
    // connected, display the available hosts rather than an empty launcher.
    private var results: [HostRecord] {
        let query=store.search.trimmingCharacters(in:.whitespacesAndNewlines)
        if !query.isEmpty {
            return store.hosts.filter { host in
                [host.name,host.alias,host.hostname,host.tags,
                 host.groupId.map { store.groupPath($0) } ?? ""]
                    .contains(where:{ $0.localizedCaseInsensitiveContains(query) })
            }.sorted { a,b in
                if a.lastConnected != b.lastConnected {
                    return (a.lastConnected ?? 0) > (b.lastConnected ?? 0)
                }
                return a.name.localizedStandardCompare(b.name) == .orderedAscending
            }
        }
        return store.hosts.sorted { a,b in
            if a.lastConnected != b.lastConnected {
                return (a.lastConnected ?? 0) > (b.lastConnected ?? 0)
            }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
    }

    private var displayHeading: String {
        if !store.search.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty {
            return "搜索结果"
        }
        return store.hosts.contains(where:{ $0.lastConnected != nil }) ? "最近使用" : "全部主机"
    }

    var body: some View {
        VStack(alignment:.leading,spacing:0) {
            searchBar
                .padding(.horizontal,19)
                .padding(.top,18)
                .padding(.bottom,17)

            HStack {
                Text(LocalizedStringKey(displayHeading))
                    .font(Design.font(12.5,.medium))
                    .foregroundColor(Design.secondary)
                Spacer()
                if store.busy { ProgressView().controlSize(.small) }
            }
            .padding(.horizontal,30)
            .padding(.bottom,8)

            ScrollViewReader { proxy in
                ScrollView(.vertical,showsIndicators:false) {
                    LazyVStack(spacing:0) {
                        ForEach(Array(results.enumerated()),id:\.element.id) { index,host in
                            resultRow(host,index:index)
                                .id(host.id)
                            if index < results.count-1 {
                                Rectangle().fill(Design.hairline.opacity(0.58))
                                    .frame(height:1)
                                    .padding(.leading,77)
                                    .padding(.trailing,15)
                            }
                        }
                        if results.isEmpty {
                            VStack(spacing:9) {
                                Image(systemName:"magnifyingglass")
                                    .font(.system(size:23))
                                Text(LocalizedStringKey(store.hosts.isEmpty ? "还没有主机，请先在管理器中添加" :
                                     "没有匹配的主机"))
                                    .font(Design.font(14))
                            }
                            .foregroundColor(Design.secondary)
                            .frame(maxWidth:.infinity)
                            .padding(.top,65)
                        }
                    }
                    .padding(.horizontal,18)
                    .background(NativeScrollbarCleaner())
                }
                .hideNativeScrollIndicators()
                .onChange(of:selectedIndex) { next in
                    guard next >= 0,next < results.count else {return}
                    withAnimation(.easeOut(duration:0.10)) {
                        proxy.scrollTo(results[next].id,anchor:.center)
                    }
                }
            }
            .frame(maxWidth:.infinity,maxHeight:.infinity)

            if let error = store.errorMessage {
                Text(error).foregroundColor(.red)
                    .font(Design.font(11.5))
                    .lineLimit(2)
                    .padding(.horizontal,26)
                    .padding(.bottom,5)
            }

            Rectangle().fill(Design.hairline.opacity(0.65)).frame(height:1)
                .padding(.horizontal,19)

            HStack(spacing:10) {
                Text("↵")
                    .font(.system(size:14,weight:.semibold,design:.rounded))
                    .foregroundColor(Design.secondary)
                Text("打开连接")
                    .font(Design.font(12.5))
                    .foregroundColor(Design.secondary)
                Spacer()
                shortcutHint("↑")
                shortcutHint("↓")
                Text("选择")
                    .font(Design.font(12.5))
                    .foregroundColor(Design.secondary)
                Text("·")
                    .foregroundColor(Design.secondary)
                Text("Esc 关闭")
                    .font(Design.font(12.5))
                    .foregroundColor(Design.secondary)
            }
            .padding(.horizontal,27)
            .frame(height:48)
        }
        .frame(width:650,height:536)
        .background {
            MacMaterial(material:.popover,blendingMode:.behindWindow,opacity:0.96)
        }
        .clipShape(RoundedRectangle(cornerRadius:21,style:.continuous))
        .overlay(RoundedRectangle(cornerRadius:21,style:.continuous)
            .strokeBorder(Design.surface(0.38),lineWidth:1))
        .onExitCommand(perform:onDismiss)
        .environment(\.locale,AppLanguage.locale(store.language))
        .preferredColorScheme(store.appearance == "dark" ? .dark :
                              (store.appearance == "light" ? .light : nil))
        .onChange(of:store.search) { _ in selectedIndex=0 }
        .onAppear {
            store.refresh()
            installKeyboardMonitor()
            DispatchQueue.main.async {searchFocused=true}
        }
        .onDisappear {
            if let monitor=monitor {NSEvent.removeMonitor(monitor)}
            monitor=nil
        }
    }

    private var searchBar: some View {
        HStack(spacing:12) {
            Image(systemName:"magnifyingglass")
                .font(.system(size:21,weight:.regular))
                .foregroundColor(Design.secondary)
            TextField("搜索主机、SSH 别名或 IP",text:$store.search)
                .font(Design.font(20))
                .textFieldStyle(.plain)
                .focused($searchFocused)
                .accessibilityLabel("搜索主机、SSH 别名或 IP")
            if !store.search.isEmpty {
                Button {
                    store.search=""
                    selectedIndex=0
                } label: {
                    Image(systemName:"xmark.circle.fill")
                        .foregroundColor(Design.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("清除搜索")
            }
            Image(nsImage:Design.brandIcon)
                .resizable()
                .interpolation(.high)
                .frame(width:27,height:27)
                .clipShape(RoundedRectangle(cornerRadius:7))
                .padding(.leading,3)
            Text("⌃⌥⌘ K")
                .font(.system(size:12.5,weight:.medium,design:.rounded))
                .foregroundColor(Design.secondary)
                .padding(.horizontal,8)
                .frame(height:27)
                .background(Design.surface(0.23),
                            in:RoundedRectangle(cornerRadius:6))
                .overlay(RoundedRectangle(cornerRadius:6)
                    .strokeBorder(Design.hairline.opacity(0.7),lineWidth:1))
        }
        .padding(.horizontal,19)
        .frame(height:61)
        .background(Design.surface(0.27),
                    in:RoundedRectangle(cornerRadius:15))
        .overlay(RoundedRectangle(cornerRadius:15)
            .strokeBorder(Design.hairline.opacity(0.5),lineWidth:1))
    }

    private func resultRow(_ host:HostRecord,index:Int) -> some View {
        let isSelected=selectedIndex==index
        let isHovered=hoveredID==host.id
        return Button {
            open(host)
        } label: {
            HStack(spacing:15) {
                TerminalIcon(name:host.name,tags:host.tagNames,size:42)
                VStack(alignment:.leading,spacing:4) {
                    Text(host.name)
                        .font(Design.font(15.5,.semibold))
                        .foregroundColor(Design.primary)
                        .lineLimit(1)
                    HStack(spacing:9) {
                        Text(host.hostname)
                            .font(Design.font(13))
                            .foregroundColor(Design.secondary)
                            .lineLimit(1)
                        ForEach(Array(host.tagNames.prefix(2)),id:\.self) { tag in
                            TerminalBadge(tag:tag,scale:0.78)
                        }
                    }
                }
                Spacer(minLength:5)
                Image(systemName:"arrow.up.right")
                    .font(.system(size:16,weight:.medium))
                    .foregroundColor(Design.secondary)
                    .frame(width:22)
            }
            .padding(.horizontal,14)
            .frame(height:65)
            .frame(maxWidth:.infinity,alignment:.leading)
            .background(isSelected ? Design.blue.opacity(0.10) :
                (isHovered ? Design.surface(0.22) : Color.clear),
                in:RoundedRectangle(cornerRadius:11))
            .overlay(RoundedRectangle(cornerRadius:11)
                .strokeBorder(isSelected ? Design.blue.opacity(0.25) : Color.clear))
            .contentShape(RoundedRectangle(cornerRadius:11))
        }
        .buttonStyle(.plain)
        .disabled(store.busy)
        .onHover { hovering in
            hoveredID=hovering ? host.id : (hoveredID==host.id ? nil : hoveredID)
        }
        .help("在 Warp 中打开 \(host.alias)")
    }

    private func shortcutHint(_ value:String) -> some View {
        Text(value)
            .font(.system(size:12,weight:.medium,design:.rounded))
            .foregroundColor(Design.secondary)
            .frame(width:22,height:22)
            .background(Design.surface(0.20),
                        in:RoundedRectangle(cornerRadius:5))
            .overlay(RoundedRectangle(cornerRadius:5)
                .strokeBorder(Design.hairline.opacity(0.60)))
    }

    private func open(_ host:HostRecord) {
        guard !store.busy else {return}
        store.connect(host)
        onDismiss()
    }

    // The search TextField normally consumes arrow/Return keyDown events;
    // a window-scoped local monitor keeps navigation responsive while typing.
    // This is NOT a global keyboard event tap and does not affect Warp.
    private func installKeyboardMonitor() {
        guard monitor == nil else {return}
        monitor=NSEvent.addLocalMonitorForEvents(matching:.keyDown) { event in
            guard event.window is QuickConnectWindow else {return event}
            // Leave IME composition to the native text input client.
            if let input=event.window?.firstResponder as? NSTextView,
               input.hasMarkedText() {return event}
            switch event.keyCode {
            case 125: // down
                if !results.isEmpty {selectedIndex=min(selectedIndex+1,results.count-1)}
                return nil
            case 126: // up
                if !results.isEmpty {selectedIndex=max(0,selectedIndex-1)}
                return nil
            case 36,76: // Return / keypad Enter
                if results.indices.contains(selectedIndex) {open(results[selectedIndex])}
                return nil
            case 53: // Escape
                onDismiss()
                return nil
            default:
                return event
            }
        }
    }
}
