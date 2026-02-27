#!/bin/bash
# ============================================================
# Phase 1 MVP - Step 3: コアAPI実装
# POST /inputs / POST /analyze / PATCH /items/:id
# POST /actions / POST /issues / GET /issues / GET /trace/:id
# ============================================================
set -e

PROJECT="$HOME/projects/decision-os"
BACKEND="$PROJECT/backend"

echo "=== Step 3: コアAPI実装 ==="

# ---- Pydanticスキーマ群 ----
cat > "$BACKEND/app/schemas/input.py" << 'EOF'
from pydantic import BaseModel
from typing import Optional
from datetime import datetime

class InputCreate(BaseModel):
    project_id: str
    source_type: str  # email/voice/meeting/bug/other
    raw_text: str
    summary: Optional[str] = None
    importance: Optional[str] = "3"

class InputResponse(BaseModel):
    id: str
    project_id: str
    source_type: str
    raw_text: str
    summary: Optional[str]
    importance: Optional[str]
    created_at: datetime

    class Config:
        from_attributes = True
EOF

cat > "$BACKEND/app/schemas/item.py" << 'EOF'
from pydantic import BaseModel
from typing import Optional
from datetime import datetime

class ItemResponse(BaseModel):
    id: str
    input_id: str
    text: str
    intent_code: str
    domain_code: str
    confidence: Optional[float]
    position: int
    is_corrected: Optional[str]
    created_at: datetime

    class Config:
        from_attributes = True

class ItemUpdate(BaseModel):
    intent_code: Optional[str] = None
    domain_code: Optional[str] = None
    text: Optional[str] = None
EOF

cat > "$BACKEND/app/schemas/action.py" << 'EOF'
from pydantic import BaseModel
from typing import Optional
from datetime import datetime

class ActionCreate(BaseModel):
    item_id: str
    action_type: str  # CREATE_ISSUE/ANSWER/STORE/REJECT/HOLD/LINK_EXISTING
    decision_reason: Optional[str] = None

class ActionResponse(BaseModel):
    id: str
    item_id: str
    action_type: str
    decision_reason: Optional[str]
    decided_at: datetime

    class Config:
        from_attributes = True
EOF

cat > "$BACKEND/app/schemas/issue.py" << 'EOF'
from pydantic import BaseModel
from typing import Optional, List
from datetime import datetime

class IssueCreate(BaseModel):
    project_id: str
    action_id: Optional[str] = None
    title: str
    description: Optional[str] = None
    priority: str = "medium"
    assignee_id: Optional[str] = None
    due_date: Optional[datetime] = None
    labels: Optional[str] = None  # JSON文字列

class IssueUpdate(BaseModel):
    title: Optional[str] = None
    description: Optional[str] = None
    status: Optional[str] = None
    priority: Optional[str] = None
    assignee_id: Optional[str] = None
    due_date: Optional[datetime] = None
    labels: Optional[str] = None

class IssueResponse(BaseModel):
    id: str
    project_id: str
    action_id: Optional[str]
    title: str
    description: Optional[str]
    status: str
    priority: str
    assignee_id: Optional[str]
    labels: Optional[str]
    created_at: datetime
    updated_at: Optional[datetime]

    class Config:
        from_attributes = True
EOF

# ---- Input ルーター ----
cat > "$BACKEND/app/api/v1/routers/inputs.py" << 'EOF'
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from typing import List
from ....core.deps import get_db, get_current_user
from ....models.input import Input
from ....models.user import User
from ....schemas.input import InputCreate, InputResponse

router = APIRouter(prefix="/inputs", tags=["inputs"])

