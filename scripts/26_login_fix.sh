#!/usr/bin/env bash
# =============================================================================
# decision-os / 26_login_fix.sh
# ログイン問題の診断・自動修正
# 対象: demo@example.com / demo1234 で Internal Server Error になるケース
# 確認項目:
#   1. backend.log の直近エラー内容確認
#   2. DB内のユーザーレコード確認（パスワードハッシュ形式）
#   3. bcrypt バージョン互換性チェック
#   4. auth.py の verify_password ロジック確認
#   5. パスワードハッシュ再生成（強制リセット）
#   6. ログイン動作確認
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
section "1. backend.log の直近エラー確認"
# =============================================================================
if [[ -f "$LOG" ]]; then
  info "--- 直近50行（ERRORのみ抽出）---"
  grep -i "error\|exception\|traceback\|500" "$LOG" | tail -30 || true
  echo ""
  info "--- 直近20行（全体）---"
  tail -20 "$LOG"
else
  warn "backend.log が見つかりません: $LOG"
fi

# =============================================================================
section "2. bcrypt バージョン確認"
# =============================================================================
BCRYPT_VER=$(pip show bcrypt 2>/dev/null | grep Version | awk '{print $2}')
PASSLIB_VER=$(pip show passlib 2>/dev/null | grep Version | awk '{print $2}')
info "bcrypt   : $BCRYPT_VER"
info "passlib  : $PASSLIB_VER"

# bcrypt 4.x系が安全。5.x は passlib と互換性問題あり
BCRYPT_MAJOR=$(echo "$BCRYPT_VER" | cut -d. -f1)
if [[ "$BCRYPT_MAJOR" -ge 5 ]]; then
  warn "bcrypt $BCRYPT_VER は passlib と互換性問題あり → 4.0.1 に固定します"
  pip install "bcrypt==4.0.1" -q
  ok "bcrypt 4.0.1 インストール完了"
else
  ok "bcrypt $BCRYPT_VER — 問題なし"
fi

# =============================================================================
section "3. auth.py の verify_password ロジック確認"
# =============================================================================
AUTH_FILE="$BACKEND/app/api/v1/routers/auth.py"
CORE_SECURITY="$BACKEND/app/core/security.py"

# security.py または auth.py に verify_password が存在するか確認
for f in "$AUTH_FILE" "$CORE_SECURITY" "$BACKEND/app/core/auth.py"; do
  if [[ -f "$f" ]]; then
    info "確認: $f"
    grep -n "verify_password\|pwd_context\|bcrypt\|passlib\|CryptContext" "$f" || true
  fi
done

# CryptContext の schemes 確認
PY_CHECK=$(python3 -c "
from passlib.context import CryptContext
ctx = CryptContext(schemes=['bcrypt'], deprecated='auto')
hashed = ctx.hash('demo1234')
result = ctx.verify('demo1234', hashed)
print('verify OK:', result)
print('hash sample:', hashed[:30], '...')
" 2>&1)
echo "$PY_CHECK"
if echo "$PY_CHECK" | grep -q "verify OK: True"; then
  ok "passlib + bcrypt の動作確認 OK"
else
  err "passlib + bcrypt に問題あり"
fi

# =============================================================================
section "4. DB ユーザーレコード確認"
# =============================================================================
info "demo@example.com のハッシュ形式を確認..."
DB_HASH=$(python3 -c "
import sys
sys.path.insert(0, '.')
from app.db.session import SessionLocal
from app.models.user import User
db = SessionLocal()
u = db.query(User).filter(User.email == 'demo@example.com').first()
if u:
    print('FOUND')
    print('id:', u.id)
    print('role:', u.role)
    h = u.hashed_password if hasattr(u, 'hashed_password') else u.password_hash
    print('hash_prefix:', h[:20] if h else 'NULL')
    print('hash_len:', len(h) if h else 0)
else:
    print('NOT_FOUND')
db.close()
" 2>&1)
echo "$DB_HASH"

# =============================================================================
section "5. パスワード強制リセット（demo1234 で再ハッシュ）"
# =============================================================================
info "demo@example.com のパスワードを demo1234 で再生成..."
RESET_RESULT=$(python3 -c "
import sys
sys.path.insert(0, '.')
from passlib.context import CryptContext
from app.db.session import SessionLocal
from app.models.user import User

ctx = CryptContext(schemes=['bcrypt'], deprecated='auto')
new_hash = ctx.hash('demo1234')

db = SessionLocal()
u = db.query(User).filter(User.email == 'demo@example.com').first()
if not u:
    # ユーザーが存在しない場合は作成
    import uuid
    u = User(
        id=str(uuid.uuid4()),
        email='demo@example.com',
        role='pm',
    )
    db.add(u)
    print('CREATED new user')
else:
    print('UPDATING existing user')

# hashed_password か password_hash か自動判定
if hasattr(u, 'hashed_password'):
    u.hashed_password = new_hash
elif hasattr(u, 'password_hash'):
    u.password_hash = new_hash
else:
    print('ERROR: password field not found')
    db.close()
    exit(1)

db.commit()
db.close()
print('DONE: hash =', new_hash[:30], '...')
" 2>&1)
echo "$RESET_RESULT"

if echo "$RESET_RESULT" | grep -q "DONE"; then
  ok "パスワードリセット完了"
else
  err "パスワードリセット失敗 — 上記エラーを確認してください"
fi

# =============================================================================
section "6. バックエンド再起動"
# =============================================================================
pkill -f "uvicorn app.main" 2>/dev/null || true
sleep 2
nohup uvicorn app.main:app --host 0.0.0.0 --port 8089 --reload \
  > "$PROJECT_DIR/logs/backend.log" 2>&1 &
sleep 4

if curl -sf http://localhost:8089/health > /dev/null 2>&1 || \
   curl -sf http://localhost:8089/docs  > /dev/null 2>&1; then
  ok "バックエンド起動 ✅"
else
  err "バックエンド起動失敗 — ログ確認: tail -30 $LOG"
  exit 1
fi

# =============================================================================
section "7. ログイン動作確認"
# =============================================================================
info "demo@example.com / demo1234 でログイン試行..."
LOGIN_RESP=$(curl -s -X POST http://localhost:8089/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"demo@example.com","password":"demo1234"}' 2>&1)
echo "レスポンス: $LOGIN_RESP"

TOKEN=$(echo "$LOGIN_RESP" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(d.get('access_token',''))
except:
    print('')
" 2>/dev/null)

if [[ -n "$TOKEN" ]] && [[ "$TOKEN" != "null" ]]; then
  ok "ログイン成功 ✅"
  info "TOKEN: ${TOKEN:0:50}..."
  echo ""
  ok "=== 26_login_fix.sh 完了 ==="
  ok "次のステップ: bash ~/projects/decision-os/scripts/27_browser_check.sh"
else
  err "ログイン失敗 — レスポンス: $LOGIN_RESP"
  info "backend.log を確認: tail -40 $LOG"
  exit 1
fi
