//! Warp SSH Manager — macOS-first GPUI desktop interface.
//! The panes reproduce the approved dark/light three-column design.
//! SSH login itself is delegated to Warp and OpenSSH; this view never handles credentials.
use anyhow::Result;
use gpui::*;
use gpui::prelude::*;
use gpui_component::scroll::ScrollableElement;
use gpui_component::{
    input::{Input, InputEvent, InputState},
    theme::Theme,
    Icon, IconName, Root, Sizable, StyledExt,
};
use std::collections::HashSet;
use uuid::Uuid;
use wsm_core::{AppPaths, Group, Host, HostInput, HostSource, Manager};

mod theme;
mod quick_connect;
use theme::{Appearance, Palette};

#[cfg(feature = "tray")]
mod tray;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum ViewFilter {
    All,
    Favorites,
    Recent,
    Group(Uuid),
}

#[derive(Clone, Copy, PartialEq, Eq)]
enum Feedback { Info, Success, Error, Warning }

struct ManagerView {
    manager: Manager,
    hosts: Vec<Host>,
    groups: Vec<Group>,
    selected: Option<Uuid>,
    filter: ViewFilter,
    editor_group: Option<Uuid>,
    group_picker_open: bool,
    actions_open: bool,
    collapsed_groups: HashSet<Uuid>,
    appearance: Appearance,
    search: Entity<InputState>,
    group_input: Entity<InputState>,
    name: Entity<InputState>,
    alias: Entity<InputState>,
    hostname: Entity<InputState>,
    username: Entity<InputState>,
    port: Entity<InputState>,
    identity: Entity<InputState>,
    jump: Entity<InputState>,
    tags: Entity<InputState>,
    notes: Entity<InputState>,
    favorite: bool,
    message: String,
    feedback: Feedback,
    confirm_delete: bool,
    _subscription: Subscription,
    _appearance_subscription: Subscription,
}

fn make_input(window: &mut Window, cx: &mut Context<ManagerView>, hint: &'static str) -> Entity<InputState> {
    cx.new(|cx| InputState::new(window, cx).placeholder(hint))
}

// Indentation and expansion live entirely in the UI; parent_id is stored in SQLite.
fn nested_groups(
    groups: &[Group], parent: Option<Uuid>, depth: usize, collapsed: &HashSet<Uuid>, out: &mut Vec<(Group,usize)>,
) {
    if depth > 24 { return; }
    for group in groups.iter().filter(|g| g.parent_id == parent) {
        out.push((group.clone(), depth));
        if !collapsed.contains(&group.id) {
            nested_groups(groups, Some(group.id), depth+1, collapsed, out);
        }
    }
}

fn is_descendant(groups: &[Group], id: Option<Uuid>, target: Uuid) -> bool {
    let mut cursor=id;
    for _ in 0..=groups.len() {
        let Some(group_id)=cursor else {return false};
        if group_id == target {return true;}
        cursor=groups.iter().find(|g|g.id==group_id).and_then(|g|g.parent_id);
    }
    false // broken parent cycle: fail closed
}

impl ManagerView {
    fn new(window: &mut Window, cx: &mut Context<Self>) -> Self {
        let manager=Manager::discover().expect("unable to open local database");
        let hosts=manager.db.list_hosts().unwrap_or_default();
        let groups=manager.db.list_groups().unwrap_or_default();
        let appearance=Appearance::read(&manager.paths.data_dir);
        let search=make_input(window,cx,"搜索名称、IP 或 SSH 别名...");
        let subscription=cx.subscribe_in(&search,window,|_,_,event:&InputEvent,_,cx| {
            if matches!(event,InputEvent::Change) {cx.notify();}
        });
        let appearance_subscription=cx.observe_window_appearance(window,|this,window,cx| {
            if this.appearance==Appearance::System {
                Theme::change(this.appearance.mode(window.appearance()),Some(window),cx);
                cx.notify();
            }
        });
        let first_host = hosts.first().map(|host| host.id);
        let mut view = Self {
            manager,hosts,groups,selected:None,filter:ViewFilter::All,
            editor_group:None,group_picker_open:false,actions_open:false,collapsed_groups:HashSet::new(),appearance,search,
            group_input:make_input(window,cx,"新建分组名称"),
            name:make_input(window,cx,"服务器显示名称"),
            alias:make_input(window,cx,"prod-api-01"),
            hostname:make_input(window,cx,"192.168.1.10"),
            username:make_input(window,cx,"ubuntu"),
            port:make_input(window,cx,"22"),
            identity:make_input(window,cx,"~/.ssh/id_ed25519"),
            jump:make_input(window,cx,"可选跳板机别名"),
            tags:make_input(window,cx,"api, production"),
            notes:cx.new(|cx| InputState::new(window,cx).placeholder("添加服务器备注...").multi_line(true)),
            favorite:false,confirm_delete:false,
            message:"请选择服务器；新建自管主机前需先初始化 SSH 集成。".into(),
            feedback:Feedback::Info,
            _subscription:subscription,_appearance_subscription:appearance_subscription,
        };
        if let Some(id) = first_host { view.select_host(id, window, cx); }
        view
    }

    fn refresh(&mut self,cx:&mut Context<Self>) {
        match (self.manager.db.list_hosts(),self.manager.db.list_groups()) {
            (Ok(hosts),Ok(groups))=> {self.hosts=hosts;self.groups=groups;cx.notify();},
            (Err(e),_)|(_,Err(e))=> self.message=format!("读取数据失败：{e:#}"),
        }
    }

