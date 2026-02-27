#!/bin/bash
# 27_patch4.sh — conversations.content→body リネーム + decisions カラム追加
set -euo pipefail
BASE_URL="http://localhost:8089/api/v1"
PASS=0; FAIL=0; WARN=0

log_ok()   { echo "[OK]    $*"; PASS=$((PASS+1)); }
log_fail() { echo "[FAIL]  $*"; FAIL=$((FAIL+1)); }
log_warn() { echo "[WARN]  $*"; WARN=$((WARN+1)); }
log_info() { echo "[INFO]  $*"; }

cd ~/projects/decision-os/backend
source .venv/bin/activate 2>/dev/null || true

# ===== 1. Conversation モデル: content → body にリネーム =====
echo "========== 1. Conversation モデル修正（content → body） =========="
CONV_MODEL=~/projects/decision-os/backend/app/models/conversation.py
cp "$CONV_MODEL" "${CONV_MODEL}.bak_$(date +%H%M%S)"

cat > "$CONV_MODEL" << 'PYEOF'
from sqlalchemy import Column, String, Text, DateTime, ForeignKey, func
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import relationship
from .base import Base, gen_uuid

class Conversation(Base):
    __tablename__ = "conversations"

    id = Column(UUID(as_uuid=False), primary_key=True, default=gen_uuid)
    issue_id = Column(UUID(as_uuid=False), ForeignKey("issues.id"))
    author_id = Column(UUID(as_uuid=False), ForeignKey("users.id"), nullable=False)
    body = Column(Text, nullable=False, default="")
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), onupdate=func.now())

    issue = relationship("Issue", back_populates="conversations")
    author = relationship("User", foreign_keys=[author_id])
PYEOF
log_ok "conversation.py 更新完了（body カラムのみ）"

# ===== 2. Decision モデル: ルーター仕様に合わせて更新 =====
echo ""
echo "========== 2. Decision モデル修正（ルーター仕様に統一） =========="
DECISION_MODEL=~/projects/decision-os/backend/app/models/decision.py
cp "$DECISION_MODEL" "${DECISION_MODEL}.bak_$(date +%H%M%S)"

cat > "$DECISION_MODEL" << 'PYEOF'
from sqlalchemy import Column, String, Text, DateTime, ForeignKey, func
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import relationship
from .base import Base, gen_uuid

class Decision(Base):
    __tablename__ = "decisions"

    id = Column(UUID(as_uuid=False), primary_key=True, default=gen_uuid)
    project_id = Column(UUID(as_uuid=False), ForeignKey("projects.id"), nullable=False)
    decision_text = Column(Text, nullable=False)
    reason = Column(Text, nullable=False)
    decided_by = Column(UUID(as_uuid=False), ForeignKey("users.id"), nullable=False)
    related_request_id = Column(UUID(as_uuid=False), ForeignKey("inputs.id"), nullable=True)
    related_issue_id = Column(UUID(as_uuid=False), ForeignKey("issues.id"), nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())

    issue = relationship("Issue", back_populates="decisions", foreign_keys=[related_issue_id])
    decider = relationship("User", foreign_keys=[decided_by])
PYEOF
log_ok "decision.py 更新完了"

# ===== 3. DB マイグレーション =====
echo ""
echo "========== 3. DB マイグレーション =========="
python3 -c "
import sys; sys.path.insert(0, '.')
from app.db.session import engine
from sqlalchemy import text, inspect

insp = inspect(engine)

