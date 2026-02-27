#!/bin/bash
set -e
BASE=~/projects/decision-os/backend
cd $BASE
source .venv/bin/activate

echo "=== Item モデル確認 ==="
grep -n "action" app/models/item.py

echo ""
echo "=== dashboard.py 修正 ==="
# Item.action_id → action カラム名を実態に合わせて修正
# 同時に InputCreate の field_validator も Pydantic v2 対応で修正
python3 - << 'PYEOF'
import re

# Item モデルからaction関連カラムを確認
with open("app/models/item.py") as f:
    item_content = f.read()
print("Item model:")
for line in item_content.splitlines():
    if "action" in line.lower():
        print(" ", line)
PYEOF

# dashboard.py を Item モデルの実態に合わせて修正
cat > app/api/v1/routers/dashboard.py << 'PYEOF'
from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session
from typing import Optional
from ....core.deps import get_db, get_current_user
from ....models.input import Input
from ....models.item import Item
from ....models.issue import Issue
from ....models.user import User

router = APIRouter(prefix="/dashboard", tags=["dashboard"])


@router.get("/counts")
def get_dashboard_counts(
    project_id: Optional[str] = Query(None),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    # INPUT カウント
    input_q = db.query(Input).filter(Input.deleted_at == None)
    if project_id:
        input_q = input_q.filter(Input.project_id == project_id)
    total_inputs = input_q.count()

    # 未処理INPUT（Itemが1件もないもの）
    from sqlalchemy import exists
    unprocessed_inputs = input_q.filter(
        ~exists().where(Item.input_id == Input.id)
    ).count()

    # ITEM カウント（action未設定 = Actionレコードが紐づいていない）
    item_q = db.query(Item)
    if project_id:
        item_q = item_q.join(Input, Item.input_id == Input.id).filter(
            Input.project_id == project_id
        )
    # action関連カラム名を動的に確認してフィルタ
    item_cols = [c.key for c in Item.__table__.columns]
    print(f"Item columns: {item_cols}")

    if "action_id" in item_cols:
        pending_items = item_q.filter(Item.action_id == None).count()
    else:
        # action_id カラムがない場合は全itemを「未対応」として扱う
        pending_items = item_q.count()

    # ISSUE カウント
    issue_q = db.query(Issue)
    if project_id:
        issue_q = issue_q.filter(Issue.project_id == project_id)
    open_issues = issue_q.filter(
        Issue.status.in_(["open", "in_progress", "review"])
    ).count()
    total_issues = issue_q.count()

    recent_issues = issue_q.filter(
        Issue.status.in_(["open", "in_progress"])
    ).order_by(Issue.updated_at.desc().nullslast()).limit(5).all()

    return {
        "inputs": {
            "total": total_inputs,
            "unprocessed": unprocessed_inputs,
        },
        "items": {
            "pending_action": pending_items,
        },
        "issues": {
            "open": open_issues,
            "total": total_issues,
            "recent": [
                {
                    "id": str(i.id),
                    "title": i.title,
                    "status": i.status,
                    "priority": i.priority,
                }
                for i in recent_issues
            ],
        },
    }
PYEOF
echo "[OK] dashboard.py 修正完了"

echo ""
echo "=== schemas/input.py の field_validator 修正 ==="
# Pydantic v2 では model_validator を使う方が確実
cat > app/schemas/input.py << 'PYEOF'
from pydantic import BaseModel, model_validator
from typing import Optional
from datetime import datetime


class InputCreate(BaseModel):
    raw_text: Optional[str] = None
    text: Optional[str] = None
    project_id: Optional[str] = None
    source_type: str = "manual"
    summary: Optional[str] = None
    importance: int = 3

    @model_validator(mode="before")
    @classmethod
    def normalize_text(cls, values):
        # text → raw_text へ自動変換
        if not values.get("raw_text") and values.get("text"):
            values["raw_text"] = values["text"]
        return values

    def get_raw_text(self) -> str:
        return self.raw_text or self.text or ""


class InputResponse(BaseModel):
    id: str
    project_id: Optional[str] = None
    author_id: Optional[str] = None
    source_type: str
    raw_text: str
    summary: Optional[str] = None
    importance: int
    created_at: datetime
    updated_at: Optional[datetime] = None

    model_config = {"from_attributes": True}
PYEOF
echo "[OK] schemas/input.py 修正完了"

echo ""
echo "=== バックエンド再起動 ==="
pkill -f "uvicorn app.main" 2>/dev/null || true
sleep 1
nohup uvicorn app.main:app --host 0.0.0.0 --port 8089 --reload \
  > ~/projects/decision-os/logs/backend.log 2>&1 &
sleep 4
curl -s http://localhost:8089/health && echo ""

echo ""
echo "=== 動作確認 ==="
TOKEN=$(curl -s -X POST http://localhost:8089/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"demo@example.com","password":"demo1234"}' \
  | python3 -c "import sys,json; print(json.load(sys.stdin).get('access_token','ERROR'))")

PROJECT_ID=$(curl -s http://localhost:8089/api/v1/projects \
  -H "Authorization: Bearer $TOKEN" \
  | python3 -c "import sys,json; d=json.load(sys.stdin); print(d[0]['id'])")
echo "PROJECT_ID: $PROJECT_ID"

echo ""
echo "--- POST /inputs (text フィールド) ---"
INPUT_RESP=$(curl -s -X POST http://localhost:8089/api/v1/inputs \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"text":"ログインページのボタンが押せない。また検索機能も追加してほしい","source_type":"email"}')
echo "$INPUT_RESP" | python3 -m json.tool 2>/dev/null || echo "$INPUT_RESP"
INPUT_ID=$(echo "$INPUT_RESP" | python3 -c "import sys,json; print(json.load(sys.stdin).get('id','ERROR'))" 2>/dev/null || echo "ERROR")
echo "→ INPUT_ID: $INPUT_ID"

echo ""
echo "--- GET /dashboard/counts ---"
curl -s "http://localhost:8089/api/v1/dashboard/counts?project_id=$PROJECT_ID" \
  -H "Authorization: Bearer $TOKEN" | python3 -m json.tool 2>/dev/null

echo ""
echo "--- POST /analyze ---"
if [ "$INPUT_ID" != "ERROR" ] && [ -n "$INPUT_ID" ]; then
  curl -s -X POST http://localhost:8089/api/v1/analyze \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d "{\"input_id\": \"$INPUT_ID\"}" | python3 -m json.tool 2>/dev/null
fi
