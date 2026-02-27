#!/usr/bin/env bash
# =============================================================================
# decision-os / 28_test_coverage.sh
# バックエンド pytest + coverage 一括計測
# 目標: 主要APIルーター 80%以上
# 出力: coverage_report_YYYYMMDD_HHMMSS.txt + HTML レポート
# =============================================================================
set -euo pipefail

GREEN='\033[0;32m'; RED='\033[0;31m'; CYAN='\033[0;36m'
YELLOW='\033[1;33m'; BOLD='\033[1m'; RESET='\033[0m'

ok()      { echo -e "${GREEN}[OK]${RESET}    $*"; }
err()     { echo -e "${RED}[ERR]${RESET}   $*"; }
info()    { echo -e "${CYAN}[INFO]${RESET}  $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
section() { echo -e "\n${BOLD}========== $* ==========${RESET}"; }

PROJECT_DIR="$HOME/projects/decision-os"
BACKEND="$PROJECT_DIR/backend"
REPORTS_DIR="$PROJECT_DIR/reports"
TIMESTAMP=$(date '+%Y%m%d_%H%M%S')
REPORT_FILE="$REPORTS_DIR/coverage_report_$TIMESTAMP.txt"

mkdir -p "$REPORTS_DIR"
cd "$BACKEND"
source .venv/bin/activate

# =============================================================================
section "1. 依存パッケージ確認・インストール"
# =============================================================================
pip install pytest pytest-cov pytest-asyncio httpx -q
ok "pytest / pytest-cov / httpx インストール完了"

# =============================================================================
section "2. テストファイル確認"
# =============================================================================
TEST_FILES=$(find . -name "test_*.py" -o -name "*_test.py" 2>/dev/null | grep -v __pycache__ || true)
if [[ -z "$TEST_FILES" ]]; then
  warn "既存テストファイルなし — 主要ルーターのテストを自動生成します"
  mkdir -p tests

  # conftest.py
  cat > tests/conftest.py << 'PYEOF'
import pytest
from httpx import AsyncClient, ASGITransport
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from app.main import app
from app.db.session import get_db
from app.db.base import Base
import os

TEST_DB_URL = os.environ.get(
    "TEST_DATABASE_URL",
    "postgresql://dev:devpass_2ed89487@localhost:5439/decisionos_test"
)

# テスト用DB（本番DBをそのまま使う場合は本番URLにフォールバック）
PROD_DB_URL = os.environ.get(
    "DATABASE_URL",
    "postgresql://dev:devpass_2ed89487@localhost:5439/decisionos"
)

engine = create_engine(PROD_DB_URL)
TestingSessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

def override_get_db():
    db = TestingSessionLocal()
    try:
        yield db
    finally:
        db.close()

app.dependency_overrides[get_db] = override_get_db

@pytest.fixture(scope="session")
def anyio_backend():
    return "asyncio"

@pytest.fixture(scope="module")
async def client():
    async with AsyncClient(
        transport=ASGITransport(app=app),
        base_url="http://test"
    ) as c:
        yield c

@pytest.fixture(scope="module")
async def auth_token(client):
    resp = await client.post("/api/v1/auth/login", json={
        "email": "demo@example.com",
        "password": "demo1234"
    })
    data = resp.json()
    token = data.get("access_token", "")
    return token

@pytest.fixture(scope="module")
def auth_headers(auth_token):
    return {"Authorization": f"Bearer {auth_token}"}
PYEOF

  # test_auth.py
  cat > tests/test_auth.py << 'PYEOF'
import pytest
from httpx import AsyncClient

@pytest.mark.anyio
async def test_login_success(client):
    resp = await client.post("/api/v1/auth/login", json={
        "email": "demo@example.com",
        "password": "demo1234"
    })
    assert resp.status_code == 200
    data = resp.json()
    assert "access_token" in data
    assert data["access_token"] != ""

@pytest.mark.anyio
async def test_login_wrong_password(client):
    resp = await client.post("/api/v1/auth/login", json={
        "email": "demo@example.com",
        "password": "wrongpassword"
    })
    assert resp.status_code in (401, 400, 422)

@pytest.mark.anyio
async def test_login_unknown_email(client):
    resp = await client.post("/api/v1/auth/login", json={
        "email": "nobody@nowhere.com",
        "password": "dummy"
    })
    assert resp.status_code in (401, 400, 404, 422)

@pytest.mark.anyio
async def test_protected_without_token(client):
    resp = await client.get("/api/v1/projects")
    assert resp.status_code in (401, 403)
PYEOF

  # test_projects.py
  cat > tests/test_projects.py << 'PYEOF'
import pytest
from httpx import AsyncClient
import time

@pytest.mark.anyio
async def test_list_projects(client, auth_headers):
    resp = await client.get("/api/v1/projects", headers=auth_headers)
    assert resp.status_code == 200

@pytest.mark.anyio
async def test_create_project(client, auth_headers):
    resp = await client.post("/api/v1/projects",
        headers=auth_headers,
        json={"name": f"テストプロジェクト_{int(time.time())}", "description": "pytest作成"}
    )
    assert resp.status_code in (200, 201)
    data = resp.json()
    assert "id" in data
PYEOF

  # test_inputs.py
  cat > tests/test_inputs.py << 'PYEOF'
import pytest
from httpx import AsyncClient
import time

async def get_project_id(client, auth_headers):
    resp = await client.get("/api/v1/projects", headers=auth_headers)
    data = resp.json()
    items = data if isinstance(data, list) else data.get("items", data.get("data", []))
    if items:
        return items[0]["id"]
    # 作成
    r = await client.post("/api/v1/projects",
        headers=auth_headers,
        json={"name": f"test_{int(time.time())}", "description": "test"})
    return r.json()["id"]

@pytest.mark.anyio
async def test_create_input(client, auth_headers):
    pid = await get_project_id(client, auth_headers)
    resp = await client.post("/api/v1/inputs",
        headers=auth_headers,
        json={
            "project_id": pid,
            "source_text": "ログインするとエラーが出て進めません"
        }
    )
    assert resp.status_code in (200, 201)
    data = resp.json()
    assert "id" in data

@pytest.mark.anyio
async def test_list_inputs(client, auth_headers):
    resp = await client.get("/api/v1/inputs", headers=auth_headers)
    assert resp.status_code == 200

@pytest.mark.anyio
async def test_analyze(client, auth_headers):
    pid = await get_project_id(client, auth_headers)
    # まずInputを作成
    ir = await client.post("/api/v1/inputs",
        headers=auth_headers,
        json={"project_id": pid, "source_text": "検索機能を追加してほしいです。バグも直してください。"}
    )
    input_id = ir.json().get("id", "")
    if not input_id:
        pytest.skip("Input作成失敗")

    resp = await client.post("/api/v1/analyze",
        headers=auth_headers,
        json={"input_id": input_id, "project_id": pid}
    )
    assert resp.status_code in (200, 201, 202)
PYEOF

  # test_issues.py
  cat > tests/test_issues.py << 'PYEOF'
import pytest
from httpx import AsyncClient
import time

async def get_project_id(client, auth_headers):
    resp = await client.get("/api/v1/projects", headers=auth_headers)
    data = resp.json()
    items = data if isinstance(data, list) else data.get("items", data.get("data", []))
    if items:
        return items[0]["id"]
    r = await client.post("/api/v1/projects",
        headers=auth_headers,
        json={"name": f"test_{int(time.time())}", "description": "test"})
    return r.json()["id"]

@pytest.mark.anyio
async def test_create_issue(client, auth_headers):
    pid = await get_project_id(client, auth_headers)
    resp = await client.post("/api/v1/issues",
        headers=auth_headers,
        json={
            "project_id": pid,
            "title": "pytest テスト課題",
            "issue_type": "task",
            "status": "open",
            "priority": "medium"
        }
    )
    assert resp.status_code in (200, 201)
    data = resp.json()
    assert "id" in data
    return data["id"]

@pytest.mark.anyio
async def test_list_issues(client, auth_headers):
    resp = await client.get("/api/v1/issues", headers=auth_headers)
    assert resp.status_code == 200

@pytest.mark.anyio
async def test_issue_filter(client, auth_headers):
    pid = await get_project_id(client, auth_headers)
    resp = await client.get(
        f"/api/v1/issues?project_id={pid}&status=open",
        headers=auth_headers
    )
    assert resp.status_code == 200

@pytest.mark.anyio
async def test_issue_type_change(client, auth_headers):
    pid = await get_project_id(client, auth_headers)
    cr = await client.post("/api/v1/issues",
        headers=auth_headers,
        json={"project_id": pid, "title": "型変更テスト", "issue_type": "task", "status": "open"})
    issue_id = cr.json().get("id", "")
    if not issue_id:
        pytest.skip("Issue作成失敗")

    resp = await client.patch(f"/api/v1/issues/{issue_id}",
        headers=auth_headers,
        json={"issue_type": "epic"})
    assert resp.status_code in (200, 204)

@pytest.mark.anyio
async def test_parent_child_issue(client, auth_headers):
    pid = await get_project_id(client, auth_headers)
    parent = await client.post("/api/v1/issues",
        headers=auth_headers,
        json={"project_id": pid, "title": "親課題", "issue_type": "epic", "status": "open"})
    parent_id = parent.json().get("id", "")
    if not parent_id:
        pytest.skip("親課題作成失敗")

    child = await client.post("/api/v1/issues",
        headers=auth_headers,
        json={"project_id": pid, "title": "子課題", "issue_type": "task",
              "status": "open", "parent_id": parent_id})
    assert child.status_code in (200, 201)
    assert child.json().get("parent_id") == parent_id
PYEOF

  # test_engine.py
  cat > tests/test_engine.py << 'PYEOF'
import pytest
import sys
import os
sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))

