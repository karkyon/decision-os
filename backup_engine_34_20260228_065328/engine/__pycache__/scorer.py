"""
Scorer: 信頼度スコアの算出

現状の問題:
- スコアが 0.25〜0.50 に集中し、実用上の意味が薄い
- INF フォールバックに同じスコアが付いてしまい区別できない

改善方針:
- raw_score（キーワードマッチ数）を非線形変換で [0.0, 1.0] に正規化
- Intent と Domain の両方が高スコアなら信頼度ボーナス
- INF フォールバック（raw_score=0）は低スコア (0.15) に固定
- 文字数・マッチ密度も加味
"""
from typing import Tuple


# INF フォールバック時の固定スコア
INF_FALLBACK_SCORE = 0.15

# 信頼度算出の係数
INTENT_WEIGHT = 0.55
DOMAIN_WEIGHT = 0.30
BONUS_WEIGHT  = 0.15


def _normalize_raw_score(raw: float, max_expected: float = 5.0) -> float:
    """
    生スコア (0〜) を [0.0, 1.0] に変換。
    max_expected はスコアが「十分に高い」とみなす上限値。
    シグモイドに近い非線形変換で、1〜3マッチで急激に上がる。
    """
    if raw <= 0:
        return 0.0
    # log変換 + クリップ
    import math
    normalized = math.log(1 + raw) / math.log(1 + max_expected)
    return min(normalized, 1.0)


def calc_confidence(
    text: str,
    intent_code: str,
    intent_raw: float,
    domain_code: str,
    domain_raw: float,
) -> float:
    """
    信頼度スコア [0.0, 1.0] を算出する。

    Parameters
    ----------
    text : str
        元テキスト
    intent_code : str
        分類された Intent コード
    intent_raw : float
        Intent の生スコア（マッチ数ベース）
    domain_code : str
        分類された Domain コード
    domain_raw : float
        Domain の生スコア（マッチ数ベース）

    Returns
    -------
    float
        信頼度スコア [0.0, 1.0]、小数点2桁
    """
    # INF フォールバック（マッチなし）は低スコア固定
    if intent_code == "INF" and intent_raw == 0.0:
        return INF_FALLBACK_SCORE

    intent_score = _normalize_raw_score(intent_raw)
    domain_score = _normalize_raw_score(domain_raw)

    # ボーナス: Intent も Domain も 1マッチ以上あれば加算
    bonus = 0.0
    if intent_raw > 0 and domain_raw > 0:
        bonus = 1.0  # ボーナス枠を満点にして加重

    confidence = (
        INTENT_WEIGHT * intent_score
        + DOMAIN_WEIGHT * domain_score
        + BONUS_WEIGHT  * bonus
    )

    # 文字が極端に短い場合は信頼度を下げる
    if len(text.strip()) < 5:
        confidence *= 0.7

    return round(min(max(confidence, 0.0), 1.0), 2)


# ---------- 旧インターフェース互換（既存コードが score(item) を呼んでいる場合） ----------

def score(item: dict) -> float:
    """
    後方互換性のためのラッパー。
    item = {"text": str, "intent": str, "domain": str,
            "intent_raw": float, "domain_raw": float}
    """
    text        = item.get("text", "")
    intent_code = item.get("intent", "INF")
    domain_code = item.get("domain", "SPEC")
    intent_raw  = item.get("intent_raw", 0.0)
    domain_raw  = item.get("domain_raw", 0.0)

    # 旧コードが raw スコアを持っていない場合の推定
    if intent_raw == 0.0 and intent_code != "INF":
        intent_raw = 1.0  # 最低1マッチとして扱う
    if domain_raw == 0.0 and domain_code not in ("SPEC", "GENERAL"):
        domain_raw = 1.0

    return calc_confidence(text, intent_code, intent_raw, domain_code, domain_raw)


# ---------- スコア帯の意味 ----------
CONFIDENCE_LABELS = {
    (0.00, 0.20): "very_low",   # INFフォールバック・マッチなし
    (0.20, 0.40): "low",        # 1〜2キーワードのみマッチ
    (0.40, 0.65): "medium",     # 複数マッチ・要人間確認
    (0.65, 0.80): "high",       # 信頼できる自動分類
    (0.80, 1.01): "very_high",  # 複数マッチ+ドメイン確定
}


def confidence_label(score_val: float) -> str:
    for (lo, hi), label in CONFIDENCE_LABELS.items():
        if lo <= score_val < hi:
            return label
    return "unknown"


# ---------- テスト ----------

if __name__ == "__main__":
    test_cases = [
        # text, intent, domain, i_raw, d_raw, expected_range
        ("ログインするとエラーが出ます",   "BUG",  "AUTH",  2.0, 2.0, (0.60, 1.0)),
        ("検索機能を追加してほしい",       "REQ",  "UI",    2.5, 1.0, (0.55, 1.0)),
        ("APIが遅い",                      "IMP",  "PERF",  1.5, 2.0, (0.50, 1.0)),
        ("タイムアウトはいくつですか？",   "QST",  "API",   3.0, 1.5, (0.65, 1.0)),
        ("完了しました",                   "INF",  "SPEC",  0.0, 0.0, (0.10, 0.25)),
        ("共有します",                     "INF",  "SPEC",  0.0, 0.0, (0.10, 0.25)),
    ]

    print("=" * 60)
    print("信頼度スコアテスト")
    print("=" * 60)
    ok = fail = 0
    for text, intent, domain, i_raw, d_raw, (lo, hi) in test_cases:
        conf = calc_confidence(text, intent, i_raw, domain, d_raw)
        label = confidence_label(conf)
        in_range = lo <= conf < hi
        status = "✅" if in_range else "❌"
        if in_range:
            ok += 1
        else:
            fail += 1
        print(f"{status} score={conf:.2f} [{label:10s}] {text}")
        if not in_range:
            print(f"   期待範囲: {lo:.2f}〜{hi:.2f}")
    print(f"\n結果: {ok}/{ok+fail} 正解 ({ok/(ok+fail)*100:.0f}%)")
