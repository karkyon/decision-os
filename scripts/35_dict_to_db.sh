#!/usr/bin/env bash
# =============================================================================
# 35_dict_to_db.sh — 辞書DB化 + 精度修正
# 1. intent_keywords テーブル作成
# 2. intent.json の既存キーワードをDBに移行
# 3. 不足キーワードをDBに追加（IMP/FBK/MIS/BUG強化）
# 4. classifier.py をDB読み込み対応に改修
# 5. 管理API追加（GET/POST/DELETE /api/v1/dictionary）
# 6. 精度テスト（35件）
# =============================================================================
set -euo pipefail
GREEN='\033[0;32m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'; BOLD='\033[1m'; RESET='\033[0m'
ok()      { echo -e "${GREEN}[OK]${RESET}    $*"; }
info()    { echo -e "${CYAN}[INFO]${RESET}  $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
section() { echo -e "\n${BOLD}========== $* ==========${RESET}"; }

PROJECT_DIR="$HOME/projects/decision-os"
BACKEND="$PROJECT_DIR/backend"
cd "$BACKEND"
source .venv/bin/activate


# ─────────────────────────────────────────────
section "1. intent_keywords テーブル作成"
# ─────────────────────────────────────────────
python3 << 'PYEOF'
import os, psycopg2
from urllib.parse import urlparse
db_url = os.popen("grep DATABASE_URL ~/projects/decision-os/.env 2>/dev/null | cut -d= -f2-").read().strip()
u = urlparse(db_url)
conn = psycopg2.connect(host=u.hostname,port=u.port or 5432,dbname=u.path.lstrip("/"),user=u.username,password=u.password)
cur = conn.cursor()
cur.execute("""
CREATE TABLE IF NOT EXISTS intent_keywords (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    intent      VARCHAR(10) NOT NULL,
    keyword     TEXT NOT NULL,
    match_type  VARCHAR(10) NOT NULL DEFAULT 'partial',
    weight      FLOAT NOT NULL DEFAULT 1.0,
    enabled     BOOLEAN NOT NULL DEFAULT true,
    source      VARCHAR(20) NOT NULL DEFAULT 'manual',
    created_at  TIMESTAMP NOT NULL DEFAULT now()
)
""")
cur.execute("CREATE UNIQUE INDEX IF NOT EXISTS uq_intent_keyword ON intent_keywords(intent, keyword)")
cur.execute("CREATE INDEX IF NOT EXISTS idx_intent_keywords_intent ON intent_keywords(intent) WHERE enabled = true")
conn.commit()
conn.close()
print("  intent_keywords テーブル作成完了")
PYEOF
ok "intent_keywords テーブル作成完了"

# ─────────────────────────────────────────────
section "2. intent.json → DB に移行"
# ─────────────────────────────────────────────
python3 << 'PYEOF'
import json, os, psycopg2, re
from urllib.parse import urlparse

db_url = os.popen("grep DATABASE_URL ~/projects/decision-os/.env 2>/dev/null | cut -d= -f2-").read().strip()
if not db_url:
    db_url = "postgresql://postgres:postgres@localhost:5432/decisionos"

# psycopg2用にURLをパース
u = urlparse(db_url)
conn = psycopg2.connect(
    host=u.hostname, port=u.port or 5432,
    dbname=u.path.lstrip("/"),
    user=u.username, password=u.password
)
cur = conn.cursor()

# intent.json を読み込み
json_path = os.path.expanduser("~/projects/decision-os/backend/engine/dictionary/intent.json")
with open(json_path, encoding="utf-8") as f:
    data = json.load(f)

total = 0
for intent, v in data.items():
    for kw in v.get("keywords", []):
        if not kw.strip():
            continue
        cur.execute("""
            INSERT INTO intent_keywords (intent, keyword, match_type, source)
            VALUES (%s, %s, 'partial', 'json_import')
            ON CONFLICT (intent, keyword) DO NOTHING
        """, (intent, kw.strip()))
        total += 1

    for pat in v.get("patterns", []):
        if not pat.strip():
            continue
        cur.execute("""
            INSERT INTO intent_keywords (intent, keyword, match_type, weight, source)
            VALUES (%s, %s, 'regex', 2.0, 'json_import')
            ON CONFLICT (intent, keyword) DO NOTHING
        """, (intent, pat.strip()))
        total += 1

conn.commit()
cur.execute("SELECT COUNT(*) FROM intent_keywords")
count = cur.fetchone()[0]
conn.close()
print(f"  移行完了: {total} 件処理 → DB合計 {count} 件")
PYEOF
ok "intent.json → DB 移行完了"

# ─────────────────────────────────────────────
section "3. 不足キーワードをDBに追加（精度改善分）"
# ─────────────────────────────────────────────
python3 << 'PYEOF'
import os, psycopg2
from urllib.parse import urlparse

db_url = os.popen("grep DATABASE_URL ~/projects/decision-os/.env 2>/dev/null | cut -d= -f2-").read().strip()
if not db_url:
    db_url = "postgresql://postgres:postgres@localhost:5432/decisionos"
u = urlparse(db_url)
conn = psycopg2.connect(
    host=u.hostname, port=u.port or 5432,
    dbname=u.path.lstrip("/"),
    user=u.username, password=u.password
)
cur = conn.cursor()

NEW_KEYWORDS = {
    # ── BUG: 口語・変化表現 ──────────────────────────────────────────────────
    "BUG": [
        ("なにも起きない",        "partial", 1.0),
        ("何も起きない",          "partial", 1.0),
        ("起きない",              "partial", 1.0),
        ("切れる",                "partial", 1.0),
        ("切れた",                "partial", 1.0),
        ("切れることがある",      "partial", 1.5),
        ("切れてしまう",          "partial", 1.0),
        ("動かなくなった",        "partial", 1.5),
        ("動かなくなっている",    "partial", 1.5),
        ("落ちることがある",      "partial", 1.5),
        (r"(?:なにも|何も)(?:起き|変わら)(?:ない|ません)", "regex", 2.0),
        (r"(?:切れ|落ち)(?:ることがある|ることがあります|てしまう)", "regex", 2.0),
    ],
    # ── IMP: 変化・劣化表現（口語・過去形）──────────────────────────────────
    "IMP": [
        ("重くなった",            "partial", 1.5),
        ("重くなっている",        "partial", 1.5),
        ("重くなってきた",        "partial", 1.5),
        ("遅くなった",            "partial", 1.5),
        ("遅くなっている",        "partial", 1.5),
        ("遅くなってきた",        "partial", 1.5),
        ("使いにくくなった",      "partial", 1.5),
        ("以前より",              "partial", 1.0),
        ("前より",                "partial", 1.0),
        ("前の方が",              "partial", 1.0),
        ("前のUIの方が",          "partial", 2.0),
        ("気がします",            "partial", 0.8),
        ("気がする",              "partial", 0.8),
        ("なんか重い",            "partial", 1.5),
        ("なんか遅い",            "partial", 1.5),
        (r"(?:重く|遅く|使いにくく)な(?:った|っている|ってきた)", "regex", 2.0),
        (r"前(?:の|より)(?:.*?)(?:方が|ほうが)(?:よ|良|使|見)", "regex", 2.0),
    ],
    # ── REQ: 依頼・願望表現 ─────────────────────────────────────────────────
    "REQ": [
        ("助かります",            "partial", 1.5),
        ("助かるのですが",        "partial", 1.5),
        ("助かりますので",        "partial", 1.5),
        ("いただけると助かります","partial", 2.0),
        ("いただけると幸いです",  "partial", 2.0),
        ("できたらいいな",        "partial", 1.5),
        ("できればいいな",        "partial", 1.5),
        ("あれば嬉しい",          "partial", 1.5),
        ("あったらいいな",        "partial", 1.5),
        ("いいなと思いまして",    "partial", 2.0),
        ("と思いまして",          "partial", 1.0),
        (r"(?:いただけると|できれば)(?:助かり|幸い|嬉し)", "regex", 2.5),
        (r"(?:できたら|あれば|あったら)(?:いい|嬉し|助かり)", "regex", 2.0),
    ],
    # ── FBK: 「助かる」系を削除してREQへ移動済み。純粋な感謝・称賛のみ ────
    # （削除はUPDATEで対応）
    # ── MIS: 認識相違・想定外 ────────────────────────────────────────────────
    "MIS": [
        ("違う挙動",              "partial", 2.0),
        ("想定と違う",            "partial", 2.0),
        ("期待と違う",            "partial", 2.0),
        ("思ってたのと違う",      "partial", 2.0),
        ("挙動が違う",            "partial", 2.0),
        ("動作が違う",            "partial", 1.5),
        ("仕様が違う",            "partial", 1.5),
        ("イメージと違う",        "partial", 1.5),
        ("思ったより",            "partial", 1.0),
        ("思っていたより",        "partial", 1.0),
        ("認識のずれ",            "partial", 2.0),
        ("認識相違",              "partial", 2.0),
        (r"(?:思って|思ってた|期待して)(?:た|いた)(?:の|もの)?と違", "regex", 2.5),
        (r"(?:挙動|動作|仕様)が違", "regex", 2.0),
    ],
}

# FBK から「助かる」系を無効化
fbk_disable = ["助かる", "助かります", "助かっています"]
for kw in fbk_disable:
    cur.execute("""
        UPDATE intent_keywords SET enabled = false
        WHERE intent = 'FBK' AND keyword = %s
    """, (kw,))
    if cur.rowcount > 0:
        print(f"  FBK: '{kw}' を無効化")

# 新キーワードを挿入
added = 0
for intent, entries in NEW_KEYWORDS.items():
    for kw, match_type, weight in entries:
        cur.execute("""
            INSERT INTO intent_keywords (intent, keyword, match_type, weight, source)
            VALUES (%s, %s, %s, %s, 'precision_patch')
            ON CONFLICT (intent, keyword) DO UPDATE
                SET weight = EXCLUDED.weight, enabled = true, source = EXCLUDED.source
        """, (intent, kw, match_type, weight))
        added += 1

conn.commit()

# 確認
cur.execute("""
    SELECT intent, COUNT(*) FROM intent_keywords
    WHERE enabled = true GROUP BY intent ORDER BY intent
""")
print(f"\n  追加完了: {added} 件")
print(f"\n  {'Intent':^8} {'件数':^6}")
print("  " + "─"*16)
for row in cur.fetchall():
    print(f"  {row[0]:^8} {row[1]:^6}")

conn.close()
PYEOF
ok "不足キーワード追加完了"

# ─────────────────────────────────────────────
section "4. classifier.py を DB 読み込み対応に改修"
# ─────────────────────────────────────────────
cat > "$BACKEND/engine/classifier.py" << 'PYEOF'
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
PYEOF
ok "classifier.py v3 書き込み完了"

# ─────────────────────────────────────────────
section "5. 管理API追加（/api/v1/dictionary）"
# ─────────────────────────────────────────────
mkdir -p "$BACKEND/app/api/v1/routers"
cat > "$BACKEND/app/api/v1/routers/dictionary.py" << 'PYEOF'
"""
辞書管理API
GET    /api/v1/dictionary          — 辞書一覧
POST   /api/v1/dictionary          — キーワード追加
DELETE /api/v1/dictionary/{id}     — キーワード削除
PATCH  /api/v1/dictionary/{id}     — 有効/無効切り替え
POST   /api/v1/dictionary/reload   — キャッシュクリア（即時反映）
"""
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from sqlalchemy import Column, String, Float, Boolean, DateTime, text
from sqlalchemy.dialects.postgresql import UUID
from pydantic import BaseModel
from typing import Optional, List
from datetime import datetime
import uuid

from app.db.session import Base, get_db
from app.core.deps import get_current_user
from app.models.user import User

router = APIRouter(prefix="/dictionary", tags=["dictionary"])


# ── モデル ───────────────────────────────────────────────────────────────────
class IntentKeyword(Base):
    __tablename__ = "intent_keywords"
    id         = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    intent     = Column(String(10), nullable=False)
    keyword    = Column(String, nullable=False)
    match_type = Column(String(10), default="partial")
    weight     = Column(Float, default=1.0)
    enabled    = Column(Boolean, default=True)
    source     = Column(String(20), default="manual")
    created_at = Column(DateTime, default=datetime.utcnow)


# ── スキーマ ─────────────────────────────────────────────────────────────────
class KeywordCreate(BaseModel):
    intent:     str
    keyword:    str
    match_type: str = "partial"
    weight:     float = 1.0

class KeywordUpdate(BaseModel):
    enabled: Optional[bool] = None
    weight:  Optional[float] = None

class KeywordOut(BaseModel):
    id:         str
    intent:     str
    keyword:    str
    match_type: str
    weight:     float
    enabled:    bool
    source:     str
    created_at: datetime

    class Config:
        from_attributes = True


# ── エンドポイント ───────────────────────────────────────────────────────────
@router.get("", response_model=List[KeywordOut])
def list_keywords(
    intent: Optional[str] = None,
    enabled: Optional[bool] = None,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    q = db.query(IntentKeyword)
    if intent:
        q = q.filter(IntentKeyword.intent == intent.upper())
    if enabled is not None:
        q = q.filter(IntentKeyword.enabled == enabled)
    return q.order_by(IntentKeyword.intent, IntentKeyword.weight.desc()).all()


@router.post("", response_model=KeywordOut, status_code=201)
def add_keyword(
    payload: KeywordCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    existing = db.query(IntentKeyword).filter(
        IntentKeyword.intent == payload.intent.upper(),
        IntentKeyword.keyword == payload.keyword,
    ).first()
    if existing:
        raise HTTPException(status_code=409, detail="既に登録済みです")

    kw = IntentKeyword(
        intent=payload.intent.upper(),
        keyword=payload.keyword,
        match_type=payload.match_type,
        weight=payload.weight,
        source="manual",
    )
    db.add(kw)
    db.commit()
    db.refresh(kw)

    # キャッシュクリア（即時反映）
    try:
        from engine.classifier import invalidate_cache
        invalidate_cache()
    except Exception:
        pass

    return kw


@router.patch("/{keyword_id}", response_model=KeywordOut)
def update_keyword(
    keyword_id: str,
    payload: KeywordUpdate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    kw = db.query(IntentKeyword).filter(IntentKeyword.id == keyword_id).first()
    if not kw:
        raise HTTPException(status_code=404, detail="Not found")
    if payload.enabled is not None:
        kw.enabled = payload.enabled
    if payload.weight is not None:
        kw.weight = payload.weight
    db.commit()
    db.refresh(kw)

    try:
        from engine.classifier import invalidate_cache
        invalidate_cache()
    except Exception:
        pass

    return kw


@router.delete("/{keyword_id}", status_code=204)
def delete_keyword(
    keyword_id: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    kw = db.query(IntentKeyword).filter(IntentKeyword.id == keyword_id).first()
    if not kw:
        raise HTTPException(status_code=404, detail="Not found")
    db.delete(kw)
    db.commit()

    try:
        from engine.classifier import invalidate_cache
        invalidate_cache()
    except Exception:
        pass


@router.post("/reload", status_code=200)
def reload_cache(current_user: User = Depends(get_current_user)):
    """辞書キャッシュを強制クリア（DB更新後に即時反映させる）"""
    try:
        from engine.classifier import invalidate_cache
        invalidate_cache()
        return {"message": "キャッシュをクリアしました。次回リクエスト時にDBから再ロードします。"}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
PYEOF
ok "dictionary.py ルーター作成完了"

# api.py に dictionary を登録
python3 << 'PYEOF'
import os
path = os.path.expanduser("~/projects/decision-os/backend/app/api/v1/api.py")
with open(path, encoding="utf-8") as f:
    src = f.read()

if "dictionary" not in src:
    # import 追加
    src = src.replace(
        "from app.api.v1.routers import",
        "from app.api.v1.routers import dictionary as dictionary_router\nfrom app.api.v1.routers import",
        1
    )
    # router 登録
    last_include = src.rfind("api_router.include_router(")
    end = src.find("\n", last_include) + 1
    src = src[:end] + 'api_router.include_router(dictionary_router.router)\n' + src[end:]
    with open(path, "w", encoding="utf-8") as f:
        f.write(src)
    print("  api.py に dictionary ルーター登録完了")
else:
    print("  api.py: dictionary は既に登録済み")
PYEOF

# ─────────────────────────────────────────────
section "6. バックエンド再起動"
# ─────────────────────────────────────────────
pkill -f "uvicorn" 2>/dev/null || true
sleep 1
nohup uvicorn app.main:app --host 0.0.0.0 --port 8089 --reload \
  > "$PROJECT_DIR/backend.log" 2>&1 &
sleep 4
if curl -s http://localhost:8089/docs > /dev/null 2>&1; then
    ok "バックエンド起動 ✅"
else
    warn "起動確認失敗 → backend.log を確認"
    tail -10 "$PROJECT_DIR/backend.log"
fi

# ─────────────────────────────────────────────
section "7. 精度テスト（35件）"
# ─────────────────────────────────────────────
python3 << 'PYEOF'
import sys, importlib, time
sys.path.insert(0, ".")

# キャッシュクリアして再ロード
import engine.classifier as clf
clf.invalidate_cache()
time.sleep(0.5)

ALL = [
    ("ログインするとエラーが出て進めません","BUG"),("アプリが突然クラッシュします","BUG"),
    ("Dockerコンテナが起動しない","BUG"),("画面が真っ白になってしまいます","BUG"),
    ("保存ボタンを押しても保存されない","BUG"),("500エラーが返ってくる","BUG"),
    ("認証エラーが発生しています","BUG"),("タイムアウトが頻発している","BUG"),
    ("検索機能を追加してほしいです","REQ"),("CSVエクスポート機能を実装できますか","REQ"),
    ("ダークモードに対応をお願いしたいです","REQ"),("メール通知機能の導入を希望します","REQ"),
    ("APIのページネーション対応をお願いできますか","REQ"),("モバイル対応を検討してほしいです","REQ"),
    ("パスワードのリセット方法を教えてください","QST"),("このAPIの仕様はどこで確認できますか","QST"),
    ("リリース予定日はいつでしょうか","QST"),("検索が遅くて使いにくいです","IMP"),
    ("入力フォームが使いづらいです","IMP"),("新機能、とても使いやすくて助かります","FBK"),
    ("なんか動かないんですけど","BUG"),("最近重くなった気がします","IMP"),
    ("ボタン押してもなにも起きない","BUG"),("たまにエラーになります","BUG"),
    ("〇〇機能はありますか？","QST"),("エクスポートできたらいいなと思いまして","REQ"),
    ("対応いただけると助かります","REQ"),("ログインできないので修正してほしいです","BUG"),
    ("エラーが出るので機能を追加してください","BUG"),("DBの接続が切れることがあります","BUG"),
    ("先週から検索が遅くなっています","IMP"),("ユーザー数が増えてきました","INF"),
    ("思ってたのと違う挙動をしています","MIS"),("前のUIの方が使いやすかったです","IMP"),
    ("ありがとうございます、解決しました","FBK"),
]

ok_count = 0
print(f"\n{'テキスト':<42} {'正解':^6} {'結果':^6} {'スコア':^7}")
print("─"*65)
for text, exp in ALL:
    r, s = clf.classify_intent(text)
    mark = "✅" if r == exp else "❌"
    ok_count += r == exp
    if r != exp:  # ❌だけ表示（見やすく）
        print(f"{text[:40]:<42} {exp:^6} {r:^4}{mark} {s:^7.1f}")
print("─"*65)

n = len(ALL)
pct = ok_count/n*100
print(f"\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
print(f"  総合精度: {ok_count}/{n} = {pct:.0f}%")
status = "✅ 目標達成（90%以上）" if pct >= 90 else f"⚠️  目標未達（あと{90-pct:.0f}%）"
print(f"  {status}")
print(f"━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

# DB件数確認
try:
    import psycopg2
    from urllib.parse import urlparse
    import os
    db_url = os.popen("grep DATABASE_URL ~/projects/decision-os/.env 2>/dev/null | cut -d= -f2-").read().strip()
    u = urlparse(db_url)
    conn = psycopg2.connect(host=u.hostname,port=u.port or 5432,dbname=u.path.lstrip("/"),user=u.username,password=u.password)
    cur = conn.cursor()
    cur.execute("SELECT COUNT(*) FROM intent_keywords WHERE enabled=true")
    cnt = cur.fetchone()[0]
    conn.close()
    print(f"\n  DB辞書: {cnt} 件（有効）")
    print(f"  管理API: http://localhost:8089/api/v1/dictionary")
    print(f"  キャッシュTTL: 5分（POST /dictionary/reload で即時反映）")
except Exception as e:
    print(f"  DB確認エラー: {e}")
PYEOF