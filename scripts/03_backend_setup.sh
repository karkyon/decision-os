#!/usr/bin/env bash
# =============================================================================
# decision-os  /  Step 3: バックエンドセットアップ
# 実行方法: bash 03_backend_setup.sh
# 前提: 02_project_setup.sh が完了済み
# =============================================================================
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'
info()    { echo -e "${CYAN}[INFO]${RESET}  $*"; }
success() { echo -e "${GREEN}[OK]${RESET}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
error()   { echo -e "${RED}[ERROR]${RESET} $*"; exit 1; }
section() { echo -e "\n${BOLD}========== $* ==========${RESET}"; }

# ---------- プロジェクトルートへ移動 ----------
PROJECT_DIR="$HOME/projects/decision-os"
[[ -d "$PROJECT_DIR" ]] || error "プロジェクトが見つかりません: $PROJECT_DIR"
cd "$PROJECT_DIR"
set -a; source .env; set +a

# ---------- 1. requirements.txt の生成 ----------
section "1. requirements.txt の生成"

cat > backend/requirements.txt << 'EOF'
# ===== Web Framework =====
fastapi==0.115.0
uvicorn[standard]==0.30.6

# ===== Database =====
sqlalchemy==2.0.31
alembic==1.13.2
psycopg2-binary==2.9.9

# ===== Cache =====
redis==5.0.8

# ===== Validation =====
pydantic==2.8.2
pydantic-settings==2.4.0

# ===== Auth =====
python-jose[cryptography]==3.3.0
passlib[bcrypt]==1.7.4
python-multipart==0.0.9

# ===== WebSocket =====
websockets==13.0

# ===== Text Processing（分解エンジン用）=====
unicodedata2==15.1.0

# ===== Testing =====
pytest==8.3.2
pytest-asyncio==0.23.8
httpx==0.27.2
pytest-cov==5.0.0

# ===== Lint =====
flake8==7.1.1
EOF

success "backend/requirements.txt を生成しました"

# ---------- 2. Python 仮想環境の作成 ----------
section "2. Python 仮想環境の作成"

cd backend

# pyenv 有効化
export PYENV_ROOT="$HOME/.pyenv"
export PATH="$PYENV_ROOT/bin:$PATH"
eval "$(pyenv init -)"

echo "3.12.3" > .python-version

if [[ -d .venv ]]; then
  success "仮想環境は既に存在します"
else
  python -m venv .venv
  success "仮想環境を作成しました: backend/.venv"
fi

source .venv/bin/activate
pip install --upgrade pip --quiet
pip install -r requirements.txt --quiet
success "依存パッケージをインストールしました"

# ---------- 3. FastAPI メインアプリの生成 ----------
section "3. FastAPI アプリケーションファイルの生成"

# app/core/config.py
cat > app/core/config.py << 'EOF'
from pydantic_settings import BaseSettings

class Settings(BaseSettings):
    database_url: str
    redis_url: str = "redis://localhost:6379/0"
    jwt_secret: str
    jwt_expire_minutes: int = 1440
    debug: bool = False
    backend_host: str = "0.0.0.0"
    backend_port: int = 8089
    ai_provider: str = "none"
    ai_confidence_threshold: float = 0.75

    class Config:
        env_file = "../.env"
        extra = "ignore"

settings = Settings()
EOF

# app/db/session.py
cat > app/db/session.py << 'EOF'
from sqlalchemy import create_engine
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import sessionmaker
from app.core.config import settings

engine = create_engine(settings.database_url)
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
Base = declarative_base()

def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
EOF

# app/main.py
cat > app/main.py << 'EOF'
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from app.core.config import settings

app = FastAPI(
    title="decision-os API",
    version="1.0.0",
    description="開発判断OS - 意思決定管理システム",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["http://localhost:3000", "http://localhost:80"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

@app.get("/health")
def health():
    return {"status": "ok", "version": "1.0.0"}

@app.get("/api/v1/ping")
def ping():
    return {"message": "pong"}
EOF

success "FastAPI アプリケーションファイルを生成しました"

# ---------- 4. Alembic 初期化 ----------
section "4. Alembic（DBマイグレーション）の初期化"

if [[ -f alembic.ini ]]; then
  success "Alembic は既に初期化済みです"
else
  alembic init alembic

  # alembic.ini の DATABASE_URL を環境変数から取得するよう修正
  sed -i 's|sqlalchemy.url = .*|sqlalchemy.url = %(DATABASE_URL)s|' alembic.ini

  # alembic/env.py を修正してモデルを読み込む
  cat > alembic/env.py << 'ENVPY'
from logging.config import fileConfig
from sqlalchemy import engine_from_config, pool
from alembic import context
import os, sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from app.db.session import Base
from app.core.config import settings

config = context.config
config.set_main_option("sqlalchemy.url", settings.database_url)

if config.config_file_name is not None:
    fileConfig(config.config_file_name)

target_metadata = Base.metadata

def run_migrations_offline():
    url = config.get_main_option("sqlalchemy.url")
    context.configure(url=url, target_metadata=target_metadata, literal_binds=True)
    with context.begin_transaction():
        context.run_migrations()

def run_migrations_online():
    connectable = engine_from_config(
        config.get_section(config.config_ini_section, {}),
        prefix="sqlalchemy.",
        poolclass=pool.NullPool,
    )
    with connectable.connect() as connection:
        context.configure(connection=connection, target_metadata=target_metadata)
        with context.begin_transaction():
            context.run_migrations()

if context.is_offline_mode():
    run_migrations_offline()
else:
    run_migrations_online()
ENVPY

  success "Alembic を初期化しました"
fi

# ---------- 5. 分解エンジンの初期ファイル生成 ----------
section "5. 分解エンジン ファイルの生成"

cat > engine/__init__.py << 'EOF'
EOF

cat > engine/normalizer.py << 'EOF'
"""
Normalizer: テキストの前処理・正規化
"""
import unicodedata
import json
import os

# ライブ辞書を読み込む（起動時のみ）
_LIVE_DICT_PATH = os.path.join(os.path.dirname(__file__), "../dictionary/live.json")

def _load_live_dict() -> dict:
    try:
        with open(_LIVE_DICT_PATH, "r", encoding="utf-8") as f:
            return json.load(f)
    except FileNotFoundError:
        return {}

_REPLACE_MAP = {
    "ログイン出来ない": "ログインできない",
    "落ちちゃう": "落ちる",
    "できませんか": "できるか",
    "使えない": "使用できない",
    **_load_live_dict(),
}

def normalize(text: str) -> str:
    """全角半角統一・表記ゆれ補正"""
    text = unicodedata.normalize("NFKC", text)
    for src, dst in _REPLACE_MAP.items():
        text = text.replace(src, dst)
    return text.strip()
EOF

cat > engine/segmenter.py << 'EOF'
"""
Segmenter: テキストを意味単位に分解する
"""
import re

CONJUNCTIONS = [
    "しかし", "ただし", "また", "なお", "一方",
    "ちなみに", "さらに", "加えて", "それから",
]

def segment(text: str) -> list[str]:
    """テキストを文単位に分解する"""
    lines = text.split("\n")
    results = []
    for line in lines:
        # 句点・感嘆符・疑問符で分割
        parts = re.split(r"[。！？!?]", line)
        for part in parts:
            part = part.strip()
            if not part:
                continue
            # 接続詞での分割
            split_done = False
            for conj in CONJUNCTIONS:
                if conj in part and not part.startswith(conj):
                    idx = part.index(conj)
                    before = part[:idx].strip()
                    after = part[idx:].strip()
                    if before:
                        results.append(before)
                    if after:
                        results.append(after)
                    split_done = True
                    break
            if not split_done:
                results.append(part)
    return [r for r in results if len(r) > 1]
EOF

cat > engine/classifier.py << 'EOF'
"""
Classifier: Intent / Domain / Semantic の3軸分類
"""
import json, os

# ----- Intent キーワード辞書 -----
INTENT_KEYWORDS = {
    "BUG":  ["エラー", "落ちる", "動かない", "失敗", "バグ", "不具合",
             "できない", "壊れ", "おかしい", "異常", "エラーが出"],
    "TSK":  ["してください", "お願いします", "やってください", "対応してください"],
    "REQ":  ["してほしい", "追加", "改善", "できますか", "希望", "要望",
             "ほしい", "欲しい", "対応可能", "実装", "機能"],
    "IMP":  ["使いづらい", "分かりにくい", "遅い", "重い", "改善",
             "もっと", "せめて", "直して"],
    "QST":  ["？", "?", "でしょうか", "ですか", "教えて", "いつ", "どうすれば"],
    "FBK":  ["便利", "いい", "良い", "助かる", "使いやすい", "ありがとう"],
    "MIS":  ["違う", "そうではなく", "誤解", "そういう意味ではない"],
    "INF":  [],  # デフォルト
}

# ----- Domain キーワード辞書 -----
DOMAIN_KEYWORDS = {
    "UI":       ["画面", "ボタン", "UI", "デザイン", "レイアウト", "表示"],
    "BACKEND":  ["API", "サーバー", "エンドポイント", "レスポンス"],
    "DATABASE": ["DB", "SQL", "データベース", "データ", "保存", "検索"],
    "AUTH":     ["ログイン", "認証", "権限", "パスワード", "アカウント"],
    "PERF":     ["遅い", "重い", "パフォーマンス", "速度", "タイムアウト"],
    "INFRA":    ["サーバー", "CPU", "メモリ", "Docker", "デプロイ", "インフラ"],
    "OPS":      ["運用", "設定", "環境", "バックアップ"],
}

def detect_intent(text: str) -> str:
    for intent, keywords in INTENT_KEYWORDS.items():
        if any(kw in text for kw in keywords):
            return intent
    return "INF"

def detect_domain(text: str) -> str:
    for domain, keywords in DOMAIN_KEYWORDS.items():
        if any(kw in text for kw in keywords):
            return domain
    return "GENERAL"

def classify(text: str) -> dict:
    return {
        "intent": detect_intent(text),
        "domain": detect_domain(text),
    }
EOF

cat > engine/scorer.py << 'EOF'
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
EOF

cat > engine/main.py << 'EOF'
"""
Engine Main: 分解エンジンのオーケストレーター
"""
from engine.normalizer import normalize
from engine.segmenter  import segment
from engine.classifier import classify
from engine.scorer     import score

def analyze(text: str) -> list[dict]:
    """テキストを受け取り、分解・分類結果のリストを返す"""
    text = normalize(text)
    sentences = segment(text)

    items = []
    for i, sent in enumerate(sentences):
        result = classify(sent)
        result["text"] = sent
        result["position"] = i
        result["confidence"] = score(result)
        items.append(result)

    return items

if __name__ == "__main__":
    sample = input("テキストを入力してください > ")
    from pprint import pprint
    pprint(analyze(sample))
EOF

success "分解エンジンファイルを生成しました"

# ---------- 6. 辞書ファイルの初期化 ----------
section "6. 辞書ファイルの初期化"

echo '{}' > ../dictionary/live.json

cat > ../dictionary/common/intent_keywords.yml << 'EOF'
# Intent キーワード辞書（共通）
# format: term / intent_hint / priority(1-5)
entries:
  - { term: "エラー",       intent_hint: "BUG", priority: 5 }
  - { term: "動かない",     intent_hint: "BUG", priority: 5 }
  - { term: "落ちる",       intent_hint: "BUG", priority: 5 }
  - { term: "不具合",       intent_hint: "BUG", priority: 5 }
  - { term: "してほしい",   intent_hint: "REQ", priority: 4 }
  - { term: "追加",         intent_hint: "REQ", priority: 3 }
  - { term: "改善",         intent_hint: "IMP", priority: 3 }
  - { term: "使いづらい",   intent_hint: "IMP", priority: 4 }
  - { term: "？",           intent_hint: "QST", priority: 4 }
  - { term: "でしょうか",   intent_hint: "QST", priority: 4 }
EOF

cat > ../dictionary/dev/domain_terms.yml << 'EOF'
# Domain キーワード辞書（システム開発）
entries:
  - { term: "API",         domain: "BACKEND" }
  - { term: "画面",        domain: "UI" }
  - { term: "DB",          domain: "DATABASE" }
  - { term: "SQL",         domain: "DATABASE" }
  - { term: "ログイン",    domain: "AUTH" }
  - { term: "デプロイ",    domain: "INFRA" }
  - { term: "レイテンシ",  domain: "PERF" }
EOF

success "辞書ファイルを初期化しました"

# ---------- 7. テストファイルの生成 ----------
section "7. テストファイルの生成"

cat > tests/__init__.py << 'EOF'
EOF

cat > tests/test_health.py << 'EOF'
from fastapi.testclient import TestClient
from app.main import app

client = TestClient(app)

def test_health():
    res = client.get("/health")
    assert res.status_code == 200
    assert res.json()["status"] == "ok"

def test_ping():
    res = client.get("/api/v1/ping")
    assert res.status_code == 200
EOF

cat > tests/test_engine.py << 'EOF'
import sys, os
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from engine.main import analyze

def test_analyze_bug():
    result = analyze("ログインするとエラーが出て使えない")
    assert len(result) > 0
    intents = [r["intent"] for r in result]
    assert "BUG" in intents

def test_analyze_request():
    result = analyze("CSV出力機能を追加してほしい")
    assert len(result) > 0
    assert result[0]["intent"] == "REQ"

def test_analyze_question():
    result = analyze("この機能はいつ対応できますか？")
    assert len(result) > 0
    assert result[0]["intent"] == "QST"

def test_confidence_range():
    result = analyze("改善してほしい")
    for item in result:
        assert 0.0 <= item["confidence"] <= 1.0
EOF

success "テストファイルを生成しました"

# ---------- 8. 動作確認 ----------
section "8. エンジン動作確認"

cd "$PROJECT_DIR/backend"
source .venv/bin/activate

info "エンジンテストを実行中..."
python -m pytest tests/test_engine.py -v --tb=short 2>&1 | tail -20
success "エンジンテスト完了"

# ---------- 完了メッセージ ----------
cd "$PROJECT_DIR"
section "Step 3 完了"
echo -e "${GREEN}"
echo "  ✔ requirements.txt"
echo "  ✔ Python 仮想環境（backend/.venv）"
echo "  ✔ FastAPI アプリ（app/main.py, config.py, session.py）"
echo "  ✔ Alembic 初期化"
echo "  ✔ 分解エンジン（engine/*.py）"
echo "  ✔ 辞書ファイル（dictionary/）"
echo "  ✔ テストファイル（tests/）"
echo -e "${RESET}"
echo -e "${YELLOW}【次のアクション】${RESET}"
echo -e "  bash ${BOLD}04_frontend_setup.sh${RESET}"