@router.post("", response_model=InputResponse, status_code=201)
def create_input(
    payload: InputCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    inp = Input(
        project_id=payload.project_id,
        author_id=current_user.id,
        source_type=payload.source_type,
        raw_text=payload.raw_text,
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
    inp = db.query(Input).filter(Input.id == input_id, Input.deleted_at == None).first()
    if not inp:
        raise HTTPException(status_code=404, detail="Input not found")
    return inp

@router.get("", response_model=List[InputResponse])
def list_inputs(
    project_id: str,
    skip: int = 0,
    limit: int = 50,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    return db.query(Input).filter(
        Input.project_id == project_id,
        Input.deleted_at == None
    ).order_by(Input.created_at.desc()).offset(skip).limit(limit).all()
EOF

# ---- Analyze ルーター（分解エンジン呼び出し）----
cat > "$BACKEND/app/api/v1/routers/analyze.py" << 'EOF'
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from typing import List
from pydantic import BaseModel
from ....core.deps import get_db, get_current_user
from ....models.input import Input
from ....models.item import Item
from ....models.interpretation import Interpretation
from ....models.user import User
from ....schemas.item import ItemResponse

router = APIRouter(prefix="/analyze", tags=["analyze"])

class AnalyzeRequest(BaseModel):
    input_id: str

@router.post("", response_model=List[ItemResponse])
def analyze_input(
    payload: AnalyzeRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    inp = db.query(Input).filter(Input.id == payload.input_id).first()
    if not inp:
        raise HTTPException(status_code=404, detail="Input not found")

    # 既存ITEMがあれば返す（冪等）
    existing_items = db.query(Item).filter(Item.input_id == payload.input_id).all()
    if existing_items:
        return existing_items

    # 分解エンジン呼び出し
    import sys, os
    sys.path.insert(0, os.path.join(os.path.dirname(__file__), "../../../../../engine"))
    try:
        from engine.main import analyze_text
        results = analyze_text(inp.raw_text)
    except Exception as e:
        # エンジンが未実装の場合のフォールバック
        results = _fallback_analyze(inp.raw_text)

    # Interpretation生成
    interp = Interpretation(
        input_id=inp.id,
        summary=f"（自動解析）{inp.raw_text[:100]}...",
        overall_intent=results[0]["intent_code"] if results else "INF",
        confidence=results[0]["confidence"] if results else 0.5,
    )
    db.add(interp)

    # Item生成
    items = []
    for i, r in enumerate(results):
        item = Item(
            input_id=inp.id,
            text=r["text"],
            intent_code=r["intent_code"],
            domain_code=r["domain_code"],
            confidence=r["confidence"],
            position=i,
        )
        db.add(item)
        items.append(item)

    db.commit()
    for item in items:
        db.refresh(item)
    return items

def _fallback_analyze(text: str) -> list:
    """分解エンジン未実装時のシンプルフォールバック"""
    import re
    sentences = re.split(r'[。\n]+', text.strip())
    sentences = [s.strip() for s in sentences if s.strip()]

    results = []
    bug_words = ["エラー", "バグ", "不具合", "動かない", "おかしい", "失敗"]
    req_words = ["ほしい", "したい", "追加", "実装", "対応", "欲しい"]
    qst_words = ["？", "ですか", "でしょうか", "どう", "どの"]

    for s in sentences:
        if any(w in s for w in bug_words):
            intent, domain, conf = "BUG", "API", 0.80
        elif any(w in s for w in req_words):
            intent, domain, conf = "REQ", "SPEC", 0.75
        elif any(w in s for w in qst_words):
            intent, domain, conf = "QST", "SPEC", 0.70
        else:
            intent, domain, conf = "INF", "SPEC", 0.60

        # domain推定
        if any(w in s for w in ["画面", "UI", "ボタン", "表示"]):
            domain = "UI"
        elif any(w in s for w in ["API", "エンドポイント", "レスポンス"]):
            domain = "API"
        elif any(w in s for w in ["DB", "データベース", "テーブル", "SQL"]):
            domain = "DB"
        elif any(w in s for w in ["認証", "ログイン", "権限"]):
            domain = "AUTH"

        results.append({"text": s, "intent_code": intent, "domain_code": domain, "confidence": conf})

    return results if results else [{"text": text, "intent_code": "INF", "domain_code": "SPEC", "confidence": 0.5}]
EOF

# ---- Item ルーター（手動修正）----
cat > "$BACKEND/app/api/v1/routers/items.py" << 'EOF'
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from ....core.deps import get_db, get_current_user
from ....models.item import Item
from ....models.learning_log import LearningLog
from ....models.user import User
from ....schemas.item import ItemUpdate, ItemResponse

router = APIRouter(prefix="/items", tags=["items"])

@router.patch("/{item_id}", response_model=ItemResponse)
def update_item(
    item_id: str,
    payload: ItemUpdate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    item = db.query(Item).filter(Item.id == item_id).first()
    if not item:
        raise HTTPException(status_code=404, detail="Item not found")

    # 学習ログ記録（変更があれば）
    if payload.intent_code and payload.intent_code != item.intent_code:
        log = LearningLog(
            item_id=item.id,
            predicted_intent=item.intent_code,
            corrected_intent=payload.intent_code,
            predicted_domain=item.domain_code,
            corrected_domain=payload.domain_code or item.domain_code,
        )
        db.add(log)
        item.is_corrected = "true"

    if payload.intent_code:
        item.intent_code = payload.intent_code
    if payload.domain_code:
        item.domain_code = payload.domain_code
    if payload.text:
        item.text = payload.text

    db.commit()
    db.refresh(item)
    return item
EOF

# ---- Action ルーター ----
cat > "$BACKEND/app/api/v1/routers/actions.py" << 'EOF'
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from ....core.deps import get_db, get_current_user
from ....models.action import Action
from ....models.item import Item
from ....models.issue import Issue
from ....models.user import User
from ....schemas.action import ActionCreate, ActionResponse

router = APIRouter(prefix="/actions", tags=["actions"])

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

    # CREATE_ISSUE の場合、自動で課題生成
    if payload.action_type == "CREATE_ISSUE":
        issue = Issue(
            project_id=item.input.project_id,
            action_id=action.id,
            title=f"[自動生成] {item.text[:100]}",
            description=item.text,
            priority="medium",
        )
        db.add(issue)
        db.commit()

    return action
EOF

# ---- Issue ルーター ----
cat > "$BACKEND/app/api/v1/routers/issues.py" << 'EOF'
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from typing import List, Optional
from ....core.deps import get_db, get_current_user
from ....models.issue import Issue
from ....models.user import User
from ....schemas.issue import IssueCreate, IssueUpdate, IssueResponse

router = APIRouter(prefix="/issues", tags=["issues"])

@router.post("", response_model=IssueResponse, status_code=201)
def create_issue(
    payload: IssueCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    issue = Issue(**payload.model_dump())
    db.add(issue)
    db.commit()
    db.refresh(issue)
    return issue

@router.get("", response_model=List[IssueResponse])
def list_issues(
    project_id: str,
    status: Optional[str] = None,
    priority: Optional[str] = None,
    assignee_id: Optional[str] = None,
    skip: int = 0,
    limit: int = 100,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    q = db.query(Issue).filter(Issue.project_id == project_id)
    if status:
        q = q.filter(Issue.status == status)
    if priority:
        q = q.filter(Issue.priority == priority)
    if assignee_id:
        q = q.filter(Issue.assignee_id == assignee_id)
    return q.order_by(Issue.created_at.desc()).offset(skip).limit(limit).all()

@router.get("/{issue_id}", response_model=IssueResponse)
def get_issue(
    issue_id: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    issue = db.query(Issue).filter(Issue.id == issue_id).first()
    if not issue:
        raise HTTPException(status_code=404, detail="Issue not found")
    return issue

@router.patch("/{issue_id}", response_model=IssueResponse)
def update_issue(
    issue_id: str,
    payload: IssueUpdate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    issue = db.query(Issue).filter(Issue.id == issue_id).first()
    if not issue:
        raise HTTPException(status_code=404, detail="Issue not found")
    for field, value in payload.model_dump(exclude_unset=True).items():
        setattr(issue, field, value)
    db.commit()
    db.refresh(issue)
    return issue
EOF

# ---- トレーサビリティ ルーター ----
cat > "$BACKEND/app/api/v1/routers/trace.py" << 'EOF'
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from ....core.deps import get_db, get_current_user
from ....models.issue import Issue
from ....models.action import Action
from ....models.item import Item
from ....models.input import Input
from ....models.user import User

router = APIRouter(prefix="/trace", tags=["trace"])

@router.get("/{issue_id}")
def get_trace(
    issue_id: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    issue = db.query(Issue).filter(Issue.id == issue_id).first()
    if not issue:
        raise HTTPException(status_code=404, detail="Issue not found")

    result = {
        "issue": {
            "id": issue.id,
            "title": issue.title,
            "status": issue.status,
            "priority": issue.priority,
            "created_at": str(issue.created_at),
        },
        "action": None,
        "item": None,
        "input": None,
    }

    if issue.action_id:
        action = db.query(Action).filter(Action.id == issue.action_id).first()
        if action:
            result["action"] = {
                "id": action.id,
                "action_type": action.action_type,
                "decision_reason": action.decision_reason,
                "decided_at": str(action.decided_at),
            }
            item = db.query(Item).filter(Item.id == action.item_id).first()
            if item:
                result["item"] = {
                    "id": item.id,
                    "text": item.text,
                    "intent_code": item.intent_code,
                    "domain_code": item.domain_code,
                    "confidence": item.confidence,
                }
                inp = db.query(Input).filter(Input.id == item.input_id).first()
                if inp:
                    result["input"] = {
                        "id": inp.id,
                        "source_type": inp.source_type,
                        "raw_text": inp.raw_text,
                        "created_at": str(inp.created_at),
                    }

    return result
EOF

# ---- プロジェクト ルーター ----
cat > "$BACKEND/app/api/v1/routers/projects.py" << 'EOF'
from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session
from typing import List
from pydantic import BaseModel
from ....core.deps import get_db, get_current_user
from ....models.project import Project
from ....models.user import User

router = APIRouter(prefix="/projects", tags=["projects"])

class ProjectCreate(BaseModel):
    name: str
    description: str = ""

class ProjectResponse(BaseModel):
    id: str
    name: str
    description: str | None
    status: str | None

    class Config:
        from_attributes = True

@router.post("", response_model=ProjectResponse, status_code=201)
def create_project(payload: ProjectCreate, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    p = Project(name=payload.name, description=payload.description)
    db.add(p)
    db.commit()
    db.refresh(p)
    return p

@router.get("", response_model=List[ProjectResponse])
def list_projects(db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    return db.query(Project).filter(Project.status == "active").all()
EOF

# ---- APIルーター統合 ----
cat > "$BACKEND/app/api/v1/api.py" << 'EOF'
from fastapi import APIRouter
from .routers import auth, inputs, analyze, items, actions, issues, trace, projects

api_router = APIRouter()
api_router.include_router(auth.router)
api_router.include_router(projects.router)
api_router.include_router(inputs.router)
api_router.include_router(analyze.router)
api_router.include_router(items.router)
api_router.include_router(actions.router)
api_router.include_router(issues.router)
api_router.include_router(trace.router)
EOF

# ---- main.py 更新（ルーター登録）----
cat > "$BACKEND/app/main.py" << 'EOF'
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from .core.config import settings
from .api.v1.api import api_router

app = FastAPI(
    title="decision-os API",
    description="開発判断OS - 意思決定の透明化システム",
    version="1.0.0",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["http://localhost:3008", "http://localhost:8888"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(api_router, prefix=settings.API_V1_STR)

@app.get("/health")
def health():
    return {"status": "ok", "service": "decision-os"}

@app.get("/api/v1/ping")
def ping():
    return {"message": "pong", "version": "1.0.0"}
EOF

echo "✅ コアAPI生成完了"
echo "✅✅✅ Step 3 完了: inputs/analyze/items/actions/issues/trace API"
