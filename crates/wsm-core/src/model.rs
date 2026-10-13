use serde::{Deserialize, Serialize};
use uuid::Uuid;

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub enum HostSource {
    Managed,
    Imported,
}

impl HostSource {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Managed => "managed",
            Self::Imported => "imported",
        }
    }
    pub fn from_db(value: &str) -> anyhow::Result<Self> {
        match value {
            "managed" => Ok(Self::Managed),
            "imported" => Ok(Self::Imported),
            _ => anyhow::bail!("invalid host source: {value}"),
        }
    }
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum AuthMode { #[default] Auto, Key, Password }

impl AuthMode {
    pub fn as_str(self) -> &'static str {
        match self { Self::Auto => "auto", Self::Key => "key", Self::Password => "password" }
    }
    pub fn from_db(value: &str) -> anyhow::Result<Self> {
        match value {
            "auto" => Ok(Self::Auto),
            "key" => Ok(Self::Key),
            "password" => Ok(Self::Password),
            _ => anyhow::bail!("invalid auth mode: {value}"),
        }
    }
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Host {
    pub id: Uuid,
    pub name: String,
    pub alias: String,
    pub hostname: String,
    pub username: String,
    pub port: u16,
    pub identity_file: Option<String>,
    pub proxy_jump: Option<String>,
    #[serde(default)]
    pub auth_mode: AuthMode,
    pub group_id: Option<Uuid>,
    pub favorite: bool,
    pub source: HostSource,
    pub last_connected: Option<i64>,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct HostInput {
    pub name: String,
    pub alias: String,
    pub hostname: String,
    pub username: String,
    pub port: u16,
    pub identity_file: Option<String>,
    pub proxy_jump: Option<String>,
    #[serde(default)]
    pub auth_mode: AuthMode,
    pub group_id: Option<Uuid>,
    pub favorite: bool,
}

impl HostInput {
    pub fn into_host(self, source: HostSource) -> Host {
        Host {
            id: Uuid::new_v4(),
            name: self.name,
            alias: self.alias,
            hostname: self.hostname,
            username: self.username,
            port: self.port,
            identity_file: self.identity_file,
            proxy_jump: self.proxy_jump,
            auth_mode: self.auth_mode,
            group_id: self.group_id,
            favorite: self.favorite,
            source,
            last_connected: None,
        }
    }
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Group {
    pub id: Uuid,
    pub name: String,
    pub parent_id: Option<Uuid>,
    pub sort_order: i32,
}
