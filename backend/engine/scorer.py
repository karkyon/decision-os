"""
Scorer v3: 信頼度スコア算出
- log正規化で 0.15〜0.93 の広域分布
- INF は固定 0.15（明確区別）
- 0.75 以上 → 自動判定 / 未満 → AI補助 (設計書 5.3 準拠)

改善内容:
  Before: raw_score=1 → 0.32, raw_score=3 → 0.58（差が小さい）
  After:  raw_score=1 → 0.57, raw_score=3 → 0.76（0.75ラインを適切に超える）
"""
import math

# 自動判定閾値（設計書 5.3）
AI_ASSIST_THRESHOLD = 0.75

# 信頼度ラベル
CONFIDENCE_LABELS = {
    (0.00, 0.20): "very_low",   # INF・ほぼ不明
    (0.20, 0.40): "low",        # キーワード1個のみ
    (0.40, 0.65): "medium",     # 複数マッチだが確信度低め
    (0.65, 0.80): "high",       # 自動判定ライン付近
    (0.80, 1.01): "very_high",  # 複数マッチ + ドメイン確定
}


def calc_confidence(
    text: str,
    intent_raw_score: float,
    domain_raw_score: float,
    text_length: int,
    intent_code: str = "",
) -> float:
    """
    信頼度スコアを 0.15〜0.93 の範囲で返す。

    Args:
        text: 入力テキスト
        intent_raw_score: classifier が返す intent の生スコア（マッチ数ベース）
        domain_raw_score: classifier が返す domain の生スコア
        text_length: テキスト文字数
        intent_code: 分類コード（INF の場合は固定 0.15）
    """
    # INF またはスコア 0 → 固定 0.15
    if intent_code == "INF" or intent_raw_score == 0.0:
        return 0.15

    # log正規化（最大 8 を基準に正規化）
    intent_norm = math.log1p(intent_raw_score) / math.log1p(8)
    domain_norm = math.log1p(domain_raw_score) / math.log1p(6) if domain_raw_score > 0 else 0.0

    # 基本スコア: intent 65% + domain 25%
    base = intent_norm * 0.65 + domain_norm * 0.25

    # ボーナス
    both_bonus    = 0.07 if (intent_raw_score > 0 and domain_raw_score > 0) else 0.0
    pattern_bonus = 0.05 if intent_raw_score >= 2.0 else 0.0
    length_bonus  = 0.04 if text_length >= 30 else (0.02 if text_length >= 15 else 0.0)

    score = base + both_bonus + pattern_bonus + length_bonus
    return round(min(max(score, 0.15), 0.93), 3)


def score(item: dict) -> float:
    """item dict から信頼度を計算（ルーター向けショートカット）"""
    intent = item.get("intent", "INF")
    text   = item.get("text", "")
    i_raw  = item.get("intent_raw_score", 1.0 if intent != "INF" else 0.0)
    d_raw  = item.get("domain_raw_score", 0.0)
    return calc_confidence(text, i_raw, d_raw, len(text), intent)


def get_confidence_label(s: float) -> str:
    for (lo, hi), label in CONFIDENCE_LABELS.items():
        if lo <= s < hi:
            return label
    return "very_high"


def needs_ai_assist(confidence: float) -> bool:
    """True なら AI補助が必要（0.75 未満）"""
    return confidence < AI_ASSIST_THRESHOLD
