//! Native macOS menu-bar integration. The menu contains a snapshot of favorites at launch;
//! changes to favorite items show in the main window immediately and after restart in the menu.
#[cfg(target_os="macos")]
pub fn install(cx: &mut gpui::App) {
    use gpui::AppContext;
    use std::time::Duration;
    use tray_icon::{menu::{Menu,MenuEvent,MenuItem},Icon,TrayIconBuilder};
    use uuid::Uuid;
    use wsm_core::Manager;

    let menu=Menu::new();
    let show=MenuItem::new("打开 SSH 管理器",true,None);
    let quick=MenuItem::new("快速连接…",true,None);
    let quit=MenuItem::new("退出 Warp SSH 管理器",true,None);
    let show_id=show.id().clone();
    let quick_id=quick.id().clone();
    let quit_id=quit.id().clone();
    let _=menu.append(&show);
    let _=menu.append(&quick);
    let mut favorites=Vec::<(_,Uuid)>::new();
    if let Ok(manager)=Manager::discover() {
        if let Ok(hosts)=manager.db.list_hosts() {
            for host in hosts.into_iter().filter(|h|h.favorite).take(15) {
                let item=MenuItem::new(format!("连接：{}",host.name),true,None);
                favorites.push((item.id().clone(),host.id));
                let _=menu.append(&item);
            }
        }
    }
    let _=menu.append(&quit);
    // A small double-chevron silhouette is recognizable in the macOS menu bar.
    // Use a neutral status-item glyph rather than the full-color Dock artwork.
    let mut rgba=vec![0u8;32*32*4];
    for y in 0..32usize {for x in 0..32usize {
        let glyph = |shift: f32| {
            let xx=x as f32-shift;
            let yy=y as f32;
            let center=15.5f32;
            let distance=(yy-center).abs();
            let arm=(12.0-distance*0.82).max(0.0);
            xx >= 1.0+arm && xx <= 7.0+arm && (yy>=4.0 && yy<=28.0)
        };
        let a=glyph(1.0) || glyph(12.0);
        if a {
            let i=(y*32+x)*4;
            rgba[i..i+4].copy_from_slice(&[25,39,63,255]);
        }
    }}
    let icon=match Icon::from_rgba(rgba,32,32) {Ok(icon)=>icon,Err(_)=>return};
    let tray=match TrayIconBuilder::new().with_icon(icon).with_tooltip("Warp SSH 管理器")
        .with_menu(Box::new(menu)).build() {Ok(tray)=>tray,Err(error)=>{eprintln!("tray failed: {error}");return}};
    cx.spawn(async move |cx| {
        // Keep the native status item alive for the lifetime of the async task.
        let _tray=tray;
        loop {
            cx.background_executor().timer(Duration::from_millis(120)).await;
            while let Ok(event)=MenuEvent::receiver().try_recv() {
                if event.id==quit_id {let _=cx.update(|app|app.quit());return;}
                if event.id==show_id {let _=cx.update(|app|app.activate(true));}
                if event.id==quick_id {
                    let _=cx.update(|app|super::quick_connect::open_window(app));
                }
                for (id,host_id) in &favorites {
                    if event.id==*id {
                        if let Ok(manager)=Manager::discover() {
                            if let Err(error)=manager.connect(*host_id,false,false) {
                                eprintln!("menu-bar SSH launch: {error:#}");
                            }
                        }
                    }
                }
            }
        }
    }).detach();
}

#[cfg(not(target_os="macos"))]
pub fn install(_: &mut gpui::App) {}
