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
	  uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload

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
