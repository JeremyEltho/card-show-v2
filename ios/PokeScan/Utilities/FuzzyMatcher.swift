import Foundation

struct CardNameEntry: Decodable {
    let id: String
    let name: String
    let set: String?
}

final class FuzzyMatcher {
    static let shared = FuzzyMatcher()
    private var cardIndex: [CardNameEntry] = []

    private init() {
        guard let url = Bundle.main.url(forResource: "card_names_cache", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let entries = try? JSONDecoder().decode([CardNameEntry].self, from: data) else {
            return
        }
        cardIndex = entries
    }

    func match(_ ocrText: String) -> CardMatch? {
        guard !cardIndex.isEmpty else { return nil }
        let cleaned = clean(ocrText)
        guard cleaned.count >= 2 else { return nil }

        var best: (CardNameEntry, Float)?
        for entry in cardIndex {
            let score = jaroWinkler(cleaned.lowercased(), entry.name.lowercased())
            if score > (best?.1 ?? 0) {
                best = (entry, score)
            }
        }

        guard let (entry, score) = best, score >= 0.7 else { return nil }
        return CardMatch(
            cardId: entry.id,
            name: entry.name,
            setName: entry.set,
            number: nil,
            imageUrlSm: nil,
            confidence: score,
            marketPrice: nil,
            pipeline: "local_fuzzy"
        )
    }

    private func clean(_ text: String) -> String {
        var result = text.components(separatedBy: .newlines).first ?? text
        result = result.replacingOccurrences(of: #"HP\s*\d+"#, with: "", options: .regularExpression)
        result = result.replacingOccurrences(of: #"\d+/\d+"#, with: "", options: .regularExpression)
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func jaroWinkler(_ s1: String, _ s2: String) -> Float {
        if s1 == s2 { return 1.0 }
        let a = Array(s1), b = Array(s2)
        let la = a.count, lb = b.count
        if la == 0 || lb == 0 { return 0 }
        let matchDist = max(la, lb) / 2 - 1
        var s1m = [Bool](repeating: false, count: la)
        var s2m = [Bool](repeating: false, count: lb)
        var matches = 0, transpositions = 0

        for i in 0..<la {
            let start = max(0, i - matchDist)
            let end = min(i + matchDist + 1, lb)
            for j in start..<end {
                if s2m[j] || a[i] != b[j] { continue }
                s1m[i] = true; s2m[j] = true; matches += 1; break
            }
        }
        if matches == 0 { return 0 }
        var k = 0
        for i in 0..<la {
            guard s1m[i] else { continue }
            while !s2m[k] { k += 1 }
            if a[i] != b[k] { transpositions += 1 }
            k += 1
        }
        let fm = Float(matches)
        let jaro = (fm/Float(la) + fm/Float(lb) + (fm - Float(transpositions)/2)/fm) / 3
        var prefix = 0
        for i in 0..<min(4, min(la, lb)) {
            if a[i] == b[i] { prefix += 1 } else { break }
        }
        return jaro + Float(prefix) * 0.1 * (1 - jaro)
    }
}
