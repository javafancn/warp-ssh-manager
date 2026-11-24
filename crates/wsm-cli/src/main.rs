mod ui;
use anyhow::{Context, Result};
use clap::{Parser, Subcommand};
use std::collections::HashMap;
use uuid::Uuid;
use wsm_core::import::{ImportCandidate, ImportStatus};
use wsm_core::ssh::EffectiveSsh;
use wsm_core::{AuthMode, HostInput, Manager};

#[derive(Parser)]
#[command(name="wsm",about="Warp SSH Manager — native SSH host management for Warp",version)]
struct Cli { #[command(subcommand)] command: Commands }

#[derive(Subcommand)]
enum Commands {
    /// Structured local JSON API for the native SwiftUI application.
    Ui { #[command(subcommand)] action: ui::UiCommand },
    /// Explicitly authorize an Include in ~/.ssh/config (makes a backup).
    Init,
    /// Check installation and paths.
    Doctor,
    /// Import existing OpenSSH aliases without changing their files.
    Import {
        /// Show the changes that would be imported.
        #[arg(long)]
        dry_run: bool,
        /// Select an SSH alias (repeat for multiple aliases).
        #[arg(long = "alias", value_name = "ALIAS")]
        aliases: Vec<String>,
    },
    /// Show known hosts.
    List { #[arg(short,long)] search:Option<String> },
    /// Create a managed SSH host (run init first).
    Add {
        #[arg(long)] name:String, #[arg(long)] alias:String,
        #[arg(long)] hostname:String, #[arg(long)] user:String,
        #[arg(long,default_value_t=22)] port:u16,
        #[arg(long)] identity:Option<String>, #[arg(long)] jump:Option<String>,
        #[arg(long)] group:Option<Uuid>, #[arg(long)] favorite:bool,
    },
    /// Edit host metadata/connection fields (connection fields are read-only for imported hosts).
    Edit {
        id:Uuid, #[arg(long)] name:Option<String>, #[arg(long)] alias:Option<String>,
        #[arg(long)] hostname:Option<String>, #[arg(long)] user:Option<String>,
        #[arg(long)] port:Option<u16>, #[arg(long)] identity:Option<String>,
        #[arg(long)] jump:Option<String>, #[arg(long)] group:Option<Uuid>,
        #[arg(long)] no_group:bool,
    },
    /// Delete a host from manager; imported OpenSSH files are untouched.
    Delete { id:Uuid },
    /// Toggle a host as favorite.
    Favorite { id:Uuid, #[arg(long)] off:bool },
    /// Generate the config and dispatch a Warp URI.
    Connect { id:Uuid, #[arg(long)] new_window:bool, #[arg(long)] preview:bool,
        #[arg(long)] dry_run:bool },
    /// Regenerate favorites and existing config files (or all if --all).
    Sync { #[arg(long)] all:bool },
    /// Group management.
    Group { #[command(subcommand)] action:GroupCmd },
}

#[derive(Subcommand)]
enum GroupCmd {
    List,
    Add { name:String, #[arg(long)] parent:Option<Uuid> },
    Edit { id:Uuid, #[arg(long)] name:Option<String>,
        #[arg(long,conflicts_with="root")] parent:Option<Uuid>,
        #[arg(long)] root:bool },
    Delete { id:Uuid },
}

fn main() {
    if let Err(error)=run() { eprintln!("Error: {error:#}");std::process::exit(1); }
}

fn print_import_candidate(row: &ImportCandidate) {
    let status = match row.status {
        ImportStatus::New => "new",
        ImportStatus::Update => "update",
        ImportStatus::Unchanged => "unchanged",
        ImportStatus::Managed => "managed",
        ImportStatus::Conflict => "conflict",
        ImportStatus::Error => "error",
    };
    fn target(config: &EffectiveSsh) -> String {
        format!(
            "{}@{} port {} (IdentityFile {}, ProxyJump {})",
            config.username, config.hostname, config.port,
            config.identity_file.as_deref().unwrap_or("none"),
            config.proxy_jump.as_deref().unwrap_or("none"),
        )
    }
    print!("{status}\t{}", row.alias);
    if let (ImportStatus::Update, Some(before), Some(after)) = (row.status, &row.before, &row.after) {
        print!("\t{} -> {}", target(before), target(after));
    } else if let Some(after) = &row.after {
        print!("\t{}", target(after));
    }
    if let Some(detail) = &row.detail { print!("\t{}", detail.trim()); }
    println!();
}

fn run()->Result<()> {
    let cli=Cli::parse();
    let manager=Manager::discover()?;
    match cli.command {
        Commands::Ui {action} => ui::run(&manager, action)?,
        Commands::Init=> {
            let changed=manager.initialize_ssh()?;
            println!("SSH integration: {}",if changed {"enabled; original config backed up if present"}else{"already installed"});
            println!("Managed SSH file: {}",manager.paths.managed_ssh.display());
        }
        Commands::Doctor=> {
            let r=manager.doctor()?;
            println!("OpenSSH found: {}\nmacOS open found: {}\nSSH Include installed: {}",r.ssh_available,r.open_available,r.include_enabled);
            println!("Managed hosts: {}\nImported hosts: {}",r.managed_hosts,r.imported_hosts);
            println!("SSH config: {}\nWarp Tab Configs: {}",r.ssh_config.display(),r.warp_config_directory.display());
        }
        Commands::Import { dry_run, aliases } => {
            if dry_run {
                let preview = manager.preview_ssh_import(&aliases)?;
                println!("SSH config: {}", preview.config_path.display());
                if preview.candidates.is_empty() { println!("No SSH aliases found"); }
                for row in &preview.candidates { print_import_candidate(row); }
            } else {
                let (report, warnings) = manager.import_ssh_aliases(&aliases)?;
                println!("Imported {} new, updated {} existing hosts", report.added, report.updated);
                for warning in warnings { eprintln!("Warning: {warning}"); }
            }
        }
        Commands::List{search}=> {
            let groups:HashMap<_,_>=manager.db.list_groups()?.into_iter().map(|g|(g.id,g.name)).collect();
            for h in manager.db.list_hosts()? {
                let g=h.group_id.and_then(|id|groups.get(&id)).map(String::as_str).unwrap_or("Ungrouped");
                let search_match=search.as_ref().is_none_or(|s|{
                    let needle=s.to_lowercase();
                    [h.name.as_str(),h.alias.as_str(),h.hostname.as_str(),g].iter().any(|v|v.to_lowercase().contains(&needle))
                });
                if search_match {println!("{} {} {:22} {:20} {}@{}:{} [{}]",h.id,if h.favorite{"★"}else{" "},h.name,h.alias,h.username,h.hostname,h.port,g);}
            }
        }
        Commands::Add{name,alias,hostname,user,port,identity,jump,group,favorite}=> {
            let h=manager.add_managed(HostInput{name,alias,hostname,username:user,port,identity_file:identity,
                proxy_jump:jump,auth_mode:AuthMode::Auto,group_id:group,favorite})?;
            println!("Created {} ({})",h.name,h.id);
        }
        Commands::Edit{id,name,alias,hostname,user,port,identity,jump,group,no_group}=> {
            let mut h=manager.db.get_host(id)?.context("host not found")?;
            if let Some(v)=name{h.name=v} if let Some(v)=alias{h.alias=v}
            if let Some(v)=hostname{h.hostname=v} if let Some(v)=user{h.username=v}
            if let Some(v)=port{h.port=v} if let Some(v)=identity{h.identity_file=Some(v)}
            if let Some(v)=jump{h.proxy_jump=Some(v)}
            if let Some(v)=group{h.group_id=Some(v)} if no_group{h.group_id=None}
            manager.update_host(h)?; println!("Host updated");
        }
        Commands::Delete{id}=> {manager.delete_host(id)?;println!("Host removed from manager");}
        Commands::Favorite{id,off}=> {
            let mut h=manager.db.get_host(id)?.context("host not found")?;
            h.favorite=!off;
            manager.update_host(h)?;
            manager.sync_existing_tabs()?;
            println!("Favorite: {}",!off);
        }
        Commands::Connect{id,new_window,preview,dry_run}=> {
            if dry_run {
                let h=manager.db.get_host(id)?.context("host not found")?;
                let group=h.group_id.and_then(|id|manager.db.list_groups().ok()?.into_iter().find(|g|g.id==id).map(|g|g.name));
                println!("{}",wsm_core::warp::render_tab_config(&h,group.as_deref())?);
                println!("Would open: {}://tab_config/{}{}",if preview{"warppreview"}else{"warp"},wsm_core::warp::config_stem(id),if new_window{"?new_window=true"}else{""});
            } else {manager.connect(id,new_window,preview)?;println!("Warp open request sent (SSH success cannot be observed from this app)");}
        }
        Commands::Sync{all}=> {let n=if all{manager.sync_all_tabs()?}else{manager.sync_existing_tabs()?};println!("Synchronized {n} Tab Configs");}
        Commands::Group{action}=>match action {
            GroupCmd::List=>for g in manager.db.list_groups()? {
                println!("{} {} parent={}",g.id,g.name,g.parent_id.map(|id|id.to_string()).unwrap_or_else(||"none".into()));
            },
            GroupCmd::Add{name,parent}=> {let g=manager.group_add(&name,parent)?;println!("Added group '{}' {}",g.name,g.id);},
            GroupCmd::Edit{id,name,parent,root}=> {
                let old=manager.db.list_groups()?.into_iter().find(|g|g.id==id)
                    .ok_or_else(||anyhow::anyhow!("group not found"))?;
                let new_parent=if root{None}else{parent.or(old.parent_id)};
                let g=manager.group_update(id,name.as_deref().unwrap_or(&old.name),new_parent)?;
                println!("Updated group '{}' {}",g.name,g.id);
            },
            GroupCmd::Delete{id}=>{manager.group_delete(id)?;println!("Group deleted");}
        }
    }
    Ok(())
}
