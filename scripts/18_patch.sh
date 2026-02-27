#!/usr/bin/env bash
set -euo pipefail
GREEN='\033[0;32m'; BOLD='\033[1m'; RESET='\033[0m'
ok()      { echo -e "${GREEN}[OK]${RESET}    $*"; }
section() { echo -e "\n${BOLD}========== $* ==========${RESET}"; }

PROJECT_DIR="$HOME/projects/decision-os"
CLIENT_TS="$PROJECT_DIR/frontend/src/api/client.ts"

section "FE-1: client.ts の issueApi 更新（パス修正）"

python3 - << PYEOF
import re

path = "$CLIENT_TS"
with open(path, "r") as f:
    src = f.read()

new_issue_api = '''export const issueApi = {
  list: (params: {
    project_id?: string;
    status?: string;
    priority?: string;
    assignee_id?: string;
    intent_code?: string;
    label?: string;
    date_from?: string;
    date_to?: string;
    q?: string;
    sort?: string;
    limit?: number;
    offset?: number;
  } = {}) => {
    const p = new URLSearchParams();
    Object.entries(params).forEach(([k, v]) => { if (v !== undefined && v !== "") p.append(k, String(v)); });
    return api.get(\`/issues\${p.toString() ? "?" + p.toString() : ""}\`);
  },
  get:    (id: string)               => api.get(\`/issues/\${id}\`),
  create: (body: object)             => api.post("/issues", body),
  update: (id: string, body: object) => api.patch(\`/issues/\${id}\`, body),
};'''

src_new = re.sub(
    r'export const issueApi\s*=\s*\{.*?\};',
    new_issue_api,
    src,
    flags=re.DOTALL,
)

if src_new == src:
    # フォールバック: 末尾追記
    src_new = src.rstrip() + "\n\n" + new_issue_api + "\n"
    print("APPENDED")
else:
    print("REPLACED")

with open(path, "w") as f:
    f.write(src_new)
PYEOF
ok "client.ts: issueApi 更新完了"

section "FE-2: IssueList.tsx 確認"
ISSUE_LIST="$PROJECT_DIR/frontend/src/pages/IssueList.tsx"
if grep -q "フィルター" "$ISSUE_LIST" 2>/dev/null; then
  ok "IssueList.tsx: フィルターパネル確認済み ✅"
else
  echo "[WARN] IssueList.tsx にフィルターが見つかりません → 再作成します"
  # スクリプト本体の IssueList 部分を再適用
  bash "$HOME/projects/decision-os/scripts/18_add_filter_search.sh" 2>&1 | grep -E "\[OK\]|\[WARN\]" || true
fi

section "バックエンド再起動 & 確認"
cd "$PROJECT_DIR/backend"
source .venv/bin/activate
pkill -f "uvicorn" 2>/dev/null || true
sleep 1
nohup uvicorn app.main:app --host 0.0.0.0 --port 8089 --reload > "$PROJECT_DIR/backend.log" 2>&1 &
sleep 3

TOKEN=$(curl -s -X POST http://localhost:8089/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"demo@example.com","password":"demo1234"}' | \
  python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('access_token',''))" 2>/dev/null || echo "")

if [ -n "$TOKEN" ]; then
  RES=$(curl -s -H "Authorization: Bearer $TOKEN" \
    "http://localhost:8089/api/v1/issues?status=open&sort=priority_desc&limit=5")
  echo "$RES" | python3 -c "
import sys, json
d = json.load(sys.stdin)
if isinstance(d, list):
    print(f'total: {len(d)} (配列形式)')
else:
    print(f'total: {d.get(\"total\", \"?\")}')
" 2>/dev/null && ok "GET /issues?status=open&sort=priority_desc 確認 ✅" || echo "$RES"
fi

echo ""
echo "✅ 完了！ブラウザで確認:"
echo "  http://localhost:3008/issues → 🎛 フィルターボタンをクリック"
