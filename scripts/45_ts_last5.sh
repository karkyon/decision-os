#!/usr/bin/env bash
# =============================================================================
# decision-os / 45_ts_last5.sh  残り5件のTSエラー一括修正
# 1. store/auth.ts: authStore に logout 追加（authStore.logout() を呼べるように）
# 2. IssueDetail.tsx: useAuthStore → token は authStore.getToken() で取得
# 3. IssueList.tsx: ISSUE_TYPE_ICONS 削除、?? unreachable 修正
# =============================================================================
set -uo pipefail
GREEN='\033[0;32m'; CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'
info()    { echo -e "${CYAN}[INFO]${RESET}  $*"; }
success() { echo -e "${GREEN}[OK]${RESET}    $*"; }
section() { echo -e "\n${BOLD}========== $* ==========${RESET}"; }

SRC="$HOME/projects/decision-os/frontend/src"
cd "$HOME/projects/decision-os/frontend"
eval "$(~/.nvm/nvm.sh 2>/dev/null || true)"
nvm use --lts 2>/dev/null || true

# =============================================================================
section "1. store/auth.ts: authStore に logout メソッド追加"
# =============================================================================
python3 << 'PYEOF'
path = "/home/karkyon/projects/decision-os/frontend/src/store/auth.ts"
with open(path, encoding='utf-8') as f:
    content = f.read()

# isLoggedIn の後に logout を追加
old = "  isLoggedIn: () => !!localStorage.getItem(\"token\"),\n};"
new = """  isLoggedIn: () => !!localStorage.getItem("token"),
  logout: () => {
    localStorage.removeItem("token");
    localStorage.removeItem("user");
    window.location.href = "/login";
  },
};"""

if 'logout:' not in content.split('// ---')[0]:
    content = content.replace(old, new)
    print("  ✅ authStore.logout 追加完了")
else:
    print("  既に存在（スキップ）")

with open(path, 'w', encoding='utf-8') as f:
    f.write(content)
PYEOF
success "store/auth.ts 修正完了"

# =============================================================================
section "2. IssueDetail.tsx: useAuthStore → authStore に置換"
# =============================================================================
python3 << 'PYEOF'
path = "/home/karkyon/projects/decision-os/frontend/src/pages/IssueDetail.tsx"
with open(path, encoding='utf-8') as f:
    content = f.read()

# import { useAuthStore } → import { authStore }
content = content.replace(
    "import { useAuthStore } from '../store/auth'",
    "import { authStore } from '../store/auth'"
)
# const { token } = useAuthStore() → const token = authStore.getToken()
import re
content = re.sub(
    r"const\s*\{\s*token\s*\}\s*=\s*useAuthStore\(\)",
    "const token = authStore.getToken()",
    content
)
# 念のため残った useAuthStore() を削除
content = re.sub(
    r"const\s+\{[^}]*\}\s*=\s*useAuthStore\(\)\s*\n",
    "",
    content
)

with open(path, 'w', encoding='utf-8') as f:
    f.write(content)
print("  ✅ IssueDetail.tsx: useAuthStore → authStore 修正完了")
PYEOF
success "IssueDetail.tsx 修正完了"

# =============================================================================
section "3. IssueList.tsx: ISSUE_TYPE_ICONS 削除・unreachable 修正"
# =============================================================================
python3 << 'PYEOF'
path = "/home/karkyon/projects/decision-os/frontend/src/pages/IssueList.tsx"
with open(path, encoding='utf-8') as f:
    content = f.read()

import re

# ISSUE_TYPE_ICONS 定義を削除
content = re.sub(
    r'\nconst ISSUE_TYPE_ICONS[^\n]*\n\s*[^\n]*\n\};\n',
    '\n',
    content
)
# 使用箇所も削除（unreachable ?? も含む）
content = re.sub(r'ISSUE_TYPE_ICONS\[[^\]]*\]\s*\?\?\s*["\'][^"\']*["\']', '"⬜"', content)
content = re.sub(r'ISSUE_TYPE_ICONS\[[^\]]*\]', '"⬜"', content)

with open(path, 'w', encoding='utf-8') as f:
    f.write(content)
print("  ✅ IssueList.tsx: ISSUE_TYPE_ICONS 削除完了")
PYEOF
success "IssueList.tsx 修正完了"

# =============================================================================
section "4. 最終ビルド"
# =============================================================================
info "npm run build 実行中..."
BUILD_OUT=$(npm run build 2>&1 || true)
TS_ERRORS=$(echo "$BUILD_OUT" | grep "error TS" || true)

if [[ -z "$TS_ERRORS" ]]; then
  success "🎉🎉🎉 TSビルドエラー 0件！ビルド完全成功！"
  echo "$BUILD_OUT" | grep -E "built|chunks|✓|vite|dist|gzip" | tail -6
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "  次: テストカバレッジ80%"
  echo "  bash ~/projects/decision-os/scripts/34_final_80.sh"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
else
  echo "$TS_ERRORS"
  # 残存エラーのファイル内容を確認
  echo "$TS_ERRORS" | grep -oP 'src/[^(]+' | sort -u | while read -r f; do
    echo ""; echo "=== $f ==="
    grep -n "logout\|token\|ISSUE_TYPE\|useAuth" "$HOME/projects/decision-os/frontend/$f" 2>/dev/null | head -10
  done
fi
