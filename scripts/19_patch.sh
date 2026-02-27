#!/usr/bin/env bash
# =============================================================================
# decision-os / 19_patch.sh
# 親子課題の修正パッチ
# 1. parent_id を UUID 型で正しく追加
# 2. models/issue.py の children relationship の循環参照を修正
# 3. バックエンド再起動確認
# =============================================================================
set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'
ok()      { echo -e "${GREEN}[OK]${RESET}    $*"; }
info()    { echo -e "${CYAN}[INFO]${RESET}  $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
section() { echo -e "\n${BOLD}========== $* ==========${RESET}"; }

PROJECT_DIR="$HOME/projects/decision-os"
cd "$PROJECT_DIR/backend"
source .venv/bin/activate

# ─────────────────────────────────────────────
# 1. DB: parent_id を UUID 型で追加
# ─────────────────────────────────────────────
section "DB: parent_id (UUID) / issue_type 追加"

python3 << 'PYEOF'
import sys
sys.path.insert(0, ".")
from app.db.session import engine
from sqlalchemy import text

with engine.connect() as conn:
    # トランザクションリセット
    try:
        conn.execute(text("ROLLBACK"))
    except:
        pass

    # parent_id (UUID型)
    try:
        conn.execute(text(
            "ALTER TABLE issues ADD COLUMN parent_id UUID REFERENCES issues(id) ON DELETE SET NULL"
        ))
        conn.commit()
        print("[OK]    parent_id UUID カラム追加")
    except Exception as e:
        conn.rollback()
        if "already exists" in str(e):
            print("[INFO]  parent_id は既に存在")
        else:
            print(f"[WARN]  parent_id: {e}")

    # issue_type
    try:
        conn.execute(text(
            "ALTER TABLE issues ADD COLUMN issue_type VARCHAR DEFAULT 'task'"
        ))
        conn.commit()
        print("[OK]    issue_type カラム追加")
    except Exception as e:
        conn.rollback()
        if "already exists" in str(e):
            print("[INFO]  issue_type は既に存在")
        else:
            print(f"[WARN]  issue_type: {e}")

    # 確認
    result = conn.execute(text(
        "SELECT column_name, data_type FROM information_schema.columns "
        "WHERE table_name='issues' AND column_name IN ('parent_id','issue_type')"
    ))
    for row in result:
        print(f"  ✓ {row[0]}: {row[1]}")
PYEOF

# ─────────────────────────────────────────────
# 2. models/issue.py の children relationship を安全な形に修正
# ─────────────────────────────────────────────
section "models/issue.py: relationship 修正"

ISSUE_MODEL="$PROJECT_DIR/backend/app/models/issue.py"

python3 - << 'PYEOF'
import os, re
path = os.path.expanduser("~/projects/decision-os/backend/app/models/issue.py")

with open(path) as f:
    src = f.read()

print("=== 現在の issue.py ===")
print(src)
PYEOF

# issue.py を安全な形で書き直す
python3 - << 'PYEOF'
import os, re
path = os.path.expanduser("~/projects/decision-os/backend/app/models/issue.py")

with open(path) as f:
    src = f.read()

# children relationship の問題のある行を除去
# "children = relationship..." の行を削除（循環参照の原因）
src = re.sub(r'\n\s+children\s*=\s*relationship\([^\n]+\n', '\n', src)

# backref import も不要なら除去
src = src.replace("from sqlalchemy.orm import relationship, backref", 
                  "from sqlalchemy.orm import relationship")

# parent_id の型を UUID に修正（VARCHAR の場合）
src = re.sub(
    r'parent_id\s*=\s*Column\(String,\s*ForeignKey',
    'parent_id  = Column(UUID(as_uuid=True), ForeignKey',
    src
)

# UUID import 確認
if "UUID" in src and "from sqlalchemy.dialects.postgresql import UUID" not in src:
    src = re.sub(
        r'(from sqlalchemy import[^\n]+)',
        r'\1\nfrom sqlalchemy.dialects.postgresql import UUID',
        src,
        count=1
    )

with open(path, "w") as f:
    f.write(src)

print("[OK] models/issue.py 修正完了")
print("=== 修正後 ===")
with open(path) as f:
    print(f.read())
PYEOF

ok "models/issue.py 修正完了"

# ─────────────────────────────────────────────
# 3. backend.log 確認 → 起動
# ─────────────────────────────────────────────
section "バックエンド起動"

pkill -f "uvicorn" 2>/dev/null || true
sleep 1

nohup uvicorn app.main:app --host 0.0.0.0 --port 8089 --reload > "$PROJECT_DIR/backend.log" 2>&1 &
sleep 4

# ログ確認
echo "--- backend.log (末尾20行) ---"
tail -20 "$PROJECT_DIR/backend.log" || true
echo "------------------------------"

# ヘルスチェック
if curl -s http://localhost:8089/api/v1/issues > /dev/null 2>&1; then
  ok "バックエンド起動確認 ✅"
else
  warn "まだ起動中の可能性 → 5秒待って再確認..."
  sleep 5
  if curl -s http://localhost:8089/api/v1/issues > /dev/null 2>&1; then
    ok "バックエンド起動確認 ✅"
  else
    warn "起動失敗 → backend.log を確認してください"
    tail -30 "$PROJECT_DIR/backend.log" || true
    exit 1
  fi
fi

# ─────────────────────────────────────────────
# 4. 動作確認
# ─────────────────────────────────────────────
section "動作確認"

TOKEN=$(curl -s -X POST http://localhost:8089/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"demo@example.com","password":"demo1234"}' | \
  python3 -c "import sys,json; print(json.load(sys.stdin).get('access_token',''))" 2>/dev/null || echo "")

if [ -z "$TOKEN" ]; then
  warn "ログイン失敗"
  exit 1
fi
ok "ログイン成功"

# issue_type カラムのテスト
ISSUE_ID=$(curl -s -H "Authorization: Bearer $TOKEN" \
  "http://localhost:8089/api/v1/issues?limit=1" | \
  python3 -c "
import sys, json
d = json.load(sys.stdin)
issues = d if isinstance(d, list) else d.get('issues', [])
print(issues[0]['id'] if issues else '')
" 2>/dev/null || echo "")

if [ -n "$ISSUE_ID" ]; then
  # issue_type を epic に変更
  PATCH=$(curl -s -X PATCH -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d '{"issue_type":"epic"}' \
    "http://localhost:8089/api/v1/issues/$ISSUE_ID")
  echo "$PATCH" | python3 -c "import sys,json; d=json.load(sys.stdin); print('issue_type:', d.get('issue_type','ERROR'))" 2>/dev/null \
    && ok "PATCH issue_type=epic ✅" || warn "PATCH失敗: $PATCH"

  # children エンドポイント
  CHILDREN=$(curl -s -H "Authorization: Bearer $TOKEN" \
    "http://localhost:8089/api/v1/issues/$ISSUE_ID/children")
  echo "$CHILDREN" | python3 -c "import sys,json; d=json.load(sys.stdin); print('children:', len(d.get('children',[])))" 2>/dev/null \
    && ok "GET /issues/{id}/children ✅" || warn "children失敗: $CHILDREN"

  # tree エンドポイント
  TREE=$(curl -s -H "Authorization: Bearer $TOKEN" \
    "http://localhost:8089/api/v1/issues/$ISSUE_ID/tree")
  echo "$TREE" | python3 -c "import sys,json; d=json.load(sys.stdin); print('tree.title:', d.get('title','?')[:20])" 2>/dev/null \
    && ok "GET /issues/{id}/tree ✅" || warn "tree失敗: $TREE"
else
  info "課題が0件 → UIから確認してください"
fi

echo ""
ok "19_patch.sh 完了！"
echo "ブラウザで確認: http://localhost:3008/issues → 課題詳細 → 🌳 子課題タブ"
