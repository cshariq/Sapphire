import Foundation
import XCTest
@testable import Sapphire

final class LocalizationFormattingTests: XCTestCase {
    // Run each locale in its own process with -testLanguage/-testRegion.
    private var isChinese: Bool {
        Locale.current.language.languageCode?.identifier == "zh"
    }

    private var isTraditionalChinese: Bool {
        isChinese && (Locale.preferredLanguages.first ?? "").hasPrefix("zh-Hant")
    }

    /// Expected text for the language this test process runs in. English values are
    /// exactly what Sapphire printed before localization.
    private func expected(_ english: String, _ simplified: String, _ traditional: String) -> String {
        isTraditionalChinese ? traditional : isChinese ? simplified : english
    }

    /// Traditional Chinese uses the same thresholds and rounding; only the myriad units differ.
    private func chineseCount(_ simplified: String) -> String {
        isTraditionalChinese
            ? simplified.replacingOccurrences(of: "万", with: "萬").replacingOccurrences(of: "亿", with: "億")
            : simplified
    }

    // English columns are the pre-localization outputs; each formatter keeps its own rules.
    private let countCases: [(value: Int, playEnglish: String, playChinese: String, compactEnglish: String, compactChinese: String)] = [
        (0, "0", "0", "0", "0"),
        (1, "1", "1", "1", "1"),
        (999, "999", "999", "999", "999"),
        (1_000, "1K", "1000", "1K", "1000"),
        (1_499, "1K", "1499", "1.5K", "1499"),
        (1_500, "2K", "1500", "1.5K", "1500"),
        (9_999, "10K", "9999", "10K", "9999"),
        (10_000, "10K", "1万", "10K", "1万"),
        (12_345, "12K", "1.2万", "12.3K", "1.2万"),
        (123_456, "123K", "12万", "123.5K", "12.3万"),
        (999_999, "1000K", "100万", "1000K", "100万"),
        (1_000_000, "1.0M", "100万", "1M", "100万"),
        (1_250_000, "1.2M", "125万", "1.2M", "125万"),
        (100_000_000, "100M", "1亿", "100M", "1亿"),
        (1_000_000_000, "1000M", "10亿", "1B", "10亿"),
        (1_250_000_000, "1250M", "12亿", "1.2B", "12.5亿"),
    ]

    func testProcessUsesAnExpectedLanguageAndRegion() {
        print("LOCALIZATION_TEST_LOCALE \(Locale.current.identifier); languages=\(Locale.preferredLanguages)")
        let language = Locale.current.language.languageCode?.identifier ?? ""
        let region = Locale.current.region?.identifier ?? ""
        XCTAssertTrue(
            (language == "en" && region == "US") ||
                (language == "zh" && !isTraditionalChinese && (region == "CN" || region == "US")) ||
                (isTraditionalChinese && region == "TW"),
            "Run formatting tests in en/US, zh-Hans/CN, zh-Hans/US, or zh-Hant/TW; got \(Locale.current.identifier)"
        )
    }

    @MainActor
    func testPlayCountUsesLocaleThresholdsAndItsOwnRounding() {
        for item in countCases {
            XCTAssertEqual(
                PlayCountFetcher.formatPlayCount(item.value),
                isChinese ? chineseCount(item.playChinese) : item.playEnglish,
                "Play count \(item.value), locale \(Locale.current.identifier)"
            )
        }
    }

    func testCompactIntegerUsesLocaleThresholdsAndOneFractionDigit() {
        for item in countCases {
            XCTAssertEqual(
                item.value.compactFormatted,
                isChinese ? chineseCount(item.compactChinese) : item.compactEnglish,
                "Compact integer \(item.value), locale \(Locale.current.identifier)"
            )
        }
    }

    func testWeekdayNamesKeepTheirStoredCalendarIdentifiers() {
        let days: [(id: Int, english: String, simplified: String, traditional: String)] = [
            (1, "Sun", "周日", "週日"), (2, "Mon", "周一", "週一"), (3, "Tue", "周二", "週二"),
            (4, "Wed", "周三", "週三"), (5, "Thu", "周四", "週四"), (6, "Fri", "周五", "週五"), (7, "Sat", "周六", "週六"),
        ]

        for day in days {
            var schedule = ScheduledFocusSession()
            schedule.repeatInterval = .custom
            schedule.repeatWeekdays = [day.id]

            XCTAssertEqual(schedule.repeatDescription, expected(day.english, day.simplified, day.traditional))
            XCTAssertEqual(schedule.sortedDisplayWeekdays, [day.id])
            XCTAssertEqual(schedule.repeatWeekdays, [day.id])
            XCTAssertTrue(schedule.customRepeats(on: day.id))
        }
    }

    func testWeekdayListFormattingDoesNotReorderStoredDaysOrChangeMatching() {
        var schedule = ScheduledFocusSession()
        schedule.repeatInterval = .custom
        schedule.repeatWeekdays = [1, 7, 2]

        XCTAssertEqual(schedule.repeatDescription, expected("Mon, Sat, Sun", "周一、周六、周日", "週一、週六、週日"))
        XCTAssertEqual(schedule.sortedDisplayWeekdays, [2, 7, 1])
        XCTAssertEqual(schedule.repeatWeekdays, [1, 7, 2])
        XCTAssertEqual(
            (1...7).map { schedule.customRepeats(on: $0) },
            [true, true, false, false, false, false, true]
        )
    }

