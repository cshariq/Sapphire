//
//  UniqueFileName.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-10-07

import Foundation

nonisolated enum UniqueFileName {
    static func candidate(base: String, pathExtension: String, exists: (String) -> Bool) -> String {
        let cleanBase = base.isEmpty ? "Untitled" : base
        func name(_ suffix: Int?) -> String {
            let stem = suffix.map { "\(cleanBase) \($0)" } ?? cleanBase
            return pathExtension.isEmpty ? stem : "\(stem).\(pathExtension)"
        }
        if !exists(name(nil)) { return name(nil) }
        var counter = 2
        while exists(name(counter)), counter < 10_000 { counter += 1 }
        return name(counter)
    }

    static func url(in directory: URL, base: String, pathExtension: String) -> URL {
        let fileManager = FileManager.default
        let chosen = candidate(base: base, pathExtension: pathExtension) {
            fileManager.fileExists(atPath: directory.appendingPathComponent($0).path)
        }
        return directory.appendingPathComponent(chosen)
    }

    static func copyName(for fileName: String) -> String {
        let ext = (fileName as NSString).pathExtension
        let base = (fileName as NSString).deletingPathExtension
        return ext.isEmpty ? "\(base) Copy" : "\(base) Copy.\(ext)"
    }
}