    fn set_input(input:&Entity<InputState>,value:&str,window:&mut Window,cx:&mut Context<Self>) {
        input.update(cx,|state,cx|state.set_value(value.to_string(),window,cx));
    }
    fn read(input:&Entity<InputState>,cx:&Context<Self>)->String {
        input.read(cx).value().to_string()
    }

    fn select_host(&mut self,id:Uuid,window:&mut Window,cx:&mut Context<Self>) {
        let Some(host)=self.hosts.iter().find(|h|h.id==id).cloned() else {return};
        self.selected=Some(id);
        self.editor_group=host.group_id;
        self.group_picker_open=false;
        self.favorite=host.favorite;
        self.confirm_delete=false;
        self.feedback=Feedback::Info;
        Self::set_input(&self.name,&host.name,window,cx);
        Self::set_input(&self.alias,&host.alias,window,cx);
        Self::set_input(&self.hostname,&host.hostname,window,cx);
        Self::set_input(&self.username,&host.username,window,cx);
        Self::set_input(&self.port,&host.port.to_string(),window,cx);
        Self::set_input(&self.identity,host.identity_file.as_deref().unwrap_or(""),window,cx);
        Self::set_input(&self.jump,host.proxy_jump.as_deref().unwrap_or(""),window,cx);
        match self.manager.db.host_annotations(id) {
            Ok((tags,notes)) => {
                Self::set_input(&self.tags,&tags,window,cx);
                Self::set_input(&self.notes,&notes,window,cx);
            },
            Err(err) => self.message=format!("读取标签和备注失败：{err:#}"),
        }
        self.message=if host.source==HostSource::Imported {
            "导入主机：连接参数只读，可修改名称、分组、标签、备注和收藏。".into()
        } else {"可以编辑连接参数，点击「保存更改」生效。".into()};
        cx.notify();
    }

    fn new_host(&mut self,window:&mut Window,cx:&mut Context<Self>) {
        self.selected=None;
        self.favorite=false;
        self.editor_group=match self.filter {ViewFilter::Group(id)=>Some(id),_=>None};
        self.group_picker_open=false;
        self.confirm_delete=false;
        self.feedback=Feedback::Info;
        for input in [&self.name,&self.alias,&self.hostname,&self.username,&self.identity,&self.jump,&self.tags,&self.notes] {
            Self::set_input(input,"",window,cx);
        }
        Self::set_input(&self.port,"22",window,cx);
        self.message="正在新增主机。填写右侧资料后点击保存。".into();
        cx.notify();
    }

    fn save(&mut self,_:&ClickEvent,_:&mut Window,cx:&mut Context<Self>) {
        // Placeholder values are examples, never actual SSH input.
        let name=Self::read(&self.name,cx);
        let alias=Self::read(&self.alias,cx);
        let host=Self::read(&self.hostname,cx);
        let user=Self::read(&self.username,cx);
        let problem=if name.trim().is_empty() {Some("请填写显示名称。")}
            else if alias.trim().is_empty() {Some("请填写 SSH 别名，例如 prod-api-01；灰色文字仅是示例。")}
            else if wsm_core::ssh::validate_alias(alias.trim()).is_err() {
                Some("SSH 别名必须以字母或数字开头，仅可包含字母、数字、点、下划线和连字符。")
            } else if host.trim().is_empty() {Some("请填写主机名或 IP 地址。")}
            else if user.trim().is_empty() {Some("请填写 SSH 登录用户名。")}
            else {None};
        if let Some(error)=problem {
            self.feedback=Feedback::Error;
            self.message=error.into();
            cx.notify();
            return;
        }
        let port=match Self::read(&self.port,cx).parse::<u16>() {
            Ok(v) if v>0=>v,
            _=>{self.feedback=Feedback::Error;self.message="端口必须在 1～65535 之间。".into();cx.notify();return;}
        };
        let optional=|s:String| if s.trim().is_empty(){None}else{Some(s.trim().to_string())};
        let fields=HostInput {
            name:Self::read(&self.name,cx).trim().into(),
            alias:Self::read(&self.alias,cx).trim().into(),
            hostname:Self::read(&self.hostname,cx).trim().into(),
            username:Self::read(&self.username,cx).trim().into(),
            port,identity_file:optional(Self::read(&self.identity,cx)),
            proxy_jump:optional(Self::read(&self.jump,cx)),
            group_id:self.editor_group,favorite:self.favorite,
        };
        let result=if let Some(id)=self.selected {
            match self.manager.db.get_host(id) {
                Ok(Some(mut current)) => {
                    // Imported SSH connection details must not be modified.
                    if current.source==HostSource::Managed {
                        current.alias=fields.alias;
                        current.hostname=fields.hostname;
                        current.username=fields.username;
                        current.port=fields.port;
                        current.identity_file=fields.identity_file;
                        current.proxy_jump=fields.proxy_jump;
                    }
                    current.name=fields.name;
                    current.group_id=fields.group_id;
                    current.favorite=fields.favorite;
                    self.manager.update_host(current).map(|_|id)
                },
                Ok(None)=>Err(anyhow::anyhow!("主机不存在")),
                Err(err)=>Err(err),
            }
        } else { self.manager.add_managed(fields).map(|host|host.id) };
        match result {
            Ok(id)=>{
                let tags=Self::read(&self.tags,cx);
                let notes=Self::read(&self.notes,cx);
                match self.manager.db.save_annotations(id,tags.trim(),notes.trim()) {
                    Ok(())=>{self.feedback=Feedback::Success;self.message="主机及备注已保存，配置已同步。".into()},
                    Err(err)=>{self.feedback=Feedback::Warning;self.message=format!("主机已保存，但标签/备注保存失败：{err:#}")},
                }
                self.selected=Some(id);
                self.refresh(cx);
            },
            Err(err)=>{
                self.feedback=Feedback::Error;
                let raw=format!("{err:#}");
                self.message=if raw.contains("wsm init") {
                    "保存失败：请先点击顶部「⚙」→「初始化 SSH」，然后再试。".into()
                } else if raw.contains("SSH alias") {
                    "保存失败：SSH 别名格式无效或已存在，请检查别名字段。".into()
                } else {format!("保存失败：{raw}")};
            },
        }
        cx.notify();
    }

