#!/bin/bash
# ============================================================
# DB接続情報修正 + マイグレーション再実行
# ============================================================
set -e

PROJECT="$HOME/projects/decision-os"
BACKEND="$PROJECT/backend"

echo "=== DB接続情報を.envから読み込んで修正 ==="

# .envから正しいDATABASE_URLを取得
DATABASE_URL=$(grep "^DATABASE_URL=" "$PROJECT/.env" | cut -d'=' -f2-)
echo "DATABASE_URL: $DATABASE_URL"

# config.py を .env の値を使うように修正
cat > "$BACKEND/app/core/config.py" << EOF
from pydantic_settings import BaseSettings

class Settings(BaseSettings):
    APP_NAME: str = "decision-os"
    API_V1_STR: str = "/api/v1"
    SECRET_KEY: str = "changeme-secret-key-in-production"
    ALGORITHM: str = "HS256"
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 60 * 24

    DATABASE_URL: str = "${DATABASE_URL}"
    REDIS_URL: str = "redis://localhost:6380/0"
    BACKEND_PORT: int = 8089
    FRONTEND_PORT: int = 3008

    class Config:
        env_file = ".env"
        extra = "ignore"

settings = Settings()
EOF

echo "✅ config.py 修正完了"

# alembic.ini の sqlalchemy.url も修正
sed -i "s|sqlalchemy.url = .*|sqlalchemy.url = ${DATABASE_URL}|" "$BACKEND/alembic.ini"
echo "✅ alembic.ini 修正完了"

echo ""
echo "=== Alembicマイグレーション実行 ==="
cd "$BACKEND"
source .venv/bin/activate

# 既存のマイグレーションファイルをクリア（空のものがあると競合する）
rm -f alembic/versions/*.py
echo "✅ 既存マイグレーションファイルをクリア"

alembic revision --autogenerate -m "initial_schema"
echo "✅ マイグレーションファイル生成"

alembic upgrade head
echo "✅ マイグレーション適用完了"

echo ""
echo "=== DBテーブル確認 ==="
docker exec decisionos_db psql -U dev -d decisionos -c "\dt"

echo ""
echo "✅✅✅ Step 1 完了！次は Step 2〜5 を続けて実行します"
echo ""
echo "=== Step 2: 認証API ==="
bash "$HOME/projects/decision-os/scripts/phase1_step2_auth.sh"

echo ""
echo "=== Step 3: コアAPI ==="
bash "$HOME/projects/decision-os/scripts/phase1_step3_api.sh"

echo ""
echo "=== Step 4: 分解エンジン ==="
bash "$HOME/projects/decision-os/scripts/phase1_step4_engine.sh"

echo ""
echo "=== Step 5: フロントエンド ==="
bash "$HOME/projects/decision-os/scripts/phase1_step5_frontend.sh"

echo ""
echo "============================================"
echo "  Phase 1 MVP 全実装完了！"
echo "============================================"
echo ""
echo "=== バックエンド再起動 ==="
pkill -f "uvicorn app.main" 2>/dev/null || true
sleep 1
cd "$BACKEND"
source .venv/bin/activate
nohup uvicorn app.main:app --host 0.0.0.0 --port 8089 --reload \
  > "$PROJECT/logs/backend.log" 2>&1 &
echo "✅ バックエンド起動 PID: $!"

sleep 3
echo ""
echo "=== 動作確認 ==="
curl -s http://localhost:8089/health && echo ""
curl -s http://localhost:8089/api/v1/ping && echo ""

echo ""
echo "【アクセスURL】"
echo "  フロントエンド:  http://192.168.1.11:3008"
echo "  nginx(統合):     http://192.168.1.11:8888"
echo "  API Swagger:     http://192.168.1.11:8089/docs"
echo ""
echo "【デモアカウント作成】"
echo "curl -X POST http://localhost:8089/api/v1/auth/register \\"
echo "  -H 'Content-Type: application/json' \\"
echo "  -d '{\"name\":\"デモユーザー\",\"email\":\"demo@example.com\",\"password\":\"demo1234\",\"role\":\"pm\"}'"