    func testLocalizedScheduleStillEncodesRawRepeatAndWeekdayValues() throws {
        var schedule = ScheduledFocusSession()
        schedule.startTime = Date(timeIntervalSince1970: 1_700_000_000)
        schedule.repeatInterval = .custom
        schedule.repeatWeekdays = [1, 7, 2]
        _ = schedule.repeatDescription

        let data = try JSONEncoder().encode(schedule)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["repeatInterval"] as? String, "custom")
        XCTAssertEqual(json["repeatWeekdays"] as? [Int], [1, 7, 2])
        XCTAssertEqual(try JSONDecoder().decode(ScheduledFocusSession.self, from: data), schedule)
    }

    // The values below look up the same localization values the weather services build.
    func testWeatherUnitsKeepTheOriginalEnglishText() {
        let windMph = 10, windKmh = 16, visibility = 10
        XCTAssertEqual(String(localized: "\(windMph) mph"), expected("10 mph", "10 英里/小时", "10 英里/小時"))
        XCTAssertEqual(String(localized: "\(windKmh) km/h"), expected("16 km/h", "16 公里/小时", "16 公里/小時"))
        XCTAssertEqual(String(localized: "\(visibility) mi"), expected("10 mi", "10 英里", "10 英里"))
        XCTAssertEqual(String(localized: "\(windKmh) km"), expected("16 km", "16 公里", "16 公里"))
        XCTAssertEqual(String(localized: "\(String(format: "%.2f", 29.92)) in"), expected("29.92 in", "29.92 英寸汞柱", "29.92 英吋汞柱"))
        XCTAssertEqual(String(localized: "\(String(1013)) hPa"), expected("1013 hPa", "1013 百帕", "1013 百帕"))
        XCTAssertEqual(String(localized: "-- mi"), expected("-- mi", "-- 英里", "-- 英里"))
        XCTAssertEqual(String(localized: "-- km"), expected("-- km", "-- 公里", "-- 公里"))
        XCTAssertEqual(String(localized: "-- in"), expected("-- in", "-- 英寸汞柱", "-- 英吋汞柱"))
        XCTAssertEqual(String(localized: "-- hPa"), expected("-- hPa", "-- 百帕", "-- 百帕"))
    }

    func testHourlyForecastLabelKeepsTheOriginalEnglishPattern() throws {
        let formatter = DateFormatter()
        formatter.dateFormat = String(localized: "weather.hourly.dateFormat", defaultValue: "ha")
        let date = try XCTUnwrap(Calendar.current.date(from: DateComponents(year: 2024, month: 3, day: 5, hour: 6)))
        XCTAssertEqual(formatter.string(from: date).uppercased(), expected("6AM", "上午6时", "上午6時"))
    }

    func testCountsKeepTheOriginalEnglishWording() {
        // Before localization these English strings did not switch to a singular form.
        XCTAssertEqual(String(localized: "\(1) items"), expected("1 items", "1 项", "1 個項目"))
        XCTAssertEqual(String(localized: "\(1) notes"), expected("1 notes", "1 条笔记", "1 則備忘錄"))
        XCTAssertEqual(String(localized: "\(1) Events"), expected("1 Events", "1 个日程", "1 個行程"))
        XCTAssertEqual(String(localized: "\(String(1000)) sessions"), expected("1000 sessions", "1000 次专注", "1000 次專注"))
        XCTAssertEqual(String(localized: "NFiles", defaultValue: "\(1) files"), expected("1 files", "1 个文件", "1 個檔案"))
        XCTAssertEqual(
            String(localized: "Your scheduled focus session is running for \(1) minutes. Stay focused!"),
            expected("Your scheduled focus session is running for 1 minutes. Stay focused!", "已按计划开始专注，时长 1 分钟。保持专注！", "你排定的專注時段正在進行，時長 1 分鐘。保持專注！")
        )
        // These already distinguished singular and plural.
        XCTAssertEqual(String(localized: "\(1) files"), expected("1 File", "1 个文件", "1 個檔案"))
        XCTAssertEqual(String(localized: "\(2) files"), expected("2 Files", "2 个文件", "2 個檔案"))
        XCTAssertEqual(
            String(localized: "Show all \(1) paired devices in an adaptive, same-size sharing card. Offline devices stay visible."),
            expected(
                "Show all 1 paired device in an adaptive, same-size sharing card. Offline devices stay visible.",
                "在自适应的等尺寸共享卡片中显示全部 1 台已配对设备。离线设备仍然可见。",
                "在自適應、相同大小的分享卡片中顯示全部 1 部已配對裝置。離線裝置仍會顯示。"
            )
        )
    }

    func testDurationsAndListsKeepTheOriginalEnglishText() {
        XCTAssertEqual(String(localized: "\(1)h \(0)m"), expected("1h 0m", "1 小时 0 分钟", "1 小時 0 分鐘"))
        XCTAssertEqual(String(localized: "\(45)m"), expected("45m", "45 分钟", "45 分鐘"))

        let names = ["A", "B", "C"]
        let separator = String(localized: "settings.permissions.listSeparator", defaultValue: ", ")
        let list = String(localized: "settings.permissions.list", defaultValue: "\(names.dropLast().joined(separator: separator)) and \(names.last!)")
        XCTAssertEqual(list, expected("A, B and C", "A、B和C", "A、B和C"))
    }
}
