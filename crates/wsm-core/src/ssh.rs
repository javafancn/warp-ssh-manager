use anyhow::{bail, Context, Result};
use glob::glob;
use std::collections::{BTreeSet, HashSet};
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;
use uuid::Uuid;

use crate::model::Host;
use crate::paths::AppPaths;

/// Restrict aliases to a conservative subset that is safe in a shell startup command.
pub fn validate_alias(value: &str) -> Result<()> {
    let bytes = value.as_bytes();
    if bytes.is_empty() || bytes.len() > 128 || !bytes[0].is_ascii_alphanumeric()
        || !bytes.iter().all(|&c| c.is_ascii_alphanumeric() || b"._-".contains(&c))
    {
        bail!("SSH alias must start with a letter/digit and contain only A-Z, 0-9, dot, _ or - (max 128)");
    }
    Ok(())
}

fn safe_token(v: &str, field: &str) -> Result<()> {
    if v.is_empty() || v.len() > 1024 || v.chars().any(|c| c.is_control()) || v.contains('"') || v.contains('\\')
        || v.chars().any(char::is_whitespace)
    {
        bail!("{field} contains unsupported characters");
    }
    Ok(())
}

pub fn validate_host(host: &Host) -> Result<()> {
    validate_alias(&host.alias)?;
    if host.name.trim().is_empty() || host.name.chars().any(char::is_control) || host.name.len() > 200 {
        bail!("host display name is empty, too long or contains control characters");
    }
    safe_token(&host.hostname, "hostname")?;
    if host.hostname.starts_with('-') { bail!("hostname cannot start with a dash"); }
    safe_token(&host.username, "username")?;
    if host.username.starts_with('-') { bail!("username cannot start with a dash"); }
    if host.port == 0 { bail!("port must be 1..65535"); }
    if let Some(v) = &host.identity_file { safe_token(v, "identity file")?; }
    if let Some(v) = &host.proxy_jump {
        safe_token(v, "proxy jump")?;
        if !v.chars().all(|ch| ch.is_ascii_alphanumeric() || "._-@:,[]%".contains(ch)) {
            bail!("proxy jump contains unsafe characters");
        }
    }
    Ok(())
}

pub fn render_managed_config(hosts: &[Host]) -> Result<String> {
    let mut output = String::from("# Managed by Warp SSH Manager. Changes may be overwritten.\n# Do not place secrets in this file.\n\n");
    let mut sorted = hosts.iter().filter(|h| h.source == crate::model::HostSource::Managed).collect::<Vec<_>>();
    sorted.sort_by(|a,b| a.alias.to_lowercase().cmp(&b.alias.to_lowercase()));
    for host in sorted {
        validate_host(host)?;
        output.push_str(&format!("Host {}\n    HostName {}\n    User {}\n    Port {}\n", host.alias, host.hostname,host.username,host.port));
        if let Some(key) = &host.identity_file { output.push_str(&format!("    IdentityFile {}\n", key)); }
        if let Some(jump) = &host.proxy_jump { output.push_str(&format!("    ProxyJump {}\n", jump)); }
        output.push('\n');
    }
    Ok(output)
}

/// Atomic replacement with no followed symlinks, retaining restrictive permissions.
pub fn atomic_write(path: &Path, content: &str) -> Result<()> {
    if path.is_symlink() { bail!("refusing to overwrite symlink: {}",path.display()); }
    let parent=path.parent().context("file has no parent")?;
    fs::create_dir_all(parent)?;
    let temp=parent.join(format!(".wsm-{}.tmp",Uuid::new_v4()));
    let result=(|| -> Result<()> {
        use std::io::Write;
        let mut options=fs::OpenOptions::new();
        options.create_new(true).write(true);
        #[cfg(unix)] {
            use std::os::unix::fs::OpenOptionsExt;
            options.mode(0o600);
        }
        let mut f=options.open(&temp)?;
        f.write_all(content.as_bytes())?;
        f.sync_all()?;
        fs::rename(&temp,path)?;
        Ok(())
    })();
    if result.is_err() { let _=fs::remove_file(&temp); }
    result
}

