#!/bin/bash
set -e
FRONT=~/projects/decision-os/frontend/src/pages/IssueList.tsx

echo "========== L71 の確認 =========="
sed -n '68,75p' "$FRONT"

echo ""
echo "========== unreachable ?? を修正 =========="
# "?? '⬜'" を削除（左辺が never nullish なので右辺を直値にする）
# パターン: XXX ?? '⬜'  →  XXX
python3 - "$FRONT" <<'PYEOF'
import sys, re

path = sys.argv[1]
with open(path, 'r') as f:
    content = f.read()

# ?? '...' または ?? "..." を削除（unreachable な右辺を除去）
fixed = re.sub(r'\s*\?\?\s*[\'"][^\'\"]*[\'"]', '', content, count=5)

if fixed != content:
    with open(path, 'w') as f:
        f.write(fixed)
    print("✅ ?? 除去完了")
else:
    # 別パターン: ?? で右辺がフォールバック値になっている場合は右辺だけ残す
    # エラー行を直接見て手動修正
    lines = content.splitlines()
    print(f"[WARN] ?? パターン未マッチ - L71の内容:")
    if len(lines) >= 71:
        print(f"  {lines[70]}")
PYEOF

echo ""
echo "========== 最終ビルド =========="
cd ~/projects/decision-os/frontend
npm run build 2>&1 | tail -20

if ! npm run build 2>&1 | grep -q "error TS"; then
    echo ""
    echo "🎉 TSビルド完全成功！"
    echo "次: bash ~/projects/decision-os/scripts/34_final_80.sh"
else
    echo ""
    echo "[WARN] まだエラーあり - L71の内容:"
    sed -n '69,73p' ~/projects/decision-os/frontend/src/pages/IssueList.tsx
fi
