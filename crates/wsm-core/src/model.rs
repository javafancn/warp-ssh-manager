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
