//
//  DevActivityDetectionTests.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-09-12

import Foundation
import Testing
@testable import Sapphire

struct DevActivityDetectionTests {

    // MARK: - Fixtures

    private static func process(
        pid: pid_t = 1,
        ppid: pid_t = 1,
        path: String,
        arguments: [String] = [],
        ageSeconds: TimeInterval = 30
    ) -> DevProcess {
        DevProcess(
            pid: pid,
            ppid: ppid,
            shortName: (path as NSString).lastPathComponent,
            startedAt: Date().addingTimeInterval(-ageSeconds),
            executablePath: path,
            arguments: arguments.isEmpty ? [path] : arguments
        )
    }

    private static let terminal =
        "/System/Applications/Utilities/Terminal.app/Contents/MacOS/Terminal"

    private static func classify(_ processes: [DevProcess]) -> Set<String> {
        var table = Dictionary(uniqueKeysWithValues: processes.map { ($0.pid, $0) })
        let tasks = DevActivityScanEngine().classify(
            &table,
            configuration: .init(
                enabledKinds: ["ai", "build", "command"],
                sensitivity: 1,
                includeIDEAgents: true
            ),
            sampleCPU: { _, _ in }
        )
        return Set(tasks.map { "\($0.kind.rawValue):\($0.title)" })
    }

    // MARK: - Tool matching

    @Test(arguments: [
        ("/Users/me/Library/Application Support/Claude/claude-code/2.1.0/claude.app/Contents/MacOS/claude", [String](), "claude"),
        ("/opt/homebrew/bin/node", ["node", "/usr/lib/node_modules/@anthropic-ai/claude-code/cli.js"], "claude"),
        ("/opt/homebrew/bin/codex", ["codex"], "codex"),
        ("/Applications/ChatGPT.app/Contents/Resources/codex", ["codex", "app-server"], "codex"),
        ("/Users/me/.local/bin/cursor-agent", ["cursor-agent"], "cursor"),
        ("/Applications/Cursor.app/Contents/Frameworks/Cursor Helper (Plugin).app/Contents/MacOS/Cursor Helper (Plugin)", [], "cursor"),
        ("/Applications/Antigravity IDE.app/Contents/MacOS/Electron", [], "antigravity"),
        ("/Applications/Devin.app/Contents/MacOS/Electron", [], "devin"),
        ("/Users/me/.codeium/windsurf/language_server_macos_arm", [], "devin"),
        ("/opt/homebrew/bin/node", ["node", "/Users/me/.vscode/extensions/github.copilot-1.0/dist/language-server.js"], "copilot"),
        ("/opt/homebrew/bin/gemini", ["gemini"], "gemini"),
        ("/opt/homebrew/bin/aider", ["aider"], "aider"),

        ("/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild", ["xcodebuild", "-scheme", "App", "build"], "xcode"),
        ("/Applications/Xcode.app/usr/bin/swift-frontend", ["swift-frontend", "-c"], "xcode"),
        ("/Applications/Android Studio.app/Contents/jbr/Contents/Home/bin/java",
         ["java", "-cp", "gradle-launcher.jar", "org.gradle.launcher.daemon.bootstrap.GradleDaemon", "8.7"], "androidstudio"),
        ("/bin/sh", ["sh", "./gradlew", "assembleDebug"], "gradle"),
        ("/Users/me/.cargo/bin/cargo", ["cargo", "build", "--release"], "cargo"),
        ("/opt/homebrew/bin/npm", ["npm", "run", "build"], "node"),
        ("/opt/homebrew/bin/node", ["node", "vite", "build"], "node"),
        ("/opt/homebrew/bin/pod", ["pod", "install"], "packages"),
        ("/usr/bin/make", ["make", "-j8"], "make"),
        ("/usr/local/bin/docker", ["docker", "build", "-t", "x", "."], "docker"),
        ("/opt/homebrew/bin/pytest", ["pytest", "-q"], "tests"),
        ("/usr/bin/git", ["git", "clone", "https://example.com/x"], "git")
    ])
    func recognisesTool(path: String, arguments: [String], expected: String) {
        let rule = DevToolCatalog.rule(for: Self.process(path: path, arguments: arguments))
        #expect(rule?.tool.id == expected)
    }

    @Test(arguments: [
        ("/Applications/Claude.app/Contents/MacOS/Claude", [String]()),
        ("/opt/homebrew/bin/npm", ["npm", "run", "dev"]),
        ("/opt/homebrew/bin/tsc", ["tsc", "--watch"]),
        ("/usr/local/bin/ollama", ["ollama", "serve"]),
        ("/bin/zsh", ["zsh"])
    ])
    func ignoresNonTask(path: String, arguments: [String]) {
        let rule = DevToolCatalog.rule(for: Self.process(path: path, arguments: arguments))
        #expect(rule == nil)
    }

    // MARK: - Process trees

