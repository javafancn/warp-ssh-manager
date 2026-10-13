use crate::model::{AuthMode, Group, Host, HostSource};
use anyhow::{Context, Result};
use rusqlite::{params, Connection, OptionalExtension, Row};
use std::path::Path;
use uuid::Uuid;

pub struct Repository { conn: Connection }

impl Repository {
    pub fn open(path: &Path) -> Result<Self> {
        if path.is_symlink() { anyhow::bail!("refusing to open symlinked database: {}", path.display()); }
        if let Some(parent) = path.parent() {
            std::fs::create_dir_all(parent)?;
            #[cfg(unix)] {
                use std::os::unix::fs::PermissionsExt;
                std::fs::set_permissions(parent, std::fs::Permissions::from_mode(0o700))?;
            }
        }
        let conn = Connection::open(path).with_context(|| format!("opening database {}", path.display()))?;
        #[cfg(unix)] {
            use std::os::unix::fs::PermissionsExt;
            std::fs::set_permissions(path, std::fs::Permissions::from_mode(0o600))?;
        }
        conn.execute_batch("PRAGMA foreign_keys = ON; PRAGMA busy_timeout = 3000;\n\
            CREATE TABLE IF NOT EXISTS groups (\
                id TEXT PRIMARY KEY, name TEXT NOT NULL, parent_id TEXT REFERENCES groups(id) ON DELETE RESTRICT,\
                sort_order INTEGER NOT NULL DEFAULT 0\
            );\
            CREATE TABLE IF NOT EXISTS hosts (\
                id TEXT PRIMARY KEY, name TEXT NOT NULL, alias TEXT NOT NULL UNIQUE COLLATE NOCASE,\
                hostname TEXT NOT NULL, username TEXT NOT NULL, port INTEGER NOT NULL,\
                identity_file TEXT, proxy_jump TEXT, group_id TEXT REFERENCES groups(id) ON DELETE SET NULL,\
                favorite INTEGER NOT NULL DEFAULT 0, source TEXT NOT NULL, last_connected INTEGER\
            );\
            CREATE TABLE IF NOT EXISTS host_annotations (\
                host_id TEXT PRIMARY KEY REFERENCES hosts(id) ON DELETE CASCADE,\
                tags TEXT NOT NULL DEFAULT '', notes TEXT NOT NULL DEFAULT ''\
            );\
            CREATE INDEX IF NOT EXISTS idx_hosts_group ON hosts(group_id);\
            CREATE INDEX IF NOT EXISTS idx_hosts_favorite ON hosts(favorite);")?;
        // Existing v0.4 databases have no auth_mode column.
        let has_auth_mode = {
            let mut statement = conn.prepare("PRAGMA table_info(hosts)")?;
            let rows = statement.query_map([], |row| row.get::<_, String>(1))?;
            rows.collect::<rusqlite::Result<Vec<_>>>()?.iter().any(|name| name == "auth_mode")
        };
        if !has_auth_mode {
            conn.execute("ALTER TABLE hosts ADD COLUMN auth_mode TEXT NOT NULL DEFAULT 'auto'", [])?;
        }
        Ok(Self { conn })
    }

    fn map_host(row: &Row<'_>) -> rusqlite::Result<Host> {
        let id: String = row.get(0)?;
        let group: Option<String> = row.get(8)?;
        let source: String = row.get(10)?;
        Ok(Host {
            id: Uuid::parse_str(&id).map_err(to_sql_err)?, name: row.get(1)?, alias: row.get(2)?,
            hostname: row.get(3)?, username: row.get(4)?, port: row.get(5)?,
            identity_file: row.get(6)?, proxy_jump: row.get(7)?,
            group_id: group.as_deref().map(Uuid::parse_str).transpose().map_err(to_sql_err)?,
            favorite: row.get::<_, i64>(9)? != 0,
            source: match source.as_str() {
                "managed" => HostSource::Managed,
                "imported" => HostSource::Imported,
                _ => return Err(rusqlite::Error::InvalidColumnType(10, "source".into(), rusqlite::types::Type::Text)),
            },
            last_connected: row.get(11)?,
            auth_mode: match row.get::<_, String>(12)?.as_str() {
                "auto" => AuthMode::Auto,
                "key" => AuthMode::Key,
                "password" => AuthMode::Password,
                _ => return Err(rusqlite::Error::InvalidColumnType(
                    12, "auth_mode".into(), rusqlite::types::Type::Text,
                )),
            },
        })
    }


    pub fn list_hosts(&self) -> Result<Vec<Host>> {
        let mut stmt = self.conn.prepare("SELECT id,name,alias,hostname,username,port,identity_file,proxy_jump,group_id,favorite,source,last_connected,auth_mode FROM hosts ORDER BY favorite DESC, name COLLATE NOCASE")?;
        let rows = stmt.query_map([], Self::map_host)?;
        Ok(rows.collect::<rusqlite::Result<_>>()?)
    }

    pub fn get_host(&self, id: Uuid) -> Result<Option<Host>> {
        self.conn.query_row("SELECT id,name,alias,hostname,username,port,identity_file,proxy_jump,group_id,favorite,source,last_connected,auth_mode FROM hosts WHERE id=?1", [id.to_string()], Self::map_host).optional().map_err(Into::into)
    }

    pub fn find_alias(&self, alias: &str) -> Result<Option<Host>> {
        self.conn.query_row("SELECT id,name,alias,hostname,username,port,identity_file,proxy_jump,group_id,favorite,source,last_connected,auth_mode FROM hosts WHERE alias=?1 COLLATE NOCASE", [alias], Self::map_host).optional().map_err(Into::into)
    }

    pub fn save_host(&self, host: &Host) -> Result<()> {
        self.conn.execute("INSERT INTO hosts (id,name,alias,hostname,username,port,identity_file,proxy_jump,group_id,favorite,source,last_connected,auth_mode)
             VALUES (?1,?2,?3,?4,?5,?6,?7,?8,?9,?10,?11,?12,?13)
             ON CONFLICT(id) DO UPDATE SET name=excluded.name,alias=excluded.alias,hostname=excluded.hostname,
             username=excluded.username,port=excluded.port,identity_file=excluded.identity_file,
             proxy_jump=excluded.proxy_jump,group_id=excluded.group_id,favorite=excluded.favorite,
             source=excluded.source,last_connected=excluded.last_connected,auth_mode=excluded.auth_mode",
            params![host.id.to_string(),host.name,host.alias,host.hostname,host.username,host.port,host.identity_file,
                host.proxy_jump,host.group_id.map(|v|v.to_string()),host.favorite as i32,host.source.as_str(),host.last_connected,host.auth_mode.as_str()])?;
        Ok(())
    }

    pub fn delete_host(&self, id: Uuid) -> Result<bool> {
        Ok(self.conn.execute("DELETE FROM hosts WHERE id=?", [id.to_string()])? != 0)
    }

    /// UI-only metadata. Never written into the user's SSH configuration.
    /// A separate table keeps existing v0.1 host rows backward compatible.
    pub fn host_annotations(&self, id: Uuid) -> Result<(String, String)> {
        Ok(self.conn.query_row(
            "SELECT tags, notes FROM host_annotations WHERE host_id=?1",
            [id.to_string()],
            |row| Ok((row.get(0)?, row.get(1)?)),
        ).optional()?.unwrap_or_else(|| (String::new(), String::new())))
    }

    pub fn save_annotations(&self, id: Uuid, tags: &str, notes: &str) -> Result<()> {
        self.conn.execute(
            "INSERT INTO host_annotations(host_id,tags,notes) VALUES(?1,?2,?3)\
             ON CONFLICT(host_id) DO UPDATE SET tags=excluded.tags,notes=excluded.notes",
            params![id.to_string(), tags, notes],
        )?;
        Ok(())
    }

    pub fn mark_connected(&self, id: Uuid, at: i64) -> Result<()> {
        self.conn.execute("UPDATE hosts SET last_connected=?2 WHERE id=?1", params![id.to_string(),at])?;
        Ok(())
    }

    pub fn list_groups(&self) -> Result<Vec<Group>> {
        let mut stmt=self.conn.prepare("SELECT id,name,parent_id,sort_order FROM groups ORDER BY sort_order,name COLLATE NOCASE")?;
        let rows=stmt.query_map([],|r|{
            let id: String=r.get(0)?; let parent: Option<String>=r.get(2)?;
            Ok(Group { id:Uuid::parse_str(&id).map_err(to_sql_err)?, name:r.get(1)?,
                parent_id:parent.as_deref().map(Uuid::parse_str).transpose().map_err(to_sql_err)?,sort_order:r.get(3)? })
        })?;
        Ok(rows.collect::<rusqlite::Result<_>>()?)
    }

    pub fn save_group(&self, group:&Group) -> Result<()> {
        self.conn.execute("INSERT INTO groups(id,name,parent_id,sort_order) VALUES (?1,?2,?3,?4)
            ON CONFLICT(id) DO UPDATE SET name=excluded.name,parent_id=excluded.parent_id,sort_order=excluded.sort_order",
            params![group.id.to_string(),group.name,group.parent_id.map(|v|v.to_string()),group.sort_order])?;
        Ok(())
    }

    pub fn delete_group(&self, id: Uuid) -> Result<bool> {
        Ok(self.conn.execute("DELETE FROM groups WHERE id=?1", [id.to_string()])? != 0)
    }
}

