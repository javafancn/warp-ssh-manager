use anyhow::{Context, Result};
use std::path::PathBuf;

#[derive(Clone, Debug)]
pub struct AppPaths {
    pub data_dir: PathBuf,
    pub ssh_config: PathBuf,
    pub managed_ssh: PathBuf,
    pub warp_configs: PathBuf,
}

impl AppPaths {
    pub fn discover() -> Result<Self> {
        let home = dirs::home_dir().context("cannot determine HOME directory")?;
        let data_dir = std::env::var_os("WSM_HOME")
            .map(PathBuf::from)
            .unwrap_or_else(|| home.join("Library/Application Support/WarpSSHManager"));
        let ssh_config = std::env::var_os("WSM_SSH_CONFIG")
            .map(PathBuf::from)
            .unwrap_or_else(|| home.join(".ssh/config"));
        let ssh_dir = ssh_config.parent().context("SSH config path has no parent")?;
        let managed_ssh = ssh_dir.join("config.d/warp-ssh-manager.conf");
        let warp_configs = std::env::var_os("WSM_WARP_CONFIG_DIR")
            .map(PathBuf::from)
            .unwrap_or_else(|| home.join(".warp/tab_configs"));
        Ok(Self { data_dir, ssh_config, managed_ssh, warp_configs })
    }

    pub fn database(&self) -> PathBuf { self.data_dir.join("hosts.sqlite3") }
}
