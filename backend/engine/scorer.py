"""
Scorer: 分類信頼度スコアの算出
score = keyword_match_rate * 0.4 + pattern_match * 0.3 + context_consistency * 0.3
閾値: 0.75未満はAI補助候補としてフラグ
"""


def calc_confidence(
    text: str,
    intent_raw_score: float,
    domain_raw_score: float,
    text_length: int,
) -> float:
    """
    0.0 ~ 1.0 の信頼度スコアを返す
    """
    # キーワードヒット数から基本スコア算出（5ヒットで0.5相当）
    base = min(intent_raw_score / 5.0, 0.6)

    # ドメインが特定できた場合ボーナス
    domain_bonus = 0.15 if domain_raw_score > 0 else 0.0

    # 文長ボーナス（短すぎる文は信頼度低め）
    length_bonus = 0.0
    if text_length >= 10:
        length_bonus = 0.1
    if text_length >= 30:
        length_bonus = 0.15

    score = base + domain_bonus + length_bonus
    return round(min(score, 1.0), 3)


AI_ASSIST_THRESHOLD = 0.75

def needs_ai_assist(confidence: float) -> bool:
    return confidence < AI_ASSIST_THRESHOLD
