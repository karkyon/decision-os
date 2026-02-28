#!/bin/bash
ISSUE_DETAIL=~/projects/decision-os/frontend/src/pages/IssueDetail.tsx
FRONTEND_DIR=~/projects/decision-os/frontend

echo "=== 修正前 L55付近 ==="
grep -n "traceLoading\|setTraceLoading" $ISSUE_DETAIL

# 宣言: [_traceLoading, setTraceLoading] に統一
sed -i 's/const \[traceLoading, setTraceLoading\]/const [_traceLoading, _setTraceLoading]/' $ISSUE_DETAIL
sed -i 's/const \[_traceLoading, setTraceLoading\]/const [_traceLoading, _setTraceLoading]/' $ISSUE_DETAIL

# 使用箇所: traceLoading → _traceLoading
sed -i 's/\btraceLoading\b/_traceLoading/g' $ISSUE_DETAIL
sed -i 's/\bsetTraceLoading\b/_setTraceLoading/g' $ISSUE_DETAIL

echo "=== 修正後 ==="
grep -n "traceLoading\|setTraceLoading\|_traceLoading\|_setTraceLoading" $ISSUE_DETAIL

echo ""
echo "=== ビルド確認 ==="
cd $FRONTEND_DIR
npm run build && echo "🎉 ビルド成功！" || grep "error TS" /tmp/b.log
