use crate::db::Repository;
use crate::model::{AuthMode, Group, Host, HostInput, HostSource};
use crate::paths::AppPaths;
use crate::{ssh, warp};
use anyhow::{bail, Context, Result};
use std::collections::HashMap;
use std::time::{SystemTime, UNIX_EPOCH};
use uuid::Uuid;

pub struct Manager { pub paths: AppPaths, pub db: Repository }

#[derive(Debug)]
pub struct DoctorReport {
    pub include_enabled: bool,
    pub managed_hosts: usize,
    pub imported_hosts: usize,
    pub warp_config_directory: std::path::PathBuf,
    pub ssh_config: std::path::PathBuf,
    pub ssh_available: bool,
    pub open_available: bool,
}

impl Manager {
    pub fn open(paths: AppPaths) -> Result<Self> {
        let db=Repository::open(&paths.database())?;
        Ok(Self{paths,db})
    }

    pub fn discover() -> Result<Self> { Self::open(AppPaths::discover()?) }

    /// Explicit opt-in operation that modifies ~/.ssh/config (creating a backup).
    pub fn initialize_ssh(&self) -> Result<bool> {
        let hosts=self.db.list_hosts()?;
        ssh::atomic_write(&self.paths.managed_ssh,&ssh::render_managed_config(&hosts)?)?;
        ssh::install_include(&self.paths)
    }

    fn check_alias_conflict(&self, alias:&str, self_id:Option<Uuid>) -> Result<()> {
        ssh::validate_alias(alias)?;
        if let Some(existing)=self.db.find_alias(alias)? {
            if Some(existing.id)!=self_id { bail!("SSH alias '{alias}' is already managed or imported"); }
        }
        let aliases=ssh::find_aliases(&self.paths.ssh_config)?;
        let matches_external=aliases.iter().any(|a|a.eq_ignore_ascii_case(alias));
        let old_alias=self_id.and_then(|id| self.db.get_host(id).ok().flatten()).map(|h|h.alias);
        if matches_external && old_alias.as_deref()!=Some(alias) {
            bail!("SSH alias '{alias}' already exists in SSH config; import it instead of overwriting");
        }
        Ok(())
    }

    pub fn add_managed(&self, input:HostInput) -> Result<Host> {
        if !ssh::include_installed(&self.paths)? { bail!("run `wsm init` before adding managed hosts"); }
        self.check_alias_conflict(&input.alias,None)?;
        let host=input.into_host(HostSource::Managed);
        ssh::validate_host(&host)?;
        self.db.save_host(&host)?;
        if let Err(err)=self.refresh_managed() {
            let _=self.db.delete_host(host.id);
            return Err(err).context("config write failed; database insertion rolled back");
        }
        Ok(host)
    }

    pub fn update_host(&self, host:Host) -> Result<()> {
        let previous=self.db.get_host(host.id)?.context("host not found")?;
        if host.source != previous.source { bail!("cannot change a host's source type"); }
        if previous.source==HostSource::Imported {
            // Imported config values come from user files; only metadata may be changed.
            if host.alias!=previous.alias || host.hostname!=previous.hostname || host.username!=previous.username
                || host.port!=previous.port || host.identity_file!=previous.identity_file || host.proxy_jump!=previous.proxy_jump {
                bail!("imported host connection settings are read-only; edit ~/.ssh/config instead");
            }
        } else {
            self.check_alias_conflict(&host.alias,Some(host.id))?;
            ssh::validate_host(&host)?;
        }
        self.db.save_host(&host)?;
        if let Err(err)=self.refresh_managed().and_then(|_| self.refresh_tab_if_exists(&host)) {
            let _=self.db.save_host(&previous);
            let _=self.refresh_managed();
            return Err(err).context("update failed; database state restored");
        }
        Ok(())
    }

    pub fn delete_host(&self,id:Uuid) -> Result<()> {
        let old=self.db.get_host(id)?.context("host not found")?;
        self.db.delete_host(id)?;
        if let Err(err)=self.refresh_managed() {
            let _=self.db.save_host(&old);
            let _=self.refresh_managed();
            return Err(err);
        }
        warp::remove_tab(&self.paths,id)?;
        Ok(())
    }

