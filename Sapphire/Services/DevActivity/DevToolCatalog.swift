//
//  DevToolCatalog.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-09-12
//

import Foundation
import SwiftUI

enum DevTaskKind: String, Codable, CaseIterable, Identifiable, Equatable {
    case ai
    case build
    case command

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .ai: return "AI Agents"
        case .build: return "Builds & Tests"
        case .command: return "Terminal Commands"
        }
    }

    var symbol: String {
        switch self {
        case .ai: return "sparkles"
        case .build: return "hammer.fill"
        case .command: return "terminal.fill"
        }
    }
}

struct DevTool: Identifiable, Hashable {
    let id: String
    let displayName: String
    let symbol: String
    let tint: Color

    static let genericAI = DevTool(id: "ai", displayName: "AI Agent", symbol: "sparkles", tint: .purple)
    static let genericBuild = DevTool(id: "build", displayName: "Build", symbol: "hammer.fill", tint: .orange)
    static let genericCommand = DevTool(id: "shell", displayName: "Command", symbol: "terminal.fill", tint: .gray)
}

enum DevBusySignal: Equatable {
    case presence
    case activity(threshold: Double)
}

struct DevToolRule {
    let tool: DevTool
    let kind: DevTaskKind
    let signal: DevBusySignal
    var isEditorHeuristic: Bool = false

    var executables: Set<String> = []
    var pathFragments: [String] = []
    var commandFragments: [String] = []
    var requiredFragments: [String] = []
    var excludedFragments: [String] = []

    func matches(_ process: DevProcess) -> Bool {
        matches(DevMatchSubject(process))
    }

    func matches(_ subject: DevMatchSubject) -> Bool {
        let command = subject.command

        for excluded in excludedFragments where command.containsBytes(excluded) { return false }
        for required in requiredFragments where !command.containsBytes(required) { return false }

        if !subject.isAppBundleExecutable, executables.contains(subject.executableName) {
            return true
        }

        for fragment in pathFragments where subject.path.containsBytes(fragment) { return true }
        for fragment in commandFragments where command.containsBytes(fragment) { return true }

        return false
    }
}

struct DevMatchSubject {
    let path: String
    let command: String
    let executableName: String
    let isAppBundleExecutable: Bool

    init(_ process: DevProcess) {
        path = process.executablePath.lowercased()
        command = process.commandLine.lowercased()
        executableName = process.executableName.lowercased()
        isAppBundleExecutable = path.containsBytes(".app/contents/macos/")
    }
}

extension String {
    func containsBytes(_ needle: String) -> Bool {
        var haystack = self
        var needle = needle
        return haystack.withUTF8 { hay in
            needle.withUTF8 { pin in
                guard !pin.isEmpty else { return true }
                guard hay.count >= pin.count,
                      let hayBase = hay.baseAddress,
                      let pinBase = pin.baseAddress else { return false }
                return memmem(hayBase, hay.count, pinBase, pin.count) != nil
            }
        }
    }
}

enum DevToolCatalog {

    // MARK: - Tools

    static let claude = DevTool(id: "claude", displayName: "Claude", symbol: "sparkle", tint: Color(red: 0.85, green: 0.47, blue: 0.29))
    static let codex = DevTool(id: "codex", displayName: "Codex", symbol: "chevron.left.forwardslash.chevron.right", tint: Color(red: 0.10, green: 0.72, blue: 0.61))
    static let cursor = DevTool(id: "cursor", displayName: "Cursor", symbol: "cursorarrow.rays", tint: Color(red: 0.35, green: 0.55, blue: 0.95))
    static let antigravity = DevTool(id: "antigravity", displayName: "Antigravity", symbol: "arrow.up.forward.circle.fill", tint: Color(red: 0.31, green: 0.60, blue: 0.98))
    static let copilot = DevTool(id: "copilot", displayName: "GitHub Copilot", symbol: "wand.and.stars", tint: Color(red: 0.55, green: 0.55, blue: 0.62))
    static let devin = DevTool(id: "devin", displayName: "Devin", symbol: "brain.head.profile", tint: Color(red: 0.16, green: 0.72, blue: 0.53))
    static let gemini = DevTool(id: "gemini", displayName: "Gemini", symbol: "sparkles", tint: Color(red: 0.26, green: 0.52, blue: 0.96))
    static let aider = DevTool(id: "aider", displayName: "Aider", symbol: "text.badge.star", tint: Color(red: 0.90, green: 0.62, blue: 0.20))
    static let amazonQ = DevTool(id: "amazonq", displayName: "Amazon Q", symbol: "sparkles", tint: Color(red: 0.95, green: 0.60, blue: 0.16))
    static let zed = DevTool(id: "zed", displayName: "Zed", symbol: "bolt.fill", tint: Color(red: 0.25, green: 0.60, blue: 0.90))
    static let vsCode = DevTool(id: "vscode", displayName: "VS Code", symbol: "chevron.left.forwardslash.chevron.right", tint: Color(red: 0.13, green: 0.47, blue: 0.79))
    static let jetbrainsAI = DevTool(id: "jetbrains", displayName: "JetBrains AI", symbol: "sparkles", tint: Color(red: 0.94, green: 0.31, blue: 0.55))

