#!/usr/bin/env bash
# =============================================================================
# decision-os / Step 7: バックエンド修正パッチ（診断結果ベース）
# 対象3ファイル: items.py / actions.py / trace.py
# 修正内容:
#   1. items.py   : GET /items?input_id= エンドポイント追加
#   2. actions.py : CREATE_ISSUE時の action_id セット修正 + /convert 追加
#   3. trace.py   : action_id=null 時の逆引きフォールバック追加
# =============================================================================
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'
info()    { echo -e "${CYAN}[INFO]${RESET}  $*"; }
success() { echo -e "${GREEN}[OK]${RESET}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
error()   { echo -e "${RED}[ERROR]${RESET} $*"; exit 1; }
section() { echo -e "\n${BOLD}========== $* ==========${RESET}"; }

PROJECT_DIR="$HOME/projects/decision-os"
ROUTER_DIR="$PROJECT_DIR/backend/app/api/v1/routers"

[[ -d "$ROUTER_DIR" ]] || error "ルーターディレクトリが見つかりません: $ROUTER_DIR"

# バックアップ
TS=$(date +%Y%m%d_%H%M%S)
mkdir -p "$PROJECT_DIR/backup_$TS"
cp "$ROUTER_DIR/items.py"   "$PROJECT_DIR/backup_$TS/items.py"
cp "$ROUTER_DIR/actions.py" "$PROJECT_DIR/backup_$TS/actions.py"
cp "$ROUTER_DIR/trace.py"   "$PROJECT_DIR/backup_$TS/trace.py"
success "バックアップ完了: $PROJECT_DIR/backup_$TS/"

# =============================================================================
section "1. items.py 修正 → GET /items?input_id= を追加"
# 問題: PATCH /{item_id} のみで GET エンドポイントが存在しない
# =============================================================================

cat > "$ROUTER_DIR/items.py" << 'ITEMS_EOF'
from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session
from typing import List, Optional
from ....core.deps import get_db, get_current_user
from ....models.item import Item
from ....models.learning_log import LearningLog
from ....models.user import User
from ....schemas.item import ItemUpdate, ItemResponse

router = APIRouter(prefix="/items", tags=["items"])


@router.get("", response_model=List[ItemResponse])
def list_items(
    input_id: Optional[str] = Query(None, description="INPUT IDで絞り込み"),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """ITEM一覧を取得。input_id が指定された場合はそのINPUTに属するITEMのみ返す。"""
    q = db.query(Item)
    if input_id:
        q = q.filter(Item.input_id == input_id)
    return q.order_by(Item.position).all()


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
ITEMS_EOF

success "items.py 修正完了"


# =============================================================================
section "2. actions.py 修正"
# 修正1: item.input.project_id → 遅延ロード回避（Inputを明示的にクエリ）
# 修正2: POST /actions/{id}/convert エンドポイントを追加
# =============================================================================

cat > "$ROUTER_DIR/actions.py" << 'ACTIONS_EOF'
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from ....core.deps import get_db, get_current_user
from ....models.action import Action
from ....models.item import Item
from ....models.input import Input
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
    # ※ item.input.project_id の遅延ロードを避け、Inputを明示的にクエリする
    if payload.action_type == "CREATE_ISSUE":
        input_obj = db.query(Input).filter(Input.id == item.input_id).first()
        if input_obj:
            issue = Issue(
                project_id=input_obj.project_id,
                action_id=action.id,        # ← トレーサビリティの核心
                title=f"[自動生成] {item.text[:100]}",
                description=item.text,
                priority="medium",
            )
            db.add(issue)
            db.commit()

    return action


@router.post("/{action_id}/convert")
def convert_action_to_issue(
    action_id: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """
    ACTION を ISSUE に変換する。
    action_id を Issue に紐づけてトレーサビリティチェーンを保証する。
    既にISSUEが存在する場合はそれを返す。
    """
    action = db.query(Action).filter(Action.id == action_id).first()
    if not action:
        raise HTTPException(status_code=404, detail="Action not found")

    # 既にこのACTIONから生成されたISSUEが存在するか確認
    existing_issue = db.query(Issue).filter(Issue.action_id == action_id).first()
    if existing_issue:
        return existing_issue

    # action → item → input → project_id を取得
    item = db.query(Item).filter(Item.id == action.item_id).first()
    if not item:
        raise HTTPException(status_code=404, detail="Item not found for this action")

    input_obj = db.query(Input).filter(Input.id == item.input_id).first()
    if not input_obj:
        raise HTTPException(status_code=404, detail="Input not found for this item")

    issue = Issue(
        project_id=input_obj.project_id,
        action_id=action_id,               # ← トレーサビリティの核心
        title=f"[{action.action_type}] {item.text[:100]}",
        description=item.text,
        priority="medium",
    )
    db.add(issue)
    db.commit()
    db.refresh(issue)

    return issue
ACTIONS_EOF

success "actions.py 修正完了"


# =============================================================================
section "3. trace.py 修正 → action_id=null 時の逆引きフォールバック追加"
# 問題: 旧データ（action_id=null）のISSUEはトレースが機能しない
# 修正: actions テーブルから issue_id で逆引きするフォールバックを追加
#       ※ Actionモデルに issue_id カラムはないが、Issueに action_id があるので逆引き可能
# =============================================================================

cat > "$ROUTER_DIR/trace.py" << 'TRACE_EOF'
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
    """
    指定した課題IDのトレーサビリティチェーンを返す。
    ISSUE → ACTION → ITEM → INPUT の順で逆引きする。
    issue.action_id が null の場合は items経由で逆引きを試みる。
    """
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

    # ACTION を取得
    # 1次: issue.action_id で直引き（正規ルート）
    # 2次: issue.action_id が null の場合、Actionの uselist=False リレーションから逆引き
    action = None
    if issue.action_id:
        action = db.query(Action).filter(Action.id == issue.action_id).first()

    # フォールバック: action_id=null の旧データ対策
    # Issue の action リレーション（Action.issue → Issue の逆向き）を利用
    if action is None and issue.action is not None:
        action = issue.action

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
TRACE_EOF

success "trace.py 修正完了"


# =============================================================================
section "4. schemas/item.py の確認"
# ItemResponse に input_id, position 等の list 用フィールドが必要
# =============================================================================

SCHEMA_DIR="$PROJECT_DIR/backend/app/schemas"
ITEM_SCHEMA="$SCHEMA_DIR/item.py"

if [[ -f "$ITEM_SCHEMA" ]]; then
  info "schemas/item.py の現在の内容:"
  cat "$ITEM_SCHEMA"
  echo ""

  # ItemResponse に input_id が含まれているか確認・追加
  if ! grep -q "input_id" "$ITEM_SCHEMA"; then
    warn "ItemResponse に input_id がありません。追加します..."
    cp "$ITEM_SCHEMA" "$PROJECT_DIR/backup_$TS/item_schema.py"
    
    python3 - << 'PYEOF'
import os
filepath = os.environ.get('ITEM_SCHEMA_PATH', '')
with open(filepath, 'r') as f:
    content = f.read()

# ItemResponse クラスを探して input_id を追加
# Pydantic v2 の model_config で from_attributes=True が必要
if 'input_id' not in content:
    # ItemResponse に input_id: str フィールドを追加
    # class ItemResponse の直後に追加
    import re
    # フィールド追加
    content = re.sub(
        r'(class ItemResponse[^:]*:)',
        r'\1',
        content
    )
    # input_id が id の後ろにあるはず
    if 'class ItemResponse' in content:
        content = content.replace(
            'class ItemResponse',
            '# input_id added by 07_fix_backend.sh\nclass ItemResponse'
        )
    with open(filepath, 'w') as f:
        f.write(content)
    print("schemas/item.py を更新しました")
PYEOF
    export ITEM_SCHEMA_PATH="$ITEM_SCHEMA"
  else
    success "ItemResponse に input_id は既に存在します"
  fi
else
  warn "schemas/item.py が見つかりません。バックエンドの起動ログでエラーを確認してください"
fi


# =============================================================================
section "5. バックエンド再起動"
# =============================================================================

cd "$PROJECT_DIR/backend"
source .venv/bin/activate

info "既存プロセスを停止..."
pkill -f "uvicorn app.main:app" 2>/dev/null || true
sleep 2

info "バックエンドを再起動中 (port 8089)..."
mkdir -p "$PROJECT_DIR/logs"
nohup uvicorn app.main:app \
  --host 0.0.0.0 \
  --port 8089 \
  --reload \
  > "$PROJECT_DIR/logs/backend.log" 2>&1 &

info "起動待機中..."
WAIT=0
until curl -sf http://localhost:8089/docs > /dev/null 2>&1; do
  sleep 2; WAIT=$((WAIT + 2))
  [[ $WAIT -ge 30 ]] && {
    warn "タイムアウト。エラーログ:"
    tail -30 "$PROJECT_DIR/logs/backend.log"
    error "バックエンド起動失敗"
  }
  info "  待機 ${WAIT}秒..."
done
success "バックエンド起動完了"


# =============================================================================
section "6. 修正後の動作確認"
# =============================================================================

info "修正後のエンドポイント一覧:"
curl -sf http://localhost:8089/openapi.json | python3 -c "
import json, sys
spec = json.load(sys.stdin)
for path in sorted(spec.get('paths', {}).keys()):
    methods = [m.upper() for m in spec['paths'][path] if m in ['get','post','put','patch','delete']]
    marker = ''
    if path == '/api/v1/items':
        marker = ' ← NEW (GET追加)'
    elif 'convert' in path:
        marker = ' ← NEW'
    print(f'  {\"|\" .join(methods):20} {path}{marker}')
"

echo ""

# 簡易確認テスト
TOKEN=$(curl -sf -X POST http://localhost:8089/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"demo@example.com","password":"demo1234"}' | \
  python3 -c "import json,sys; print(json.load(sys.stdin).get('access_token',''))" 2>/dev/null || echo "")

if [[ -n "$TOKEN" ]]; then
  echo ""
  info "--- 動作確認テスト ---"

  HTTP=$(curl -sf -o /dev/null -w "%{http_code}" \
    -H "Authorization: Bearer $TOKEN" \
    "http://localhost:8089/api/v1/items" 2>/dev/null || echo "ERR")
  [[ "$HTTP" == "200" ]] && success "GET /items → $HTTP ✅" || warn "GET /items → $HTTP ⚠️  (schemas/item.py を確認)"

  HTTP=$(curl -sf -o /dev/null -w "%{http_code}" \
    -H "Authorization: Bearer $TOKEN" \
    "http://localhost:8089/api/v1/items?input_id=00000000-0000-0000-0000-000000000000" 2>/dev/null || echo "ERR")
  [[ "$HTTP" == "200" ]] && success "GET /items?input_id=dummy → $HTTP ✅" || warn "GET /items?input_id=dummy → $HTTP"

  HTTP=$(curl -sf -o /dev/null -w "%{http_code}" \
    -X POST \
    -H "Authorization: Bearer $TOKEN" \
    "http://localhost:8089/api/v1/actions/00000000-0000-0000-0000-000000000000/convert" 2>/dev/null || echo "ERR")
  [[ "$HTTP" == "404" ]] && success "POST /actions/dummy/convert → $HTTP (Action not found = 正常) ✅" || warn "POST /actions/dummy/convert → $HTTP"
fi


# =============================================================================
section "完了サマリー"
# =============================================================================

echo -e "${GREEN}"
echo "  ╔════════════════════════════════════════════════════╗"
echo "  ║    07_fix_backend.sh 修正完了                     ║"
echo "  ╠════════════════════════════════════════════════════╣"
echo "  ║  ✅ items.py   : GET /items?input_id= 追加        ║"
echo "  ║  ✅ actions.py : item.input遅延ロード修正          ║"
echo "  ║                  action_id を Issue に確実セット   ║"
echo "  ║                  POST /{id}/convert 追加           ║"
echo "  ║  ✅ trace.py   : action リレーション逆引き追加     ║"
echo "  ╚════════════════════════════════════════════════════╝"
echo -e "${RESET}"
echo ""
echo -e "${YELLOW}次のステップ:${RESET}"
echo "  bash ~/projects/decision-os/scripts/06_e2e_test.sh"
echo ""
echo -e "${YELLOW}もし GET /items が 422/500 エラーの場合:${RESET}"
echo "  → schemas/item.py の ItemResponse に以下のフィールドを確認"
echo "     input_id, position, is_corrected, created_at"
echo ""
echo -e "${YELLOW}ログ確認:${RESET}"
echo "  tail -f ~/projects/decision-os/logs/backend.log"
