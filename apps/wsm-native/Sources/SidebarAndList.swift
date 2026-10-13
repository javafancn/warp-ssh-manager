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
    // Use the same typography for all selectable rows. At narrower window
    // widths, reduce padding before shrinking navigation labels too much.
    // Leave the established 48pt-row hit targets on sidebarScale.
    private var navigationTextScale:CGFloat {
        max(0.96,min(1,paneWidth / 300.0))
    }
    private var navigationRowHeight:CGFloat {48 * sidebarScale}
    private var navigationFontSize:CGFloat {17.5 * navigationTextScale}
    private var navigationIconSize:CGFloat {19 * navigationTextScale}
    private var sectionHeaderFontSize:CGFloat {15 * navigationTextScale}
    @EnvironmentObject private var store: ManagerStore
    @State private var groupEditor: GroupEditorRequest?
    @State private var pendingDeleteGroup: GroupRecord?
    @State private var expandedGroupIDs: Set<String>=[]
    @State private var initializedExpansion=false
    @State private var showSettings = false
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
                Text("分组").font(Design.font(sectionHeaderFontSize,.medium)).foregroundColor(Design.secondary)
                Spacer()
                Button {presentNewGroup(parentID:nil)} label:{
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
                    groupBranch(parentID:nil,depth:0)
                    nav("未分组","folder",count:store.hosts.filter{$0.groupId == nil}.count,filter:.ungrouped)
                }
                // An explicit full-width content column is important inside
                // NSScrollView; otherwise the plain Button can shrink to its
                // label and leave the apparent row unclickable.
                .frame(maxWidth:.infinity,alignment:.leading)
                .padding(.horizontal,14 * sidebarScale)
                .background(NativeScrollbarCleaner())
            }
            .hideNativeScrollIndicators()
            Spacer(minLength:0)
            Rectangle().fill(Design.hairline).frame(height:1)
            HStack(spacing:10) {
                Button {presentNewGroup(parentID:nil)} label:{
                    Label("新建分组",systemImage:"plus")
                        .frame(maxWidth:.infinity,alignment:.leading)
                        .padding(.horizontal,12 * sidebarScale)
                        .frame(height:38 * sidebarScale)
                }
                .buttonStyle(SoftButtonStyle())
                Button {showSettings.toggle()} label:{
                    Image(systemName:"gearshape")
                        .font(.system(size:17 * sidebarScale))
                        .frame(width:38 * sidebarScale,height:38 * sidebarScale)
                }
                .buttonStyle(SoftButtonStyle())
                .help("更多选项")
                .popover(isPresented:$showSettings,arrowEdge:.top) {
                    VStack(alignment:.leading,spacing:13) {
                        Button {
                            showSettings=false;store.newHost()
                        } label: { Label("新建主机",systemImage:"plus") }
                        Button {
                            showSettings=false;store.refresh()
                        } label: { Label("刷新连接列表",systemImage:"arrow.clockwise") }
                        Divider()
                        Text("外观")
                            .font(Design.font(13,.medium))
                            .foregroundColor(Design.secondary)
                        Picker("外观",selection:$store.appearance) {
                            Text("自动").tag("auto")
                            Text("深色").tag("dark")
                            Text("浅色").tag("light")
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                    }
                    .buttonStyle(.plain)
                    .padding(16)
                    .frame(width:240)
                }
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
        .sheet(item:$groupEditor) { request in
            GroupEditorSheet(request:request,store:store) { name,parent in
                if let existing=request.existing {
                    store.updateGroup(existing,name:name,parentID:parent)
                } else {
                    store.addGroup(name,parentID:parent)
                }
            }
        }
        .alert("删除分组",isPresented:Binding(
            get:{pendingDeleteGroup != nil},
            set:{if !$0 {pendingDeleteGroup=nil}}
        )) {
            Button("取消",role:.cancel) {pendingDeleteGroup=nil}
            Button("删除",role:.destructive) {
                if let group=pendingDeleteGroup {
                    store.removeGroup(group.id)
                }
                pendingDeleteGroup=nil
            }
        } message: {
            Text("删除后，该分组中的主机将移至「未分组」。此操作不会删除主机或 SSH 配置。包含子分组的分组不可删除。")
        }
        .onAppear {initializeGroupExpansion()}
        .onChange(of:store.groups) { _ in initializeGroupExpansion() }
        .onChange(of:store.filter) { _ in revealSelectedGroup() }
    }
    private func presentNewGroup(parentID:String?) {
        groupEditor=GroupEditorRequest(existing:nil,parentID:parentID)
    }

    private func revealSelectedGroup() {
        if case .group(let id)=store.filter {
            expandedGroupIDs.formUnion(store.groupAncestors(of:id))
        }
    }

    private func initializeGroupExpansion() {
        if !initializedExpansion && !store.groups.isEmpty {
            expandedGroupIDs=Set(store.groups.map(\.id))
            initializedExpansion=true
        }
        revealSelectedGroup()
    }

    // Children are indented without introducing independent scroll views.
    // Any depth is supported; malformed parent IDs are displayed at the root.
    private func groupBranch(parentID:String?,depth:Int) -> AnyView {
        AnyView(ForEach(store.groupChildren(of:parentID)) { group in
            VStack(spacing:4 * sidebarScale) {
                groupNavigationRow(group,depth:depth)
                if expandedGroupIDs.contains(group.id) {
                    groupBranch(parentID:group.id,depth:depth+1)
                }
            }
            .frame(maxWidth:.infinity,alignment:.leading)
        })
    }

    private func groupNavigationRow(_ group:GroupRecord,depth:Int) -> some View {
        let selected=store.filter == .group(group.id)
        let hasChildren = !store.groupChildren(of:group.id).isEmpty
        return HStack(spacing:5 * sidebarScale) {
            if hasChildren {
                Button {
                    if expandedGroupIDs.contains(group.id) {
                        expandedGroupIDs.remove(group.id)
                    } else {
                        expandedGroupIDs.insert(group.id)
                    }
                } label: {
                    Image(systemName:expandedGroupIDs.contains(group.id)
                          ? "chevron.down" : "chevron.right")
                        .font(.system(size:10 * sidebarScale,weight:.semibold))
                        .frame(width:24 * sidebarScale,height:navigationRowHeight)
                        .foregroundColor(Design.secondary)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(expandedGroupIDs.contains(group.id) ? "折叠分组" : "展开分组")
            } else {
                Color.clear.frame(width:24 * sidebarScale,height:navigationRowHeight)
            }
            Button {
                store.filter = .group(group.id)
            } label: {
                HStack(spacing:8 * sidebarScale) {
                    Image(systemName:hasChildren ? "folder.fill" : "folder")
                        .font(.system(size:navigationIconSize))
                        .frame(width:22 * sidebarScale)
                    Text(group.name)
                        .font(Design.font(navigationFontSize,selected ? .semibold : .medium))
                        .lineLimit(1)
                    Spacer(minLength:2)
                    CountPill(count:store.groupHostCount(group.id),
                              highlighted:selected,scale:sidebarScale)
                }
                .foregroundColor(selected ? Design.blue : Design.primary)
                .padding(.horizontal,7 * sidebarScale)
                .frame(maxWidth:.infinity,alignment:.leading)
                .frame(height:navigationRowHeight)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(store.groupPath(group.id))
        }
        .padding(.leading,CGFloat(min(depth,8))*13 * sidebarScale + 5 * sidebarScale)
        .padding(.trailing,5 * sidebarScale)
        .frame(maxWidth:.infinity,alignment:.leading)
        .frame(height:navigationRowHeight)
        .background(selected ? Design.selectedSurface : Color.clear,
                    in:RoundedRectangle(cornerRadius:11))
        .contextMenu {
            Button {
                presentNewGroup(parentID:group.id)
                expandedGroupIDs.insert(group.id)
            } label: {Label("新建子分组",systemImage:"folder.badge.plus")}
            Button {
                groupEditor=GroupEditorRequest(existing:group,parentID:group.parentId)
            } label: {Label("重命名或移动",systemImage:"pencil")}
            Divider()
            Button(role:.destructive) {
                pendingDeleteGroup=group
            } label: {
                Label("删除分组",systemImage:"trash")
            }
            .disabled(hasChildren)
        }
    }

    @ViewBuilder
    private func nav(_ title:String,_ symbol:String,count:Int,filter:HostFilter)->some View {
        let selected = store.filter == filter
        Button {
            store.filter=filter
        } label: {
            HStack(spacing:13 * sidebarScale) {
                Image(systemName:symbol)
                    .font(.system(size:navigationIconSize,weight:.regular))
                    .frame(width:23 * sidebarScale)
                Text(title)
                    .font(Design.font(navigationFontSize,selected ? .semibold : .medium))
                    .lineLimit(1)
                Spacer(minLength:4)
                CountPill(count:count,highlighted:selected,scale:sidebarScale)
            }
            .foregroundColor(selected ? Design.blue : Design.primary)
            .padding(.horizontal,13 * sidebarScale)
            .frame(maxWidth:.infinity,alignment:.leading)
            .frame(height:navigationRowHeight)
            .background(selected ? Design.selectedSurface : Color.clear,
                        in:RoundedRectangle(cornerRadius:11))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .help(title)
    }
}

private struct GroupEditorRequest: Identifiable {
    let id=UUID().uuidString
    let existing:GroupRecord?
    let parentID:String?
}

private struct GroupEditorSheet: View {
    let request:GroupEditorRequest
    @ObservedObject var store:ManagerStore
    let onSubmit:(String,String?)->Void
    @Environment(\.dismiss) private var dismiss
    @State private var groupName:String
    @State private var parentID:String?
    @State private var showParentPicker=false
    @FocusState private var nameFocused:Bool

    init(request:GroupEditorRequest,store:ManagerStore,
         onSubmit:@escaping (String,String?)->Void) {
        self.request=request
        self.store=store
        self.onSubmit=onSubmit
        _groupName=State(initialValue:request.existing?.name ?? "")
        _parentID=State(initialValue:request.parentID)
    }

    private var isEditing:Bool { request.existing != nil }
    private var candidateName:String {
        groupName.trimmingCharacters(in:.whitespacesAndNewlines)
    }

    private var validation:String? {
        if candidateName.isEmpty {return "请输入分组名称"}
        if candidateName.count > 24 {return "分组名称不能超过 24 个字符"}
        if candidateName.unicodeScalars.contains(where:{$0.properties.generalCategory == .control}) {
            return "分组名称不能包含控制字符"
        }
        if store.groups.contains(where:{
            $0.id != request.existing?.id && $0.parentId == parentID &&
            $0.name.caseInsensitiveCompare(candidateName) == .orderedSame
        }) {return "该位置已存在同名分组"}
        return nil
    }

    private var availableParents:[GroupRecord] {
        let forbidden:Set<String>
        if let current=request.existing {
            forbidden=store.groupDescendants(of:current.id).union([current.id])
        } else {forbidden=[]}
        return store.groups.filter{!forbidden.contains($0.id)}
            .sorted {store.groupPath($0.id).localizedStandardCompare(store.groupPath($1.id)) == .orderedAscending}
    }

    private var selectedParentTitle:String {
        guard let parentID=parentID else {return "顶级分组"}
        return store.groupPath(parentID)
    }

    private var isNameInvalid:Bool {
        !candidateName.isEmpty && validation != nil
    }

    var body:some View {
        VStack(spacing:0) {
            VStack(alignment:.leading,spacing:22) {
                heading
                VStack(alignment:.leading,spacing:19) {
                    groupNameField
                    parentField
                }
                .padding(.top,2)
            }
            .padding(.horizontal,28)
            .padding(.top,27)
            .padding(.bottom,24)

            Rectangle().fill(Design.hairline.opacity(0.65))
                .frame(height:1)

            HStack(spacing:10) {
                Label("仅调整本地分组，不修改 SSH 配置",
                      systemImage:"checkmark.shield")
                    .font(Design.font(11.5))
                    .foregroundColor(Design.secondary)
                    .lineLimit(1)
                Spacer(minLength:10)
                Button {dismiss()} label:{
                    Text("取消")
                        .font(Design.font(13.5,.medium))
                        .foregroundColor(Design.primary)
                        .frame(width:85,height:38)
                        .background(Design.surface(0.23),
                                    in:RoundedRectangle(cornerRadius:9))
                        .overlay(RoundedRectangle(cornerRadius:9)
                                    .strokeBorder(Design.hairline,lineWidth:1))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)

                Button(action:submit) {
                    Text(isEditing ? "保存更改" : "创建分组")
                        .font(Design.font(13.5,.semibold))
                        .foregroundColor(.white)
                        .frame(width:98,height:38)
                        .background(Design.blue,
                                    in:RoundedRectangle(cornerRadius:9))
                }
                .buttonStyle(.plain)
                .disabled(validation != nil || store.busy)
                .opacity(validation != nil || store.busy ? 0.5 : 1)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal,28)
            .padding(.vertical,17)
            .background(Design.surface(0.08))
        }
        .frame(width:506)
        // Use one material for the entire dialog rather than a solid white
        // macOS sheet with another white form card on top of it.
        .background {
            MacMaterial(material:.sidebar,
                        blendingMode:.behindWindow,opacity:0.86)
        }
        .background(GroupEditorSheetWindowConfiguration())
        .onAppear {DispatchQueue.main.async {nameFocused=true}}
    }

    private var heading:some View {
        HStack(alignment:.center,spacing:14) {
            Image(systemName:isEditing ? "folder" : "folder.badge.plus")
                .font(.system(size:21,weight:.medium))
                .foregroundColor(Design.blue)
                .frame(width:50,height:50)
                .background(Design.blue.opacity(0.09),
                            in:RoundedRectangle(cornerRadius:14))
                .overlay(RoundedRectangle(cornerRadius:14)
                            .strokeBorder(Design.blue.opacity(0.11)))
            VStack(alignment:.leading,spacing:5) {
                Text(isEditing ? "编辑分组" : "新建分组")
                    .font(Design.font(21,.semibold))
                    .foregroundColor(Design.primary)
                Text(isEditing ? "调整分组名称或移动到其他位置"
                               : "创建分组，让服务器列表更有条理")
                    .font(Design.font(13))
                    .foregroundColor(Design.secondary)
            }
            Spacer(minLength:0)
        }
    }

    private var groupNameField:some View {
        VStack(alignment:.leading,spacing:9) {
            Text("分组名称")
                .font(Design.font(14,.medium))
                .foregroundColor(Design.primary)
            HStack(spacing:10) {
                Image(systemName:"folder")
                    .font(.system(size:14))
                    .foregroundColor(Design.secondary)
                TextField("例如：生产环境、业务系统",text:$groupName)
                    .font(Design.font(14.5))
                    .foregroundColor(Design.primary)
                    .textFieldStyle(.plain)
                    .focused($nameFocused)
                    .onSubmit(submit)
                    .accessibilityLabel("分组名称")
            }
            .padding(.horizontal,14)
            .frame(height:46)
            .background(Design.surface(0.35),
                        in:RoundedRectangle(cornerRadius:10))
            .overlay(RoundedRectangle(cornerRadius:10)
                        .strokeBorder(nameFocused ? Design.blue : Design.inputBorder,
                                      lineWidth:nameFocused ? 1.5 : 1))
            HStack {
                Text(isNameInvalid ? validation! : "同一上级分组下名称不可重复")
                    .foregroundColor(isNameInvalid ? .red : Design.secondary)
                Spacer()
                Text("\(candidateName.count)/24")
                    .foregroundColor(candidateName.count > 24 ? .red : Design.secondary)
                    .monospacedDigit()
            }
            .font(Design.font(11.5))
        }
    }

    private var parentField:some View {
        VStack(alignment:.leading,spacing:9) {
            HStack {
                Text("上级分组")
                    .font(Design.font(14,.medium))
                    .foregroundColor(Design.primary)
                Spacer()
                Text("可选")
                    .font(Design.font(11.5))
                    .foregroundColor(Design.secondary)
            }
            Button {showParentPicker.toggle()} label:{
                HStack(spacing:10) {
                    Image(systemName:parentID == nil ? "folder" : "folder.fill")
                        .font(.system(size:14))
                        .foregroundColor(parentID == nil ? Design.secondary : Design.blue)
                    Text(selectedParentTitle)
                        .font(Design.font(14.5))
                        .foregroundColor(Design.primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength:4)
                    Image(systemName:"chevron.up.chevron.down")
                        .font(.system(size:11,weight:.semibold))
                        .foregroundColor(Design.secondary)
                }
                .padding(.horizontal,14)
                .frame(height:46)
                .contentShape(RoundedRectangle(cornerRadius:10))
                .background(Design.surface(0.35),
                            in:RoundedRectangle(cornerRadius:10))
                .overlay(RoundedRectangle(cornerRadius:10)
                            .strokeBorder(showParentPicker ? Design.blue : Design.inputBorder,
                                          lineWidth:showParentPicker ? 1.5 : 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("选择上级分组")
            .popover(isPresented:$showParentPicker,arrowEdge:.bottom) {
                parentPicker
            }

            HStack(spacing:5) {
                Image(systemName:"arrow.turn.down.right")
                    .font(.system(size:10))
                Text(parentID == nil ? "创建在分组列表的顶层" :
                     (isEditing ? "当前分组及其子分组会一起移动" : "创建为所选分组的子分组"))
            }
            .font(Design.font(11.5))
            .foregroundColor(Design.secondary)
        }
    }

    private var parentPicker:some View {
        VStack(alignment:.leading,spacing:9) {
            Text("选择存放位置")
                .font(Design.font(13.5,.semibold))
                .foregroundColor(Design.primary)
                .padding(.horizontal,8)
            ScrollView(.vertical,showsIndicators:false) {
                VStack(spacing:3) {
                    parentChoice(id:nil,title:"顶级分组",path:"不属于任何上级分组")
                    ForEach(availableParents) { group in
                        parentChoice(id:group.id,title:group.name,
                                     path:store.groupPath(group.id))
                    }
                }
            }
            .frame(maxHeight:255)
        }
        .padding(12)
        .frame(width:335)
        .background(MacMaterial(material:.popover,
                                blendingMode:.behindWindow,opacity:0.92))
    }

    private func parentChoice(id:String?,title:String,path:String) -> some View {
        let selected=parentID == id
        return Button {
            parentID=id
            showParentPicker=false
        } label: {
            HStack(spacing:11) {
                Image(systemName:id == nil ? "folder" : "folder.fill")
                    .font(.system(size:14))
                    .foregroundColor(selected ? Design.blue : Design.secondary)
                    .frame(width:19)
                VStack(alignment:.leading,spacing:3) {
                    Text(title)
                        .font(Design.font(13.5,selected ? .semibold : .medium))
                        .foregroundColor(Design.primary)
                        .lineLimit(1)
                    Text(path)
                        .font(Design.font(11))
                        .foregroundColor(Design.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength:4)
                if selected {
                    Image(systemName:"checkmark")
                        .font(.system(size:12,weight:.semibold))
                        .foregroundColor(Design.blue)
                }
            }
            .padding(.horizontal,10)
            .frame(minHeight:48)
            .frame(maxWidth:.infinity,alignment:.leading)
            .background(selected ? Design.blue.opacity(0.09) : Color.clear,
                        in:RoundedRectangle(cornerRadius:9))
            .contentShape(RoundedRectangle(cornerRadius:9))
        }
        .buttonStyle(.plain)
    }

    private func submit() {
        guard validation == nil, !store.busy else {return}
        onSubmit(candidateName,parentID)
        dismiss()
    }
}

// Sheets have a solid AppKit default background even when SwiftUI draws a
// material behind its content. Clear only this sheet window, never the main UI.
private struct GroupEditorSheetWindowConfiguration: NSViewRepresentable {
    final class View: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            // The sheet's parent is set by AppKit during presentation,
            // which can happen one run loop after SwiftUI attaches this view.
            DispatchQueue.main.async { [weak self] in
                guard let window=self?.window,window.sheetParent != nil else {return}
                window.isOpaque=false
                window.backgroundColor = .clear
            }
        }
    }
    func makeNSView(context:Context)->View {View(frame:.zero)}
    func updateNSView(_ view:View,context:Context) {}
}

/// Stable tag colors: common environments keep meaningful hues, while
/// custom tags get a deterministic hue from their name (not list position).
/// Avoid Swift's randomized hashValue so colors survive app restarts.
enum TagBadgePalette {
    static func hue(for tag:String) -> Double {
        let name=tag.trimmingCharacters(in:.whitespacesAndNewlines).lowercased()
        switch name {
        case "production","prod","生产","生产环境": return 0.42 // green
        case "test","testing","测试","测试环境": return 0.09 // orange
        case "dev","development","开发","开发环境": return 0.76 // violet
        case "staging","stage","预发布": return 0.15 // amber
        case "api": return 0.58 // blue
        case "database","db","数据库": return 0.94 // rose
        case "ops","operations","运维": return 0.51 // teal
        case "jump","bastion","跳板机": return 0.48 // mint
        default:
            var hash: UInt64 = 14695981039346656037
            for byte in name.utf8 {
                hash = (hash ^ UInt64(byte)) &* 1099511628211
            }
            return Double(hash % 360) / 360.0
        }
    }
}

struct TerminalBadge: View {
    var tag: String
    var scale: CGFloat = 1
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let hue=TagBadgePalette.hue(for:tag)
        let isDark=colorScheme == .dark
        let fg=Color(hue:hue,saturation:isDark ? 0.43 : 0.78,
                     brightness:isDark ? 0.99 : 0.43)
        let bg=Color(hue:hue,saturation:isDark ? 0.38 : 0.25,
                     brightness:isDark ? 0.35 : 0.98)
        Text(tag)
            .font(Design.font(14 * scale,.medium))
            .foregroundColor(fg)
            .padding(.horizontal,9 * scale)
            .padding(.vertical,5 * scale)
            .background(bg,in:RoundedRectangle(cornerRadius:8 * scale))
            .fixedSize(horizontal:true,vertical:false)
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
    @State private var shownHostMenuID: String? = nil
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
            // Favorites remain available inside the actions popover.
            // Each row now has only one trailing ellipsis control.
            // macOS Menu's borderless style appends a disclosure chevron.
            // A plain ellipsis Button with a popover has only the three dots.
            Button {
                shownHostMenuID = shownHostMenuID == host.id ? nil : host.id
            } label: {
                Image(systemName:"ellipsis")
                    .font(.system(size:19 * cardScale,weight:.medium))
                    .foregroundColor(Design.secondary)
                    .frame(width:25 * cardScale,height:31 * cardScale)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("更多主机操作")
            .accessibilityLabel("更多主机操作")
            .popover(isPresented:Binding(
                get:{shownHostMenuID == host.id},
                set:{if !$0 && shownHostMenuID == host.id {shownHostMenuID = nil}}
            ),arrowEdge:.bottom) {
                VStack(alignment:.leading,spacing:12) {
                    Button {
                        shownHostMenuID=nil;store.connect(host)
                    } label: {
                        Label("在 Warp 中打开",systemImage:"arrow.up.right.square")
                    }
                    Button {
                        shownHostMenuID=nil;store.connectManual(host)
                    } label: {
                        Label("手动连接",systemImage:"terminal")
                    }
                    Divider()
                    Button {
                        shownHostMenuID=nil;store.copyPassword(.ssh,for:host)
                    } label: {
                        Label("复制 SSH 密码",systemImage:"doc.on.doc")
                    }
                    .disabled(!store.hasPassword(.ssh,for:host.id))
                    Button {
                        shownHostMenuID=nil;store.copyPassword(.sudo,for:host)
                    } label: {
                        Label("复制 sudo 密码",systemImage:"doc.on.doc")
                    }
                    .disabled(!store.hasPassword(.sudo,for:host.id) && !store.hasPassword(.ssh,for:host.id))
                    Divider()
                    Button {
                        shownHostMenuID=nil;store.toggleFavorite(host)
                    } label: {
                        Label(host.favorite ? "取消收藏" : "收藏",
                              systemImage:host.favorite ? "star.slash" : "star")
                    }
                }
                .font(Design.font(14))
                .buttonStyle(.plain)
                .padding(16)
                .frame(width:215,alignment:.leading)
            }
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
