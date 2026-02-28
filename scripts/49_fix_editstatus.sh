#!/bin/bash
set -e
ISSUE_DETAIL=~/projects/decision-os/frontend/src/pages/IssueDetail.tsx
FRONTEND_DIR=~/projects/decision-os/frontend

echo "========== L79 editStatus 未使用変数を修正 =========="

# editStatus の宣言行を確認
echo "  修正前:"
grep -n "editStatus" $ISSUE_DETAIL

# setEditStatus だけ残して editStatus を _ プレフィックスで無視
sed -i 's/const \[editStatus, setEditStatus\]/const [_editStatus, setEditStatus]/' $ISSUE_DETAIL

echo "  修正後:"
grep -n "editStatus" $ISSUE_DETAIL
echo "  ✅ 修正完了"

echo ""
echo "========== ビルド確認 =========="
cd $FRONTEND_DIR
npm run build && echo "" && echo "🎉 ビルド成功！" || echo "⚠️ まだエラーあり"
