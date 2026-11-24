use crate::model::{AuthMode, Host, HostInput, HostSource};
use crate::ssh::{self, EffectiveSsh};
use crate::Manager;
use anyhow::{bail, Context, Result};
use serde::{Deserialize, Serialize};
use std::collections::{BTreeMap, BTreeSet};
use std::path::PathBuf;
use uuid::Uuid;

#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum ImportStatus {
    New,
    Update,
    Unchanged,
    Managed,
    Conflict,
    Error,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub struct ImportCandidate {
    pub alias: String,
    pub status: ImportStatus,
    pub existing_id: Option<Uuid>,
    pub before: Option<EffectiveSsh>,
    pub after: Option<EffectiveSsh>,
    pub detail: Option<String>,
}

impl ImportCandidate {
    pub fn is_selectable(&self) -> bool {
        matches!(self.status, ImportStatus::New | ImportStatus::Update)
    }
}

#[derive(Debug, Serialize)]
pub struct ImportPreview {
    pub config_path: PathBuf,
    pub candidates: Vec<ImportCandidate>,
}

#[derive(Debug, Default, Serialize)]
pub struct ImportResult {
    pub added: usize,
    pub updated: usize,
    pub stale_aliases: Vec<String>,
}

impl From<&Host> for EffectiveSsh {
    fn from(host: &Host) -> Self {
        Self {
            hostname: host.hostname.clone(),
            username: host.username.clone(),
            port: host.port,
            identity_file: host.identity_file.clone(),
            proxy_jump: host.proxy_jump.clone(),
        }
    }
}

fn classify(
    alias: String,
    ambiguous: bool,
    existing: Option<Host>,
    config: Option<&std::path::Path>,
) -> ImportCandidate {
    let mut row = ImportCandidate {
        alias,
        status: ImportStatus::Error,
        existing_id: existing.as_ref().map(|host| host.id),
        before: existing.as_ref().map(EffectiveSsh::from),
        after: None,
        detail: None,
    };
    if existing
        .as_ref()
        .is_some_and(|host| host.source == HostSource::Managed)
    {
        row.status = ImportStatus::Managed;
    } else if ambiguous
        || existing
            .as_ref()
            .is_some_and(|host| host.alias != row.alias)
    {
        row.status = ImportStatus::Conflict;
    } else {
        match ssh::effective_config_from(&row.alias, config) {
            Ok(after) => {
                row.status = match &row.before {
                    None => ImportStatus::New,
                    Some(before) if *before == after => ImportStatus::Unchanged,
                    Some(_) => ImportStatus::Update,
                };
                row.after = Some(after);
            }
            Err(error) => row.detail = Some(format!("{error:#}")),
        }
    }
    row
}

impl Manager {
    pub fn preview_ssh_import(&self, aliases: &[String]) -> Result<ImportPreview> {
        let config = &self.paths.ssh_config;
        let user_ssh = dirs::home_dir()
            .context("cannot determine HOME directory")?
            .join(".ssh");
        let default_config = user_ssh.join("config");
        let explicit_config = (config != &default_config).then_some(config.as_path());
        let mut discovered: BTreeMap<String, Vec<String>> = BTreeMap::new();
        for alias in ssh::find_aliases_from(config, &user_ssh)? {
            discovered
                .entry(alias.to_ascii_lowercase())
                .or_default()
                .push(alias);
        }
        let requested: BTreeMap<_, _> = aliases
            .iter()
            .map(|alias| (alias.to_ascii_lowercase(), alias))
            .collect();
        let mut candidates = Vec::new();
        for (key, variants) in &discovered {
            if !requested.is_empty() && !requested.contains_key(key) {
                continue;
            }
            let existing = self.db.find_alias(key)?;
            let ambiguous = variants.len() > 1;
            for alias in variants {
                candidates.push(classify(
                    alias.clone(),
                    ambiguous,
                    existing.clone(),
                    explicit_config,
                ));
            }
        }
        for (key, alias) in requested {
            if !discovered.contains_key(&key) {
                candidates.push(ImportCandidate {
                    alias: alias.clone(),
                    status: ImportStatus::Error,
                    existing_id: None,
                    before: None,
                    after: None,
                    detail: Some("alias was not found in SSH config".into()),
                });
            }
        }
        Ok(ImportPreview {
            config_path: config.clone(),
            candidates,
        })
    }

