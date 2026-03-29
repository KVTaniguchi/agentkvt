import Foundation

/// Heuristic detection of generic assistant refusals (Llama “no objective” boilerplate), shared by objective workers and mission retry.
enum MetaRefusalText {
    static func isLikelyRefusal(_ text: String) -> Bool {
        let t = text.lowercased()
        let needles = [
            "don't have any specific",
            "don't have any predefined",
            "no predefined goals",
            "no missions to execute",
            "don't have any mission",
            "i don't have any instructions",
            "i can provide information and assist",
            "i am ready to assist",
            "however, i don't have",
            "don't have any specific objective",
        ]
        return needles.contains { t.contains($0) }
    }
}
