import SwiftUI
import AppKit

struct HostInspector: View {
    var paneWidth: CGFloat
    private var scale: CGFloat { max(0.79, min(1, paneWidth / 555)) }
    private var textScale: CGFloat { max(0.90, scale) }
    @EnvironmentObject private var store: ManagerStore
    @State private var confirmDelete = false
    @State private var editingTags = false
    @State private var newTag = ""
    @State private var showGroupPicker = false
    @State private var showMoreOptions = false
    @State private var showConnectActions = false

    var body: some View {
        VStack(spacing:0) {
            if store.selectedID != nil || store.isNew {
                inspectorHeader
                tabBar
                Rectangle().fill(Design.hairline).frame(height:1)
                ScrollView(.vertical,showsIndicators:false) {
                    VStack(alignment:.leading,spacing:12 * scale) {
                        switch store.tab {
                        case .basic: basicFields
                        case .connection: connectionFields
                        case .tags: metadataFields
                        case .advanced: advancedFields
                        }
                    }
                    .padding(.horizontal,28 * scale)
                    .padding(.top,25 * scale)
                    .padding(.bottom,22 * scale)
                    .background(NativeScrollbarCleaner())
                }
                .frame(maxWidth:.infinity,maxHeight:.infinity)
                .hideNativeScrollIndicators()
                footer
            } else {
                VStack(spacing:16) {
                    Spacer()
                    Image(systemName:"terminal")
                        .font(.system(size:46,weight:.ultraLight))
                        .foregroundColor(Design.blue.opacity(0.62))
                    Text("选择一台主机")
                        .font(Design.font(21,.semibold))
                        .foregroundColor(Design.primary)
                    Text("从连接列表中选择主机，查看 SSH 配置。")
                        .font(Design.font(15))
                        .foregroundColor(Design.secondary)
                    Button("新建主机"){store.newHost()}
                        .buttonStyle(SoftButtonStyle(prominent:true))
                        .padding(12)
                    if !store.includeEnabled {
                        Button("初始化 SSH 集成"){store.act(["init"])}
                            .font(Design.font(13))
                    }
                    Spacer()
                }.frame(maxWidth:.infinity,maxHeight:.infinity)
            }
        }
        // The shared native window material shows through the inspector.
        .alert("删除主机",isPresented:$confirmDelete) {
            Button("取消",role:.cancel){}
            Button("删除",role:.destructive){store.delete()}
        } message: {
            Text("将从管理器移除这台主机，不会删除用户自己维护的 OpenSSH 配置。")
        }
    }

    private var inspectorHeader: some View {
        HStack(alignment:.center,spacing:12 * scale) {
            Text(store.isNew ? "新建主机" : "主机详情")
                .font(Design.font(25 * scale,.semibold))
                .foregroundColor(Design.primary)
            Spacer()
            if !store.isNew {
                Button {
                    if let host=store.selected {store.toggleFavorite(host)}
                } label: {
                    Label(store.draft.favorite ? "已收藏" : "设为收藏",
                          systemImage:store.draft.favorite ? "star.fill" : "star")
                        .font(Design.font(14 * textScale,.medium))
                        .foregroundColor(store.draft.favorite ? .orange : Design.primary)
                        .padding(.horizontal,12 * scale).frame(height:37 * scale)
                }
                .buttonStyle(SoftButtonStyle())
                Button {showMoreOptions.toggle()} label: {
                    Image(systemName:"ellipsis")
                        .font(.system(size:17 * textScale,weight:.medium))
                        .foregroundColor(Design.primary)
                        .frame(width:36 * scale,height:37 * scale)
                }
                .buttonStyle(SoftButtonStyle())
                .popover(isPresented:$showMoreOptions,arrowEdge:.bottom) {
                    VStack(alignment:.leading,spacing:12) {
                        Button("刷新主机列表"){showMoreOptions=false;store.refresh()}
                        Button("导入 SSH 配置"){showMoreOptions=false;store.act(["import"])}
                    }
                    .font(Design.font(14))
                    .buttonStyle(.plain)
                    .padding(16)
                    .frame(width:185,alignment:.leading)
                }
                .accessibilityLabel("更多主机操作")
            }
        }
        .padding(.horizontal,28 * scale)
        .padding(.top,23 * scale)
        .padding(.bottom,23 * scale)
    }

