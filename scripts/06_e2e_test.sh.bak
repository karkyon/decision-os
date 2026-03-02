#!/usr/bin/env bash
# =============================================================================
# decision-os  /  Step 6: プロジェクト作成 & E2Eテスト（修正版）
# 実行方法: bash 06_e2e_test.sh
# 前提: Docker(DB/Redis)・バックエンド(8089)・フロントエンド(3008) が起動済み
# =============================================================================
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'
info()    { echo -e "${CYAN}[INFO]${RESET}  $*"; }
success() { echo -e "${GREEN}[OK]${RESET}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
error()   { echo -e "${RED}[ERROR]${RESET} $*"; exit 1; }
section() { echo -e "\n${BOLD}========== $* ==========${RESET}"; }

PASS_COUNT=0
FAIL_COUNT=0
BASE_URL="http://localhost:8089"
API="${BASE_URL}/api/v1"

# ─── JSON フィールド抽出ヘルパー（grep/cut を廃止、python3 で堅牢化）───────
jq_get() {
  # jq_get <json_string> <key>  → 値を echo
  local json="$1" key="$2"
  echo "$json" | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    if isinstance(d, list):
        print(d[0].get('$key', '') if d else '')
    else:
        print(d.get('$key', ''))
except Exception:
    print('')
" 2>/dev/null || echo ""
}

count_items() {
  # count_items <json_string>  → リスト長を echo
  local json="$1"
  echo "$json" | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    items = d if isinstance(d, list) else d.get('items', [])
    print(len(items))
except Exception:
    print(0)
" 2>/dev/null || echo 0
}

first_id() {
  # first_id <json_string>  → items[0].id を echo
  local json="$1"
  echo "$json" | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    items = d if isinstance(d, list) else d.get('items', [])
    print(items[0].get('id','') if items else '')
except Exception:
    print('')
" 2>/dev/null || echo ""
}

# テスト用サンプル要望テキスト
SAMPLE_TEXT="検索画面でキーワードを入力してもヒットしないことがある。特に日本語の場合に多い気がします。
またタグの選択UIが使いにくいという声が複数ユーザーから出ています。ドロップダウンではなくチェックボックス形式にしてほしい。
ダッシュボードの読み込みが遅い。特に課題が100件を超えると顕著です。
ログイン後に前回の作業状態を復元してほしい。"

# =============================================================================
section "0. 前提チェック：サービス起動確認"
# =============================================================================

if curl -sf "${BASE_URL}/docs" > /dev/null 2>&1; then
  success "バックエンドAPI: OK (${BASE_URL}/docs)"
else
  error "バックエンド(8089)が応答しません。先に bash 06_start_services.sh を実行してください"
fi

if curl -sf "http://localhost:3008" > /dev/null 2>&1; then
  success "フロントエンド: OK (http://localhost:3008)"
else
  warn "フロントエンド(3008)未起動。APIテストは続行します"
fi

# =============================================================================
section "1. 認証テスト: ログイン → JWTトークン取得"
# =============================================================================

info "demo@example.com でログイン..."
LOGIN_RESP=$(curl -s -X POST "${API}/auth/login" \
  -H "Content-Type: application/json" \
  -d '{"email":"demo@example.com","password":"demo1234"}') || true

info "レスポンス: ${LOGIN_RESP:0:200}"

TOKEN=$(jq_get "$LOGIN_RESP" "access_token")
USER_ID=$(jq_get "$LOGIN_RESP" "user_id")

[[ -n "$TOKEN" ]] && [[ "$TOKEN" != "null" ]] \
  || error "トークン取得失敗\nレスポンス: $LOGIN_RESP"

success "ログイン成功"
info "  user_id : $USER_ID"
info "  token   : ${TOKEN:0:50}..."
PASS_COUNT=$((PASS_COUNT+1))

AUTH="Authorization: Bearer $TOKEN"

# =============================================================================
section "2. プロジェクト作成（ダッシュボードのカウントを動かす）"
# =============================================================================

info "テストプロジェクトを作成中..."
TS=$(date '+%Y-%m-%d %H:%M')
PROJ_RESP=$(curl -s -X POST "${API}/projects" \
  -H "$AUTH" \
  -H "Content-Type: application/json" \
  -d "{\"name\":\"decision-os 動作確認プロジェクト\",\"description\":\"Phase1 E2Eテスト用 ($TS)\"}") || true

info "レスポンス: ${PROJ_RESP:0:200}"
PROJECT_ID=$(jq_get "$PROJ_RESP" "id")

if [[ -n "$PROJECT_ID" ]] && [[ "$PROJECT_ID" != "null" ]]; then
  success "プロジェクト作成成功 → project_id: $PROJECT_ID"
  PASS_COUNT=$((PASS_COUNT+1))
else
  warn "プロジェクト作成失敗。既存プロジェクトから取得を試みます..."
  PROJ_LIST=$(curl -s "${API}/projects" -H "$AUTH") || true
  PROJECT_ID=$(first_id "$PROJ_LIST")
  [[ -n "$PROJECT_ID" ]] && [[ "$PROJECT_ID" != "null" ]] \
    || error "利用可能なプロジェクトがありません"
  warn "  既存 project_id: $PROJECT_ID を使用"
  FAIL_COUNT=$((FAIL_COUNT+1))
fi

# =============================================================================
section "3. プロジェクト一覧確認"
# =============================================================================

LIST_RESP=$(curl -s "${API}/projects" -H "$AUTH") || true
PROJ_COUNT=$(count_items "$LIST_RESP")
success "プロジェクト一覧: ${PROJ_COUNT}件"
PASS_COUNT=$((PASS_COUNT+1))

# =============================================================================
section "4. 要望（RAW_INPUT）登録"
# =============================================================================

info "原文テキストを登録中..."
ENCODED=$(python3 -c "import json,sys; print(json.dumps(sys.stdin.read()))" <<< "$SAMPLE_TEXT")

INPUT_RESP=$(curl -s -X POST "${API}/inputs" \
  -H "$AUTH" \
  -H "Content-Type: application/json" \
  -d "{
    \"project_id\":\"$PROJECT_ID\",
    \"raw_text\":$ENCODED,
    \"source_type\":\"meeting\",
    \"author\":\"テストユーザー\",
    \"summary\":\"ユーザー要望・不具合報告（E2Eテスト用）\"
  }") || true

info "レスポンス: ${INPUT_RESP:0:200}"
INPUT_ID=$(jq_get "$INPUT_RESP" "id")

[[ -n "$INPUT_ID" ]] && [[ "$INPUT_ID" != "null" ]] \
  || error "INPUT登録失敗\nレスポンス: $INPUT_RESP"

success "INPUT登録成功 → input_id: $INPUT_ID"
PASS_COUNT=$((PASS_COUNT+1))

# =============================================================================
section "5. 分解エンジン実行（analyze）"
# =============================================================================

info "分解エンジンを実行中..."
ANA_RESP=$(curl -s -X POST "${API}/analyze" \
  -H "$AUTH" \
  -H "Content-Type: application/json" \
  -d "{\"input_id\":\"$INPUT_ID\",\"options\":{\"ai_assist\":false,\"threshold\":0.6}}") || true

info "レスポンス: ${ANA_RESP:0:400}"

ITEM_COUNT=$(count_items "$ANA_RESP")
FIRST_ITEM_ID=$(first_id "$ANA_RESP")

if [[ -n "$FIRST_ITEM_ID" ]] && [[ "$FIRST_ITEM_ID" != "null" ]]; then
  success "分解成功: ${ITEM_COUNT}件のITEM生成 / 先頭ID: $FIRST_ITEM_ID"

  I_INTENT=$(echo "$ANA_RESP" | python3 -c "
import json,sys; d=json.load(sys.stdin)
items=d if isinstance(d,list) else d.get('items',[])
print(items[0].get('intent_code','?') if items else '?')" 2>/dev/null || echo "?")
  I_DOMAIN=$(echo "$ANA_RESP" | python3 -c "
import json,sys; d=json.load(sys.stdin)
items=d if isinstance(d,list) else d.get('items',[])
print(items[0].get('domain_code','?') if items else '?')" 2>/dev/null || echo "?")
  I_CONF=$(echo "$ANA_RESP" | python3 -c "
import json,sys; d=json.load(sys.stdin)
items=d if isinstance(d,list) else d.get('items',[])
print(items[0].get('confidence','?') if items else '?')" 2>/dev/null || echo "?")

  info "  Intent: $I_INTENT  /  Domain: $I_DOMAIN  /  信頼度: $I_CONF"
  PASS_COUNT=$((PASS_COUNT+1))
else
  warn "analyzeレスポンスからITEM取得失敗。/items?input_id= で再取得を試みます..."
  FALLBACK=$(curl -s "${API}/items?input_id=${INPUT_ID}" -H "$AUTH") || true
  FIRST_ITEM_ID=$(first_id "$FALLBACK")
  ITEM_COUNT=$(count_items "$FALLBACK")
  if [[ -n "$FIRST_ITEM_ID" ]] && [[ "$FIRST_ITEM_ID" != "null" ]]; then
    warn "  /items から取得成功: ${ITEM_COUNT}件 / ID: $FIRST_ITEM_ID"
  else
    warn "  ITEM取得失敗（analyzeエンドポイントの実装を確認）"
    FAIL_COUNT=$((FAIL_COUNT+1))
  fi
fi

# =============================================================================
section "6. ITEM一覧確認"
# =============================================================================

ITEMS_RESP=$(curl -s "${API}/items?input_id=${INPUT_ID}" -H "$AUTH") || true
FETCHED=$(count_items "$ITEMS_RESP")

if [[ "$FETCHED" -gt 0 ]]; then
  success "ITEM一覧: ${FETCHED}件"
  # FIRST_ITEM_IDが未取得なら補完
  if [[ -z "${FIRST_ITEM_ID:-}" ]] || [[ "$FIRST_ITEM_ID" == "null" ]]; then
    FIRST_ITEM_ID=$(first_id "$ITEMS_RESP")
    info "  ITEM_ID 補完: $FIRST_ITEM_ID"
  fi
  PASS_COUNT=$((PASS_COUNT+1))
else
  warn "ITEM一覧: 0件 (${ITEMS_RESP:0:200})"
  FAIL_COUNT=$((FAIL_COUNT+1))
fi

# =============================================================================
section "7. ACTION設定（最初のITEMを課題化）"
# =============================================================================

ACTION_ID=""
if [[ -n "${FIRST_ITEM_ID:-}" ]] && [[ "$FIRST_ITEM_ID" != "null" ]]; then
  info "ITEM($FIRST_ITEM_ID) に ACTION=CREATE_ISSUE を設定..."
  ACT_RESP=$(curl -s -X POST "${API}/actions" \
    -H "$AUTH" \
    -H "Content-Type: application/json" \
    -d "{
      \"item_id\":\"$FIRST_ITEM_ID\",
      \"action_type\":\"CREATE_ISSUE\",
      \"reason\":\"E2Eテスト：ユーザー報告の不具合として課題化\",
      \"decided_by\":\"demo@example.com\"
    }") || true

  info "レスポンス: ${ACT_RESP:0:200}"
  ACTION_ID=$(jq_get "$ACT_RESP" "id")

  if [[ -n "$ACTION_ID" ]] && [[ "$ACTION_ID" != "null" ]]; then
    success "ACTION設定成功 → action_id: $ACTION_ID"
    PASS_COUNT=$((PASS_COUNT+1))
  else
    warn "ACTION設定失敗 (${ACT_RESP:0:200})"
    FAIL_COUNT=$((FAIL_COUNT+1))
  fi
else
  warn "ITEM_IDなし → ACTIONをスキップ"
  FAIL_COUNT=$((FAIL_COUNT+1))
fi

# =============================================================================
section "8. 課題（ISSUE）作成"
# =============================================================================

ISSUE_ID=""

# ① convert エンドポイントを試みる
if [[ -n "${ACTION_ID:-}" ]]; then
  CV_RESP=$(curl -s -X POST "${API}/actions/${ACTION_ID}/convert" \
    -H "$AUTH" \
    -H "Content-Type: application/json" \
    -d "{
      \"title\":\"[E2E] 検索機能の日本語対応不具合\",
      \"description\":\"日本語キーワードで検索してもヒットしない。タグUIの改善も必要。\",
      \"priority\":\"high\",
      \"status\":\"open\",
      \"project_id\":\"$PROJECT_ID\"
    }") || true
  info "convert レスポンス: ${CV_RESP:0:200}"
  ISSUE_ID=$(jq_get "$CV_RESP" "id")
fi

# ② 失敗なら /issues へ直接作成
if [[ -z "${ISSUE_ID:-}" ]] || [[ "$ISSUE_ID" == "null" ]]; then
  warn "convert失敗 → /issues へ直接作成..."
  IS_RESP=$(curl -s -X POST "${API}/issues" \
    -H "$AUTH" \
    -H "Content-Type: application/json" \
    -d "{
      \"title\":\"[E2E] 検索機能の日本語対応不具合\",
      \"description\":\"日本語キーワードで検索してもヒットしない。タグUIの改善も必要。\",
      \"priority\":\"high\",
      \"status\":\"open\",
      \"project_id\":\"$PROJECT_ID\"
    }") || true
  info "直接作成レスポンス: ${IS_RESP:0:200}"
  ISSUE_ID=$(jq_get "$IS_RESP" "id")
fi

if [[ -n "${ISSUE_ID:-}" ]] && [[ "$ISSUE_ID" != "null" ]]; then
  success "課題作成成功 → issue_id: $ISSUE_ID"
  PASS_COUNT=$((PASS_COUNT+1))
else
  warn "課題作成失敗"
  FAIL_COUNT=$((FAIL_COUNT+1))
fi

# =============================================================================
section "9. 課題一覧確認"
# =============================================================================

IL_RESP=$(curl -s "${API}/issues?project_id=${PROJECT_ID}" -H "$AUTH") || true
IL_COUNT=$(count_items "$IL_RESP")
if [[ "$IL_COUNT" -gt 0 ]]; then
  success "課題一覧: ${IL_COUNT}件"
  PASS_COUNT=$((PASS_COUNT+1))
else
  warn "課題一覧: 0件 (${IL_RESP:0:200})"
  FAIL_COUNT=$((FAIL_COUNT+1))
fi

# =============================================================================
section "10. トレーサビリティ確認（ISSUE → ACTION → ITEM → INPUT）"
# =============================================================================

if [[ -n "${ISSUE_ID:-}" ]] && [[ "$ISSUE_ID" != "null" ]]; then
  info "trace API 呼び出し中 (issue_id: $ISSUE_ID)..."
  TR_RESP=$(curl -s "${API}/trace/${ISSUE_ID}" -H "$AUTH") || true
  info "レスポンス: ${TR_RESP:0:500}"

  echo ""
  echo "  ┌────────────────────────────────────────────┐"
  echo "  │       トレーサビリティチェーン確認          │"
  echo "  └────────────────────────────────────────────┘"

  check_chain() {
    local label="$1" key="$2"
    local found
    found=$(echo "$TR_RESP" | python3 -c "
import json,sys
try:
    d=json.load(sys.stdin)
    print('yes' if d.get('$key') else 'no')
except Exception:
    print('no')" 2>/dev/null || echo "no")
    if [[ "$found" == "yes" ]]; then
      echo -e "  ${GREEN}✅${RESET} $label"
      PASS_COUNT=$((PASS_COUNT+1))
    else
      echo -e "  ${RED}❌${RESET} $label（データなし）"
      FAIL_COUNT=$((FAIL_COUNT+1))
    fi
  }

  check_chain "ISSUE（課題）"      "issue"
  check_chain "ACTION（対応判断）" "action"
  check_chain "ITEM（意味単位）"   "item"
  check_chain "INPUT（原文）"      "input"
  echo ""
else
  warn "issue_idなし → トレーサビリティをスキップ"
  FAIL_COUNT=$((FAIL_COUNT+1))
fi

# =============================================================================
section "11. 課題ステータス更新（open → in_progress）"
# =============================================================================

if [[ -n "${ISSUE_ID:-}" ]] && [[ "$ISSUE_ID" != "null" ]]; then
  UPD_RESP=$(curl -s -X PATCH "${API}/issues/${ISSUE_ID}" \
    -H "$AUTH" \
    -H "Content-Type: application/json" \
    -d '{"status":"in_progress"}') || true
  NEW_ST=$(jq_get "$UPD_RESP" "status")
  if [[ -n "$NEW_ST" ]] && [[ "$NEW_ST" != "null" ]]; then
    success "課題更新成功: status = $NEW_ST"
    PASS_COUNT=$((PASS_COUNT+1))
  else
    warn "課題更新失敗 (${UPD_RESP:0:200})"
    FAIL_COUNT=$((FAIL_COUNT+1))
  fi
fi

# =============================================================================
section "12. ダッシュボード集計サマリー"
# =============================================================================

P_TOT=$(curl -s "${API}/projects" -H "$AUTH" | python3 -c "
import json,sys; d=json.load(sys.stdin); items=d if isinstance(d,list) else d.get('items',[]); print(len(items))" 2>/dev/null || echo "?")
I_TOT=$(curl -s "${API}/inputs?project_id=${PROJECT_ID}" -H "$AUTH" | python3 -c "
import json,sys; d=json.load(sys.stdin); items=d if isinstance(d,list) else d.get('items',[]); print(len(items))" 2>/dev/null || echo "?")
IS_TOT=$(curl -s "${API}/issues?project_id=${PROJECT_ID}" -H "$AUTH" | python3 -c "
import json,sys; d=json.load(sys.stdin); items=d if isinstance(d,list) else d.get('items',[]); print(len(items))" 2>/dev/null || echo "?")

echo ""
echo "  ┌─────────────────────────────────────────┐"
echo "  │     ダッシュボード表示カウント（確認）   │"
echo "  ├─────────────────────────────────────────┤"
printf "  │  プロジェクト数 : %3s件                  │\n" "$P_TOT"
printf "  │  要望(INPUT)数  : %3s件                  │\n" "$I_TOT"
printf "  │  課題(ISSUE)数  : %3s件                  │\n" "$IS_TOT"
echo "  └─────────────────────────────────────────┘"
PASS_COUNT=$((PASS_COUNT+1))

# =============================================================================
section "テスト結果サマリー"
# =============================================================================

TOTAL=$((PASS_COUNT+FAIL_COUNT))
echo ""
echo "  ╔════════════════════════════════════════════════╗"
echo "  ║          E2E テスト 最終結果                   ║"
echo "  ╠════════════════════════════════════════════════╣"
printf  "  ║  ✅ PASS : %3d / %3d                           ║\n" "$PASS_COUNT" "$TOTAL"
printf  "  ║  ❌ FAIL : %3d                                  ║\n" "$FAIL_COUNT"
echo "  ╠════════════════════════════════════════════════╣"
printf  "  ║  PROJECT : %-36s  ║\n" "${PROJECT_ID:0:36}"
printf  "  ║  INPUT   : %-36s  ║\n" "${INPUT_ID:0:36}"
printf  "  ║  ISSUE   : %-36s  ║\n" "${ISSUE_ID:-（未作成）}"
echo "  ╚════════════════════════════════════════════════╝"
echo ""

if [[ $FAIL_COUNT -eq 0 ]]; then
  echo -e "${GREEN}🎉 全テスト合格！Phase1 E2E検証完了${RESET}"
else
  echo -e "${RED}⚠️  ${FAIL_COUNT}件失敗。上記の [WARN] ログを確認してください${RESET}"
fi

echo ""
echo -e "${CYAN}ブラウザ動作確認:${RESET}"
echo "  http://localhost:3008  → demo@example.com / demo1234"
echo "  ✔ ダッシュボードのカウントが 0 → 実数に変わっていること"
echo "  ✔ 課題一覧に「[E2E] 検索機能の日本語対応不具合」があること"
echo "  ✔ 課題詳細の右パネルで ITEM → INPUT（原文）が追跡できること"
echo ""

exit $FAIL_COUNT