"""
Card identification pipeline for the backend fallback path.
iOS handles the primary scan; this is called when on-device confidence < 0.85.

Pipeline:
1. Clean OCR text
2. FTS5 search against card_cache
3. If FTS confidence >= 0.7 → return match
4. Fall back to pokemontcg.io API search
5. Try image OCR if image_b64 provided and text search failed
"""
import base64
import io
import json
import re
from datetime import datetime, timezone

from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import text, select

from app.models.card_cache import CardCache
from app.services.card_service import _api_card_to_row, _search_api
from app.services.price_service import get_price
from app.services.name_validator import NameValidator


def _clean_line(line: str) -> str:
    """Strip HP/set codes/symbols from a single OCR line."""
    s = re.sub(r'\bHP\s*\d+', '', line, flags=re.IGNORECASE)
    s = re.sub(r'\d+/\d+', '', s)            # set number "4/102"
    s = re.sub(r'\b\d{2,4}\b', '', s)        # bare HP numbers
    s = re.sub(r'[^\w\s\-\'é]', ' ', s)      # keep letters, spaces, hyphens, apostrophes
    return ' '.join(s.split()).strip()


# Known prefix artifacts from the card frame that OCR picks up before the name
_FRAME_NOISE = {
    "basic", "stage", "stage 1", "stage 2", "evolves", "evolves from",
    "single strike", "rapid strike", "fusion strike", "dynamax",
    "team", "gas", "games", "care", "ex rule", "v rule", "vmax rule",
    "pokemon", "pokémon", "trainer", "energy", "item", "supporter",
}


def _split_camelcase_glued(s: str) -> list[str]:
    """
    Split tokens that OCR has fused. Examples:
      "GASBulbasaur" -> ["GAS", "Bulbasaur"]
      "MimikyuVnAx"  -> ["Mimikyu", "Vn", "Ax"]
      "mASO Pinsir"  -> ["m", "ASO", "Pinsir"]
    Splits at boundaries: lowercase->uppercase, letter->digit, digit->letter,
    and at any run of 2+ uppercase letters between lowercase neighbors.
    """
    # Insert space before uppercase that follows a lowercase
    s = re.sub(r'(?<=[a-z])(?=[A-Z])', ' ', s)
    # Insert space before uppercase that's followed by lowercase but preceded by uppercase ("VMAx" -> "V MAx")
    s = re.sub(r'(?<=[A-Z])(?=[A-Z][a-z])', ' ', s)
    # Letter <-> digit
    s = re.sub(r'(?<=[A-Za-z])(?=\d)|(?<=\d)(?=[A-Za-z])', ' ', s)
    return [t for t in s.split() if t]


def _candidate_lines(raw: str) -> list[str]:
    """
    Extract candidate card-name lines from multi-line OCR output, ranked best-first.

    OCR commonly returns lines like:
      ["BASIC", "Gyarados", "180"]    — Gyarados EX with noise on either side
      ["CARE Heracross", "120"]       — foil shine glued "CARE" to "Heracross"
      ["GASBulbasaur"]                — set logo glued to card name with no space
      ["MimikyuVnAx"]                 — "VMAX" badge glued to name

    Strategy: for each line, generate multiple candidate strings:
      1. cleaned full line (minus frame-noise prefixes)
      2. each word in isolation (catches "Heracross" from "CARE Heracross")
      3. camelcase-split words (catches "Bulbasaur" from "GASBulbasaur")
    """
    if not raw:
        return []

    seen: set[str] = set()
    candidates: list[tuple[float, str]] = []

    def add(text: str, base_score: float) -> None:
        text = text.strip()
        if not text or len(text) < 3:
            return
        if text.lower() in _FRAME_NOISE:
            return
        if text.lower() in seen:
            return
        seen.add(text.lower())
        alpha = sum(1 for c in text if c.isalpha())
        if alpha < 3:
            return
        score = base_score + alpha
        if not any(c.isdigit() for c in text):
            score += 5

        # Title-case bonus: real card names are capitalized (Charizard, Greninja, Urshifu)
        # OCR garbage tends to be all-lowercase or mixed-case mid-word (sEsErE)
        first_word = text.split()[0] if text.split() else ""
        if first_word and first_word[0].isupper() and first_word[1:].islower():
            score += 4

        # Reading-friendliness bonus: penalize tokens with unusual letter patterns.
        # Real Pokémon names tend to have vowel/consonant alternation. OCR garbage like
        # "Sesere" has it too — but tokens with 3+ same letter in a row, no vowels, or
        # > 50% uppercase usually aren't card names.
        has_vowel = any(c in "aeiouAEIOU" for c in text)
        if not has_vowel:
            score -= 8
        upper_ratio = sum(1 for c in text if c.isupper()) / max(alpha, 1)
        if upper_ratio > 0.7 and alpha > 4:
            score -= 3   # likely a set code or all-caps frame noise

        candidates.append((score, text))

    for raw_line in raw.strip().splitlines():
        cleaned = _clean_line(raw_line)
        if not cleaned:
            continue
        words = cleaned.split()
        # Strip frame-noise prefixes
        while words and words[0].lower() in _FRAME_NOISE:
            words = words[1:]
        if not words:
            continue

        # 1. Full cleaned line (highest base score)
        add(' '.join(words), base_score=10)

        # 2. Each individual word
        for w in words:
            add(w, base_score=5)

        # 3. Camelcase-split words (catches glued OCR tokens)
        for w in words:
            parts = _split_camelcase_glued(w)
            if len(parts) > 1:
                # The longest part is likely the card name
                longest = max(parts, key=len)
                add(longest, base_score=8)
                # Also try joining adjacent parts (handles "Single Strike Urshifu" if glued)
                for i in range(len(parts) - 1):
                    add(' '.join(parts[i:i+2]), base_score=6)

    candidates.sort(key=lambda x: -x[0])
    return [c[1] for c in candidates]


