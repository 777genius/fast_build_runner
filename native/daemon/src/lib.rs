use std::collections::{BTreeMap, BTreeSet};
use std::fs;
use std::path::{Path, PathBuf};
use std::sync::mpsc;
use std::time::{Duration, Instant};

use anyhow::{anyhow, Context, Result};
use notify::{recommended_watcher, Event, EventKind, RecursiveMode, Watcher};
use serde::{Deserialize, Serialize};

#[derive(Debug, Deserialize)]
#[serde(tag = "command", rename_all = "snake_case")]
pub enum DaemonRequest {
    Ping {
        id: String,
    },
    WatchOnce {
        id: String,
        path: String,
        #[serde(default)]
        tracked_paths: Option<Vec<String>>,
        #[serde(default)]
        debounce_ms: Option<u64>,
        #[serde(default)]
        timeout_ms: Option<u64>,
    },
    StartWatch {
        id: String,
        watch_id: String,
        path: String,
        #[serde(default)]
        tracked_paths: Option<Vec<String>>,
        #[serde(default)]
        warmup_ms: Option<u64>,
    },
    FinishWatch {
        id: String,
        watch_id: String,
        #[serde(default)]
        debounce_ms: Option<u64>,
        #[serde(default)]
        timeout_ms: Option<u64>,
        #[serde(default)]
        keep_alive: Option<bool>,
    },
}

#[derive(Debug, Serialize)]
#[serde(tag = "kind", rename_all = "snake_case")]
pub enum DaemonResponse {
    Pong {
        id: String,
        protocol_version: u32,
        daemon: &'static str,
    },
    WatchBatch {
        id: String,
        #[serde(skip_serializing_if = "Option::is_none")]
        watch_id: Option<String>,
        status: &'static str,
        root: String,
        events: Vec<WatchEventPayload>,
        warnings: Vec<String>,
    },
    WatchReady {
        id: String,
        watch_id: String,
        status: &'static str,
        root: String,
    },
    Error {
        id: Option<String>,
        message: String,
    },
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct WatchEventPayload {
    pub path: String,
    pub kind: &'static str,
}

pub struct DaemonServer {
    active_watches: BTreeMap<String, ActiveWatch>,
}

impl DaemonServer {
    pub fn new() -> Self {
        Self {
            active_watches: BTreeMap::new(),
        }
    }

    pub fn handle_request(&mut self, request: DaemonRequest) -> DaemonResponse {
        match request {
            DaemonRequest::Ping { id } => DaemonResponse::Pong {
                id,
                protocol_version: 3,
                daemon: "fast_build_runner_daemon",
            },
            DaemonRequest::WatchOnce {
                id,
                path,
                tracked_paths,
                debounce_ms,
                timeout_ms,
            } => match watch_once(&path, tracked_paths, debounce_ms, timeout_ms) {
                Ok(events) => DaemonResponse::WatchBatch {
                    id,
                    watch_id: None,
                    status: "ok",
                    root: path,
                    events,
                    warnings: vec![],
                },
                Err(error) => DaemonResponse::Error {
                    id: Some(id),
                    message: format!("{error:#}"),
                },
            },
            DaemonRequest::StartWatch {
                id,
                watch_id,
                path,
                tracked_paths,
                warmup_ms,
            } => match self.start_watch(&watch_id, &path, tracked_paths, warmup_ms) {
                Ok(active_watch) => {
                    let root = active_watch.root.clone();
                    self.active_watches.insert(watch_id.clone(), active_watch);
                    DaemonResponse::WatchReady {
                        id,
                        watch_id,
                        status: "ready",
                        root,
                    }
                }
                Err(error) => DaemonResponse::Error {
                    id: Some(id),
                    message: format!("{error:#}"),
                },
            },
            DaemonRequest::FinishWatch {
                id,
                watch_id,
                debounce_ms,
                timeout_ms,
                keep_alive,
            } => {
                let keep_alive = keep_alive.unwrap_or(false);
                if keep_alive {
                    let Some(active_watch) = self.active_watches.get_mut(&watch_id) else {
                        return DaemonResponse::Error {
                            id: Some(id),
                            message: format!("Unknown active watch id: {watch_id}"),
                        };
                    };
                    let root = active_watch.root.clone();
                    match active_watch.next_batch(debounce_ms, timeout_ms) {
                        Ok(events) => DaemonResponse::WatchBatch {
                            id,
                            watch_id: Some(watch_id),
                            status: "ok",
                            root,
                            events,
                            warnings: vec![],
                        },
                        Err(error) => DaemonResponse::Error {
                            id: Some(id),
                            message: format!("{error:#}"),
                        },
                    }
                } else {
                    let Some(mut active_watch) = self.active_watches.remove(&watch_id) else {
                        return DaemonResponse::Error {
                            id: Some(id),
                            message: format!("Unknown active watch id: {watch_id}"),
                        };
                    };
                    let root = active_watch.root.clone();
                    match active_watch.next_batch(debounce_ms, timeout_ms) {
                        Ok(events) => DaemonResponse::WatchBatch {
                            id,
                            watch_id: Some(watch_id),
                            status: "ok",
                            root,
                            events,
                            warnings: vec![],
                        },
                        Err(error) => DaemonResponse::Error {
                            id: Some(id),
                            message: format!("{error:#}"),
                        },
                    }
                }
            }
        }
    }

