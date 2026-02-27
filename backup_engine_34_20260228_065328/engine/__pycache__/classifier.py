"""
Classifier: Intent / Domain の分類
- 辞書マッチング（キーワード + 正規表現パターン）
- 複数マッチ時の重み付きスコアリング
- INFへのフォールバックを抑制するロジック
- 信頼度スコアは Scorer が担当

優先順位: BUG > QST > TSK > REQ > IMP > FBK > MIS > INF
"""
import json
import re
from typing import Tuple
from pathlib import Path

DICT_DIR = Path(__file__).parent / "dictionary"

# ---------- Intent 優先順位（低インデックス = 高優先） ----------
INTENT_PRIORITY = ["BUG", "QST", "TSK", "REQ", "IMP", "FBK", "MIS", "INF"]


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


def reload_dicts():
    """辞書キャッシュをリセット（辞書更新後に呼ぶ）"""
    global _intent_dict, _domain_dict
    _intent_dict = None
    _domain_dict = None


# ---------- Intent 分類 ----------

def classify_intent(text: str) -> Tuple[str, float]:
    """
    Intent分類。 (intent_code, raw_score) を返す。
    raw_score はキーワード/パターンのマッチ数ベースの生スコア。
    信頼度変換は scorer.py が担当。

    改善ポイント:
    - キーワードマッチは +1.0
    - パターンマッチは +1.5（より具体的なため高め）
    - 同スコアの場合は優先順位 (INTENT_PRIORITY) で決定
    - スコアが0でも最優先順位で判定（INFへの安易なフォールバック防止）
    """
    d = _get_intent_dict()
    scores = {code: 0.0 for code in d if not code.startswith("_")}

    for code, rules in d.items():
        if code.startswith("_"):
            continue
        for kw in rules.get("keywords", []):
            if kw in text:
                scores[code] += 1.0

        for pat in rules.get("patterns", []):
            try:
                if re.search(pat, text):
                    scores[code] += 1.5
            except re.error:
                pass

    # スコアが全て0の場合: INF を返すが、raw_score=0 で信頼度低と示す
    max_score = max(scores.values())
    if max_score == 0:
        return "INF", 0.0

    # 同スコアの候補が複数ある場合は優先順位で決定
    candidates = [code for code, sc in scores.items() if sc == max_score]
    for priority_code in INTENT_PRIORITY:
        if priority_code in candidates:
            return priority_code, max_score

    # フォールバック（通常ここには来ない）
    best = max(scores, key=lambda c: (scores[c], -INTENT_PRIORITY.index(c) if c in INTENT_PRIORITY else -99))
    return best, scores[best]


# ---------- Domain 分類 ----------

def classify_domain(text: str) -> Tuple[str, float]:
    """
    Domain分類。 (domain_code, raw_score) を返す。

    改善ポイント:
    - キーワードマッチ +1.0
    - パターンマッチ +1.5
    - スコア0の場合は SPEC（仕様・その他）にフォールバック
    """
    d = _get_domain_dict()
    scores = {code: 0.0 for code in d if not code.startswith("_")}

    for code, rules in d.items():
        if code.startswith("_"):
            continue
        for kw in rules.get("keywords", []):
            if kw in text:
                scores[code] += 1.0

        for pat in rules.get("patterns", []):
            try:
                if re.search(pat, text):
                    scores[code] += 1.5
            except re.error:
                pass

    max_score = max(scores.values())
    if max_score == 0:
        return "SPEC", 0.0

    best_code = max(scores, key=scores.get)
    return best_code, max_score


# ---------- 簡易テスト ----------

if __name__ == "__main__":
    test_cases = [
        ("ログインするとエラーが出て進めません", "BUG", None),
        ("検索機能を追加してほしいです", "REQ", None),
        ("ページの読み込みが遅い", "IMP", "PERF"),
        ("APIのタイムアウト時間はどのくらいですか？", "QST", "API"),
        ("デプロイをお願いします", "TSK", "OPS"),
        ("ありがとうございます、助かりました", "FBK", None),
        ("共有させていただきます", "INF", None),
        ("確認しました。完了です", "INF", None),
        ("認証エラーが発生しています", "BUG", "AUTH"),
        ("DBのバックアップはいつ取られますか？", "QST", "DB"),
    ]

    print("=" * 60)
    print("Intent/Domain 分類テスト")
    print("=" * 60)
    ok = fail = 0
    for text, expected_intent, expected_domain in test_cases:
        intent, i_score = classify_intent(text)
        domain, d_score = classify_domain(text)
        intent_ok = intent == expected_intent
        domain_ok = expected_domain is None or domain == expected_domain
        status = "✅" if (intent_ok and domain_ok) else "❌"
        if intent_ok and domain_ok:
            ok += 1
        else:
            fail += 1
        print(f"{status} [{intent}({i_score:.1f}) / {domain}({d_score:.1f})] {text[:40]}")
        if not intent_ok:
            print(f"   Intent期待: {expected_intent} → 実際: {intent}")
        if expected_domain and not domain_ok:
            print(f"   Domain期待: {expected_domain} → 実際: {domain}")
    print(f"\n結果: {ok}/{ok+fail} 正解 ({ok/(ok+fail)*100:.0f}%)")