# --- conversations ---
conv_cols = [c['name'] for c in insp.get_columns('conversations')]
print('conversations 現在:', conv_cols)
with engine.begin() as conn:
    # content を body にリネーム（既存データ保持）
    if 'content' in conv_cols and 'body' not in conv_cols:
        conn.execute(text('ALTER TABLE conversations RENAME COLUMN content TO body'))
        print('[OK] conversations.content → body リネーム')
    elif 'body' not in conv_cols:
        conn.execute(text(\"ALTER TABLE conversations ADD COLUMN body TEXT NOT NULL DEFAULT ''\"))
        print('[OK] conversations.body カラム追加')
    else:
        # body も content も両方ある場合: content の NOT NULL を外す
        conn.execute(text('ALTER TABLE conversations ALTER COLUMN content DROP NOT NULL'))
        print('[OK] conversations.content の NOT NULL を解除')
    # updated_at がなければ追加
    if 'updated_at' not in conv_cols:
        conn.execute(text('ALTER TABLE conversations ADD COLUMN updated_at TIMESTAMP WITH TIME ZONE'))
        print('[OK] conversations.updated_at 追加')

# --- decisions ---
dec_cols = [c['name'] for c in insp.get_columns('decisions')]
print('decisions 現在:', dec_cols)
with engine.begin() as conn:
    if 'project_id' not in dec_cols:
        # まず NULL 許容で追加してからデフォルト設定
        conn.execute(text('ALTER TABLE decisions ADD COLUMN project_id UUID REFERENCES projects(id)'))
        print('[OK] decisions.project_id 追加')
    if 'decision_text' not in dec_cols:
        conn.execute(text(\"ALTER TABLE decisions ADD COLUMN decision_text TEXT NOT NULL DEFAULT ''\"))
        print('[OK] decisions.decision_text 追加')
    if 'related_issue_id' not in dec_cols:
        conn.execute(text('ALTER TABLE decisions ADD COLUMN related_issue_id UUID REFERENCES issues(id)'))
        print('[OK] decisions.related_issue_id 追加')
    if 'related_request_id' not in dec_cols:
        conn.execute(text('ALTER TABLE decisions ADD COLUMN related_request_id UUID REFERENCES inputs(id)'))
        print('[OK] decisions.related_request_id 追加')
    # change_type の NOT NULL 制約を解除（旧カラム）
    if 'change_type' in dec_cols:
        conn.execute(text('ALTER TABLE decisions ALTER COLUMN change_type DROP NOT NULL'))
        print('[OK] decisions.change_type NOT NULL 解除')
    # issue_id の NOT NULL も解除（旧カラム）
    if 'issue_id' in dec_cols:
        conn.execute(text('ALTER TABLE decisions ALTER COLUMN issue_id DROP NOT NULL'))
        print('[OK] decisions.issue_id NOT NULL 解除')

print('マイグレーション完了')
"

# ===== 4. Issue モデルの decisions back_populates を確認・修正 =====
echo ""
echo "========== 4. Issue モデルの decisions relationship 確認 =========="
ISSUE_MODEL=~/projects/decision-os/backend/app/models/issue.py
log_info "decisions relationship の foreign_keys 確認..."
grep -n "decisions" "$ISSUE_MODEL"

# Issue.decisions に foreign_keys がなければ追加
if grep -q "decisions = relationship" "$ISSUE_MODEL"; then
  python3 -c "
content = open('$ISSUE_MODEL').read()
old = 'decisions = relationship(\"Decision\", back_populates=\"issue\")'
new = 'decisions = relationship(\"Decision\", back_populates=\"issue\", foreign_keys=\"[Decision.related_issue_id]\")'
if old in content:
    content = content.replace(old, new)
    open('$ISSUE_MODEL', 'w').write(content)
    print('[OK] Issue.decisions に foreign_keys 追加')
else:
    print('[SKIP] 既に修正済みまたは別の形式')
    # 現在の decisions 行を表示
    for i, line in enumerate(content.split(chr(10)), 1):
        if 'decisions' in line:
            print(f'  line {i}: {line}')
"
fi

# ===== 5. マッパー初期化テスト =====
echo ""
echo "========== 5. マッパー初期化テスト =========="
python3 -c "
import sys; sys.path.insert(0, '.')
try:
    from sqlalchemy.orm import configure_mappers
    import app.models
    configure_mappers()
    print('[OK] マッパー初期化 成功')
except Exception as e:
    print('[ERROR]', type(e).__name__, str(e))
    import traceback; traceback.print_exc()
"

# ===== 6. バックエンド再起動 =====
echo ""
echo "========== 6. バックエンド再起動 =========="
pkill -f "uvicorn app.main" 2>/dev/null || true
sleep 2
LOGFILE=$(find ~/projects/decision-os/logs -name "backend.log" 2>/dev/null | head -1)
[ -z "$LOGFILE" ] && LOGFILE=~/projects/decision-os/logs/backend.log
mkdir -p ~/projects/decision-os/logs
nohup uvicorn app.main:app --host 0.0.0.0 --port 8089 --reload \
  > "$LOGFILE" 2>&1 &
sleep 4
HEALTH=$(curl -s http://localhost:8089/health 2>/dev/null || curl -s http://localhost:8089/api/v1/health 2>/dev/null || echo "")
if echo "$HEALTH" | grep -qi "ok\|healthy\|status\|pong"; then
  log_ok "バックエンド再起動成功"
else
  log_warn "ヘルスチェック: $HEALTH"
fi

# ===== 7. コメント + 決定ログ 再テスト =====
echo ""
echo "========== 7. コメント + 決定ログ 再テスト =========="
LOGIN=$(curl -s -X POST "$BASE_URL/auth/login" \
  -H "Content-Type: application/json" \
  -d '{"email":"demo@example.com","password":"demo1234"}')
TOKEN=$(echo "$LOGIN" | python3 -c "import sys,json; print(json.load(sys.stdin).get('access_token',''))" 2>/dev/null || echo "")
[ -z "$TOKEN" ] && { log_fail "ログイン失敗"; exit 1; }
log_ok "JWT取得成功"

PID=$(curl -s -X POST "$BASE_URL/projects" \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"name":"patch4_'$(date +%s)'","description":"test"}' \
  | python3 -c "import sys,json; print(json.load(sys.stdin).get('id',''))" 2>/dev/null || echo "")
IID=$(curl -s -X POST "$BASE_URL/issues" \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d "{\"project_id\":\"$PID\",\"title\":\"final test\",\"issue_type\":\"task\",\"status\":\"open\"}" \
  | python3 -c "import sys,json; print(json.load(sys.stdin).get('id',''))" 2>/dev/null || echo "")
log_info "PID=$PID / IID=$IID"

# コメント
CONV=$(curl -s -w "\nHTTP:%{http_code}" -X POST "$BASE_URL/conversations" \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d "{\"issue_id\":\"$IID\",\"body\":\"テストコメント\"}")
HTTP=$(echo "$CONV" | grep "HTTP:" | cut -d: -f2)
BODY=$(echo "$CONV" | grep -v "HTTP:")
if [ "$HTTP" = "201" ] || [ "$HTTP" = "200" ]; then
  log_ok "コメント投稿成功 ✅ HTTP $HTTP"
else
  log_fail "コメント失敗 HTTP $HTTP — $BODY"
fi

# 決定ログ
DEC=$(curl -s -w "\nHTTP:%{http_code}" -X POST "$BASE_URL/decisions" \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d "{\"project_id\":\"$PID\",\"decision_text\":\"テスト決定\",\"reason\":\"テスト理由\",\"related_issue_id\":\"$IID\"}")
HTTP=$(echo "$DEC" | grep "HTTP:" | cut -d: -f2)
BODY=$(echo "$DEC" | grep -v "HTTP:")
if [ "$HTTP" = "201" ] || [ "$HTTP" = "200" ]; then
  log_ok "決定ログ作成成功 ✅ HTTP $HTTP"
else
  log_fail "決定ログ失敗 HTTP $HTTP — $BODY"
  # 直近エラーを確認
  grep -i "error\|exception\|decision" "$LOGFILE" 2>/dev/null | tail -15 || true
fi

# ===== サマリー =====
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  修正テスト結果"
echo "  ✅ PASS: $PASS"
echo "  ❌ FAIL: $FAIL"
echo "  ⚠️  WARN: $WARN"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if [ $FAIL -eq 0 ] && [ $WARN -eq 0 ]; then
  echo "[OK] 全項目クリア！次: conftest.py 修正 → テストカバレッジ計測"
else
  echo "FAIL/WARN あり — 上記を確認してください"
fi
