import Foundation

// A Foundation-only process: never create NSApplication or load Sapphire code.
func argument(_ name: String) -> String? {
    guard let index = CommandLine.arguments.firstIndex(of: name),
          index + 1 < CommandLine.arguments.count else { return nil }
    return CommandLine.arguments[index + 1]
}

let product: Bundle
if let path = argument("--app") {
    guard let bundle = Bundle(path: path) else {
        fputs("Cannot read product bundle: \(path)\n", stderr)
        exit(2)
    }
    product = bundle
} else {
    product = .main
}
let chinese = argument("--expected-language") == "zh-Hans"
var checks: [[String: Any]] = []
func check(_ name: String, _ actual: String, _ expected: String, scope: String) {
    checks.append([
        "name": name, "scope": scope, "actual": actual,
        "expected": expected, "passed": actual == expected
    ])
}

check("General", String(localized: "General", bundle: product),
      chinese ? "通用" : "General", scope: "product")
check("Search settings", String(localized: "Search settings", bundle: product),
      chinese ? "搜索设置" : "Search settings", scope: "product")
check("Quit", String(localized: "Quit", bundle: product),
      chinese ? "退出" : "Quit", scope: "product")
check("NSCameraUsageDescription",
      product.object(forInfoDictionaryKey: "NSCameraUsageDescription") as? String ?? "<missing>",
      chinese
        ? "Sapphire 使用摄像头提供镜子小组件，让你能在刘海区域看到自己。"
        : "Sapphire uses the camera for the Mirror widget so you can see yourself in the notch.",
      scope: "product")

check("missing-key-default",
      String(localized: "fixture.absent", defaultValue: "English fallback",
             table: "ProbeFixtures", bundle: .main),
      "English fallback", scope: "fixture")
check("missing-Chinese-translation",
      String(localized: "fixture.untranslated", defaultValue: "English-only fixture",
             table: "ProbeFixtures", bundle: .main),
      "English-only fixture", scope: "fixture")

for count: Int64 in [0, 1, 2, 1000] {
    let number = count == 1000
        ? (Locale.current.region?.identifier == "FR" ? "1\u{202F}000" : "1,000")
        : String(count)
    let expected = chinese ? "\(number)个项目" : "\(number) \(count == 1 ? "item" : "items")"
    check("NFiles-\(count)",
          String(localized: "NFiles", defaultValue: "\(count) files", bundle: product),
          chinese ? "\(number) 个文件" : "\(number) files",
          scope: "product")
    check("focus-history-sessions-\(count)",
          String(localized: "\(String(count)) sessions", bundle: product),
          chinese ? "\(count) 次专注" : "\(count) sessions",
          scope: "product")
    check("plural-interpolation-\(count)",
          String(localized: "fixture.count", defaultValue: "\(count) items",
                 table: "ProbeFixtures", bundle: .main),
          expected, scope: "fixture")
    let format = NSLocalizedString("fixture.count", tableName: "ProbeFixtures",
                                   bundle: .main, value: "%lld items", comment: "")
    check("plural-NSLocalizedString-\(count)",
          String.localizedStringWithFormat(format, count), expected, scope: "fixture")
}

let name = "项目 100% %@ 🧪 General"
let count: Int64 = 2
check("two-argument-reorder-and-verbatim-name",
      String(localized: "fixture.destination", defaultValue: "Move \(count) items to \(name)",
             table: "ProbeFixtures", bundle: .main),
      chinese ? "移到\(name)：\(count)个项目" : "Move \(count) items to \(name)",
      scope: "fixture")

let archiveName = "报告 100% %@ 🧪 .zip"
check("archive-file-name-verbatim",
      String(localized: "Extracting \(archiveName)…", bundle: product),
      chinese ? "正在解压 \(archiveName)…" : "Extracting \(archiveName)…",
      scope: "product")
let step = 2, total = 7
check("step-two-parameter-order",
      String(localized: "Step \(step) of \(total)", bundle: product),
      chinese ? "第 2 步，共 7 步" : "Step 2 of 7", scope: "product")
check("weather-semantic-key-default",
      String(localized: "weather.condition.clear", defaultValue: "Clear", bundle: product),
      chinese ? "晴" : "Clear", scope: "product")

let speakerName = "客厅 100% %@ 🎵 General"
check("spotify-transferred-device-name-verbatim",
      String(localized: "Playback moved to \(speakerName).", bundle: product),
      chinese ? "已切换到 \(speakerName) 播放。" : "Playback moved to \(speakerName).",
      scope: "product")
let playbackError = "HTTP 429: %@ / 100% 🔒"
check("spotify-switch-error-detail-verbatim",
      String(localized: "Couldn’t switch device: \(playbackError)", bundle: product),
      chinese ? "无法切换设备：\(playbackError)" : "Couldn’t switch device: \(playbackError)",
      scope: "product")

let expectedLanguage = chinese ? "zh-Hans" : "en"
check("selected-product-language", product.preferredLocalizations.first ?? "<missing>",
      expectedLanguage, scope: "product")
check("selected-fixture-language", Bundle.main.preferredLocalizations.first ?? "<missing>",
      expectedLanguage, scope: "fixture")
check("requested-region", Locale.current.region?.identifier ?? "<missing>",
      Locale(identifier: argument("-AppleLocale") ?? "").region?.identifier ?? "<missing>",
      scope: "process")

func resources(_ bundle: Bundle, table: String) -> [String: String] {
    var paths: [String: String] = [:]
    for language in ["en", "zh-Hans"] {
        for ext in ["strings", "stringsdict"] {
            let key = "\(language)/\(table).\(ext)"
            if let root = bundle.resourceURL {
                let path = root.appendingPathComponent("\(language).lproj/\(table).\(ext)").path
                if FileManager.default.fileExists(atPath: path) { paths[key] = path }
            }
        }
    }
    return paths
}

let productResources = resources(product, table: "Localizable")
let infoResources = resources(product, table: "InfoPlist")
for language in ["en", "zh-Hans"] {
    check("compiled-Localizable-\(language)",
          String(productResources.keys.contains { $0.hasPrefix("\(language)/") }),
          "true", scope: "product")
    check("compiled-InfoPlist-\(language)",
          String(infoResources["\(language)/InfoPlist.strings"] != nil),
          "true", scope: "product")
}
let passed = checks.allSatisfy { $0["passed"] as? Bool == true }
let result: [String: Any] = [
    "passed": passed, "checks": checks,
    "arguments": Array(CommandLine.arguments.dropFirst()),
    "preferredLanguages": Locale.preferredLanguages,
    "locale": Locale.current.identifier,
    "productBundle": product.bundleURL.path,
    "productLocalizations": product.localizations,
    "productPreferredLocalizations": product.preferredLocalizations,
    "productDevelopmentLocalization": product.developmentLocalization ?? "<missing>",
    "productResources": productResources, "infoPlistResources": infoResources,
    "fixtureBundle": Bundle.main.bundleURL.path,
    "fixtureResources": resources(.main, table: "ProbeFixtures")
]
let data = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
FileHandle.standardOutput.write(data)
FileHandle.standardOutput.write(Data("\n".utf8))
exit(passed ? 0 : 1)
