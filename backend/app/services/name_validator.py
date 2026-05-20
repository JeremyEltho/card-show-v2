"""
Local Pokémon name validation + fuzzy correction.

Loaded once at startup. Corrects noisy OCR text against a canonical database of
valid card names BEFORE querying pokemontcg.io, avoiding wasted API calls on garbage.

3-stage pipeline per candidate:
  Stage 1 — O(1) exact normalized lookup
  Stage 2 — rapidfuzz WRatio, threshold 82
  Stage 3 — None (caller falls back to API with original text)
"""
from __future__ import annotations

import json
import logging
import re
import time
from dataclasses import dataclass
from functools import lru_cache
from pathlib import Path
from typing import Optional

from rapidfuzz import fuzz, process as rf_process

logger = logging.getLogger(__name__)

DATA_FILE = Path(__file__).parent.parent / "data" / "pokemon_names.json"

# ---------------------------------------------------------------------------
# Known valid card suffixes / prefixes (used for scoring bonuses)
# ---------------------------------------------------------------------------
VALID_SUFFIXES = {"ex", "EX", "GX", "V", "VMAX", "VSTAR", "BREAK",
                  "Radiant", "Ancient", "Future", "LEGEND"}
MULTI_WORD_PREFIXES = {"Single Strike", "Rapid Strike", "Fusion Strike",
                       "Dark", "Shining", "Radiant", "Ancient", "Future"}

# ---------------------------------------------------------------------------
# Common OCR substitution mistakes
# ---------------------------------------------------------------------------
OCR_CORRECTIONS: list[tuple[str, str]] = [
    (r"@",      "a"),   # @ -> a  (most common: @harmander -> Charmander)
    (r"\b0\b",  "O"),   # standalone 0 -> O
    (r"(?<=[a-zA-Z])0(?=[a-zA-Z])", "o"),  # embedded 0 -> o
    (r"(?<=[a-zA-Z])1(?=[a-zA-Z])", "l"),  # embedded 1 -> l
    (r"\brn\b",  "m"),  # "rn" confusion -> m
    (r"rn",      "m"),  # same mid-word
    (r"vv",      "w"),  # double-v -> w
    (r"VV",      "W"),
    (r"\|",      "I"),  # pipe -> I
    (r"€",       "e"),  # stray euro sign
    (r"•",       ""),   # bullet point
    (r"[·•·]",   ""),   # various dots
    (r"[^\w\s\-\']", " "),  # strip remaining symbols
]

# ---------------------------------------------------------------------------
# Validation result
# ---------------------------------------------------------------------------
@dataclass
class ValidationResult:
    matched: bool
    canonical_name: Optional[str]
    raw_ocr: str
    normalized: str
    match_source: str        # "exact" | "fuzzy" | "none"
    confidence: float        # 0–100, rapidfuzz scale
    duration_ms: float


