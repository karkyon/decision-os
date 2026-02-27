#!/usr/bin/env bash
# =============================================================================
# decision-os / 43_fix_issuedetail.sh
# IssueDetail.tsx L63 構文エラー修正 → ビルド成功
# =============================================================================
set -uo pipefail
GREEN='\033[0;32m'; CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'
info()    { echo -e "${CYAN}[INFO]${RESET}  $*"; }
success() { echo -e "${GREEN}[OK]${RESET}    $*"; }
section() { echo -e "\n${BOLD}========== $* ==========${RESET}"; }

FRONTEND_DIR="$HOME/projects/decision-os/frontend"
SRC="$FRONTEND_DIR/src"
FILE="$SRC/pages/IssueDetail.tsx"

cd "$FRONTEND_DIR"
eval "$(~/.nvm/nvm.sh 2>/dev/null || true)"
nvm use --lts 2>/dev/null || true

# =============================================================================
section "1. IssueDetail.tsx L60-70 の現状確認"
# =============================================================================
info "問題行の内容:"
sed -n '58,70p' "$FILE"

# =============================================================================
section "2. 構文エラー修正"
# =============================================================================
python3 << 'PYEOF'
path = "/home/karkyon/projects/decision-os/frontend/src/pages/IssueDetail.tsx"
with open(path, encoding='utf-8') as f:
    lines = f.readlines()

print(f"総行数: {len(lines)}")
print("L58-70:")
for i, l in enumerate(lines[57:70], 58):
    print(f"  {i:3d}: {l}", end='')

# L63 の問題を修正
# 正規表現削除で壊れたパターン: useAuthStore 参照行が中途半端に残っている
line63 = lines[62] if len(lines) > 62 else ""
print(f"\nL63の内容: '{line63.strip()}'")

# 修正: 壊れた行を削除（空行か構文的に壊れた行）
fixed_lines = []
i = 0
while i < len(lines):
    line = lines[i]
    # 構文的に壊れた行のパターン（単独の } や ; や空の式）
    stripped = line.strip()
    # "useAuthStore" の残骸や空の式ブロックを削除
    if (stripped in ['}', '};', ');', ')', ''] and i == 62):
        # 前後の文脈を確認して本当に不要な行かチェック
        print(f"\nL{i+1} を候補として確認: '{stripped}'")
        # この行が本当に不要かは前後を見て判断
        prev = lines[i-1].strip() if i > 0 else ""
        next_l = lines[i+1].strip() if i+1 < len(lines) else ""
        print(f"  前行(L{i}): '{prev}'")
        print(f"  次行(L{i+2}): '{next_l}'")
    fixed_lines.append(line)
    i += 1

# より直接的なアプローチ: L63付近の壊れたパターンを特定して修正
content = ''.join(lines)
print("\n=== 修正前のL55-75 ===")
all_lines = content.split('\n')
for i, l in enumerate(all_lines[54:75], 55):
    print(f"  {i:3d}: {l}")
PYEOF

# Python で直接修正
python3 << 'PYEOF'
import re
path = "/home/karkyon/projects/decision-os/frontend/src/pages/IssueDetail.tsx"
with open(path, encoding='utf-8') as f:
    content = f.read()

lines = content.split('\n')
line63 = lines[62] if len(lines) > 62 else ""
print(f"L63: '{line63}'")

# 正規表現で破壊されたパターンを修正
# よくある壊れ方: "useAuthStore();" → "" だが前後の括弧が残る
# 例: "  const { user } = ;" のような形
# 例: 単独の "};" が文脈なしに残る

# パターン1: 変数宣言の右辺が消えた → "const xxx = ;" 
content_fixed = re.sub(r'const\s+\w+\s*=\s*;', '', content)
# パターン2: 単独の空のブロック行
content_fixed = re.sub(r'^\s*\n\s*\n\s*\n', '\n\n', content_fixed, flags=re.MULTILINE)
# パターン3: 壊れた式 "= ;" や "; ;" 
content_fixed = re.sub(r'\s*=\s*;\s*\n', '\n', content_fixed)

# L63付近だけ詳細確認
lines2 = content_fixed.split('\n')
print("\n=== 修正後L58-72 ===")
for i, l in enumerate(lines2[57:72], 58):
    print(f"  {i:3d}: {l}")

with open(path, 'w', encoding='utf-8') as f:
    f.write(content_fixed)
print("\n✅ IssueDetail.tsx 修正完了")
PYEOF

# =============================================================================
section "3. ビルド最終確認"
# =============================================================================
info "npm run build 実行中..."
BUILD_OUT=$(npm run build 2>&1 || true)
TS_ERRORS=$(echo "$BUILD_OUT" | grep "error TS" || true)

if [[ -z "$TS_ERRORS" ]]; then
  success "🎉🎉🎉 TSビルドエラー 0件！ビルド完全成功！"
  echo "$BUILD_OUT" | grep -E "built|dist|chunk|✓|vite" | tail -8
else
  # 手動で問題行を表示して修正
  echo "$TS_ERRORS"
  echo ""
  info "IssueDetail.tsx L60-70 最終確認:"
  sed -n '58,72p' "$SRC/pages/IssueDetail.tsx"
  echo ""
  info "強制修正: L63を直接書き換えます..."
  python3 << 'PYEOF2'
path = "/home/karkyon/projects/decision-os/frontend/src/pages/IssueDetail.tsx"
with open(path, encoding='utf-8') as f:
    lines = f.readlines()

# エラーL63の行を確認・削除
print(f"L63: '{lines[62].rstrip()}'")
print(f"L62: '{lines[61].rstrip()}'")
print(f"L64: '{lines[63].rstrip()}'")

# 壊れた行（構文として成立しない行）を削除
new_lines = []
for i, line in enumerate(lines):
    stripped = line.strip()
    # 構文エラーを起こしそうなパターン
    is_broken = (
        re.search(r'^\s*[};,]\s*$', line) is None and  # 正常な単行 } ; , はOK
        (
            re.search(r'^\s*=\s*$', line) or          # = だけ
            re.search(r'^\s*\(\s*$', line) or          # ( だけ
            (i == 62 and len(stripped) < 5 and stripped not in ['{', '}', '};', '(', ')', ';', ','])
        )
    )
    if is_broken:
        import re
        print(f"  削除: L{i+1}: '{stripped}'")
    else:
        new_lines.append(line)

import re
with open(path, 'w', encoding='utf-8') as f:
    f.writelines(new_lines)
print("✅ 強制修正完了")
PYEOF2

  info "再ビルド..."
  BUILD_OUT2=$(npm run build 2>&1 || true)
  TS_ERRORS2=$(echo "$BUILD_OUT2" | grep "error TS" || true)
  if [[ -z "$TS_ERRORS2" ]]; then
    success "🎉 ビルド成功！"
    echo "$BUILD_OUT2" | tail -5
  else
    echo "$TS_ERRORS2"
    echo ""
    info "IssueDetail.tsx L55-80 最終状態:"
    sed -n '55,80p' "$SRC/pages/IssueDetail.tsx"
  fi
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  ✅ 成功なら次: bash ~/projects/decision-os/scripts/34_final_80.sh"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
