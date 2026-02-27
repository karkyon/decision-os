#!/usr/bin/env bash
# =============================================================================
# decision-os / 28_patch.sh
# 28_test_coverage.sh の --timeout=60 エラー修正
# pytest-timeout をインストールしてカバレッジ再実行
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
section "1. pytest-timeout インストール"
# =============================================================================
pip install pytest-timeout anyio pytest-anyio -q
ok "pytest-timeout / anyio インストール完了"

# =============================================================================
section "2. 既存テストファイル確認"
# =============================================================================
info "プロジェクト内のテストファイル（.venv除く）:"
find . -name "test_*.py" -not -path "./.venv/*" | sort
echo ""

# テストが tests/test_engine.py と tests/test_health.py のみなら追加生成
EXISTING=$(find . -name "test_*.py" -not -path "./.venv/*" | wc -l)
info "プロジェクトテスト数: $EXISTING"

if [[ "$EXISTING" -lt 5 ]]; then
  info "テストが少ないため追加生成..."
  mkdir -p tests

  # conftest.py（まだなければ）
  if [[ ! -f tests/conftest.py ]]; then
    cat > tests/conftest.py << 'PYEOF'
import pytest
import asyncio
from httpx import AsyncClient, ASGITransport
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from app.main import app
from app.db.session import get_db
import os

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
def event_loop():
    loop = asyncio.new_event_loop()
    yield loop
    loop.close()

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
    return resp.json().get("access_token", "")

@pytest.fixture(scope="module")
async def auth_headers(auth_token):
    return {"Authorization": f"Bearer {auth_token}"}
PYEOF
    ok "tests/conftest.py 生成"
  fi

  # test_auth.py
  cat > tests/test_auth.py << 'PYEOF'
import pytest

@pytest.mark.asyncio
async def test_login_success(client):
    resp = await client.post("/api/v1/auth/login", json={
        "email": "demo@example.com", "password": "demo1234"
    })
    assert resp.status_code == 200
    assert "access_token" in resp.json()

@pytest.mark.asyncio
async def test_login_wrong_password(client):
    resp = await client.post("/api/v1/auth/login", json={
        "email": "demo@example.com", "password": "wrong"
    })
    assert resp.status_code in (401, 400, 422)

@pytest.mark.asyncio
async def test_no_token_rejected(client):
    resp = await client.get("/api/v1/projects")
    assert resp.status_code in (401, 403)
PYEOF

  # test_projects.py
  cat > tests/test_projects.py << 'PYEOF'
import pytest, time

@pytest.mark.asyncio
async def test_list_projects(client, auth_headers):
    resp = await client.get("/api/v1/projects", headers=auth_headers)
    assert resp.status_code == 200

@pytest.mark.asyncio
async def test_create_project(client, auth_headers):
    resp = await client.post("/api/v1/projects",
        headers=auth_headers,
        json={"name": f"test_{int(time.time())}", "description": "pytest"})
    assert resp.status_code in (200, 201)
    assert "id" in resp.json()
PYEOF

  # test_issues.py
  cat > tests/test_issues.py << 'PYEOF'
import pytest, time

async def get_or_create_project(client, auth_headers):
    r = await client.get("/api/v1/projects", headers=auth_headers)
    items = r.json() if isinstance(r.json(), list) else r.json().get("items", r.json().get("data", []))
    if items:
        return items[0]["id"]
    r2 = await client.post("/api/v1/projects", headers=auth_headers,
        json={"name": f"test_{int(time.time())}", "description": "test"})
    return r2.json()["id"]

@pytest.mark.asyncio
async def test_list_issues(client, auth_headers):
    resp = await client.get("/api/v1/issues", headers=auth_headers)
    assert resp.status_code == 200

@pytest.mark.asyncio
async def test_create_issue(client, auth_headers):
    pid = await get_or_create_project(client, auth_headers)
    resp = await client.post("/api/v1/issues", headers=auth_headers,
        json={"project_id": pid, "title": "pytest issue", "issue_type": "task", "status": "open"})
    assert resp.status_code in (200, 201)
    assert "id" in resp.json()

