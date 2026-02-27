#!/usr/bin/env bash
# =============================================================================
# decision-os / 29_patch.sh
# action.py の issue relationship に foreign_keys を直接追記
# + 2本目のFKがどこにあるか全モデルを検索して特定・修正
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
section "1. actions→issues への FK を全モデルから検索"
# =============================================================================
info "全モデルファイルで issues.id への ForeignKey を検索..."
grep -rn 'ForeignKey.*issues\.id' app/models/ || true
echo ""
info "actions テーブルの DB スキーマ確認（psql）..."
PGPASSWORD=devpass_2ed89487 psql \
  -h localhost -p 5439 -U dev -d decisionos \
  -c "\d actions" 2>/dev/null || true

# =============================================================================
section "2. action.py を完全上書き（foreign_keys 明示）"
# =============================================================================
info "action.py を直接書き換え..."

# まず現在の内容を確認して linked_issue_id などの追加列を検出
EXTRA_COLS=$(grep -E "issue.*Column|Column.*issue" app/models/action.py | grep -v "^#" || true)
info "issue関連列: $EXTRA_COLS"

# action.py を完全に正しい内容で上書き
cat > app/models/action.py << 'PYEOF'
from sqlalchemy import Column, String, Text, DateTime, ForeignKey, func
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import relationship
from .base import Base, gen_uuid


class Action(Base):
    __tablename__ = "actions"

    id = Column(UUID(as_uuid=False), primary_key=True, default=gen_uuid)
    item_id = Column(UUID(as_uuid=False), ForeignKey("items.id", ondelete="CASCADE"), nullable=False, unique=True)
    action_type = Column(String(20), nullable=False)
    # CREATE_ISSUE / ANSWER / STORE / REJECT / HOLD / LINK_EXISTING
    decided_by = Column(UUID(as_uuid=False), ForeignKey("users.id"))
    decision_reason = Column(Text)
    decided_at = Column(DateTime(timezone=True), server_default=func.now())
    issue_id = Column(UUID(as_uuid=False), ForeignKey("issues.id", ondelete="SET NULL"), nullable=True)
    linked_issue_id = Column(UUID(as_uuid=False), ForeignKey("issues.id", ondelete="SET NULL"), nullable=True)

    item = relationship("Item", back_populates="action")
    issue = relationship(
        "Issue",
        foreign_keys=[issue_id],
        back_populates="action",
        uselist=False,
    )
    linked_issue = relationship(
        "Issue",
        foreign_keys=[linked_issue_id],
        uselist=False,
    )
    decider = relationship("User", foreign_keys=[decided_by])
PYEOF

ok "action.py 上書き完了"
echo ""
cat app/models/action.py

# =============================================================================
section "3. Issue モデルの back_populates 確認"
# =============================================================================
info "issue.py の action 参照を確認..."
grep -n "action\|Action" app/models/issue.py || true

# issue.py に `action` の back_populates があれば確認
# linked_issue の back_populates は不要（Issueからはリンク不要）

# =============================================================================
section "4. マッパー初期化テスト"
# =============================================================================
python3 << 'PYEOF'
import sys
sys.path.insert(0, '.')
try:
    # モデルを全部インポート
    import app.models
    from app.models.action import Action
    from app.models.issue import Issue
    from sqlalchemy.orm import configure_mappers
    configure_mappers()
    print("[OK] マッパー初期化 成功!")
except Exception as e:
    print(f"[ERROR] {e}")
    import traceback; traceback.print_exc()
    sys.exit(1)
PYEOF

ok "マッパー初期化 OK"

# =============================================================================
section "5. パスワードリセット（psql直接）"
# =============================================================================
NEW_HASH=$(python3 -c "
from passlib.context import CryptContext
ctx = CryptContext(schemes=['bcrypt'], deprecated='auto')
print(ctx.hash('demo1234'))
")

# hashed_password列を試す
R1=$(PGPASSWORD=devpass_2ed89487 psql -h localhost -p 5439 -U dev -d decisionos \
  -c "UPDATE users SET hashed_password='$NEW_HASH' WHERE email='demo@example.com';" 2>&1)
echo "hashed_password: $R1"

if echo "$R1" | grep -q "UPDATE 1"; then
  ok "パスワードリセット完了"
else
  # password_hash列を試す
  R2=$(PGPASSWORD=devpass_2ed89487 psql -h localhost -p 5439 -U dev -d decisionos \
    -c "UPDATE users SET password_hash='$NEW_HASH' WHERE email='demo@example.com';" 2>&1)
  echo "password_hash: $R2"
  echo "$R2" | grep -q "UPDATE 1" && ok "パスワードリセット完了" || err "パスワードリセット失敗"
fi

# =============================================================================
section "6. バックエンド再起動"
# =============================================================================
pkill -f "uvicorn app.main" 2>/dev/null || true
sleep 2
nohup uvicorn app.main:app --host 0.0.0.0 --port 8089 --reload \
  > "$LOG" 2>&1 &
sleep 5

if curl -sf http://localhost:8089/docs > /dev/null 2>&1; then
  ok "バックエンド起動 ✅"
else
  err "起動失敗 — ログ確認:"
  tail -20 "$LOG"
  exit 1
fi

# =============================================================================
section "7. ログイン確認"
# =============================================================================
RESP=$(curl -s -X POST http://localhost:8089/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"demo@example.com","password":"demo1234"}')
echo "レスポンス: $RESP"

TOKEN=$(echo "$RESP" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('access_token',''))" 2>/dev/null || echo "")

if [[ -n "$TOKEN" ]] && [[ "$TOKEN" != "null" ]]; then
  ok "ログイン成功 ✅"
  info "TOKEN: ${TOKEN:0:50}..."
  echo ""
  ok "=== ログイン問題 完全解決！==="
  ok "次: bash ~/projects/decision-os/scripts/27_browser_check.sh"
else
  err "まだ失敗 — backend.log:"
  tail -30 "$LOG"
fi
