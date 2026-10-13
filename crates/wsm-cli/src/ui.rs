//! Stable, JSON-only IPC used by the bundled SwiftUI front end.
use anyhow::{Context, Result, bail};
use clap::Subcommand;
use serde::{Deserialize, Serialize};
use std::io::{self, Read};
use uuid::Uuid;
use wsm_core::{AuthMode, Group, Host, HostInput, HostSource, Manager};

#[derive(Subcommand)]
pub enum UiCommand {
    /// Emit the full state in one transaction-like read.
    Snapshot,
    /// Read a JSON host draft from stdin. Existing hosts are updated by id.
    Save,
    Delete { id: Uuid },
    Favorite { id: Uuid, value: String },
    Connect { id: Uuid, #[arg(long)] askpass_session: Option<Uuid> },
    Init,
    Import,
    AddGroup { name: String, #[arg(long)] parent: Option<Uuid> },
    UpdateGroup { id: Uuid, name: String,
        #[arg(long,conflicts_with = "root")] parent: Option<Uuid>,
        #[arg(long)] root: bool },
    DeleteGroup { id: Uuid },
}

#[derive(Serialize)]
struct UiHost {
    #[serde(flatten)]
    host: Host,
    tags: String,
    notes: String,
}
#[derive(Serialize)]
struct Snapshot {
    hosts: Vec<UiHost>,
    groups: Vec<Group>,
    include_enabled: bool,
}
#[derive(Deserialize)]
struct Draft {
    id: Option<Uuid>,
    name: String,
    alias: String,
    hostname: String,
    username: String,
    port: u16,
    identity_file: Option<String>,
    proxy_jump: Option<String>,
    #[serde(default)]
    auth_mode: AuthMode,
    group_id: Option<Uuid>,
    favorite: bool,
    tags: String,
    notes: String,
}

fn snapshot(manager: &Manager) -> Result<Snapshot> {
    let hosts = manager.db.list_hosts()?.into_iter().map(|host| {
        let (tags, notes) = manager.db.host_annotations(host.id)?;
        Ok(UiHost { host, tags, notes })
    }).collect::<Result<Vec<_>>>()?;
    Ok(Snapshot {
        hosts,
        groups: manager.db.list_groups()?,
        include_enabled: wsm_core::ssh::include_installed(&manager.paths)?,
    })
}

fn read_draft() -> Result<Draft> {
    let mut input = String::new();
    io::stdin().take(128 * 1024).read_to_string(&mut input)?;
    Ok(serde_json::from_str(&input).context("invalid host JSON from UI")?)
}

fn save(manager: &Manager) -> Result<()> {
    let draft = read_draft()?;
    if draft.name.trim().is_empty() || draft.alias.trim().is_empty()
        || draft.hostname.trim().is_empty() || draft.username.trim().is_empty() {
        bail!("显示名称、SSH 别名、主机/IP 和用户名不能为空");
    }
    let host = if let Some(id) = draft.id {
        let mut host = manager.db.get_host(id)?.context("host not found")?;
        host.name = draft.name;
        host.favorite = draft.favorite;
        host.group_id = draft.group_id;
        host.auth_mode = draft.auth_mode;
        if host.source == HostSource::Managed {
            host.alias = draft.alias;
            host.hostname = draft.hostname;
            host.username = draft.username;
            host.port = draft.port;
            host.identity_file = draft.identity_file;
            host.proxy_jump = draft.proxy_jump;
        }
        manager.update_host(host.clone())?;
        host
    } else {
        manager.add_managed(HostInput {
            name: draft.name,
            alias: draft.alias,
            hostname: draft.hostname,
            username: draft.username,
            port: draft.port,
            identity_file: draft.identity_file,
            proxy_jump: draft.proxy_jump,
            auth_mode: draft.auth_mode,
            group_id: draft.group_id,
            favorite: draft.favorite,
        })?
    };
    manager.db.save_annotations(host.id, &draft.tags, &draft.notes)?;
    println!("{}", serde_json::json!({"id": host.id}));
    Ok(())
}

pub fn run(manager: &Manager, command: UiCommand) -> Result<()> {
    match command {
        UiCommand::Snapshot => println!("{}", serde_json::to_string(&snapshot(manager)?)?),
        UiCommand::Save => save(manager)?,
        UiCommand::Delete {id} => manager.delete_host(id)?,
        UiCommand::Favorite {id, value} => {
            let favorite = match value.as_str() {
                "true" => true,
                "false" => false,
                _ => bail!("favorite value must be true or false"),
            };
            let mut h = manager.db.get_host(id)?.context("host not found")?;
            h.favorite = favorite;
            manager.update_host(h)?;
            manager.sync_existing_tabs()?;
        }
        UiCommand::Connect {id,askpass_session} => {
            if let Some(session)=askpass_session {manager.connect_askpass(id,session)?;}
            else {manager.connect(id,false,false)?;}
        },
        UiCommand::Init => {manager.initialize_ssh()?;},
        UiCommand::Import => {
            let (_added, _updated, errors) = manager.import_ssh()?;
            for error in errors {eprintln!("Warning: {error}");}
        }
        UiCommand::AddGroup {name,parent} => {
            let group=manager.group_add(&name,parent)?;
            println!("{}",serde_json::json!({"id":group.id}));
        },
        UiCommand::UpdateGroup {id,name,parent,root} => {
            let existing=manager.db.list_groups()?.into_iter()
                .find(|g|g.id==id).context("group not found")?;
            let parent_id=if root {None} else {parent.or(existing.parent_id)};
            manager.group_update(id,&name,parent_id)?;
        },
        UiCommand::DeleteGroup {id} => {manager.group_delete(id)?;},
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use wsm_core::AppPaths;
    #[test]
    fn snapshot_uses_existing_database_without_demo_hosts() {
        let temp = tempfile::tempdir().unwrap();
        let paths = AppPaths {
            data_dir: temp.path().join("data"),
            ssh_config: temp.path().join(".ssh/config"),
            managed_ssh: temp.path().join(".ssh/config.d/managed"),
            warp_configs: temp.path().join("warp"),
        };
        let manager = Manager::open(paths).unwrap();
        let state = snapshot(&manager).unwrap();
        assert!(state.hosts.is_empty());
        assert!(state.groups.is_empty());
        assert!(!state.include_enabled);
    }
}
