#!/bin/bash
# config.py の IndentationError 修正
set -e

BACKEND="$HOME/projects/decision-os/backend"
CONFIG="$BACKEND/app/core/config.py"

GREEN='\033[0;32m'; CYAN='\033[0;36m'; NC='\033[0m'
ok()      { echo -e "${GREEN}✅ $1${NC}"; }
section() { echo -e "\n${CYAN}━━━ $1 ━━━${NC}"; }

section "1. config.py 現在の内容確認"
cat -n "$CONFIG"

section "2. SSO/TOTP 追記ブロックを削除して正しく再追加"

python3 << 'PYEOF'
config_path = "/home/karkyon/projects/decision-os/backend/app/core/config.py"

with open(config_path, "r", encoding="utf-8") as f:
    src = f.read()

# ── まず誤った追記ブロックを除去 ──────────────────────────────
import re

# 前回スクリプトが挿入した壊れたブロックを削除
src = re.sub(
    r'\n\s*# SSO: Google \(A-002\).*?# TOTP 2FA \(A-003\)\n\s*TOTP_ISSUER: str = "decision-os"\n',
    '\n',
    src, flags=re.DOTALL
)
# フォールバックで追加されたコメントも除去
src = re.sub(r'\n# SSO/TOTP settings appended\n.*', '', src, flags=re.DOTALL)

print("=== クリーンアップ後 ===")
print(src)
print("=" * 40)

# Settings クラスを探して、その中に正しいインデントで追加
# クラス定義を検出
if "class Settings" in src:
    # クラス末尾（次のクラスか EOF の直前）を探す
    # フィールドの最後の行の後に追加
    if "GOOGLE_CLIENT_ID" not in src:
        # model_config か class_config の前に挿入
        insert_block = """
    # SSO: Google OAuth2 (A-002)
    GOOGLE_CLIENT_ID: str = ""
    GOOGLE_CLIENT_SECRET: str = ""
    GOOGLE_REDIRECT_URI: str = "http://localhost:8089/api/v1/auth/google/callback"

    # SSO: GitHub OAuth2 (A-002)
    GITHUB_CLIENT_ID: str = ""
    GITHUB_CLIENT_SECRET: str = ""
    GITHUB_REDIRECT_URI: str = "http://localhost:8089/api/v1/auth/github/callback"

    # TOTP 2FA (A-003)
    TOTP_ISSUER: str = "decision-os"
"""
        # model_config の直前に挿入
        if "model_config" in src:
            src = src.replace(
                "    model_config",
                insert_block + "    model_config",
                1
            )
        else:
            # クラスの最後のフィールド後に追加（class の次の非クラス行の前）
            # 単純に SettingsConfigDict か Settings クラスの最後に追加
            src = re.sub(
                r'(class Settings\b.*?)(^[^\s]|\Z)',
                lambda m: m.group(1).rstrip() + "\n" + insert_block + "\n" + m.group(2),
                src, count=1, flags=re.DOTALL | re.MULTILINE
            )
        print("SSO/TOTP フィールドを追加しました")
    else:
        print("GOOGLE_CLIENT_ID は既に存在します")
else:
    # Settings クラスがない場合はファイル末尾に追加
    src += """
# SSO/TOTP 設定（手動追加）
# ※ Settings クラス内に移動してください
"""
    print("WARNING: Settings クラスが見つかりません")

with open(config_path, "w", encoding="utf-8") as f:
    f.write(src)

print("\n=== 修正後 ===")
with open(config_path) as f:
    for i, line in enumerate(f, 1):
        print(f"{i:3}: {line}", end="")
PYEOF

section "3. Python 構文チェック"
cd "$BACKEND"
source .venv/bin/activate
python3 -c "
import ast, sys
with open('app/core/config.py') as f:
    src = f.read()
try:
    ast.parse(src)
    print('✅ 構文エラーなし')
except SyntaxError as e:
    print(f'❌ SyntaxError: {e}')
    sys.exit(1)
"

section "4. バックエンド再起動"
pkill -f "uvicorn app.main" 2>/dev/null || true
sleep 1
nohup uvicorn app.main:app --host 0.0.0.0 --port 8089 --reload \
  > "$HOME/projects/decision-os/logs/backend.log" 2>&1 &
sleep 5

echo "--- backend.log (末尾 12 行) ---"
tail -12 "$HOME/projects/decision-os/logs/backend.log"
echo "--------------------------------"

if curl -s http://localhost:8089/docs | head -3 | grep -q "swagger\|html"; then
  ok "バックエンド起動 ✅"
else
  echo "❌ まだ起動していません。ログを確認:"
  tail -20 "$HOME/projects/decision-os/logs/backend.log"
fi

section "5. SSO / TOTP エンドポイント確認"
for path in "/api/v1/auth/google" "/api/v1/auth/github" "/api/v1/auth/totp/setup"; do
  HTTP=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:8089${path}")
  if [[ "$HTTP" =~ ^(200|307|401|403|422)$ ]]; then
    ok "GET ${path} → HTTP ${HTTP}"
  else
    echo "⚠️  GET ${path} → HTTP ${HTTP}"
  fi
done
