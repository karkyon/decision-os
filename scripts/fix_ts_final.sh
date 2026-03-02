#!/bin/bash
PROJECT="$HOME/projects/decision-os"
FRONTEND="$PROJECT/frontend"
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
ok()      { echo -e "${GREEN}✅ $1${NC}"; }
warn()    { echo -e "${YELLOW}⚠️  $1${NC}"; }
section() { echo -e "\n${CYAN}━━━ $1 ━━━${NC}"; }

section "1. SSOButtons.tsx 修正"
FILE="$FRONTEND/src/components/SSOButtons.tsx"
if [ -f "$FILE" ]; then
  sed -i '/^import React from /d' "$FILE"
  head -3 "$FILE"
  ok "SSOButtons.tsx 修正完了"
else
  warn "$FILE が見つかりません"
fi

section "2. TOTPLogin.tsx 修正"
FILE="$FRONTEND/src/pages/TOTPLogin.tsx"
if [ -f "$FILE" ]; then
  sed -i 's/^import React, { /import { /g' "$FILE"
  sed -i '/^import React from /d' "$FILE"
  head -3 "$FILE"
  ok "TOTPLogin.tsx 修正完了"
else
  warn "$FILE が見つかりません"
fi

section "3. TypeScript チェック"
cd "$FRONTEND"
TS_RESULT=$(npx tsc --noEmit 2>&1)
if [ -z "$TS_RESULT" ]; then
  ok "TSエラー 0件 ✨"
else
  echo "$TS_RESULT" | tail -20
  warn "TSエラーあり"
fi

section "4. フロントエンド再起動"
pkill -f "vite" 2>/dev/null && sleep 1 && ok "旧プロセス停止" || true
mkdir -p "$PROJECT/logs"
nohup npm run dev > "$PROJECT/logs/frontend.log" 2>&1 &
sleep 5
HTTP=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:3008 || echo "000")
[[ "$HTTP" =~ ^(200|304)$ ]] && ok "フロントエンド: HTTP $HTTP" || { warn "HTTP $HTTP"; tail -10 "$PROJECT/logs/frontend.log"; }

section "5. E2Eテスト"
cd "$PROJECT/scripts"
bash 06_e2e_test.sh 2>&1 | tail -5

section "6. 引き継ぎ資料"
HANDOVER=$(ls "$PROJECT"/decisionos_NEXT_Phase2_引き継ぎ資料_*.md 2>/dev/null | tail -1)
if [ -n "$HANDOVER" ]; then
  ok "引き継ぎ資料: $HANDOVER"
  cp "$HANDOVER" /tmp/ && ok "/tmp/ にコピー済み"
else
  warn "Phase2引き継ぎ資料が見つかりません"
  ls "$PROJECT"/*.md 2>/dev/null
fi

ok "全作業完了！"
