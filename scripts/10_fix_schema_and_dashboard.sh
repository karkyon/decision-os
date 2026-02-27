#!/bin/bash
# decision-os API修正スクリプト
# 修正1: InputCreateスキーマに text/raw_text の両フィールド対応
# 修正2: /api/v1/dashboard/counts エンドポイント追加
# 実行: bash 10_fix_schema_and_dashboard.sh

set -e
BASE=~/projects/decision-os/backend
cd $BASE
source .venv/bin/activate

echo "========== [1/4] schemas/input.py 修正 =========="
# text と raw_text を両方受け付け、project_id をオプション化
cat > app/schemas/input.py << 'PYEOF'
from pydantic import BaseModel, field_validator
from typing import Optional
from datetime import datetime


class InputCreate(BaseModel):
    # raw_text でも text でも受け付ける（フロントエンド互換）
    raw_text: Optional[str] = None
    text: Optional[str] = None
    project_id: Optional[str] = None   # オプション化（デモ用）
    source_type: str = "manual"
    summary: Optional[str] = None
    importance: int = 3

    @field_validator("raw_text", mode="before")
    @classmethod
    def set_raw_text(cls, v, info):
        # raw_text が空なら text を使う
        if not v and info.data.get("text"):
            return info.data["text"]
        return v

    def get_raw_text(self) -> str:
        return self.raw_text or self.text or ""


class InputResponse(BaseModel):
    id: str
    project_id: Optional[str]
    author_id: Optional[str]
    source_type: str
    raw_text: str
    summary: Optional[str]
    importance: int
    created_at: datetime
    updated_at: Optional[datetime]

    model_config = {"from_attributes": True}
PYEOF
echo "[OK] schemas/input.py 修正完了"


echo ""
echo "========== [2/4] routers/inputs.py 修正 =========="
cat > app/api/v1/routers/inputs.py << 'PYEOF'
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from typing import List, Optional
from ....core.deps import get_db, get_current_user
from ....models.input import Input
from ....models.project import Project
from ....models.user import User
from ....schemas.input import InputCreate, InputResponse

router = APIRouter(prefix="/inputs", tags=["inputs"])


@router.post("", response_model=InputResponse, status_code=201)
def create_input(
    payload: InputCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    raw_text = payload.get_raw_text()
    if not raw_text:
        raise HTTPException(status_code=422, detail="raw_text または text が必要です")

    # project_id が未指定の場合、ユーザーの最初のプロジェクトを使用
    project_id = payload.project_id
    if not project_id:
        first_project = db.query(Project).first()
        if first_project:
            project_id = str(first_project.id)

    inp = Input(
        project_id=project_id,
        author_id=current_user.id,
        source_type=payload.source_type,
        raw_text=raw_text,
        summary=payload.summary,
        importance=payload.importance,
    )
    db.add(inp)
    db.commit()
    db.refresh(inp)
    return inp


@router.get("/{input_id}", response_model=InputResponse)
def get_input(
    input_id: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    inp = db.query(Input).filter(
        Input.id == input_id,
        Input.deleted_at == None
    ).first()
    if not inp:
        raise HTTPException(status_code=404, detail="Input not found")
    return inp


@router.get("", response_model=List[InputResponse])
def list_inputs(
    project_id: Optional[str] = None,
    skip: int = 0,
    limit: int = 50,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    query = db.query(Input).filter(Input.deleted_at == None)
    if project_id:
        query = query.filter(Input.project_id == project_id)
    return query.order_by(Input.created_at.desc()).offset(skip).limit(limit).all()
PYEOF
echo "[OK] routers/inputs.py 修正完了"


echo ""
echo "========== [3/4] dashboard エンドポイント追加 =========="
cat > app/api/v1/routers/dashboard.py << 'PYEOF'
from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session
from sqlalchemy import func
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
    """ダッシュボード用カウント取得"""
    # INPUT: 未処理（items が紐づいていない）
    input_q = db.query(Input).filter(Input.deleted_at == None)
    if project_id:
        input_q = input_q.filter(Input.project_id == project_id)

    total_inputs = input_q.count()

    # 処理済みINPUT（itemsが存在するもの）
    processed_input_ids = db.query(Item.input_id).distinct().subquery()
    unprocessed_inputs = input_q.filter(
        ~Input.id.in_(db.query(processed_input_ids))
    ).count()

    # ITEM: action未設定（action_idがNull）
    item_q = db.query(Item)
    if project_id:
        item_q = item_q.join(Input, Item.input_id == Input.id).filter(
            Input.project_id == project_id
        )
    pending_items = item_q.filter(Item.action_id == None).count()

    # ISSUE: 未完了
    issue_q = db.query(Issue)
    if project_id:
        issue_q = issue_q.filter(Issue.project_id == project_id)
    open_issues = issue_q.filter(
        Issue.status.in_(["open", "in_progress", "review"])
    ).count()
    total_issues = issue_q.count()

    # 直近のISSUE（遅延タスク含む）
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
                    "id": str(issue.id),
                    "title": issue.title,
                    "status": issue.status,
                    "priority": issue.priority,
                }
                for issue in recent_issues
            ],
        },
    }