    fn start_watch(
        &self,
        watch_id: &str,
        root: &str,
        tracked_paths: Option<Vec<String>>,
        warmup_ms: Option<u64>,
    ) -> Result<ActiveWatch> {
        if self.active_watches.contains_key(watch_id) {
            return Err(anyhow!("Active watch id already exists: {watch_id}"));
        }
        ActiveWatch::start(root, tracked_paths, warmup_ms)
    }
}

pub fn watch_once(
    root: &str,
    tracked_paths: Option<Vec<String>>,
    debounce_ms: Option<u64>,
    timeout_ms: Option<u64>,
) -> Result<Vec<WatchEventPayload>> {
    let root_path = PathBuf::from(root);
    if !root_path.exists() {
        return Err(anyhow!(
            "Watch root does not exist: {}",
            root_path.display()
        ));
    }

    let debounce = Duration::from_millis(debounce_ms.unwrap_or(350));
    let timeout = Duration::from_millis(timeout_ms.unwrap_or(15_000));
    let warmup = Duration::from_millis(250);
    let canonical_root = root_path
        .canonicalize()
        .with_context(|| format!("Failed to canonicalize watch root {}", root_path.display()))?;
    let tracked_paths = normalize_tracked_paths(&canonical_root, tracked_paths)?;
    let tracked_path_filter = tracked_paths
        .as_ref()
        .map(|entries| entries.keys().cloned().collect::<BTreeSet<_>>());
    let existing_paths = tracked_paths.unwrap_or_else(|| collect_existing_paths(&canonical_root));
    let (tx, rx) = mpsc::channel();

    let mut watcher = recommended_watcher(move |result| {
        let _ = tx.send(result);
    })
    .context("Failed to create filesystem watcher")?;

    watcher
        .watch(&root_path, RecursiveMode::Recursive)
        .with_context(|| format!("Failed to watch {}", root_path.display()))?;

    let start = Instant::now();
    let warmup_deadline = start + warmup;
    let mut first_event_seen = false;
    let mut last_event_at: Option<Instant> = None;
    let mut collected = Vec::new();

    loop {
        let remaining = timeout
            .checked_sub(start.elapsed())
            .ok_or_else(|| anyhow!("Timed out waiting for watcher events"))?;

        let wait_for = if first_event_seen {
            let idle_remaining = debounce
                .checked_sub(last_event_at.unwrap_or_else(Instant::now).elapsed())
                .unwrap_or(Duration::ZERO);
            idle_remaining.min(remaining)
        } else {
            remaining
        };

        match rx.recv_timeout(wait_for) {
            Ok(Ok(event)) => {
                if !first_event_seen && Instant::now() < warmup_deadline {
                    continue;
                }
                first_event_seen = true;
                last_event_at = Some(Instant::now());
                collected.extend(normalize_event_batch(
                    &canonical_root,
                    tracked_path_filter.as_ref(),
                    &existing_paths,
                    &event,
                ));
            }
            Ok(Err(error)) => return Err(anyhow!("Watcher reported an error: {error}")),
            Err(mpsc::RecvTimeoutError::Timeout) => {
                if first_event_seen {
                    break;
                }
            }
            Err(mpsc::RecvTimeoutError::Disconnected) => {
                return Err(anyhow!("Watcher channel disconnected unexpectedly"));
            }
        }
    }

    if collected.is_empty() {
        return Err(anyhow!(
            "Timed out waiting for watcher events under {}",
            root_path.display()
        ));
    }

    Ok(merge_watch_events(collected))
}

struct ActiveWatch {
    root: String,
    canonical_root: PathBuf,
    tracked_path_filter: Option<BTreeSet<String>>,
    existing_paths: BTreeMap<String, bool>,
    receiver: mpsc::Receiver<notify::Result<Event>>,
    _watcher: notify::RecommendedWatcher,
}

impl ActiveWatch {
    fn start(
        root: &str,
        tracked_paths: Option<Vec<String>>,
        warmup_ms: Option<u64>,
    ) -> Result<Self> {
        let root_path = PathBuf::from(root);
        if !root_path.exists() {
            return Err(anyhow!(
                "Watch root does not exist: {}",
                root_path.display()
            ));
        }
        let canonical_root = root_path.canonicalize().with_context(|| {
            format!("Failed to canonicalize watch root {}", root_path.display())
        })?;
        let tracked_paths = normalize_tracked_paths(&canonical_root, tracked_paths)?;
        let tracked_path_filter = tracked_paths
            .as_ref()
            .map(|entries| entries.keys().cloned().collect::<BTreeSet<_>>());
        let existing_paths =
            tracked_paths.unwrap_or_else(|| collect_existing_paths(&canonical_root));
        let (tx, rx) = mpsc::channel();

        let mut watcher = recommended_watcher(move |result| {
            let _ = tx.send(result);
        })
        .context("Failed to create filesystem watcher")?;

        watcher
            .watch(&canonical_root, RecursiveMode::Recursive)
            .with_context(|| format!("Failed to watch {}", canonical_root.display()))?;

        std::thread::sleep(Duration::from_millis(warmup_ms.unwrap_or(250)));

        Ok(Self {
            root: root.to_string(),
            canonical_root,
            tracked_path_filter,
            existing_paths,
            receiver: rx,
            _watcher: watcher,
        })
    }

