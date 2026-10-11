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
    Ungrouped,
    Group(Uuid),
}

#[derive(Clone, Copy, PartialEq, Eq)]
enum Feedback { Info, Success, Error, Warning }

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum DetailTab { Basic, Connection, Tags, Advanced }

struct ManagerView {
    manager: Manager,
    hosts: Vec<Host>,
    groups: Vec<Group>,
    selected: Option<Uuid>,
    editing_new: bool,
    detail_tab: DetailTab,
    filter: ViewFilter,
    editor_group: Option<Uuid>,
    group_picker_open: bool,
    actions_open: bool,
    filter_menu_open: bool,
    creating_group: bool,
    tag_input_open: bool,
    expanded_card: Option<Uuid>,
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
    _tags_subscription: Subscription,
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
        // Do not turn a database error into an apparently empty library.
        let (hosts,host_error)=match manager.db.list_hosts() {
            Ok(hosts)=>(hosts,None),
            Err(err)=>(Vec::new(),Some(format!("读取主机数据库失败：{err:#}"))),
        };
        let (groups,group_error)=match manager.db.list_groups() {
            Ok(groups)=>(groups,None),
            Err(err)=>(Vec::new(),Some(format!("读取分组失败：{err:#}"))),
        };
        let load_error=host_error.or(group_error);
        let appearance=Appearance::read(&manager.paths.data_dir);
        let search=make_input(window,cx,"搜索名称、IP 或 SSH 别名…");
        let subscription=cx.subscribe_in(&search,window,|_,_,event:&InputEvent,_,cx| {
            if matches!(event,InputEvent::Change) {cx.notify();}
        });
        let tags=make_input(window,cx,"api, production");
        let tags_subscription=cx.subscribe_in(&tags,window,|_,_,event:&InputEvent,_,cx| {
            if matches!(event,InputEvent::Change) { cx.notify(); }
        });
        let appearance_subscription=cx.observe_window_appearance(window,|this,window,cx| {
            if this.appearance==Appearance::System {
                Theme::change(this.appearance.mode(window.appearance()),Some(window),cx);
                cx.notify();
            }
        });
        let first_host = hosts.first().map(|host| host.id);
        let mut view = Self {
            manager,hosts,groups,selected:None,editing_new:false,
            detail_tab:DetailTab::Basic,filter:ViewFilter::All,
            editor_group:None,group_picker_open:false,actions_open:false,filter_menu_open:false,creating_group:false,tag_input_open:false,expanded_card:None,collapsed_groups:HashSet::new(),appearance,search,
            group_input:make_input(window,cx,"新建分组名称"),
            name:make_input(window,cx,"服务器显示名称"),
            alias:make_input(window,cx,"prod-api-01"),
            hostname:make_input(window,cx,"192.168.1.10"),
            username:make_input(window,cx,"ubuntu"),
            port:make_input(window,cx,"22"),
            identity:make_input(window,cx,"~/.ssh/id_ed25519"),
            jump:make_input(window,cx,"可选跳板机别名"),
            tags,
            notes:cx.new(|cx| InputState::new(window,cx).placeholder("添加主机备注…").multi_line(true)),
            favorite:false,confirm_delete:false,
            message:load_error.clone().unwrap_or_else(||"请选择主机或导入现有 SSH 配置。".into()),
            feedback:if load_error.is_some(){Feedback::Error}else{Feedback::Info},
            _subscription:subscription,_tags_subscription:tags_subscription,
            _appearance_subscription:appearance_subscription,
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
        self.editing_new=false;
        self.detail_tab=DetailTab::Basic;
        self.editor_group=host.group_id;
        self.group_picker_open=false;
        self.tag_input_open=false;
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
        self.editing_new=true;
        self.detail_tab=DetailTab::Basic;
        self.favorite=false;
        self.editor_group=match self.filter {ViewFilter::Group(id)=>Some(id),_=>None};
        self.group_picker_open=false;
        self.tag_input_open=true;
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
                Some("SSH 别名必须以字母或数字开头，只能包含字母、数字、点、下划线和连字符。")
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
                let normalized=parse_tags(&tags).join(", ");
                match self.manager.db.save_annotations(id,&normalized,notes.trim()) {
                    Ok(())=>{self.feedback=Feedback::Success;self.message="主机资料已保存，配置已同步。".into()},
                    Err(err)=>{self.feedback=Feedback::Warning;self.message=format!("主机已保存，但标签/备注保存失败：{err:#}")},
                }
                self.selected=Some(id);
                self.editing_new=false;
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
                self.message="主机已删除，原始 SSH 配置文件保持不变。".into();
                self.refresh(cx);
            },
            Err(err)=>{self.feedback=Feedback::Error;self.message=format!("删除失败：{err:#}")},
        }
        cx.notify();
    }

    fn connect(&mut self,_:&ClickEvent,_:&mut Window,cx:&mut Context<Self>) {
        let Some(id)=self.selected else {
            self.feedback=Feedback::Warning;
            self.message="请先保存主机，再点击「在 Warp 中打开」。".into();cx.notify();return;
        };
        match self.manager.connect(id,false,false) {
            Ok(())=>{
                self.feedback=Feedback::Success;
                self.message="已请求 Warp 打开标签页；SSH 认证由 Warp / OpenSSH 负责。".into();
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
            Ok(true)=>self.message="已启用 SSH 集成，并备份现有 SSH 配置。".into(),
            Ok(false)=>self.message="SSH 集成已经启用。".into(),
            Err(err)=>self.message=format!("初始化失败：{err:#}"),
        }
        self.feedback=if self.message.starts_with("初始化失败") {Feedback::Error} else {Feedback::Success};
        cx.notify();
    }

    fn sync(&mut self,_:&ClickEvent,_:&mut Window,cx:&mut Context<Self>) {
        match self.manager.sync_existing_tabs() {
            Ok(count)=>self.message=format!("已同步 {count} 条已生成或收藏的 Warp 标签配置。"),
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
                self.creating_group=false;
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
        let result=parse_tags(&values).into_iter()
            .filter(|item| item != tag_to_remove)
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
            ViewFilter::Ungrouped=>host.group_id.is_none(),
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
fn detail_field(label: &'static str, input: &Entity<InputState>, readonly: bool, p: Palette, cx: &Context<ManagerView>) -> impl IntoElement {
    // gpui-component 0.5.1 lacks Input::readonly, so imported connection
    // values are shown in a non-editable surface matching the editable input.
    let display_value = input.read(cx).value().to_string();
    div().h_flex().items_center().gap_3().min_h(px(40.))
        .child(div().w(px(104.)).text_sm().text_color(rgb(p.primary)).child(label))
        .child(div().flex_1().min_w_0()
            .when(label=="端口", |el| el.max_w(px(105.)))
            .rounded_lg().border_1().border_color(rgb(p.border))
            .bg(rgb(p.input_surface))
            .min_h(px(38.)).px_1()
            .when(readonly, |el| el.child(div().px_2().py_2().min_h(px(32.))
                .text_sm().text_color(rgb(p.primary))
                .child(display_value.clone())))
            .when(!readonly, |el| el.child(Input::new(input).appearance(false))))
}


// A shared tag parser handles English and Chinese separators and removes duplicates.
fn parse_tags(value: &str) -> Vec<String> {
    let mut result: Vec<String> = Vec::new();
    for candidate in value.split(|ch| matches!(ch, ',' | '，' | ';' | '；' | '\n')) {
        let tag = candidate.trim();
        if !tag.is_empty() && !result.iter().any(|old| old.eq_ignore_ascii_case(tag)) {
            result.push(tag.to_string());
        }
    }
    result
}

fn tag_palette(name: &str, p: Palette) -> (u32, u32) {
    let value = name.to_lowercase();
    let (bg, fg) = if value.contains("database") || value.contains("数据库") {
        (p.danger_surface, p.danger)
    } else if value.contains("test") || value.contains("测试") || value.contains("stag") {
        (p.warning_surface, p.warning_foreground)
    } else if value.contains("dev") || value.contains("开发") {
        (p.stage_surface, p.stage_foreground)
    } else if value.contains("prod") || value.contains("生产") {
        (p.dev_surface, p.dev_foreground)
    } else if value.contains("api") {
        (p.prod_surface, p.prod_foreground)
    } else { (p.chip, p.secondary) };
    (bg, fg)
}

fn environment(name: &str, p: Palette) -> impl IntoElement {
    let (bg, fg) = tag_palette(name, p);
    div().px_2().py_1().rounded_md().bg(rgb(bg))
        .text_xs().font_semibold().text_color(rgb(fg)).child(name.to_owned())
}

fn sidebar_row(icon: IconName, text: &'static str, count: usize, active: bool, p: Palette) -> impl IntoElement {
    div().h_flex().items_center().justify_between().rounded_lg().px_3().py_3()
        .bg(if active { linear_gradient(90.,linear_color_stop(rgb(p.selected),0.),linear_color_stop(rgb(p.selected_end),1.)) }
            else {linear_gradient(90.,linear_color_stop(rgb(p.sidebar),0.),linear_color_stop(rgb(p.sidebar_end),1.))})
        .child(div().h_flex().items_center().gap_3().text_sm().font_semibold()
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
                .child(sidebar_row(IconName::SquareTerminal, "全部主机", host_count, current_filter == ViewFilter::All, p))
                .id("main-interaction-001").on_click(cx.listener(|this, _, _, cx| { this.filter = ViewFilter::All; cx.notify(); })))
            .child(div().cursor_pointer()
                .child(sidebar_row(IconName::Star, "收藏", favorite_count, current_filter == ViewFilter::Favorites, p))
                .id("main-interaction-002").on_click(cx.listener(|this, _, _, cx| { this.filter = ViewFilter::Favorites; cx.notify(); })))
            .child(div().cursor_pointer()
                .child(sidebar_row(IconName::Calendar, "最近连接", recent_count, current_filter == ViewFilter::Recent, p))
                .id("main-interaction-003").on_click(cx.listener(|this, _, _, cx| { this.filter = ViewFilter::Recent; cx.notify(); })));

        let mut flat = Vec::new();
        nested_groups(&self.groups, None, 0, &self.collapsed_groups, &mut flat);
        for group in self.groups.iter().filter(|g| g.parent_id.is_some()
            && !self.groups.iter().any(|parent| Some(parent.id) == g.parent_id)) {
            flat.push((group.clone(), 0));
        }
        let mut group_list = div().v_flex().gap_1();
        let ungrouped_count = self.hosts.iter().filter(|h|h.group_id.is_none()).count();
        if ungrouped_count>0 || self.groups.is_empty() {
            group_list=group_list.child(
                div().id("ungrouped-sidebar-item").cursor_pointer()
                    .hover(|style| style.bg(rgb(p.chip)))
                    .child(sidebar_row(IconName::Folder, "未分组", ungrouped_count,
                        current_filter==ViewFilter::Ungrouped,p))
                    .on_click(cx.listener(|this,_,_,cx|{
                        this.filter=ViewFilter::Ungrouped;
                        cx.notify();
                    })));
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
        // Reference design: independent server tiles, without imaginary online/offline indicators.
        // Native-feeling compact tiles. Colors denote annotations/categories, never
        // unverified host availability. Annotations are loaded from the real database.
        let mut connections = div().v_flex().gap_2();
        for host in filtered {
            let id = host.id;
            let active = self.selected == Some(id);
            let starred = host.favorite;
            let expanded = self.expanded_card == Some(id);
            // The selected tile mirrors unsaved editor tags; other tiles use SQLite.
            let visible_group = if active { self.editor_group } else { host.group_id };
            let label = self.group_label(visible_group);
            let tags = if active { Self::read(&self.tags,cx) } else {
                self.manager.db.host_annotations(id).map(|(tags,_)|tags).unwrap_or_default()
            };
            let parsed = parse_tags(&tags);
            let mut chips = div().h_flex().items_center().gap_1();
            for tag in parsed.iter().take(2) {
                chips = chips.child(environment(tag, p));
            }
            if parsed.len()>2 {
                chips = chips.child(div().px_2().py_1().rounded_md()
                    .bg(rgb(p.chip)).text_xs().text_color(rgb(p.secondary))
                    .child(format!("+{}",parsed.len()-2)));
            }
            if parsed.is_empty() {
                if visible_group.is_some() {
                    chips = chips.child(environment(&label,p));
                } else {
                    chips = chips.child(div().px_2().py_1().rounded_md()
                        .bg(rgb(p.chip)).text_xs().text_color(rgb(p.tertiary))
                        .child("SSH"));
                }
            }
            let (icon_top,icon_bottom,icon_outline) = if tags.contains("database") || host.name.contains("db-") {
                (0x593442, 0x1A1C29, p.danger)
            } else if tags.contains("dev") || label.contains("开发") {
                (0x52447F, 0x181B37, p.stage_foreground)
            } else if tags.contains("prod") || label.contains("生产") {
                (0x28584D, 0x152932, p.dev_foreground)
            } else { (0x33566B, 0x142332, p.selected_border) };
            connections = connections.child(
                div().id(SharedString::from(format!("connection-row-{id}")))
                    .v_flex().rounded_lg().cursor_pointer().overflow_hidden().shadow_sm()
                    .border_1().border_color(rgb(if active { p.selected_border } else { p.border }))
                    .bg(if active {linear_gradient(125.,linear_color_stop(rgb(p.card_selected),0.),linear_color_stop(rgb(p.card_selected_end),1.))}
                        else {linear_gradient(90.,linear_color_stop(rgb(p.inspector),0.),linear_color_stop(rgb(p.card_end),1.))})
                    .hover(|style| style.border_color(rgb(p.selected_border)))
                    .child(div().h_flex().items_center().gap_3().px_3().py_3()
                        .child(div().w(px(46.)).h(px(46.)).rounded_lg()
                            .border_1().border_color(rgb(icon_outline))
                            .shadow_sm()
                            .bg(linear_gradient(160.,linear_color_stop(rgb(icon_top),0.),linear_color_stop(rgb(icon_bottom),1.)))
                            .flex().items_center().justify_center()
                            .text_color(rgb(0xF1FAFF))
                            .text_base().font_semibold().child(">_"))
                        .child(div().flex_1().min_w_0().v_flex().gap_2()
                            .child(div().text_sm().font_semibold()
                                .text_color(rgb(p.primary))
                                .child(host.name.clone()))
                            .child(div().text_xs()
                                .text_color(rgb(p.secondary))
                                .child(host.hostname.clone()))
                            .child(chips))
                        .child(div().h_flex().items_center().gap_1()
                            .child(div().id(SharedString::from(format!("connection-star-{id}")))
                                .cursor_pointer().rounded_lg().px_1().py_2()
                                .hover(|style| style.bg(rgb(p.chip)))
                                .text_lg()
                                .text_color(rgb(if starred { 0xECAA36 } else { p.secondary }))
                                .child(if starred { "★" } else { "☆" })
                                .on_click(cx.listener(move |this, _, _, cx| {
                                    cx.stop_propagation();
                                    this.toggle_list_favorite(id, cx);
                                })))
                            .child(div().id(SharedString::from(format!("connection-menu-{id}")))
                                .cursor_pointer().rounded_lg().px_1().py_2()
                                .hover(|style| style.bg(rgb(p.chip)))
                                .text_sm().font_semibold().text_color(rgb(p.secondary))
                                .child("···")
                                .on_click(cx.listener(move |this, _, _, cx| {
                                    cx.stop_propagation();
                                    this.expanded_card = if this.expanded_card == Some(id) { None } else { Some(id) };
                                    cx.notify();
                                })))))
                    .when(expanded, |el| el.child(div().h_flex().items_center().justify_between()
                        .px_4().py_2().border_t_1().border_color(rgb(p.border))
                        .bg(rgb(if active { p.selected } else { p.control }))
                        .child(div().text_xs().text_color(rgb(if active { p.accent } else { p.secondary }))
                            .child("双击在 Warp 中连接"))
                        .child(div().id(SharedString::from(format!("connection-menu-open-{id}")))
                            .cursor_pointer().rounded_md().bg(rgb(p.accent))
                            .px_3().py_2().text_xs().font_semibold()
                            .text_color(rgb(p.accent_foreground))
                            .child("打开 ↗")
                            .on_click(cx.listener(move |this, event: &ClickEvent, window, cx| {
                                cx.stop_propagation();
                                this.select_host(id, window, cx);
                                this.connect(event, window, cx);
                            })))))
                    .on_click(cx.listener(move |this, event: &ClickEvent, window, cx| {
                        this.select_host(id, window, cx);
                        if event.click_count() >= 2 {
                            this.connect(event, window, cx);
                        }
                    }))
            );
        }
        let library_error = self.feedback == Feedback::Error
            && self.message.starts_with("读取");
        if filtered_count == 0 {
            if self.hosts.is_empty() && !library_error {
                connections=connections.child(
                    div().v_flex().items_center().gap_3().px_3().pt_16()
                        .child(div().w(px(64.)).h(px(64.)).rounded_lg()
                            .bg(rgb(p.selected)).border_1().border_color(rgb(p.border))
                            .flex().items_center().justify_center()
                            .text_color(rgb(p.accent))
                            .child(Icon::new(IconName::SquareTerminal)))
                        .child(div().text_base().font_semibold()
                            .text_color(rgb(p.primary)).child("还没有保存的 SSH 主机"))
                        .child(div().text_sm().text_center()
                            .text_color(rgb(p.secondary))
                            .child("导入现有 SSH 配置，或从零添加第一台主机"))
                        .child(div().v_flex().gap_2().w_full().pt_3()
                            .child(div().id("empty-import").cursor_pointer()
                                .h_flex().items_center().justify_center().gap_2()
                                .rounded_lg().px_3().py_3()
                                .bg(rgb(p.accent)).text_color(rgb(p.accent_foreground))
                                .text_sm().font_semibold()
                                .child(Icon::new(IconName::Folder))
                                .child("导入现有 SSH 配置")
                                .on_click(cx.listener(Self::import)))
                            .child(div().id("empty-create").cursor_pointer()
                                .h_flex().items_center().justify_center().gap_2()
                                .rounded_lg().border_1().border_color(rgb(p.border))
                                .bg(rgb(p.inspector)).px_3().py_3()
                                .text_sm().text_color(rgb(p.primary))
                                .child("+ 新建主机")
                                .on_click(cx.listener(|this,_,window,cx| this.new_host(window,cx)))))
                        .child(div().text_xs().text_color(rgb(p.tertiary))
                            .text_center().pt_2()
                            .child("导入只读取本机 SSH 配置，不会修改原文件"))
                );
            } else {
                connections=connections.child(
                    div().v_flex().items_center().gap_3().pt_16().px_4()
                        .child(div().w(px(48.)).h(px(48.)).rounded_lg()
                            .bg(rgb(p.control)).flex().items_center().justify_center()
                            .text_color(rgb(p.tertiary))
                            .child(Icon::new(IconName::Search)))
                        .child(div().text_sm().font_semibold().text_color(rgb(p.primary))
                            .child(if library_error { "无法读取主机数据" } else { "没有匹配的主机" }))
                        .child(div().text_xs().text_center().text_color(rgb(p.secondary))
                            .child(if library_error {
                                "请检查本地数据库及访问权限，不会自动清空或覆盖数据"
                            } else { "可以调整搜索关键词，或切换左侧筛选条件" }))
                );
            }
        }

        let mut group_picker = div().v_flex().gap_1()
            .child(div().h_flex().items_center().gap_3()
                .child(div().w(px(101.)).text_sm().text_color(rgb(p.secondary)).child("所属分组"))
                .child(div().h_flex().flex_1().min_w_0().items_center().rounded_md().border_1()
                    .border_color(rgb(p.border)).bg(rgb(p.input_surface))
                    .min_h(px(36.)).px_3().py_2().cursor_pointer()
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
        // Chips and input are mutually exclusive modes: no duplicated tag textboxes.
        // The same semantic palette is used by host cards and the inspector.
        let raw_tags = Self::read(&self.tags, cx);
        let parsed_tags = parse_tags(&raw_tags);
        let mut tag_chips = div().h_flex().items_center().flex_wrap().gap_1();
        for (index, tag_name) in parsed_tags.iter().take(4).cloned().enumerate() {
            let (tag_bg, tag_fg) = tag_palette(&tag_name, p);
            tag_chips = tag_chips.child(div().h_flex().items_center().gap_1().rounded_md()
                .bg(rgb(tag_bg)).px_2().py_1()
                .child(div().text_xs().font_semibold().text_color(rgb(tag_fg))
                    .child(tag_name.clone()))
                .child(div().id(SharedString::from(format!("tag-remove-{index}")))
                    .cursor_pointer().px_1().rounded_sm()
                    .text_color(rgb(tag_fg))
                    .child(Icon::new(IconName::Close).xsmall())
                    .on_click(cx.listener(move |this, _, window, cx| {
                        this.remove_tag(&tag_name,window,cx);
                    }))));
        }
        if parsed_tags.len()>4 {
            tag_chips=tag_chips.child(div().px_2().py_1().rounded_md()
                .bg(rgb(p.chip)).text_xs().text_color(rgb(p.secondary))
                .child(format!("+{}",parsed_tags.len()-4)));
        }
        let tags_field = div().h_flex().items_start().gap_3().min_h(px(36.))
            .child(div().w(px(101.)).py_2().text_sm()
                .text_color(rgb(p.secondary)).child("标签"))
            .child(div().v_flex().flex_1().min_w_0().gap_2()
                .when(!self.tag_input_open, |el| el.child(
                    div().h_flex().items_center().gap_2().flex_wrap()
                        .when(!parsed_tags.is_empty(), |el| el.child(tag_chips))
                        .child(div().id("tag-editor-open").cursor_pointer()
                            .rounded_md().border_1().border_color(rgb(p.border))
                            .px_3().py_2().bg(rgb(p.input_surface))
                            .text_xs().text_color(rgb(p.secondary))
                            .child(if parsed_tags.is_empty() { "+ 添加标签" } else { "+ 编辑" })
                            .on_click(cx.listener(|this,_,_,cx| {
                                this.tag_input_open=true;
                                cx.notify();
                            })))))
                .when(self.tag_input_open, |el| el.child(
                    div().h_flex().items_center().gap_2()
                        .child(div().flex_1().min_w_0().rounded_md().border_1()
                            .border_color(rgb(p.border)).bg(rgb(p.input_surface))
                            .child(Input::new(&self.tags).appearance(false)))
                        .child(div().id("tag-editor-close").cursor_pointer()
                            .rounded_md().px_3().py_2().bg(rgb(p.chip))
                            .text_xs().text_color(rgb(p.secondary)).child("收起")
                            .on_click(cx.listener(|this,_,_,cx| {
                                this.tag_input_open=false;
                                cx.notify();
                            }))))));

        // Tabs are real controls; each exposes a focused subset of the existing SSH editor.
        let mut detail_tabs = div().h_flex().items_center().gap_2().px_4()
            .border_b_1().border_color(rgb(p.border));
        for (index, (tab, title)) in [
            (DetailTab::Basic, "基本信息"),
            (DetailTab::Connection, "连接配置"),
            (DetailTab::Tags, "标签与分组"),
            (DetailTab::Advanced, "高级设置"),
        ].into_iter().enumerate() {
            let chosen = self.detail_tab == tab;
            detail_tabs = detail_tabs.child(
                div().id(SharedString::from(format!("detail-tab-{index}")))
                    .cursor_pointer().px_2().py_2().v_flex().gap_2()
                    .child(div().text_sm().font_semibold()
                        .text_color(rgb(if chosen { p.accent } else { p.secondary }))
                        .child(title))
                    .child(div().h(px(3.)).rounded_full()
                        .bg(rgb(if chosen { p.accent } else { p.inspector })))
                    .on_click(cx.listener(move |this, _, _, cx| {
                        this.detail_tab = tab;
                        this.group_picker_open = false;
                        cx.notify();
                    }))
            );
        }
        let notes_field = div().h_flex().items_start().gap_3()
            .child(div().w(px(101.)).py_2().text_sm().text_color(rgb(p.secondary)).child("备注"))
            .child(div().flex_1().min_w_0().rounded_md().border_1()
                .border_color(rgb(p.border)).bg(rgb(p.input_surface))
                .px_2().py_1()
                .child(Input::new(&self.notes).appearance(false).h(px(72.))));
        let favorite_switch = div().h_flex().items_center().justify_between().px_1().py_1()
            .child(div().h_flex().items_center().gap_2()
                .child(Icon::new(IconName::Star))
                .child(div().text_sm().text_color(rgb(p.secondary)).child("设为收藏")))
            .child(div().id("main-interaction-021").cursor_pointer()
                .h_flex().items_center().w(px(44.)).h(px(24.)).px_1().rounded_full()
                .bg(rgb(if self.favorite { p.accent } else { p.border }))
                .when(self.favorite, |el| el.child(div().flex_1()))
                .child(div().w(px(17.)).h(px(17.)).rounded_full()
                    .bg(rgb(p.accent_foreground)))
                .when(!self.favorite, |el| el.child(div().flex_1()))
                .on_click(cx.listener(Self::toggle_favorite)));
        let detail_panel = match self.detail_tab {
            DetailTab::Basic => div().v_flex().gap_2()
                .child(detail_field("显示名称", &self.name, false, p, cx))
                .child(detail_field("SSH 别名", &self.alias, imported, p, cx))
                .child(detail_field("主机名 / IP", &self.hostname, imported, p, cx))
                .child(detail_field("用户名", &self.username, imported, p, cx))
                .child(detail_field("端口", &self.port, imported, p, cx))
                .child(detail_field("身份文件", &self.identity, imported, p, cx))
                .child(group_picker)
                .child(tags_field)
                .child(notes_field)
                .child(favorite_switch),
            DetailTab::Connection => div().v_flex().gap_3()
                .child(div().text_sm().font_semibold().text_color(rgb(p.primary))
                    .child("SSH 连接参数"))
                .child(div().text_xs().text_color(rgb(p.tertiary))
                    .child("由 Warp 使用系统 OpenSSH 发起连接"))
                .child(detail_field("SSH 别名", &self.alias, imported, p, cx))
                .child(detail_field("主机名 / IP", &self.hostname, imported, p, cx))
                .child(detail_field("用户名", &self.username, imported, p, cx))
                .child(detail_field("端口", &self.port, imported, p, cx))
                .child(detail_field("身份文件", &self.identity, imported, p, cx))
                .child(detail_field("跳板机", &self.jump, imported, p, cx)),
            DetailTab::Tags => div().v_flex().gap_4()
                .child(div().text_sm().font_semibold().text_color(rgb(p.primary))
                    .child("分类与备注"))
                .child(group_picker)
                .child(tags_field)
                .child(notes_field),
            DetailTab::Advanced => div().v_flex().gap_4()
                .child(div().text_sm().font_semibold().text_color(rgb(p.primary))
                    .child("高级连接选项"))
                .child(detail_field("跳板机", &self.jump, imported, p, cx))
                .child(favorite_switch)
                .child(div().rounded_lg().px_3().py_3().bg(rgb(p.control))
                    .text_xs().text_color(rgb(p.secondary))
                    .child("连接配置由 OpenSSH 管理。导入的主机连接字段保持只读；可以修改备注、收藏和分组。")),
        };
        let doctor = self.manager.doctor().ok();
        let linked = doctor.as_ref().map(|d| d.include_enabled).unwrap_or(false);
        let warp_ready = self.manager.paths.warp_configs.exists();
        let (banner_bg,banner_fg,banner_icon,banner_title)=match self.feedback {
            Feedback::Error => (p.danger_surface,p.danger,"!","操作失败"),
            Feedback::Warning => (p.stage_surface,p.stage_foreground,"!","请确认"),
            Feedback::Success => (p.dev_surface,p.dev_foreground,"✓","操作成功"),
            Feedback::Info => (p.chip,p.secondary,"i","提示"),
        };
        let banner=div().h_flex().items_center().gap_2().mx_4().mt_3().px_3().py_3()
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
                    .text_xs().child("导入 SSH 配置").id("main-interaction-012").on_click(cx.listener(Self::import)))
                .child(div().cursor_pointer().rounded_md().px_3().py_2().bg(rgb(p.control))
                    .hover(|style| style.bg(rgb(p.chip)))
                    .text_xs().child("同步 Warp 标签配置").id("main-interaction-013").on_click(cx.listener(Self::sync)))
                .child(div().flex_1())
                .child(div().h_flex().items_center().gap_3()
                    .child(div().text_xs().text_color(rgb(tab_color))
                        .child(format!("Warp 标签配置{}", if warp_ready { "已就绪" } else { "未生成" })))
                    .child(div().text_xs().text_color(rgb(status_color))
                        .child(format!("SSH 配置{}", if linked { "已接入" } else { "需初始化" }))))
                .child(div().cursor_pointer().text_xs().text_color(rgb(p.tertiary))
                    .child("关闭 ×")
                    .id("main-interaction-014").on_click(cx.listener(|this, _, _, cx| { this.actions_open = false; cx.notify(); })));
        }

        // Window shell mirrors the reference: persistent branded sidebar,
        // independent toolbar over connection cards and inspector, native macOS chrome.
        let sidebar = div().w(px(266.)).h_full().v_flex().min_h_0()
            .bg(linear_gradient(160.,linear_color_stop(rgb(p.sidebar),0.),linear_color_stop(rgb(p.sidebar_end),1.)))
            .border_r_1().border_color(rgb(p.border))
            .child(div().h_flex().items_center().gap_2().px_3().pt_16().pb_4()
                .child(div().w(px(46.)).h(px(46.)).rounded_lg().shadow_sm()
                    .bg(linear_gradient(160.,linear_color_stop(rgb(0x24BCFC),0.),linear_color_stop(rgb(0x153BF1),1.)))
                    .border_1().border_color(rgb(p.selected_border))
                    .flex().items_center().justify_center()
                    .text_color(rgb(p.accent_foreground)).text_lg().font_semibold()
                    .child(">_"))
                .child(div().v_flex().gap_1()
                    .child(div().text_base().font_semibold().text_color(rgb(p.primary))
                        .child("Warp SSH 管理器"))
                    .child(div().text_xs().text_color(rgb(p.tertiary))
                        .child("高效管理 · 快速连接"))))
            .child(div().v_flex().flex_1().min_h_0().px_3().py_2().gap_3()
                .child(folder_items)
                .child(div().h_flex().items_center().justify_between().pt_2()
                    .child(div().text_sm().font_semibold().text_color(rgb(p.secondary))
                        .child("分组"))
                    .child(div().id("sidebar-group-toggle").cursor_pointer()
                    .px_2().py_2().text_color(rgb(p.secondary))
                    .child(if self.creating_group { "×" } else { "+" })
                    .on_click(cx.listener(|this,_,_,cx| {
                        this.creating_group=!this.creating_group;
                        cx.notify();
                    }))))
                .child(div().flex_1().min_h_0().overflow_y_scrollbar()
                    .child(group_list)))
            .when(self.creating_group, |el| el.child(
                div().h_flex().items_center().gap_2().px_3().py_2()
                    .child(div().flex_1().min_w_0().child(Input::new(&self.group_input)))
                    .child(div().id("create-sidebar-group").cursor_pointer()
                        .rounded_lg().px_3().py_2().bg(rgb(p.accent))
                        .text_color(rgb(p.accent_foreground)).text_sm().font_semibold()
                        .child("创建")
                        .on_click(cx.listener(Self::add_group)))))
            .child(div().h_flex().items_center().gap_2().px_4().py_3()
                .border_t_1().border_color(rgb(p.border))
                .child(div().id("show-sidebar-group-form").flex_1()
                    .cursor_pointer().h_flex().items_center().gap_2()
                    .rounded_lg().px_2().py_2().bg(rgb(p.control))
                    .text_sm().text_color(rgb(p.primary))
                    .child("+")
                    .child("新建分组")
                    .on_click(cx.listener(|this,_,_,cx| {
                        this.creating_group=!this.creating_group;
                        cx.notify();
                    })))
                .child(div().id("sidebar-settings").cursor_pointer().px_3().py_2()
                    .rounded_lg().bg(rgb(p.control)).text_color(rgb(p.secondary))
                    .child(Icon::new(IconName::Settings))
                    .on_click(cx.listener(|this,_,_,cx| {
                        this.actions_open=!this.actions_open; cx.notify();
                    }))));

        let toolbar = div().h_flex().h(px(66.)).items_center().justify_between().px_4()
            .bg(linear_gradient(90.,linear_color_stop(rgb(p.titlebar),0.),linear_color_stop(rgb(p.titlebar_end),1.)))
            .border_b_1().border_color(rgb(p.border))
            .child(div().text_xl().font_semibold().text_color(rgb(p.primary))
                .child("连接列表"))
            .child(div().h_flex().items_center().gap_3()
                .child(div().h_flex().items_center().gap_1().p_1().rounded_lg()
                    .bg(rgb(p.control)).border_1().border_color(rgb(p.border))
                    .child(div().id("main-interaction-015").cursor_pointer().rounded_md()
                        .px_3().py_2()
                        .bg(rgb(if self.appearance == Appearance::System { p.inspector } else { p.control }))
                        .text_color(rgb(if self.appearance == Appearance::System { p.accent } else { p.secondary }))
                        .text_xs().font_semibold().child("自动")
                        .on_click(cx.listener(|this,_,window,cx| this.set_theme(Appearance::System,window,cx)))
                    )
                    .child(div().id("main-interaction-016").cursor_pointer().rounded_md()
                        .px_3().py_2()
                        .bg(rgb(if self.appearance == Appearance::Dark { p.inspector } else { p.control }))
                        .text_color(rgb(if self.appearance == Appearance::Dark { p.accent } else { p.secondary }))
                        .text_xs().font_semibold().child("深色")
                        .on_click(cx.listener(|this,_,window,cx| this.set_theme(Appearance::Dark,window,cx)))
                    )
                    .child(div().id("main-interaction-017").cursor_pointer().rounded_md()
                        .px_3().py_2()
                        .bg(rgb(if self.appearance == Appearance::Light { p.inspector } else { p.control }))
                        .text_color(rgb(if self.appearance == Appearance::Light { p.accent } else { p.secondary }))
                        .text_xs().font_semibold().child("浅色")
                        .on_click(cx.listener(|this,_,window,cx| this.set_theme(Appearance::Light,window,cx)))
                    ))
                .child(div().id("main-interaction-018").cursor_pointer().rounded_lg().shadow_sm()
                    .px_4().py_3().bg(linear_gradient(180.,linear_color_stop(rgb(0x3398FF),0.),linear_color_stop(rgb(p.accent),1.)))
                    .hover(|style| style.bg(rgb(p.selected_border)))
                    .text_color(rgb(p.accent_foreground)).text_sm().font_semibold()
                    .child("+ 新建主机")
                    .on_click(cx.listener(|this,_,window,cx| this.new_host(window,cx)))));

        let connections_pane = div().w(px(446.)).h_full().v_flex().min_h_0()
            .bg(rgb(p.list)).border_r_1().border_color(rgb(p.border))
            .p_3().gap_2()
            .child(div().h_flex().items_center().gap_2()
                .child(div().flex_1().min_w_0().rounded_lg().border_1()
                    .border_color(rgb(p.border)).bg(rgb(p.control))
                    .child(Input::new(&self.search)
                        .prefix(Icon::new(IconName::Search).small())))
                .child(div().id("list-filter-menu-toggle").cursor_pointer().rounded_lg()
                    .border_1().border_color(rgb(p.border)).px_3().py_2()
                    .bg(rgb(if self.filter_menu_open { p.selected } else { p.control }))
                    .text_color(rgb(p.secondary))
                    .child(Icon::new(IconName::Settings))
                    .on_click(cx.listener(|this,_,_,cx| {
                        this.filter_menu_open=!this.filter_menu_open;
                        cx.notify();
                    }))))
            .when(self.filter_menu_open, |el| el.child(div().h_flex().items_center().gap_2()
                .child(div().id("list-filter-all").cursor_pointer().px_3().py_2().rounded_md()
                    .bg(rgb(if self.filter == ViewFilter::All { p.selected } else { p.control }))
                    .text_xs().child("全部")
                    .on_click(cx.listener(|this,_,_,cx| {
                        this.filter=ViewFilter::All; this.filter_menu_open=false;cx.notify();
                    })))
                .child(div().id("list-filter-favorites").cursor_pointer().px_3().py_2().rounded_md()
                    .bg(rgb(if self.filter == ViewFilter::Favorites { p.selected } else { p.control }))
                    .text_xs().child("已收藏")
                    .on_click(cx.listener(|this,_,_,cx| {
                        this.filter=ViewFilter::Favorites; this.filter_menu_open=false;cx.notify();
                    })))
                .child(div().id("list-filter-recent").cursor_pointer().px_3().py_2().rounded_md()
                    .bg(rgb(if self.filter == ViewFilter::Recent { p.selected } else { p.control }))
                    .text_xs().child("最近连接")
                    .on_click(cx.listener(|this,_,_,cx| {
                        this.filter=ViewFilter::Recent; this.filter_menu_open=false;cx.notify();
                    })))))
            .child(div().flex_1().min_h_0().overflow_y_scrollbar()
                .child(connections));

        let inspector_editor = div().size_full().v_flex().min_h_0()
            .bg(rgb(p.inspector))
            .child(div().h_flex().items_center().justify_between().px_4().py_2()
                .child(div().v_flex().gap_1()
                    .child(div().text_xl().font_semibold().text_color(rgb(p.primary))
                        .child(if selected_is_host { "主机详情" } else { "新建主机" }))
                    .child(div().text_xs().text_color(rgb(p.tertiary))
                        .child(if imported { "已导入 · 连接字段只读" } else { "自管主机 · OpenSSH" })))
                .child(div().id("inspector-favorite").cursor_pointer().rounded_lg().px_3().py_2()
                    .bg(rgb(if self.favorite { p.selected } else { p.control }))
                    .text_color(rgb(if self.favorite { 0xEFB53D } else { p.secondary }))
                    .text_xs().child(if self.favorite { "★ 已收藏" } else { "☆ 设为收藏" })
                    .on_click(cx.listener(Self::toggle_favorite))))
            .child(detail_tabs)
            .when(self.feedback != Feedback::Info, |el| el.child(banner))
            .child(div().flex_1().min_h_0().overflow_y_scrollbar().px_4().py_3()
                .child(detail_panel))
            .child(div().h_flex().items_center().gap_2().px_4().py_3()
                .border_t_1().border_color(rgb(p.border))
                .bg(rgb(p.inspector))
                .when(selected_is_host, |el| el.child(
                    div().id("main-interaction-022").cursor_pointer()
                        .rounded_lg().px_4().py_3().shadow_sm()
                        .bg(rgb(p.accent)).hover(|style| style.bg(rgb(p.selected_border)))
                        .text_color(rgb(p.accent_foreground)).text_sm().font_semibold()
                        .child(div().h_flex().items_center().gap_2()
                            .child(Icon::new(IconName::SquareTerminal))
                            .child("在 Warp 中打开"))
                        .on_click(cx.listener(Self::connect))))
                .child(div().id("main-interaction-023").cursor_pointer()
                    .rounded_lg().px_4().py_3()
                    .bg(rgb(if self.editing_new { p.accent } else { p.control }))
                    .text_color(rgb(if self.editing_new { p.accent_foreground } else { p.primary }))
                    .text_sm().font_semibold()
                    .child(if self.editing_new { "保存并创建主机" } else { "保存更改" })
                    .on_click(cx.listener(Self::save)))
                .when(selected_is_host, |el| el.child(
                    div().id("main-interaction-024").cursor_pointer()
                        .rounded_lg().px_3().py_3().bg(rgb(p.danger_surface))
                        .text_color(rgb(p.danger)).text_sm()
                        .child(if self.confirm_delete { "确认删除" } else { "删除" })
                        .on_click(cx.listener(Self::remove)))))

        // No host selected means "welcome/select a host", NOT "new host editor".
        // New host editing is an explicit action and does not fabricate a host.
        let no_selection = self.selected.is_none() && !self.editing_new;
        let inspector_pane = div().flex_1().min_w_0().h_full().v_flex().min_h_0()
            .bg(rgb(p.inspector))
            .when(!no_selection, |el| el.child(inspector_editor))
            .when(no_selection, |el| el.child(
                div().size_full().v_flex()
                    .child(div().px_5().py_5().border_b_1().border_color(rgb(p.border))
                        .child(div().text_xl().font_semibold().text_color(rgb(p.primary))
                            .child(if library_error { "数据读取异常" } else { "主机工作台" }))
                        .child(div().pt_2().text_sm().text_color(rgb(p.secondary))
                            .child(if library_error {
                                "无法加载本地主机信息，请先检查数据库"
                            } else { "集中管理连接、分组和标签，交给 Warp 发起 SSH 会话" })))
                    .child(div().flex_1().v_flex().items_center().justify_center()
                        .px_6().gap_4()
                        .child(div().w(px(72.)).h(px(72.)).rounded_lg()
                            .bg(rgb(p.selected)).border_1().border_color(rgb(p.border))
                            .flex().items_center().justify_center()
                            .text_color(rgb(p.accent))
                            .child(Icon::new(IconName::SquareTerminal)))
                        .child(div().text_lg().font_semibold().text_color(rgb(p.primary))
                            .child(if library_error { "请检查主机数据库" }
                                else if host_count==0 { "准备连接第一台服务器？" }
                                else { "选择一台主机查看详情" }))
                        .child(div().text_sm().text_center().text_color(rgb(p.secondary))
                            .child(if library_error {
                                "数据库读取失败不会清空原有资料，请先检查文件与权限"
                            } else if host_count==0 {
                                "从 SSH 配置导入，或手动添加第一台主机"
                            } else { "从中间连接列表选择主机，即可查看详情并在 Warp 中打开" }))
                        .when(host_count==0 && !library_error, |el| el.child(
                            div().h_flex().items_center().gap_2().pt_3()
                                .child(div().id("welcome-import").cursor_pointer()
                                    .rounded_lg().border_1().border_color(rgb(p.border))
                                    .bg(rgb(p.control)).px_4().py_3()
                                    .text_sm().font_semibold().text_color(rgb(p.primary))
                                    .child("导入 SSH 配置")
                                    .on_click(cx.listener(Self::import)))
                                .child(div().id("welcome-add").cursor_pointer()
                                    .rounded_lg().bg(rgb(p.accent)).px_4().py_3()
                                    .text_sm().font_semibold().text_color(rgb(p.accent_foreground))
                                    .child("+ 新建主机")
                                    .on_click(cx.listener(|this,_,window,cx| this.new_host(window,cx))))))
                        .child(div().px_4().py_3().rounded_lg()
                            .bg(rgb(p.control)).text_xs().text_color(rgb(p.tertiary))
                            .child(if library_error {
                                self.message.clone()
                            } else {
                                "所有主机记录保存在本机；不会自动修改现有 SSH 配置".to_string()
                            })))
            ));

        let workspace = div().flex_1().min_w_0().h_full().v_flex().min_h_0()
            .child(toolbar)
            .when(self.actions_open, |el| el.child(secondary_actions))
            .child(div().h_flex().flex_1().min_h_0().items_start()
                .child(connections_pane)
                .child(inspector_pane));

        div().size_full().v_flex().bg(rgb(p.app)).text_color(rgb(p.primary))
            .child(div().h_flex().flex_1().min_h_0().items_start()
                .child(sidebar)
                .child(workspace))


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
            window_bounds:Some(WindowBounds::centered(size(px(1200.),px(780.)),cx)),
            window_min_size:Some(size(px(1040.),px(660.))),
            titlebar:Some(TitlebarOptions {
                title:None,
                appears_transparent:true,
                traffic_light_position:Some(point(px(18.),px(18.))),
            }),
            ..WindowOptions::default()
        };
        cx.open_window(options,|window,cx| {
            let view=cx.new(|cx|ManagerView::new(window,cx));
            cx.new(|cx|Root::new(view,window,cx))
        }).expect("GPUI window could not open");
    });
    Ok(())
}