    fn remove(&mut self,_:&ClickEvent,window:&mut Window,cx:&mut Context<Self>) {
        let Some(id)=self.selected else {return};
        if !self.confirm_delete {
            self.confirm_delete=true;
            self.feedback=Feedback::Warning;
            self.message="再次点击删除按钮以确认删除该主机。".into();
            cx.notify();return;
        }
        match self.manager.delete_host(id) {
            Ok(())=>{
                self.new_host(window,cx);
                self.feedback=Feedback::Success;
                self.message="主机已删除。导入的用户 SSH 配置文件没有被修改。".into();
                self.refresh(cx);
            },
            Err(err)=>{self.feedback=Feedback::Error;self.message=format!("删除失败：{err:#}")},
        }
        cx.notify();
    }

    fn connect(&mut self,_:&ClickEvent,_:&mut Window,cx:&mut Context<Self>) {
        let Some(id)=self.selected else {
            self.feedback=Feedback::Warning;
            self.message="请先保存主机，再点击 Open in Warp。".into();cx.notify();return;
        };
        match self.manager.connect(id,false,false) {
            Ok(())=>{
                self.feedback=Feedback::Success;
                self.message="已请求 Warp 打开标签页；SSH 认证由 Warp/OpenSSH 负责。".into();
                self.refresh(cx);
            },
            Err(err)=>{self.feedback=Feedback::Error;self.message=format!("启动连接失败：{err:#}")},
        }
        cx.notify();
    }

    fn import(&mut self,_:&ClickEvent,_:&mut Window,cx:&mut Context<Self>) {
        match self.manager.import_ssh() {
            Ok((added,updated,errors))=>self.message=format!("导入 {added} 台，更新 {updated} 台，跳过 {} 项；原 SSH 文件保持只读。",errors.len()),
            Err(err)=>self.message=format!("导入失败：{err:#}"),
        }
        self.feedback=if self.message.starts_with("导入失败") {Feedback::Error} else {Feedback::Success};
        self.refresh(cx);
    }

    fn init(&mut self,_:&ClickEvent,_:&mut Window,cx:&mut Context<Self>) {
        match self.manager.initialize_ssh() {
            Ok(true)=>self.message="已启用 SSH 集成，并备份现有 SSH Config。".into(),
            Ok(false)=>self.message="SSH 集成已经启用。".into(),
            Err(err)=>self.message=format!("初始化失败：{err:#}"),
        }
        self.feedback=if self.message.starts_with("初始化失败") {Feedback::Error} else {Feedback::Success};
        cx.notify();
    }

    fn sync(&mut self,_:&ClickEvent,_:&mut Window,cx:&mut Context<Self>) {
        match self.manager.sync_existing_tabs() {
            Ok(count)=>self.message=format!("已同步 {count} 条已生成或收藏的 Warp Tab Config。"),
            Err(err)=>self.message=format!("同步失败：{err:#}"),
        }
        self.feedback=if self.message.starts_with("同步失败") {Feedback::Error} else {Feedback::Success};
        cx.notify();
    }

    fn add_group(&mut self,_:&ClickEvent,_:&mut Window,cx:&mut Context<Self>) {
        let name=Self::read(&self.group_input,cx);
        let parent=match self.filter {ViewFilter::Group(id)=>Some(id),_=>None};
        match self.manager.group_add(name.trim(),parent) {
            Ok(group)=>{
                self.filter=ViewFilter::Group(group.id);
                self.message=format!("已创建分组「{}」。",group.name);
                self.refresh(cx);
            },
            Err(err)=>self.message=format!("创建分组失败：{err:#}"),
        }
        self.feedback=if self.message.starts_with("创建分组失败") {Feedback::Error} else {Feedback::Success};
        cx.notify();
    }


    fn remove_tag(&mut self, tag_to_remove: &str, window: &mut Window, cx: &mut Context<Self>) {
        let values=Self::read(&self.tags,cx);
        let mut removed=false;
        let result=values.split(',').map(str::trim)
            .filter(|item| !item.is_empty())
            .filter(|item| {
                if !removed && *item == tag_to_remove { removed=true; false } else { true }
            })
            .collect::<Vec<_>>().join(", ");
        Self::set_input(&self.tags,&result,window,cx);
        cx.notify();
    }

    fn toggle_favorite(&mut self,_:&ClickEvent,_:&mut Window,cx:&mut Context<Self>) {
        self.favorite=!self.favorite;
        cx.notify();
    }

    fn toggle_list_favorite(&mut self,id:Uuid,cx:&mut Context<Self>) {
        if let Some(mut host)=self.hosts.iter().find(|h|h.id==id).cloned() {
            host.favorite=!host.favorite;
            match self.manager.update_host(host.clone()) {
                Ok(())=>{
                    if self.selected==Some(id) {self.favorite=host.favorite;}
                    self.refresh(cx);
                },
                Err(err)=>self.message=format!("更新收藏失败：{err:#}"),
            }
        }
        cx.notify();
    }

    fn group_label(&self,id:Option<Uuid>)->String {
        id.and_then(|id|self.groups.iter().find(|g|g.id==id))
            .map(|g|g.name.clone()).unwrap_or_else(||"未分组".into())
    }

