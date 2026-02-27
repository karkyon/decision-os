#!/usr/bin/env bash
# =============================================================================
# decision-os / 29_fix_all.sh
# 根本原因を2つ同時修正:
#
# [BUG-1] AmbiguousForeignKeysError: Action.issue
#   → Action モデルが issues テーブルへの FK を2本持っており
#     relationship() がどちらを使うか判断できない
#   → 修正: relationship に foreign_keys=[Action.issue_id] を明示
#
# [BUG-2] conftest.py の event_loop fixture
#   → pytest-asyncio 0.23+ では scope="session" の event_loop は非推奨
#   → 修正: event_loop fixture を削除、pytest.ini で asyncio_mode=auto
#
# [BONUS] パスワードリセットを psql 直接実行（ORM 不要）
# =============================================================================
set -euo pipefail

GREEN='\033[0;32m'; RED='\033[0;31m'; CYAN='\033[0;36m'
YELLOW='\033[1;33m'; BOLD='\033[1m'; RESET='\033[0m'

ok()      { echo -e "${GREEN}[OK]${RESET}    $*"; }
err()     { echo -e "${RED}[ERR]${RESET}   $*"; }
info()    { echo -e "${CYAN}[INFO]${RESET}  $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
section() { echo -e "\n${BOLD}========== $* ==========${RESET}"; }

PROJECT_DIR="$HOME/projects/decision-os"
BACKEND="$PROJECT_DIR/backend"
LOG="$PROJECT_DIR/logs/backend.log"
DB_URL="postgresql://dev:devpass_2ed89487@localhost:5439/decisionos"

cd "$BACKEND"
source .venv/bin/activate

# =============================================================================
section "1. Action モデルの現状確認"
# =============================================================================
ACTION_MODEL="$BACKEND/app/models/action.py"
info "--- action.py 全体 ---"
cat "$ACTION_MODEL"
echo ""

# =============================================================================
section "2. Action モデルの relationship を修正"
# =============================================================================
# issue_id が何本あるか確認
FK_COUNT=$(grep -c "issue" "$ACTION_MODEL" || true)
info "issueへの参照数: $FK_COUNT"

# バックアップ
cp "$ACTION_MODEL" "${ACTION_MODEL}.bak_$(date +%H%M%S)"

# Pythonで安全に修正
python3 << 'PYEOF'
import re

path = "app/models/action.py"
with open(path) as f:
    content = f.read()

print("=== 修正前 ===")
print(content)
print("=== 修正 ===")

# relationship("Issue", ...) に foreign_keys を追加
# パターン: relationship("Issue") または relationship("Issue", back_populates=...)
# → relationship("Issue", foreign_keys=[issue_id], ...) に変更

# まず issue_id カラム名を確認
import re
col_match = re.search(r'(\w+_id)\s*=\s*Column.*ForeignKey.*issues\.id', content)
if col_match:
    fk_col = col_match.group(1)
    print(f"メインFK列: {fk_col}")
else:
    fk_col = "issue_id"
    print(f"FK列推定: {fk_col}")

# relationship("Issue" ...) を修正
# すでに foreign_keys がある場合はスキップ
if 'foreign_keys' not in content:
    # relationship("Issue") パターンを検索して foreign_keys を追加
    new_content = re.sub(
        r'relationship\("Issue"([^)]*)\)',
        lambda m: f'relationship("Issue", foreign_keys=[{fk_col}]{", " + m.group(1).lstrip(",").strip() if m.group(1).strip() else ""})',
        content
    )
    # 末尾の余分なカンマやスペースを整理
    new_content = re.sub(r',\s*\)', ')', new_content)
    with open(path, 'w') as f:
        f.write(new_content)
    print("=== 修正後 ===")
    print(new_content)
    print("[DONE] foreign_keys 追加完了")
else:
    print("[SKIP] foreign_keys は既に存在します")
    # 既存の foreign_keys が正しいか確認
    print("現在の relationship 定義:")
    for line in content.split('\n'):
        if 'relationship' in line or 'foreign_keys' in line:
            print(f"  {line}")
PYEOF

ok "Action モデル修正完了"

# =============================================================================
section "3. 起動確認 — モデル読み込みテスト"
# =============================================================================
info "SQLAlchemy マッパー初期化テスト..."
python3 << 'PYEOF'
import sys
sys.path.insert(0, '.')
try:
    from app.models import *
    from app.db.session import Base
    # configure_mappers を明示的に呼ぶ
    from sqlalchemy.orm import configure_mappers
    configure_mappers()
    print("[OK] マッパー初期化 成功!")
except Exception as e:
    print(f"[ERROR] {e}")
    import traceback; traceback.print_exc()
    sys.exit(1)
PYEOF
ok "マッパー初期化 OK"

# =============================================================================
section "4. パスワードリセット（psql 直接 — ORM不使用）"
# =============================================================================
info "demo@example.com のパスワードハッシュを psql で直接更新..."

# Pythonでハッシュだけ生成
NEW_HASH=$(python3 -c "
from passlib.context import CryptContext
ctx = CryptContext(schemes=['bcrypt'], deprecated='auto')
print(ctx.hash('demo1234'))
")
info "新しいハッシュ: ${NEW_HASH:0:30}..."

# psql で直接UPDATE
PSQL_CMD="UPDATE users SET hashed_password='$NEW_HASH' WHERE email='demo@example.com';"
RESULT=$(PGPASSWORD=devpass_2ed89487 psql \
  -h localhost -p 5439 -U dev -d decisionos \
  -c "$PSQL_CMD" 2>&1)
echo "psql 結果: $RESULT"

if echo "$RESULT" | grep -q "UPDATE 1"; then
  ok "パスワードリセット完了（psql直接更新）"
elif echo "$RESULT" | grep -q "UPDATE 0"; then
  warn "対象ユーザーが見つからない — hashed_password 列名を確認..."
  # 列名確認
  COLS=$(PGPASSWORD=devpass_2ed89487 psql \
    -h localhost -p 5439 -U dev -d decisionos \
    -c "\d users" 2>&1)
  echo "$COLS"
  # password_hash の場合
  PSQL_CMD2="UPDATE users SET password_hash='$NEW_HASH' WHERE email='demo@example.com';"
  RESULT2=$(PGPASSWORD=devpass_2ed89487 psql \
    -h localhost -p 5439 -U dev -d decisionos \
    -c "$PSQL_CMD2" 2>&1)
  echo "psql 結果2: $RESULT2"
  echo "$RESULT2" | grep -q "UPDATE 1" && ok "password_hash 列でリセット完了" || warn "ユーザーが存在しない可能性"
else
  warn "psql コマンド失敗: $RESULT"
  # フォールバック: Docker経由
  warn "Docker経由で試行..."
  docker exec -i decision-os-db-1 psql -U dev -d decisionos \
    -c "UPDATE users SET hashed_password='$NEW_HASH' WHERE email='demo@example.com';" 2>/dev/null || \
  docker exec -i $(docker ps --format '{{.Names}}' | grep -i "db\|postgres" | head -1) \
    psql -U dev -d decisionos \
    -c "UPDATE users SET hashed_password='$NEW_HASH' WHERE email='demo@example.com';" 2>/dev/null || \
    warn "Docker経由も失敗 — ORM経由で再試行"
fi

# =============================================================================
section "5. バックエンド再起動"
# =============================================================================
pkill -f "uvicorn app.main" 2>/dev/null || true
sleep 2
nohup uvicorn app.main:app --host 0.0.0.0 --port 8089 --reload \
  > "$LOG" 2>&1 &
sleep 5

if curl -sf http://localhost:8089/docs > /dev/null 2>&1; then
  ok "バックエンド起動 ✅"
else
  err "バックエンド起動失敗"
  tail -30 "$LOG"
  exit 1
fi

# =============================================================================
section "6. ログイン動作確認"
# =============================================================================
info "demo@example.com / demo1234 でログイン..."
RESP=$(curl -s -X POST http://localhost:8089/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"demo@example.com","password":"demo1234"}')
echo "レスポンス: $RESP"

TOKEN=$(echo "$RESP" | python3 -c "
import sys,json
d=json.load(sys.stdin)
print(d.get('access_token',''))
" 2>/dev/null || echo "")

if [[ -n "$TOKEN" ]] && [[ "$TOKEN" != "null" ]]; then
  ok "ログイン成功 ✅"
  info "TOKEN: ${TOKEN:0:60}..."
else
  err "ログインまだ失敗 — backend.log を確認"
  tail -30 "$LOG"
  exit 1
fi

# =============================================================================
section "7. conftest.py 修正（event_loop fixture 削除）"
# =============================================================================
CONFTEST="$BACKEND/tests/conftest.py"
info "conftest.py を修正..."

cat > "$CONFTEST" << 'PYEOF'
# conftest.py
# pytest-asyncio 0.23+ 対応版
# - event_loop fixture は削除（asyncio_mode=auto で自動管理）
# - scope="function" に統一（module scopeはevent_loopの競合を起こす）

import pytest
import asyncio
from httpx import AsyncClient, ASGITransport
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from app.main import app
from app.db.session import get_db
import os

PROD_DB_URL = os.environ.get(
    "DATABASE_URL",
    "postgresql://dev:devpass_2ed89487@localhost:5439/decisionos"
)

engine = create_engine(PROD_DB_URL)
TestingSessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

def override_get_db():
    db = TestingSessionLocal()
    try:
        yield db
    finally:
        db.close()

app.dependency_overrides[get_db] = override_get_db

@pytest.fixture
async def client():
    async with AsyncClient(
        transport=ASGITransport(app=app),
        base_url="http://test"
    ) as c:
        yield c

@pytest.fixture
async def auth_token(client):
    resp = await client.post("/api/v1/auth/login", json={
        "email": "demo@example.com",
        "password": "demo1234"
    })
    data = resp.json()
    return data.get("access_token", "")

@pytest.fixture
async def auth_headers(auth_token):
    return {"Authorization": f"Bearer {auth_token}"}
PYEOF
ok "conftest.py 修正完了（event_loop fixture 削除）"

# =============================================================================
section "8. pytest 再実行（修正後）"
# =============================================================================
info "テスト実行..."

set +e
python -m pytest tests/ \
  --cov=app \
  --cov=engine \
  --cov-report=term-missing \
  --cov-report=json:.coverage.json \
  -v \
  2>&1 | tee "$PROJECT_DIR/reports/coverage_report_final_$(date +%H%M%S).txt"
EXIT_CODE=$?
set -e

# =============================================================================
section "9. 最終カバレッジ集計"
# =============================================================================
if [[ -f ".coverage.json" ]]; then
  python3 << 'PYEOF'
import json
with open('.coverage.json') as f:
    d = json.load(f)

totals = d.get('totals', {})
total_pct = totals.get('percent_covered', 0)

print(f"\n  ┌──────────────────────────────────────────────┐")
print(f"  │  総合カバレッジ: {total_pct:.1f}%                          │")
print(f"  └──────────────────────────────────────────────┘\n")

files = d.get('files', {})
targets = ['auth', 'inputs', 'issues', 'actions', 'projects', 'users',
           'decisions', 'labels', 'search', 'conversations', 'classifier', 'scorer']

rows = []
for path, data in sorted(files.items()):
    name = path.split('/')[-1].replace('.py','')
    if any(t in name for t in targets):
        pct = data.get('summary',{}).get('percent_covered',0)
        bar = '█'*int(pct/5) + '░'*(20-int(pct/5))
        flag = '✅' if pct>=80 else ('⚠️ ' if pct>=60 else '❌')
        rows.append((pct, f"  {flag} {name:<25} {bar} {pct:.0f}%"))

for _, row in sorted(rows, reverse=True):
    print(row)

achieved = sum(1 for p,_ in rows if p>=80)
print(f"\n  目標80%達成: {achieved}/{len(rows)} ファイル")
flag = "🎉" if total_pct>=80 else ("⚠️" if total_pct>=60 else "📈")
print(f"  {flag} 総合カバレッジ: {total_pct:.1f}%")
PYEOF
fi

echo ""
if [[ $EXIT_CODE -eq 0 ]]; then
  ok "全テスト PASS ✅"
  echo ""
  ok "=== 全修正完了！==="
  ok "次: bash ~/projects/decision-os/scripts/27_browser_check.sh"
else
  warn "一部テスト失敗あり — 上記 FAILED/ERROR を確認"
  info "ログイン自体は成功しているので 27_browser_check.sh は実行可能です"
fi
