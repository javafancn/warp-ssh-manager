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
    let show=MenuItem::new("Open SSH Manager",true,None);
    let quick=MenuItem::new("Quick Connect…",true,None);
    let quit=MenuItem::new("Quit Warp SSH Manager",true,None);
    let show_id=show.id().clone();
    let quick_id=quick.id().clone();
    let quit_id=quit.id().clone();
    let _=menu.append(&show);
    let _=menu.append(&quick);
    let mut favorites=Vec::<(_,Uuid)>::new();
    if let Ok(manager)=Manager::discover() {
        if let Ok(hosts)=manager.db.list_hosts() {
            for host in hosts.into_iter().filter(|h|h.favorite).take(15) {
                let item=MenuItem::new(format!("Connect: {}",host.name),true,None);
                favorites.push((item.id().clone(),host.id));
                let _=menu.append(&item);
            }
        }
    }
    let _=menu.append(&quit);
    // A simple 16x16 status icon with a transparent background.
    let mut rgba=vec![0u8;16*16*4];
    for y in 0..16 {for x in 0..16 {
        let i=(y*16+x)*4;
        if (x>=2 && x<=13) && (y>=3 && y<=12) {
            let bright=(x>=4&&x<=11)&&(y==5||y==6||y==9||y==10);
            rgba[i..i+4].copy_from_slice(if bright{&[255,255,255,255]}else{&[49,133,201,255]});
        }
    }}
    let icon=match Icon::from_rgba(rgba,16,16) {Ok(icon)=>icon,Err(_)=>return};
    let tray=match TrayIconBuilder::new().with_icon(icon).with_tooltip("Warp SSH Manager")
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