    fn filtered(&self,host:&Host,search:&str)->bool {
        let matches=match self.filter {
            ViewFilter::All=>true,
            ViewFilter::Favorites=>host.favorite,
            ViewFilter::Recent=>host.last_connected.is_some(),
            ViewFilter::Group(id)=>is_descendant(&self.groups,host.group_id,id),
        };
        matches && (search.is_empty() || [&host.name,&host.alias,&host.hostname]
            .iter().any(|text|text.to_lowercase().contains(search)))
    }

    fn set_theme(&mut self,choice:Appearance,window:&mut Window,cx:&mut Context<Self>) {
        self.appearance=choice;
        Theme::change(choice.mode(window.appearance()),Some(window),cx);
        if let Err(err)=choice.save(&self.manager.paths.data_dir) {
            self.message=format!("主题已切换，但保存主题偏好失败：{err}");
        }
        cx.notify();
    }
}

// Reusable, semantic styles keep Dark, Light and System modes visually identical.
// macOS chrome stays native. Never draw a second set of traffic-light buttons.
fn detail_field(label: &'static str, input: &Entity<InputState>, readonly: bool, p: Palette) -> impl IntoElement {
    // The GPUI component input already draws a focus ring and border: avoid double frames.
    div().h_flex().items_center().gap_3()
        .child(div().w(px(105.)).text_sm().text_color(rgb(p.secondary)).child(label))
        .child(div().flex_1().min_w_0().child(Input::new(input).disabled(readonly)))
}

fn environment(name: &str, p: Palette) -> impl IntoElement {
    let value = name.to_ascii_lowercase();
    let (bg, fg) = if value.contains("prod") || value.contains("生产") {
        (p.prod_surface, p.prod_foreground)
    } else if value.contains("stag") || value.contains("test") || value.contains("测试") {
        (p.stage_surface, p.stage_foreground)
    } else if value.contains("dev") || value.contains("开发") {
        (p.dev_surface, p.dev_foreground)
    } else { (p.chip, p.secondary) };
    div().px_2().py_1().rounded_md().bg(rgb(bg))
        .text_xs().font_semibold().text_color(rgb(fg)).child(name.to_owned())
}

fn sidebar_row(icon: IconName, text: &'static str, count: usize, active: bool, p: Palette) -> impl IntoElement {
    div().h_flex().items_center().justify_between().rounded_lg().px_3().py_3()
        .bg(rgb(if active { p.selected } else { p.sidebar }))
        .child(div().h_flex().items_center().gap_2().text_sm().font_semibold()
            .text_color(rgb(if active { p.accent } else { p.primary }))
            .child(Icon::new(icon)).child(text))
        .child(div().px_2().py_1().rounded_full()
            .bg(rgb(if active { p.control } else { p.chip })).text_xs()
            .text_color(rgb(if active { p.accent } else { p.secondary }))
            .child(count.to_string()))
}