    fn validate_group(&self,name:&str,parent_id:Option<Uuid>,self_id:Option<Uuid>) -> Result<String> {
        let name=name.trim();
        if name.is_empty() || name.chars().count()>120 || name.chars().any(char::is_control) {
            bail!("invalid group name (1–120 printable characters)");
        }
        let groups=self.db.list_groups()?;
        if let Some(parent)=parent_id {
            if !groups.iter().any(|g|g.id==parent) { bail!("parent group not found"); }
            let mut cursor=Some(parent);
            let mut visited=std::collections::HashSet::new();
            while let Some(id)=cursor {
                if Some(id)==self_id { bail!("cannot move group beneath itself or a descendant"); }
                if !visited.insert(id) { bail!("cycle in group hierarchy"); }
                cursor=groups.iter().find(|g|g.id==id).and_then(|g|g.parent_id);
            }
        }
        if groups.iter().any(|g|Some(g.id)!=self_id && g.parent_id==parent_id
            && g.name.eq_ignore_ascii_case(name)) {
            bail!("duplicate group name under the same parent");
        }
        Ok(name.to_owned())
    }

    pub fn group_add(&self,name:&str,parent_id:Option<Uuid>) -> Result<Group> {
        let name=self.validate_group(name,parent_id,None)?;
        let group=Group{id:Uuid::new_v4(),name,parent_id,sort_order:0};
        self.db.save_group(&group)?;
        Ok(group)
    }

    pub fn group_update(&self,id:Uuid,name:&str,parent_id:Option<Uuid>) -> Result<Group> {
        let mut group=self.db.list_groups()?.into_iter()
            .find(|g|g.id==id).context("group not found")?;
        group.name=self.validate_group(name,parent_id,Some(id))?;
        group.parent_id=parent_id;
        self.db.save_group(&group)?;
        self.sync_existing_tabs()?;
        Ok(group)
    }

    pub fn group_delete(&self,id:Uuid) -> Result<()> {
        if !self.db.delete_group(id)? { bail!("group not found (or still has subgroups)"); }
        self.sync_existing_tabs()?;
        Ok(())
    }

    pub fn refresh_managed(&self) -> Result<()> {
        let hosts=self.db.list_hosts()?;
        if hosts.iter().any(|h|h.source==HostSource::Managed) || ssh::include_installed(&self.paths)? {
            ssh::write_managed(&self.paths,&hosts)?;
        }
        Ok(())
    }

    pub fn import_ssh(&self) -> Result<(usize,usize,Vec<String>)> {
        let aliases=ssh::find_aliases(&self.paths.ssh_config)?;
        let mut added=0;let mut updated=0;let mut errors=Vec::new();
        for alias in aliases {
            let current=self.db.find_alias(&alias)?;
            if matches!(current.as_ref().map(|h|h.source),Some(HostSource::Managed)) { continue; }
            match ssh::effective_config(&alias) {
                Ok(c) => {
                    let mut host=if let Some(h)=current { updated+=1;h } else {
                        added+=1;
                        HostInput{name:alias.clone(),alias:alias.clone(),hostname:c.hostname.clone(),username:c.username.clone(),port:c.port,
                            identity_file:c.identity_file.clone(),proxy_jump:c.proxy_jump.clone(),auth_mode:AuthMode::Auto,group_id:None,favorite:false}
                            .into_host(HostSource::Imported)
                    };
                    host.hostname=c.hostname;host.username=c.username;host.port=c.port;
                    host.identity_file=c.identity_file;host.proxy_jump=c.proxy_jump;
                    self.db.save_host(&host)?;
                }
                Err(e)=>errors.push(format!("{alias}: {e:#}")),
            }
        }
        Ok((added,updated,errors))
    }

    fn group_name(&self, group_id:Option<Uuid>) -> Result<Option<String>> {
        let groups=self.db.list_groups()?;
        Ok(group_id.and_then(|id|groups.iter().find(|g|g.id==id)).map(|g|g.name.clone()))
    }

