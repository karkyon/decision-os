#!/bin/bash
# App.tsx JSXエラー修正 + フロントエンド再起動
set -e

FE="$HOME/projects/decision-os/frontend/src"
GREEN='\033[0;32m'; CYAN='\033[0;36m'; NC='\033[0m'
ok()      { echo -e "${GREEN}✅ $1${NC}"; }
section() { echo -e "\n${CYAN}━━━ $1 ━━━${NC}"; }

section "1. 現在の App.tsx 確認"
cat -n "$FE/App.tsx"

section "2. App.tsx を安全に修正"

python3 << 'PYEOF'
import re

path = "/home/karkyon/projects/decision-os/frontend/src/App.tsx"
with open(path) as f:
    src = f.read()

# ── Step1: 壊れた挿入を全部除去 ──────────────────────────────
# 前スクリプトが /login Route の後に </Route>の外へ挿入した壊れたパターンを削除
src = re.sub(r'\n\s*<Route path="/totp-login"[^\n]*/>\s*\}?\s*/>', '', src)
src = re.sub(r'\n\s*<Route path="/totp-setup"[^\n]*/>\s*\}?\s*/>', '', src)
src = re.sub(r'\n\s*<Route path="/totp-login"[^\n]*/>', '', src)
src = re.sub(r'\n\s*<Route path="/totp-setup"[^\n]*/>', '', src)

# ── Step2: import が重複していたら除去して1つに ───────────────
src = re.sub(r'import TOTPSetup from ["\'][^"\']+["\'];\n', '', src)
src = re.sub(r'import TOTPLogin from ["\'][^"\']+["\'];\n', '', src)

# ── Step3: 既存の import ブロック末尾に正しく追加 ─────────────
# "import " で始まる行の最後の後に追加
lines = src.split('\n')
last_import = -1
for i, line in enumerate(lines):
    if line.startswith('import '):
        last_import = i

if last_import >= 0:
    lines.insert(last_import + 1, "import TOTPLogin from './pages/TOTPLogin';")
    lines.insert(last_import + 1, "import TOTPSetup from './pages/TOTPSetup';")

src = '\n'.join(lines)

# ── Step4: Routes ブロック内に正しく挿入 ─────────────────────
# </Routes> の直前に追加（確実にRoutes内に入る）
if '/totp-setup' not in src:
    src = src.replace(
        '</Routes>',
        '        <Route path="/totp-setup" element={<TOTPSetup />} />\n'
        '        <Route path="/totp-login" element={<TOTPLogin />} />\n'
        '      </Routes>',
        1
    )

print("=== 修正後 App.tsx ===")
print(src)

with open(path, 'w') as f:
    f.write(src)
print("\n修正完了")
PYEOF

section "3. 修正後の App.tsx 確認"
cat -n "$FE/App.tsx"

section "4. TypeScript チェック"
cd "$HOME/projects/decision-os/frontend"
npx tsc --noEmit 2>&1
TS_EXIT=$?
if [ $TS_EXIT -eq 0 ]; then
  ok "TypeScript エラーなし"
else
  echo "⚠️  TSエラーあり（上記を確認）"
fi

section "5. Vite 再起動"
pkill -f "vite" 2>/dev/null || true
sleep 1
nohup npm run dev -- --host 0.0.0.0 --port 3008 \
  > "$HOME/projects/decision-os/logs/frontend.log" 2>&1 &
sleep 4

echo "--- frontend.log (末尾8行) ---"
tail -8 "$HOME/projects/decision-os/logs/frontend.log"
echo "------------------------------"

if curl -s http://localhost:3008 | grep -q "html\|vite\|react"; then
  ok "フロントエンド起動 ✅"
  echo ""
  echo "ブラウザで確認:"
  echo "  http://localhost:3008/login      → Google/GitHub ボタンが出ること"
  echo "  http://localhost:3008/totp-setup → 2FAセットアップ画面"
else
  echo "⚠️  フロントエンド応答なし"
  tail -20 "$HOME/projects/decision-os/logs/frontend.log"
fi
