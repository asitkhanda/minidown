use std::process::Command;

/// Convert exported HTML to docx/rtf/txt using macOS's built-in textutil.
/// The HTML is written to a temp file here so no fs-plugin scope is needed.
#[tauri::command]
fn export_via_textutil(html: String, output: String, format: String) -> Result<(), String> {
    const ALLOWED: [&str; 3] = ["docx", "rtf", "txt"];
    if !ALLOWED.contains(&format.as_str()) {
        return Err(format!("unsupported format: {format}"));
    }
    let tmp = std::env::temp_dir().join(format!("minidown-export-{}.html", std::process::id()));
    std::fs::write(&tmp, &html).map_err(|e| e.to_string())?;
    let result = Command::new("/usr/bin/textutil")
        .args(["-convert", &format])
        .arg(&tmp)
        .arg("-output")
        .arg(&output)
        .status();
    let _ = std::fs::remove_file(&tmp);
    match result {
        Ok(status) if status.success() => Ok(()),
        Ok(status) => Err(format!("textutil exited with {status}")),
        Err(e) => Err(e.to_string()),
    }
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_opener::init())
        .plugin(tauri_plugin_dialog::init())
        .plugin(tauri_plugin_fs::init())
        .invoke_handler(tauri::generate_handler![export_via_textutil])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