    pub fn prepare_connection(&self,id:Uuid) -> Result<(Host,std::path::PathBuf)> {
        let host=self.db.get_host(id)?.context("host not found")?;
        if host.source==HostSource::Managed && !ssh::include_installed(&self.paths)? { bail!("SSH Include is missing; run `wsm init`"); }
        let group=self.group_name(host.group_id)?;
        let path=warp::write_tab(&self.paths,&host,group.as_deref())?;
        Ok((host,path))
    }

    /// Explicit one-shot Keychain auto-login; the Rust bridge never sees a password.
    pub fn connect_askpass(&self,id:Uuid,session:Uuid) -> Result<()> {
        let host=self.db.get_host(id)?.context("host not found")?;
        if host.auth_mode!=AuthMode::Password {
            bail!("auto-login requires password authentication mode");
        }
        if host.source==HostSource::Managed && !ssh::include_installed(&self.paths)? {
            bail!("SSH Include is missing; run wsm init");
        }
        let sessions_dir=self.paths.data_dir.join("askpass_sessions");
        if !sessions_dir.join(format!("{}.json",session.simple())).is_file() {
            bail!("auto-login session not found");
        }
        let helper=std::env::current_exe()?
            .parent().context("wsm executable directory missing")?
            .join("wsm-askpass");
        if !helper.is_file() { bail!("wsm-askpass helper not installed"); }
        let launch=warp::AskpassLaunch {session,sessions_dir:&sessions_dir,helper:&helper};
        let group=self.group_name(host.group_id)?;
        warp::write_tab_with_askpass(&self.paths,&host,group.as_deref(),Some(&launch))?;
        warp::open_tab(id,false,false)?;
        let now=SystemTime::now().duration_since(UNIX_EPOCH)?.as_secs() as i64;
        self.db.mark_connected(host.id,now)?;
        Ok(())
    }

    pub fn connect(&self,id:Uuid,new_window:bool,preview:bool) -> Result<()> {
        let (host,_file)=self.prepare_connection(id)?;
        warp::open_tab(id,new_window,preview)?;
        let now=SystemTime::now().duration_since(UNIX_EPOCH)?.as_secs() as i64;
        self.db.mark_connected(host.id,now)?;
        Ok(())
    }

    pub fn refresh_tab_if_exists(&self,host:&Host) -> Result<()> {
        if warp::config_path(&self.paths,host.id).exists() {
            let group=self.group_name(host.group_id)?;
            warp::write_tab(&self.paths,host,group.as_deref())?;
        }
        Ok(())
    }

    pub fn sync_existing_tabs(&self) -> Result<usize> {
        self.refresh_managed()?;
        let mut count=0;
        for host in self.db.list_hosts()? {
            if host.favorite || warp::config_path(&self.paths,host.id).exists() {
                let group=self.group_name(host.group_id)?;
                warp::write_tab(&self.paths,&host,group.as_deref())?;
                count+=1;
            }
        }
        Ok(count)
    }

    pub fn sync_all_tabs(&self)->Result<usize> {
        self.refresh_managed()?;
        let mut count=0;
        let groups:HashMap<Uuid,String>=self.db.list_groups()?.into_iter().map(|g|(g.id,g.name)).collect();
        for host in self.db.list_hosts()? {
            let group=host.group_id.and_then(|id|groups.get(&id).map(String::as_str));
            warp::write_tab(&self.paths,&host,group)?;
            count+=1;
        }
        Ok(count)
    }