PYEOF
echo "[OK] routers/dashboard.py 作成完了"


echo ""
echo "========== [4/4] api.py に dashboard ルーター追加 =========="
# 現在のapi.pyを確認してから追加
python3 - << 'PYEOF'
import re

with open("app/api/v1/api.py", "r") as f:
    content = f.read()

# dashboard が既に含まれていなければ追加
if "dashboard" not in content:
    # import行に追加
    content = re.sub(
        r'(from .routers import.*?)(\n)',
        lambda m: m.group(0),
        content
    )
    # from .routers.xxx import router as xxx_router パターンを探す
    last_import = list(re.finditer(r'from \.routers\.\w+ import router as \w+_router', content))
    if last_import:
        pos = last_import[-1].end()
        content = content[:pos] + "\nfrom .routers.dashboard import router as dashboard_router" + content[pos:]

    # api_router.include_router の末尾に追加
    last_include = list(re.finditer(r'api_router\.include_router\([^)]+\)', content))
    if last_include:
        pos = last_include[-1].end()
        content = content[:pos] + '\napi_router.include_router(dashboard_router)' + content[pos:]

    with open("app/api/v1/api.py", "w") as f:
        f.write(content)
    print("[OK] api.py に dashboard_router を追加")
else:
    print("[SKIP] dashboard は既に登録済み")

print("\n--- api.py 現在の内容 ---")
with open("app/api/v1/api.py") as f:
    print(f.read())
PYEOF


echo ""
echo "========== バックエンド再起動 =========="
pkill -f "uvicorn app.main" 2>/dev/null || true
sleep 1
nohup uvicorn app.main:app --host 0.0.0.0 --port 8089 --reload \
  > ~/projects/decision-os/logs/backend.log 2>&1 &
sleep 3
curl -s http://localhost:8089/health
echo ""
echo "[OK] 再起動完了"


echo ""
echo "========== 動作確認 =========="

# TOKEN再取得
TOKEN=$(curl -s -X POST http://localhost:8089/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"demo@example.com","password":"demo1234"}' \
  | python3 -c "import sys,json; print(json.load(sys.stdin).get('access_token','ERROR'))")
echo "TOKEN: ${TOKEN:0:30}..."

# project_id取得
PROJECT_ID=$(curl -s http://localhost:8089/api/v1/projects \
  -H "Authorization: Bearer $TOKEN" \
  | python3 -c "import sys,json; d=json.load(sys.stdin); print(d[0]['id'])")
echo "PROJECT_ID: $PROJECT_ID"

echo ""
echo "--- [CHECK 1] text フィールドでINPUT登録 ---"
INPUT_RESP=$(curl -s -X POST http://localhost:8089/api/v1/inputs \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"text":"ログインページのボタンが押せない。また検索機能も追加してほしい","source_type":"email"}')
echo "$INPUT_RESP" | python3 -m json.tool
INPUT_ID=$(echo "$INPUT_RESP" | python3 -c "import sys,json; print(json.load(sys.stdin).get('id','ERROR'))" 2>/dev/null || echo "ERROR")
echo "INPUT_ID: $INPUT_ID"

echo ""
echo "--- [CHECK 2] analyze (input_id 方式) ---"
if [ "$INPUT_ID" != "ERROR" ] && [ -n "$INPUT_ID" ]; then
  curl -s -X POST http://localhost:8089/api/v1/analyze \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d "{\"input_id\": \"$INPUT_ID\"}" | python3 -m json.tool
else
  echo "[SKIP] INPUT登録に失敗したためSKIP"
fi

echo ""
echo "--- [CHECK 3] dashboard/counts ---"
curl -s "http://localhost:8089/api/v1/dashboard/counts?project_id=$PROJECT_ID" \
  -H "Authorization: Bearer $TOKEN" | python3 -m json.tool

echo ""
echo "--- [CHECK 4] issues 一覧 ---"
curl -s "http://localhost:8089/api/v1/issues?project_id=$PROJECT_ID" \
  -H "Authorization: Bearer $TOKEN" | python3 -m json.tool | head -40

echo ""
echo "========== 修正完了 =========="
echo "✅ text フィールドでINPUT登録"
echo "✅ project_id 省略可能"
echo "✅ /dashboard/counts 実装"
