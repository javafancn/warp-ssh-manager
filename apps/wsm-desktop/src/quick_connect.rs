//! Searchable Quick Connect window. Opened from the native macOS menu-bar menu.
//! The UI is intentionally GPUI, so it follows the main window's saved light/dark preference.
//! NOTE: A precisely NSStatusItem-anchored popover is future native integration work.
use gpui::*;
use gpui::prelude::*;
use gpui_component::scroll::ScrollableElement;
use gpui_component::StyledExt;
use gpui_component::{input::{Input,InputEvent,InputState}, Root};
use uuid::Uuid;
use wsm_core::{Host,Manager};
use super::{environment, theme::{Appearance,Palette}};

pub struct QuickConnect {
    manager: Manager,
    search: Entity<InputState>,
    status: String,
    _subscription: Subscription,
}

impl QuickConnect {
    fn new(window:&mut Window,cx:&mut Context<Self>)->Self {
        let manager=Manager::discover().expect("unable to open SSH Manager database");
        let search=cx.new(|cx|InputState::new(window,cx).placeholder("搜索服务器名称、IP、别名..."));
        let sub=cx.subscribe_in(&search,window,|this,_,event:&InputEvent,window,cx| {
            match event {
                InputEvent::Change => cx.notify(),
                InputEvent::PressEnter { .. } => this.connect_first(window,cx),
                _=>{}
            }
        });
        // Open as a keyboard-first search utility. No mouse click is required.
        search.update(cx,|state,cx|state.focus(window,cx));
        Self {manager,search,status:"按 Enter 连接第一个结果，或点击主机。".into(),_subscription:sub}
    }

    fn hosts(&self,cx:&Context<Self>)->Vec<Host> {
        let query=self.search.read(cx).value().to_string().to_lowercase();
        let mut hosts=self.manager.db.list_hosts().unwrap_or_default();
        hosts.retain(|h|query.is_empty()||[&h.name,&h.alias,&h.hostname]
            .iter().any(|s|s.to_lowercase().contains(&query)));
        hosts.sort_by(|a,b|b.favorite.cmp(&a.favorite)
            .then_with(||b.last_connected.cmp(&a.last_connected))
            .then_with(||a.name.cmp(&b.name)));
        hosts.truncate(12);
        hosts
    }

    fn connect_first(&mut self,window:&mut Window,cx:&mut Context<Self>) {
        if let Some(host)=self.hosts(cx).first() {self.connect(host.id,window,cx)}
        else {self.status="没有匹配的主机。".into();cx.notify();}
    }

    fn connect(&mut self,id:Uuid,window:&mut Window,cx:&mut Context<Self>) {
        match self.manager.connect(id,false,false) {
            Ok(())=>window.remove_window(),
            Err(err)=> {self.status=format!("连接请求失败：{err:#}");cx.notify();}
        }
    }
}

impl Render for QuickConnect {
    fn render(&mut self, window: &mut Window, cx: &mut Context<Self>) -> impl IntoElement {
        let setting = Appearance::read(&self.manager.paths.data_dir);
        let p = Palette::new(setting.dark(window.appearance()));
        let hosts = self.hosts(cx);
        let groups = self.manager.db.list_groups().unwrap_or_default();
        let mut list = div().v_flex().gap_1();
        for (index, host) in hosts.iter().enumerate() {
            let id = host.id;
            let picked = index == 0;
            let label = host.group_id
                .and_then(|id| groups.iter().find(|g| g.id == id))
                .map(|group| group.name.as_str()).unwrap_or("未分组");
            list = list.child(div().h_flex().items_center().gap_2().px_3().py_2().rounded_lg()
                .bg(rgb(if picked { p.selected } else { p.inspector }))
                .border_1().border_color(rgb(if picked { p.selected_border } else { p.inspector }))
                .cursor_pointer()
                .child(div().w(px(30.)).h(px(30.)).rounded_md()
                    .bg(rgb(p.control)).flex().items_center().justify_center()
                    .text_color(rgb(p.secondary)).child("▤"))
                .child(div().v_flex().gap_1().flex_1().min_w_0()
                    .child(div().text_sm().font_semibold().text_color(rgb(p.primary)).child(host.name.clone()))
                    .child(div().text_xs().text_color(rgb(p.tertiary)).child(host.hostname.clone())))
                .child(environment(label, p))
                .child(div().text_lg().text_color(rgb(if host.favorite { 0xF4B532 } else { p.tertiary }))
                    .child(if host.favorite { "★" } else { "☆" }))
                .id("quick_connect-action-86").on_click(cx.listener(move |this, _, window, cx| this.connect(id, window, cx))));
        }
        if hosts.is_empty() {
            list = list.child(div().py_8().v_flex().items_center().gap_2()
                .child(div().text_2xl().text_color(rgb(p.tertiary)).child("⌕"))
                .child(div().text_sm().text_color(rgb(p.secondary)).child("没有找到匹配的服务器")));
        }
        div().size_full().v_flex().p_4().gap_3().bg(rgb(p.inspector)).text_color(rgb(p.primary))
            .child(div().h_flex().justify_between().items_center()
                .child(div().text_lg().font_semibold().child("Quick Connect"))
                .child(div().cursor_pointer().px_2().py_1().rounded_md()
                    .bg(rgb(p.control)).text_color(rgb(p.secondary)).child("✕")
                    .id("quick_connect-action-98").on_click(cx.listener(|_, _, window, _| window.remove_window()))))
            .child(div().h_flex().items_center().rounded_lg().border_1().border_color(rgb(p.border))
                .bg(rgb(p.control))
                .child(div().flex_1().min_w_0().child(Input::new(&self.search)))
                .child(div().text_xs().text_color(rgb(p.tertiary)).px_3().child("↵")))
            .child(div().flex_1().min_h_0().overflow_y_scrollbar().child(list))
            .child(div().pt_3().border_t_1().border_color(rgb(p.border))
                .h_flex().justify_between().items_center()
                .child(div().text_xs().text_color(rgb(p.secondary)).child(self.status.clone()))
                .child(div().text_xs().text_color(rgb(p.tertiary)).child("Warp ↗")))
    }
}

pub fn open_window(cx:&mut App) {
    let opts=WindowOptions {
        titlebar:None,
        window_bounds:Some(WindowBounds::centered(size(px(460.),px(500.)),cx)),
        kind:WindowKind::Floating,
        is_resizable:false,
        ..WindowOptions::default()
    };
    if let Err(err)=cx.open_window(opts,|window,cx| {
        let view=cx.new(|cx|QuickConnect::new(window,cx));
        cx.new(|cx|Root::new(view,window,cx))
    }) {
        eprintln!("unable to open Quick Connect: {err:?}");
    }
}