impl Render for ManagerView {
    fn render(&mut self, window: &mut Window, cx: &mut Context<Self>) -> impl IntoElement {
        let p = Palette::new(self.appearance.dark(window.appearance()));
        let search = Self::read(&self.search, cx).trim().to_lowercase();
        let selected_source = self.selected.and_then(|id| self.hosts.iter().find(|h| h.id == id).map(|h| h.source));
        let imported = selected_source == Some(HostSource::Imported);
        let selected_is_host = self.selected.is_some();
        let host_count = self.hosts.len();
        let favorite_count = self.hosts.iter().filter(|h| h.favorite).count();
        let recent_count = self.hosts.iter().filter(|h| h.last_connected.is_some()).count();
        let current_filter = self.filter;

        let mut folder_items = div().v_flex().gap_1();
        folder_items = folder_items
            .child(div().cursor_pointer()
                .child(sidebar_row(IconName::SquareTerminal, "All Servers", host_count, current_filter == ViewFilter::All, p))
                .id("main-interaction-001").on_click(cx.listener(|this, _, _, cx| { this.filter = ViewFilter::All; cx.notify(); })))
            .child(div().cursor_pointer()
                .child(sidebar_row(IconName::Star, "Favorites", favorite_count, current_filter == ViewFilter::Favorites, p))
                .id("main-interaction-002").on_click(cx.listener(|this, _, _, cx| { this.filter = ViewFilter::Favorites; cx.notify(); })))
            .child(div().cursor_pointer()
                .child(sidebar_row(IconName::Calendar, "Recent", recent_count, current_filter == ViewFilter::Recent, p))
                .id("main-interaction-003").on_click(cx.listener(|this, _, _, cx| { this.filter = ViewFilter::Recent; cx.notify(); })));

        let mut flat = Vec::new();
        nested_groups(&self.groups, None, 0, &self.collapsed_groups, &mut flat);
        for group in self.groups.iter().filter(|g| g.parent_id.is_some()
            && !self.groups.iter().any(|parent| Some(parent.id) == g.parent_id)) {
            flat.push((group.clone(), 0));
        }
        let mut group_list = div().v_flex().gap_1();
        if self.groups.is_empty() {
            group_list = group_list.child(
                div().v_flex().items_center().gap_2().rounded_lg()
                    .border_1().border_color(rgb(p.border)).bg(rgb(p.control))
                    .px_3().py_5()
                    .child(div().text_lg().text_color(rgb(p.tertiary)).child(Icon::new(IconName::Folder)))
                    .child(div().text_sm().font_semibold().text_color(rgb(p.secondary)).child("还没有分组"))
                    .child(div().text_xs().text_color(rgb(p.tertiary)).child("在下方创建分组，整理服务器"))
            );
        }
        for (group, level) in flat {
            let id = group.id;
            let children = self.groups.iter().any(|g| g.parent_id == Some(id));
            let expanded = !self.collapsed_groups.contains(&id);
            let count = self.hosts.iter().filter(|h| is_descendant(&self.groups, h.group_id, id)).count();
            let active = current_filter == ViewFilter::Group(id);
            group_list = group_list.child(
                div().h_flex().items_center().rounded_md().px_2().py_2()
                    .ml(px(level as f32 * 12.))
                    .bg(rgb(if active { p.selected } else { p.sidebar }))
                    .child(div().w(px(18.)).text_xs().text_color(rgb(p.secondary)).cursor_pointer()
                        .child(if children { if expanded { "▾" } else { "▸" } } else { "·" })
                        .id(SharedString::from(format!("group-collapse-{id}"))).on_click(cx.listener(move |this, _, _, cx| {
                            if !this.collapsed_groups.insert(id) { this.collapsed_groups.remove(&id); }
                            cx.notify();
                        })))
                    .child(div().flex_1().min_w_0().cursor_pointer().text_sm()
                        .text_color(rgb(if active { p.accent } else { p.primary }))
                        .child(div().h_flex().items_center().gap_2()
                            .child(Icon::new(IconName::Folder))
                            .child(group.name.clone()))
                        .id(SharedString::from(format!("group-select-{id}"))).on_click(cx.listener(move |this, _, _, cx| { this.filter = ViewFilter::Group(id); cx.notify(); })))
                    .child(div().rounded_full().bg(rgb(p.chip)).px_2().py_1()
                        .text_xs().text_color(rgb(p.secondary)).child(count.to_string()))
            );
        }

        let mut filtered: Vec<Host> = self.hosts.iter().filter(|h| self.filtered(h, &search)).cloned().collect();
        if current_filter == ViewFilter::Recent { filtered.sort_by(|a, b| b.last_connected.cmp(&a.last_connected)); }
        let filtered_count = filtered.len();
        let mut connections = div().v_flex().gap_1();
        for host in filtered {
            let id = host.id;
            let active = self.selected == Some(id);
            let label = self.group_label(host.group_id);
            let starred = host.favorite;
            // GPUI interactive IDs must be unique per sibling; the old static ID
            // was reused for all rows, which broke click targeting.
            connections = connections.child(
                div().id(SharedString::from(format!("connection-row-{id}")))
                    .h_flex().items_center().gap_2().rounded_lg()
                    .px_2().py_2().cursor_pointer()
                    .border_1().border_color(rgb(if active { p.selected_border } else { p.list }))
                    .bg(rgb(if active { p.selected } else { p.list }))
                    .hover(|style| style.bg(rgb(if active { p.selected } else { p.chip })))
                    .child(div().w(px(32.)).h(px(32.)).rounded_md()
                        .bg(rgb(if active { p.prod_surface } else { p.control }))
                        .flex().items_center().justify_center()
                        .text_color(rgb(if active { p.accent } else { p.secondary }))
                        .child(Icon::new(IconName::SquareTerminal)))
                    .child(div().flex_1().min_w_0().v_flex().gap_1()
                        .child(div().text_sm().font_semibold()
                            .text_color(rgb(if active { p.accent } else { p.primary }))
                            .child(host.name.clone()))
                        .child(div().text_xs().text_color(rgb(p.tertiary))
                            .child(host.hostname.clone())))
                    .child(environment(&label, p))
                    .child(div().id(SharedString::from(format!("connection-star-{id}")))
                        .cursor_pointer().px_2().py_2().rounded_md().text_lg()
                        .text_color(rgb(if starred { 0xEAA830 } else { p.tertiary }))
                        .child(Icon::new(if starred { IconName::Star } else { IconName::StarOff }))
                        .on_click(cx.listener(move |this, _, _, cx| {
                            cx.stop_propagation();
                            this.toggle_list_favorite(id, cx);
                        })))
                    .on_click(cx.listener(move |this, event: &ClickEvent, window, cx| {
                        this.select_host(id, window, cx);
                        if event.click_count() >= 2 {
                            this.connect(event, window, cx);
                        }
                    }))
            );
        }
        if filtered_count == 0 {
            connections = connections.child(div().py_8().v_flex().items_center().gap_2()
                .child(div().text_2xl().text_color(rgb(p.tertiary)).child("⌕"))
                .child(div().text_sm().text_color(rgb(p.secondary)).child("没有找到匹配的服务器"))
                .child(div().text_xs().text_color(rgb(p.tertiary))
                    .child("试试其他关键词，或点击右上角「新建主机」")));
        }

        let mut group_picker = div().v_flex().gap_1()
            .child(div().h_flex().items_center().gap_3()
                .child(div().w(px(105.)).text_sm().text_color(rgb(p.secondary)).child("所属分组"))
                .child(div().h_flex().flex_1().min_w_0().items_center().rounded_md().border_1()
                    .border_color(rgb(p.border)).bg(rgb(p.control)).px_3().py_2().cursor_pointer()
                    .child(Icon::new(IconName::Folder))
                    .child(div().flex_1().text_sm().text_color(rgb(p.primary))
                        .child(self.group_label(self.editor_group)))
                    .child(Icon::new(if self.group_picker_open { IconName::ChevronUp } else { IconName::ChevronDown }))
                    .id("main-interaction-008").on_click(cx.listener(|this, _, _, cx| { this.group_picker_open = !this.group_picker_open; cx.notify(); }))));
        if self.group_picker_open {
            group_picker = group_picker.child(div().cursor_pointer().rounded_md().px_3().py_2()
                .text_xs().text_color(rgb(p.secondary)).bg(rgb(p.chip))
                .child("未分组")
                .id("main-interaction-009").on_click(cx.listener(|this, _, _, cx| { this.editor_group = None; this.group_picker_open = false; cx.notify(); })));
            for group in &self.groups {
                let id = group.id;
                let selected = self.editor_group == Some(id);
                group_picker = group_picker.child(
                    div().cursor_pointer().rounded_md().px_3().py_2()
                        .bg(rgb(if selected { p.selected } else { p.control }))
                        .text_xs().text_color(rgb(if selected { p.accent } else { p.secondary }))
                        .child(div().h_flex().items_center().gap_2()
                            .child(Icon::new(if selected { IconName::CircleCheck } else { IconName::Folder }))
                            .child(group.name.clone()))
                        .id(SharedString::from(format!("group-picker-{id}"))).on_click(cx.listener(move |this, _, _, cx| { this.editor_group = Some(id); this.group_picker_open = false; cx.notify(); }))
                );
            }
        }

        // Tag chips are only a visual representation. The same comma-separated value
        // remains editable through the input beneath them, and is persisted to SQLite.
        let raw_tags = Self::read(&self.tags, cx);
        let mut tag_chips = div().h_flex().gap_2();
        for (index,tag) in raw_tags.split(',').map(str::trim).filter(|tag| !tag.is_empty()).take(4).enumerate() {
            let tag_name=tag.to_owned();
            tag_chips = tag_chips.child(div().h_flex().items_center().gap_1().rounded_md()
                .bg(rgb(p.chip)).px_2().py_1()
                .child(div().text_xs().font_semibold().text_color(rgb(p.secondary))
                    .child(tag_name.clone()))
                .child(div().id(SharedString::from(format!("tag-remove-{index}")))
                    .cursor_pointer().px_1().text_color(rgb(p.tertiary))
                    .child(Icon::new(IconName::Close).xsmall())
                    .on_click(cx.listener(move |this, _, window, cx| {
                        this.remove_tag(&tag_name,window,cx);
                    }))));
        }
        let tags_field = div().h_flex().items_center().gap_3()
            .child(div().w(px(105.)).text_sm().text_color(rgb(p.secondary)).child("标签"))
            .child(div().v_flex().flex_1().min_w_0().gap_2()
                .child(Input::new(&self.tags))
                .when(!raw_tags.trim().is_empty(), |el| el.child(tag_chips)));

        let doctor = self.manager.doctor().ok();
        let linked = doctor.as_ref().map(|d| d.include_enabled).unwrap_or(false);
        let warp_ready = self.manager.paths.warp_configs.exists();
        let (banner_bg,banner_fg,banner_icon,banner_title)=match self.feedback {
            Feedback::Error => (p.danger_surface,p.danger,"!","操作失败"),
            Feedback::Warning => (p.stage_surface,p.stage_foreground,"!","请确认"),
            Feedback::Success => (p.dev_surface,p.dev_foreground,"✓","操作成功"),
            Feedback::Info => (p.chip,p.secondary,"i","提示"),
        };
        let banner=div().h_flex().items_center().gap_2().mx_4().mt_3().px_3().py_2()
            .rounded_lg().border_1().border_color(rgb(banner_fg)).bg(rgb(banner_bg))
            .child(div().w(px(20.)).h(px(20.)).rounded_full().bg(rgb(banner_fg))
                .text_color(rgb(p.inspector)).font_semibold().flex().items_center().justify_center()
                .child(banner_icon))
            .child(div().text_sm().font_semibold().text_color(rgb(banner_fg)).child(banner_title))
            .child(div().flex_1().min_w_0().text_sm().text_color(rgb(p.primary))
                .child(self.message.clone()))
            .child(div().id("feedback-dismiss").cursor_pointer().px_1().py_1()
                .text_color(rgb(banner_fg))
                .child(Icon::new(IconName::Close).small())
                .on_click(cx.listener(|this,_,_,cx| { this.feedback=Feedback::Info; cx.notify(); })));
        let status_color = if linked { p.success } else { p.tertiary };
        let tab_color = if warp_ready { p.success } else { p.tertiary };

        let mut secondary_actions = div().h_flex().items_center().gap_2().px_4().py_2()
            .bg(rgb(p.titlebar)).border_b_1().border_color(rgb(p.border));
        if self.actions_open {
            secondary_actions = secondary_actions
                .child(div().text_xs().text_color(rgb(p.secondary)).mr_3().child("配置管理"))
                .child(div().cursor_pointer().rounded_md().px_3().py_2().bg(rgb(p.control))
                    .hover(|style| style.bg(rgb(p.chip)))
                    .text_xs().child("初始化 SSH").id("main-interaction-011").on_click(cx.listener(Self::init)))
                .child(div().cursor_pointer().rounded_md().px_3().py_2().bg(rgb(p.control))
                    .hover(|style| style.bg(rgb(p.chip)))
                    .text_xs().child("导入 SSH Config").id("main-interaction-012").on_click(cx.listener(Self::import)))
                .child(div().cursor_pointer().rounded_md().px_3().py_2().bg(rgb(p.control))
                    .hover(|style| style.bg(rgb(p.chip)))
                    .text_xs().child("同步 Tab Configs").id("main-interaction-013").on_click(cx.listener(Self::sync)))
                .child(div().flex_1())
                .child(div().cursor_pointer().text_xs().text_color(rgb(p.tertiary))
                    .child("关闭 ×")
                    .id("main-interaction-014").on_click(cx.listener(|this, _, _, cx| { this.actions_open = false; cx.notify(); })));
        }

        div().size_full().v_flex().bg(rgb(p.app)).text_color(rgb(p.primary))
            // A minimal toolbar, matching the reference image; native macOS window controls
            // are supplied by the host system rather than duplicated in GPUI content.
            .child(div().h_flex().items_center().justify_between().px_5().py_3()
                .bg(rgb(p.titlebar)).border_b_1().border_color(rgb(p.border))
                .child(div().h_flex().items_center().gap_3()
                    .child(div().w(px(30.)).h(px(30.)).rounded_lg().bg(rgb(p.accent))
                        .flex().items_center().justify_center()
                        .text_color(rgb(p.accent_foreground)).font_semibold().child(Icon::new(IconName::SquareTerminal)))
                    .child(div().v_flex().gap_1()
                        .child(div().text_sm().font_semibold().child("Warp SSH Manager"))
                        .child(div().text_xs().text_color(rgb(p.tertiary)).child("SSH Workspace"))))
                .child(div().h_flex().items_center().gap_2()
                    .child(div().h_flex().gap_1().p_1().rounded_lg()
                        .bg(rgb(p.control)).border_1().border_color(rgb(p.border))
                        .child(div().cursor_pointer().rounded_md().px_2().py_1()
                            .bg(rgb(if self.appearance == Appearance::System { p.selected } else { p.control }))
                            .text_color(rgb(if self.appearance == Appearance::System { p.accent } else { p.secondary }))
                            .text_xs().child("自动")
                            .id("main-interaction-015").on_click(cx.listener(|this, _, window, cx| this.set_theme(Appearance::System, window, cx))))
                        .child(div().cursor_pointer().rounded_md().px_2().py_1()
                            .bg(rgb(if self.appearance == Appearance::Dark { p.selected } else { p.control }))
                            .text_color(rgb(if self.appearance == Appearance::Dark { p.accent } else { p.secondary }))
                            .text_xs().child("☾ 深色")
                            .id("main-interaction-016").on_click(cx.listener(|this, _, window, cx| this.set_theme(Appearance::Dark, window, cx))))
                        .child(div().cursor_pointer().rounded_md().px_2().py_1()
                            .bg(rgb(if self.appearance == Appearance::Light { p.selected } else { p.control }))
                            .text_color(rgb(if self.appearance == Appearance::Light { p.accent } else { p.secondary }))
                            .text_xs().child("☀ 浅色")
                            .id("main-interaction-017").on_click(cx.listener(|this, _, window, cx| this.set_theme(Appearance::Light, window, cx)))))
                    .child(div().cursor_pointer().rounded_md().px_3().py_2()
                        .bg(rgb(p.accent)).hover(|style| style.bg(rgb(p.selected_border)))
                        .text_color(rgb(p.accent_foreground)).text_sm().font_semibold()
                        .child("+ 新建主机")
                        .id("main-interaction-018").on_click(cx.listener(|this, _, window, cx| this.new_host(window, cx))))
                    .child(div().cursor_pointer().rounded_md().px_3().py_2()
                        .bg(rgb(p.control)).hover(|style| style.bg(rgb(p.chip)))
                        .text_color(rgb(p.secondary)).text_sm()
                        .child(Icon::new(IconName::Settings))
                        .id("main-interaction-019").on_click(cx.listener(|this, _, _, cx| { this.actions_open = !this.actions_open; cx.notify(); })))))
            .when(self.actions_open, |el| el.child(secondary_actions))
            // One continuous three-column layout. Each pane owns its scrolling area.
            .child(div().h_flex().flex_1().min_h_0().items_start()
                .child(div().w(px(246.)).h_full().v_flex().min_h_0().bg(rgb(p.sidebar))
                    .border_r_1().border_color(rgb(p.border)).p_4().gap_3()
                    .child(div().h_flex().items_center().justify_between()
                        .child(div().text_sm().font_semibold().text_color(rgb(p.primary)).child("Folders"))
                        .child(div().text_xs().text_color(rgb(p.tertiary)).child("WORKSPACE")))
                    .child(folder_items)
                    .child(div().mt_3().mb_1().h_flex().items_center().justify_between()
                        .child(div().text_xs().font_semibold().text_color(rgb(p.tertiary)).child("GROUPS"))
                        .child(div().text_xs().text_color(rgb(p.tertiary)).child(self.groups.len().to_string())))
                    .child(div().flex_1().overflow_y_scrollbar().child(group_list))
                    .child(div().h_flex().items_center().gap_2()
                        .child(div().flex_1().min_w_0().rounded_md().border_1().border_color(rgb(p.border))
                            .bg(rgb(p.control)).child(Input::new(&self.group_input)))
                        .child(div().cursor_pointer().rounded_md().bg(rgb(p.accent))
                            .text_color(rgb(p.accent_foreground)).text_xs().font_semibold()
                            .px_2().py_2().child("创建")
                            .id("main-interaction-020").on_click(cx.listener(Self::add_group)))))
                .child(div().w(px(408.)).h_full().v_flex().min_h_0().bg(rgb(p.list))
                    .border_r_1().border_color(rgb(p.border)).p_4().gap_3()
                    .child(div().h_flex().items_center().justify_between()
                        .child(div().text_lg().font_semibold().text_color(rgb(p.primary)).child("Connections"))
                        .child(div().rounded_full().px_2().py_1().bg(rgb(p.chip)).text_xs().text_color(rgb(p.secondary)).child(format!("{} 台", filtered_count))))
                    .child(div().rounded_lg().bg(rgb(p.control))
                        .child(Input::new(&self.search).prefix(Icon::new(IconName::Search).small())))
                    .child(div().text_xs().text_color(rgb(p.tertiary))
                        .child("单击查看详情   ·   双击在 Warp 中连接"))
                    .child(div().flex_1().min_h_0().overflow_y_scrollbar().child(connections)))
                .child(div().flex_1().min_w_0().h_full().v_flex().min_h_0().bg(rgb(p.inspector))
                    .child(div().h_flex().items_center().justify_between().px_4().py_3()
                        .border_b_1().border_color(rgb(p.border))
                        .child(div().v_flex().gap_1()
                            .child(div().text_lg().font_semibold()
                                .child(if selected_is_host { "Server Details" } else { "New Server" }))
                            .child(div().text_xs().text_color(rgb(p.tertiary))
                                .child(if imported { "Imported · 连接字段只读" } else { "Managed · OpenSSH" })))
                        .child(div().text_xs().text_color(rgb(if self.favorite { 0xF4B532 } else { p.tertiary }))
                            .child(if self.favorite { "★ 已收藏" } else { "☆ 未收藏" })))
                    .when(self.feedback != Feedback::Info, |el| el.child(banner))
                    .child(div().flex_1().min_h_0().overflow_y_scrollbar().px_5().py_3()
                        .child(div().v_flex().gap_2()
                            .child(div().h_flex().items_center().gap_2().py_2()
                                .child(div().w(px(3.)).h(px(14.)).rounded_full().bg(rgb(p.accent)))
                                .child(div().text_xs().font_semibold().text_color(rgb(p.tertiary))
                                    .child("CONNECTION SETTINGS")))
                            .child(detail_field("显示名称", &self.name, false, p))
                            .child(detail_field("SSH 别名", &self.alias, imported, p))
                            .child(detail_field("主机名 / IP", &self.hostname, imported, p))
                            .child(detail_field("用户名", &self.username, imported, p))
                            .child(detail_field("端口", &self.port, imported, p))
                            .child(detail_field("身份文件", &self.identity, imported, p))
                            .child(group_picker)
                            .child(tags_field)
                            .child(detail_field("ProxyJump", &self.jump, imported, p))
                            .child(detail_field("备注", &self.notes, false, p))
                            .child(div().h_flex().items_center().justify_between().px_1().py_2()
                                .child(div().text_sm().text_color(rgb(p.secondary)).child("设为收藏"))
                                .child(div().cursor_pointer().rounded_full().px_3().py_2()
                                    .bg(rgb(if self.favorite { p.accent } else { p.chip }))
                                    .hover(|style| style.bg(rgb(p.selected)))
                                    .text_color(rgb(if self.favorite { p.accent_foreground } else { p.secondary }))
                                    .text_xs().child(if self.favorite { "●   ON" } else { "OFF   ○" })
                                    .id("main-interaction-021").on_click(cx.listener(Self::toggle_favorite))))))
                    .child(div().h_flex().items_center().gap_2().px_5().py_3()
                        .bg(rgb(p.inspector)).border_t_1().border_color(rgb(p.border))
                        .child(div().w(px(160.)).cursor_pointer().rounded_md().px_3().py_2()
                            .bg(rgb(p.accent)).hover(|style| style.bg(rgb(p.selected_border)))
                            .text_color(rgb(p.accent_foreground))
                            .text_sm().font_semibold().flex().items_center().justify_center()
                            .child("Open in Warp ↗").id("main-interaction-022").on_click(cx.listener(Self::connect)))
                        .child(div().cursor_pointer().rounded_md().px_3().py_2()
                            .border_1().border_color(rgb(p.border)).bg(rgb(p.control))
                            .hover(|style| style.bg(rgb(p.chip)))
                            .text_sm().child("Save Changes").id("main-interaction-023").on_click(cx.listener(Self::save)))
                        .child(div().cursor_pointer().rounded_md().px_3().py_2()
                            .bg(rgb(p.danger_surface)).hover(|style| style.bg(rgb(p.chip)))
                            .text_color(rgb(p.danger)).text_sm()
                            .child(if self.confirm_delete { "确认删除" } else { "Delete" })
                            .id("main-interaction-024").on_click(cx.listener(Self::remove))))))
            // Never equate generated configuration status with a successful SSH login.
            .child(div().h_flex().items_center().gap_4().px_4().py_2()
                .bg(rgb(p.titlebar)).border_t_1().border_color(rgb(p.border))
                .child(div().text_xs().text_color(rgb(tab_color))
                    .child(format!("●  Warp Tab Configs {}", if warp_ready { "ready" } else { "not created" })))
                .child(div().text_xs().text_color(rgb(status_color))
                    .child(format!("●  SSH Config {}", if linked { "linked" } else { "setup needed" })))
                .child(div().text_xs().text_color(rgb(p.tertiary))
                    .child(format!("{} servers  ·  {} groups", host_count, self.groups.len())))
                .child(div().flex_1().min_w_0().text_xs().text_color(rgb(p.tertiary))
                    .overflow_hidden().child("SSH 连接由 Warp / OpenSSH 执行")))
    }
}

fn main()->Result<()> {
    let app=Application::new().with_assets(gpui_component_assets::Assets);
    app.run(|cx| {
        gpui_component::init(cx);
        // Apply persisted appearance before the first input control is rendered.
        let preference=AppPaths::discover().ok()
            .map(|p|Appearance::read(&p.data_dir)).unwrap_or(Appearance::System);
        Theme::change(preference.mode(cx.window_appearance()),None,cx);
        cx.activate(true);
        #[cfg(feature="tray")]
        tray::install(cx);
        let options=WindowOptions {
            window_bounds:Some(WindowBounds::centered(size(px(1320.),px(810.)),cx)),
            ..WindowOptions::default()
        };
        cx.open_window(options,|window,cx| {
            let view=cx.new(|cx|ManagerView::new(window,cx));
            cx.new(|cx|Root::new(view,window,cx))
        }).expect("GPUI window could not open");
    });
    Ok(())
}
