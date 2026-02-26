"""
Scorer: 分類の信頼度スコアを算出する
"""

def score(item: dict) -> float:
    s = 0.5
    if item.get("intent") not in ("INF", None):
        s += 0.25
    if item.get("domain") not in ("GENERAL", None):
        s += 0.15
    if item.get("ref") is not None:
        s += 0.10
    return round(min(s, 1.0), 2)
