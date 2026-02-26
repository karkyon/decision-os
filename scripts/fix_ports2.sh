#!/usr/bin/env bash
# =============================================================================
# decision-os  /  fix_ports2.sh
# Redis 6379 → 6380 に変更、DATABASE_URLの変数展開バグも修正
# =============================================================================
set -euo pipefail

GREEN='\033[0;32m'; CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'
success() { echo -e "${GREEN}[OK]${RESET}    $*"; }
info()    { echo -e "${CYAN}[INFO]${RESET}  $*"; }
section() { echo -e "\n${BOLD}========== $* ==========${RESET}"; }

PROJECT_DIR="$HOME/projects/decision-os"
cd "$PROJECT_DIR"

# ---------- 1. Redis ポート変更 ----------
section "1. docker-compose.yml: Redis 6379 → 6380"
sed -i 's|127.0.0.1:6379:6379|127.0.0.1:6380:6379|g' docker-compose.yml
success "docker-compose.yml 修正完了"
grep "6380" docker-compose.yml

# ---------- 2. .env の REDIS_URL を更新 ----------
section "2. .env: REDIS_URL のポートを 6380 に変更"
sed -i 's|redis://localhost:6379|redis://localhost:6380|g' .env
success ".env 修正完了"
grep "REDIS_URL" .env

# ---------- 3. DATABASE_URL の変数展開バグ修正 ----------
# 現状: DATABASE_URL=postgresql://dev:${POSTGRES_PASSWORD}@...
# 正常: DATABASE_URL=postgresql://dev:実際のパスワード@...
section "3. .env: DATABASE_URL の変数展開バグ修正"

# POSTGRES_PASSWORDの実際の値を取得
PGPASS=$(grep "^POSTGRES_PASSWORD=" .env | cut -d'=' -f2)
info "POSTGRES_PASSWORD: ${PGPASS}"

# DATABASE_URLを実際の値で書き直す
sed -i "s|DATABASE_URL=postgresql://dev:\${POSTGRES_PASSWORD}@localhost:5439/decisionos|DATABASE_URL=postgresql://dev:${PGPASS}@localhost:5439/decisionos|g" .env
success "DATABASE_URL を修正しました"
grep "DATABASE_URL" .env

# ---------- 4. コンテナ再起動 ----------
section "4. コンテナ再起動"

docker compose down --remove-orphans 2>/dev/null || true
docker compose up -d

info "DB起動待機中..."
WAIT=0
until docker compose exec -T db pg_isready -U "dev" -d "decisionos" &>/dev/null; do
  sleep 2; WAIT=$((WAIT+2))
  [[ $WAIT -ge 60 ]] && { echo "タイムアウト"; exit 1; }
  info "${WAIT}秒経過..."
done

success "全サービス起動完了"
docker compose ps

section "完了"
echo ""
echo "  PostgreSQL: localhost:5439 → コンテナ内:5432"
echo "  Redis:      localhost:6380 → コンテナ内:6379"
echo ""
echo "次のステップ: bash 05_launch.sh"