def _clean_ocr(raw: str) -> str:
    """Backward-compat: returns the top-ranked candidate."""
    cands = _candidate_lines(raw)
    return cands[0] if cands else ""


def _jaro_winkler(s1: str, s2: str) -> float:
    """Jaro-Winkler similarity for short string matching."""
    if s1 == s2:
        return 1.0
    len1, len2 = len(s1), len(s2)
    if len1 == 0 or len2 == 0:
        return 0.0

    match_dist = max(len1, len2) // 2 - 1
    s1_matches = [False] * len1
    s2_matches = [False] * len2
    matches = 0
    transpositions = 0

    for i in range(len1):
        start = max(0, i - match_dist)
        end = min(i + match_dist + 1, len2)
        for j in range(start, end):
            if s2_matches[j] or s1[i] != s2[j]:
                continue
            s1_matches[i] = s2_matches[j] = True
            matches += 1
            break

    if matches == 0:
        return 0.0

    k = 0
    for i in range(len1):
        if not s1_matches[i]:
            continue
        while not s2_matches[k]:
            k += 1
        if s1[i] != s2[k]:
            transpositions += 1
        k += 1

    jaro = (matches / len1 + matches / len2 + (matches - transpositions / 2) / matches) / 3
    prefix = 0
    for i in range(min(4, min(len1, len2))):
        if s1[i] == s2[i]:
            prefix += 1
        else:
            break
    return jaro + prefix * 0.1 * (1 - jaro)


