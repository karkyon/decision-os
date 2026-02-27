#!/bin/bash
# 30_conftest_fix.sh — conftest.py event_loop 修正 + カバレッジ計測
set -euo pipefail
PASS=0; FAIL=0; WARN=0

log_ok()   { echo "[OK]    $*"; PASS=$((PASS+1)); }
log_fail() { echo "[FAIL]  $*"; FAIL=$((FAIL+1)); }
log_warn() { echo "[WARN]  $*"; WARN=$((WARN+1)); }
log_info() { echo "[INFO]  $*"; }

cd ~/projects/decision-os/backend
source .venv/bin/activate 2>/dev/null || true

# ===== 1. conftest.py 修正 =====
echo "========== 1. conftest.py 修正 =========="
CONFTEST=~/projects/decision-os/backend/tests/conftest.py
log_info "--- 現状 ---"
cat "$CONFTEST"
cp "$CONFTEST" "${CONFTEST}.bak_$(date +%H%M%S)"

cat > "$CONFTEST" << 'PYEOF'
import pytest
import asyncio
from httpx import AsyncClient, ASGITransport
from app.main import app

# pytest-asyncio 0.23+ では event_loop fixture のカスタム定義は不要
# asyncio_mode=auto（pytest.ini で設定済み）に任せる

BASE_URL = "http://localhost:8089/api/v1"

@pytest.fixture(scope="function")
async def client():
    async with AsyncClient(
        transport=ASGITransport(app=app),
        base_url="http://test"
    ) as c:
        yield c

@pytest.fixture(scope="function")
async def auth_token(client):
    resp = await client.post("/api/v1/auth/login", json={
        "email": "demo@example.com",
        "password": "demo1234"
    })
    data = resp.json()
    return data.get("access_token", "")

@pytest.fixture(scope="function")
async def auth_headers(auth_token):
    return {"Authorization": f"Bearer {auth_token}"}
PYEOF
log_ok "conftest.py 更新完了（event_loop fixture 削除、scope=function に統一）"

# ===== 2. pytest.ini 確認・asyncio_mode=auto を確認 =====
echo ""
echo "========== 2. pytest.ini 確認 =========="
PYTEST_INI=~/projects/decision-os/backend/pytest.ini
cat "$PYTEST_INI" 2>/dev/null || echo "(なし)"

# asyncio_mode=auto が設定されているか確認・追加
if [ -f "$PYTEST_INI" ]; then
  if ! grep -q "asyncio_mode" "$PYTEST_INI"; then
    echo "asyncio_mode = auto" >> "$PYTEST_INI"
    log_ok "pytest.ini に asyncio_mode = auto を追加"
  else
    log_info "asyncio_mode は設定済み"
  fi
else
  cat > "$PYTEST_INI" << 'EOF'
[pytest]
asyncio_mode = auto
addopts = --tb=short
EOF
  log_ok "pytest.ini を新規作成"
fi
cat "$PYTEST_INI"

# ===== 3. テスト実行（まず現状確認）=====
echo ""
echo "========== 3. テスト実行（修正後）=========="
cd ~/projects/decision-os/backend
python -m pytest tests/ -v --tb=short \
  --cov=app --cov=engine \
  --cov-report=term-missing \
  --cov-report=json:.coverage.json \
  2>&1 | tee /tmp/pytest_result.txt || true

