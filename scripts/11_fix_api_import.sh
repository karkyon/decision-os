#!/bin/bash
# api.py の import 修正 + 再起動 + 動作確認
set -e
BASE=~/projects/decision-os/backend
cd $BASE
source .venv/bin/activate

echo "========== [1/3] api.py import修正 =========="
cat > app/api/v1/api.py << 'PYEOF'
from fastapi import APIRouter
from .routers import auth, inputs, analyze, items, actions, issues, trace, projects
from .routers.dashboard import router as dashboard_router

api_router = APIRouter()
api_router.include_router(auth.router)
api_router.include_router(projects.router)
api_router.include_router(inputs.router)
api_router.include_router(analyze.router)
api_router.include_router(items.router)
api_router.include_router(actions.router)
api_router.include_router(issues.router)
api_router.include_router(trace.router)
api_router.include_router(dashboard_router)
PYEOF
echo "[OK] api.py 修正完了"
cat app/api/v1/api.py

echo ""
echo "========== [2/3] バックエンド再起動 =========="
pkill -f "uvicorn app.main" 2>/dev/null || true
sleep 1
cd $BASE
nohup uvicorn app.main:app --host 0.0.0.0 --port 8089 --reload \
  > ~/projects/decision-os/logs/backend.log 2>&1 &
sleep 4

# 起動確認
HEALTH=$(curl -s http://localhost:8089/health)
echo "health: $HEALTH"
if echo "$HEALTH" | grep -q "ok"; then
  echo "[OK] バックエンド起動確認"
else
  echo "[ERROR] 起動失敗 → ログ確認:"
  tail -20 ~/projects/decision-os/logs/backend.log
  exit 1
fi

echo ""
echo "========== [3/3] 動作確認 =========="

TOKEN=$(curl -s -X POST http://localhost:8089/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"demo@example.com","password":"demo1234"}' \
  | python3 -c "import sys,json; print(json.load(sys.stdin).get('access_token','ERROR'))")
echo "TOKEN: ${TOKEN:0:40}..."

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
echo "$INPUT_RESP" | python3 -m json.tool 2>/dev/null || echo "$INPUT_RESP"
INPUT_ID=$(echo "$INPUT_RESP" | python3 -c "import sys,json; print(json.load(sys.stdin).get('id','ERROR'))" 2>/dev/null || echo "ERROR")
echo "→ INPUT_ID: $INPUT_ID"

echo ""
echo "--- [CHECK 2] analyze ---"
if [ "$INPUT_ID" != "ERROR" ] && [ -n "$INPUT_ID" ]; then
  curl -s -X POST http://localhost:8089/api/v1/analyze \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d "{\"input_id\": \"$INPUT_ID\"}" | python3 -m json.tool 2>/dev/null
else
  echo "[SKIP] INPUT登録失敗"
fi

echo ""
echo "--- [CHECK 3] dashboard/counts ---"
DASH=$(curl -s "http://localhost:8089/api/v1/dashboard/counts?project_id=$PROJECT_ID" \
  -H "Authorization: Bearer $TOKEN")
echo "$DASH" | python3 -m json.tool 2>/dev/null || echo "$DASH"

echo ""
if echo "$DASH" | grep -q "inputs"; then
  echo "✅ dashboard/counts OK"
else
  echo "❌ dashboard/counts NG"
fi

if [ "$INPUT_ID" != "ERROR" ] && [ -n "$INPUT_ID" ]; then
  echo "✅ POST /inputs (text フィールド) OK"
else
  echo "❌ POST /inputs NG"
fi
