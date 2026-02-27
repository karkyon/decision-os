#!/bin/bash
# 27_patch2.sh — コメントISE修正 + ラベル/決定ログ フィールド修正確認
set -euo pipefail
BASE_URL="http://localhost:8089/api/v1"
PASS=0; FAIL=0; WARN=0

log_ok()   { echo "[OK]    $*"; PASS=$((PASS+1)); }
log_fail() { echo "[FAIL]  $*"; FAIL=$((FAIL+1)); }
log_warn() { echo "[WARN]  $*"; WARN=$((WARN+1)); }
log_info() { echo "[INFO]  $*"; }

cd ~/projects/decision-os/backend
source .venv/bin/activate 2>/dev/null || true

# ===== 0. ログイン =====
echo "========== 0. ログイン =========="
LOGIN=$(curl -s -X POST "$BASE_URL/auth/login" \
  -H "Content-Type: application/json" \
  -d '{"email":"demo@example.com","password":"demo1234"}')
TOKEN=$(echo "$LOGIN" | python3 -c "import sys,json; print(json.load(sys.stdin).get('access_token',''))" 2>/dev/null || echo "")
[ -z "$TOKEN" ] && { echo "[FAIL] ログイン失敗"; exit 1; }
log_ok "JWT取得成功"

PID=$(curl -s -X POST "$BASE_URL/projects" \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"name":"patch2_test_'$(date +%s)'","description":"patch2"}' \
  | python3 -c "import sys,json; print(json.load(sys.stdin).get('id',''))" 2>/dev/null || echo "")

IID=$(curl -s -X POST "$BASE_URL/issues" \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d "{\"project_id\":\"$PID\",\"title\":\"patch2 test\",\"issue_type\":\"task\",\"status\":\"open\"}" \
  | python3 -c "import sys,json; print(json.load(sys.stdin).get('id',''))" 2>/dev/null || echo "")
log_info "PID=$PID / IID=$IID"

# ===== 1. コメント ISE 根本原因調査 =====
echo ""
echo "========== 1. コメント Internal Server Error 調査 =========="

log_info "--- conversations.py 全体確認 ---"
CONV_PY=~/projects/decision-os/backend/app/api/v1/routers/conversations.py
cat "$CONV_PY"

echo ""
log_info "--- conversation スキーマ確認 ---"
cat ~/projects/decision-os/backend/app/schemas/conversation.py 2>/dev/null || true

echo ""
log_info "--- エンジン単体で会話モデルの import テスト ---"
python3 -c "
import sys; sys.path.insert(0,'.')
try:
    from app.models.conversation import Conversation
    print('Conversation model: OK')
    from app.schemas.conversation import ConversationCreate
    print('ConversationCreate schema: OK')
except Exception as e:
    print('ERROR:', e)
    import traceback; traceback.print_exc()
"

echo ""
log_info "--- コメント POST 実行（body フィールド）+ 詳細エラー取得 ---"
CONV_RESP=$(curl -s -w "\nHTTP_STATUS:%{http_code}" -X POST "$BASE_URL/conversations" \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d "{\"issue_id\":\"$IID\",\"body\":\"テストコメントです\"}")
HTTP_STATUS=$(echo "$CONV_RESP" | grep "HTTP_STATUS:" | cut -d: -f2)
BODY=$(echo "$CONV_RESP" | grep -v "HTTP_STATUS:")
log_info "HTTP $HTTP_STATUS: $BODY"

if [ "$HTTP_STATUS" = "200" ] || [ "$HTTP_STATUS" = "201" ]; then
  log_ok "コメント投稿成功！"
else
  log_warn "コメント失敗 HTTP $HTTP_STATUS"
  log_info "--- backend.log から conversations エラーを抽出 ---"
  LOGFILE=$(find ~/projects/decision-os/logs -name "backend.log" 2>/dev/null | head -1)
  [ -z "$LOGFILE" ] && LOGFILE=$(find ~/projects/decision-os -name "backend.log" 2>/dev/null | head -1)
  if [ -n "$LOGFILE" ]; then
    grep -A 5 -i "conversation\|500\|error\|exception" "$LOGFILE" | tail -40 || true
  fi

  # conversations.py の POST ハンドラーのモデル参照を確認
  log_info "--- conversations.py の外部参照モデル確認 ---"
  python3 -c "
import sys; sys.path.insert(0,'.')
try:
    # アプリ全体をインポートしてマッパー確認
    from app.main import app
    print('app import: OK')
    # 直接 conversation ルーターを実行テスト
    from app.models.conversation import Conversation
    from app.models.issue import Issue
    from app.models.user import User
    print('all models: OK')
except Exception as e:
    print('ERROR:', type(e).__name__, str(e))
    import traceback; traceback.print_exc()
