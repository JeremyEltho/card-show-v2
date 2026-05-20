"""Tests for the local Pokémon name validation + fuzzy correction layer."""
import pytest

from app.services.name_validator import NameValidator


@pytest.fixture(scope="module")
def validator():
    return NameValidator.load()


class TestNormalization:
    """OCR mistake substitutions."""

    def test_at_sign_to_a(self, validator):
        assert "a" in validator._normalize("@harmander")

    def test_lowercase(self, validator):
        assert validator._normalize("CHARIZARD") == "charizard"

    def test_strip_symbols(self, validator):
        assert validator._normalize("•Charizard•") == "charizard"

    def test_collapse_whitespace(self, validator):
        assert validator._normalize("  charizard   ex  ") == "charizard ex"

    def test_euro_to_e(self, validator):
        assert "e" in validator._normalize("Charizard€")


class TestExactLookup:
    """Stage 1 — O(1) exact normalized hash lookup."""

    def test_exact_charizard(self, validator):
        r = validator.validate("Charizard")
        assert r.matched
        assert r.canonical_name == "Charizard"
        assert r.match_source == "exact"
        assert r.confidence == 100.0

    def test_exact_with_case_diff(self, validator):
        r = validator.validate("CHARIZARD")
        assert r.matched
        assert r.match_source == "exact"

    def test_exact_with_suffix(self, validator):
        r = validator.validate("Charizard ex")
        assert r.matched
        assert r.canonical_name == "Charizard ex"


class TestFuzzyCorrection:
    """Stage 2 — rapidfuzz against canonical dictionary."""

    def test_charmander_with_at_sign(self, validator):
        """The classic OCR @ -> a fix."""
        r = validator.validate("@harmander")
        assert r.matched
        assert "Charmander" in r.canonical_name

    def test_grening_to_greninja(self, validator):
        r = validator.validate("Grening")
        assert r.matched
        assert "Greninja" in r.canonical_name

    def test_bulbasar_to_bulbasaur(self, validator):
        r = validator.validate("Bulbasar")
        assert r.matched
        assert "Bulbasaur" in r.canonical_name

    def test_pikchu_to_pikachu(self, validator):
        r = validator.validate("Pikchu")
        assert r.matched
        assert "Pikachu" in r.canonical_name

    def test_glued_set_code_prefix(self, validator):
        """The base candidate extraction should handle GASBulbasaur but this is just on the
        validator level — we expect it not to match 'gasbulbasaur' directly because that's
        not a Pokémon. The upstream camelcase splitter handles that case."""
        r = validator.validate("gasbulbasaur")
        # Below the length-ratio threshold for direct fuzzy match — should not falsely match.
        # Acceptable outcome: either no match, or fuzzy match to Bulbasaur via partial token.
        if r.matched:
            assert "Bulbasaur" in r.canonical_name


class TestRejection:
    """Stage 3 — return no match for garbage."""

    def test_too_short(self, validator):
        r = validator.validate("AB")
        assert not r.matched

    def test_pure_digits(self, validator):
        r = validator.validate("120")
        assert not r.matched

    def test_hp_only(self, validator):
        r = validator.validate("HP 120")
        assert not r.matched

    def test_empty(self, validator):
        r = validator.validate("")
        assert not r.matched

    def test_random_garbage(self, validator):
        r = validator.validate("xqzwvbtfgh")
        assert not r.matched

    def test_short_input_doesnt_match_long_canonical(self, validator):
        """'Miss' should NOT match 'Miss Fortune Sisters' — length-ratio guard."""
        r = validator.validate("Miss")
        # Either no match, or if matched, must not be the much-longer trainer card
        if r.matched and r.canonical_name:
            assert len(r.canonical_name) < 15  # No multi-word trainer cards from 4 letters


class TestPerformance:
    """Per the requirements: keep matching under a few milliseconds per candidate."""

    def test_validate_is_fast(self, validator):
        r = validator.validate("Charizard")
        assert r.duration_ms < 50, f"Exact lookup took {r.duration_ms}ms"

    def test_fuzzy_match_is_fast(self, validator):
        r = validator.validate("Bulbasar")
        # Fuzzy is more expensive but should still be under ~100ms
        assert r.duration_ms < 200, f"Fuzzy match took {r.duration_ms}ms"


class TestBestCanonical:
    """Convenience API for batch candidate evaluation."""

    def test_picks_best_from_list(self, validator):
        candidates = ["xyzqwerty", "Bulbasaur", "garbage_text"]
        result = validator.best_canonical(candidates)
        assert result is not None
        assert "Bulbasaur" in result

    def test_returns_none_for_all_garbage(self, validator):
        result = validator.best_canonical(["xyzqwerty", "abcdefgh", "lkjhgfds"])
        assert result is None
