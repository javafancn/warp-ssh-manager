import SwiftUI
import AppKit

struct CountPill: View {
    var count: Int
    var highlighted = false
    var scale: CGFloat = 1
    var body: some View {
        Text(String(count))
            .font(Design.font(14 * scale,.medium))
            .foregroundColor(highlighted ? Design.blue : Design.secondary)
            .padding(.horizontal,9 * scale).padding(.vertical,5 * scale)
            .background(highlighted ? Color.white.opacity(0.50) :
                        Color(red:0.83,green:0.87,blue:0.94).opacity(0.52),in:Capsule())
    }
}
struct ManagerSidebar: View {
    var paneWidth: CGFloat
    private var sidebarScale: CGFloat {
        max(0.85, min(1, paneWidth / 300.0))
    }
    @EnvironmentObject private var store: ManagerStore
    @State private var showAddGroup = false
    @State private var newGroupName = ""
    var body: some View {
        VStack(alignment:.leading,spacing:0) {
            HStack(spacing:13 * sidebarScale) {
                Image(nsImage: Design.brandIcon)
                    .resizable().interpolation(.high)
                    .frame(width:54 * sidebarScale,height:54 * sidebarScale)
                    .clipShape(RoundedRectangle(cornerRadius:13 * sidebarScale))
                VStack(alignment:.leading,spacing:5 * sidebarScale) {
                    Text("Warp SSH 管理器")
                        .font(Design.font(20 * sidebarScale,.semibold))
                        .foregroundColor(Design.primary)
                        .lineLimit(1)
                    Text("高效管理 · 快速连接")
                        .font(Design.font(13.5 * sidebarScale))
                        .foregroundColor(Design.secondary)
                }
            }
            .padding(.leading,20 * sidebarScale)
            .padding(.trailing,12 * sidebarScale)
            .padding(.top,72 * sidebarScale)
            .padding(.bottom,23 * sidebarScale)

            VStack(spacing:4 * sidebarScale) {
                nav("全部主机","server.rack",count:store.hosts.count,filter:.all)
                nav("收藏","star",count:store.favoriteCount,filter:.favorites)
                nav("最近连接","clock",count:store.recentCount,filter:.recent)
            }
            .padding(.horizontal,14 * sidebarScale)

            HStack {
                Text("分组").font(Design.font(16 * sidebarScale,.medium)).foregroundColor(Design.secondary)
                Spacer()
                Button {showAddGroup=true} label:{
                    Image(systemName:"plus").font(.system(size:17 * sidebarScale,weight:.regular))
                }
                .buttonStyle(.plain)
                .foregroundColor(Design.primary)
                .accessibilityLabel("新建分组")
            }
            .padding(.horizontal,25 * sidebarScale)
            .padding(.top,35 * sidebarScale)
            .padding(.bottom,13 * sidebarScale)

            ScrollView(.vertical,showsIndicators:false) {
                VStack(spacing:4 * sidebarScale) {
                    ForEach(store.groups) { group in
                        nav(group.name,"folder",count:store.hosts.filter{$0.groupId == group.id}.count,
                            filter:.group(group.id))
                        .contextMenu {
                            Button("删除分组",role:.destructive) { store.removeGroup(group.id) }
                        }
                    }
                    nav("未分组","folder",count:store.hosts.filter{$0.groupId == nil}.count,filter:.ungrouped)
                }
                .padding(.horizontal,14 * sidebarScale)
                .background(NativeScrollbarCleaner())
            }
            .hideNativeScrollIndicators()
            Spacer(minLength:0)
            Rectangle().fill(Design.hairline).frame(height:1)
            HStack(spacing:10) {
                Button {showAddGroup=true} label:{
                    Label("新建分组",systemImage:"plus")
                        .frame(maxWidth:.infinity,alignment:.leading)
                        .padding(.horizontal,12 * sidebarScale)
                        .frame(height:38 * sidebarScale)
                }
                .buttonStyle(SoftButtonStyle())
                Button {store.refresh()} label:{
                    Image(systemName:"gearshape")
                        .font(.system(size:17 * sidebarScale))
                        .frame(width:38 * sidebarScale,height:38 * sidebarScale)
                }
                .buttonStyle(SoftButtonStyle())
                .help("刷新连接列表")
            }
            .font(Design.font(15 * sidebarScale))
            .padding(.horizontal,18 * sidebarScale)
            .padding(.vertical,14 * sidebarScale)
        }
        .background {
            // Extend the actual sidebar material behind the native traffic
            // lights, so there is no separate white strip above the sidebar.
            // The sidebar must sample the wallpaper, not a fixed silver RGB.
            MacMaterial(material:.sidebar,
                        blendingMode:.behindWindow,opacity:0.75)
                .ignoresSafeArea(.container,edges:.top)
        }
        .alert("新建分组",isPresented:$showAddGroup) {
            TextField("分组名称",text:$newGroupName)
            Button("取消",role:.cancel) {newGroupName=""}
            Button("创建") {store.addGroup(newGroupName);newGroupName=""}
        } message: {
            Text("分组不会修改已有的 SSH 配置文件。")
        }
    }
    @ViewBuilder
    private func nav(_ title:String,_ symbol:String,count:Int,filter:HostFilter)->some View {
        let selected = store.filter == filter
        Button {
            store.filter=filter
        } label: {
            HStack(spacing:13 * sidebarScale) {
                Image(systemName:symbol).font(.system(size:19 * sidebarScale,weight:.regular))
                    .frame(width:23 * sidebarScale)
                Text(title).font(Design.font(17 * sidebarScale,selected ? .semibold : .medium))
                    .lineLimit(1)
                Spacer(minLength:4)
                CountPill(count:count,highlighted:selected,scale:sidebarScale)
            }
            .foregroundColor(selected ? Design.blue : Design.primary)
            .padding(.horizontal,13 * sidebarScale)
            .frame(height:50 * sidebarScale)
            .background(selected ? Design.selectedSurface : .clear,
                        in:RoundedRectangle(cornerRadius:11))
        }
        .buttonStyle(.plain)
    }
}

