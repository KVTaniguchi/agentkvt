import Foundation

/// Strips PII from email body before the LLM sees it. Removes SSN, gov IDs, bank account numbers,
/// and optionally full names (except "User"). Use regex for speed; a local "Sanitizer" model can be added later.
public struct EmailSanitizer {
    public init() {}

    /// Sanitize body text: replace sensitive patterns with placeholders.
    public func sanitize(_ body: String) -> String {
        var out = body
        out = replaceSSN(in: out)
        out = replaceGovIds(in: out)
        out = replaceBankAccountNumbers(in: out)
        out = replaceFullNames(in: out)
        return out
    }

    /// SSN: 123-45-6789 or 123456789
    private func replaceSSN(in text: String) -> String {
        let pattern = #"\b\d{3}[-\s]?\d{2}[-\s]?\d{4}\b|\b\d{9}\b"#
        return text.replacingOccurrences(of: pattern, with: "[REDACTED_SSN]", options: .regularExpression)
    }

    /// Government IDs: long digit strings that might be IDs (e.g. 10–20 digits)
    private func replaceGovIds(in text: String) -> String {
        let pattern = #"\b\d{10,20}\b"#
        return text.replacingOccurrences(of: pattern, with: "[REDACTED_ID]", options: .regularExpression)
    }

    /// Bank-style account numbers: 4+ groups of 4 digits, or 12+ consecutive digits
    private func replaceBankAccountNumbers(in text: String) -> String {
        var out = text
        out = out.replacingOccurrences(of: #"\b\d{4}[\s-]?\d{4}[\s-]?\d{4}[\s-]?\d{4}(\d{4})?\b"#, with: "[REDACTED_ACCOUNT]", options: .regularExpression)
        out = out.replacingOccurrences(of: #"\b\d{12,}\b"#, with: "[REDACTED_ACCOUNT]", options: .regularExpression)
        return out
    }

    /// Heuristic: replace Title Case phrases (2–3 words) that might be names. Preserve "User".
    private func replaceFullNames(in text: String) -> String {
        let words = text.split(separator: " ", omittingEmptySubsequences: false)
        var result: [String] = []
        var i = 0
        let skipSet: Set<String> = ["User", "The", "A", "An", "To", "In", "On", "At", "For", "And", "Or", "But"]
        while i < words.count {
            let w = String(words[i])
            if w.lowercased() == "user" {
                result.append(w)
                i += 1
                continue
            }
            if skipSet.contains(w) {
                result.append(w)
                i += 1
                continue
            }
            if isTitleCase(w) && i + 1 < words.count {
                let next = String(words[i + 1])
                if isTitleCase(next) {
                    result.append("[NAME]")
                    if i + 2 < words.count && isTitleCase(String(words[i + 2])) {
                        i += 3
                    } else {
                        i += 2
                    }
                    continue
                }
            }
            result.append(w)
            i += 1
        }
        return result.joined(separator: " ")
    }

    private func isTitleCase(_ s: String) -> Bool {
        guard let first = s.first, first.isUppercase else { return false }
        return s.dropFirst().allSatisfy { $0.isLowercase || $0 == "'" }
    }
}
