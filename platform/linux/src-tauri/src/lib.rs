use serde_json::Value;
use std::collections::HashSet;
use std::env;
use std::ffi::OsString;
use std::fs::{self, File, OpenOptions};
use std::io::{BufReader, Write};
use std::path::{Path, PathBuf};

const STATE_FILENAME: &str = "dayman-state-v1.json";
const SCHEMA_VERSION: u64 = 1;

fn non_empty(value: Option<OsString>) -> Option<OsString> {
    value.filter(|value| !value.is_empty())
}

fn select_config_dir(
    is_flatpak: bool,
    host_xdg_config_home: Option<OsString>,
    xdg_config_home: Option<OsString>,
    home: Option<OsString>,
) -> Result<PathBuf, String> {
    // Flatpak replaces XDG_CONFIG_HOME with its private app directory. The
    // manifest grants this one host directory so desktop-shell widgets can
    // consume the same state without broad home-directory access.
    if is_flatpak {
        if let Some(path) = non_empty(host_xdg_config_home) {
            return Ok(PathBuf::from(path).join("dayman"));
        }
        return non_empty(home)
            .map(PathBuf::from)
            .map(|home| home.join(".config/dayman"))
            .ok_or_else(|| {
                "Neither HOST_XDG_CONFIG_HOME nor HOME is set inside Flatpak".to_owned()
            });
    }

    if let Some(path) = non_empty(xdg_config_home) {
        return Ok(PathBuf::from(path).join("dayman"));
    }

    non_empty(home)
        .map(PathBuf::from)
        .map(|home| home.join(".config/dayman"))
        .ok_or_else(|| "Neither XDG_CONFIG_HOME nor HOME is set".to_owned())
}

fn config_dir() -> Result<PathBuf, String> {
    select_config_dir(
        env::var_os("FLATPAK_ID").is_some(),
        env::var_os("HOST_XDG_CONFIG_HOME"),
        env::var_os("XDG_CONFIG_HOME"),
        env::var_os("HOME"),
    )
}

fn validate_versioned_object(value: &Value, kind: &str) -> Result<(), String> {
    let object = value
        .as_object()
        .ok_or_else(|| format!("{kind} must be a JSON object"))?;
    match object.get("schemaVersion").and_then(Value::as_u64) {
        Some(SCHEMA_VERSION) => Ok(()),
        Some(version) => Err(format!(
            "Unsupported {kind} schemaVersion {version}; expected {SCHEMA_VERSION}"
        )),
        None => Err(format!("{kind} must contain numeric schemaVersion")),
    }
}

fn validate_snapshot(value: &Value) -> Result<(), String> {
    validate_versioned_object(value, "ClockSnapshot")?;
    let object = value
        .as_object()
        .expect("versioned objects were checked above");

    for key in [
        "calculatedAt",
        "expiresAt",
        "dateKey",
        "timezone",
        "accessibilityText",
    ] {
        if !object.get(key).is_some_and(Value::is_string) {
            return Err(format!("ClockSnapshot.{key} must be a string"));
        }
    }

    if !object.get("location").is_some_and(Value::is_object) {
        return Err("ClockSnapshot.location must be an object".to_owned());
    }
    if !object.get("arcs").is_some_and(Value::is_array) {
        return Err("ClockSnapshot.arcs must be an array".to_owned());
    }
    if !object.get("events").is_some_and(Value::is_array) {
        return Err("ClockSnapshot.events must be an array".to_owned());
    }
    if !object.get("geometry").is_some_and(Value::is_object) {
        return Err("ClockSnapshot.geometry must be an object".to_owned());
    }
    if !object.get("palette").is_some_and(Value::is_object) {
        return Err("ClockSnapshot.palette must be an object".to_owned());
    }
    if !object.get("hourLabels").is_some_and(Value::is_array) {
        return Err("ClockSnapshot.hourLabels must be an array".to_owned());
    }
    if !object.get("referenceMinute").is_some_and(Value::is_number) {
        return Err("ClockSnapshot.referenceMinute must be a number".to_owned());
    }

    Ok(())
}

