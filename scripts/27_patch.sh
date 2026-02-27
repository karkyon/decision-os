#!/bin/bash
# 27_patch.sh — 統合テスト残課題の修正 + /analyze 調査
set -euo pipefail
BASE_URL="http://localhost:8089/api/v1"
FRONTEND="http://localhost:3008"
PASS=0; FAIL=0; WARN=0

log_ok()   { echo "[OK]    $*"; PASS=$((PASS+1)); }
log_fail() { echo "[FAIL]  $*"; FAIL=$((FAIL+1)); }
log_warn() { echo "[WARN]  $*"; WARN=$((WARN+1)); }
log_info() { echo "[INFO]  $*"; }

# ===== 0. ログイン =====
echo "========== 0. ログイン =========="
LOGIN=$(curl -s -X POST "$BASE_URL/auth/login" \
  -H "Content-Type: application/json" \
  -d '{"email":"demo@example.com","password":"demo1234"}')
TOKEN=$(echo "$LOGIN" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('access_token',''))" 2>/dev/null || echo "")
if [ -z "$TOKEN" ]; then
  log_fail "ログイン失敗 — $LOGIN"
  exit 1
fi
log_ok "JWT取得成功"
AUTH="-H \"Authorization: Bearer $TOKEN\""

# プロジェクト作成
PID=$(curl -s -X POST "$BASE_URL/projects" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"name":"patch_test_'$(date +%s)'","description":"patch"}' \
  | python3 -c "import sys,json; print(json.load(sys.stdin).get('id',''))" 2>/dev/null || echo "")
log_info "プロジェクトID: $PID"

# ===== 1. Input登録 — raw_text フィールドで送信 =====
echo ""
echo "========== 1. Input登録（raw_text フィールド） =========="
INPUT_RESP=$(curl -s -X POST "$BASE_URL/inputs" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"project_id\":\"$PID\",\"raw_text\":\"ログインするとエラーが出て進めません\"}")
INPUT_ID=$(echo "$INPUT_RESP" | python3 -c "import sys,json; print(json.load(sys.stdin).get('id',''))" 2>/dev/null || echo "")
if [ -n "$INPUT_ID" ]; then
  log_ok "Input登録成功 → ID: $INPUT_ID"
else
  log_fail "Input登録失敗 — $INPUT_RESP"
  # フォールバック: text フィールドも試す
  log_info "フォールバック: text フィールドで再試行..."
  INPUT_RESP2=$(curl -s -X POST "$BASE_URL/inputs" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d "{\"project_id\":\"$PID\",\"text\":\"ログインするとエラーが出て進めません\"}")
  INPUT_ID=$(echo "$INPUT_RESP2" | python3 -c "import sys,json; print(json.load(sys.stdin).get('id',''))" 2>/dev/null || echo "")
  if [ -n "$INPUT_ID" ]; then
    log_ok "Input登録成功（text フィールドで成功）→ ID: $INPUT_ID"
    log_info ">>> inputs.py の受付フィールドは 'text' です"
  else
    log_warn "どちらのフィールドでも失敗 — raw_text: $INPUT_RESP / text: $INPUT_RESP2"
  fi
fi

# ===== 2. /analyze の Internal Server Error 調査 =====
echo ""
echo "========== 2. /analyze 調査 =========="

log_info "--- ルーター定義確認 ---"
ANALYZE_PY=$(find ~/projects/decision-os/backend/app -name "analyze.py" 2>/dev/null | head -1)
if [ -n "$ANALYZE_PY" ]; then
  log_info "analyze.py: $ANALYZE_PY"
  echo "--- 先頭60行 ---"
  head -60 "$ANALYZE_PY"
else
  log_warn "analyze.py が見つかりません"
fi

log_info ""
log_info "--- /analyze に text フィールドで POST ---"
ANALYZE_RESP=$(curl -s -X POST "$BASE_URL/analyze" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"text":"ログインするとエラーが出て進めません"}')
echo "レスポンス: $ANALYZE_RESP"

if echo "$ANALYZE_RESP" | grep -q "Internal Server Error"; then
  log_warn "/analyze → Internal Server Error"
  log_info ""
  log_info "--- backend.log の直近エラー（analyze関連） ---"
  LOGFILE=$(find ~/projects/decision-os -name "backend.log" 2>/dev/null | head -1)
  if [ -n "$LOGFILE" ]; then
    grep -i "error\|traceback\|exception\|analyze" "$LOGFILE" | tail -30 || true
  else
    log_info "backend.log が見つかりません。uvicorn のログを確認:"
    journalctl --no-pager -n 30 2>/dev/null || true
  fi

  log_info ""
  log_info "--- エンジン単体テスト ---"
  cd ~/projects/decision-os/backend
  source .venv/bin/activate 2>/dev/null || true
  python3 -c "
import sys
sys.path.insert(0, '.')
try:
    from engine.main import analyze
    result = analyze('ログインするとエラーが出て進めません')
    print('エンジン単体: OK →', result)
except Exception as e:
    print('エンジン単体エラー:', type(e).__name__, str(e))
    import traceback; traceback.print_exc()
