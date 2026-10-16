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
    @FocusState private var tagInputFocused: Bool
    @State private var showGroupPicker = false
    @State private var showMoreOptions = false
    @State private var showConnectActions = false
    @State private var credentialEditor: CredentialVault.Kind? = nil

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
                    .padding(.horizontal,20 * scale)
                    .padding(.top,17 * scale)
                    .padding(.bottom,22 * scale)
                    .background(NativeScrollbarCleaner())
                }
                .frame(maxWidth:.infinity,maxHeight:.infinity)
                // Use the same inspector glass in all tabs: an additional
                // connection-only white wash made this tab visibly heavier.
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
        // Match the first column's actual macOS sidebar material and opacity.
        // A separate white surface here previously made the whole inspector
        // look opaque compared to the sidebar, regardless of card styling.
        .background {
            MacMaterial(material:.sidebar,
                        blendingMode:.behindWindow,opacity:0.75)
                .ignoresSafeArea(.container,edges:.top)
        }
        .sheet(item:$credentialEditor) { kind in
            CredentialEditor(hostID:store.selectedID,kind:kind,store:store)
        }
        .alert("删除主机",isPresented:$confirmDelete) {
            Button("取消",role:.cancel){}
            Button("删除",role:.destructive){store.delete()}
        } message: {
            Text("将从管理器移除这台主机，不会删除用户自己维护的 OpenSSH 配置。")
        }
    }

    private var inspectorHeader: some View {
        HStack(alignment:.center,spacing:11 * scale) {
            if store.isNew {
                Text("新建主机")
                    .font(Design.font(25 * scale,.semibold))
                    .foregroundColor(Design.primary)
            } else if let host=store.selected {
                TerminalIcon(name:host.name,tags:host.tagNames,size:58 * scale)
                VStack(alignment:.leading,spacing:5 * scale) {
                    HStack(spacing:8 * scale) {
                        Text(host.name)
                            .font(Design.font(23 * textScale,.semibold))
                            .foregroundColor(Design.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)
                        if let tag=host.tagNames.first {
                            TerminalBadge(tag:tag,scale:scale)
                                .fixedSize(horizontal:true,vertical:false)
                        }
                    }
                    Text(host.hostname)
                        .font(Design.font(14 * textScale))
                        .foregroundColor(Design.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth:.infinity,alignment:.leading)
            } else {
                Text("主机详情")
                    .font(Design.font(25 * scale,.semibold))
                    .foregroundColor(Design.primary)
            }
            Spacer(minLength:3 * scale)
            if !store.isNew {
                Button {
                    if let host=store.selected {store.toggleFavorite(host)}
                } label: {
                    Image(systemName:store.draft.favorite ? "star.fill" : "star")
                        .font(.system(size:21 * textScale,weight:.regular))
                        .foregroundColor(store.draft.favorite ? .orange : Design.primary)
                        .frame(width:29 * scale,height:35 * scale)
                }
                .buttonStyle(.plain)
                .help(store.draft.favorite ? "取消收藏" : "设为收藏")
                Button {showMoreOptions.toggle()} label: {
                    Image(systemName:"ellipsis")
                        .font(.system(size:17 * textScale,weight:.medium))
                        .foregroundColor(Design.primary)
                        .frame(width:36 * scale,height:37 * scale)
                        .contentShape(Rectangle())
                }
                // Match the favorite action: no opaque white button tile.
                .buttonStyle(.plain)
                .help("更多主机操作")
                .popover(isPresented:$showMoreOptions,arrowEdge:.bottom) {
                    VStack(alignment:.leading,spacing:12) {
                        Button("刷新主机列表"){showMoreOptions=false;store.refresh()}
                        Button("导入 SSH 配置"){showMoreOptions=false;store.act(["import"])}
                        if let host = store.selected {
                            Divider()
                            Button {
                                showMoreOptions=false;store.connectManual(host)
                            } label: {
                                Label("手动连接",systemImage:"terminal")
                            }
                            Divider()
                            Button {
                                showMoreOptions=false;store.copyPassword(.ssh,for:host)
                            } label: {
                                Label("复制 SSH 密码",systemImage:"doc.on.doc")
                            }
                            .disabled(!store.hasPassword(.ssh,for:host.id))
                            Button {
                                showMoreOptions=false;store.copyPassword(.sudo,for:host)
                            } label: {
                                Label("复制 sudo 密码",systemImage:"doc.on.doc")
                            }
                            .disabled(!store.hasPassword(.sudo,for:host.id) && !store.hasPassword(.ssh,for:host.id))
                        }
                    }
                    .font(Design.font(14))
                    .buttonStyle(.plain)
                    .padding(16)
                    .frame(width:215,alignment:.leading)
                }
                .accessibilityLabel("更多主机操作")
            }
        }
        .padding(.horizontal,24 * scale)
        .padding(.top,38 * scale)
        .padding(.bottom,22 * scale)
    }

    private var tabBar: some View {
        HStack(spacing:10 * scale) {
            ForEach(InspectorTab.allCases,id:\.self) { tab in
                Button {store.tab=tab} label: {
                    VStack(spacing:11 * scale) {
                        Text(LocalizedStringKey(tab.rawValue))
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
        .padding(.bottom,6 * scale)
    }

    private func field(_ title:String, _ value:Binding<String>,
                       editable:Bool=true,compact:Bool=false) -> some View {
        HStack(spacing:12 * scale) {
            Text(LocalizedStringKey(title))
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
            .background(store.tab == .connection ? Design.surface(0.38) : Design.surface(0.67),
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
            .background(store.tab == .connection ? Design.surface(0.38) : Design.surface(0.67),
                        in:RoundedRectangle(cornerRadius:10))
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
                    Text(store.draft.groupId.map {store.groupPath($0)} ?? AppLanguage.text("未分组"))
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
                    ForEach(store.groups.sorted(by:{
                        store.groupPath($0.id).localizedStandardCompare(store.groupPath($1.id)) == .orderedAscending
                    })) { group in
                        Button(store.groupPath(group.id)){
                            store.draft.groupId=group.id;showGroupPicker=false
                        }
                    }
                }
                .buttonStyle(.plain)
                .font(Design.font(14))
                .padding(16)
                .frame(minWidth:190,alignment:.leading)
            }
        }
    }

    // A consistent inline editor instead of an unstyled native roundedBorder
    // field that stretches beneath the tag chips when focused.
    private var reusableTagSuggestions:[String] {
        HostTagCatalog.available(store.availableTagNames,
                                 excluding:store.draft.tagNames,
                                 search:newTag)
    }

    private var newTagValidation: String? {
        let candidate=newTag.trimmingCharacters(in:.whitespacesAndNewlines)
        if candidate.contains(",") || candidate.contains("，") {
            return "标签不能包含逗号"
        }
        if candidate.count > 32 {
            return "标签名称最多 32 个字符"
        }
        if store.draft.tagNames.contains(where:{
            HostTagCatalog.key($0) == HostTagCatalog.key(candidate)
        }) {
            return "标签已存在"
        }
        return nil
    }

    private var tagRow: some View {
        HStack(alignment:.top,spacing:12 * scale) {
            Text("标签")
                .font(Design.font(16 * textScale))
                .foregroundColor(Design.primary)
                .frame(width:106 * scale,alignment:.leading)
                .padding(.top,9 * scale)
            VStack(alignment:.leading,spacing:9 * scale) {
                ScrollView(.horizontal,showsIndicators:false) {
                    HStack(spacing:7 * scale) {
                        ForEach(store.draft.tagNames,id:\.self) { tag in
                            HStack(spacing:4 * scale) {
                                TerminalBadge(tag:tag,scale:scale)
                                Button {
                                    store.draft.tags=store.draft.tagNames
                                        .filter{$0 != tag}.joined(separator:",")
                                } label: {
                                    Image(systemName:"xmark")
                                        .font(.system(size:10 * scale,weight:.semibold))
                                        .foregroundColor(Design.secondary)
                                        .frame(width:16 * scale,height:24 * scale)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .help("移除标签：\(tag)")
                            }
                        }
                        Button {
                            editingTags.toggle()
                            newTag=""
                            if editingTags {
                                DispatchQueue.main.async {tagInputFocused=true}
                            }
                        } label: {
                            Label(editingTags ? "收起" : "添加标签",
                                  systemImage:editingTags ? "minus" : "plus")
                                .font(Design.font(12.5 * textScale,.medium))
                                .foregroundColor(Design.secondary)
                                .padding(.horizontal,9 * scale)
                                .frame(height:29 * scale)
                                .background(Design.surface(0.35),
                                            in:RoundedRectangle(cornerRadius:8 * scale))
                                .overlay(RoundedRectangle(cornerRadius:8 * scale)
                                            .strokeBorder(Design.hairline,lineWidth:1))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical,2 * scale)
                }
                .frame(maxWidth:.infinity,alignment:.leading)
                .frame(height:36 * scale)

                if editingTags {
                    if !reusableTagSuggestions.isEmpty {
                        VStack(alignment:.leading,spacing:6 * scale) {
                            HStack(spacing:5 * scale) {
                                Image(systemName:"tag.fill")
                                Text("已有标签 · 点击即可复用")
                            }
                            .font(Design.font(11.5 * textScale))
                            .foregroundColor(Design.secondary)

                            ScrollView(.horizontal,showsIndicators:false) {
                                HStack(spacing:7 * scale) {
                                    ForEach(reusableTagSuggestions,id:\.self) { tag in
                                        Button {
                                            selectExistingTag(tag)
                                        } label: {
                                            HStack(spacing:4 * scale) {
                                                Image(systemName:"plus.circle.fill")
                                                    .font(.system(size:12 * textScale))
                                                    .foregroundColor(Design.blue)
                                                TerminalBadge(tag:tag,scale:scale)
                                            }
                                            .padding(.horizontal,7 * scale)
                                            .frame(height:33 * scale)
                                            .background(Design.surface(0.35),
                                                        in:RoundedRectangle(cornerRadius:9 * scale))
                                            .contentShape(RoundedRectangle(cornerRadius:9 * scale))
                                        }
                                        .buttonStyle(.plain)
                                        .help("使用已有标签：\(tag)")
                                    }
                                }
                                .padding(.vertical,3 * scale)
                            }
                        }
                    }

                    HStack(spacing:8 * scale) {
                        HStack(spacing:8 * scale) {
                            Image(systemName:"tag")
                                .font(.system(size:13 * textScale))
                                .foregroundColor(Design.secondary)
                            TextField("输入标签名称",text:$newTag)
                                .font(Design.font(14 * textScale))
                                .foregroundColor(Design.primary)
                                .textFieldStyle(.plain)
                                .focused($tagInputFocused)
                                .onSubmit(addTag)
                                .onExitCommand {
                                    editingTags=false
                                    newTag=""
                                }
                        }
                        .padding(.horizontal,12 * scale)
                        .frame(height:39 * scale)
                        .background(Design.surface(0.57),
                                    in:RoundedRectangle(cornerRadius:9 * scale))
                        .overlay(RoundedRectangle(cornerRadius:9 * scale)
                                    .strokeBorder(tagInputFocused ? Design.blue : Design.inputBorder,
                                                  lineWidth:tagInputFocused ? 1.4 : 1))

                        Button(action:addTag) {
                            Text("添加")
                                .font(Design.font(13 * textScale,.medium))
                                .foregroundColor(.white)
                                .frame(width:53 * scale,height:39 * scale)
                                .background(Design.blue,
                                            in:RoundedRectangle(cornerRadius:9 * scale))
                        }
                        .buttonStyle(.plain)
                        .disabled(newTag.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty ||
                                  newTagValidation != nil)
                        .opacity(newTag.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty ||
                                 newTagValidation != nil ? 0.45 : 1)
                    }
                    if let error=newTagValidation,
                       !newTag.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty {
                        Text(error)
                            .font(Design.font(11.5 * textScale))
                            .foregroundColor(.red)
                    }
                }
            }
            .frame(maxWidth:.infinity,alignment:.leading)
        }
        .frame(minHeight:46 * scale)
    }

    private func selectExistingTag(_ tag:String) {
        guard !store.draft.tagNames.contains(where:{
            HostTagCatalog.key($0) == HostTagCatalog.key(tag)
        }) else {return}
        store.draft.tags=(store.draft.tagNames + [tag]).joined(separator:",")
        newTag=""
        tagInputFocused=true
    }

    private func addTag() {
        let tag=newTag.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !tag.isEmpty,newTagValidation == nil else {return}
        let canonical=HostTagCatalog.canonical(tag,in:store.availableTagNames)
        selectExistingTag(canonical)
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
    // Three inset glass sections match the reference's card-based inspector.
    // This only changes SwiftUI presentation: auth, Keychain and Warp behavior
    // remain owned by their existing model and service layers.
    private var connectionFields: some View {
        VStack(alignment:.leading,spacing:16 * scale) {
            authMethodSectionCard
            sshParameterSectionCard
            credentialSectionCard
        }
        .frame(maxWidth:.infinity,alignment:.leading)
    }

    private func settingsSectionCard<Content: View>(
        icon:String, title:String, subtitle:String,
        @ViewBuilder content:() -> Content
    ) -> some View {
        VStack(alignment:.leading,spacing:14 * scale) {
            HStack(alignment:.top,spacing:11 * scale) {
                Image(systemName:icon)
                    .font(.system(size:19 * textScale,weight:.medium))
                    .foregroundColor(Design.primary)
                    .frame(width:27 * scale,height:27 * scale)
                VStack(alignment:.leading,spacing:4 * scale) {
                    Text(LocalizedStringKey(title))
                        .font(Design.font(17 * textScale,.semibold))
                        .foregroundColor(Design.primary)
                    Text(LocalizedStringKey(subtitle))
                        .font(Design.font(12 * textScale))
                        .foregroundColor(Design.secondary)
                        .fixedSize(horizontal:false,vertical:true)
                }
                Spacer(minLength:0)
            }
            content()
        }
        .padding(17 * scale)
        .frame(maxWidth:.infinity,alignment:.leading)
        // Just a little extra brightness over the common sidebar glass.
        .background(Design.surface(0.16),
                    in:RoundedRectangle(cornerRadius:15 * scale,style:.continuous))
        .overlay(RoundedRectangle(cornerRadius:15 * scale,style:.continuous)
                    .strokeBorder(Design.hairline,lineWidth:1))
    }

    private func authOptionCard(
        _ mode:String, title:String, subtitle:String, icon:String
    ) -> some View {
        let selected = store.draft.authMode == mode
        return Button {
            store.draft.authMode = mode
        } label: {
            VStack(alignment:.center,spacing:8 * scale) {
                HStack(spacing:6 * scale) {
                    Image(systemName:icon)
                        .font(.system(size:18 * textScale,weight:.medium))
                    Text(LocalizedStringKey(title))
                        .font(Design.font(13.5 * textScale,.semibold))
                        .lineLimit(2)
                        .minimumScaleFactor(0.78)
                }
                .foregroundColor(selected ? Design.blue : Design.primary)
                .frame(maxWidth:.infinity)
                Text(LocalizedStringKey(subtitle))
                    .font(Design.font(11.5 * textScale))
                    .foregroundColor(Design.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .fixedSize(horizontal:false,vertical:true)
                    .frame(maxWidth:.infinity)
            }
            .padding(.horizontal,8 * scale)
            .padding(.vertical,14 * scale)
            .frame(maxWidth:.infinity)
            .frame(height:112 * scale)
            .background(selected ? Design.blue.opacity(0.09) : Design.surface(0.14),
                        in:RoundedRectangle(cornerRadius:12 * scale,style:.continuous))
            .overlay(RoundedRectangle(cornerRadius:12 * scale,style:.continuous)
                        .strokeBorder(selected ? Design.blue : Design.hairline,
                                      lineWidth:selected ? 1.4 : 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .help(title)
    }

    private var authMethodSectionCard: some View {
        settingsSectionCard(
            icon:"key",
            title:"SSH 认证方式",
            subtitle:"选择连接时使用的身份验证方式"
        ) {
            VStack(alignment:.leading,spacing:11 * scale) {
                HStack(alignment:.top,spacing:8 * scale) {
                    authOptionCard("auto",
                        title:"自动选择",subtitle:"按优先级尝试多种认证",
                        icon:"bolt")
                    authOptionCard("key",
                        title:"SSH 密钥",subtitle:"使用私钥文件进行认证",
                        icon:"key")
                    authOptionCard("password",
                        title:"用户名 + 密码",subtitle:"使用用户名和密码认证",
                        icon:"person")
                }
                HStack(alignment:.top,spacing:7 * scale) {
                    Image(systemName:"info.circle")
                        .foregroundColor(Design.blue)
                    Text(LocalizedStringKey(authHint))
                        .foregroundColor(Design.secondary)
                        .fixedSize(horizontal:false,vertical:true)
                }
                .font(Design.font(12 * textScale))
                .padding(.horizontal,2 * scale)
            }
        }
    }

    private var authHint:String {
        if store.draft.imported {
            return store.draft.authMode == "password"
                ? "原有 SSH 配置保持不变；保存密码后可尝试辅助登录。"
                : "此主机由 ~/.ssh/config 管理，保留原有连接设置。"
        }
        switch store.draft.authMode {
        case "key":
            return "使用 SSH 公钥认证；不会自动提交保存的密码。"
        case "password":
            return "保存密码后可尝试自动登录；仍可在主机菜单中手动连接。"
        default:
            return "沿用 OpenSSH 的认证规则，不影响已有连接方式。"
        }
    }

    private var credentialSectionCard: some View {
        let sshSaved = store.selectedID.map {
            store.hasPassword(.ssh,for:$0)
        } ?? false
        let sudoSaved = store.selectedID.map {
            store.hasPassword(.sudo,for:$0)
        } ?? false
        return settingsSectionCard(
            icon:"lock.shield",
            title:"凭据管理",
            subtitle:"密码仅保存在此 Mac 的钥匙串中，不写入 SSH 配置"
        ) {
            VStack(spacing:9 * scale) {
                credentialSettingRow(
                    kind:.ssh,
                    title:"SSH 登录密码",
                    detail:sshSaved ? (store.draft.authMode == "password"
                        ? "已保存到钥匙串，可用于自动登录" : "已保存到钥匙串，可一键复制")
                        : "保存在钥匙串中，可安全管理 SSH 登录密码",
                    status:sshSaved ? "已保存" : "未保存",
                    hasOwnCredential:sshSaved,
                    canCopy:sshSaved
                )
                credentialSettingRow(
                    kind:.sudo,
                    title:"sudo 密码",
                    detail:sudoSaved ? "已单独保存，仅支持复制"
                        : (sshSaved ? "复用已保存的 SSH 密码，不自动填写"
                          : "可单独保存 sudo 密码，不自动填写"),
                    status:sudoSaved ? "已配置" : (sshSaved ? "复用 SSH" : "未配置"),
                    hasOwnCredential:sudoSaved,
                    canCopy:sudoSaved || sshSaved
                )
            }
        }
    }

    private func credentialSettingRow(
        kind:CredentialVault.Kind,
        title:String,detail:String,status:String,
        hasOwnCredential:Bool,canCopy:Bool
    ) -> some View {
        HStack(spacing:4 * scale) {
            Button {
                credentialEditor = kind
            } label: {
                HStack(spacing:11 * scale) {
                    Image(systemName:kind == .ssh ? "key.fill" : "terminal")
                        .font(.system(size:18 * textScale,weight:.medium))
                        .foregroundColor(kind == .ssh ? Design.blue : Design.primary)
                        .frame(width:40 * scale,height:40 * scale)
                        .background(Design.surface(0.20),
                                    in:RoundedRectangle(cornerRadius:11 * scale))
                    VStack(alignment:.leading,spacing:5 * scale) {
                        Text(LocalizedStringKey(title))
                            .font(Design.font(14 * textScale,.semibold))
                            .foregroundColor(Design.primary)
                        Text(LocalizedStringKey(detail))
                            .font(Design.font(11.5 * textScale))
                            .foregroundColor(Design.secondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                    .frame(maxWidth:.infinity,alignment:.leading)
                    Text(LocalizedStringKey(store.selectedID == nil ? "先保存主机" : status))
                        .font(Design.font(11.5 * textScale,.medium))
                        .foregroundColor(Design.secondary)
                        .padding(.horizontal,8 * scale)
                        .padding(.vertical,5 * scale)
                        .background(Design.surface(0.28),in:Capsule())
                        .fixedSize(horizontal:true,vertical:false)
                    Image(systemName:"chevron.right")
                        .font(.system(size:11 * textScale,weight:.semibold))
                        .foregroundColor(Design.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(store.selectedID == nil)
            .help(store.selectedID == nil ? "请先保存主机" :
                  (hasOwnCredential ? "修改或删除密码" : "设置密码"))
            if canCopy, let host=store.selected {
                Button {
                    store.copyPassword(kind,for:host)
                } label: {
                    Image(systemName:"doc.on.doc")
                        .font(.system(size:12 * textScale))
                        .foregroundColor(Design.secondary)
                        .frame(width:25 * scale,height:30 * scale)
                }
                .buttonStyle(.plain)
                .help(kind == .ssh ? "复制 SSH 登录密码" : "复制 sudo 密码")
                .accessibilityLabel(kind == .ssh ? "复制 SSH 登录密码" : "复制 sudo 密码")
            }
        }
        .padding(.horizontal,12 * scale)
        .padding(.vertical,15 * scale)
        .frame(maxWidth:.infinity,alignment:.leading)
        .background(Design.surface(0.13),
                    in:RoundedRectangle(cornerRadius:11 * scale,style:.continuous))
        .overlay(RoundedRectangle(cornerRadius:11 * scale,style:.continuous)
                    .strokeBorder(Design.hairline,lineWidth:1))
    }

    private var sshParameterSectionCard: some View {
        settingsSectionCard(
            icon:"slider.horizontal.3",
            title:"SSH 连接参数",
            subtitle:store.draft.imported
                ? "连接信息来自 ~/.ssh/config，修改请编辑原始文件"
                : "配置主机地址、用户名、端口和 SSH 连接选项"
        ) {
            VStack(alignment:.leading,spacing:10 * scale) {
                field("SSH 别名",$store.draft.alias,editable:!store.draft.imported)
                field("主机名 / IP",$store.draft.hostname,editable:!store.draft.imported)
                field("用户名",$store.draft.username,editable:!store.draft.imported)
                field("端口",$store.draft.port,editable:!store.draft.imported,compact:true)
                if store.draft.authMode != "password" {
                    identityRow
                }
                field("代理跳板",$store.draft.proxyJump,editable:!store.draft.imported)
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
                        Text(LocalizedStringKey(store.draft.imported ? "OpenSSH 配置导入" : "管理器创建"))
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
                    Text(store.draft.id ?? AppLanguage.text("保存后自动生成"))
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
                        Text(LocalizedStringKey(store.includeEnabled ? "已就绪" : "未初始化"))
                            .font(Design.font(12 * textScale,.medium))
                            .foregroundColor(store.includeEnabled ? Design.blue : .orange)
                            .padding(.horizontal,9 * scale)
                            .padding(.vertical,5 * scale)
                            .background(Design.surface(0.50),in:Capsule())
                    }

                    Text(LocalizedStringKey(store.draft.imported
                         ? "此主机由 ~/.ssh/config 管理，连接参数请在原配置文件中修改。"
                         : "管理器通过 SSH Include 管理自建主机，不覆盖你的原始 SSH 配置。"))
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
                        if let host = store.selected {
                            Button {
                                showConnectActions=false;store.connectManual(host)
                            } label: {
                                Label("手动连接",systemImage:"terminal")
                            }
                            Divider()
                            Button {
                                showConnectActions=false;store.copyPassword(.ssh,for:host)
                            } label: {
                                Label("复制 SSH 密码",systemImage:"doc.on.doc")
                            }
                            .disabled(!store.hasPassword(.ssh,for:host.id))
                            Button {
                                showConnectActions=false;store.copyPassword(.sudo,for:host)
                            } label: {
                                Label("复制 sudo 密码",systemImage:"doc.on.doc")
                            }
                            .disabled(!store.hasPassword(.sudo,for:host.id) && !store.hasPassword(.ssh,for:host.id))
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
                    .frame(width:215,alignment:.leading)
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

extension CredentialVault.Kind: Identifiable {
    var id: String { rawValue }
}

private struct CredentialEditor: View {
    let hostID: String?
    let kind: CredentialVault.Kind
    @ObservedObject var store: ManagerStore
    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    @State private var showPassword = false
    @State private var inlineError: String?
    @FocusState private var passwordFocused: Bool

    private var exists: Bool {
        hostID.map {store.hasPassword(kind,for:$0)} ?? false
    }

    var body: some View {
        VStack(alignment:.leading,spacing:18) {
            HStack(alignment:.top,spacing:12) {
                Image(systemName:kind == .ssh ? "key.fill" : "lock.shield")
                    .font(.system(size:18,weight:.medium))
                    .foregroundColor(Design.blue)
                    .frame(width:42,height:42)
                    .background(Design.blue.opacity(0.10),
                                in:RoundedRectangle(cornerRadius:11))
                VStack(alignment:.leading,spacing:5) {
                    Text(kind == .ssh ? "SSH 登录密码" : "sudo 独立密码")
                        .font(Design.font(19,.semibold))
                        .foregroundColor(Design.primary)
                    Text(exists ? "修改这台主机保存的密码" : "为这台主机安全保存密码")
                        .font(Design.font(13))
                        .foregroundColor(Design.secondary)
                }
                Spacer(minLength:0)
            }

            VStack(alignment:.leading,spacing:8) {
                Text("密码")
                    .font(Design.font(13,.medium))
                    .foregroundColor(Design.primary)
                HStack(spacing:10) {
                    Image(systemName:"lock.fill")
                        .font(.system(size:14))
                        .foregroundColor(Design.secondary)
                    Group {
                        if showPassword {
                            TextField("输入密码",text:$password)
                                .focused($passwordFocused)
                        } else {
                            SecureField("输入密码",text:$password)
                                .focused($passwordFocused)
                        }
                    }
                    .font(Design.font(15))
                    .textFieldStyle(.plain)
                    .onSubmit(save)
                    Button {
                        showPassword.toggle()
                        DispatchQueue.main.async {passwordFocused=true}
                    } label: {
                        Image(systemName:showPassword ? "eye.slash" : "eye")
                            .font(.system(size:15))
                            .foregroundColor(Design.secondary)
                            .frame(width:30,height:32)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(showPassword ? "隐藏密码" : "显示密码")
                    .accessibilityLabel(showPassword ? "隐藏密码" : "显示密码")
                }
                .padding(.horizontal,13)
                .frame(height:45)
                .background(Design.surface(0.62),
                            in:RoundedRectangle(cornerRadius:10))
                .overlay(RoundedRectangle(cornerRadius:10)
                            .strokeBorder(passwordFocused ? Design.blue : Design.inputBorder,
                                          lineWidth:passwordFocused ? 1.4 : 1))
                if let inlineError=inlineError {
                    Text(LocalizedStringKey(inlineError))
                        .font(Design.font(12))
                        .foregroundColor(.red)
                }
                Label("仅保存在 macOS 钥匙串，不写入 SSH 配置或数据库",
                      systemImage:"checkmark.shield")
                    .font(Design.font(12))
                    .foregroundColor(Design.secondary)
            }

            Rectangle().fill(Design.hairline).frame(height:1)
            HStack(spacing:10) {
                if exists {
                    Button(role:.destructive) {
                        guard let hostID=hostID else {return}
                        if store.removePassword(kind,hostID:hostID) {
                            dismiss()
                        } else {
                            inlineError=store.errorMessage ?? "删除密码失败"
                        }
                    } label: {
                        Text("删除已保存密码")
                            .font(Design.font(13))
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.red)
                }
                Spacer()
                Button("取消") {dismiss()}
                    .keyboardShortcut(.cancelAction)
                Button("保存密码",action:save)
                    .buttonStyle(.borderedProminent)
                    .tint(Design.blue)
                    .disabled(hostID == nil || password.isEmpty)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width:490)
        .onAppear {
            DispatchQueue.main.async {passwordFocused=true}
        }
        .onChange(of:password) { _ in inlineError=nil }
    }

    private func save() {
        guard let hostID=hostID else {
            inlineError="请先保存主机"
            return
        }
        guard !password.isEmpty else {
            inlineError="请输入密码"
            return
        }
        if store.savePassword(password,kind:kind,hostID:hostID) {
            dismiss()
        } else {
            inlineError=store.errorMessage ?? "保存密码失败，请重试"
        }
    }
}