    static let xcode = DevTool(id: "xcode", displayName: "Xcode", symbol: "hammer.fill", tint: Color(red: 0.26, green: 0.53, blue: 0.96))
    static let androidStudio = DevTool(id: "androidstudio", displayName: "Android Studio", symbol: "hammer.fill", tint: Color(red: 0.24, green: 0.73, blue: 0.42))
    static let gradle = DevTool(id: "gradle", displayName: "Gradle", symbol: "hammer.fill", tint: Color(red: 0.01, green: 0.60, blue: 0.65))
    static let swiftBuild = DevTool(id: "swift", displayName: "Swift", symbol: "swift", tint: Color(red: 0.94, green: 0.35, blue: 0.20))
    static let cargo = DevTool(id: "cargo", displayName: "Cargo", symbol: "shippingbox.fill", tint: Color(red: 0.72, green: 0.42, blue: 0.22))
    static let golang = DevTool(id: "go", displayName: "Go", symbol: "hammer.fill", tint: Color(red: 0.00, green: 0.68, blue: 0.85))
    static let node = DevTool(id: "node", displayName: "Node", symbol: "shippingbox.fill", tint: Color(red: 0.40, green: 0.72, blue: 0.31))
    static let docker = DevTool(id: "docker", displayName: "Docker", symbol: "shippingbox.fill", tint: Color(red: 0.14, green: 0.52, blue: 0.93))
    static let make = DevTool(id: "make", displayName: "Make", symbol: "hammer.fill", tint: .orange)
    static let tests = DevTool(id: "tests", displayName: "Tests", symbol: "checkmark.seal.fill", tint: Color(red: 0.36, green: 0.78, blue: 0.45))
    static let python = DevTool(id: "python", displayName: "Python", symbol: "chevron.left.forwardslash.chevron.right", tint: Color(red: 0.22, green: 0.45, blue: 0.70))
    static let git = DevTool(id: "git", displayName: "Git", symbol: "arrow.triangle.branch", tint: Color(red: 0.94, green: 0.33, blue: 0.20))
    static let packageManager = DevTool(id: "packages", displayName: "Packages", symbol: "shippingbox.fill", tint: Color(red: 0.85, green: 0.30, blue: 0.30))

    // MARK: - Terminals

    static let terminalPathFragments: [String] = [
        "/terminal.app/", "/iterm.app/", "/warp.app/", "/ghostty.app/",
        "/kitty.app/", "/wezterm.app/", "/alacritty.app/", "/hyper.app/",
        "/tabby.app/", "/rio.app/", "/contour.app/"
    ]

    static let shellExecutables: Set<String> = [
        "zsh", "bash", "sh", "fish", "dash", "ksh", "csh", "tcsh", "nu",
        "login", "tmux", "screen", "script", "env", "sudo", "su", "ssh-agent",
        "starship", "direnv", "fzf", "less", "more", "man", "pager", "vim",
        "nvim", "emacs", "nano", "top", "htop", "btop", "tail", "watch",
        "sleep", "cat", "grep", "rg", "fd", "find", "ls", "git-credential-osxkeychain"
    ]

    static let neverEndingFragments: [String] = [
        "--watch", " watch", "watchman", "nodemon", "dev-server", "devserver",
        " serve", "--serve", "run dev", "run start", "run watch", "run serve",
        "next dev", "vite dev", "expo start", "ng serve", "rails server",
        "jekyll serve", "hugo server", "webpack serve", "--continuous",
        "tail -f", "journalctl -f", "docker compose up", "ollama serve"
    ]

    // MARK: - Rules

    static let rules: [DevToolRule] = aiRules + buildRules

