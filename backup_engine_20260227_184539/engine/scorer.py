"""
Scorer v2: 分類信頼度スコアの算出
- log正規化で 0.15〜0.92 の広域分布
- intent + domain 両方マッチ時にボーナス
- INFフォールバックは 0.15 固定
"""
import math

# 信頼度しきい値
AI_ASSIST_THRESHOLD = 0.75

# スコアラベル
CONFIDENCE_LABELS = {
    (0.00, 0.20): "very_low",
    (0.20, 0.40): "low",
    (0.40, 0.65): "medium",
    (0.65, 0.80): "high",
    (0.80, 1.00): "very_high",
}

def calc_confidence(
    text: str,
    intent_raw_score: float,
    domain_raw_score: float,
    text_length: int,
    intent_code: str = "",
) -> float:
    """0.0〜1.0 の信頼度スコアを返す"""

    # INF フォールバックは最低スコア
    if intent_code == "INF" or intent_raw_score == 0.0:
        return 0.15

    # log正規化（最大スコア ~10 で 0.88 付近）
    intent_norm = math.log1p(intent_raw_score) / math.log1p(12)  # 0〜0.88
    domain_norm = math.log1p(domain_raw_score) / math.log1p(8)   # 0〜0.88

    # 基本スコア（intent 60% + domain 30%）
    base = intent_norm * 0.60 + domain_norm * 0.30

    # 両方マッチボーナス
    both_bonus = 0.08 if (intent_raw_score > 0 and domain_raw_score > 0) else 0.0

    # 文長ボーナス（10文字以上で +0.03、30文字以上で +0.05）
    length_bonus = 0.0
    if text_length >= 10:
        length_bonus = 0.03
    if text_length >= 30:
        length_bonus = 0.05

    score = base + both_bonus + length_bonus
    return round(min(max(score, 0.15), 0.92), 3)


def score(item: dict) -> float:
    """後方互換API（engine/main.py から呼ばれる）"""
    # classifier v1 の {'intent', 'domain'} 形式に対応
    intent = item.get("intent", "INF")
    domain = item.get("domain", "SPEC")
    text   = item.get("text", "")

    # raw_score が item に含まれている場合は使用
    intent_raw = item.get("intent_raw_score", 1.0 if intent != "INF" else 0.0)
    domain_raw = item.get("domain_raw_score", 1.0 if domain not in ("SPEC", "GENERAL") else 0.0)

    return calc_confidence(
        text=text,
        intent_raw_score=intent_raw,
        domain_raw_score=domain_raw,
        text_length=len(text),
        intent_code=intent,
    )


def get_confidence_label(score: float) -> str:
    for (lo, hi), label in CONFIDENCE_LABELS.items():
        if lo <= score < hi:
            return label
    return "very_high"


def needs_ai_assist(confidence: float) -> bool:
    return confidence < AI_ASSIST_THRESHOLD


# 自己テスト
if __name__ == "__main__":
    cases = [
        ("INF", "SPEC",   "", 0.0, 0.0, 5),
        ("BUG", "AUTH",   "ログインエラーが発生", 3.0, 2.0, 18),
        ("REQ", "UI",     "検索機能を追加してほしいです", 2.0, 1.0, 16),
        ("BUG", "INFRA",  "Dockerが起動しない", 4.0, 3.0, 10),
        ("QST", "AUTH",   "パスワードを教えてください", 2.0, 1.0, 13),
    ]
    for intent, domain, text, ir, dr, tl in cases:
        s = calc_confidence(text, ir, dr, tl, intent)
        label = get_confidence_label(s)
        print(f"{intent:^6} {domain:^8} score={s:.3f} ({label})")
