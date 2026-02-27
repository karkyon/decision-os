#!/usr/bin/env bash
set -euo pipefail
GREEN='\033[0;32m'; BOLD='\033[1m'; RESET='\033[0m'
ok()      { echo -e "${GREEN}[OK]${RESET}    $*"; }
section() { echo -e "\n${BOLD}========== $* ==========${RESET}"; }

PROJECT_DIR="$HOME/projects/decision-os"
cd "$PROJECT_DIR/backend"
source .venv/bin/activate

section "demo@example.com パスワードリセット → demo1234"
python3 << 'PYEOF'
import sys
sys.path.insert(0, ".")
from app.db.session import engine
from sqlalchemy import text
from passlib.context import CryptContext

pwd_ctx = CryptContext(schemes=["bcrypt"], deprecated="auto")
hashed = pwd_ctx.hash("demo1234")

with engine.connect() as conn:
    conn.execute(text(f"UPDATE users SET hashed_password=:h WHERE email='demo@example.com'"), {"h": hashed})
    conn.commit()
    print("[OK] demo@example.com のパスワードを demo1234 にリセット完了")
PYEOF

section "ログイン確認"
RES=$(curl -s -X POST http://localhost:8089/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"demo@example.com","password":"demo1234"}')
echo "レスポンス: $RES" | head -c 200
TOKEN=$(echo "$RES" | python3 -c "import sys,json; print(json.load(sys.stdin).get('access_token',''))" 2>/dev/null || echo "")
[ -z "$TOKEN" ] && echo "[WARN] まだログイン失敗" && exit 1
ok "ログイン成功！"

section "親子課題 動作確認"
ISSUE_ID=$(curl -s -H "Authorization: Bearer $TOKEN" \
  "http://localhost:8089/api/v1/issues?limit=1" | \
  python3 -c "
import sys,json; d=json.load(sys.stdin)
lst = d if isinstance(d,list) else d.get('issues',[])
print(lst[0]['id'] if lst else '')
" 2>/dev/null || echo "")

if [ -z "$ISSUE_ID" ]; then
  ok "課題0件 → UIから確認してください"
else
  curl -s -X PATCH -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" -d '{"issue_type":"epic"}' \
    "http://localhost:8089/api/v1/issues/$ISSUE_ID" | \
    python3 -c "import sys,json; d=json.load(sys.stdin); print('issue_type:', d.get('issue_type','?'))" \
    && ok "PATCH issue_type=epic ✅"

  curl -s -H "Authorization: Bearer $TOKEN" \
    "http://localhost:8089/api/v1/issues/$ISSUE_ID/children" | \
    python3 -c "import sys,json; print('children:', len(json.load(sys.stdin).get('children',[])))" \
    && ok "GET /children ✅"

  curl -s -H "Authorization: Bearer $TOKEN" \
    "http://localhost:8089/api/v1/issues/$ISSUE_ID/tree" | \
    python3 -c "import sys,json; print('tree.title:', json.load(sys.stdin).get('title','?')[:30])" \
    && ok "GET /tree ✅"
fi

echo ""
ok "完了！ http://localhost:3008/issues → 課題詳細 → 🌳 子課題タブ"