fn validate_state(value: &Value) -> Result<(), String> {
    validate_versioned_object(value, "platform state")?;
    let object = value
        .as_object()
        .expect("versioned objects were checked above");
    if !object.get("updatedAt").is_some_and(Value::is_string) {
        return Err("platform state.updatedAt must be a string".to_owned());
    }
    let settings = object
        .get("settings")
        .and_then(Value::as_object)
        .ok_or_else(|| "platform state.settings must be an object".to_owned())?;
    if !settings.get("location").is_some_and(Value::is_object) {
        return Err("platform state.settings.location must be an object".to_owned());
    }
    let snapshot = object
        .get("snapshot")
        .ok_or_else(|| "platform state.snapshot is required".to_owned())?;
    validate_snapshot(snapshot)?;
    let fallback_date_key = snapshot
        .get("dateKey")
        .and_then(Value::as_str)
        .expect("validated snapshots contain dateKey");
    let fallback_timezone = snapshot
        .get("timezone")
        .and_then(Value::as_str)
        .expect("validated snapshots contain timezone");

    let snapshots = object
        .get("snapshots")
        .and_then(Value::as_array)
        .ok_or_else(|| "platform state.snapshots must be an array".to_owned())?;
    if snapshots.is_empty() {
        return Err("platform state.snapshots must contain at least one snapshot".to_owned());
    }
    let mut date_keys = HashSet::new();
    let mut previous_date_key: Option<&str> = None;
    for (index, queued_snapshot) in snapshots.iter().enumerate() {
        validate_snapshot(queued_snapshot)
            .map_err(|error| format!("platform state.snapshots[{index}]: {error}"))?;
        let date_key = queued_snapshot
            .get("dateKey")
            .and_then(Value::as_str)
            .expect("validated snapshots contain dateKey");
        let timezone = queued_snapshot
            .get("timezone")
            .and_then(Value::as_str)
            .expect("validated snapshots contain timezone");
        if timezone != fallback_timezone {
            return Err(format!(
                "platform state.snapshots[{index}].timezone must match snapshot.timezone"
            ));
        }
        if !date_keys.insert(date_key) {
            return Err(format!(
                "platform state.snapshots contains duplicate dateKey {date_key}"
            ));
        }
        if previous_date_key.is_some_and(|previous| date_key <= previous) {
            return Err("platform state.snapshots must be ordered by ascending dateKey".to_owned());
        }
        previous_date_key = Some(date_key);
    }
    if snapshots[0].get("dateKey").and_then(Value::as_str) != Some(fallback_date_key) {
        return Err(
            "platform state.snapshots must begin with the fallback snapshot dateKey".to_owned(),
        );
    }

    Ok(())
}

fn read_json(path: &Path) -> Result<Option<Value>, String> {
    let file = match File::open(path) {
        Ok(file) => file,
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok(None),
        Err(error) => return Err(format!("Could not open {}: {error}", path.display())),
    };

    serde_json::from_reader(BufReader::new(file))
        .map(Some)
        .map_err(|error| format!("Could not parse {}: {error}", path.display()))
}

fn atomic_write_json(path: &Path, value: &Value) -> Result<(), String> {
    let parent = path
        .parent()
        .ok_or_else(|| format!("{} has no parent directory", path.display()))?;
    fs::create_dir_all(parent)
        .map_err(|error| format!("Could not create {}: {error}", parent.display()))?;

    let temp_path = path.with_extension("json.tmp");
    let bytes = serde_json::to_vec_pretty(value)
        .map_err(|error| format!("Could not serialize JSON: {error}"))?;

    let mut options = OpenOptions::new();
    options.write(true).create(true).truncate(true);
    #[cfg(unix)]
    {
        use std::os::unix::fs::OpenOptionsExt;
        options.mode(0o600);
    }

    let mut file = options
        .open(&temp_path)
        .map_err(|error| format!("Could not create {}: {error}", temp_path.display()))?;
    file.write_all(&bytes)
        .and_then(|_| file.write_all(b"\n"))
        .and_then(|_| file.sync_all())
        .map_err(|error| format!("Could not write {}: {error}", temp_path.display()))?;
    fs::rename(&temp_path, path)
        .map_err(|error| format!("Could not replace {}: {error}", path.display()))
}

#[tauri::command]
fn save_dayman_state(state: Value) -> Result<(), String> {
    validate_state(&state)?;
    atomic_write_json(&config_dir()?.join(STATE_FILENAME), &state)
}

