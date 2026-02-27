#!/usr/bin/env bash
# =============================================================================
# decision-os  /  サービス起動（実環境版 ポート8089/3008/5439）
# 実行方法: bash 06_start_services.sh
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

# ---------- 1. Docker（DB・Redis）起動 ----------
section "1. Docker サービス起動（DB:5439 / Redis:6380）"

docker compose up -d db redis
info "DB 起動待機中..."

WAIT=0
until docker compose exec -T db pg_isready \
  -U "dev" -d "decisionos" &>/dev/null; do
  sleep 2; WAIT=$((WAIT+2))
  [[ $WAIT -ge 60 ]] && error "DB起動タイムアウト（60秒）"
  info "  待機中... ${WAIT}秒"
done
success "DB(5439): 起動完了"

docker compose exec -T redis redis-cli -p 6379 ping 2>/dev/null | grep -q PONG \
  && success "Redis(6380): 起動完了" \
  || warn "Redis ping未確認（起動中の可能性あり）"

# ---------- 2. バックエンド起動（ポート8089） ----------
section "2. バックエンド起動（FastAPI:8089）"

cd "$PROJECT_DIR/backend"

# pyenv / venv 有効化
export PYENV_ROOT="$HOME/.pyenv"
export PATH="$PYENV_ROOT/bin:$PATH"
eval "$(pyenv init -)" 2>/dev/null || true
source .venv/bin/activate

# .env 読み込み
set -a; source "$PROJECT_DIR/.env"; set +a

# 既存プロセス停止
pkill -f "uvicorn app.main:app" 2>/dev/null || true
sleep 1

mkdir -p "$PROJECT_DIR/logs"

nohup uvicorn app.main:app \
  --host 0.0.0.0 \
  --port 8089 \
  --reload \
  > "$PROJECT_DIR/logs/backend.log" 2>&1 &

BACKEND_PID=$!
echo $BACKEND_PID > "$PROJECT_DIR/.backend.pid"
info "バックエンド PID: $BACKEND_PID"

# ヘルスチェック（最大40秒）
cd "$PROJECT_DIR"
WAIT=0
until curl -sf http://localhost:8089/docs > /dev/null 2>&1; do
  sleep 2; WAIT=$((WAIT+2))
  [[ $WAIT -ge 40 ]] && {
    warn "起動タイムアウト。直近ログ:"
    tail -30 logs/backend.log
    error "バックエンド起動失敗"
  }
  info "  バックエンド起動待機... ${WAIT}秒"
done
success "バックエンド(8089): 起動完了"

# ---------- 3. フロントエンド起動（ポート3008） ----------
section "3. フロントエンド起動（Vite:3008）"

export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && source "$NVM_DIR/nvm.sh"
nvm use 20 2>/dev/null || true

pkill -f "vite" 2>/dev/null || true
sleep 1

cd "$PROJECT_DIR/frontend"
nohup npm run dev \
  > "$PROJECT_DIR/logs/frontend.log" 2>&1 &

FRONTEND_PID=$!
echo $FRONTEND_PID > "$PROJECT_DIR/.frontend.pid"
info "フロントエンド PID: $FRONTEND_PID"

WAIT=0
until curl -sf http://localhost:3008 > /dev/null 2>&1; do
  sleep 2; WAIT=$((WAIT+2))
  [[ $WAIT -ge 40 ]] && {
    warn "フロントエンド起動タイムアウト。ログ:"
    tail -20 "$PROJECT_DIR/logs/frontend.log"
    error "フロントエンド起動失敗"
  }
  info "  フロントエンド起動待機... ${WAIT}秒"
done
success "フロントエンド(3008): 起動完了"

# ---------- 4. 起動確認サマリー ----------
section "起動完了"

SERVER_IP=$(hostname -I | awk '{print $1}')

echo -e "${GREEN}"
echo "  ╔══════════════════════════════════════════════╗"
echo "  ║      decision-os 起動完了（実環境ポート）    ║"
echo "  ╠══════════════════════════════════════════════╣"
echo "  ║  フロントエンド:                             ║"
echo "  ║    http://localhost:3008                     ║"
echo "  ║    http://${SERVER_IP}:3008  ← 外部アクセス ║"
echo "  ║                                              ║"
echo "  ║  バックエンドAPI:                            ║"
echo "  ║    http://localhost:8089/docs  ← Swagger     ║"
echo "  ║                                              ║"
echo "  ║  デモアカウント:                             ║"
echo "  ║    email:    demo@example.com                ║"
echo "  ║    password: demo1234                        ║"
echo "  ╚══════════════════════════════════════════════╝"
echo -e "${RESET}"

echo -e "${YELLOW}次のステップ:${RESET}"
echo "  E2Eテスト実行:  bash 06_e2e_test.sh"
echo ""
echo -e "${YELLOW}ログ確認:${RESET}"
echo "  tail -f ~/projects/decision-os/logs/backend.log"
echo "  tail -f ~/projects/decision-os/logs/frontend.log"