    @Test func reportsCommandTypedInTerminal() {
        let tasks = Self.classify([
            Self.process(pid: 100, path: Self.terminal),
            Self.process(pid: 101, ppid: 100, path: "/bin/zsh", arguments: ["zsh"]),
            Self.process(pid: 102, ppid: 101, path: "/usr/bin/rsync", arguments: ["rsync", "-a", "src/", "dst/"])
        ])
        #expect(tasks == ["command:rsync src"])
    }

    @Test func ignoresCommandThatBarelyRan() {
        let tasks = Self.classify([
            Self.process(pid: 100, path: Self.terminal),
            Self.process(pid: 101, ppid: 100, path: "/bin/zsh", arguments: ["zsh"]),
            Self.process(pid: 102, ppid: 101, path: "/bin/ls", arguments: ["ls"], ageSeconds: 1)
        ])
        #expect(tasks.isEmpty)
    }

    @Test func ignoresDevServerInTerminal() {
        let tasks = Self.classify([
            Self.process(pid: 100, path: Self.terminal),
            Self.process(pid: 101, ppid: 100, path: "/bin/zsh", arguments: ["zsh"]),
            Self.process(pid: 102, ppid: 101, path: "/opt/homebrew/bin/npm", arguments: ["npm", "run", "dev"])
        ])
        #expect(tasks.isEmpty)
    }

    @Test func foldsCompilersIntoTheirBuild() {
        let tasks = Self.classify([
            Self.process(pid: 100, path: Self.terminal),
            Self.process(pid: 101, ppid: 100, path: "/bin/zsh", arguments: ["zsh"]),
            Self.process(pid: 102, ppid: 101, path: "/usr/bin/xcodebuild", arguments: ["xcodebuild", "-scheme", "App", "build"]),
            Self.process(pid: 103, ppid: 102, path: "/usr/bin/swift-frontend", arguments: ["swift-frontend", "-c"]),
            Self.process(pid: 104, ppid: 102, path: "/usr/bin/clang", arguments: ["clang", "-c", "a.m"])
        ])
        #expect(tasks == ["build:Xcode Build"])
    }

    @Test func foldsDetachedCompilersIntoOneBuild() {
        let tasks = Self.classify([
            Self.process(pid: 102, path: "/usr/bin/xcodebuild", arguments: ["xcodebuild", "build"]),
            Self.process(pid: 200, path: "/usr/bin/swift-frontend", arguments: ["swift-frontend", "-c"]),
            Self.process(pid: 201, path: "/usr/bin/clang", arguments: ["clang", "-c", "a.m"])
        ])
        #expect(tasks == ["build:Xcode Build"])
    }

    @Test func ignoresHelperCommandsSpawnedByABuild() {
        let tasks = Self.classify([
            Self.process(pid: 100, path: Self.terminal),
            Self.process(pid: 101, ppid: 100, path: "/bin/zsh", arguments: ["zsh"]),
            Self.process(pid: 102, ppid: 101, path: "/usr/bin/make", arguments: ["make", "-j8"]),
            Self.process(pid: 103, ppid: 102, path: "/usr/bin/grep", arguments: ["grep", "-r", "x"])
        ])
        #expect(tasks == ["build:Make Build"])
    }

    @Test func surfacesBuildStartedByAnAgent() {
        let tasks = Self.classify([
            Self.process(pid: 200, path: "/Users/me/.local/bin/some-agent", arguments: ["some-agent"]),
            Self.process(pid: 201, ppid: 200, path: "/bin/zsh", arguments: ["zsh", "-c", "cargo build"]),
            Self.process(pid: 202, ppid: 201, path: "/Users/me/.cargo/bin/cargo", arguments: ["cargo", "build"])
        ])
        #expect(tasks == ["build:Cargo Build"])
    }

    @Test func ignoresAnAppsOwnSubprocesses() {
        let tasks = Self.classify([
            Self.process(pid: 300, path: "/Applications/Some App.app/Contents/MacOS/Some App"),
            Self.process(pid: 301, ppid: 300, path: "/Applications/Some App.app/Contents/MacOS/helper", arguments: ["helper"])
        ])
        #expect(tasks.isEmpty)
    }

    @Test func disabledKindsDoNotTriggerCPUSampling() {
        let rows = [
            Self.process(pid: 100, path: "/usr/bin/xcodebuild", arguments: ["xcodebuild", "build"]),
            Self.process(pid: 101, ppid: 100, path: "/usr/bin/swift-frontend", arguments: ["swift-frontend", "-c"])
        ]
        var table = Dictionary(uniqueKeysWithValues: rows.map { ($0.pid, $0) })
        var sampled = Set<pid_t>()

        let tasks = DevActivityScanEngine().classify(
            &table,
            configuration: .init(
                enabledKinds: [DevTaskKind.ai.rawValue],
                sensitivity: 1,
                includeIDEAgents: true
            ),
            sampleCPU: { pids, _ in sampled.formUnion(pids) }
        )

        #expect(tasks.isEmpty)
        #expect(sampled.isEmpty)
    }
}