fn include_directive(paths:&AppPaths) -> Result<String> {
    let s=paths.managed_ssh.to_str().context("non-UTF8 managed SSH path")?;
    if s.chars().any(|ch| matches!(ch, '\n' | '\r' | '"')) { bail!("unsupported SSH path characters"); }
    Ok(format!("Include \"{s}\""))
}

pub fn include_installed(paths: &AppPaths) -> Result<bool> {
    if !paths.ssh_config.exists() { return Ok(false); }
    let value=fs::read_to_string(&paths.ssh_config)?;
    let wanted=include_directive(paths)?;
    Ok(value.lines().any(|line| line.trim() == wanted))
}

/// Invoked only from an explicit "init" user action. Backs up an existing SSH config.
pub fn install_include(paths: &AppPaths) -> Result<bool> {
    let dir=paths.ssh_config.parent().context("SSH config without directory")?;
    fs::create_dir_all(dir)?;
    #[cfg(unix)] {
        use std::os::unix::fs::PermissionsExt;
        fs::set_permissions(dir, fs::Permissions::from_mode(0o700))?;
    }
    if paths.ssh_config.is_symlink() { bail!("refusing to edit symlinked ~/.ssh/config"); }
    if include_installed(paths)? { return Ok(false); }
    let existing = if paths.ssh_config.exists() { fs::read_to_string(&paths.ssh_config)? } else { String::new() };
    if paths.ssh_config.exists() {
        let backup=paths.ssh_config.with_extension(format!("wsm-backup-{}",Uuid::new_v4()));
        fs::copy(&paths.ssh_config, &backup).context("creating SSH config backup")?;
        #[cfg(unix)] {
            use std::os::unix::fs::PermissionsExt;
            fs::set_permissions(&backup, fs::Permissions::from_mode(0o600))?;
        }
    }
    let content=format!("{}\n{}",include_directive(paths)?, existing);
    atomic_write(&paths.ssh_config,&content)?;
    Ok(true)
}

pub fn write_managed(paths: &AppPaths, hosts: &[Host]) -> Result<()> {
    if !include_installed(paths)? { bail!("managed SSH include is not enabled; run `wsm init` first"); }
    let value=render_managed_config(hosts)?;
    if let Some(dir)=paths.managed_ssh.parent() {
        fs::create_dir_all(dir)?;
        #[cfg(unix)] {
            use std::os::unix::fs::PermissionsExt;
            fs::set_permissions(dir,fs::Permissions::from_mode(0o700))?;
        }
    }
    atomic_write(&paths.managed_ssh,&value)
}

/// Parse the literal aliases in the Host directives (not wildcard patterns). Recursively follows Include.
pub fn find_aliases(root: &Path) -> Result<Vec<String>> {
    let mut out=BTreeSet::new();
    let mut visited=HashSet::new();
    read_aliases(root,&mut visited,&mut out,0)?;
    Ok(out.into_iter().collect())
}

fn read_aliases(file: &Path, visited: &mut HashSet<PathBuf>, out: &mut BTreeSet<String>, depth: usize) -> Result<()> {
    if depth>12 { bail!("SSH Include depth exceeded 12"); }
    if !file.exists() { return Ok(()); }
    let canonical=fs::canonicalize(file)?;
    if !visited.insert(canonical) { return Ok(()); }
    let content=fs::read_to_string(file).with_context(||format!("reading {}",file.display()))?;
    for line in content.lines() {
        let s=line.trim();
        if s.is_empty() || s.starts_with('#') { continue; }
        let mut parts=s.split_whitespace();
        match parts.next().unwrap_or("").to_ascii_lowercase().as_str() {
            "host" => {
                for item in parts.take_while(|p|!p.starts_with('#')) {
                    if validate_alias(item).is_ok() { out.insert(item.to_string()); }
                }
            }
            "include" => {
                for pattern in parts.take_while(|p|!p.starts_with('#')) {
                    let pattern=pattern.trim_matches('"');
                    let resolved=if let Some(tail)=pattern.strip_prefix("~/") {
                        dirs::home_dir().unwrap_or_default().join(tail)
                    } else if Path::new(pattern).is_absolute() { PathBuf::from(pattern) }
                    else { file.parent().unwrap_or(Path::new(".")).join(pattern) };
                    let expr=resolved.to_string_lossy();
                    if let Ok(globbed)=glob(&expr) {
                        for item in globbed.flatten() {
                            if item.is_file() { read_aliases(&item,visited,out,depth+1)?; }
                        }
                    }
                }
            }
            _ => {}
        }
    }
    Ok(())
}