#[cfg(test)]
mod auth_tests {
    use super::*;
    #[test]
    fn migrates_existing_host_table_without_losing_rows() {
        let temp = tempfile::tempdir().unwrap();
        let path = temp.path().join("hosts.sqlite3");
        {
            let conn = Connection::open(&path).unwrap();
            conn.execute_batch(
                "CREATE TABLE hosts (id TEXT PRIMARY KEY, name TEXT NOT NULL, alias TEXT NOT NULL,
                hostname TEXT NOT NULL, username TEXT NOT NULL, port INTEGER NOT NULL,
                identity_file TEXT, proxy_jump TEXT, group_id TEXT,
                favorite INTEGER NOT NULL DEFAULT 0, source TEXT NOT NULL, last_connected INTEGER);
                INSERT INTO hosts VALUES
                ('3c728e71-68f7-41f3-a9de-1c9e036953f8','Legacy','legacy','example.test','deploy',22,
                 NULL,NULL,NULL,0,'managed',NULL);"
            ).unwrap();
        }
        let db = Repository::open(&path).unwrap();
        let old = db.list_hosts().unwrap();
        assert_eq!(old.len(),1);
        assert_eq!(old[0].auth_mode,AuthMode::Auto);
        let mut edited = old[0].clone();
        edited.auth_mode=AuthMode::Password;
        db.save_host(&edited).unwrap();
        assert_eq!(db.get_host(edited.id).unwrap().unwrap().auth_mode,AuthMode::Password);
        drop(db);
        let reopened=Repository::open(&path).unwrap();
        assert_eq!(reopened.list_hosts().unwrap()[0].auth_mode,AuthMode::Password);
    }
}

fn to_sql_err<E: std::error::Error + Send + Sync + 'static>(err: E) -> rusqlite::Error {
    rusqlite::Error::FromSqlConversionFailure(0,rusqlite::types::Type::Text,Box::new(err))
}