    pub fn doctor(&self)->Result<DoctorReport> {
        let hosts=self.db.list_hosts()?;
        Ok(DoctorReport { include_enabled:ssh::include_installed(&self.paths)?,
            managed_hosts:hosts.iter().filter(|h|h.source==HostSource::Managed).count(),
            imported_hosts:hosts.iter().filter(|h|h.source==HostSource::Imported).count(),
            warp_config_directory:self.paths.warp_configs.clone(), ssh_config:self.paths.ssh_config.clone(),
            ssh_available:std::process::Command::new("ssh").arg("-V").output().is_ok(),
            open_available:std::process::Command::new("which").arg("open").output().map(|r|r.status.success()).unwrap_or(false),
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;
    fn fixture() -> (tempfile::TempDir,Manager) {
        let dir=tempfile::tempdir().unwrap();
        let p=AppPaths{data_dir:dir.path().join("data"),ssh_config:dir.path().join("ssh/config"),
            managed_ssh:dir.path().join("ssh/config.d/warp-ssh-manager.conf"),warp_configs:dir.path().join("warp")};
        (dir,Manager::open(p).unwrap())
    }
    fn input(alias:&str)->HostInput {
        HostInput{name:"API".into(),alias:alias.into(),hostname:"example.com".into(),username:"deploy".into(),port:22,
            identity_file:None,proxy_jump:None,auth_mode:AuthMode::Auto,group_id:None,favorite:false}
    }
    #[test] fn lifecycle_and_config_sync() {
        let (_dir,m)=fixture();
        m.initialize_ssh().unwrap();
        let mut h=m.add_managed(input("test-01")).unwrap();
        assert_eq!(m.db.list_hosts().unwrap().len(),1);
        assert!(fs::read_to_string(&m.paths.managed_ssh).unwrap().contains("Host test-01"));
        assert!(m.add_managed(input("test-01")).is_err());
        let (_,path)=m.prepare_connection(h.id).unwrap();
        assert!(path.exists());
        h.name="New Name".into();m.update_host(h.clone()).unwrap();
        assert!(fs::read_to_string(&path).unwrap().contains("New Name"));
        m.delete_host(h.id).unwrap();
        assert!(!path.exists());
        assert!(!fs::read_to_string(&m.paths.managed_ssh).unwrap().contains("Host test-01"));
    }
    #[test] fn imported_config_is_never_overwritten() {
        let (_dir,m)=fixture();
        m.initialize_ssh().unwrap();
        let external="Host user-host\n HostName example.org\n User alice\n";
        fs::write(&m.paths.ssh_config,format!("Include \"{}\"\n{external}",m.paths.managed_ssh.display())).unwrap();
        assert!(m.add_managed(input("user-host")).is_err());
        assert!(fs::read_to_string(&m.paths.ssh_config).unwrap().contains(external));
    }
    #[test] fn nested_group_lifecycle_and_cycle_guards() {
        let (_dir,m)=fixture();
        let root=m.group_add("Team",None).unwrap();
        let child=m.group_add("Services",Some(root.id)).unwrap();
        let grandchild=m.group_add("API",Some(child.id)).unwrap();
        let sibling=m.group_add("Backend",Some(root.id)).unwrap();
        assert!(m.group_add("services",Some(root.id)).is_err());
        assert!(m.group_add("Services",None).is_ok());
        assert!(m.group_update(root.id,"Team",Some(grandchild.id)).is_err());
        assert!(m.group_update(child.id,"Services",Some(child.id)).is_err());
        assert!(m.group_update(sibling.id,"API",Some(child.id)).is_err());
        assert_eq!(m.group_update(grandchild.id,"API",Some(sibling.id)).unwrap().parent_id,Some(sibling.id));
        assert!(m.group_delete(root.id).is_err());
        assert!(m.group_delete(child.id).is_ok());
        assert!(m.group_delete(root.id).is_err());
        assert!(m.group_update(sibling.id,"Backend",None).is_ok());
        assert!(m.group_delete(root.id).is_ok());
        assert_eq!(m.db.list_groups().unwrap().iter().find(|g|g.id==grandchild.id).unwrap().parent_id,Some(sibling.id));
    }
    #[test] fn annotations_preserved_and_removed_with_host() {
        let (_dir,m)=fixture();
        m.initialize_ssh().unwrap();
        let h=m.add_managed(input("annotated-host")).unwrap();
        m.db.save_annotations(h.id,"production,api","Team's entry point").unwrap();
        assert_eq!(m.db.host_annotations(h.id).unwrap(),
            ("production,api".into(),"Team's entry point".into()));
        m.delete_host(h.id).unwrap();
        assert_eq!(m.db.host_annotations(h.id).unwrap(),(String::new(),String::new()));
    }
}