    fn next_batch(
        &mut self,
        debounce_ms: Option<u64>,
        timeout_ms: Option<u64>,
    ) -> Result<Vec<WatchEventPayload>> {
        let debounce = Duration::from_millis(debounce_ms.unwrap_or(350));
        let timeout = Duration::from_millis(timeout_ms.unwrap_or(15_000));
        let start = Instant::now();
        let mut first_event_seen = false;
        let mut last_event_at: Option<Instant> = None;
        let mut collected = Vec::new();

        loop {
            let remaining = timeout
                .checked_sub(start.elapsed())
                .ok_or_else(|| anyhow!("Timed out waiting for watcher events"))?;

            let wait_for = if first_event_seen {
                let idle_remaining = debounce
                    .checked_sub(last_event_at.unwrap_or_else(Instant::now).elapsed())
                    .unwrap_or(Duration::ZERO);
                idle_remaining.min(remaining)
            } else {
                remaining
            };

            match self.receiver.recv_timeout(wait_for) {
                Ok(Ok(event)) => {
                    first_event_seen = true;
                    last_event_at = Some(Instant::now());
                    collected.extend(normalize_event_batch(
                        &self.canonical_root,
                        self.tracked_path_filter.as_ref(),
                        &self.existing_paths,
                        &event,
                    ));
                }
                Ok(Err(error)) => return Err(anyhow!("Watcher reported an error: {error}")),
                Err(mpsc::RecvTimeoutError::Timeout) => {
                    if first_event_seen {
                        break;
                    }
                }
                Err(mpsc::RecvTimeoutError::Disconnected) => {
                    return Err(anyhow!("Watcher channel disconnected unexpectedly"));
                }
            }
        }

        if collected.is_empty() {
            return Err(anyhow!(
                "Timed out waiting for watcher events under {}",
                self.canonical_root.display()
            ));
        }

        Ok(merge_watch_events(collected))
    }
}

fn normalize_event_batch(
    canonical_root: &Path,
    tracked_path_filter: Option<&BTreeSet<String>>,
    existing_paths: &BTreeMap<String, bool>,
    event: &Event,
) -> Vec<WatchEventPayload> {
    event
        .paths
        .iter()
        .filter_map(|path| normalize_watch_path(canonical_root, path).ok())
        .filter(|path| path != &canonical_root.display().to_string())
        .filter(|path| {
            tracked_path_filter
                .map(|filter| filter.contains(path))
                .unwrap_or(true)
        })
        .map(|path| WatchEventPayload {
            kind: normalize_kind(classify_event_kind(&event.kind), &path, existing_paths),
            path,
        })
        .collect()
}

fn normalize_watch_path(canonical_root: &Path, path: &Path) -> Result<String> {
    let absolute = if path.is_absolute() {
        path.to_path_buf()
    } else {
        canonical_root.join(path)
    };
    if absolute.starts_with(&canonical_root) {
        Ok(absolute.display().to_string())
    } else {
        Err(anyhow!(
            "Watcher produced a path outside of the root: {}",
            absolute.display()
        ))
    }
}

fn classify_event_kind(kind: &EventKind) -> &'static str {
    match kind {
        EventKind::Create(_) => "add",
        EventKind::Modify(_) => "modify",
        EventKind::Remove(_) => "remove",
        _ => "other",
    }
}

