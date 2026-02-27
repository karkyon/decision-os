"""
Classifier: Intent / Domain の分類
- 辞書マッチング（キーワード + 正規表現パターン）
- 信頼度スコアは Scorer が担当
"""
import json
import re
from typing import Tuple
from pathlib import Path

DICT_DIR = Path(__file__).parent / "dictionary"


def _load_dict(name: str) -> dict:
    path = DICT_DIR / f"{name}.json"
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


_intent_dict: dict = None
_domain_dict: dict = None


def _get_intent_dict() -> dict:
    global _intent_dict
    if _intent_dict is None:
        _intent_dict = _load_dict("intent")
    return _intent_dict


def _get_domain_dict() -> dict:
    global _domain_dict
    if _domain_dict is None:
        _domain_dict = _load_dict("domain")
    return _domain_dict


def classify_intent(text: str) -> Tuple[str, float]:
    """Intent分類。 (intent_code, raw_score) を返す"""
    d = _get_intent_dict()
    scores = {code: 0.0 for code in d}

    for code, rules in d.items():
        for kw in rules.get("keywords", []):
            if kw in text:
                scores[code] += 1.0

        for pat in rules.get("patterns", []):
            if re.search(pat, text):
                scores[code] += 1.5  # パターンマッチは高めに

    best_code = max(scores, key=scores.get)
    best_score = scores[best_code]

    # スコアが0ならINFにフォールバック
    if best_score == 0:
        return "INF", 0.0

    return best_code, best_score


def classify_domain(text: str) -> Tuple[str, float]:
    """Domain分類。 (domain_code, raw_score) を返す"""
    d = _get_domain_dict()
    scores = {code: 0.0 for code in d}

    for code, rules in d.items():
        for kw in rules.get("keywords", []):
            if kw in text:
                scores[code] += 1.0

    best_code = max(scores, key=scores.get)
    best_score = scores[best_code]

    if best_score == 0:
        return "SPEC", 0.0

    return best_code, best_score
