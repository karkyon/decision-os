#!/usr/bin/env bash
# =============================================================================
# decision-os / Step 7a: バックエンド診断スクリプト
# 実行方法: bash 07a_diagnose.sh
# 目的: 現在のルーター実装を確認して修正方針を決定する
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

cd "$PROJECT_DIR"
set -a; source .env; set +a

# =============================================================================
section "A. ルーターファイル一覧"
ls -la "$ROUTER_DIR/"

# =============================================================================
section "B. items.py 全文"
echo "--- items.py ---"
cat "$ROUTER_DIR/items.py"

# =============================================================================
section "C. actions.py 全文"
echo "--- actions.py ---"
cat "$ROUTER_DIR/actions.py"

# =============================================================================
section "D. issues.py 全文"
echo "--- issues.py ---"
cat "$ROUTER_DIR/issues.py"

# =============================================================================
section "E. trace.py 全文"
echo "--- trace.py ---"
cat "$ROUTER_DIR/trace.py"

# =============================================================================
section "F. モデルファイル一覧"
ls -la "$MODEL_DIR/" 2>/dev/null || echo "models ディレクトリなし"
echo ""
for f in "$MODEL_DIR"/*.py; do
  [[ -f "$f" ]] || continue
  echo "--- $(basename $f) ---"
  cat "$f"
  echo ""
done

# =============================================================================
section "G. DBスキーマ（issues, actions, items, inputs テーブル）"
source "$BACKEND_DIR/.venv/bin/activate"
python3 << 'PYEOF'
import os
db_url = os.environ.get('DATABASE_URL', '')
if not db_url:
    print("DATABASE_URL 未設定")
    exit(0)

try:
    import sqlalchemy as sa
    engine = sa.create_engine(db_url)
    for tbl in ['issues', 'actions', 'items', 'inputs']:
        print(f"\n=== {tbl} テーブル ===")
        try:
            with engine.connect() as conn:
                rows = conn.execute(sa.text(f"""
                    SELECT column_name, data_type, is_nullable, column_default
                    FROM information_schema.columns
                    WHERE table_name = '{tbl}'
                    ORDER BY ordinal_position
                """))
                for row in rows:
                    print(f"  {row[0]:25} {row[1]:20} nullable={row[2]}")
        except Exception as e:
            print(f"  エラー: {e}")
except ImportError:
    print("sqlalchemy が利用できません")
PYEOF

# =============================================================================
section "H. 現在のAPIエンドポイント一覧（Swagger）"
curl -sf http://localhost:8089/openapi.json 2>/dev/null | python3 -c "
import json, sys
try:
    spec = json.load(sys.stdin)
    for path in sorted(spec.get('paths', {}).keys()):
        methods = [m.upper() for m in spec['paths'][path] if m in ['get','post','put','patch','delete']]
        print(f'  {\"|\".join(methods):20} {path}')
except Exception as e:
    print(f'エラー: {e}')
" || warn "Swagger 取得失敗"

# =============================================================================
section "I. 簡易APIテスト（認証なし）"

# ログインしてトークン取得
TOKEN=$(curl -sf -X POST http://localhost:8089/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"demo@example.com","password":"demo1234"}' | \
  python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('access_token',''))" 2>/dev/null || echo "")

if [[ -z "$TOKEN" ]]; then
  warn "ログイン失敗。以降のAPIテストをスキップ"
else
  success "ログイン成功"
  
  echo ""
  info "GET /api/v1/items → テスト:"
  curl -sf -o /dev/null -w "%{http_code}" \
    -H "Authorization: Bearer $TOKEN" \
    "http://localhost:8089/api/v1/items" || true
  echo ""
  
  info "GET /api/v1/items?input_id=test → テスト:"
  curl -sf -o /dev/null -w "%{http_code}" \
    -H "Authorization: Bearer $TOKEN" \
    "http://localhost:8089/api/v1/items?input_id=00000000-0000-0000-0000-000000000000" || true
  echo ""
  
  info "POST /api/v1/actions/test/convert → テスト:"
  curl -sf -o /dev/null -w "%{http_code}" \
    -X POST \
    -H "Authorization: Bearer $TOKEN" \
    "http://localhost:8089/api/v1/actions/00000000-0000-0000-0000-000000000000/convert" || true
  echo ""
fi

section "診断完了"
echo ""
echo "上記の出力内容を Claude に貼り付けてください。"
echo "ルーターとモデルの実装を確認し、正確なパッチを作成します。"