def test_classify_bug():
    from engine.classifier import classify_intent
    intent, score = classify_intent("ログインするとエラーが出て進めません")
    assert intent == "BUG"
    assert score > 0

def test_classify_req():
    from engine.classifier import classify_intent
    intent, score = classify_intent("検索機能を追加してほしいです")
    assert intent == "REQ"
    assert score > 0

def test_classify_qst():
    from engine.classifier import classify_intent
    intent, score = classify_intent("パスワードのリセット方法を教えてください")
    assert intent == "QST"
    assert score > 0

def test_classify_imp():
    from engine.classifier import classify_intent
    intent, score = classify_intent("検索が遅くて使いにくいです")
    assert intent == "IMP"
    assert score > 0

def test_classify_fbk():
    from engine.classifier import classify_intent
    intent, score = classify_intent("新機能、とても使いやすくて助かります")
    assert intent == "FBK"
    assert score > 0

def test_bulk_accuracy():
    from engine.classifier import classify_intent
    cases = [
        ("ログインするとエラーが出て進めません", "BUG"),
        ("アプリが突然クラッシュします", "BUG"),
        ("500エラーが返ってくる", "BUG"),
        ("検索機能を追加してほしいです", "REQ"),
        ("ダークモードに対応をお願いしたいです", "REQ"),
        ("パスワードのリセット方法を教えてください", "QST"),
        ("このAPIの仕様はどこで確認できますか", "QST"),
        ("検索が遅くて使いにくいです", "IMP"),
        ("入力フォームが使いづらいです", "IMP"),
        ("新機能、とても使いやすくて助かります", "FBK"),
    ]
    correct = sum(1 for text, expected in cases
                  if classify_intent(text)[0] == expected)
    accuracy = correct / len(cases)
    print(f"\n精度: {correct}/{len(cases)} = {accuracy:.0%}")
    assert accuracy >= 0.9, f"精度が90%未満: {accuracy:.0%}"