struct TerminalBadge: View {
    var tag: String
    var scale: CGFloat = 1
    var body: some View {
        let lower = tag.lowercased()
        let isAPI = lower == "api"
        let isProd = lower.contains("production") || lower == "prod"
        let isDev = lower == "dev"
        let isDB = lower.contains("database")
        let fg: Color = isAPI ? Color(red:0.05,green:0.39,blue:0.95) :
            isProd ? Color(red:0.02,green:0.46,blue:0.30) :
            isDev ? Color(red:0.35,green:0.22,blue:0.90) :
            isDB ? .red : Color(red:0.65,green:0.34,blue:0.05)
        let bg: Color = isAPI ? Color(red:0.84,green:0.92,blue:1) :
            isProd ? Color(red:0.77,green:0.96,blue:0.88) :
            isDev ? Color(red:0.90,green:0.86,blue:1) :
            isDB ? Color(red:1,green:0.87,blue:0.91) :
            Color(red:1,green:0.91,blue:0.80)
        Text(tag).font(Design.font(14 * scale))
            .foregroundColor(fg)
            .padding(.horizontal,9 * scale).padding(.vertical,5 * scale)
            .background(bg,in:RoundedRectangle(cornerRadius:8))
    }
}
struct TerminalIcon: View {
    var name: String
    var tags: [String] = []
    var size: CGFloat = 54
    var body: some View {
        let lower = name.lowercased()
        let labels = tags.map { $0.lowercased() }
        let isDB = lower.contains("db") || labels.contains("database")
        let isDev = lower.contains("dev") || labels.contains("dev")
        let isJump = lower.contains("jump") || labels.contains("jump")
        let isTest = labels.contains("test")
        // Untagged hosts get deterministic *decorative* icon shades rather
        // than the same flat navy square. This does not infer environment,
        // connection status, or add any invented server tags.
        let shade = name.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) % 4 }
        let defaultPalette: [[Color]] = [
            [Color(red:0.20,green:0.42,blue:0.62),Color(red:0.09,green:0.19,blue:0.32)],
            [Color(red:0.18,green:0.44,blue:0.50),Color(red:0.09,green:0.23,blue:0.31)],
            [Color(red:0.30,green:0.35,blue:0.63),Color(red:0.13,green:0.16,blue:0.36)],
            [Color(red:0.24,green:0.38,blue:0.56),Color(red:0.10,green:0.19,blue:0.30)]
        ]
        let colors: [Color] = isDB ?
            [Color(red:0.43,green:0.22,blue:0.29),Color(red:0.12,green:0.12,blue:0.19)] :
            isDev ? [Color(red:0.38,green:0.29,blue:0.61),Color(red:0.14,green:0.12,blue:0.28)] :
            isJump ? [Color(red:0.17,green:0.43,blue:0.36),Color(red:0.07,green:0.17,blue:0.18)] :
            isTest ? [Color(red:0.30,green:0.40,blue:0.61),Color(red:0.11,green:0.17,blue:0.29)] :
            defaultPalette[shade]
        let outline: Color = isDB ? .red.opacity(0.85) :
            isJump ? .green.opacity(0.85) :
            isDev ? .purple.opacity(0.72) :
            isTest ? .orange.opacity(0.75) :
            Color(red:0.20,green:0.51,blue:0.90).opacity(0.72)
        RoundedRectangle(cornerRadius:12,style:.continuous)
            .fill(LinearGradient(colors:colors,
                startPoint:.topLeading,endPoint:.bottomTrailing))
            .overlay(RoundedRectangle(cornerRadius:12).strokeBorder(outline,lineWidth:1))
            .overlay(Text(">_").font(.system(size:18 * size / 54,weight:.bold,design:.monospaced))
                .foregroundColor(.white))
            .shadow(color:.black.opacity(0.12),radius:3,y:2)
            .frame(width:size,height:size)
    }
}
struct ConnectionList: View {
    // Match the prototype's tile density across different pane widths.
    var listWidth: CGFloat
    private var cardScale: CGFloat { max(0.82, min(1.0, listWidth / 538.0)) }
    @EnvironmentObject private var store: ManagerStore
    @State private var showFilters = false
    var body: some View {
        VStack(spacing:0) {
            HStack(spacing:10 * cardScale) {
                HStack(spacing:9 * cardScale) {
                    Image(systemName:"magnifyingglass")
                        .font(.system(size:17 * cardScale)).foregroundColor(Design.secondary)
                    TextField("搜索名称、IP、标签或分组…",text:$store.search)
                        .font(Design.font(16 * max(0.9,cardScale)))
                        .textFieldStyle(.plain)
                        .accessibilityLabel("搜索主机")
                }
                .padding(.horizontal,14 * cardScale)
                .frame(height:46 * cardScale)
                .background(.thinMaterial,in:RoundedRectangle(cornerRadius:11))
                .overlay(RoundedRectangle(cornerRadius:11).strokeBorder(Design.hairline))
                // A borderless macOS Menu has an implicit 200px minimum width
                // and steals space from the search field. A compact popover
                // keeps the design's fixed 43px filter control.
                Button {showFilters.toggle()} label: {
                    Image(systemName:"slider.horizontal.3")
                        .font(.system(size:18 * cardScale))
                        .frame(width:46 * cardScale,height:46 * cardScale)
                        .foregroundColor(Design.primary)
                }
                .buttonStyle(.plain)
                .background(.thinMaterial,in:RoundedRectangle(cornerRadius:10))
                .overlay(RoundedRectangle(cornerRadius:10).strokeBorder(Design.hairline))
                .popover(isPresented:$showFilters,arrowEdge:.bottom) {
                    VStack(alignment:.leading,spacing:8) {
                        filterChoice("全部主机",filter:.all)
                        filterChoice("收藏",filter:.favorites)
                        filterChoice("最近连接",filter:.recent)
                        Divider()
                        Button("刷新") {showFilters=false;store.refresh()}
                        Button("导入 SSH 配置") {showFilters=false;store.act(["import"])}
                    }
                    .font(Design.font(14))
                    .padding(15)
                    .frame(width:190,alignment:.leading)
                }
            }
            .padding(.horizontal,20 * cardScale)
            .padding(.top,16 * cardScale)
            .padding(.bottom,14 * cardScale)
            ScrollView(.vertical,showsIndicators:false) {
                LazyVStack(spacing:11 * cardScale) {
                    ForEach(store.filtered) { host in
                        hostRow(host)
                    }
                    if store.filtered.isEmpty {
                        VStack(spacing:9) {
                            Image(systemName:"terminal").font(.system(size:30))
                            Text(store.hosts.isEmpty ? "暂无主机" : "没有匹配的主机")
                                .font(Design.font(16,.medium))
                            Text(store.hosts.isEmpty ? "点击右上角新建主机，或导入已有 OpenSSH 配置。" : "试试其他搜索条件")
                                .font(Design.font(13))
                                .multilineTextAlignment(.center)
                        }
                        .foregroundColor(Design.secondary)
                        .padding(30)
                    }
                }
                .padding(.horizontal,20 * cardScale)
                .padding(.bottom,24 * cardScale)
                .frame(maxWidth:.infinity)
                .background(NativeScrollbarCleaner())
            }
            .hideNativeScrollIndicators()
        }
        // Window-wide native glass is provided by ManagerShell.
        // Do not stack another opaque NSVisualEffectView behind host cards.
    }
    private func filterChoice(_ title:String,filter:HostFilter)->some View {
        Button {
            store.filter=filter
            showFilters=false
        } label: {
            HStack(spacing:10) {
                Text(title)
                Spacer()
                if store.filter==filter {Image(systemName:"checkmark").foregroundColor(Design.blue)}
            }
        }
        .buttonStyle(.plain)
        .frame(maxWidth:.infinity,alignment:.leading)
    }
    private func hostRow(_ host:HostRecord)->some View {
        let active = store.selectedID == host.id && !store.isNew
        return HStack(alignment:.center,spacing:16 * cardScale) {
            TerminalIcon(name:host.name,tags:host.tagNames,size:54 * cardScale)
            VStack(alignment:.leading,spacing:6 * cardScale) {
                Text(host.name)
                    .font(Design.font(20 * cardScale,.semibold))
                    .foregroundColor(Design.primary)
                    .lineLimit(1)
                Text(host.hostname)
                    .font(Design.font(16 * cardScale))
                    .foregroundColor(Design.secondary)
                    .lineLimit(1)
                HStack(spacing:6 * cardScale) {
                    ForEach(Array(host.tagNames.prefix(2)),id:\.self) { tag in
                        TerminalBadge(tag:tag,scale:cardScale)
                    }
                    if host.tagNames.isEmpty,let group=store.groups.first(where:{$0.id==host.groupId}) {
                        TerminalBadge(tag:group.name,scale:cardScale)
                    }
                }
            }
            Spacer(minLength:0)
            Button {store.toggleFavorite(host)} label: {
                Image(systemName:host.favorite ? "star.fill" : "star")
                    .font(.system(size:19 * cardScale))
                    .foregroundColor(host.favorite ? .orange : Design.secondary)
            }.buttonStyle(.plain).help("收藏")
            Menu {
                Button("在 Warp 中打开"){store.connect(host)}
                Button(host.favorite ? "取消收藏" : "收藏"){store.toggleFavorite(host)}
            } label: {
                Image(systemName:"ellipsis")
                    .font(.system(size:19 * cardScale,weight:.medium))
                    .foregroundColor(Design.secondary)
            }.menuStyle(.borderlessButton).frame(width:24 * cardScale)
        }
        .padding(.horizontal,17 * cardScale)
        .frame(minHeight:125 * cardScale)
        .background(active ? Design.selectedSurface : Design.cardSurface,
                    in:RoundedRectangle(cornerRadius:13,style:.continuous))
        .overlay(RoundedRectangle(cornerRadius:13)
            .strokeBorder(active ? Design.blue : Design.hairline,lineWidth:active ? 1.5:1))
        .shadow(color:.black.opacity(active ? 0.068 : 0.044),radius:active ? 8:5,y:2)
        .contentShape(RoundedRectangle(cornerRadius:13))
        // Competing 1-click and 2-click SwiftUI recognizers defer the single
        // click while waiting for a potential double click. Handle the initial
        // click immediately and inspect the AppKit mouse click count instead.
        .onTapGesture {
            if NSApp.currentEvent?.clickCount == 2 {
                store.connect(host)
            } else {
                store.select(host)
            }
        }
    }
}