    static let aiRules: [DevToolRule] = [
        DevToolRule(
            tool: claude, kind: .ai, signal: .activity(threshold: 12),
            executables: ["claude", "claude-code"],
            pathFragments: ["/claude-code/"],
            commandFragments: ["@anthropic-ai/claude-code"]
        ),
        DevToolRule(
            tool: codex, kind: .ai, signal: .activity(threshold: 12),
            executables: ["codex", "codex-exec", "codex-cli", "codex-responses-api-proxy"],
            pathFragments: ["/.codex/"],
            commandFragments: ["@openai/codex", "codex exec", "codex-mcp"]
        ),
        DevToolRule(
            tool: cursor, kind: .ai, signal: .activity(threshold: 12),
            executables: ["cursor-agent", "cursor-tunnel"],
            pathFragments: ["/.cursor/"],
            commandFragments: ["cursor-agent"]
        ),
        DevToolRule(
            tool: cursor, kind: .ai, signal: .activity(threshold: 20),
            isEditorHeuristic: true,
            pathFragments: ["/cursor.app/"],
            excludedFragments: ["cursoruiviewservice"]
        ),
        DevToolRule(
            tool: antigravity, kind: .ai, signal: .activity(threshold: 12),
            executables: ["antigravity"],
            pathFragments: ["/.antigravity/"]
        ),
        DevToolRule(
            tool: antigravity, kind: .ai, signal: .activity(threshold: 20),
            isEditorHeuristic: true,
            pathFragments: ["/antigravity ide.app/", "/antigravity.app/"]
        ),
        DevToolRule(
            tool: devin, kind: .ai, signal: .activity(threshold: 12),
            executables: ["devin", "windsurf", "codeium"],
            pathFragments: ["/.codeium/", "/.windsurf/"]
        ),
        DevToolRule(
            tool: devin, kind: .ai, signal: .activity(threshold: 20),
            isEditorHeuristic: true,
            executables: ["language_server_macos_arm"],
            pathFragments: ["/devin.app/", "/windsurf.app/"]
        ),
        DevToolRule(
            tool: copilot, kind: .ai, signal: .activity(threshold: 12),
            executables: ["copilot", "copilot-language-server", "github-copilot-cli"],
            commandFragments: ["copilot-language-server", "github.copilot", "gh copilot", "copilot-agent"]
        ),
        DevToolRule(
            tool: gemini, kind: .ai, signal: .activity(threshold: 12),
            executables: ["gemini"],
            commandFragments: ["@google/gemini-cli", "gemini-cli"]
        ),
        DevToolRule(
            tool: aider, kind: .ai, signal: .activity(threshold: 10),
            executables: ["aider"]
        ),
        DevToolRule(
            tool: amazonQ, kind: .ai, signal: .activity(threshold: 12),
            executables: ["qchat", "amazon-q", "q-chat"],
            pathFragments: ["/amazon q.app/", "/.aws/amazonq/"],
            commandFragments: ["q chat"]
        ),
        DevToolRule(
            tool: DevTool(id: "opencode", displayName: "OpenCode", symbol: "sparkles", tint: .teal),
            kind: .ai, signal: .activity(threshold: 12),
            executables: ["opencode", "amp", "goose", "crush", "cline"]
        ),
        DevToolRule(
            tool: zed, kind: .ai, signal: .activity(threshold: 25),
            isEditorHeuristic: true,
            pathFragments: ["/zed.app/"]
        ),
        DevToolRule(
            tool: jetbrainsAI, kind: .ai, signal: .activity(threshold: 25),
            isEditorHeuristic: true,
            commandFragments: ["llm-agent", "jetbrains.ml.llm", "ai-assistant"]
        ),
        DevToolRule(
            tool: vsCode, kind: .ai, signal: .activity(threshold: 25),
            isEditorHeuristic: true,
            pathFragments: ["/visual studio code.app/contents/frameworks/code helper (plugin)"],
            requiredFragments: ["extensionhost"]
        )
    ]