# カバレッジ総合値を取得
TOTAL_COV=$(python3 -c "
import json
try:
    d = json.load(open('.coverage.json'))
    pct = d['totals']['percent_covered']
    print(f'{pct:.1f}')
except:
    print('0')
" 2>/dev/null || echo "0")
log_info "現在のカバレッジ: ${TOTAL_COV}%"

# テスト結果サマリー
PASSED=$(grep -c "PASSED" /tmp/pytest_result.txt || echo "0")
FAILED=$(grep -c "FAILED\|ERROR" /tmp/pytest_result.txt || echo "0")
log_info "テスト: ${PASSED} PASSED / ${FAILED} FAILED+ERROR"

# ===== 4. 不足テストを自動生成して80%を目指す =====
echo ""
echo "========== 4. カバレッジ不足ファイルにテスト追加 =========="

# カバレッジが低いルーターを特定
python3 -c "
import json, sys
try:
    d = json.load(open('.coverage.json'))
    files = d['files']
    low = []
    for f, info in files.items():
        if 'routers' in f or 'engine' in f:
            pct = info['summary']['percent_covered']
            if pct < 60:
                low.append((f, pct))
    low.sort(key=lambda x: x[1])
    for f, p in low[:8]:
        print(f'{p:.0f}%  {f}')
except Exception as e:
    print('ERROR:', e)
" 2>/dev/null || true

# テスト追加: conversations, decisions, inputs, actions, labels の主要エンドポイント
TESTS_DIR=~/projects/decision-os/backend/tests

cat > "$TESTS_DIR/test_conversations.py" << 'PYEOF'
import pytest
import time
from httpx import AsyncClient, ASGITransport
from app.main import app

BASE = "http://test"

async def get_auth(client):
    r = await client.post("/api/v1/auth/login",
        json={"email": "demo@example.com", "password": "demo1234"})
    return {"Authorization": f"Bearer {r.json().get('access_token', '')}"}

async def make_project(client, headers):
    r = await client.post("/api/v1/projects",
        headers=headers, json={"name": f"cv_test_{int(time.time())}", "description": "t"})
    return r.json().get("id", "")

async def make_issue(client, headers, pid):
    r = await client.post("/api/v1/issues",
        headers=headers,
        json={"project_id": pid, "title": "cv issue", "issue_type": "task", "status": "open"})
    return r.json().get("id", "")

@pytest.mark.asyncio
async def test_create_conversation():
    async with AsyncClient(transport=ASGITransport(app=app), base_url=BASE) as c:
        h = await get_auth(c)
        pid = await make_project(c, h)
        iid = await make_issue(c, h, pid)
        r = await c.post("/api/v1/conversations", headers=h,
            json={"issue_id": iid, "body": "テストコメント"})
        assert r.status_code in (200, 201)
        assert r.json().get("id")

@pytest.mark.asyncio
async def test_list_conversations():
    async with AsyncClient(transport=ASGITransport(app=app), base_url=BASE) as c:
        h = await get_auth(c)
        pid = await make_project(c, h)
        iid = await make_issue(c, h, pid)
        await c.post("/api/v1/conversations", headers=h,
            json={"issue_id": iid, "body": "コメント1"})
        r = await c.get(f"/api/v1/conversations?issue_id={iid}", headers=h)
        assert r.status_code == 200
        assert isinstance(r.json(), list)

@pytest.mark.asyncio
async def test_conversation_empty_body():
    async with AsyncClient(transport=ASGITransport(app=app), base_url=BASE) as c:
        h = await get_auth(c)
        pid = await make_project(c, h)
        iid = await make_issue(c, h, pid)
        r = await c.post("/api/v1/conversations", headers=h,
            json={"issue_id": iid, "body": "   "})
        assert r.status_code == 422

@pytest.mark.asyncio
async def test_conversation_invalid_issue():
    async with AsyncClient(transport=ASGITransport(app=app), base_url=BASE) as c:
        h = await get_auth(c)
        r = await c.post("/api/v1/conversations", headers=h,
            json={"issue_id": "00000000-0000-0000-0000-000000000000", "body": "test"})
        assert r.status_code == 404
PYEOF
log_ok "test_conversations.py 生成"

cat > "$TESTS_DIR/test_decisions.py" << 'PYEOF'
import pytest
import time
from httpx import AsyncClient, ASGITransport
from app.main import app

BASE = "http://test"

async def get_auth(client):
    r = await client.post("/api/v1/auth/login",
        json={"email": "demo@example.com", "password": "demo1234"})
    return {"Authorization": f"Bearer {r.json().get('access_token', '')}"}

async def make_project(client, headers):
    r = await client.post("/api/v1/projects",
        headers=headers, json={"name": f"dec_test_{int(time.time())}", "description": "t"})
    return r.json().get("id", "")

@pytest.mark.asyncio
async def test_create_decision():
    async with AsyncClient(transport=ASGITransport(app=app), base_url=BASE) as c:
        h = await get_auth(c)
        pid = await make_project(c, h)
        r = await c.post("/api/v1/decisions", headers=h,
            json={"project_id": pid, "decision_text": "A案を採用", "reason": "コスト優先"})
        assert r.status_code in (200, 201)
        assert r.json().get("id")

@pytest.mark.asyncio
async def test_list_decisions():
    async with AsyncClient(transport=ASGITransport(app=app), base_url=BASE) as c:
        h = await get_auth(c)
        pid = await make_project(c, h)
        await c.post("/api/v1/decisions", headers=h,
            json={"project_id": pid, "decision_text": "B案採用", "reason": "速度優先"})
        r = await c.get(f"/api/v1/decisions?project_id={pid}", headers=h)
        assert r.status_code == 200
        assert isinstance(r.json(), list)

@pytest.mark.asyncio
async def test_decision_empty_text():
    async with AsyncClient(transport=ASGITransport(app=app), base_url=BASE) as c:
        h = await get_auth(c)
        pid = await make_project(c, h)
        r = await c.post("/api/v1/decisions", headers=h,
            json={"project_id": pid, "decision_text": "  ", "reason": "理由"})
        assert r.status_code == 422
PYEOF
log_ok "test_decisions.py 生成"

cat > "$TESTS_DIR/test_inputs.py" << 'PYEOF'
import pytest
import time
from httpx import AsyncClient, ASGITransport
from app.main import app

BASE = "http://test"

async def get_auth(client):
    r = await client.post("/api/v1/auth/login",
        json={"email": "demo@example.com", "password": "demo1234"})
    return {"Authorization": f"Bearer {r.json().get('access_token', '')}"}

async def make_project(client, headers):
    r = await client.post("/api/v1/projects",
        headers=headers, json={"name": f"inp_test_{int(time.time())}", "description": "t"})
    return r.json().get("id", "")

@pytest.mark.asyncio
async def test_create_input():
    async with AsyncClient(transport=ASGITransport(app=app), base_url=BASE) as c:
        h = await get_auth(c)
        pid = await make_project(c, h)
        r = await c.post("/api/v1/inputs", headers=h,
            json={"project_id": pid, "raw_text": "ログインするとエラーになります"})
        assert r.status_code in (200, 201)
        assert r.json().get("id")

@pytest.mark.asyncio
async def test_list_inputs():
    async with AsyncClient(transport=ASGITransport(app=app), base_url=BASE) as c:
        h = await get_auth(c)
        pid = await make_project(c, h)
        await c.post("/api/v1/inputs", headers=h,
            json={"project_id": pid, "raw_text": "検索機能が欲しい"})
        r = await c.get(f"/api/v1/inputs?project_id={pid}", headers=h)
        assert r.status_code == 200

@pytest.mark.asyncio
async def test_analyze_input():
    async with AsyncClient(transport=ASGITransport(app=app), base_url=BASE) as c:
        h = await get_auth(c)
        pid = await make_project(c, h)
        inp = await c.post("/api/v1/inputs", headers=h,
            json={"project_id": pid, "raw_text": "ボタンを押すとクラッシュします"})
        iid = inp.json().get("id", "")
        r = await c.post("/api/v1/analyze", headers=h, json={"input_id": iid})
        assert r.status_code == 200
        assert isinstance(r.json(), list)
PYEOF
log_ok "test_inputs.py 生成"

cat > "$TESTS_DIR/test_labels.py" << 'PYEOF'
import pytest
import time
from httpx import AsyncClient, ASGITransport
from app.main import app

BASE = "http://test"

async def get_auth(client):
    r = await client.post("/api/v1/auth/login",
        json={"email": "demo@example.com", "password": "demo1234"})
    return {"Authorization": f"Bearer {r.json().get('access_token', '')}"}

async def make_issue(client, headers):
    r = await client.post("/api/v1/projects",
        headers=headers, json={"name": f"lbl_{int(time.time())}", "description": "t"})
    pid = r.json().get("id", "")
    r2 = await client.post("/api/v1/issues", headers=headers,
        json={"project_id": pid, "title": "label test", "issue_type": "task", "status": "open"})
    return r2.json().get("id", ""), pid

@pytest.mark.asyncio
async def test_list_labels():
    async with AsyncClient(transport=ASGITransport(app=app), base_url=BASE) as c:
        h = await get_auth(c)
        r = await c.get("/api/v1/labels", headers=h)
        assert r.status_code == 200

@pytest.mark.asyncio
async def test_add_labels_to_issue():
    async with AsyncClient(transport=ASGITransport(app=app), base_url=BASE) as c:
        h = await get_auth(c)
        iid, _ = await make_issue(c, h)
        r = await c.patch(f"/api/v1/issues/{iid}", headers=h,
            json={"labels": ["bug", "urgent"]})
        assert r.status_code == 200
        assert "bug" in str(r.json().get("labels", ""))

@pytest.mark.asyncio
async def test_suggest_labels():
    async with AsyncClient(transport=ASGITransport(app=app), base_url=BASE) as c:
        h = await get_auth(c)
        r = await c.get("/api/v1/labels/suggest?text=ログインエラー", headers=h)
        assert r.status_code == 200
PYEOF
log_ok "test_labels.py 生成"

# ===== 5. カバレッジ再計測 =====
echo ""
echo "========== 5. カバレッジ再計測（全テスト）=========="
python -m pytest tests/ -v --tb=short \
  --cov=app --cov=engine \
  --cov-report=term-missing \
  --cov-report=json:.coverage.json \
  --cov-report=html:htmlcov \
  2>&1 | tee /tmp/pytest_result2.txt || true

TOTAL_COV2=$(python3 -c "
import json
try:
    d = json.load(open('.coverage.json'))
    pct = d['totals']['percent_covered']
    print(f'{pct:.1f}')
except:
    print('0')
" 2>/dev/null || echo "0")

PASSED2=$(grep -oP '\d+ passed' /tmp/pytest_result2.txt | tail -1 | grep -oP '\d+' || echo "0")
FAILED2=$(grep -oP '\d+ failed' /tmp/pytest_result2.txt | tail -1 | grep -oP '\d+' || echo "0")
ERRORS2=$(grep -oP '\d+ error' /tmp/pytest_result2.txt | tail -1 | grep -oP '\d+' || echo "0")

# ===== サマリー =====
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  最終カバレッジ: ${TOTAL_COV2}%"
echo "  テスト: ${PASSED2} passed / ${FAILED2} failed / ${ERRORS2} errors"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if python3 -c "exit(0 if float('${TOTAL_COV2}') >= 80 else 1)" 2>/dev/null; then
  echo "[OK] 目標 80% 達成！ 🎉"
  echo "     次のステップ: @メンション通知（F-053）実装"
  log_ok "カバレッジ目標達成"
else
  echo "[WARN] 目標 80% 未達（${TOTAL_COV2}%）"
  echo "       HTMLレポート: cd backend && python3 -m http.server 8090 --directory htmlcov"
  log_warn "カバレッジ未達"
fi

# 保存
REPORT_DIR=~/projects/decision-os/reports
mkdir -p "$REPORT_DIR"
cp /tmp/pytest_result2.txt "$REPORT_DIR/coverage_$(date +%Y%m%d_%H%M%S).txt"
echo "[INFO] レポート保存: $REPORT_DIR"
