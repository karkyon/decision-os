#!/usr/bin/env bash
set -euo pipefail
GREEN='\033[0;32m'; BOLD='\033[1m'; RESET='\033[0m'
ok()      { echo -e "${GREEN}[OK]${RESET}    $*"; }
section() { echo -e "\n${BOLD}========== $* ==========${RESET}"; }

PROJECT_DIR="$HOME/projects/decision-os"
cd "$PROJECT_DIR/backend"
source .venv/bin/activate

section "auth import パスを既存ルーターから確認"

# 他の正常動作しているルーターから get_current_user の import 行を取得
AUTH_IMPORT=$(grep -r "get_current_user" \
  "$PROJECT_DIR/backend/app/api/v1/routers/" \
  --include="*.py" \
  -l | grep -v issues.py | head -1)

echo "参照ファイル: $AUTH_IMPORT"
CORRECT_IMPORT=$(grep "get_current_user" "$AUTH_IMPORT" | grep "^from" | head -1)
echo "正しい import: $CORRECT_IMPORT"

section "issues.py の import 修正"

python3 - << PYEOF
import os, re

path = os.path.expanduser("~/projects/decision-os/backend/app/api/v1/routers/issues.py")
with open(path) as f:
    src = f.read()

# 間違った import を正しいものに置換
correct = """$CORRECT_IMPORT"""
src = re.sub(r'from app\.core\.auth import get_current_user', correct.strip(), src)

with open(path, "w") as f:
    f.write(src)
print("FIXED")
PYEOF
ok "issues.py: auth import 修正完了"

section "バックエンド再起動"
pkill -f "uvicorn" 2>/dev/null || true
sleep 1
nohup uvicorn app.main:app --host 0.0.0.0 --port 8089 --reload \
  > "$PROJECT_DIR/backend.log" 2>&1 &
sleep 4

# ログ確認
echo "--- backend.log (末尾10行) ---"
tail -10 "$PROJECT_DIR/backend.log"
echo "------------------------------"

if curl -s http://localhost:8089/api/v1/issues > /dev/null 2>&1; then
  ok "バックエンド起動 ✅"
else
  echo "[WARN] 起動失敗 → 以下のログを確認:"
  tail -20 "$PROJECT_DIR/backend.log"
  exit 1
fi

section "動作確認"
TOKEN=$(curl -s -X POST http://localhost:8089/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"demo@example.com","password":"demo1234"}' | \
  python3 -c "import sys,json; print(json.load(sys.stdin).get('access_token',''))" 2>/dev/null || echo "")

[ -z "$TOKEN" ] && echo "[WARN] ログイン失敗" && exit 1
ok "ログイン成功"

ISSUE_ID=$(curl -s -H "Authorization: Bearer $TOKEN" \
  "http://localhost:8089/api/v1/issues?limit=1" | \
  python3 -c "
import sys,json
d=json.load(sys.stdin)
lst = d if isinstance(d,list) else d.get('issues',[])
print(lst[0]['id'] if lst else '')
" 2>/dev/null || echo "")

if [ -n "$ISSUE_ID" ]; then
  curl -s -X PATCH -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d '{"issue_type":"epic"}' \
    "http://localhost:8089/api/v1/issues/$ISSUE_ID" | \
    python3 -c "import sys,json; d=json.load(sys.stdin); print('issue_type:', d.get('issue_type','?'))" \
    && ok "PATCH issue_type=epic ✅"

  curl -s -H "Authorization: Bearer $TOKEN" \
    "http://localhost:8089/api/v1/issues/$ISSUE_ID/children" | \
    python3 -c "import sys,json; d=json.load(sys.stdin); print('children:', len(d.get('children',[])))" \
    && ok "GET /children ✅"

  curl -s -H "Authorization: Bearer $TOKEN" \
    "http://localhost:8089/api/v1/issues/$ISSUE_ID/tree" | \
    python3 -c "import sys,json; d=json.load(sys.stdin); print('tree.title:', d.get('title','?')[:30])" \
    && ok "GET /tree ✅"
else
  ok "課題0件 → UIから確認してください"
fi

ok "全修正完了！ http://localhost:3008/issues → 課題詳細 → 🌳 子課題タブ"
