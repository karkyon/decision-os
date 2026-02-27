"""
Classifier v3: DB辞書対応版
- 起動時に intent_keywords テーブルからロード
- 5分ごとにキャッシュ更新（再デプロイ不要）
- フォールバック: DB接続失敗時はインライン辞書を使用
"""
import re
import os
import time
import logging
from typing import Tuple

logger = logging.getLogger(__name__)

# ── キャッシュ ───────────────────────────────────────────────────────────────
_cache: dict = {}
_cache_time: float = 0.0
CACHE_TTL = 300  # 5分

# Intent 優先順位（同スコア時に上位を選択）
INTENT_PRIORITY = ["BUG", "TSK", "REQ", "IMP", "QST", "FBK", "MIS", "INF"]

# ── フォールバック辞書（DB接続失敗時） ──────────────────────────────────────
FALLBACK_DICT = {
    "BUG": {"keywords": [
        "エラー","error","Error","例外","動かない","起動しない","落ちる","クラッシュ",
        "フリーズ","失敗","できない","バグ","不具合","障害","接続できない","タイムアウト",
        "表示されない","真っ白","保存できない","保存されない","なにも起きない","何も起きない",
        "切れる","切れた","切れることがある","動かなくなった","500","404",
    ], "patterns": [
        r"エラー(?:が|を|に|で)",
        r"(?:動か|起動し|ログインでき|接続でき)(?:ない|ません|なかった)",
        r"(?:なにも|何も)(?:起き|変わら)(?:ない|ません)",
        r"(?:切れ|落ち)(?:ることがある|てしまう)",
    ]},
    "TSK": {"keywords": [
        "してください","お願いします","やってください","対応してください","実施してください",
    ], "patterns": []},
    "REQ": {"keywords": [
        "してほしい","追加","実装","対応","機能","要望","ほしい","欲しい","希望",
        "助かります","いただけると助かります","いただけると幸いです",
        "できたらいいな","あれば嬉しい","いいなと思いまして",
    ], "patterns": [
        r"(?:いただけると|できれば)(?:助かり|幸い|嬉し)",
        r"(?:できたら|あれば|あったら)(?:いい|嬉し|助かり)",
    ]},
    "IMP": {"keywords": [
        "使いづらい","使いにくい","わかりにくい","遅い","重い","改善",
        "重くなった","重くなっている","遅くなった","遅くなっている",
        "前の方が","前のUIの方が","気がします","なんか重い","なんか遅い",
    ], "patterns": [
        r"(?:重く|遅く|使いにくく)な(?:った|っている)",
        r"前(?:の|より)(?:.*?)(?:方が|ほうが)",
    ]},
    "QST": {"keywords": [
        "ですか","でしょうか","？","?","どう","どの","何","いつ","なぜ","教えて",
    ], "patterns": []},
    "FBK": {"keywords": [
        "便利","いい","良い","使いやすい","ありがとう","ありがとうございます",
        "すばらしい","最高","満足","重宝",
    ], "patterns": []},
    "MIS": {"keywords": [
        "違う","そうではない","誤解","そういう意味ではない","違う挙動",
        "想定と違う","期待と違う","思ってたのと違う","挙動が違う","認識のずれ",
    ], "patterns": [
        r"(?:思って|思ってた|期待して)(?:た|いた)(?:の|もの)?と違",
        r"(?:挙動|動作|仕様)が違",
    ]},
    "INF": {"keywords": [], "patterns": []},
}


def _load_from_db() -> dict:
    """DBから辞書をロードする"""
    try:
        import psycopg2
        from urllib.parse import urlparse

        db_url = os.environ.get("DATABASE_URL", "")
        if not db_url:
            # .env から読み込み
            env_path = os.path.expanduser("~/projects/decision-os/.env")
            if os.path.exists(env_path):
                with open(env_path) as f:
                    for line in f:
                        if line.startswith("DATABASE_URL="):
                            db_url = line.split("=", 1)[1].strip()
                            break

        if not db_url:
            return {}

        u = urlparse(db_url)
        conn = psycopg2.connect(
            host=u.hostname, port=u.port or 5432,
            dbname=u.path.lstrip("/"),
            user=u.username, password=u.password,
            connect_timeout=2,
        )
        cur = conn.cursor()
        cur.execute("""
            SELECT intent, keyword, match_type, weight
            FROM intent_keywords
            WHERE enabled = true
            ORDER BY intent, weight DESC
        """)
        rows = cur.fetchall()
        conn.close()

        result: dict = {}
        for intent, keyword, match_type, weight in rows:
            if intent not in result:
                result[intent] = {"keywords": [], "patterns": [], "weights": {}}
            if match_type == "regex":
                result[intent]["patterns"].append(keyword)
                result[intent]["weights"][keyword] = weight
            else:
                result[intent]["keywords"].append(keyword)
                result[intent]["weights"][keyword] = weight

        logger.debug(f"DB辞書ロード完了: {sum(len(v['keywords'])+len(v['patterns']) for v in result.values())} 件")
        return result

    except Exception as e:
        logger.warning(f"DB辞書ロード失敗（フォールバック使用）: {e}")
        return {}


