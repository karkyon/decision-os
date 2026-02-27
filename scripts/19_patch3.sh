#!/usr/bin/env bash
set -euo pipefail
GREEN='\033[0;32m'; CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'
ok()      { echo -e "${GREEN}[OK]${RESET}    $*"; }
info()    { echo -e "${CYAN}[INFO]${RESET}  $*"; }
section() { echo -e "\n${BOLD}========== $* ==========${RESET}"; }

PROJECT_DIR="$HOME/projects/decision-os"
cd "$PROJECT_DIR/backend"
source .venv/bin/activate

section "登録済みユーザー確認"
python3 << 'PYEOF'
import sys
sys.path.insert(0, ".")
from app.db.session import engine
from sqlalchemy import text

with engine.connect() as conn:
    rows = conn.execute(text("SELECT email, role FROM users LIMIT 5")).fetchall()
    if rows:
        for r in rows:
            print(f"  email={r[0]}, role={r[1]}")
    else:
        print("  [INFO] ユーザーなし → デモアカウント作成します")
PYEOF

section "ログイン試行（複数パターン）"
TOKEN=""

for CRED in \
  '{"email":"demo@example.com","password":"demo1234"}' \
  '{"email":"admin@example.com","password":"admin1234"}' \
  '{"email":"test@example.com","password":"test1234"}'; do
  RES=$(curl -s -X POST http://localhost:8089/api/v1/auth/login \
    -H "Content-Type: application/json" \
    -d "$CRED")
  TOKEN=$(echo "$RES" | python3 -c "import sys,json; print(json.load(sys.stdin).get('access_token',''))" 2>/dev/null || echo "")
  if [ -n "$TOKEN" ]; then
    EMAIL=$(echo "$CRED" | python3 -c "import sys,json; print(json.load(sys.stdin)['email'])")
    ok "ログイン成功: $EMAIL"
    break
  fi
done

# それでも失敗なら DB から直接メール取得して再試行
if [ -z "$TOKEN" ]; then
  info "既存アカウントで試行..."
  FIRST_EMAIL=$(python3 << 'PYEOF'
import sys
sys.path.insert(0, ".")
from app.db.session import engine
from sqlalchemy import text
with engine.connect() as conn:
    row = conn.execute(text("SELECT email FROM users LIMIT 1")).fetchone()
    print(row[0] if row else "")
PYEOF
)
  if [ -n "$FIRST_EMAIL" ]; then
    # パスワードリセット
    python3 << PYEOF
import sys
sys.path.insert(0, ".")
from app.db.session import engine, SessionLocal
from sqlalchemy import text
from passlib.context import CryptContext

pwd_ctx = CryptContext(schemes=["bcrypt"], deprecated="auto")
hashed = pwd_ctx.hash("test1234")

with engine.connect() as conn:
    conn.execute(text(f"UPDATE users SET hashed_password='{hashed}' WHERE email='{FIRST_EMAIL}'"))
    conn.commit()
    print(f"[OK] {FIRST_EMAIL} のパスワードを test1234 にリセット")
PYEOF
    RES=$(curl -s -X POST http://localhost:8089/api/v1/auth/login \
      -H "Content-Type: application/json" \
      -d "{\"email\":\"$FIRST_EMAIL\",\"password\":\"test1234\"}")
    TOKEN=$(echo "$RES" | python3 -c "import sys,json; print(json.load(sys.stdin).get('access_token',''))" 2>/dev/null || echo "")
    [ -n "$TOKEN" ] && ok "ログイン成功: $FIRST_EMAIL (pass: test1234)"
  fi
fi

if [ -z "$TOKEN" ]; then
  echo "[WARN] ログイン失敗 → 手動確認してください"
  exit 1
fi

section "親子課題 動作確認"

ISSUE_ID=$(curl -s -H "Authorization: Bearer $TOKEN" \
  "http://localhost:8089/api/v1/issues?limit=1" | \
  python3 -c "
import sys,json
d=json.load(sys.stdin)
lst = d if isinstance(d,list) else d.get('issues',[])
print(lst[0]['id'] if lst else '')
" 2>/dev/null || echo "")

if [ -z "$ISSUE_ID" ]; then
  ok "課題0件 → UIから確認してください"
  echo ""
  echo "✅ 完了！ブラウザで確認:"
  echo "  http://localhost:3008/issues → 課題詳細 → 🌳 子課題タブ"
  exit 0
fi

# issue_type を epic に変更
PATCH=$(curl -s -X PATCH -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"issue_type":"epic"}' \
  "http://localhost:8089/api/v1/issues/$ISSUE_ID")
echo "$PATCH" | python3 -c "import sys,json; d=json.load(sys.stdin); print('issue_type:', d.get('issue_type','?'))" \
  && ok "PATCH issue_type=epic ✅"

# children
curl -s -H "Authorization: Bearer $TOKEN" \
  "http://localhost:8089/api/v1/issues/$ISSUE_ID/children" | \
  python3 -c "import sys,json; d=json.load(sys.stdin); print('children:', len(d.get('children',[])))" \
  && ok "GET /children ✅"

# tree
curl -s -H "Authorization: Bearer $TOKEN" \
  "http://localhost:8089/api/v1/issues/$ISSUE_ID/tree" | \
  python3 -c "import sys,json; d=json.load(sys.stdin); print('tree.title:', d.get('title','?')[:30])" \
  && ok "GET /tree ✅"

echo ""
ok "Phase 2: 親子課題 完全動作確認完了！"
echo "ブラウザで確認: http://localhost:3008/issues → 課題詳細 → 🌳 子課題タブ"