    /// Apply a previously displayed selection, checking OpenSSH again before taking the database lock.
    pub fn apply_ssh_import(&self, selected: &[ImportCandidate]) -> Result<ImportResult> {
        let aliases: BTreeSet<_> = selected
            .iter()
            .map(|row| row.alias.to_ascii_lowercase())
            .collect();
        if selected.is_empty()
            || aliases.len() != selected.len()
            || !selected.iter().all(ImportCandidate::is_selectable)
        {
            bail!("import selection must contain unique, selectable aliases");
        }
        let requested: Vec<_> = selected.iter().map(|row| row.alias.clone()).collect();
        let fresh = self.preview_ssh_import(&requested)?;
        let by_alias: BTreeMap<_, _> = fresh
            .candidates
            .iter()
            .map(|row| (row.alias.as_str(), row))
            .collect();
        let stale_aliases = selected
            .iter()
            .filter(|row| by_alias.get(row.alias.as_str()).copied() != Some(*row))
            .map(|row| row.alias.clone())
            .collect::<Vec<_>>();
        if !stale_aliases.is_empty() {
            return Ok(ImportResult {
                stale_aliases,
                ..ImportResult::default()
            });
        }
        self.commit_ssh_import(selected.iter())
    }

    pub fn import_ssh_aliases(&self, aliases: &[String]) -> Result<(ImportResult, Vec<String>)> {
        let preview = self.preview_ssh_import(aliases)?;
        let warnings = preview
            .candidates
            .iter()
            .filter_map(|row| {
                let detail = match row.status {
                    ImportStatus::Managed if !aliases.is_empty() => {
                        "alias is already managed by WSM"
                    }
                    ImportStatus::Conflict => "SSH alias has a case-insensitive conflict",
                    ImportStatus::Error => row
                        .detail
                        .as_deref()
                        .unwrap_or("unable to resolve SSH alias"),
                    _ => return None,
                };
                Some(format!("{}: {detail}", row.alias))
            })
            .collect();
        let result =
            self.commit_ssh_import(preview.candidates.iter().filter(|row| row.is_selectable()))?;
        if !result.stale_aliases.is_empty() {
            bail!(
                "host records changed during import for {}; retry the import",
                result.stale_aliases.join(", ")
            );
        }
        Ok((result, warnings))
    }

    pub fn import_ssh(&self) -> Result<(usize, usize, Vec<String>)> {
        let (result, warnings) = self.import_ssh_aliases(&[])?;
        Ok((result.added, result.updated, warnings))
    }

    fn commit_ssh_import<'a>(
        &self,
        rows: impl Iterator<Item = &'a ImportCandidate>,
    ) -> Result<ImportResult> {
        let rows: Vec<_> = rows.collect();
        if rows.is_empty() {
            return Ok(ImportResult::default());
        }
        self.db.with_write_transaction(|| {
            let mut result = ImportResult::default();
            for row in &rows {
                let current = self.db.find_alias(&row.alias)?;
                let matches = match current {
                    None => row.status == ImportStatus::New && row.existing_id.is_none(),
                    Some(host) => {
                        row.status == ImportStatus::Update
                            && host.source == HostSource::Imported
                            && host.alias == row.alias
                            && Some(host.id) == row.existing_id
                            && row.before.as_ref() == Some(&EffectiveSsh::from(&host))
                    }
                };
                if !matches {
                    result.stale_aliases.push(row.alias.clone());
                }
            }
            if !result.stale_aliases.is_empty() {
                return Ok(result);
            }
            for row in rows {
                let config = row
                    .after
                    .as_ref()
                    .context("missing effective SSH config for import")?;
                if let Some(id) = row.existing_id {
                    self.db.update_imported_connection(id, config)?;
                    result.updated += 1;
                } else {
                    self.db.save_host(
                        &HostInput {
                            name: row.alias.clone(),
                            alias: row.alias.clone(),
                            hostname: config.hostname.clone(),
                            username: config.username.clone(),
                            port: config.port,
                            identity_file: config.identity_file.clone(),
                            proxy_jump: config.proxy_jump.clone(),
                            auth_mode: AuthMode::Auto,
                            group_id: None,
                            favorite: false,
                        }
                        .into_host(HostSource::Imported),
                    )?;
                    result.added += 1;
                }
            }
            Ok(result)
        })
    }
}
