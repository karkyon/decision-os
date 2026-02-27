#!/bin/bash
# 27_patch3.sh — conversation.body カラム追加 + decisions ISE 修正
set -euo pipefail
BASE_URL="http://localhost:8089/api/v1"
PASS=0; FAIL=0; WARN=0

log_ok()   { echo "[OK]    $*"; PASS=$((PASS+1)); }
log_fail() { echo "[FAIL]  $*"; FAIL=$((FAIL+1)); }
log_warn() { echo "[WARN]  $*"; WARN=$((WARN+1)); }
log_info() { echo "[INFO]  $*"; }

cd ~/projects/decision-os/backend
source .venv/bin/activate 2>/dev/null || true

# ===== 1. Conversation モデルに body カラムを追加 =====
echo "========== 1. Conversation モデル修正 =========="
CONV_MODEL=~/projects/decision-os/backend/app/models/conversation.py
log_info "--- 現状 ---"
cat "$CONV_MODEL"

cp "$CONV_MODEL" "${CONV_MODEL}.bak_$(date +%H%M%S)"

# body カラムが存在しない場合は追加
if grep -q "body" "$CONV_MODEL"; then
  log_info "body カラムは既に存在します（定義確認）"
  grep -n "body" "$CONV_MODEL"
else
  log_info "body カラムを追加します..."
  # issue_id の行の後に body カラムを追加
  python3 -c "
content = open('$CONV_MODEL').read()
# body カラムを issue_id の後に挿入
old = '    issue_id = Column'
new_line = '    body = Column(Text, nullable=False, default=\"\")\n    '
if 'body' not in content:
    content = content.replace('    issue_id = Column', '    body = Column(Text, nullable=False, default=\"\")\n    issue_id = Column', 1)
    open('$CONV_MODEL', 'w').write(content)
    print('追加完了')
else:
    print('既に存在')
"
fi

echo ""
log_info "--- 修正後 ---"
cat "$CONV_MODEL"

# ===== 2. マイグレーション（conversations テーブルに body カラム追加） =====
echo ""
echo "========== 2. DB マイグレーション (conversations.body) =========="
log_info "現在の conversations テーブル構造確認..."
python3 -c "
import subprocess, sys
result = subprocess.run(
    ['psql', '-U', 'postgres', '-d', 'decisionos', '-c',
     '\d conversations'],
    capture_output=True, text=True
)
print(result.stdout or result.stderr)
" 2>/dev/null || \
psql -U postgres -d decisionos -c "\d conversations" 2>/dev/null || \
python3 -c "
import os, sys
sys.path.insert(0, '.')
from app.db.session import engine
from sqlalchemy import text, inspect
insp = inspect(engine)
cols = insp.get_columns('conversations')
print('columns:', [c['name'] for c in cols])
"

log_info "body カラムが存在しない場合は ALTER TABLE で追加..."
python3 -c "
import sys; sys.path.insert(0, '.')
from app.db.session import engine
from sqlalchemy import text, inspect

insp = inspect(engine)
cols = [c['name'] for c in insp.get_columns('conversations')]
print('現在のカラム:', cols)

if 'body' not in cols:
    with engine.begin() as conn:
        conn.execute(text('ALTER TABLE conversations ADD COLUMN body TEXT NOT NULL DEFAULT \'\''))
    print('[OK] body カラムを追加しました')
else:
    print('[SKIP] body カラムは既に存在します')
"

# ===== 3. モデル初期化テスト =====
echo ""
echo "========== 3. マッパー初期化テスト =========="
python3 -c "
import sys; sys.path.insert(0, '.')
try:
    from sqlalchemy.orm import configure_mappers
    import app.models
    configure_mappers()
    print('[OK] マッパー初期化 成功')
except Exception as e:
    print('[ERROR]', e)
    import traceback; traceback.print_exc()
"

# ===== 4. decisions ISE 調査 =====
echo ""
echo "========== 4. decisions ISE 調査 =========="
DECISIONS_PY=~/projects/decision-os/backend/app/api/v1/routers/decisions.py
log_info "--- decisions.py POST ハンドラー ---"
grep -A 40 "def create_decision\|@router.post" "$DECISIONS_PY" | head -60

echo ""
log_info "--- Decision モデル確認 ---"
cat ~/projects/decision-os/backend/app/models/decision.py

echo ""
log_info "--- decisions の DB カラム確認 ---"
python3 -c "
import sys; sys.path.insert(0, '.')
from app.db.session import engine
from sqlalchemy import inspect
insp = inspect(engine)
try:
    cols = [c['name'] for c in insp.get_columns('decisions')]
    print('decisions columns:', cols)
