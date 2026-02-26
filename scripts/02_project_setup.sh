#!/usr/bin/env bash
# =============================================================================
# decision-os  /  Step 2: プロジェクトセットアップ
# 実行方法: bash 02_project_setup.sh
# 前提: 01_server_setup.sh が完了済み・dockerグループが有効（newgrp docker済み）
# =============================================================================
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'
info()    { echo -e "${CYAN}[INFO]${RESET}  $*"; }
success() { echo -e "${GREEN}[OK]${RESET}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
error()   { echo -e "${RED}[ERROR]${RESET} $*"; exit 1; }
section() { echo -e "\n${BOLD}========== $* ==========${RESET}"; }

# ---------- 前提チェック ----------
section "前提チェック"

command -v docker &>/dev/null || error "Docker が見つかりません。01_server_setup.sh を先に実行してください"
docker info &>/dev/null       || error "Dockerに接続できません。'newgrp docker' または再ログイン後に実行してください"
command -v node   &>/dev/null || error "Node.js が見つかりません。01_server_setup.sh を先に実行してください"
command -v python &>/dev/null || error "Python が見つかりません。01_server_setup.sh を先に実行してください"

success "Docker:  $(docker --version)"
success "Node.js: $(node --version)"
success "Python:  $(python --version)"

# ---------- 1. リポジトリのクローン ----------
section "1. リポジトリのクローン"

PROJECT_DIR="$HOME/projects/decision-os"

if [[ -d "$PROJECT_DIR/.git" ]]; then
  success "リポジトリは既にクローン済み: $PROJECT_DIR"
else
  mkdir -p "$HOME/projects"
  # TODO: 実際のリポジトリURLに変更してください
  REPO_URL="${REPO_URL:-https://github.com/your-org/decision-os.git}"
  info "クローン中: $REPO_URL"
  git clone "$REPO_URL" "$PROJECT_DIR"
  success "クローン完了: $PROJECT_DIR"
fi

cd "$PROJECT_DIR"
success "作業ディレクトリ: $(pwd)"

# ---------- 2. .env ファイル生成 ----------
section "2. 環境変数ファイル（.env）の生成"

if [[ -f .env ]]; then
  warn ".env は既に存在します。スキップします（既存の設定を保持）"
else
  # JWT_SECRET をランダム生成
  JWT_SECRET=$(openssl rand -hex 32)

  cat > .env << EOF
# =============================================================================
# decision-os 環境変数
# 生成日時: $(date '+%Y-%m-%d %H:%M:%S')
# 本番環境では各値を必ず変更すること
# =============================================================================

# ===== PostgreSQL =====
POSTGRES_DB=decisionos
POSTGRES_USER=dev
POSTGRES_PASSWORD=devpass_$(openssl rand -hex 4)
DATABASE_URL=postgresql://dev:\${POSTGRES_PASSWORD}@localhost:5432/decisionos

# ===== Redis =====
REDIS_URL=redis://localhost:6379/0

# ===== JWT認証 =====
JWT_SECRET=${JWT_SECRET}
JWT_EXPIRE_MINUTES=1440

# ===== バックエンド =====
BACKEND_HOST=0.0.0.0
BACKEND_PORT=8089
DEBUG=true

# ===== フロントエンド =====
VITE_API_BASE_URL=http://localhost:8089
VITE_WS_URL=ws://localhost:8089/ws

# ===== AI補助判定（任意） =====
AI_PROVIDER=none
AI_CONFIDENCE_THRESHOLD=0.75
EOF

  success ".env ファイルを生成しました（JWT_SECRETは自動生成済み）"
fi

# .envを読み込む
set -a; source .env; set +a

# ---------- 3. モノレポ ディレクトリ構造の作成 ----------
section "3. ディレクトリ構造の作成"

# frontend
mkdir -p frontend/src/{components,pages,hooks,api,types}
mkdir -p frontend/public

# backend
mkdir -p backend/app/{routers,models,schemas,db,core}
mkdir -p backend/engine
mkdir -p backend/dictionary/{common,dev,infra}
mkdir -p backend/tests
mkdir -p backend/scripts

# docker
mkdir -p docker/nginx
mkdir -p docker/postgres

# github actions
mkdir -p .github/workflows

success "ディレクトリ構造を作成しました"

# ---------- 4. docker-compose.yml の生成 ----------
section "4. docker-compose.yml の生成"

# Linuxでのhost.docker.internalの代替：ホストIPを取得
HOST_IP=$(ip route show default | awk '/default/ {print $3}')
info "ホストIP（nginx upstream用）: ${HOST_IP}"

cat > docker-compose.yml << EOF
version: "3.9"

# =====================================================
# decision-os Docker Compose
# 管理対象: PostgreSQL / Redis / nginx のみ
# frontend / backend はホストで直接起動する
# =====================================================

x-logging: &default-logging
  driver: "json-file"
  options:
    max-size: "10m"
    max-file: "3"

services:

  db:
    image: postgres:16
    container_name: decisionos_db
    restart: unless-stopped
    environment:
      POSTGRES_DB: \${POSTGRES_DB}
      POSTGRES_USER: \${POSTGRES_USER}
      POSTGRES_PASSWORD: \${POSTGRES_PASSWORD}
      TZ: Asia/Tokyo
    ports:
      - "127.0.0.1:5432:5432"
    volumes:
      - db_data:/var/lib/postgresql/data
      - ./docker/postgres/init.sql:/docker-entrypoint-initdb.d/init.sql:ro
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U \${POSTGRES_USER} -d \${POSTGRES_DB}"]
      interval: 5s
      timeout: 5s
      retries: 10
    logging: *default-logging

  redis:
    image: redis:7-alpine
    container_name: decisionos_redis
    restart: unless-stopped
    ports:
      - "127.0.0.1:6379:6379"
    volumes:
      - redis_data:/data
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 5s
      retries: 5
    logging: *default-logging

  nginx:
    image: nginx:1.27-alpine
    container_name: decisionos_nginx
    restart: unless-stopped
    ports:
      - "8888:80"
    volumes:
      - ./docker/nginx/nginx.conf:/etc/nginx/nginx.conf:ro
    depends_on:
      db:
        condition: service_healthy
      redis:
        condition: service_healthy
    logging: *default-logging

volumes:
  db_data:
  redis_data:
EOF

success "docker-compose.yml を生成しました"

# ---------- 5. nginx.conf の生成（Linux対応: host IPを直接指定）----------
section "5. nginx.conf の生成"

cat > docker/nginx/nginx.conf << EOF
# decision-os nginx 設定
# Linux環境: host.docker.internal の代わりにホストIPを直接指定

events {
  worker_connections 1024;
}

http {
  # ホストで動くサービスのupstream定義
  # host.docker.internal はLinuxでは使えないため、ホストIPを直接指定
  upstream frontend {
    server ${HOST_IP}:3008;
  }

  upstream backend {
    server ${HOST_IP}:8089;
  }

  # アクセスログのフォーマット
  log_format main '\$remote_addr - [\$time_local] "\$request" '
                  '\$status \$body_bytes_sent "\$http_referer" '
                  '"\$http_user_agent"';

  access_log /var/log/nginx/access.log main;
  error_log  /var/log/nginx/error.log warn;

  server {
    listen 80;
    server_name localhost;

    # クライアントの最大ボディサイズ（ファイルアップロード用）
    client_max_body_size 10M;

    # バックエンドAPI
    location /api/ {
      proxy_pass         http://backend;
      proxy_set_header   Host              \$host;
      proxy_set_header   X-Real-IP         \$remote_addr;
      proxy_set_header   X-Forwarded-For   \$proxy_add_x_forwarded_for;
      proxy_set_header   X-Forwarded-Proto \$scheme;
      proxy_read_timeout 60s;
    }

    # WebSocket（リアルタイム会話・通知）
    location /ws {
      proxy_pass         http://backend;
      proxy_http_version 1.1;
      proxy_set_header   Upgrade    \$http_upgrade;
      proxy_set_header   Connection "upgrade";
      proxy_set_header   Host       \$host;
      proxy_read_timeout 3600s;
    }

    # フロントエンド（その他すべて）
    location / {
      proxy_pass         http://frontend;
      proxy_set_header   Host              \$host;
      proxy_set_header   X-Real-IP         \$remote_addr;
      # Viteのホットリロード（HMR）用WebSocket
      proxy_http_version 1.1;
      proxy_set_header   Upgrade    \$http_upgrade;
      proxy_set_header   Connection "upgrade";
    }
  }
}
EOF

success "docker/nginx/nginx.conf を生成しました（ホストIP: ${HOST_IP}）"

# ---------- 6. postgres 初期化SQL ----------
section "6. DB初期化SQL の生成"

cat > docker/postgres/init.sql << 'EOF'
-- decision-os 初期スキーマ設定
-- Alembic が本マイグレーションを担うため、ここでは最低限の設定のみ

-- タイムゾーン設定
SET timezone = 'Asia/Tokyo';

-- UUID拡張（PostgreSQL組み込み）
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- 全文検索用（日本語対応はpg_bigmが必要だが、まずは標準で）
CREATE EXTENSION IF NOT EXISTS pg_trgm;
EOF

success "docker/postgres/init.sql を生成しました"

# ---------- 7. Makefile の生成 ----------
section "7. Makefile の生成"

# Makefileはタブが必須のため printf で生成
cat > Makefile << 'MAKEFILE'
# =============================================================================
# decision-os Makefile
# 使い方: make <コマンド>
# =============================================================================

.PHONY: help up down logs ps \
        be fe \
        migrate seed \
        test test-be test-fe test-engine \
        lint lint-be lint-fe \
        install install-be install-fe \
        clean reset-db

# デフォルト: ヘルプを表示
help:
	@echo ""
	@echo "decision-os 開発コマンド一覧"
	@echo "================================="
	@echo "  make up          Dockerサービス起動（DB / Redis / nginx）"
	@echo "  make down        Dockerサービス停止"
	@echo "  make logs        Dockerサービスのログをtail"
	@echo "  make ps          Dockerサービスの状態確認"
	@echo "---------------------------------"
	@echo "  make be          バックエンド起動（ホットリロード）"
	@echo "  make fe          フロントエンド起動（ホットリロード）"
	@echo "---------------------------------"
	@echo "  make install     全依存パッケージインストール"
	@echo "  make install-be  バックエンド依存インストール"
	@echo "  make install-fe  フロントエンド依存インストール"
	@echo "---------------------------------"
	@echo "  make migrate     DBマイグレーション実行"
	@echo "  make seed        初期データ投入"
	@echo "---------------------------------"
	@echo "  make test        全テスト実行"
	@echo "  make test-be     バックエンドテスト"
	@echo "  make test-fe     フロントエンドテスト"
	@echo "  make test-engine 分解エンジンテスト"
	@echo "---------------------------------"
	@echo "  make lint        全Lint実行"
	@echo "  make reset-db    DB完全リセット（開発用・データ消去）"
	@echo ""

# ===== Docker サービス管理 =====
up:
	docker compose up -d
	@echo "起動確認: docker compose ps"

down:
	docker compose down

logs:
	docker compose logs -f

ps:
	docker compose ps

# ===== アプリ起動 =====
be:
	@cd backend && \
	  source .venv/bin/activate && \
	  uvicorn app.main:app --host 0.0.0.0 --port 8089 --reload

fe:
	@cd frontend && npm run dev

# ===== 依存パッケージ =====
install: install-be install-fe

install-be:
	@cd backend && \
	  python -m venv .venv && \
	  source .venv/bin/activate && \
	  pip install --upgrade pip && \
	  pip install -r requirements.txt
	@echo "バックエンド依存インストール完了"

install-fe:
	@cd frontend && npm install
	@echo "フロントエンド依存インストール完了"

# ===== DB操作 =====
migrate:
	@cd backend && \
	  source .venv/bin/activate && \
	  alembic upgrade head

seed:
	@cd backend && \
	  source .venv/bin/activate && \
	  python scripts/seed.py

# ===== テスト =====
test: test-be test-fe

test-be:
	@cd backend && \
	  source .venv/bin/activate && \
	  pytest tests/ -v --cov=app --cov-report=term-missing

test-fe:
	@cd frontend && npm run test

test-engine:
	@cd backend && \
	  source .venv/bin/activate && \
	  pytest tests/test_engine.py -v

# ===== Lint =====
lint: lint-be lint-fe

lint-be:
	@cd backend && \
	  source .venv/bin/activate && \
	  flake8 app/ engine/ --max-line-length=100

lint-fe:
	@cd frontend && npm run lint

# ===== リセット（開発用） =====
clean:
	find . -type d -name __pycache__ -exec rm -rf {} + 2>/dev/null || true
	find . -type f -name "*.pyc" -delete 2>/dev/null || true
	@echo "キャッシュファイルを削除しました"

reset-db:
	@echo "警告: DBのデータが全て削除されます"
	@read -p "本当に実行しますか？ [y/N]: " yn && [ "$$yn" = "y" ] || exit 1
	docker compose down -v
	docker compose up -d
	@echo "DBの起動を待機中..."
	@sleep 8
	$(MAKE) migrate
	$(MAKE) seed
	@echo "DBリセット完了"
MAKEFILE

success "Makefile を生成しました"

# ---------- 8. GitHub Actions の生成 ----------
section "8. GitHub Actions ワークフローの生成"

cat > .github/workflows/test.yml << 'EOF'
name: CI

on:
  push:
    branches: [main, develop]
  pull_request:
    branches: [main, develop]

jobs:
  backend-test:
    runs-on: ubuntu-24.04
    services:
      postgres:
        image: postgres:16
        env:
          POSTGRES_DB: testdb
          POSTGRES_USER: test
          POSTGRES_PASSWORD: testpass
        options: >-
          --health-cmd pg_isready
          --health-interval 5s
          --health-retries 5
        ports: ["5432:5432"]
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with:
          python-version: '3.12'
          cache: pip
          cache-dependency-path: backend/requirements.txt
      - name: Install dependencies
        run: |
          cd backend
          pip install -r requirements.txt
      - name: Run migrations
        run: |
          cd backend
          DATABASE_URL=postgresql://test:testpass@localhost:5432/testdb \
          alembic upgrade head
      - name: Run tests
        run: |
          cd backend
          DATABASE_URL=postgresql://test:testpass@localhost:5432/testdb \
          pytest tests/ -v --cov=app --cov-report=xml
      - name: Quality gate（カバレッジ85%未満で失敗）
        run: |
          cd backend
          python -m coverage report --fail-under=85

  frontend-test:
    runs-on: ubuntu-24.04
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: '20'
          cache: npm
          cache-dependency-path: frontend/package-lock.json
      - run: cd frontend && npm ci
      - run: cd frontend && npm run lint
      - run: cd frontend && npm run test
      - run: cd frontend && npm run build
EOF

success ".github/workflows/test.yml を生成しました"

# ---------- 9. .gitignore の生成 ----------
section "9. .gitignore の生成"

cat > .gitignore << 'EOF'
# 環境変数（絶対にコミットしない）
.env
.env.local
.env.*.local

# Python
backend/.venv/
backend/__pycache__/
backend/**/__pycache__/
backend/**/*.pyc
backend/.pytest_cache/
backend/.coverage
backend/coverage.xml
*.egg-info/

# Node.js
frontend/node_modules/
frontend/dist/
frontend/.vite/

# OS
.DS_Store
Thumbs.db

# IDE
.vscode/settings.json
.idea/
*.swp

# ログ
*.log
logs/

# Docker volumes（ローカルマウント時）
docker/postgres/data/
EOF

success ".gitignore を生成しました"

# ---------- 完了メッセージ ----------
section "Step 2 完了"
echo -e "${GREEN}"
echo "  ✔ .env（JWT_SECRETは自動生成済み）"
echo "  ✔ ディレクトリ構造"
echo "  ✔ docker-compose.yml（ホストIP: ${HOST_IP}）"
echo "  ✔ docker/nginx/nginx.conf（Linux対応済み）"
echo "  ✔ docker/postgres/init.sql"
echo "  ✔ Makefile"
echo "  ✔ .github/workflows/test.yml"
echo "  ✔ .gitignore"
echo -e "${RESET}"
echo -e "${YELLOW}【次のアクション】${RESET}"
echo -e "  bash ${BOLD}03_backend_setup.sh${RESET}"