async def identify_card(
    ocr_text: str | None,
    ocr_confidence: float | None,
    image_b64: str | None,
    user_id: str,
    db: AsyncSession,
) -> dict | None:
    """
    Returns dict with: card_id, name, set_name, number, image_url_sm, confidence, market_price, pipeline
    Returns None if no match found.

    Tries each OCR candidate line (best-ranked first), keeping the highest-scoring match
    across all candidates. Multi-line OCR commonly puts noise (energy type, HP, set codes)
    before the actual card name.

    Pipeline:
      1. Extract OCR candidate lines (multi-line, camelcase-split, word-by-word).
      2. Pass each candidate through NameValidator (exact + rapidfuzz against 5,437 known names).
         Validated candidates get prepended at the front of the search list, so corrected
         names like "Charmander" (from OCR "@harmander") get searched before raw garbage.
      3. FTS5 + Jaro-Winkler against cached card data.
      4. Fall back to pokemontcg.io API search with prefix-truncated forms.
    """
    raw_candidates = _candidate_lines(ocr_text or "")

    # --- NEW: validate + correct against canonical Pokémon name dictionary ---
    validator = NameValidator.get()
    validated_candidates: list[str] = []
    seen_validated: set[str] = set()
    for cand in raw_candidates[:8]:
        result = validator.validate(cand)
        if result.matched and result.canonical_name:
            key = result.canonical_name.lower()
            if key not in seen_validated:
                seen_validated.add(key)
                validated_candidates.append(result.canonical_name)

    # Build the final search list: corrected names first, then raw candidates as backup
    candidates: list[str] = []
    seen_all: set[str] = set()
    for c in validated_candidates + raw_candidates:
        if c.lower() not in seen_all:
            seen_all.add(c.lower())
            candidates.append(c)

    best_match: dict | None = None
    best_score = 0.0

    for cand in candidates[:5]:  # cap at top-5 candidates
        if len(cand) < 2:
            continue

        # Stage 1: FTS5 search on cached cards
        result = await _fts_search(cand, db)
        if result:
            card, confidence = result
            if confidence > best_score:
                price_data = await get_price(card.card_id, db)
                best_score = confidence
                best_match = {
                    "card_id": card.card_id,
                    "name": card.name,
                    "set_name": card.set_name,
                    "number": card.number,
                    "image_url_sm": card.image_url_sm,
                    "confidence": confidence,
                    "market_price": price_data.get("market_price") if price_data else None,
                    "pipeline": "fts_backend",
                }
                # If we found a perfect match, skip remaining candidates
                if confidence >= 0.95:
                    return best_match

    # If any FTS match was decent, return it
    if best_match and best_score >= 0.7:
        return best_match

    # Stage 2: pokemontcg.io API search using top candidates
    # Also try a prefix-truncated form of each candidate to catch OCR errors like "Grening" -> Greninja
    api_candidates: list[str] = []
    for cand in candidates[:5]:
        api_candidates.append(cand)
        # Prefix form: try the first word truncated to ~5 chars for prefix wildcard search
        first_word = cand.split()[0] if cand.split() else cand
        if len(first_word) >= 5:
            api_candidates.append(first_word[:5])
    # Deduplicate while preserving order
    seen_cands: set[str] = set()
    api_candidates = [c for c in api_candidates if not (c.lower() in seen_cands or seen_cands.add(c.lower()))]

    for cand in api_candidates[:5]:
        if len(cand) < 2:
            continue
        api_results = await _search_api(cand, None, 5)
        if api_results:
            # Cache the results
            for card_data in api_results:
                existing = await db.execute(
                    select(CardCache).where(CardCache.card_id == card_data["id"])
                )
                if not existing.scalar_one_or_none():
                    db.add(_api_card_to_row(card_data))
            await db.commit()

            for card_data in api_results:
                await db.execute(
                    text("INSERT OR REPLACE INTO card_fts(card_id, name) VALUES (:id, :name)"),
                    {"id": card_data["id"], "name": card_data["name"]},
                )
            await db.commit()

            # Score results with Jaro-Winkler against this candidate
            best = max(
                api_results,
                key=lambda c: _jaro_winkler(cand.lower(), c["name"].lower()),
            )
            score = _jaro_winkler(cand.lower(), best["name"].lower())
            if score > best_score:
                price_data = await get_price(best["id"], db)
                best_score = score
                best_match = {
                    "card_id": best["id"],
                    "name": best["name"],
                    "set_name": best.get("set", {}).get("name"),
                    "number": best.get("number"),
                    "image_url_sm": best.get("images", {}).get("small"),
                    "confidence": round(score, 3),
                    "market_price": price_data.get("market_price") if price_data else None,
                    "pipeline": "api_fuzzy",
                }
                if score >= 0.95:
                    return best_match

    if best_match:
        return best_match

    # Stage 3: Image OCR fallback (if image provided)
    if image_b64:
        extracted = await _ocr_image(image_b64)
        if extracted and extracted != (candidates[0] if candidates else ""):
            return await identify_card(extracted, None, None, user_id, db)

    return None

    return None


async def _fts_search(query: str, db: AsyncSession) -> tuple[CardCache, float] | None:
    """Run FTS5 search and score top result with Jaro-Winkler."""
    try:
        result = await db.execute(
            text("""
                SELECT c.card_id, c.name, c.set_id, c.set_name, c.number,
                       c.image_url_sm, c.rarity,
                       bm25(card_fts) AS score
                FROM card_fts f
                JOIN card_cache c ON c.card_id = f.card_id
                WHERE card_fts MATCH :query
                ORDER BY score
                LIMIT 5
            """),
            {"query": f'"{query}"'},
        )
        rows = result.fetchall()
        if not rows:
            # Try prefix match
            result = await db.execute(
                text("""
                    SELECT c.card_id, c.name, c.set_id, c.set_name, c.number,
                           c.image_url_sm, c.rarity,
                           bm25(card_fts) AS score
                    FROM card_fts f
                    JOIN card_cache c ON c.card_id = f.card_id
                    WHERE card_fts MATCH :query
                    ORDER BY score
                    LIMIT 5
                """),
                {"query": f"{query}*"},
            )
            rows = result.fetchall()

        if not rows:
            return None

        # Score with Jaro-Winkler for final ranking
        best_row = None
        best_score = 0.0
        for row in rows:
            score = _jaro_winkler(query.lower(), row[1].lower())
            if score > best_score:
                best_score = score
                best_row = row

        if best_row is None or best_score < 0.6:
            return None

        card = await db.get(CardCache, best_row[0])
        return (card, round(best_score, 3))

    except Exception:
        return None


async def _ocr_image(image_b64: str) -> str | None:
    """Extract text from base64 image using pytesseract (if available)."""
    try:
        import pytesseract
        from PIL import Image

        img_bytes = base64.b64decode(image_b64)
        img = Image.open(io.BytesIO(img_bytes))

        # Crop top 25% for card name band
        w, h = img.size
        title_band = img.crop((0, 0, w, int(h * 0.25)))

        text = pytesseract.image_to_string(title_band, config='--psm 7')
        return _clean_ocr(text)
    except Exception:
        return None
