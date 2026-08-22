//
//  AppleScriptRunner.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-08-18.
//

import Cocoa

enum AppleScriptRunner {
    @discardableResult
    static func execute(_ source: String, error: inout NSDictionary?) -> NSAppleEventDescriptor? {
        if Thread.isMainThread {
            return run(source: source, error: &error)
        }

        var result: NSAppleEventDescriptor?
        var executionError: NSDictionary?
        DispatchQueue.main.sync {
            result = run(source: source, error: &executionError)
        }
        error = executionError
        return result
    }

    private static func run(source: String, error: inout NSDictionary?) -> NSAppleEventDescriptor? {
        guard let script = NSAppleScript(source: source) else {
            error = [
                NSAppleScript.errorNumber: -1,
                NSAppleScript.errorMessage: "Could not compile AppleScript source.",
            ]
            return nil
        }
        return script.executeAndReturnError(&error)
    }
}