#!/usr/bin/env bash
# =============================================================================
# decision-os  /  fix_ports.sh
# PostgreSQLのホスト側ポートを 5432 → 5439 に変更する
# =============================================================================
set -euo pipefail

GREEN='\033[0;32m'; CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'
success() { echo -e "${GREEN}[OK]${RESET}    $*"; }
info()    { echo -e "${CYAN}[INFO]${RESET}  $*"; }
section() { echo -e "\n${BOLD}========== $* ==========${RESET}"; }

PROJECT_DIR="$HOME/projects/decision-os"
cd "$PROJECT_DIR"

# ---------- 1. docker-compose.yml のポート変更 ----------
section "1. docker-compose.yml: 5432 → 5439"

sed -i 's|127.0.0.1:5432:5432|127.0.0.1:5439:5432|g' docker-compose.yml
success "docker-compose.yml を修正しました"
grep "5439" docker-compose.yml

# ---------- 2. .env の DATABASE_URL を更新 ----------
section "2. .env: DATABASE_URL のポートを 5439 に変更"

sed -i 's|@localhost:5432/|@localhost:5439/|g' .env
success ".env を修正しました"
grep "DATABASE_URL" .env

# ---------- 3. version: 行の除去（警告対策）----------
section "3. docker-compose.yml: version行を除去"

if grep -q "^version:" docker-compose.yml; then
  sed -i '/^version:/d' docker-compose.yml
  success "version行を削除しました"
else
  success "version行なし（スキップ）"
fi

# ---------- 4. 既存コンテナを再起動 ----------
section "4. コンテナ再起動"

docker compose down --remove-orphans 2>/dev/null || true
docker compose up -d

info "DB起動待機中..."
WAIT=0
set -a; source .env; set +a
until docker compose exec -T db pg_isready -U "${POSTGRES_USER:-dev}" -d "${POSTGRES_DB:-decisionos}" &>/dev/null; do
  sleep 2; WAIT=$((WAIT+2))
  [[ $WAIT -ge 60 ]] && { echo "タイムアウト"; exit 1; }
  info "${WAIT}秒経過..."
done

success "全サービス起動完了"
docker compose ps

section "完了"
echo ""
echo "  PostgreSQL: localhost:5439 → コンテナ内:5432"
echo ""
echo "次のステップ: bash 05_launch.sh"