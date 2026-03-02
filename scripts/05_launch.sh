#!/usr/bin/env bash
# =============================================================================
# decision-os  /  Step 5: 起動・動作確認
# 実行方法: bash 05_launch.sh
# 前提: Step 1〜4 が完了済み
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
[[ -d "$PROJECT_DIR" ]] || error "プロジェクトが見つかりません: $PROJECT_DIR"
cd "$PROJECT_DIR"

# ---------- 1. Dockerサービス起動 ----------
section "1. Dockerサービス起動（DB / Redis / nginx）"

docker compose up -d
info "起動待機中..."

# DB が healthy になるまで最大60秒待つ
WAIT=0
until docker compose exec -T db pg_isready -U "${POSTGRES_USER:-dev}" -d "${POSTGRES_DB:-decisionos}" &>/dev/null; do
  sleep 2
  WAIT=$((WAIT + 2))
  [[ $WAIT -ge 60 ]] && error "DB起動タイムアウト（60秒）"
  info "DB起動待機中... ${WAIT}秒経過"
done
success "DB: 起動完了"

# Redis ping
docker compose exec -T redis redis-cli ping | grep -q "PONG" && success "Redis: 起動完了"

docker compose ps

# ---------- 2. DBマイグレーション ----------
section "2. DBマイグレーション"

cd backend
export PYENV_ROOT="$HOME/.pyenv"
export PATH="$PYENV_ROOT/bin:$PATH"
eval "$(pyenv init -)" 2>/dev/null || true
source .venv/bin/activate

set -a; source "$PROJECT_DIR/.env"; set +a

alembic upgrade head
success "マイグレーション完了"

# ---------- 3. バックエンド起動 ----------
section "3. バックエンド起動（バックグラウンド）"

# 既存のプロセスを停止
pkill -f "uvicorn app.main:app" 2>/dev/null || true
sleep 1

# バックグラウンドで起動（ログをファイルに出力）
nohup uvicorn app.main:app \
  --host 0.0.0.0 \
  --port 8089 \
  --reload \
  > "$PROJECT_DIR/logs/backend.log" 2>&1 &

BACKEND_PID=$!
echo $BACKEND_PID > "$PROJECT_DIR/.backend.pid"
info "バックエンド PID: $BACKEND_PID"

# ヘルスチェック（最大30秒）
cd "$PROJECT_DIR"
mkdir -p logs
WAIT=0
until curl -sf http://localhost:8089/health > /dev/null 2>&1; do
  sleep 2
  WAIT=$((WAIT + 2))
  [[ $WAIT -ge 30 ]] && {
    warn "バックエンド起動タイムアウト。ログを確認してください:"
    tail -20 logs/backend.log
    error "バックエンド起動失敗"
  }
  info "バックエンド起動待機中... ${WAIT}秒経過"
done
success "バックエンド: 起動完了 (PID: $BACKEND_PID)"

# ---------- 4. フロントエンド起動 ----------
section "4. フロントエンド起動（バックグラウンド）"

# nvm 有効化
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && source "$NVM_DIR/nvm.sh"
nvm use 20 2>/dev/null || true

# 既存プロセスを停止
pkill -f "vite" 2>/dev/null || true
sleep 1

cd frontend
nohup npm run dev \
  > "$PROJECT_DIR/logs/frontend.log" 2>&1 &

FRONTEND_PID=$!
echo $FRONTEND_PID > "$PROJECT_DIR/.frontend.pid"
info "フロントエンド PID: $FRONTEND_PID"

# 起動待機（最大30秒）
WAIT=0
until curl -sf http://localhost:3008 > /dev/null 2>&1; do
  sleep 2
  WAIT=$((WAIT + 2))
  [[ $WAIT -ge 30 ]] && {
    warn "フロントエンド起動タイムアウト。ログを確認:"
    tail -20 "$PROJECT_DIR/logs/frontend.log"
    error "フロントエンド起動失敗"
  }
  info "フロントエンド起動待機中... ${WAIT}秒経過"
done
success "フロントエンド: 起動完了 (PID: $FRONTEND_PID)"

# ---------- 5. 動作確認 ----------
section "5. 動作確認"

cd "$PROJECT_DIR"

check() {
  local label="$1"
  local url="$2"
  if curl -sf "$url" > /dev/null 2>&1; then
    success "$label: OK  ( $url )"
  else
    warn "$label: 応答なし ( $url )"
  fi
}

check "バックエンド ヘルスチェック" "http://localhost:8089/health"
check "バックエンド API"            "http://localhost:8089/api/v1/ping"
check "フロントエンド"              "http://localhost:3008"
check "nginx（ポート80）"           "http://localhost:8888"

# ---------- 完了メッセージ ----------
section "起動完了"

SERVER_IP=$(hostname -I | awk '{print $1}')

echo -e "${GREEN}"
echo "  ╔════════════════════════════════════════╗"
echo "  ║       decision-os 起動完了             ║"
echo "  ╠════════════════════════════════════════╣"
echo "  ║  フロントエンド:                        ║"
echo "  ║    http://localhost:3008               ║"
echo "  ║    http://${SERVER_IP}:3008             ║"
echo "  ║                                        ║"
echo "  ║  バックエンドAPI:                       ║"
echo "  ║    http://localhost:8089/health        ║"
echo "  ║    http://localhost:8089/docs  ← Swagger ║"
echo "  ║                                        ║"
echo "  ║  nginx（統合）:                         ║"
echo "  ║    http://localhost:8888                 ║"
echo "  ╚════════════════════════════════════════╝"
echo -e "${RESET}"

echo -e "${YELLOW}プロセス管理:${RESET}"
echo "  ログ確認:           tail -f logs/backend.log"
echo "                      tail -f logs/frontend.log"
echo "  バックエンド停止:   kill \$(cat .backend.pid)"
echo "  フロントエンド停止: kill \$(cat .frontend.pid)"
echo "  Docker停止:         docker compose down"
echo ""
echo -e "${YELLOW}次回以降の起動:${RESET}"
echo "  make up  &&  make be  （別ターミナルで）  make fe"
