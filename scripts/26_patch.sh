#!/usr/bin/env bash
# =============================================================================
# decision-os / 26_patch.sh
# ログイン Internal Server Error の直接修正
# 前回 26_login_fix.sh が "Apache: unbound variable" でクラッシュし
# パスワードリセットが未実行だったため、ここで直接修正する
# =============================================================================
set -euo pipefail

GREEN='\033[0;32m'; RED='\033[0;31m'; CYAN='\033[0;36m'
YELLOW='\033[1;33m'; BOLD='\033[1m'; RESET='\033[0m'

ok()      { echo -e "${GREEN}[OK]${RESET}    $*"; }
err()     { echo -e "${RED}[ERR]${RESET}   $*"; }
info()    { echo -e "${CYAN}[INFO]${RESET}  $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
section() { echo -e "\n${BOLD}========== $* ==========${RESET}"; }

PROJECT_DIR="$HOME/projects/decision-os"
BACKEND="$PROJECT_DIR/backend"
LOG="$PROJECT_DIR/logs/backend.log"

cd "$BACKEND"
source .venv/bin/activate

# =============================================================================
section "1. bcrypt バージョン確認（正確な方法）"
# =============================================================================
BCRYPT_VER=$(python3 -c "import bcrypt; print(bcrypt.__version__)" 2>/dev/null || echo "unknown")
PASSLIB_VER=$(python3 -c "import passlib; print(passlib.__version__)" 2>/dev/null || echo "unknown")
info "bcrypt  : $BCRYPT_VER"
info "passlib : $PASSLIB_VER"
ok "バージョン確認完了"

# =============================================================================
section "2. passlib + bcrypt 動作確認"
# =============================================================================
python3 -c "
from passlib.context import CryptContext
ctx = CryptContext(schemes=['bcrypt'], deprecated='auto')
h = ctx.hash('demo1234')
ok = ctx.verify('demo1234', h)
print(f'verify: {ok}')
assert ok, 'verify 失敗!'
print('passlib + bcrypt OK')
"
ok "passlib + bcrypt 動作確認 OK"

# =============================================================================
section "3. backend.log から Internal Server Error の原因特定"
# =============================================================================
info "auth 関連エラーを抽出..."
grep -i "error\|exception\|traceback\|500\|auth\|password\|hash\|verify" "$LOG" \
  | grep -v "^INFO:" | tail -40 || true
echo ""
info "--- 直近30行 ---"
tail -30 "$LOG"

# =============================================================================
section "4. auth.py / security.py の verify_password 確認"
# =============================================================================
# verify_password がある可能性のあるファイルを全探索
for f in \
  "$BACKEND/app/api/v1/routers/auth.py" \
  "$BACKEND/app/core/security.py" \
  "$BACKEND/app/core/auth.py" \
  "$BACKEND/app/utils/security.py"; do
  if [[ -f "$f" ]]; then
    info "=== $f ==="
    grep -n "verify_password\|pwd_context\|CryptContext\|hashed_password\|password_hash\|bcrypt\|passlib" "$f" || true
  fi
done

# =============================================================================
section "5. DBのユーザー情報確認"
# =============================================================================
python3 << 'PYEOF'
import sys
sys.path.insert(0, '.')
try:
    from app.db.session import SessionLocal
    from app.models.user import User
    db = SessionLocal()
    u = db.query(User).filter(User.email == 'demo@example.com').first()
    if u:
        print(f"[FOUND] id={u.id}")
        print(f"        role={u.role}")
        # passwordフィールドを探す
        for attr in ['hashed_password', 'password_hash', 'password']:
            val = getattr(u, attr, None)
            if val:
                print(f"        {attr}={val[:30]}... (len={len(val)})")
                break
        else:
            print("        [WARN] パスワードフィールドが見つかりません")
            print(f"        利用可能属性: {[a for a in dir(u) if not a.startswith('_')]}")
    else:
        print("[NOT_FOUND] demo@example.com は存在しません")
    db.close()
except Exception as e:
    print(f"[ERROR] {e}")
    import traceback; traceback.print_exc()
PYEOF

# =============================================================================
section "6. パスワード強制リセット"
# =============================================================================
info "demo@example.com のパスワードを demo1234 で再ハッシュ..."
python3 << 'PYEOF'
import sys
sys.path.insert(0, '.')
from passlib.context import CryptContext
from app.db.session import SessionLocal
from app.models.user import User

ctx = CryptContext(schemes=['bcrypt'], deprecated='auto')
new_hash = ctx.hash('demo1234')
print(f"新しいハッシュ: {new_hash[:30]}...")

db = SessionLocal()
try:
    u = db.query(User).filter(User.email == 'demo@example.com').first()
    if not u:
        print("[ERROR] ユーザーが存在しない — まず register してください")
        sys.exit(1)

    # フィールド名を自動判定
    for attr in ['hashed_password', 'password_hash', 'password']:
        if hasattr(u, attr):
            setattr(u, attr, new_hash)
            print(f"[OK] {attr} を更新")
            break
    else:
        print("[ERROR] パスワードフィールドが見つかりません")
        sys.exit(1)

    db.commit()
    print("[DONE] パスワードリセット完了")
finally:
    db.close()
PYEOF
ok "パスワードリセット完了"

# =============================================================================
section "7. auth.py の verify_password ロジックを直接確認・修正"
# =============================================================================
# auth.py を読んでverify_passwordの実装を確認
AUTH_FILE=""
for f in \
  "$BACKEND/app/api/v1/routers/auth.py" \
  "$BACKEND/app/core/security.py"; do
  if [[ -f "$f" ]]; then
    AUTH_FILE="$f"
    break
  fi
done

if [[ -n "$AUTH_FILE" ]]; then
  info "auth ファイル: $AUTH_FILE"
  info "--- verify_password 周辺 ---"
  grep -n -A5 "verify_password\|pwd_context" "$AUTH_FILE" || true
fi

# security.py に pwd_context がなければ作成
SECURITY_FILE="$BACKEND/app/core/security.py"
if ! grep -q "CryptContext\|pwd_context" "$SECURITY_FILE" 2>/dev/null; then
  warn "security.py に CryptContext がない — 追加します"
  cat >> "$SECURITY_FILE" << 'PYEOF'

# --- パスワードハッシュ（passlib + bcrypt） ---
from passlib.context import CryptContext
pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")

def verify_password(plain: str, hashed: str) -> bool:
    return pwd_context.verify(plain, hashed)

def get_password_hash(password: str) -> str:
    return pwd_context.hash(password)
PYEOF
  ok "security.py に CryptContext 追加"
fi

# =============================================================================
section "8. バックエンド再起動"
# =============================================================================
pkill -f "uvicorn app.main" 2>/dev/null || true
sleep 2
nohup uvicorn app.main:app --host 0.0.0.0 --port 8089 --reload \
  > "$LOG" 2>&1 &
sleep 4

if curl -sf http://localhost:8089/docs > /dev/null 2>&1; then
  ok "バックエンド起動 ✅"
else
  err "バックエンド起動失敗"
  tail -20 "$LOG"
  exit 1
fi

# =============================================================================
section "9. ログイン動作確認"
# =============================================================================
info "demo@example.com / demo1234 でログイン..."
RESP=$(curl -s -X POST http://localhost:8089/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"demo@example.com","password":"demo1234"}')
echo "レスポンス: $RESP"

TOKEN=$(python3 -c "
import sys, json
try:
    d = json.loads('$RESP'.replace(\"'\", '\"'))
    print(d.get('access_token', ''))
except:
    pass
" 2>/dev/null || \
python3 -c "
import json, sys
d = json.loads(sys.stdin.read())
print(d.get('access_token',''))
" <<< "$RESP" 2>/dev/null || echo "")

if [[ -n "$TOKEN" ]] && [[ "$TOKEN" != "null" ]] && [[ "$TOKEN" != "" ]]; then
  ok "ログイン成功 ✅"
  info "TOKEN: ${TOKEN:0:60}..."
  echo ""
  ok "=== ログイン問題 解決！ ==="
  ok "次: bash ~/projects/decision-os/scripts/27_browser_check.sh"
else
  err "まだログイン失敗 — backend.log を確認します"
  echo ""
  info "--- backend.log 直近40行 ---"
  tail -40 "$LOG"
  echo ""
  err "auth.py の login エンドポイントを手動確認してください"
  err "cat $BACKEND/app/api/v1/routers/auth.py"
fi