fn normalize_kind(
    raw_kind: &'static str,
    path: &str,
    existing_paths: &BTreeMap<String, bool>,
) -> &'static str {
    if raw_kind == "add" && existing_paths.contains_key(path) {
        "modify"
    } else {
        raw_kind
    }
}

fn normalize_tracked_paths(
    canonical_root: &Path,
    tracked_paths: Option<Vec<String>>,
) -> Result<Option<BTreeMap<String, bool>>> {
    let Some(tracked_paths) = tracked_paths else {
        return Ok(None);
    };
    let mut normalized = BTreeMap::new();
    for tracked_path in tracked_paths {
        let tracked_path_buf = PathBuf::from(&tracked_path);
        let absolute = if tracked_path_buf.is_absolute() {
            tracked_path_buf
        } else {
            canonical_root.join(tracked_path_buf)
        };
        let normalized_absolute = if absolute.exists() {
            absolute.canonicalize().unwrap_or_else(|_| absolute.clone())
        } else {
            absolute.clone()
        };
        if !normalized_absolute.starts_with(canonical_root) {
            return Err(anyhow!(
                "Tracked path is outside of the watch root: {}",
                normalized_absolute.display()
            ));
        }
        normalized.insert(
            normalized_absolute.display().to_string(),
            normalized_absolute.exists(),
        );
    }
    Ok(Some(normalized))
}

fn collect_existing_paths(root: &Path) -> BTreeMap<String, bool> {
    let mut paths = BTreeMap::new();
    let _ = collect_existing_paths_recursive(root, &mut paths);
    paths
}

fn collect_existing_paths_recursive(root: &Path, paths: &mut BTreeMap<String, bool>) -> Result<()> {
    if !root.exists() {
        return Ok(());
    }
    let normalized = root
        .canonicalize()
        .unwrap_or_else(|_| root.to_path_buf())
        .display()
        .to_string();
    paths.insert(normalized, root.is_dir());
    if root.is_dir() {
        for entry in fs::read_dir(root)
            .with_context(|| format!("Failed to read directory {}", root.display()))?
        {
            let entry =
                entry.with_context(|| format!("Failed to read entry in {}", root.display()))?;
            collect_existing_paths_recursive(&entry.path(), paths)?;
        }
    }
    Ok(())
}

pub fn merge_watch_events(events: Vec<WatchEventPayload>) -> Vec<WatchEventPayload> {
    let mut merged = BTreeMap::<String, &'static str>::new();
    for event in events {
        let next_kind = event.kind;
        match merged.get(event.path.as_str()).copied() {
            Some("add") if next_kind == "remove" => {
                merged.remove(&event.path);
            }
            Some("remove") if next_kind == "add" => {
                merged.insert(event.path, "modify");
            }
            Some("modify") if next_kind == "remove" => {
                merged.insert(event.path, "remove");
            }
            Some(_) => {}
            None => {
                merged.insert(event.path, next_kind);
            }
        }
    }

    merged
        .into_iter()
        .map(|(path, kind)| WatchEventPayload { path, kind })
        .collect()
}

#[cfg(test)]
mod tests {
    use std::collections::BTreeMap;

    use super::{merge_watch_events, normalize_kind, WatchEventPayload};

    #[test]
    fn merge_watch_events_cancels_add_then_remove() {
        let merged = merge_watch_events(vec![
            WatchEventPayload {
                path: "/tmp/a.dart".to_string(),
                kind: "add",
            },
            WatchEventPayload {
                path: "/tmp/a.dart".to_string(),
                kind: "remove",
            },
        ]);

        assert!(merged.is_empty());
    }

    #[test]
    fn merge_watch_events_turns_remove_then_add_into_modify() {
        let merged = merge_watch_events(vec![
            WatchEventPayload {
                path: "/tmp/a.dart".to_string(),
                kind: "remove",
            },
            WatchEventPayload {
                path: "/tmp/a.dart".to_string(),
                kind: "add",
            },
        ]);

        assert_eq!(
            merged,
            vec![WatchEventPayload {
                path: "/tmp/a.dart".to_string(),
                kind: "modify",
            }]
        );
    }

    #[test]
    fn normalize_kind_downgrades_existing_add_to_modify() {
        let mut existing_paths = BTreeMap::new();
        existing_paths.insert("/tmp/a.dart".to_string(), false);

        assert_eq!(
            normalize_kind("add", "/tmp/a.dart", &existing_paths),
            "modify"
        );
        assert_eq!(normalize_kind("add", "/tmp/b.dart", &existing_paths), "add");
    }
}
