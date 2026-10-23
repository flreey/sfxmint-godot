//! One JSON request per process, through pipes only. Never log a request/secret.
use serde::Deserialize;
use serde_json::{json, Value};
use std::io::{self, BufRead, Write};
use zeroize::Zeroize;

const SERVICE: &str = "com.sfxmint.godot";
const ACCOUNT: &str = "sfxmint.com";
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct Request { op: String, #[serde(default)] secret: String }

fn valid_key(s: &str) -> bool {
    s.strip_prefix("sfx_live_").is_some_and(|s| s.len() == 40 && s.bytes().all(|c| c.is_ascii_digit() || (b'a'..=b'f').contains(&c)))
}
fn handle(request: Request) -> Value {
	handle_at(request, SERVICE)
}
fn handle_at(mut request: Request, service: &str) -> Value {
    if !["get", "set", "delete"].contains(&request.op.as_str()) || (request.op == "set" && !valid_key(&request.secret)) {
        request.secret.zeroize();
        return json!({"ok": false, "error": "invalid_request"});
    }
    let entry = match keyring::Entry::new(service, ACCOUNT) {
        Ok(e) => e,
        Err(_) => { request.secret.zeroize(); return json!({"ok": false, "error": "credential_store_unavailable"}); }
    };
    let response = match request.op.as_str() {
        "get" => match entry.get_password() {
            Ok(mut key) => { let result = if valid_key(&key) { json!({"ok": true, "secret": key}) } else { json!({"ok": false, "error": "invalid_saved_key"}) }; key.zeroize(); result },
            Err(keyring::Error::NoEntry) => json!({"ok": true, "secret": ""}),
            Err(_) => json!({"ok": false, "error": "credential_store_unavailable"}),
        },
        "set" => match entry.set_password(&request.secret) {
            Ok(()) => json!({"ok": true}),
            Err(_) => json!({"ok": false, "error": "credential_store_unavailable"}),
        },
        _ => match entry.delete_credential() {
            Ok(()) | Err(keyring::Error::NoEntry) => json!({"ok": true}),
            Err(_) => json!({"ok": false, "error": "credential_store_unavailable"}),
        },
    };
    request.secret.zeroize();
    response
}
fn main() {
    // Limit input, including when invoked independently from the editor.
    let mut line = Vec::new();
    let stdin = io::stdin();
    let mut reader = stdin.lock().take(4097);
    use std::io::Read;
    let read = reader.read_until(b'\n', &mut line);
    let response = if read.is_ok() && line.len() <= 4096 {
        match serde_json::from_slice::<Request>(&line) {
            Ok(r) => handle(r),
            Err(_) => json!({"ok": false, "error": "invalid_request"}),
        }
    } else { json!({"ok": false, "error": "invalid_request"}) };
    line.zeroize();
    // stdout is private protocol output consumed by Godot, never terminal logging.
    let _ = writeln!(io::stdout().lock(), "{}", response);
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test] fn validates_without_contacting_store() {
        assert!(valid_key(&format!("sfx_live_{}", "a".repeat(40))));
        assert!(!valid_key("sfx_live_bad"));
        assert!(!valid_key(&format!("sfx_live_{}", "G".repeat(40))));
        assert_eq!(handle(Request { op: "set".into(), secret: "bad".into() })["error"], "invalid_request");
        assert_eq!(handle(Request { op: "exec".into(), secret: "".into() })["error"], "invalid_request");
    }
    #[test]
    #[ignore = "Touches only a unique disposable system credential entry"]
    fn native_store_roundtrip() {
        let service = format!("com.sfxmint.godot.self-test.{}", std::process::id());
        let key = format!("sfx_live_{}", "a".repeat(40));
        let call = |op: &str, secret: String| handle_at(Request { op: op.into(), secret }, &service);
        assert_eq!(call("set", key.clone())["ok"], true);
        let read = call("get", String::new());
        let deleted = call("delete", String::new());
        // Delete before asserting to leave no test key behind after a failure.
        assert!(read["secret"].as_str() == Some(key.as_str()));
        assert_eq!(deleted["ok"], true);
        assert_eq!(call("get", String::new())["secret"], "");
    }
}