def _get_intent_dict() -> dict:
    """キャッシュ付き辞書取得（5分TTL）"""
    global _cache, _cache_time
    now = time.time()
    if _cache and (now - _cache_time) < CACHE_TTL:
        return _cache

    db_dict = _load_from_db()
    if db_dict:
        _cache = db_dict
        _cache_time = now
        return _cache

    # フォールバック
    logger.warning("フォールバック辞書を使用")
    return FALLBACK_DICT


def _get_domain_dict() -> dict:
    """Domain辞書（JSONファイルから読み込み）"""
    import json
    from pathlib import Path
    dict_path = Path(__file__).parent / "dictionary" / "domain.json"
    try:
        with open(dict_path, encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return {}


def classify_intent(text: str) -> Tuple[str, float]:
    """
    テキストのIntentを分類する

    Returns
    -------
    (intent_code, score)
    """
    d = _get_intent_dict()
    scores: dict[str, float] = {intent: 0.0 for intent in INTENT_PRIORITY}

    for intent in INTENT_PRIORITY:
        if intent not in d:
            continue
        entry = d[intent]
        weights = entry.get("weights", {})

        # キーワードマッチ
        for kw in entry.get("keywords", []):
            if kw in text:
                w = weights.get(kw, 1.0)
                scores[intent] += w

        # 正規表現マッチ（重み2倍）
        for pat in entry.get("patterns", []):
            try:
                if re.search(pat, text):
                    w = weights.get(pat, 2.0)
                    scores[intent] += w
            except re.error:
                pass

    # 最高スコアのIntentを選択（同スコア時はPRIORITY順）
    best_score = 0.0
    best_intent = "INF"
    for intent in INTENT_PRIORITY:
        if scores[intent] > best_score:
            best_score = scores[intent]
            best_intent = intent

    return best_intent, best_score


def classify_domain(text: str) -> Tuple[str, float]:
    """テキストのDomainを分類する"""
    d = _get_domain_dict()
    DOMAIN_PRIORITY = ["AUTH", "API", "DB", "UI", "PERF", "SEC", "OPS", "INFRA", "SPEC"]

    scores: dict[str, float] = {}
    for domain in DOMAIN_PRIORITY:
        scores[domain] = 0.0
        if domain not in d:
            continue
        entry = d[domain]
        for kw in entry.get("keywords", []):
            if kw in text:
                scores[domain] += 1.0
        for pat in entry.get("patterns", []):
            try:
                if re.search(pat, text):
                    scores[domain] += 2.0
            except re.error:
                pass

    best_score = 0.0
    best_domain = "SPEC"
    for domain in DOMAIN_PRIORITY:
        if scores.get(domain, 0.0) > best_score:
            best_score = scores[domain]
            best_domain = domain

    return best_domain, best_score


def invalidate_cache():
    """キャッシュを強制クリア（辞書更新後に呼ぶ）"""
    global _cache, _cache_time
    _cache = {}
    _cache_time = 0.0
    logger.info("classifier キャッシュをクリアしました")


if __name__ == "__main__":
    cases = [
        ("ログインするとエラーが出て進めません", "BUG"),
        ("検索機能を追加してほしいです",         "REQ"),
        ("最近重くなった気がします",             "IMP"),
        ("パスワードのリセット方法を教えてください", "QST"),
        ("思ってたのと違う挙動をしています",     "MIS"),
    ]
    for text, expected in cases:
        result, score = classify_intent(text)
        mark = "✅" if result == expected else "❌"
        print(f"{mark} [{result}] score={score:.1f}  {text}")