"

  log_info ""
  log_info "--- /analyze に input_id フィールドも試す ---"
  if [ -n "$INPUT_ID" ]; then
    ANALYZE_RESP2=$(curl -s -X POST "$BASE_URL/analyze" \
      -H "Authorization: Bearer $TOKEN" \
      -H "Content-Type: application/json" \
      -d "{\"input_id\":\"$INPUT_ID\"}")
    echo "input_id レスポンス: $ANALYZE_RESP2"
  fi
else
  log_ok "/analyze 成功 → $(echo "$ANALYZE_RESP" | head -c 200)"
fi

# ===== 3. コメント投稿 — body フィールドで送信 =====
echo ""
echo "========== 3. コメント投稿（body フィールド） =========="
# まず課題作成
ISSUE_RESP=$(curl -s -X POST "$BASE_URL/issues" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"project_id\":\"$PID\",\"title\":\"patch test issue\",\"issue_type\":\"task\",\"status\":\"open\"}")
IID=$(echo "$ISSUE_RESP" | python3 -c "import sys,json; print(json.load(sys.stdin).get('id',''))" 2>/dev/null || echo "")
log_info "課題ID: $IID"

if [ -n "$IID" ]; then
  CONV_RESP=$(curl -s -X POST "$BASE_URL/conversations" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d "{\"issue_id\":\"$IID\",\"body\":\"テストコメントです\"}")
  if echo "$CONV_RESP" | python3 -c "import sys,json; d=json.load(sys.stdin); exit(0 if d.get('id') else 1)" 2>/dev/null; then
    log_ok "コメント投稿成功（body フィールドで成功）"
  else
    log_warn "コメント投稿失敗（body）— $CONV_RESP"
    # content フィールドも試す
    CONV_RESP2=$(curl -s -X POST "$BASE_URL/conversations" \
      -H "Authorization: Bearer $TOKEN" \
      -H "Content-Type: application/json" \
      -d "{\"issue_id\":\"$IID\",\"content\":\"テストコメントです\"}")
    if echo "$CONV_RESP2" | python3 -c "import sys,json; d=json.load(sys.stdin); exit(0 if d.get('id') else 1)" 2>/dev/null; then
      log_ok "コメント投稿成功（content フィールドで成功）"
    else
      log_warn "コメント投稿失敗（content）— $CONV_RESP2"
      log_info "--- conversations.py のスキーマ確認 ---"
      grep -n "body\|content\|message\|class.*Schema\|class.*Request" \
        ~/projects/decision-os/backend/app/api/v1/routers/conversations.py 2>/dev/null | head -20 || true
      grep -n "body\|content\|message" \
        ~/projects/decision-os/backend/app/schemas/conversation.py 2>/dev/null | head -20 || true
    fi
  fi
fi

# ===== 4. ラベル — 正しいエンドポイント調査 =====
echo ""
echo "========== 4. ラベル エンドポイント確認 =========="
log_info "--- ラベル関連ルーター確認 ---"
LABELS_PY=$(find ~/projects/decision-os/backend/app -name "labels.py" 2>/dev/null | head -1)
if [ -n "$LABELS_PY" ]; then
  grep -n "router\.\|@router\|def " "$LABELS_PY" | head -20
else
  log_warn "labels.py が見つかりません"
fi

# GET で一覧確認してから POST
log_info "GET /api/v1/labels:"
curl -s "$BASE_URL/labels" -H "Authorization: Bearer $TOKEN" | head -c 200
echo ""

log_info "POST /api/v1/labels (プロジェクト紐づきで試行):"
LABEL_RESP=$(curl -s -X POST "$BASE_URL/labels" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"name\":\"bug\",\"color\":\"#e74c3c\",\"project_id\":\"$PID\"}")
echo "$LABEL_RESP" | head -c 300
LABEL_ID=$(echo "$LABEL_RESP" | python3 -c "import sys,json; print(json.load(sys.stdin).get('id',''))" 2>/dev/null || echo "")
if [ -n "$LABEL_ID" ]; then
  log_ok "ラベル作成成功 → ID: $LABEL_ID"
else
  log_warn "ラベル作成失敗。エンドポイント/フィールド要確認 — $LABEL_RESP"
fi

# ===== 5. 決定ログ — decision_text フィールドで送信 =====
echo ""
echo "========== 5. 決定ログ（decision_text フィールド） =========="
if [ -n "$IID" ]; then
  DEC_RESP=$(curl -s -X POST "$BASE_URL/decisions" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d "{\"issue_id\":\"$IID\",\"decision_text\":\"テスト決定内容\",\"project_id\":\"$PID\"}")
  if echo "$DEC_RESP" | python3 -c "import sys,json; d=json.load(sys.stdin); exit(0 if d.get('id') else 1)" 2>/dev/null; then
    log_ok "決定ログ作成成功"
  else
    log_warn "決定ログ失敗 — $DEC_RESP"
    log_info "--- decisions.py スキーマ確認 ---"
    grep -n "decision_text\|content\|class.*Schema\|class.*Request" \
      ~/projects/decision-os/backend/app/schemas/decision.py 2>/dev/null | head -15 || true
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
  echo "[OK] 全項目クリア！次のステップ: conftest.py 修正 → テストカバレッジ計測"
elif [ $FAIL -eq 0 ]; then
  echo "[WARN] FAIL なし・WARN あり — 上記 WARN の詳細を確認してください"
else
  echo "[FAIL] FAIL あり — 上記の内容を確認して修正が必要です"
fi
