#!/usr/bin/env bash
# =============================================================================
# decision-os / 29_patch2.sh
# issue.py の Issue.action relationship にも foreign_keys を追加
# action.py と issue.py の両方向で foreign_keys を明示して解決
# =============================================================================
set -euo pipefail

GREEN='\033[0;32m'; RED='\033[0;31m'; CYAN='\033[0;36m'
YELLOW='\033[1;33m'; BOLD='\033[1m'; RESET='\033[0m'
ok()      { echo -e "${GREEN}[OK]${RESET}    $*"; }
err()     { echo -e "${RED}[ERR]${RESET}   $*"; }
info()    { echo -e "${CYAN}[INFO]${RESET}  $*"; }
section() { echo -e "\n${BOLD}========== $* ==========${RESET}"; }

BACKEND="$HOME/projects/decision-os/backend"
LOG="$HOME/projects/decision-os/logs/backend.log"
cd "$BACKEND"
source .venv/bin/activate

# =============================================================================
section "1. issue.py の現状確認"
# =============================================================================
info "--- issue.py 全体 ---"
cat app/models/issue.py

# =============================================================================
section "2. issue.py を直接修正（Issue.action に foreign_keys 追加）"
# =============================================================================
cp app/models/issue.py "app/models/issue.py.bak_$(date +%H%M%S)"

python3 << 'PYEOF'
path = "app/models/issue.py"
with open(path) as f:
    content = f.read()

# action = relationship("Action", back_populates="issue") を修正
old = 'action = relationship("Action", back_populates="issue")'
new = 'action = relationship("Action", foreign_keys="[Action.issue_id]", back_populates="issue", uselist=False)'

if old in content:
    content = content.replace(old, new)
    with open(path, 'w') as f:
        f.write(content)
    print("[OK] issue.py: Issue.action に foreign_keys 追加")
elif 'action' in content and 'Action' in content:
    # 別パターンを探す
    import re
    new_content = re.sub(
        r'action\s*=\s*relationship\("Action"([^)]*)\)',
        'action = relationship("Action", foreign_keys="[Action.issue_id]", back_populates="issue", uselist=False)',
        content
    )
    with open(path, 'w') as f:
        f.write(new_content)
    print("[OK] issue.py: Issue.action に foreign_keys 追加（re版）")
else:
    print("[SKIP] action relationship が見つからない")

print("--- 修正後 ---")
with open(path) as f:
    print(f.read())
PYEOF

# =============================================================================
section "3. マッパー初期化テスト"
# =============================================================================
info "SQLAlchemy マッパー初期化テスト..."
python3 << 'PYEOF'
import sys
sys.path.insert(0, '.')
try:
    import app.models
    from sqlalchemy.orm import configure_mappers
    configure_mappers()
    print("[OK] マッパー初期化 成功!")
except Exception as e:
    print(f"[ERROR] {type(e).__name__}: {e}")
    # まだエラーが出る場合はどのrelationshipか特定
    import traceback
    tb = traceback.format_exc()
    # relationship名を抽出
    import re
    rel = re.search(r"relationship (\S+)", str(e))
    if rel:
        print(f"問題のrelationship: {rel.group(1)}")
    sys.exit(1)
PYEOF

# =============================================================================
section "4. パスワードリセット（psql直接）"
# =============================================================================
NEW_HASH=$(python3 -c "
from passlib.context import CryptContext
ctx = CryptContext(schemes=['bcrypt'], deprecated='auto')
print(ctx.hash('demo1234'))
")
info "ハッシュ生成: ${NEW_HASH:0:30}..."

# DB列名を確認してから更新
COLS=$(PGPASSWORD=devpass_2ed89487 psql \
  -h localhost -p 5439 -U dev -d decisionos \
  -c "SELECT column_name FROM information_schema.columns WHERE table_name='users' AND column_name LIKE '%password%';" \
  -t 2>/dev/null | tr -d ' ')
info "パスワード列名: $COLS"

for col in hashed_password password_hash password; do
  R=$(PGPASSWORD=devpass_2ed89487 psql \
    -h localhost -p 5439 -U dev -d decisionos \
    -c "UPDATE users SET $col='$NEW_HASH' WHERE email='demo@example.com';" 2>&1)
  if echo "$R" | grep -q "UPDATE 1"; then
    ok "パスワードリセット完了 (列: $col)"
    break
  fi
done

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
  err "起動失敗 — ログ:"
  tail -25 "$LOG"
  exit 1
fi

# =============================================================================
section "6. ログイン確認"
# =============================================================================
RESP=$(curl -s -X POST http://localhost:8089/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"demo@example.com","password":"demo1234"}')
echo "レスポンス: $RESP"

TOKEN=$(echo "$RESP" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('access_token',''))" 2>/dev/null || echo "")

if [[ -n "$TOKEN" ]] && [[ "$TOKEN" != "null" ]]; then
  ok "ログイン成功 ✅"
  echo ""
  ok "=== ログイン問題 完全解決！==="
  echo ""
  ok "次: bash ~/projects/decision-os/scripts/27_browser_check.sh"
else
  err "まだ失敗 — backend.log:"
  tail -30 "$LOG"
fi