"

  # conversations.py に WebSocket notifier 呼び出しがあるか確認
  log_info "--- notifier/websocket 呼び出し箇所 ---"
  grep -n "notify\|websocket\|ws\|broadcast" "$CONV_PY" || echo "(なし)"

  # notifier.py を確認
  NOTIFIER=~/projects/decision-os/backend/app/core/notifier.py
  if [ -f "$NOTIFIER" ]; then
    log_info "--- notifier.py ---"
    cat "$NOTIFIER"
  fi
fi

# ===== 2. /analyze — input_id で正しく送信 =====
echo ""
echo "========== 2. /analyze（input_id フィールドで正しく送信） =========="
INPUT_ID=$(curl -s -X POST "$BASE_URL/inputs" \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d "{\"project_id\":\"$PID\",\"raw_text\":\"ログインするとエラーが出て進めません\"}" \
  | python3 -c "import sys,json; print(json.load(sys.stdin).get('id',''))" 2>/dev/null || echo "")
log_info "Input ID: $INPUT_ID"

if [ -n "$INPUT_ID" ]; then
  ANALYZE_RESP=$(curl -s -X POST "$BASE_URL/analyze" \
    -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
    -d "{\"input_id\":\"$INPUT_ID\"}")
  if echo "$ANALYZE_RESP" | python3 -c "import sys,json; d=json.load(sys.stdin); exit(0 if isinstance(d,list) and len(d)>0 else 1)" 2>/dev/null; then
    log_ok "/analyze 成功 → $(echo "$ANALYZE_RESP" | python3 -c "import sys,json; d=json.load(sys.stdin); print(len(d),'件')" 2>/dev/null)"
  elif echo "$ANALYZE_RESP" | grep -q "Internal Server Error"; then
    log_fail "/analyze → Internal Server Error（エンジン側のバグ）"
    log_info "エンジン単体テスト:"
    python3 -c "
import sys; sys.path.insert(0,'.')
try:
    from engine.main import analyze_text
    r = analyze_text('ログインするとエラーが出て進めません')
    print('engine OK:', r)
except Exception as e:
    print('engine ERROR:', e)
    import traceback; traceback.print_exc()
"
  else
    log_warn "/analyze レスポンス: $ANALYZE_RESP"
  fi
fi

# ===== 3. ラベル — Issue の labels カラムに直接セット =====
echo ""
echo "========== 3. ラベル — Issue.labels カラム更新で確認 =========="
log_info "ラベルは POST /api/v1/labels ではなく、PATCH /api/v1/issues/{id} の labels フィールドで管理"
if [ -n "$IID" ]; then
  LABEL_RESP=$(curl -s -X PATCH "$BASE_URL/issues/$IID" \
    -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
    -d '{"labels":["bug","urgent"]}')
  if echo "$LABEL_RESP" | python3 -c "import sys,json; d=json.load(sys.stdin); exit(0 if d.get('id') else 1)" 2>/dev/null; then
    LBLS=$(echo "$LABEL_RESP" | python3 -c "import sys,json; print(json.load(sys.stdin).get('labels',''))" 2>/dev/null)
    log_ok "ラベル付与成功 → labels: $LBLS"
  else
    log_warn "ラベル付与失敗 — $LABEL_RESP"
    # labels ルーターの POST 以外のエンドポイントを探す
    log_info "labels ルーター全エンドポイント:"
    grep -n "@router\." ~/projects/decision-os/backend/app/api/v1/routers/labels.py 2>/dev/null || true
  fi
fi

# ===== 4. 決定ログ — reason フィールドも追加 =====
echo ""
echo "========== 4. 決定ログ（decision_text + reason） =========="
log_info "--- decisions スキーマ全体確認 ---"
cat ~/projects/decision-os/backend/app/schemas/decision.py 2>/dev/null || true
echo ""

if [ -n "$IID" ]; then
  DEC_RESP=$(curl -s -X POST "$BASE_URL/decisions" \
    -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
    -d "{\"issue_id\":\"$IID\",\"decision_text\":\"テスト決定\",\"reason\":\"テスト理由\",\"project_id\":\"$PID\"}")
  if echo "$DEC_RESP" | python3 -c "import sys,json; d=json.load(sys.stdin); exit(0 if d.get('id') else 1)" 2>/dev/null; then
    log_ok "決定ログ作成成功"
  else
    log_warn "決定ログ失敗 — $DEC_RESP"
    # 必須フィールド一覧を抽出
    echo "$DEC_RESP" | python3 -c "
import sys,json
d=json.load(sys.stdin)
if isinstance(d.get('detail'),list):
    for e in d['detail']:
        print('  必須フィールド不足:', e.get('loc'), '-', e.get('msg'))
" 2>/dev/null || true
  fi
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