PYEOF

  # test_rbac.py
  cat > tests/test_rbac.py << 'PYEOF'
import pytest
from httpx import AsyncClient

@pytest.mark.anyio
async def test_users_endpoint_requires_auth(client):
    resp = await client.get("/api/v1/users")
    assert resp.status_code in (401, 403)

@pytest.mark.anyio
async def test_users_endpoint_with_auth(client, auth_headers):
    resp = await client.get("/api/v1/users", headers=auth_headers)
    # PM ロールなので 403 が正常（Admin のみ許可）
    assert resp.status_code in (200, 403)
PYEOF

  ok "テストファイル 7 本を自動生成しました"
  echo ""
  find tests/ -name "*.py" | sort
else
  info "既存テストファイル:"
  echo "$TEST_FILES"
fi

# =============================================================================
section "3. pytest.ini / setup.cfg 確認・生成"
# =============================================================================
if [[ ! -f pytest.ini ]] && [[ ! -f setup.cfg ]]; then
  cat > pytest.ini << 'INIEOF'
[pytest]
asyncio_mode = auto
testpaths = tests
python_files = test_*.py *_test.py
python_classes = Test*
python_functions = test_*
INIEOF
  ok "pytest.ini 生成"
fi

# =============================================================================
section "4. pytest + coverage 実行"
# =============================================================================
info "カバレッジ計測開始... (数分かかる場合があります)"

set +e
python -m pytest tests/ \
  --cov=app \
  --cov=engine \
  --cov-report=term-missing \
  --cov-report=html:htmlcov \
  --cov-report=json:.coverage.json \
  -v \
  --timeout=60 \
  2>&1 | tee "$REPORT_FILE"
EXIT_CODE=$?
set -e

# =============================================================================
section "5. カバレッジ集計"
# =============================================================================
if [[ -f ".coverage.json" ]]; then
  python3 -c "
import json
with open('.coverage.json') as f:
    d = json.load(f)

totals = d.get('totals', {})
total_pct = totals.get('percent_covered', 0)

files = d.get('files', {})
print(f'')
print(f'  総合カバレッジ: {total_pct:.1f}%')
print(f'')
print(f'  ファイル別（主要ルーター）:')

targets = ['auth', 'inputs', 'issues', 'actions', 'projects', 'users',
           'decisions', 'labels', 'search', 'conversations', 'classifier', 'scorer']

for path, data in sorted(files.items()):
    name = path.split('/')[-1].replace('.py', '')
    if any(t in name for t in targets):
        pct = data.get('summary', {}).get('percent_covered', 0)
        bar = '█' * int(pct / 5) + '░' * (20 - int(pct / 5))
        flag = '✅' if pct >= 80 else ('⚠️ ' if pct >= 60 else '❌')
        print(f'  {flag} {name:<25} {bar} {pct:.0f}%')
"
fi

echo ""
if [[ $EXIT_CODE -eq 0 ]]; then
  ok "全テスト PASS ✅"
else
  warn "一部テスト失敗あり（詳細: $REPORT_FILE）"
fi

ok "HTMLレポート: $BACKEND/htmlcov/index.html"
ok "テキストレポート: $REPORT_FILE"
echo ""
echo -e "${BOLD}次のステップ:${RESET}"
echo "  ブラウザで確認: http://localhost:8089/../htmlcov/index.html"
echo "  またはサーバーで: python3 -m http.server 8090 --directory $BACKEND/htmlcov"
echo ""
echo -e "${GREEN}${BOLD}=== 28_test_coverage.sh 完了 ===${RESET}"
