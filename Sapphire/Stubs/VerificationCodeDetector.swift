#if !SAPPHIRE_FULL_BUILD
import Foundation

enum VerificationCodeDetector {
    static func find(in text: String) -> String? {
        let range = NSRange(text.startIndex..., in: text)
        guard let regex = try? NSRegularExpression(pattern: #"\b\d{4,8}\b"#),
              let match = regex.firstMatch(in: text, range: range),
              let matchRange = Range(match.range, in: text) else { return nil }
        return String(text[matchRange])
    }
}
#endif
