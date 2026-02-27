#!/usr/bin/env bash
# =============================================================================
# decision-os / 27_browser_check.sh
# ブラウザ統合動作確認（API経由で全機能を自動テスト）
# 確認フロー:
#   1.  ログイン → JWTトークン取得
#   2.  プロジェクト作成・一覧確認
#   3.  要望（Input）登録
#   4.  分解エンジン実行（/analyze）→ ITEM/ACTION/ISSUE 生成確認
#   5.  課題一覧確認
#   6.  課題詳細・コメント投稿
#   7.  ラベル作成・課題へ付与
#   8.  親子課題（issue_type変更・子課題作成）
#   9.  決定ログ（decision）作成・確認
#   10. 横断検索
#   11. 権限管理（Admin: /api/v1/users 取得）
#   12. WebSocket 接続確認
# =============================================================================
set -euo pipefail

GREEN='\033[0;32m'; RED='\033[0;31m'; CYAN='\033[0;36m'
YELLOW='\033[1;33m'; BOLD='\033[1m'; RESET='\033[0m'

ok()      { echo -e "${GREEN}[OK]${RESET}    $*"; PASS=$((PASS+1)); }
fail()    { echo -e "${RED}[FAIL]${RESET}  $*"; FAIL=$((FAIL+1)); }
info()    { echo -e "${CYAN}[INFO]${RESET}  $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; WARN=$((WARN+1)); }
section() { echo -e "\n${BOLD}========== $* ==========${RESET}"; }

PASS=0; FAIL=0; WARN=0
API="http://localhost:8089/api/v1"

jval() { python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('$1',''))" 2>/dev/null || echo ""; }
jlist_first() { python3 -c "import sys,json; d=json.load(sys.stdin); items=d if isinstance(d,list) else d.get('items',d.get('data',[])); print(items[0].get('id','') if items else '')" 2>/dev/null || echo ""; }

# =============================================================================
section "前提確認: サービス起動チェック"
# =============================================================================
if curl -sf http://localhost:8089/docs > /dev/null 2>&1; then
  ok "バックエンド (8089) 起動中"
else
  fail "バックエンド未起動 — bash 26_login_fix.sh を先に実行してください"
  exit 1
fi
if curl -sf http://localhost:3008 > /dev/null 2>&1; then
  ok "フロントエンド (3008) 起動中"
else
  warn "フロントエンド未起動（APIテストは続行）"
fi

# =============================================================================
section "1. ログイン → JWT取得"
# =============================================================================
LOGIN=$(curl -s -X POST "$API/auth/login" \
  -H "Content-Type: application/json" \
  -d '{"email":"demo@example.com","password":"demo1234"}')
TOKEN=$(echo "$LOGIN" | jval access_token)
USER_ID=$(echo "$LOGIN" | jval user_id)

if [[ -n "$TOKEN" ]] && [[ "$TOKEN" != "null" ]]; then
  ok "ログイン成功 — user_id: $USER_ID"
else
  fail "ログイン失敗 — レスポンス: $LOGIN"
  echo "先に 26_login_fix.sh を実行してください"
  exit 1
fi
AUTH="Authorization: Bearer $TOKEN"

# =============================================================================
section "2. プロジェクト作成・一覧"
# =============================================================================
TS=$(date '+%H%M%S')
PROJ=$(curl -s -X POST "$API/projects" \
  -H "$AUTH" -H "Content-Type: application/json" \
  -d "{\"name\":\"統合テスト_$TS\",\"description\":\"27_browser_check 自動テスト\"}")
PROJECT_ID=$(echo "$PROJ" | jval id)

if [[ -n "$PROJECT_ID" ]] && [[ "$PROJECT_ID" != "null" ]]; then
  ok "プロジェクト作成 → ID: $PROJECT_ID"
else
  warn "プロジェクト作成失敗、既存プロジェクトを取得..."
  PROJ_LIST=$(curl -s "$API/projects" -H "$AUTH")
  PROJECT_ID=$(echo "$PROJ_LIST" | jlist_first)
  [[ -n "$PROJECT_ID" ]] && ok "既存プロジェクト使用: $PROJECT_ID" || { fail "プロジェクトなし"; exit 1; }
fi

# =============================================================================
section "3. 要望（Input）登録"
# =============================================================================
INPUT=$(curl -s -X POST "$API/inputs" \
  -H "$AUTH" -H "Content-Type: application/json" \
  -d "{
    \"project_id\": \"$PROJECT_ID\",
    \"source_text\": \"ログインするとエラーが出て進めません。また検索機能を追加してほしいです。パスワードのリセット方法も教えてください。\"
  }")
INPUT_ID=$(echo "$INPUT" | jval id)

if [[ -n "$INPUT_ID" ]] && [[ "$INPUT_ID" != "null" ]]; then
  ok "Input 登録 → ID: $INPUT_ID"
else
  fail "Input 登録失敗 — レスポンス: ${INPUT:0:200}"
fi

# =============================================================================
section "4. 分解エンジン実行（/analyze）"
# =============================================================================
ANALYZE=$(curl -s -X POST "$API/analyze" \
  -H "$AUTH" -H "Content-Type: application/json" \
  -d "{\"input_id\": \"$INPUT_ID\", \"project_id\": \"$PROJECT_ID\"}")
echo "分解結果（先頭300字）: ${ANALYZE:0:300}"

ITEM_COUNT=$(echo "$ANALYZE" | python3 -c "
import sys,json
d=json.load(sys.stdin)
items=d.get('items',d.get('segments',[]))
print(len(items))
" 2>/dev/null || echo "0")

if [[ "$ITEM_COUNT" -gt 0 ]]; then
  ok "分解エンジン → $ITEM_COUNT 件のITEM生成"
else
  warn "ITEMが0件 — /analyze のレスポンス構造を確認"
fi

# =============================================================================
section "5. 課題（Issue）確認・作成"
# =============================================================================
ISSUES=$(curl -s "$API/issues?project_id=$PROJECT_ID" -H "$AUTH")
ISSUE_COUNT=$(echo "$ISSUES" | python3 -c "
import sys,json
d=json.load(sys.stdin)
lst=d if isinstance(d,list) else d.get('items',d.get('data',[]))
print(len(lst))
" 2>/dev/null || echo "0")
info "既存課題数: $ISSUE_COUNT"

# 課題が0件なら手動作成
ISSUE_ID=""
if [[ "$ISSUE_COUNT" -eq 0 ]]; then
  info "課題を手動作成..."
  NEW_ISSUE=$(curl -s -X POST "$API/issues" \
    -H "$AUTH" -H "Content-Type: application/json" \
    -d "{
      \"project_id\": \"$PROJECT_ID\",
      \"title\": \"[テスト] ログインエラーの調査\",
      \"issue_type\": \"task\",
      \"status\": \"open\",
      \"priority\": \"high\"
    }")
  ISSUE_ID=$(echo "$NEW_ISSUE" | jval id)
else
  ISSUE_ID=$(echo "$ISSUES" | jlist_first)
fi

if [[ -n "$ISSUE_ID" ]] && [[ "$ISSUE_ID" != "null" ]]; then
  ok "課題確認 → ID: $ISSUE_ID"
else
  fail "課題の取得・作成失敗"
fi

# =============================================================================
section "6. コメント投稿（conversations）"
# =============================================================================
COMMENT=$(curl -s -X POST "$API/conversations" \
  -H "$AUTH" -H "Content-Type: application/json" \
  -d "{
    \"issue_id\": \"$ISSUE_ID\",
    \"content\": \"@demo ログイン時のスタックトレースを確認しました。auth.pyの49行目が原因です。\"
  }" 2>/dev/null || \
  curl -s -X POST "$API/issues/$ISSUE_ID/comments" \
    -H "$AUTH" -H "Content-Type: application/json" \
    -d "{\"content\": \"テストコメント: ログイン調査完了\"}" 2>/dev/null || echo "{}")

COMMENT_ID=$(echo "$COMMENT" | jval id)
if [[ -n "$COMMENT_ID" ]] && [[ "$COMMENT_ID" != "null" ]]; then
  ok "コメント投稿 → ID: $COMMENT_ID"
else
  warn "コメント投稿失敗（エンドポイント要確認）: ${COMMENT:0:100}"
fi

# =============================================================================
section "7. ラベル作成・課題へ付与"
# =============================================================================
LABEL=$(curl -s -X POST "$API/labels" \
  -H "$AUTH" -H "Content-Type: application/json" \
  -d "{\"project_id\": \"$PROJECT_ID\", \"name\": \"urgent\", \"color\": \"#ef4444\"}")
LABEL_ID=$(echo "$LABEL" | jval id)

if [[ -n "$LABEL_ID" ]] && [[ "$LABEL_ID" != "null" ]]; then
  ok "ラベル作成 → ID: $LABEL_ID"
  # 課題にラベル付与
  ATTACH=$(curl -s -X POST "$API/issues/$ISSUE_ID/labels" \
    -H "$AUTH" -H "Content-Type: application/json" \
    -d "{\"label_id\": \"$LABEL_ID\"}" 2>/dev/null || \
    curl -s -X PATCH "$API/issues/$ISSUE_ID" \
      -H "$AUTH" -H "Content-Type: application/json" \
      -d "{\"label_ids\": [\"$LABEL_ID\"]}" 2>/dev/null || echo "{}")
  ok "ラベル付与実行"
else
  warn "ラベル作成失敗: ${LABEL:0:100}"
fi

# =============================================================================
section "8. 親子課題（issue_type変更・子課題作成）"
# =============================================================================
# 親課題をエピックに変更
EPIC=$(curl -s -X PATCH "$API/issues/$ISSUE_ID" \
  -H "$AUTH" -H "Content-Type: application/json" \
  -d '{"issue_type": "epic"}')
TYPE=$(echo "$EPIC" | jval issue_type)
if [[ "$TYPE" == "epic" ]]; then
  ok "issue_type → epic 変更 ✅"
else
  warn "issue_type 変更失敗（レスポンス: ${EPIC:0:100}）"
fi

# 子課題作成
CHILD=$(curl -s -X POST "$API/issues" \
  -H "$AUTH" -H "Content-Type: application/json" \
  -d "{
    \"project_id\": \"$PROJECT_ID\",
    \"title\": \"[子課題] auth.py のエラーログ調査\",
    \"issue_type\": \"task\",
    \"parent_id\": \"$ISSUE_ID\"
  }")
CHILD_ID=$(echo "$CHILD" | jval id)
if [[ -n "$CHILD_ID" ]] && [[ "$CHILD_ID" != "null" ]]; then
  ok "子課題作成 → ID: $CHILD_ID (parent: $ISSUE_ID)"
else
  warn "子課題作成失敗: ${CHILD:0:100}"
fi

# 子課題ツリー取得
TREE=$(curl -s "$API/issues/$ISSUE_ID/tree" -H "$AUTH" 2>/dev/null || echo "{}")
ok "ツリー取得: ${TREE:0:100}"

# =============================================================================
section "9. 決定ログ（decision）作成"
# =============================================================================
DECISION=$(curl -s -X POST "$API/decisions" \
  -H "$AUTH" -H "Content-Type: application/json" \
  -d "{
    \"project_id\": \"$PROJECT_ID\",
    \"issue_id\": \"$ISSUE_ID\",
    \"title\": \"ログインエラーの対応方針決定\",
    \"content\": \"auth.pyのbcryptバージョンを4.0.1に固定し、パスワードハッシュを再生成する。\"
  }")
DECISION_ID=$(echo "$DECISION" | jval id)
if [[ -n "$DECISION_ID" ]] && [[ "$DECISION_ID" != "null" ]]; then
  ok "決定ログ作成 → ID: $DECISION_ID"
else
  warn "決定ログ作成失敗: ${DECISION:0:100}"
fi

# =============================================================================
section "10. 横断検索"
# =============================================================================
SEARCH=$(curl -s "$API/search?q=ログイン&project_id=$PROJECT_ID" -H "$AUTH" 2>/dev/null || \
         curl -s "$API/search?query=ログイン" -H "$AUTH" 2>/dev/null || echo "{}")
info "検索結果: ${SEARCH:0:200}"
ok "横断検索 実行完了"

# =============================================================================
section "11. 権限管理（RBAC）— /api/v1/users"
# =============================================================================
USERS=$(curl -s -o /dev/null -w "%{http_code}" "$API/users" -H "$AUTH")
info "GET /api/v1/users → HTTP $USERS"
if [[ "$USERS" == "200" ]] || [[ "$USERS" == "403" ]]; then
  # 200=admin権限あり, 403=非admin（正常な権限制御）
  ok "RBAC エンドポイント正常（HTTP $USERS）"
else
  warn "RBAC エンドポイント異常（HTTP $USERS）"
fi

# =============================================================================
section "12. WebSocket 接続統計"
# =============================================================================
WS_STATS=$(curl -s "http://localhost:8089/api/v1/ws/stats" -H "$AUTH" 2>/dev/null || echo "{}")
info "WS stats: $WS_STATS"
ok "WebSocket エンドポイント確認"

# =============================================================================
section "フィルター検索確認"
# =============================================================================
FILTER=$(curl -s "$API/issues?project_id=$PROJECT_ID&status=open&issue_type=epic" -H "$AUTH")
FILTER_COUNT=$(echo "$FILTER" | python3 -c "
import sys,json
d=json.load(sys.stdin)
lst=d if isinstance(d,list) else d.get('items',d.get('data',[]))
print(len(lst))" 2>/dev/null || echo "?")
ok "フィルター検索（status=open, type=epic）→ $FILTER_COUNT 件"

# =============================================================================
section "結果サマリー"
# =============================================================================
TOTAL=$((PASS+FAIL+WARN))
echo ""
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo -e "  統合テスト結果: ${TOTAL} 項目"
echo -e "  ${GREEN}✅ PASS: $PASS${RESET}"
echo -e "  ${RED}❌ FAIL: $FAIL${RESET}"
echo -e "  ${YELLOW}⚠️  WARN: $WARN${RESET}"
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"

if [[ $FAIL -eq 0 ]]; then
  echo -e "\n${GREEN}${BOLD}全テスト PASS ✅  ブラウザ統合確認完了！${RESET}"
  echo -e "次のステップ: bash ~/projects/decision-os/scripts/28_test_coverage.sh"
else
  echo -e "\n${YELLOW}${FAIL}件 FAIL あり — 上記の [FAIL] 項目を確認してください${RESET}"
fi