except Exception as e:
    print('ERROR:', e)
"

# ===== 5. backend 再起動 =====
echo ""
echo "========== 5. バックエンド再起動 =========="
pkill -f "uvicorn app.main" 2>/dev/null || true
sleep 2
LOGFILE=$(find ~/projects/decision-os/logs -name "backend.log" 2>/dev/null | head -1)
[ -z "$LOGFILE" ] && LOGFILE=~/projects/decision-os/logs/backend.log
mkdir -p ~/projects/decision-os/logs
nohup uvicorn app.main:app --host 0.0.0.0 --port 8089 --reload \
  > "$LOGFILE" 2>&1 &
sleep 4
HEALTH=$(curl -s http://localhost:8089/health 2>/dev/null || curl -s http://localhost:8089/api/v1/health 2>/dev/null || echo "")
if echo "$HEALTH" | grep -qi "ok\|healthy\|status"; then
  log_ok "バックエンド再起動成功"
else
  log_warn "ヘルスチェック応答なし（起動中かも）: $HEALTH"
fi

# ===== 6. コメント再テスト =====
echo ""
echo "========== 6. コメント再テスト =========="
LOGIN=$(curl -s -X POST "$BASE_URL/auth/login" \
  -H "Content-Type: application/json" \
  -d '{"email":"demo@example.com","password":"demo1234"}')
TOKEN=$(echo "$LOGIN" | python3 -c "import sys,json; print(json.load(sys.stdin).get('access_token',''))" 2>/dev/null || echo "")
[ -z "$TOKEN" ] && { log_fail "ログイン失敗"; exit 1; }
log_ok "JWT取得成功"

PID=$(curl -s -X POST "$BASE_URL/projects" \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"name":"patch3_'$(date +%s)'","description":"test"}' \
  | python3 -c "import sys,json; print(json.load(sys.stdin).get('id',''))" 2>/dev/null || echo "")
IID=$(curl -s -X POST "$BASE_URL/issues" \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d "{\"project_id\":\"$PID\",\"title\":\"conv test\",\"issue_type\":\"task\",\"status\":\"open\"}" \
  | python3 -c "import sys,json; print(json.load(sys.stdin).get('id',''))" 2>/dev/null || echo "")

CONV_RESP=$(curl -s -w "\nHTTP:%{http_code}" -X POST "$BASE_URL/conversations" \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d "{\"issue_id\":\"$IID\",\"body\":\"テストコメントです\"}")
HTTP=$(echo "$CONV_RESP" | grep "HTTP:" | cut -d: -f2)
BODY=$(echo "$CONV_RESP" | grep -v "HTTP:")
if [ "$HTTP" = "201" ] || [ "$HTTP" = "200" ]; then
  log_ok "コメント投稿成功 ✅ HTTP $HTTP"
else
  log_fail "コメント投稿失敗 HTTP $HTTP — $BODY"
fi

# ===== 7. 決定ログ再テスト（正しいフィールドで） =====
echo ""
echo "========== 7. 決定ログ再テスト =========="
DEC_RESP=$(curl -s -w "\nHTTP:%{http_code}" -X POST "$BASE_URL/decisions" \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d "{\"project_id\":\"$PID\",\"decision_text\":\"テスト決定\",\"reason\":\"テスト理由\",\"related_issue_id\":\"$IID\"}")
HTTP=$(echo "$DEC_RESP" | grep "HTTP:" | cut -d: -f2)
BODY=$(echo "$DEC_RESP" | grep -v "HTTP:")
if [ "$HTTP" = "200" ] || [ "$HTTP" = "201" ]; then
  log_ok "決定ログ作成成功 ✅ HTTP $HTTP"
else
  log_warn "決定ログ失敗 HTTP $HTTP — $BODY"
  log_info "--- decisions.py の create ハンドラー全体 ---"
  cat "$DECISIONS_PY"
fi

# ===== サマリー =====
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  修正テスト結果"
echo "  ✅ PASS: $PASS"
echo "  ❌ FAIL: $FAIL"
echo "  ⚠️  WARN: $WARN"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if [ $FAIL -eq 0 ] && [ $WARN -eq 0 ]; then
  echo "[OK] 全項目クリア！次: conftest.py 修正 → テストカバレッジ計測"
else
  echo "上記の FAIL/WARN を確認してください"
fi