#[derive(Clone, Debug)]
pub struct EffectiveSsh {
    pub hostname: String,
    pub username: String,
    pub port: u16,
    pub identity_file: Option<String>,
    pub proxy_jump: Option<String>,
}

/// Uses OpenSSH's own configuration resolver. Does not initiate a network connection.
pub fn effective_config(alias: &str) -> Result<EffectiveSsh> {
    validate_alias(alias)?;
    let output=Command::new("ssh").arg("-G").arg(alias).output().context("running ssh -G")?;
    if !output.status.success() { bail!("ssh -G {alias} failed: {}",String::from_utf8_lossy(&output.stderr)); }
    let text=String::from_utf8(output.stdout)?;
    let mut hostname=String::new(); let mut username=String::new(); let mut port=22u16;
    let mut identity_file=None; let mut proxy_jump=None;
    for line in text.lines() {
        let mut parts=line.splitn(2,' ');
        let key=parts.next().unwrap_or("");
        let value=parts.next().unwrap_or("").trim();
        match key {
            "hostname" => hostname=value.to_string(),
            "user" => username=value.to_string(),
            "port" => port=value.parse().context("invalid SSH port")?,
            "identityfile" if identity_file.is_none() => identity_file=Some(value.to_string()),
            "proxyjump" if value!="none" => proxy_jump=Some(value.to_string()),
            _=>{}
        }
    }
    if hostname.is_empty() || username.is_empty() { bail!("ssh -G returned incomplete configuration for {alias}"); }
    Ok(EffectiveSsh{hostname,username,port,identity_file,proxy_jump})
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::model::{HostInput,HostSource};
    #[test] fn rejects_shell_injection_aliases() {
        for alias in ["-oProxyCommand", "prod;rm", "foo bar", "$(id)", "a\nb", ""] {
            assert!(validate_alias(alias).is_err(),"{alias}");
        }
        assert!(validate_alias("prod-api_01.internal").is_ok());
    }
    #[test] fn rejects_config_injection() {
        let mut host=HostInput{name:"Prod".into(),alias:"prod".into(),hostname:"example.com\nProxyCommand rm".into(),
            username:"root".into(),port:22,identity_file:None,proxy_jump:None,group_id:None,favorite:false}.into_host(HostSource::Managed);
        assert!(render_managed_config(&[host.clone()]).is_err());
        host.hostname="example.com".into();
        assert!(render_managed_config(&[host]).unwrap().contains("Host prod"));
    }
    #[test] fn aliases_and_includes() {
        let dir=tempfile::tempdir().unwrap();
        fs::write(dir.path().join("more.conf"),"Host dev-a dev-b\n HostName some.net\n").unwrap();
        fs::write(dir.path().join("config"),"Host *\n User root\nHost prod\nInclude more.conf\nHost !negated other\n").unwrap();
        assert_eq!(find_aliases(&dir.path().join("config")).unwrap(), vec!["dev-a","dev-b","other","prod"]);
    }
    #[test] fn install_include_is_idempotent_and_preserves_config() {
        let d=tempfile::tempdir().unwrap(); let paths=AppPaths {
            data_dir:d.path().join("data"),ssh_config:d.path().join(".ssh/config"),
            managed_ssh:d.path().join(".ssh/config.d/warp-ssh-manager.conf"),warp_configs:d.path().join("warp")
        };
        fs::create_dir_all(paths.ssh_config.parent().unwrap()).unwrap();
        fs::write(&paths.ssh_config,"Host old\n HostName old.example\n").unwrap();
        assert!(install_include(&paths).unwrap());
        assert!(!install_include(&paths).unwrap());
        let text=fs::read_to_string(&paths.ssh_config).unwrap();
        assert_eq!(text.matches("Include ").count(),1);
        assert!(text.contains("Host old"));
    }
}