#[tauri::command]
fn read_dayman_state() -> Result<Option<Value>, String> {
    let value = read_json(&config_dir()?.join(STATE_FILENAME))?;
    if let Some(state) = &value {
        validate_state(state)?;
    }
    Ok(value)
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .invoke_handler(tauri::generate_handler![
            save_dayman_state,
            read_dayman_state
        ])
        .run(tauri::generate_context!())
        .expect("error while running DayMan");
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    fn valid_snapshot() -> Value {
        json!({
            "schemaVersion": 1,
            "calculatedAt": "2026-07-26T12:00:00Z",
            "expiresAt": "2026-07-27T00:00:00Z",
            "dateKey": "2026-07-26",
            "timezone": "UTC",
            "location": {"label": "Null Island", "latitude": 0, "longitude": 0},
            "size": {"width": 420, "height": 420},
            "geometry": {
                "viewBox": 420, "center": 210, "outerRadius": 190,
                "sunRadius": 138, "moonRadius": 112, "hourLabelRadius": 170,
                "handStartRadius": 64, "handEndRadius": 181
            },
            "palette": {
                "background": "#0c1424", "face": "#111b2e", "track": "#222a39",
                "text": "#f2f7fc", "mutedText": "#b8cbe0", "currentHand": "#f2f7fc"
            },
            "hourLabels": [],
            "arcs": [],
            "events": [],
            "referenceMinute": 720,
            "currentTimeLabel": "12:00",
            "nextSolarEvent": null,
            "moon": {
                "illumination": 0.5, "phaseAngle": 90,
                "phaseName": "First quarter", "markerMinute": 720
            },
            "accessibilityText": "No events"
        })
    }

    #[test]
    fn accepts_the_current_snapshot_schema() {
        assert_eq!(validate_snapshot(&valid_snapshot()), Ok(()));
    }

    #[test]
    fn rejects_unknown_snapshot_versions() {
        let mut snapshot = valid_snapshot();
        snapshot["schemaVersion"] = json!(2);
        assert!(validate_snapshot(&snapshot)
            .unwrap_err()
            .contains("Unsupported ClockSnapshot schemaVersion 2"));
    }

    fn valid_state() -> Value {
        json!({
            "schemaVersion": 1,
            "updatedAt": "2026-07-26T12:00:00Z",
            "settings": {
                "location": {
                    "id": "null-island",
                    "label": "Null Island",
                    "latitude": 0,
                    "longitude": 0,
                    "timezone": "UTC"
                }
            },
            "snapshot": valid_snapshot(),
            "snapshots": [valid_snapshot()]
        })
    }

    #[test]
    fn accepts_the_platform_state_envelope() {
        assert_eq!(validate_state(&valid_state()), Ok(()));
    }

    #[test]
    fn uses_the_native_xdg_config_directory() {
        let path = select_config_dir(
            false,
            None,
            Some(OsString::from("/tmp/xdg-config")),
            Some(OsString::from("/tmp/home")),
        )
        .unwrap();
        assert_eq!(path, PathBuf::from("/tmp/xdg-config/dayman"));
    }

    #[test]
    fn uses_the_host_xdg_directory_inside_flatpak() {
        let path = select_config_dir(
            true,
            Some(OsString::from("/tmp/host-config")),
            Some(OsString::from("/tmp/private-flatpak-config")),
            Some(OsString::from("/tmp/home")),
        )
        .unwrap();
        assert_eq!(path, PathBuf::from("/tmp/host-config/dayman"));
    }

    #[test]
    fn rejects_state_without_nested_snapshot() {
        let mut state = valid_state();
        state.as_object_mut().unwrap().remove("snapshot");
        assert!(validate_state(&state)
            .unwrap_err()
            .contains("platform state.snapshot is required"));
    }

    #[test]
    fn rejects_state_without_snapshot_queue() {
        let mut state = valid_state();
        state.as_object_mut().unwrap().remove("snapshots");
        assert!(validate_state(&state)
            .unwrap_err()
            .contains("platform state.snapshots must be an array"));
    }

    #[test]
    fn rejects_an_invalid_queued_snapshot() {
        let mut state = valid_state();
        state["snapshots"][0]["schemaVersion"] = json!(2);
        let error = validate_state(&state).unwrap_err();
        assert!(error.contains("platform state.snapshots[0]"));
        assert!(error.contains("Unsupported ClockSnapshot schemaVersion 2"));
    }

    #[test]
    fn rejects_a_snapshot_queue_for_another_timezone() {
        let mut state = valid_state();
        state["snapshots"][0]["timezone"] = json!("America/New_York");
        assert!(validate_state(&state)
            .unwrap_err()
            .contains("timezone must match snapshot.timezone"));
    }

    #[test]
    fn rejects_a_queue_that_does_not_start_with_the_fallback_date() {
        let mut state = valid_state();
        state["snapshots"][0]["dateKey"] = json!("2026-07-27");
        assert!(validate_state(&state)
            .unwrap_err()
            .contains("must begin with the fallback snapshot dateKey"));
    }

    #[test]
    fn writes_and_reads_atomically() {
        let directory = tempfile::tempdir().unwrap();
        let path = directory.path().join(STATE_FILENAME);
        let state = valid_state();

        atomic_write_json(&path, &state).unwrap();

        assert_eq!(read_json(&path).unwrap(), Some(state));
        assert!(!path.with_extension("json.tmp").exists());
    }
}
