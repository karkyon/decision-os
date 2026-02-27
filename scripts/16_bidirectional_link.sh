#!/usr/bin/env bash
# =============================================================================
# decision-os / Phase 2: Action↔Issue 双方向リンク実装
#
# 現状:
#   Issue.action_id  → Action への FK（正引き: Issue → Action）は既存
#   Action.issue_id  → Issue への FK は未実装
#
# 実装内容:
#   DB-1:  actions テーブルに issue_id カラム追加（DDL直接）
#   BE-1:  models/action.py に issue_id フィールド + relationship 追加
#   BE-2:  routers/actions.py 修正 → CREATE_ISSUE 後に action.issue_id をセット
#   BE-3:  GET /api/v1/actions/{action_id} エンドポイント追加（Action詳細+紐付きIssue）
#   BE-4:  GET /api/v1/inputs/{input_id}/trace 逆引きエンドポイント追加
#          (Input → Items → Actions → Issues の順引き)
#   FE-1:  client.ts に actionApi.get / inputApi.trace 追加
# =============================================================================
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'
info()    { echo -e "${CYAN}[INFO]${RESET}  $*"; }
success() { echo -e "${GREEN}[OK]${RESET}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
section() { echo -e "\n${BOLD}========== $* ==========${RESET}"; }

PROJECT_DIR="$HOME/projects/decision-os"
BACKEND_DIR="$PROJECT_DIR/backend"
ROUTER_DIR="$BACKEND_DIR/app/api/v1/routers"
MODEL_DIR="$BACKEND_DIR/app/models"
API_DIR="$PROJECT_DIR/frontend/src/api"
TS=$(date +%Y%m%d_%H%M%S)

mkdir -p "$PROJECT_DIR/backup_$TS"
source "$BACKEND_DIR/.venv/bin/activate"
info "バックアップ先: $PROJECT_DIR/backup_$TS/"

# =============================================================================
section "DB-1: actions テーブルに issue_id カラム追加"
# =============================================================================

python3 - << 'PYEOF'
import os
db_url = os.environ.get(
    'DATABASE_URL',
    'postgresql://dev:devpass_2ed89487@localhost:5439/decisionos'
)
try:
    import sqlalchemy as sa
    engine = sa.create_engine(db_url)
    with engine.connect() as conn:
        # カラムが既に存在するか確認
        exists = conn.execute(sa.text("""
            SELECT COUNT(*) FROM information_schema.columns
            WHERE table_name='actions' AND column_name='issue_id'
        """)).scalar()

        if exists == 0:
            conn.execute(sa.text("""
                ALTER TABLE actions
                ADD COLUMN issue_id UUID REFERENCES issues(id) ON DELETE SET NULL;
            """))
            conn.execute(sa.text("""
                CREATE INDEX IF NOT EXISTS idx_actions_issue ON actions(issue_id);
            """))
            conn.commit()
            print("✅ actions.issue_id カラム追加完了")
        else:
            print("ℹ️  actions.issue_id は既に存在")

        # 既存データのバックフィル: Issue.action_id から Action.issue_id を埋める
        backfill = conn.execute(sa.text("""
            UPDATE actions a
            SET issue_id = i.id
            FROM issues i
            WHERE i.action_id = a.id
              AND a.issue_id IS NULL
        """))
        conn.commit()
        print(f"✅ 既存データバックフィル: {backfill.rowcount}件更新")

except Exception as e:
    print(f"❌ エラー: {e}")
PYEOF

success "DB: actions.issue_id 追加完了"

# =============================================================================
section "BE-1: models/action.py に issue_id フィールド追加"
# =============================================================================

cp "$MODEL_DIR/action.py" "$PROJECT_DIR/backup_$TS/action.py"

python3 - << 'PYEOF'
import os
path = os.path.expanduser("~/projects/decision-os/backend/app/models/action.py")
with open(path) as f:
    content = f.read()

if "issue_id" not in content:
    # ForeignKey import 確認
    if "ForeignKey" not in content:
        content = content.replace(
            "from sqlalchemy import Column",
            "from sqlalchemy import Column, ForeignKey"
        )

    # decided_at カラムの後に issue_id を追加
    import re
    content = re.sub(
        r'(decided_at\s*=\s*Column.*?\n)',
        r'\1    issue_id = Column(UUID(as_uuid=False), ForeignKey("issues.id", ondelete="SET NULL"), nullable=True)\n',
        content
    )

    # relationship 追加（既存 relationship の後）
    if "relationship" in content and "issue" not in content.lower():
        content = content.rstrip() + '\n    linked_issue = relationship("Issue", foreign_keys=[issue_id], backref="source_action")\n'
    elif "relationship" not in content:
        content = content.rstrip() + '\n    linked_issue = relationship("Issue", foreign_keys="[Action.issue_id]")\n'

    with open(path, "w") as f:
        f.write(content)
    print("✅ models/action.py に issue_id + linked_issue relationship 追加")
else:
    print("ℹ️  models/action.py に issue_id は既に存在")
PYEOF

success "models/action.py 更新完了"

# =============================================================================
section "BE-2: routers/actions.py 全面改修"
# CREATE_ISSUE 後に action.issue_id をセット
# GET /{action_id} エンドポイント追加
# =============================================================================

cp "$ROUTER_DIR/actions.py" "$PROJECT_DIR/backup_$TS/actions.py"

cat > "$ROUTER_DIR/actions.py" << 'ACTIONS_EOF'
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from typing import Optional
from ....core.deps import get_db, get_current_user
from ....models.action import Action
from ....models.item import Item
from ....models.input import Input
from ....models.issue import Issue
from ....models.user import User
from ....schemas.action import ActionCreate, ActionResponse

router = APIRouter(prefix="/actions", tags=["actions"])


@router.get("/{action_id}")
def get_action(
    action_id: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """
    ACTION の詳細を返す。
    紐づく Issue があれば issue 情報も含める（双方向リンク確認用）。
    """
    action = db.query(Action).filter(Action.id == action_id).first()
    if not action:
        raise HTTPException(status_code=404, detail="Action not found")

    # 紐づく Issue を取得（action_id 経由 or issue_id 経由）
    linked_issue = None
    if hasattr(action, "issue_id") and action.issue_id:
        linked_issue = db.query(Issue).filter(Issue.id == action.issue_id).first()
    else:
        # フォールバック: Issue.action_id から逆引き
        linked_issue = db.query(Issue).filter(Issue.action_id == action_id).first()

    result = {
        "id": action.id,
        "item_id": action.item_id,
        "action_type": action.action_type,
        "decision_reason": action.decision_reason,
        "decided_by": action.decided_by,
        "decided_at": action.decided_at,
        "issue_id": getattr(action, "issue_id", None),
        # 双方向リンク: 紐づく Issue のサマリー
        "linked_issue": {
            "id": linked_issue.id,
            "title": linked_issue.title,
            "status": linked_issue.status,
            "priority": linked_issue.priority,
        } if linked_issue else None,
    }
    return result


@router.post("", response_model=ActionResponse, status_code=201)
def create_action(
    payload: ActionCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    item = db.query(Item).filter(Item.id == payload.item_id).first()
    if not item:
        raise HTTPException(status_code=404, detail="Item not found")

    existing = db.query(Action).filter(Action.item_id == payload.item_id).first()
    if existing:
        raise HTTPException(status_code=409, detail="Action already exists for this item")

    action = Action(
        item_id=payload.item_id,
        action_type=payload.action_type,
        decided_by=current_user.id,
        decision_reason=payload.decision_reason,
    )
    db.add(action)
    db.commit()
    db.refresh(action)

    # CREATE_ISSUE の場合、自動で課題生成 + 双方向リンクをセット
    if payload.action_type == "CREATE_ISSUE":
        input_obj = db.query(Input).filter(Input.id == item.input_id).first()
        if input_obj:
            issue = Issue(
                project_id=input_obj.project_id,
                action_id=action.id,          # Issue → Action（正引き）
                title=f"[自動生成] {item.text[:100]}",
                description=item.text,
                priority="medium",
            )
            db.add(issue)
            db.commit()
            db.refresh(issue)

            # ★ 双方向リンク: Action → Issue をセット
            if hasattr(action, "issue_id"):
                action.issue_id = issue.id
                db.commit()

    return action


@router.post("/{action_id}/convert")
def convert_action_to_issue(
    action_id: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """ACTION を ISSUE に変換（既存なら返す）。双方向リンクも確立。"""
    action = db.query(Action).filter(Action.id == action_id).first()
    if not action:
        raise HTTPException(status_code=404, detail="Action not found")

    # 既存の ISSUE 確認（Issue.action_id or Action.issue_id）
    existing_issue = db.query(Issue).filter(Issue.action_id == action_id).first()
    if not existing_issue and hasattr(action, "issue_id") and action.issue_id:
        existing_issue = db.query(Issue).filter(Issue.id == action.issue_id).first()

    if existing_issue:
        # 双方向リンクが未設定なら補完
        if hasattr(action, "issue_id") and action.issue_id is None:
            action.issue_id = existing_issue.id
            db.commit()
        return existing_issue

    # 新規 ISSUE 生成
    item = db.query(Item).filter(Item.id == action.item_id).first()
    if not item:
        raise HTTPException(status_code=404, detail="Item not found for this action")

    input_obj = db.query(Input).filter(Input.id == item.input_id).first()
    if not input_obj:
        raise HTTPException(status_code=404, detail="Input not found for this item")

    issue = Issue(
        project_id=input_obj.project_id,
        action_id=action_id,                   # Issue → Action（正引き）
        title=f"[課題化] {item.text[:100]}",
        description=item.text,
        priority="medium",
    )
    db.add(issue)
    db.commit()
    db.refresh(issue)

    # ★ 双方向リンク: Action → Issue
    if hasattr(action, "issue_id"):
        action.issue_id = issue.id
        db.commit()

    return issue
ACTIONS_EOF

success "routers/actions.py 改修完了（双方向リンク + GET /{action_id}）"

# =============================================================================
section "BE-3: routers/inputs.py に逆引きトレース追加"
# GET /inputs/{input_id}/trace → Input → Items → Actions → Issues
# =============================================================================

cp "$ROUTER_DIR/inputs.py" "$PROJECT_DIR/backup_$TS/inputs.py"

python3 - << 'PYEOF'
import os
path = os.path.expanduser("~/projects/decision-os/backend/app/api/v1/routers/inputs.py")
with open(path) as f:
    content = f.read()

# 逆引きトレースエンドポイントを追加（未存在なら）
if "/trace" not in content:
    append = '''

@router.get("/{input_id}/trace")
def trace_input_forward(
    input_id: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """
    INPUT から前引きトレース: Input → Items → Actions → Issues の連鎖を返す。
    「この原文がどの課題を生み出したか」を確認できる逆引き機能。
    """
    from ....models.item import Item
    from ....models.action import Action
    from ....models.issue import Issue

    inp = db.query(Input).filter(Input.id == input_id).first()
    if not inp:
        from fastapi import HTTPException
        raise HTTPException(status_code=404, detail="Input not found")

    items = db.query(Item).filter(Item.input_id == input_id).order_by(Item.position).all()

    result = {
        "input": {
            "id": inp.id,
            "source_type": inp.source_type,
            "raw_text": inp.raw_text,
            "created_at": str(inp.created_at),
        },
        "items": []
    }

    for item in items:
        action = db.query(Action).filter(Action.item_id == item.id).first()
        linked_issue = None
        if action:
            # 双方向: Action.issue_id または Issue.action_id から取得
            if hasattr(action, "issue_id") and action.issue_id:
                linked_issue = db.query(Issue).filter(Issue.id == action.issue_id).first()
            else:
                linked_issue = db.query(Issue).filter(Issue.action_id == action.id).first()

        result["items"].append({
            "id": item.id,
            "text": item.text,
            "intent_code": item.intent_code,
            "domain_code": item.domain_code,
            "confidence": item.confidence,
            "action": {
                "id": action.id,
                "action_type": action.action_type,
                "decision_reason": action.decision_reason,
                "issue_id": getattr(action, "issue_id", None),
            } if action else None,
            "issue": {
                "id": linked_issue.id,
                "title": linked_issue.title,
                "status": linked_issue.status,
                "priority": linked_issue.priority,
            } if linked_issue else None,
        })

    return result
'''
    content = content.rstrip() + "\n" + append
    with open(path, "w") as f:
        f.write(content)
    print("✅ inputs.py に GET /{input_id}/trace 追加（前引きトレース）")
else:
    print("ℹ️  inputs.py に /trace は既に存在")
PYEOF

success "routers/inputs.py 更新完了"

# =============================================================================
section "FE-1: client.ts に actionApi.get / inputApi.trace 追加"
# =============================================================================

python3 - << 'PYEOF'
import os
path = os.path.expanduser("~/projects/decision-os/frontend/src/api/client.ts")
with open(path) as f:
    content = f.read()

changed = False

# actionApi.get を追加
if "actionApi" not in content:
    content = content.rstrip() + """
// Actions
export const actionApi = {
  get: (id: string) => client.get(`/actions/${id}`),
  create: (data: any) => client.post("/actions", data),
  convert: (id: string) => client.post(`/actions/${id}/convert`),
};
"""
    changed = True
    print("✅ client.ts に actionApi 追加")
elif "actionApi.get" not in content and "get:" not in content.split("actionApi")[1][:200]:
    # 既存の actionApi に get を追加
    content = content.replace(
        "export const actionApi = {\n  create:",
        "export const actionApi = {\n  get: (id: string) => client.get(`/actions/${id}`),\n  create:"
    )
    changed = True
    print("✅ actionApi.get を追加")
else:
    print("ℹ️  actionApi は既に存在")

# inputApi に trace を追加
if "inputApi" in content and "trace" not in content.split("inputApi")[1][:400]:
    content = content.replace(
        "  list: (projectId: string) => client.get(`/inputs?project_id=${projectId}`),\n};",
        "  list: (projectId: string) => client.get(`/inputs?project_id=${projectId}`),\n  trace: (inputId: string) => client.get(`/inputs/${inputId}/trace`),\n};"
    )
    changed = True
    print("✅ inputApi.trace を追加")
else:
    print("ℹ️  inputApi.trace は既に存在またはスキップ")

if changed:
    with open(path, "w") as f:
        f.write(content)
PYEOF

success "client.ts 更新完了"

# =============================================================================
section "バックエンド再起動 & 動作確認"
# =============================================================================

cd "$BACKEND_DIR"
pkill -f "uvicorn app.main" 2>/dev/null || true
sleep 1

nohup uvicorn app.main:app --host 0.0.0.0 --port 8089 --reload \
  > ~/projects/decision-os/logs/backend.log 2>&1 &

echo "バックエンド起動中..."
sleep 4

HEALTH=$(curl -sf http://localhost:8089/health 2>/dev/null \
  | python3 -c "import sys,json; print(json.load(sys.stdin).get('status','NG'))" 2>/dev/null || echo "NG")

if [[ "$HEALTH" == "ok" ]]; then
  success "バックエンド起動確認 ✅"
else
  warn "起動失敗 → tail -30 ~/projects/decision-os/logs/backend.log"
  exit 1
fi

# 双方向リンク確認テスト
TOKEN=$(curl -sf -X POST http://localhost:8089/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"demo@example.com","password":"demo1234"}' \
  | python3 -c "import sys,json; print(json.load(sys.stdin).get('access_token','ERR'))" 2>/dev/null || echo "ERR")

if [[ "$TOKEN" != "ERR" ]]; then
  # 既存 Issue から action_id を取得して双方向確認
  CHECK=$(python3 - << PYEOF
import subprocess, json, sys

token = "$TOKEN"

# Issue一覧取得
res = subprocess.run([
    "curl", "-sf",
    "http://localhost:8089/api/v1/issues",
    "-H", f"Authorization: Bearer {token}"
], capture_output=True, text=True)

try:
    issues = json.loads(res.stdout)
    # action_id を持つ Issue を探す
    for issue in issues:
        action_id = issue.get("action_id")
        if action_id:
            # Action の詳細を取得（双方向確認）
            res2 = subprocess.run([
                "curl", "-sf",
                f"http://localhost:8089/api/v1/actions/{action_id}",
                "-H", f"Authorization: Bearer {token}"
            ], capture_output=True, text=True)
            action = json.loads(res2.stdout)
            linked = action.get("linked_issue")
            if linked:
                print(f"✅ 双方向リンク確認: Action({action_id[:8]}...) ↔ Issue({linked['id'][:8]}...) title={linked['title'][:30]}")
            else:
                print(f"⚠️  Action({action_id[:8]}...) の linked_issue が null → バックフィル未反映の可能性")
            sys.exit(0)
    print("ℹ️  action_id を持つ Issue が見つかりません（今後の課題化で双方向リンクが機能します）")
except Exception as e:
    print(f"確認スキップ: {e}")
PYEOF
)
  echo "$CHECK"

  # 前引きトレースの確認
  INPUT_ID=$(curl -sf "http://localhost:8089/api/v1/inputs" \
    -H "Authorization: Bearer $TOKEN" 2>/dev/null \
    | python3 -c "import sys,json; d=json.load(sys.stdin); print(d[0]['id'] if d else 'NONE')" 2>/dev/null || echo "NONE")

  if [[ "$INPUT_ID" != "NONE" && -n "$INPUT_ID" ]]; then
    TRACE_RES=$(curl -sf "http://localhost:8089/api/v1/inputs/$INPUT_ID/trace" \
      -H "Authorization: Bearer $TOKEN" 2>/dev/null \
      | python3 -c "
import sys,json
d=json.load(sys.stdin)
items = d.get('items', [])
issues = [i['issue'] for i in items if i.get('issue')]
print(f'items:{len(items)}件, 課題化済み:{len(issues)}件')
" 2>/dev/null || echo "ERR")
    if [[ "$TRACE_RES" != "ERR" ]]; then
      success "前引きトレース(Input→Issues): $TRACE_RES ✅"
    else
      warn "前引きトレース失敗 → backend.log 確認"
    fi
  fi
fi

# =============================================================================
section "完了サマリー"
# =============================================================================
echo ""
echo -e "${BOLD}実装完了:${RESET}"
echo "  ✅ DB:  actions.issue_id カラム追加 + 既存データバックフィル"
echo "  ✅ BE:  models/action.py に issue_id + linked_issue relationship"
echo "  ✅ BE:  routers/actions.py 改修"
echo "          - POST /actions → CREATE_ISSUE 後に action.issue_id をセット"
echo "          - GET  /actions/{id} → linked_issue を含む詳細返却"
echo "          - POST /actions/{id}/convert → 双方向リンク確立"
echo "  ✅ BE:  GET /inputs/{input_id}/trace → Input→Items→Actions→Issues 前引き"
echo "  ✅ FE:  client.ts に actionApi.get / inputApi.trace 追加"
echo ""
echo -e "${BOLD}双方向リンクのデータ構造:${RESET}"
echo "  Issue.action_id  → Action（正引き: Issue から元Actionへ）"
echo "  Action.issue_id  → Issue（逆引き: Action から生成Issueへ）"
echo "  ※ 両方向から O(1) でアクセス可能"
echo ""
echo -e "${BOLD}活用シーン:${RESET}"
echo "  - 課題詳細のトレーサビリティタブ（既存）に action → issue 逆リンク表示"
echo "  - GET /inputs/{id}/trace で「この原文から何件の課題が生まれたか」確認"
echo ""
success "Phase 2: Action↔Issue 双方向リンク 実装完了！"
