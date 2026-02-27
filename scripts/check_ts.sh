#!/usr/bin/env bash
# TS修正前の確認スクリプト
cat ~/projects/decision-os/frontend/src/pages/InputNew.tsx
echo ""
echo "========== App.test.tsx =========="
cat ~/projects/decision-os/frontend/src/test/App.test.tsx 2>/dev/null || \
  find ~/projects/decision-os/frontend/src -name "App.test.tsx" -exec cat {} \;