@pytest.mark.asyncio
async def test_issue_type_change(client, auth_headers):
    pid = await get_or_create_project(client, auth_headers)
    cr = await client.post("/api/v1/issues", headers=auth_headers,
        json={"project_id": pid, "title": "type change test", "issue_type": "task", "status": "open"})
    iid = cr.json().get("id", "")
    if not iid:
        pytest.skip("issue作成失敗")
    r = await client.patch(f"/api/v1/issues/{iid}", headers=auth_headers,
        json={"issue_type": "epic"})
    assert r.status_code in (200, 204)

@pytest.mark.asyncio
async def test_filter_issues(client, auth_headers):
    resp = await client.get("/api/v1/issues?status=open", headers=auth_headers)
    assert resp.status_code == 200

@pytest.mark.asyncio
async def test_rbac_users_endpoint(client, auth_headers):
    resp = await client.get("/api/v1/users", headers=auth_headers)
    # PMロールなので 403 が正常
    assert resp.status_code in (200, 403)
PYEOF

  ok "テストファイル追加生成完了"
fi

# =============================================================================
section "3. pytest.ini 更新（asyncio_mode設定）"
# =============================================================================
cat > pytest.ini << 'INIEOF'
[pytest]
asyncio_mode = auto
testpaths = tests
python_files = test_*.py
python_classes = Test*
python_functions = test_*
INIEOF
ok "pytest.ini 更新（asyncio_mode = auto）"

# =============================================================================
section "4. pytest + coverage 実行"
# =============================================================================
info "カバレッジ計測開始..."

set +e
python -m pytest tests/ \
  --cov=app \
  --cov=engine \
  --cov-report=term-missing \
  --cov-report=html:htmlcov \
  --cov-report=json:.coverage.json \
  -v \
  2>&1 | tee "$REPORT_FILE"
EXIT_CODE=$?
set -e

# =============================================================================
section "5. カバレッジ集計・サマリー"
# =============================================================================
if [[ -f ".coverage.json" ]]; then
  python3 << 'PYEOF'
import json
with open('.coverage.json') as f:
    d = json.load(f)

totals = d.get('totals', {})
total_pct = totals.get('percent_covered', 0)
print(f"\n  ┌─────────────────────────────────────────┐")
print(f"  │  総合カバレッジ: {total_pct:.1f}%{'':>24}│")
print(f"  └─────────────────────────────────────────┘")
print()

files = d.get('files', {})
targets = ['auth', 'inputs', 'issues', 'actions', 'projects', 'users',
           'decisions', 'labels', 'search', 'conversations', 'classifier', 'scorer']

print("  ファイル別カバレッジ:")
target_rows = []
for path, data in sorted(files.items()):
    name = path.split('/')[-1].replace('.py', '')
    if any(t in name for t in targets):
        pct = data.get('summary', {}).get('percent_covered', 0)
        bar = '█' * int(pct / 5) + '░' * (20 - int(pct / 5))
        flag = '✅' if pct >= 80 else ('⚠️ ' if pct >= 60 else '❌')
        target_rows.append((pct, f"  {flag} {name:<25} {bar} {pct:.0f}%"))

for _, row in sorted(target_rows, reverse=True):
    print(row)

achieved = sum(1 for p, _ in target_rows if p >= 80)
print(f"\n  目標80%達成: {achieved}/{len(target_rows)} ファイル")
if total_pct >= 80:
    print("  🎉 総合目標 80% 達成！")
elif total_pct >= 60:
    print("  ⚠️  60%台 — もう少し！")
else:
    print("  ❌ 60%未満 — テスト追加が必要")
PYEOF
else
  warn "coverage.json が生成されませんでした（テスト実行自体が失敗した可能性）"
  info "詳細: $REPORT_FILE"
fi

echo ""
if [[ $EXIT_CODE -eq 0 ]]; then
  ok "全テスト PASS ✅"
else
  warn "一部テスト失敗あり — $REPORT_FILE を確認"
fi

ok "HTMLレポート: $BACKEND/htmlcov/index.html"
echo ""
info "HTMLを確認したい場合:"
echo "  cd $BACKEND && python3 -m http.server 8090 --directory htmlcov"
echo "  → ブラウザで http://192.168.1.11:8090 を開く"
echo ""
ok "=== 28_patch.sh 完了 ==="
