//
//  installHelper.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-08-13.
//

func installHelper() {
    guard let scriptPath = Bundle.main.path(forResource: "install", ofType: "sh") else {
        print("Error: install.sh not found in app bundle.")
        return
    }

    let appPath = Bundle.main.bundlePath

    let appleScriptSource = """
    do shell script "sh \(scriptPath.quoted)" with administrator privileges
    """

    var error: NSDictionary?
    if let script = NSAppleScript(source: appleScriptSource) {
        if script.executeAndReturnError(&error) == nil {
            print("AppleScript execution error: \(error ?? [:])")
        } else {
            print("Helper installation script executed.")
        }
    }
}

extension String {
    var quoted: String {
        return "'\(self.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}