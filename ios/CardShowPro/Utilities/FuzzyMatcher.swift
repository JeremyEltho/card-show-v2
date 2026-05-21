import Foundation

/// On-device port of the Python NameValidator.
/// Loads the canonical Pokémon name dictionary (5,437 names) once at launch,
/// then validates OCR candidates via:
///   1. Exact normalised lookup (O(1))
///   2. Jaro-Winkler similarity with score ≥ 0.82
///   3. Bidirectional length-ratio guard
///
/// Replaces both the bundled card_names_cache.json approach AND the backend
/// /scan/identify call. Everything runs on the phone.

private struct CanonicalDictionary: Decodable {
    let pokemon_full: [String]
    let pokemon_base: [String]
    let trainers: [String]
    let energy: [String]
}

final class FuzzyMatcher {
    static let shared = FuzzyMatcher()

    // Normalised → canonical map for O(1) exact lookups
    private var normalisedMap: [String: String] = [:]

    // Flat ordered list of canonical names (for iterating fuzzy comparisons)
    private var allCanonical: [String] = []

    /// Pre-lowercased canonical names paired with their original. Avoids
    /// lowercasing 5,437 strings on every single fuzzy lookup (~10x speedup).
    private var canonicalLower: [(lower: String, original: String, length: Int)] = []

    // Lowercase set of base Pokémon names (used for ranking bonus)
    private var pokemonBase: Set<String> = []

    // Frame-noise tokens stripped before matching
    private let frameNoise: Set<String> = [
        "basic", "stage", "stage 1", "stage 2", "evolves", "evolves from",
        "single strike", "rapid strike", "fusion strike", "dynamax",
        "team", "gas", "games", "care", "ex rule", "v rule", "vmax rule",
        "pokemon", "pokémon", "trainer", "energy", "item", "supporter",
    ]

    private init() {
        load()
    }

    // MARK: - Loading