    static let buildRules: [DevToolRule] = [
        DevToolRule(
            tool: xcode, kind: .build, signal: .presence,
            executables: ["xcodebuild", "xcrun", "swift-frontend", "swiftc", "swift-driver",
                          "ld", "ld64", "clang", "clang++", "actool", "ibtool", "swift-format"],
            excludedFragments: neverEndingFragments
        ),
        DevToolRule(
            tool: xcode, kind: .build, signal: .activity(threshold: 25),
            executables: ["swbbuildservice", "xcbbuildservice"],
            pathFragments: ["swbbuildservice", "xcbbuildservice"]
        ),
        DevToolRule(
            tool: androidStudio, kind: .build, signal: .activity(threshold: 30),
            commandFragments: ["gradledaemon", "kotlin-daemon", "kotlincompiledaemon"]
        ),
        DevToolRule(
            tool: androidStudio, kind: .build, signal: .presence,
            executables: ["aapt2", "d8", "r8", "zipalign", "apksigner", "adb-install"],
            commandFragments: ["com.android.tools"]
        ),
        DevToolRule(
            tool: gradle, kind: .build, signal: .presence,
            executables: ["gradle", "gradlew", "mvn", "maven", "sbt", "ant"],
            commandFragments: ["gradlew", "mvnw", "gradle-wrapper"],
            excludedFragments: neverEndingFragments
        ),
        DevToolRule(
            tool: swiftBuild, kind: .build, signal: .presence,
            executables: ["swift", "swift-build", "swift-test", "swift-package"],
            excludedFragments: neverEndingFragments + ["swift repl"]
        ),
        DevToolRule(
            tool: cargo, kind: .build, signal: .presence,
            executables: ["cargo", "rustc", "rustup"],
            excludedFragments: neverEndingFragments
        ),
        DevToolRule(
            tool: golang, kind: .build, signal: .presence,
            executables: ["go", "compile", "gopls-build"],
            requiredFragments: [],
            excludedFragments: neverEndingFragments + ["go run", "gopls"]
        ),
        DevToolRule(
            tool: tests, kind: .build, signal: .presence,
            executables: ["pytest", "jest", "vitest", "mocha", "rspec", "phpunit", "ctest"],
            commandFragments: ["npm test", "yarn test", "pnpm test", "bun test",
                               " test --", "cargo test", "go test", "swift test",
                               "gradle test", "xcodebuild test"],
            excludedFragments: neverEndingFragments
        ),
        DevToolRule(
            tool: node, kind: .build, signal: .presence,
            executables: ["tsc", "esbuild", "rollup", "turbo", "parcel", "swc"],
            commandFragments: ["run build", "run compile", "run bundle", "run lint",
                               "run typecheck", "run type-check", "vite build",
                               "next build", "webpack --mode", "nuxt build",
                               "astro build", "ng build", "expo export"],
            excludedFragments: neverEndingFragments
        ),
        DevToolRule(
            tool: packageManager, kind: .build, signal: .presence,
            commandFragments: ["npm install", "npm ci", "yarn install", "pnpm install",
                               "bun install", "pod install", "pod update", "bundle install",
                               "pip install", "uv sync", "uv pip", "brew install",
                               "brew upgrade", "cargo fetch", "swift package resolve",
                               "gem install", "composer install"],
            excludedFragments: neverEndingFragments
        ),
        DevToolRule(
            tool: python, kind: .build, signal: .presence,
            executables: ["ruff", "mypy", "black", "pylint"],
            excludedFragments: neverEndingFragments
        ),
        DevToolRule(
            tool: make, kind: .build, signal: .presence,
            executables: ["make", "gmake", "cmake", "ninja", "bazel", "buck2", "meson", "scons"],
            excludedFragments: neverEndingFragments
        ),
        DevToolRule(
            tool: docker, kind: .build, signal: .presence,
            commandFragments: ["docker build", "docker buildx", "docker-compose build", "podman build"],
            excludedFragments: neverEndingFragments
        ),
        DevToolRule(
            tool: DevTool(id: "flutter", displayName: "Flutter", symbol: "hammer.fill", tint: Color(red: 0.26, green: 0.65, blue: 0.96)),
            kind: .build, signal: .presence,
            executables: ["flutter", "dart", "dotnet", "msbuild"],
            excludedFragments: neverEndingFragments + ["flutter run", "dotnet watch"]
        ),
        DevToolRule(
            tool: git, kind: .build, signal: .presence,
            commandFragments: ["git clone", "git push", "git pull", "git fetch",
                               "git rebase", "git-lfs", "gh pr", "gh run watch"],
            excludedFragments: neverEndingFragments
        )
    ]

    static func rule(for process: DevProcess) -> DevToolRule? {
        rule(for: DevMatchSubject(process))
    }

    static func rule(for subject: DevMatchSubject) -> DevToolRule? {
        rules.first { $0.matches(subject) }
    }

    static let editorTerminalPathFragments: [String] = [
        "cursor", "visual studio code", "antigravity", "windsurf", "devin", "zed", "android studio"
    ].map { "/\($0).app/" }

    static func isShell(_ subject: DevMatchSubject) -> Bool {
        shellExecutables.contains(subject.executableName)
    }

    static func isTerminalHost(_ subject: DevMatchSubject) -> Bool {
        if terminalPathFragments.contains(where: { subject.path.containsBytes($0) }) { return true }
        return subject.path.containsBytes(".app/contents/")
            && editorTerminalPathFragments.contains { subject.path.containsBytes($0) }
    }

    static func hostDisplayName(forPath path: String) -> String? {
        let lowered = path.lowercased()
        guard let range = lowered.range(of: ".app/") else { return nil }
        let bundlePath = String(path[path.startIndex..<path.index(range.lowerBound, offsetBy: 4)])
        let name = (bundlePath as NSString).lastPathComponent
        return name.replacingOccurrences(of: ".app", with: "")
    }
}