    private var tabBar: some View {
        HStack(spacing:10 * scale) {
            ForEach(InspectorTab.allCases,id:\.self) { tab in
                Button {store.tab=tab} label: {
                    VStack(spacing:11 * scale) {
                        Text(tab.rawValue)
                            .font(Design.font(17 * textScale,store.tab==tab ? .semibold : .medium))
                            .foregroundColor(store.tab==tab ? Design.blue : Design.secondary)
                            .fixedSize(horizontal:true,vertical:false)
                        Capsule()
                            .fill(store.tab==tab ? Design.blue : Color.clear)
                            .frame(height:3 * scale)
                    }
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength:0)
        }
        .padding(.horizontal,18 * scale)
    }

    private func field(_ title:String, _ value:Binding<String>,
                       editable:Bool=true,compact:Bool=false) -> some View {
        HStack(spacing:12 * scale) {
            Text(title)
                .font(Design.font(16 * textScale))
                .foregroundColor(Design.primary)
                .frame(width:106 * scale,alignment:.leading)
            Group {
                if editable {
                    TextField("",text:value)
                        .textFieldStyle(.plain)
                } else {
                    // Imported ~/.ssh/config entries remain immutable, but
                    // their values should not fade into illegible disabled
                    // NSTextField text. Render a selectable native label.
                    Text(value.wrappedValue)
                        .frame(maxWidth:.infinity,alignment:.leading)
                        .textSelection(.enabled)
                }
            }
            .font(Design.font(17 * textScale))
            .foregroundColor(Design.primary)
            .padding(.horizontal,13 * scale)
            .frame(height:43 * scale)
            .frame(maxWidth:compact ? 112 * scale : .infinity,alignment:.leading)
            .background(Design.surface(0.67),
                        in:RoundedRectangle(cornerRadius:10))
            .overlay(RoundedRectangle(cornerRadius:10).strokeBorder(Design.inputBorder))
            if compact { Spacer(minLength:0) }
        }
        .frame(minHeight:44 * scale)
    }

    private var basicFields: some View {
        Group {
            field("显示名称",$store.draft.name)
            field("SSH 别名",$store.draft.alias,editable:!store.draft.imported)
            field("主机名 / IP",$store.draft.hostname,editable:!store.draft.imported)
            field("用户名",$store.draft.username,editable:!store.draft.imported)
            field("端口",$store.draft.port,editable:!store.draft.imported,compact:true)
            identityRow
            groupRow
            tagRow
            notesRow
        }
    }

    private var identityRow: some View {
        HStack(spacing:12 * scale) {
            Text("身份文件").font(Design.font(16 * textScale)).foregroundColor(Design.primary)
                .frame(width:106 * scale,alignment:.leading)
            HStack(spacing:8) {
                TextField("请选择身份文件…",text:$store.draft.identityFile)
                    .textFieldStyle(.plain)
                    .font(Design.font(16 * textScale))
                    .disabled(store.draft.imported)
                Button {
                    let panel = NSOpenPanel()
                    panel.canChooseFiles = true
                    panel.canChooseDirectories = false
                    panel.allowsMultipleSelection = false
                    if panel.runModal() == .OK {
                        store.draft.identityFile = panel.url?.path ?? ""
                    }
                } label: {
                    Image(systemName:"folder").font(.system(size:17 * textScale))
                }
                .buttonStyle(.plain)
                .disabled(store.draft.imported)
                .help("选择 SSH 私钥文件")
            }
            .padding(.horizontal,13 * scale).frame(height:40 * scale)
            .background(Design.surface(0.67),in:RoundedRectangle(cornerRadius:10))
            .overlay(RoundedRectangle(cornerRadius:10).strokeBorder(Design.inputBorder))
        }.frame(minHeight:42 * scale)
    }

    private var groupRow: some View {
        HStack(spacing:12 * scale) {
            Text("所属分组").font(Design.font(16 * textScale)).foregroundColor(Design.primary)
                .frame(width:106 * scale,alignment:.leading)
            Button {showGroupPicker.toggle()} label: {
                HStack(spacing:8) {
                    Image(systemName:"folder").font(.system(size:15 * textScale))
                    Text(store.groups.first(where:{$0.id==store.draft.groupId})?.name ?? "未分组")
                        .font(Design.font(16 * textScale))
                    Spacer()
                    Image(systemName:"chevron.down").font(.system(size:12 * textScale))
                }
                .foregroundColor(Design.primary)
                .padding(.horizontal,13 * scale)
                .frame(height:40 * scale)
                .background(Design.surface(0.67),in:RoundedRectangle(cornerRadius:10))
                .overlay(RoundedRectangle(cornerRadius:10).strokeBorder(Design.inputBorder))
            }
            .buttonStyle(.plain)
            .popover(isPresented:$showGroupPicker,arrowEdge:.bottom) {
                VStack(alignment:.leading,spacing:8) {
                    Button("未分组"){store.draft.groupId=nil;showGroupPicker=false}
                    ForEach(store.groups) { group in
                        Button(group.name){store.draft.groupId=group.id;showGroupPicker=false}
                    }
                }
                .buttonStyle(.plain)
                .font(Design.font(14))
                .padding(16)
                .frame(minWidth:190,alignment:.leading)
            }
        }
    }

    private var tagRow: some View {
        HStack(alignment:.top,spacing:12 * scale) {
            Text("标签").font(Design.font(16 * textScale)).foregroundColor(Design.primary)
                .frame(width:106 * scale,alignment:.leading).padding(.top,8 * scale)
            VStack(alignment:.leading,spacing:7 * scale) {
                // On narrow windows, keep pills single-line instead of
                // compressing 'production' into two unreadable rows.
                HStack(spacing:4 * scale) {
                    ForEach(store.draft.tagNames,id:\.self) { tag in
                        HStack(spacing:4) {
                            TerminalBadge(tag:tag,scale:scale)
                                .fixedSize(horizontal:true,vertical:false)
                            Button {
                                store.draft.tags=store.draft.tagNames.filter{$0 != tag}.joined(separator:",")
                            } label: {
                                Image(systemName:"xmark").font(.system(size:10,weight:.medium))
                            }.buttonStyle(.plain)
                        }
                    }
                    Button {
                        editingTags.toggle()
                    } label: {
                        Label("添加标签",systemImage:"plus")
                            .font(Design.font(13 * textScale))
                            .fixedSize(horizontal:true,vertical:false)
                            .foregroundColor(Design.secondary)
                            .padding(.horizontal,6 * scale).padding(.vertical,7 * scale)
                    }
                    .buttonStyle(SoftButtonStyle())
                }
                .fixedSize(horizontal:true,vertical:false)
                .frame(maxWidth:.infinity,alignment:.leading)
                if editingTags {
                    HStack {
                        TextField("新标签",text:$newTag)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit(addTag)
                        Button("添加",action:addTag)
                    }
                }
            }
        }.frame(minHeight:51 * scale)
    }
    private func addTag() {
        let tag = newTag.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !tag.isEmpty,!tag.contains(","),!store.draft.tagNames.contains(tag) else {return}
        store.draft.tags = (store.draft.tagNames + [tag]).joined(separator:",")
        newTag = "";editingTags = false
    }

    private var notesRow: some View {
        HStack(alignment:.top,spacing:12 * scale) {
            Text("备注").font(Design.font(16 * textScale)).foregroundColor(Design.primary)
                .frame(width:106 * scale,alignment:.leading).padding(.top,9 * scale)
            NativeNotesEditor(text:$store.draft.notes,fontSize:16 * textScale)
                .frame(height:91 * scale)
                .background(Design.surface(0.67),in:RoundedRectangle(cornerRadius:10))
                .overlay(RoundedRectangle(cornerRadius:10).strokeBorder(Design.inputBorder))
        }
    }
    private var connectionFields: some View {
        Group {
            field("SSH 别名",$store.draft.alias,editable:!store.draft.imported)
            field("主机名 / IP",$store.draft.hostname,editable:!store.draft.imported)
            field("用户名",$store.draft.username,editable:!store.draft.imported)
            field("端口",$store.draft.port,editable:!store.draft.imported,compact:true)
            identityRow
            field("代理跳板",$store.draft.proxyJump,editable:!store.draft.imported)
            if store.draft.imported {
                Text("导入主机的连接信息由 ~/.ssh/config 管理，此处为只读。")
                    .font(Design.font(13)).foregroundColor(Design.secondary)
            }
        }
    }
    private var metadataFields: some View {
        Group {
            groupRow
            tagRow
            notesRow
        }
    }
    // Read-only operational metadata should look like a system inspector,
    // not loose debug strings. Keep all cards on the existing window glass.
    private var advancedFields: some View {
        VStack(alignment:.leading,spacing:21 * scale) {
            VStack(alignment:.leading,spacing:5 * scale) {
                Text("主机属性")
                    .font(Design.font(17 * textScale,.semibold))
                    .foregroundColor(Design.primary)
                Text("连接来源与主机标识")
                    .font(Design.font(13 * textScale))
                    .foregroundColor(Design.secondary)
            }

            VStack(alignment:.leading,spacing:0) {
                HStack(spacing:11 * scale) {
                    Image(systemName:"arrow.down.doc")
                        .font(.system(size:17 * textScale))
                        .foregroundColor(Design.blue)
                        .frame(width:25 * scale)
                    VStack(alignment:.leading,spacing:5 * scale) {
                        Text("连接来源")
                            .font(Design.font(13 * textScale))
                            .foregroundColor(Design.secondary)
                        Text(store.draft.imported ? "OpenSSH 配置导入" : "管理器创建")
                            .font(Design.font(16 * textScale,.medium))
                            .foregroundColor(Design.primary)
                    }
                    Spacer(minLength:8)
                    if store.draft.imported {
                        Text("只读")
                            .font(Design.font(12 * textScale,.medium))
                            .foregroundColor(Design.secondary)
                            .padding(.horizontal,9 * scale)
                            .padding(.vertical,5 * scale)
                            .background(Design.surface(0.56),in:Capsule())
                    }
                }
                .padding(.vertical,14 * scale)
                Rectangle()
                    .fill(Design.hairline)
                    .frame(height:1)
                VStack(alignment:.leading,spacing:10 * scale) {
                    HStack {
                        Image(systemName:"number.square")
                            .font(.system(size:16 * textScale))
                            .foregroundColor(Design.blue)
                            .frame(width:25 * scale)
                        Text("主机 ID")
                            .font(Design.font(14 * textScale,.medium))
                            .foregroundColor(Design.primary)
                        Spacer()
                        Button {
                            guard let id = store.draft.id else {return}
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(id,forType:.string)
                        } label: {
                            Label("复制",systemImage:"doc.on.doc")
                                .font(Design.font(13 * textScale))
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(Design.blue)
                        .disabled(store.draft.id == nil)
                        .help("复制主机 ID")
                    }
                    Text(store.draft.id ?? "保存后自动生成")
                        .font(.system(size:13 * textScale,weight:.medium,design:.monospaced))
                        .foregroundColor(Design.secondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal:false,vertical:true)
                        .padding(.leading,36 * scale)
                }
                .padding(.vertical,14 * scale)
            }
            .padding(.horizontal,16 * scale)
            .background(Design.surface(0.40),
                        in:RoundedRectangle(cornerRadius:13 * scale,style:.continuous))
            .overlay(RoundedRectangle(cornerRadius:13 * scale)
                .strokeBorder(Design.hairline,lineWidth:1))

            VStack(alignment:.leading,spacing:12 * scale) {
                Text("SSH 集成")
                    .font(Design.font(17 * textScale,.semibold))
                    .foregroundColor(Design.primary)

                VStack(alignment:.leading,spacing:13 * scale) {
                    HStack(spacing:10 * scale) {
                        Image(systemName:"point.3.connected.trianglepath.dotted")
                            .font(.system(size:17 * textScale))
                            .foregroundColor(Design.blue)
                        Text("OpenSSH 配置")
                            .font(Design.font(15 * textScale,.medium))
                            .foregroundColor(Design.primary)
                        Spacer()
                        Text(store.includeEnabled ? "已就绪" : "未初始化")
                            .font(Design.font(12 * textScale,.medium))
                            .foregroundColor(store.includeEnabled ? Design.blue : .orange)
                            .padding(.horizontal,9 * scale)
                            .padding(.vertical,5 * scale)
                            .background(Design.surface(0.50),in:Capsule())
                    }

                    Text(store.draft.imported
                         ? "此主机由 ~/.ssh/config 管理，连接参数请在原配置文件中修改。"
                         : "管理器通过 SSH Include 管理自建主机，不覆盖你的原始 SSH 配置。")
                        .font(Design.font(13 * textScale))
                        .foregroundColor(Design.secondary)
                        .fixedSize(horizontal:false,vertical:true)

                    if !store.includeEnabled {
                        HStack(alignment:.top,spacing:8 * scale) {
                            Image(systemName:"exclamationmark.circle")
                                .foregroundColor(.orange)
                            Text("创建自管主机前，需要先初始化 SSH 集成。")
                                .fixedSize(horizontal:false,vertical:true)
                        }
                        .font(Design.font(13 * textScale))
                        .foregroundColor(Design.secondary)
                        Button {
                            store.act(["init"])
                        } label: {
                            Label("初始化 SSH 集成",systemImage:"checkmark.shield")
                                .font(Design.font(14 * textScale,.medium))
                                .padding(.horizontal,12 * scale)
                                .frame(height:35 * scale)
                        }
                        .buttonStyle(SoftButtonStyle(prominent:true))
                        .disabled(store.busy)
                    }

                    Rectangle().fill(Design.hairline).frame(height:1)

                    Button {
                        store.act(["import"])
                    } label: {
                        HStack(spacing:10 * scale) {
                            Image(systemName:"square.and.arrow.down")
                                .foregroundColor(Design.blue)
                            VStack(alignment:.leading,spacing:3 * scale) {
                                Text("导入 OpenSSH 主机")
                                    .font(Design.font(14 * textScale,.medium))
                                    .foregroundColor(Design.primary)
                                Text("从 ~/.ssh/config 读取现有连接")
                                    .font(Design.font(12 * textScale))
                                    .foregroundColor(Design.secondary)
                            }
                            Spacer(minLength:0)
                            Image(systemName:"chevron.right")
                                .font(.system(size:12 * textScale,weight:.semibold))
                                .foregroundColor(Design.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(store.busy)
                    .help("导入 ~/.ssh/config 中的主机")
                }
                .padding(16 * scale)
                .frame(maxWidth:.infinity,alignment:.leading)
                .background(Design.surface(0.40),
                            in:RoundedRectangle(cornerRadius:13 * scale,style:.continuous))
                .overlay(RoundedRectangle(cornerRadius:13 * scale)
                    .strokeBorder(Design.hairline,lineWidth:1))
            }
        }
        .frame(maxWidth:.infinity,alignment:.leading)
    }

    private var footer: some View {
        HStack(spacing:12 * scale) {
            // The reference uses a split primary control. The main surface
            // connects immediately; the chevron exposes real actions.
            HStack(spacing:0) {
                Button {
                    if let selected=store.selected {store.connect(selected)}
                } label: {
                    Label("在 Warp 中打开",systemImage:"arrow.up.right.square")
                        .font(Design.font(16 * textScale,.semibold))
                        .fixedSize(horizontal:true,vertical:false)
                        .padding(.horizontal,17 * scale)
                        .frame(height:46 * scale)
                        .foregroundColor(.white)
                }
                .buttonStyle(.plain)
                Rectangle().fill(Color.white.opacity(0.27))
                    .frame(width:1,height:24 * scale)
                // A borderless AppKit Menu forces its black indicator tint
                // onto a colored split button. An ordinary SwiftUI popover
                // retains the white chevron and the reference's geometry.
                Button { showConnectActions.toggle() } label: {
                    Image(systemName:"chevron.down")
                        .font(.system(size:12 * textScale,weight:.semibold))
                        .foregroundColor(.white)
                        .frame(width:33 * scale,height:46 * scale)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("更多连接操作")
                .popover(isPresented:$showConnectActions,arrowEdge:.bottom) {
                    VStack(alignment:.leading,spacing:13) {
                        Button("在 Warp 中打开") {
                            showConnectActions=false
                            if let selected=store.selected {store.connect(selected)}
                        }
                        Button("复制 SSH 别名") {
                            showConnectActions=false
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(store.draft.alias,forType:.string)
                        }
                    }
                    .font(Design.font(14 * textScale))
                    .buttonStyle(.plain)
                    .padding(16)
                    .frame(width:190,alignment:.leading)
                }
            }
            .background(Design.blue,in:RoundedRectangle(cornerRadius:10 * scale,style:.continuous))
            .shadow(color:.black.opacity(0.09),radius:5 * scale,y:2)
            .disabled(store.isNew || store.busy)
            Button {store.save()} label: {
                Label(store.isNew ? "创建主机" : "保存更改",systemImage:"square.and.arrow.down")
                    .font(Design.font(15 * textScale,.medium))
                    .fixedSize(horizontal:true,vertical:false)
                    .padding(.horizontal,22 * scale)
                    .frame(height:46 * scale)
            }
            .buttonStyle(SoftButtonStyle())
            .disabled(store.busy)
            if !store.isNew {
                Button(role:.destructive) {confirmDelete = true} label: {
                    Label("删除",systemImage:"trash")
                        .font(Design.font(15 * textScale,.medium))
                        .fixedSize(horizontal:true,vertical:false)
                        .foregroundColor(.red)
                        .padding(.horizontal,21 * scale)
                        .frame(height:46 * scale)
                }
                .buttonStyle(SoftButtonStyle(destructive:true))
                .disabled(store.busy)
            }
            Spacer(minLength:0)
            if store.busy {ProgressView().controlSize(.small)}
        }
        .padding(.horizontal,20 * scale)
        .padding(.vertical,14 * scale)
        // The main window already supplies a continuous behind-window
        // NSVisualEffectView. A second .headerView material here painted a
        // bright, opaque-looking strip across the bottom of the inspector.
        // Keep the controls on the *same* glass as the rest of this pane.
        .overlay(alignment:.top) {
            Rectangle().fill(Design.hairline.opacity(0.60)).frame(height:1)
        }
    }
}


// A native NSTextView gives the notes field the same soft material and
// typography as the other fields. SwiftUI TextEditor on macOS 12 introduces
// an additional opaque inner scroll surface and visible scroll chrome.
private struct NativeNotesEditor: NSViewRepresentable {
    @Binding var text: String
    var fontSize: CGFloat = 16

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.hasVerticalScroller = false
        scroll.autohidesScrollers = true
        let editor = NSTextView(frame:.zero)
        editor.isRichText = false
        editor.allowsUndo = true
        editor.drawsBackground = false
        editor.isVerticallyResizable = true
        editor.isHorizontallyResizable = false
        editor.autoresizingMask = [.width]
        editor.textContainer?.widthTracksTextView = true
        editor.textContainerInset = NSSize(width:8,height:10)
        editor.font = NSFont.systemFont(ofSize:fontSize)
        editor.textColor = .labelColor
        editor.string = text
        editor.delegate = context.coordinator
        scroll.documentView = editor
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let editor = scroll.documentView as? NSTextView else { return }
        context.coordinator.parent = self
        if editor.string != text { editor.string = text }
        editor.textColor = .labelColor
        if editor.font?.pointSize != fontSize {
            editor.font = NSFont.systemFont(ofSize:fontSize)
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: NativeNotesEditor
        init(_ parent: NativeNotesEditor) { self.parent = parent }
        func textDidChange(_ notification: Notification) {
            if let editor = notification.object as? NSTextView {
                parent.text = editor.string
            }
        }
    }
}
