#!/bin/bash
# ============================================================
# Phase 1 MVP - 一括実行スクリプト
# 使用法: bash phase1_run_all.sh
# 実行場所: omega-dev2 サーバー（~/projects/decision-os/scripts/ に配置）
# ============================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "============================================"
echo "  decision-os Phase 1 MVP 実装開始"
echo "  $(date '+%Y-%m-%d %H:%M:%S')"
echo "============================================"
echo ""

# サービス起動確認
echo "=== 0. サービス起動確認 ==="
cd "$HOME/projects/decision-os"
docker compose ps 2>/dev/null || true

# 各Stepを順番に実行
for step in step1 step2 step3 step4 step5; do
  SCRIPT="$SCRIPT_DIR/phase1_${step}_*.sh"
  files=($SCRIPT)
  if [ -f "${files[0]}" ]; then
    echo ""
    echo "=== 実行: ${files[0]} ==="
    bash "${files[0]}"
  fi
done

echo ""
echo "============================================"
echo "  Phase 1 MVP 実装完了！"
echo "============================================"
echo ""
echo "【アクセスURL】"
echo "  フロントエンド:  http://192.168.1.11:3008"
echo "  nginx(統合):     http://192.168.1.11:8888"
echo "  API Swagger:     http://192.168.1.11:8089/docs"
echo ""
echo "【バックエンド再起動】"
echo "  cd ~/projects/decision-os/backend"
echo "  source .venv/bin/activate"
echo "  uvicorn app.main:app --host 0.0.0.0 --port 8089 --reload"
echo ""
echo "【フロントエンド起動】"
echo "  cd ~/projects/decision-os/frontend"
echo "  npm run dev"
echo ""
echo "【動作確認用デモアカウント作成】"
cat << 'CURL'
curl -X POST http://localhost:8089/api/v1/auth/register \
  -H "Content-Type: application/json" \
  -d '{"name":"デモユーザー","email":"demo@example.com","password":"demo1234","role":"pm"}'
CURL
echo ""
echo "【プロジェクト作成（トークンをセットして実行）】"
cat << 'CURL'
TOKEN="上記レスポンスのaccess_tokenをここに"
curl -X POST http://localhost:8089/api/v1/projects \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"name":"サンプルプロジェクト","description":"decision-osテスト用"}'
CURL