# ---------------------------------------------------------------------------
# NameValidator
# ---------------------------------------------------------------------------
class NameValidator:
    """Singleton — call NameValidator.get() after load()."""

    _instance: Optional["NameValidator"] = None

    def __init__(self, data: dict) -> None:
        pokemon_full: list[str] = data.get("pokemon_full", [])
        pokemon_base: list[str] = data.get("pokemon_base", [])
        trainers: list[str]     = data.get("trainers", [])
        energy: list[str]       = data.get("energy", [])

        # Combined canonical list — all valid names
        all_names = list(dict.fromkeys(
            pokemon_full + pokemon_base + trainers + energy
        ))
        self._canonical: list[str] = all_names

        # Normalized -> canonical mapping for O(1) exact lookups
        self._normalized_map: dict[str, str] = {
            self._normalize(n): n for n in all_names
        }

        # Set of base Pokémon names for bonus scoring
        self._pokemon_set: set[str] = {n.lower() for n in pokemon_base}

        logger.info(
            "NameValidator loaded: %d canonical names (%d unique normalized)",
            len(self._canonical), len(self._normalized_map),
        )

    # -----------------------------------------------------------------------
    # Public API
    # -----------------------------------------------------------------------

    @classmethod
    def load(cls) -> "NameValidator":
        """Load from disk and cache singleton."""
        if cls._instance is not None:
            return cls._instance
        if not DATA_FILE.exists():
            logger.warning("pokemon_names.json not found — validator running in fallback mode")
            cls._instance = cls({"pokemon_full": [], "pokemon_base": [],
                                  "trainers": [], "energy": []})
            return cls._instance
        with open(DATA_FILE) as f:
            data = json.load(f)
        cls._instance = cls(data)
        return cls._instance

    @classmethod
    def get(cls) -> "NameValidator":
        if cls._instance is None:
            return cls.load()
        return cls._instance

    def validate(self, raw_ocr: str) -> ValidationResult:
        """
        Run the 3-stage pipeline against a single OCR candidate.

        Logs each candidate with: raw, normalized, match, confidence.
        """
        t0 = time.perf_counter()
        normalized = self._normalize(raw_ocr)

        # Stage 1 — exact normalized lookup
        if normalized in self._normalized_map:
            canonical = self._normalized_map[normalized]
            ms = (time.perf_counter() - t0) * 1000
            self._log(raw_ocr, normalized, canonical, 100.0, "exact")
            return ValidationResult(
                matched=True, canonical_name=canonical,
                raw_ocr=raw_ocr, normalized=normalized,
                match_source="exact", confidence=100.0, duration_ms=ms,
            )

        # Bail early on inputs that can't safely fuzzy-match:
        #   - Pure digits/whitespace
        #   - Fewer than 4 alphabetic characters (too little signal for fuzzy match)
        #   - Single-word inputs shorter than 4 letters
        alpha_count = sum(1 for c in normalized if c.isalpha())
        if (
            len(normalized) < 4
            or re.fullmatch(r'[\d\s]+', normalized)
            or alpha_count < 4
        ):
            return self._no_match(raw_ocr, normalized, t0)

        # Stage 2 — rapidfuzz WRatio (extract top 5, filter by length-ratio guard)
        top_matches = rf_process.extract(
            normalized,
            self._normalized_map.keys(),
            scorer=fuzz.WRatio,
            score_cutoff=82,
            limit=5,
        )
        for matched_norm, score, _ in top_matches:
            canonical = self._normalized_map[matched_norm]

            # Length-ratio guard (bidirectional): reject if the candidate length differs
            # too much from the canonical match in either direction. Stops:
            #   - "Miss" (4) -> "Miss Fortune Sisters" (20)  : short -> long
            #   - "Grening" (7) -> "N" (1)                   : long -> short
            len_a, len_b = len(normalized), len(matched_norm)
            len_ratio = min(len_a, len_b) / max(len_a, len_b, 1)
            if len_ratio < 0.5 and score < 95:
                continue  # try the next candidate

            score = self._apply_ranking_bonus(normalized, canonical, score)
            if score >= 82:
                ms = (time.perf_counter() - t0) * 1000
                self._log(raw_ocr, normalized, canonical, score, "fuzzy")
                return ValidationResult(
                    matched=True, canonical_name=canonical,
                    raw_ocr=raw_ocr, normalized=normalized,
                    match_source="fuzzy", confidence=round(score, 1), duration_ms=ms,
                )

        return self._no_match(raw_ocr, normalized, t0)

    def validate_candidates(self, candidates: list[str]) -> list[ValidationResult]:
        """Validate a list of OCR candidates, returning all results ranked best-first."""
        results = [self.validate(c) for c in candidates]
        results.sort(key=lambda r: (-r.confidence, r.match_source != "exact"))
        return results

    def best_canonical(self, candidates: list[str]) -> Optional[str]:
        """
        Convenience: return the best canonical name from a list of OCR candidates,
        or None if no candidate clears the threshold.
        """
        for r in self.validate_candidates(candidates):
            if r.matched:
                return r.canonical_name
        return None

    # -----------------------------------------------------------------------
    # Internal helpers
    # -----------------------------------------------------------------------

    @lru_cache(maxsize=4096)
    def _normalize(self, text: str) -> str:
        """Normalize OCR text: fix common mistakes, lowercase, strip symbols."""
        s = text.strip()
        for pattern, replacement in OCR_CORRECTIONS:
            s = re.sub(pattern, replacement, s)
        # Collapse whitespace
        s = ' '.join(s.split())
        return s.lower().strip()

    def _apply_ranking_bonus(self, normalized: str, canonical: str, score: float) -> float:
        """Boost score based on ranking heuristics."""
        canonical_lower = canonical.lower()

        # Bonus: candidate matches a known base Pokémon name
        if normalized in self._pokemon_set:
            score = min(score + 8, 100)

        # Bonus: candidate is exactly one of the words in the canonical name
        words = canonical_lower.split()
        if normalized in words and len(normalized) >= 4:
            score = min(score + 5, 100)

        # Bonus: candidate is title-case (first letter uppercase, rest lower)
        if canonical[0].isupper() and canonical[1:].islower():
            score = min(score + 2, 100)

        # Bonus: canonical has a valid suffix
        if any(canonical.endswith(" " + s) for s in VALID_SUFFIXES):
            score = min(score + 2, 100)

        # Penalty: candidate has excessive consecutive same characters (OCR noise)
        if re.search(r'(.)\1{2,}', normalized):
            score = max(score - 10, 0)

        # Penalty: candidate is mostly numeric
        digit_ratio = sum(c.isdigit() for c in normalized) / max(len(normalized), 1)
        if digit_ratio > 0.4:
            score = max(score - 20, 0)

        return score

    def _no_match(self, raw_ocr: str, normalized: str, t0: float) -> ValidationResult:
        ms = (time.perf_counter() - t0) * 1000
        self._log(raw_ocr, normalized, None, 0.0, "none")
        return ValidationResult(
            matched=False, canonical_name=None,
            raw_ocr=raw_ocr, normalized=normalized,
            match_source="none", confidence=0.0, duration_ms=ms,
        )

    @staticmethod
    def _log(raw: str, normalized: str, match: Optional[str], conf: float, source: str) -> None:
        if match:
            logger.debug(
                "RAW: %-25s NORMALIZED: %-25s FUZZY MATCH: %-25s CONFIDENCE: %.1f [%s]",
                repr(raw), repr(normalized), repr(match), conf, source,
            )
        else:
            logger.debug(
                "RAW: %-25s NORMALIZED: %-25s NO MATCH",
                repr(raw), repr(normalized),
            )