    private func load() {
        guard let url = Bundle.main.url(forResource: "pokemon_names", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let dict = try? JSONDecoder().decode(CanonicalDictionary.self, from: data) else {
            print("FuzzyMatcher: pokemon_names.json not bundled — fuzzy match disabled")
            return
        }

        var seen = Set<String>()
        var ordered: [String] = []
        for n in dict.pokemon_full + dict.pokemon_base + dict.trainers + dict.energy {
            if !seen.contains(n) {
                seen.insert(n)
                ordered.append(n)
            }
        }
        allCanonical = ordered
        // Pre-lowercase + cache length once. Lookup is hot (~30k/sec on scan).
        canonicalLower = ordered.map { name in
            let lower = name.lowercased()
            return (lower, name, lower.count)
        }
        // Build normalised → canonical map, keeping the first occurrence on collisions.
        var map: [String: String] = [:]
        for name in ordered {
            let key = normalise(name)
            if map[key] == nil { map[key] = name }
        }
        normalisedMap = map
        pokemonBase = Set(dict.pokemon_base.map { $0.lowercased() })
        print("FuzzyMatcher: loaded \(allCanonical.count) canonical names, \(normalisedMap.count) unique normalised keys")
    }

    /// Force-initialise the singleton off the main thread.
    /// Call this from app startup so the first scan isn't blocked by JSON parsing.
    static func preload() {
        Task.detached(priority: .userInitiated) {
            _ = FuzzyMatcher.shared
        }
    }

    // MARK: - Normalisation (mirrors Python validator)

    func normalise(_ text: String) -> String {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // OCR mistake corrections
        s = s.replacingOccurrences(of: "@", with: "a")
        s = s.replacingOccurrences(of: "€", with: "e")
        s = s.replacingOccurrences(of: "•", with: "")
        s = s.replacingOccurrences(of: "·", with: "")
        s = s.replacingOccurrences(of: "|", with: "I")
        s = s.replacingOccurrences(of: "rn", with: "m")
        s = s.replacingOccurrences(of: "vv", with: "w")
        s = s.replacingOccurrences(of: "VV", with: "W")
        // Embedded 0 -> o, 1 -> l between letters
        s = applyBetweenLetters(s, find: "0", replace: "o")
        s = applyBetweenLetters(s, find: "1", replace: "l")
        // Strip remaining symbols (keep letters, digits, spaces, hyphens, apostrophes)
        s = s.unicodeScalars.map { sc -> String in
            if CharacterSet.alphanumerics.contains(sc) || sc == " " || sc == "-" || sc == "'" {
                return String(sc)
            }
            return " "
        }.joined()
        // Collapse whitespace
        s = s.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return s.lowercased()
    }

    private func applyBetweenLetters(_ s: String, find: String, replace: String) -> String {
        guard find.count == 1 else { return s }
        let chars = Array(s)
        var out: [Character] = []
        for i in 0..<chars.count {
            let c = chars[i]
            if String(c) == find,
               i > 0, i < chars.count - 1,
               chars[i-1].isLetter, chars[i+1].isLetter {
                out.append(Character(replace))
            } else {
                out.append(c)
            }
        }
        return String(out)
    }

    // MARK: - Validation

    struct ValidationResult {
        let matched: Bool
        let canonicalName: String?
        let confidence: Float           // 0–1
        let source: String              // "exact" | "fuzzy" | "none"
        let normalisedInput: String
    }

    /// Validate a single candidate against the canonical dictionary.
    func validate(_ raw: String) -> ValidationResult {
        let normalised = normalise(raw)

        // Stage 1 — exact lookup
        if let canonical = normalisedMap[normalised] {
            return ValidationResult(matched: true, canonicalName: canonical,
                                    confidence: 1.0, source: "exact",
                                    normalisedInput: normalised)
        }

        // Bail on inputs unlikely to match safely
        let alpha = normalised.filter { $0.isLetter }.count
        if normalised.count < 4 || alpha < 4 {
            return ValidationResult(matched: false, canonicalName: nil,
                                    confidence: 0, source: "none",
                                    normalisedInput: normalised)
        }

        // Stage 2 — Jaro-Winkler against pre-lowercased canonical names.
        // Optimisations:
        //   - Skip entries whose length differs by > 2x from the input (cheap prefilter)
        //   - Use cached lowercased form (no re-lowering 5,437 strings per call)
        //   - Short-circuit on a near-perfect match
        let inputLen = normalised.count
        let minLen = max(3, inputLen / 2)
        let maxLen = inputLen * 2
        var bestScore: Float = 0
        var bestCanonical: String? = nil
        for entry in canonicalLower {
            // Length prefilter — most candidates differ wildly in length from the input
            if entry.length < minLen || entry.length > maxLen { continue }
            let score = jaroWinkler(normalised, entry.lower)
            if score > bestScore {
                // Bidirectional length-ratio guard (catches "Miss" vs "Miss Fortune Sisters")
                let ratio = Float(min(inputLen, entry.length)) / Float(max(inputLen, entry.length))
                if ratio < 0.5 && score < 0.95 { continue }
                bestScore = score
                bestCanonical = entry.original
                if score >= 0.98 { break }  // perfect-enough, stop scanning
            }
        }

        // Apply ranking bonus + threshold
        if let canonical = bestCanonical, bestScore >= 0.82 {
            let boosted = applyRankingBonus(normalised: normalised, canonical: canonical, score: bestScore)
            return ValidationResult(matched: true, canonicalName: canonical,
                                    confidence: boosted, source: "fuzzy",
                                    normalisedInput: normalised)
        }

        return ValidationResult(matched: false, canonicalName: nil,
                                confidence: bestScore, source: "none",
                                normalisedInput: normalised)
    }

    /// Validate a list of candidate strings (from multi-line OCR).
    /// Returns the best validated canonical name + its match metadata.
    func bestMatch(from rawCandidates: [String]) -> ValidationResult? {
        var best: ValidationResult? = nil
        for raw in rawCandidates {
            let result = validate(raw)
            if result.matched, result.confidence > (best?.confidence ?? 0) {
                best = result
                if result.confidence >= 0.95 { break }
            }
        }
        return best
    }

    /// Convenience for the scanner pipeline — accepts raw multi-line OCR text,
    /// extracts candidate lines, and returns the best validated CardMatch.
    func match(_ ocrText: String) -> CardMatch? {
        let candidates = extractCandidates(from: ocrText)
        guard let result = bestMatch(from: candidates), let name = result.canonicalName else {
            return nil
        }
        return CardMatch(
            cardId: "",                     // filled in by PokemonTCGService after API call
            name: name,
            setName: nil,
            number: nil,
            imageUrlSm: nil,
            confidence: result.confidence,
            marketPrice: nil,
            pipeline: result.source
        )
    }

    // MARK: - Candidate extraction

    /// Extract likely card-name candidates from multi-line OCR output.
    func extractCandidates(from raw: String) -> [String] {
        guard !raw.isEmpty else { return [] }
        var seen = Set<String>()
        var scored: [(Float, String)] = []

        func add(_ text: String, base: Float) {
            let cleaned = cleanLine(text)
            guard cleaned.count >= 3 else { return }
            if frameNoise.contains(cleaned.lowercased()) { return }
            if seen.contains(cleaned.lowercased()) { return }
            seen.insert(cleaned.lowercased())
            let alpha = cleaned.filter { $0.isLetter }.count
            if alpha < 3 { return }
            var score = base + Float(alpha)
            if !cleaned.contains(where: { $0.isNumber }) { score += 5 }
            scored.append((score, cleaned))
        }

        for rawLine in raw.components(separatedBy: .newlines) {
            let cleaned = cleanLine(rawLine)
            if cleaned.isEmpty { continue }
            var words = cleaned.split(separator: " ").map(String.init)
            // Strip frame-noise prefixes
            while let first = words.first, frameNoise.contains(first.lowercased()) {
                words.removeFirst()
            }
            if words.isEmpty { continue }
            add(words.joined(separator: " "), base: 10)
            for w in words { add(w, base: 5) }
            // CamelCase split: "GASBulbasaur" -> ["GAS", "Bulbasaur"]
            for w in words {
                let parts = splitCamelCaseGlued(w)
                if parts.count > 1 {
                    add(parts.max(by: { $0.count < $1.count }) ?? "", base: 8)
                    for i in 0..<parts.count - 1 {
                        add("\(parts[i]) \(parts[i+1])", base: 6)
                    }
                }
            }
        }

        scored.sort { $0.0 > $1.0 }
        return scored.map { $0.1 }
    }

    private func cleanLine(_ line: String) -> String {
        var s = line
        // Strip HP patterns
        s = s.replacingOccurrences(of: #"HP\s*\d+"#, with: "", options: [.regularExpression, .caseInsensitive])
        // Strip set numbers like "4/102"
        s = s.replacingOccurrences(of: #"\d+/\d+"#, with: "", options: .regularExpression)
        // Strip bare 2-4 digit numbers (HP values)
        s = s.replacingOccurrences(of: #"\b\d{2,4}\b"#, with: "", options: .regularExpression)
        // Keep letters, digits, spaces, hyphens, apostrophes — replace others with space
        s = s.unicodeScalars.map { sc -> String in
            if CharacterSet.alphanumerics.contains(sc) || sc == " " || sc == "-" || sc == "'" {
                return String(sc)
            }
            return " "
        }.joined()
        return s.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// Split "GASBulbasaur" -> ["GAS", "Bulbasaur"]
    private func splitCamelCaseGlued(_ s: String) -> [String] {
        var result: [String] = []
        var current = ""
        let chars = Array(s)
        for i in 0..<chars.count {
            let c = chars[i]
            if i > 0 {
                let prev = chars[i-1]
                // lower → Upper boundary
                if prev.isLowercase, c.isUppercase {
                    if !current.isEmpty { result.append(current); current = "" }
                }
                // Upper UpperLower boundary (V MAx)
                if prev.isUppercase, c.isUppercase, i + 1 < chars.count, chars[i+1].isLowercase {
                    if !current.isEmpty { result.append(current); current = "" }
                }
                // letter ↔ digit boundaries
                if (prev.isLetter && c.isNumber) || (prev.isNumber && c.isLetter) {
                    if !current.isEmpty { result.append(current); current = "" }
                }
            }
            current.append(c)
        }
        if !current.isEmpty { result.append(current) }
        return result.filter { !$0.isEmpty }
    }

    // MARK: - Ranking bonuses

    private func applyRankingBonus(normalised: String, canonical: String, score: Float) -> Float {
        var s = score
        let canonLower = canonical.lowercased()
        if pokemonBase.contains(normalised) { s = min(s + 0.08, 1.0) }
        let canonWords = canonLower.split(separator: " ").map(String.init)
        if canonWords.contains(normalised) && normalised.count >= 4 { s = min(s + 0.05, 1.0) }
        // Penalty: triple-repeated char
        let chars = Array(normalised)
        for i in 0..<chars.count - 2 where chars[i] == chars[i+1] && chars[i+1] == chars[i+2] {
            s = max(s - 0.10, 0); break
        }
        return s
    }

    // MARK: - Jaro-Winkler

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
            // When `i` is near la-1 but lb is much smaller, `start` can exceed `end`.
            // Skip rather than crash on a `start..<end` with start > end.
            if start >= end { continue }
            for j in start..<end where !s2m[j] && a[i] == b[j] {
                s1m[i] = true; s2m[j] = true; matches += 1; break
            }
        }
        if matches == 0 { return 0 }
        var k = 0
        for i in 0..<la where s1m[i] {
            while !s2m[k] { k += 1 }
            if a[i] != b[k] { transpositions += 1 }
            k += 1
        }
        let fm = Float(matches)
        let jaro = (fm / Float(la) + fm / Float(lb) + (fm - Float(transpositions) / 2) / fm) / 3
        var prefix = 0
        for i in 0..<min(4, min(la, lb)) {
            if a[i] == b[i] { prefix += 1 } else { break }
        }
        return jaro + Float(prefix) * 0.1 * (1 - jaro)
    }
}
