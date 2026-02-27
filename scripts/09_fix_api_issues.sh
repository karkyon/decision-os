#!/bin/bash
# decision-os API修正スクリプト
# 問題: /inputs がproject_id必須で失敗, /analyze がtextのみ非対応, /dashboard/counts 未実装
# 実行: bash 09_fix_api_issues.sh

set -e
BASE=~/projects/decision-os/backend
cd $BASE
source .venv/bin/activate

echo "========== API構造確認 =========="
find app -name "*.py" | grep -v __pycache__ | sort

# TOKEN取得
TOKEN=$(curl -s -X POST http://localhost:8089/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"demo@example.com","password":"demo1234"}' \
  | python3 -c "import sys,json; print(json.load(sys.stdin).get('access_token','ERROR'))")
echo "TOKEN: ${TOKEN:0:30}..."

echo ""
echo "========== project一覧確認 =========="
PROJECT_RESP=$(curl -s http://localhost:8089/api/v1/projects \
  -H "Authorization: Bearer $TOKEN")
echo "$PROJECT_RESP" | python3 -m json.tool 2>/dev/null || echo "$PROJECT_RESP"

PROJECT_ID=$(echo "$PROJECT_RESP" | python3 -c \
  "import sys,json; d=json.load(sys.stdin); print(d[0]['id'] if isinstance(d,list) and d else d.get('items',[{}])[0].get('id','') if isinstance(d,dict) else '')" 2>/dev/null || echo "")
echo "PROJECT_ID: $PROJECT_ID"

echo ""
echo "========== project_idなしでinput登録テスト =========="
curl -s -X POST http://localhost:8089/api/v1/inputs \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"text":"ログインページのボタンが押せない","source_type":"email"}' | python3 -m json.tool 2>/dev/null

echo ""
echo "========== project_idありでinput登録テスト =========="
if [ -n "$PROJECT_ID" ]; then
  INPUT_RESP=$(curl -s -X POST http://localhost:8089/api/v1/inputs \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d "{\"text\":\"ログインページのボタンが押せない。また検索機能も追加してほしい\",\"source_type\":\"email\",\"project_id\":\"$PROJECT_ID\"}")
  echo "$INPUT_RESP" | python3 -m json.tool 2>/dev/null || echo "$INPUT_RESP"
  INPUT_ID=$(echo "$INPUT_RESP" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('id','ERROR'))" 2>/dev/null || echo "ERROR")
  echo "INPUT_ID: $INPUT_ID"
else
  echo "[SKIP] PROJECT_IDが取得できなかった"
fi

echo ""
echo "========== analyze (input_id方式) =========="
if [ -n "${INPUT_ID:-}" ] && [ "$INPUT_ID" != "ERROR" ]; then
  curl -s -X POST http://localhost:8089/api/v1/analyze \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d "{\"input_id\": \"$INPUT_ID\"}" | python3 -m json.tool 2>/dev/null
fi

echo ""
echo "========== issues一覧 (project_id付き) =========="
if [ -n "$PROJECT_ID" ]; then
  curl -s "http://localhost:8089/api/v1/issues?project_id=$PROJECT_ID" \
    -H "Authorization: Bearer $TOKEN" | python3 -m json.tool 2>/dev/null
fi

echo ""
echo "========== dashboard/counts =========="
curl -s "http://localhost:8089/api/v1/dashboard/counts?project_id=${PROJECT_ID:-}" \
  -H "Authorization: Bearer $TOKEN" | python3 -m json.tool 2>/dev/null

echo ""
echo "========== 完了 =========="
