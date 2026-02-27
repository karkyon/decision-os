#!/usr/bin/env bash
# =============================================================================
# decision-os / Step 8: TSビルドエラー修正（2件）
# 1. InputNew.tsx(20): 'inputId' is declared but never read  → 変数削除
# 2. App.test.tsx(2):  'screen' has no exported member       → import修正
# =============================================================================
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'
info()    { echo -e "${CYAN}[INFO]${RESET}  $*"; }
success() { echo -e "${GREEN}[OK]${RESET}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
error()   { echo -e "${RED}[ERROR]${RESET} $*"; exit 1; }
section() { echo -e "\n${BOLD}========== $* ==========${RESET}"; }

FRONTEND_DIR="$HOME/projects/decision-os/frontend"
[[ -d "$FRONTEND_DIR" ]] || error "フロントエンドディレクトリが見つかりません"

TS=$(date +%Y%m%d_%H%M%S)

# =============================================================================
section "1. InputNew.tsx 確認"
# =============================================================================

INPUT_NEW="$FRONTEND_DIR/src/pages/InputNew.tsx"
[[ -f "$INPUT_NEW" ]] || error "InputNew.tsx が見つかりません: $INPUT_NEW"

info "InputNew.tsx の 15〜25行目:"
sed -n '15,25p' "$INPUT_NEW"

echo ""
info "inputId 関連の行:"
grep -n "inputId" "$INPUT_NEW" || warn "inputId が見つかりません（既に修正済み？）"

# =============================================================================
section "2. InputNew.tsx 修正 → inputId 未使用変数を削除"
# =============================================================================

cp "$INPUT_NEW" "${INPUT_NEW}.bak.$TS"

python3 - << 'PYEOF'
import os, re

filepath = os.path.expanduser(
    "~/projects/decision-os/frontend/src/pages/InputNew.tsx"
)

with open(filepath, "r") as f:
    content = f.read()

original = content

# パターン1: const [inputId, setInputId] = useState... のような宣言
# inputId だけ未使用で setInputId は使われている場合は _ に置き換え
# inputId も setInputId も未使用なら行ごと削除

# パターン別に対処
if "const [inputId, setInputId]" in content:
    # setInputId が使われているか確認
    uses_setter = content.count("setInputId") > 1  # 宣言以外で使用
    if uses_setter:
        # inputId だけ未使用 → _ に変更
        content = content.replace(
            "const [inputId, setInputId]",
            "const [_inputId, setInputId]"
        )
        print("修正: inputId → _inputId（setInputId は保持）")
    else:
        # 両方未使用 → 行ごと削除
        content = re.sub(
            r'\s*const \[inputId, setInputId\] = .*\n',
            '\n',
            content
        )
        print("修正: const [inputId, setInputId] = ... の行を削除")

elif "const inputId" in content:
    # const inputId = ... のような宣言
    content = re.sub(
        r'\s*const inputId = .*\n',
        '\n',
        content
    )
    print("修正: const inputId = ... の行を削除")

elif re.search(r'\binputId\b', content):
    # その他のパターン → _inputId に変更
    content = re.sub(r'\binputId\b', '_inputId', content)
    print("修正: inputId → _inputId")

else:
    print("inputId が見つかりません（既に修正済みの可能性）")

if content != original:
    with open(filepath, "w") as f:
        f.write(content)
    print("InputNew.tsx を保存しました")
PYEOF

success "InputNew.tsx 修正完了"

# =============================================================================
section "3. App.test.tsx 確認"
# =============================================================================

APP_TEST="$FRONTEND_DIR/src/test/App.test.tsx"
[[ -f "$APP_TEST" ]] || {
  # パスが違う可能性を確認
  warn "$APP_TEST が見つかりません。検索中..."
  APP_TEST=$(find "$FRONTEND_DIR/src" -name "App.test.tsx" 2>/dev/null | head -1 || echo "")
  [[ -n "$APP_TEST" ]] || error "App.test.tsx が見つかりません"
  info "発見: $APP_TEST"
}

info "App.test.tsx の全文:"
cat "$APP_TEST"

# =============================================================================
section "4. App.test.tsx 修正 → screen インポートを修正"
# =============================================================================

cp "$APP_TEST" "${APP_TEST}.bak.$TS"

python3 - << 'PYEOF'
import os, re

# ファイルを検索
import subprocess, glob

frontend_dir = os.path.expanduser("~/projects/decision-os/frontend")
matches = glob.glob(f"{frontend_dir}/src/**/App.test.tsx", recursive=True)
if not matches:
    print("App.test.tsx が見つかりません")
    exit(1)
filepath = matches[0]

with open(filepath, "r") as f:
    content = f.read()

original = content

# エラー: 'screen' has no exported member from '@testing-library/react'
# 原因: @testing-library/react のバージョンによっては screen が別の場所にある
# または vitest/jest の設定で別パッケージが必要

# 修正方針: screen を使っているなら @testing-library/react から直接importに変更
# または screen を使っていないなら import から削除

lines = content.split('\n')
new_lines = []
modified = False

for line in lines:
    # import { render, screen, ... } from '@testing-library/react'
    if '@testing-library/react' in line and 'screen' in line:
        # screen を削除してみる
        new_line = re.sub(r',?\s*screen\s*,?', '', line)
        # カンマの整理
        new_line = re.sub(r'\{\s*,', '{', new_line)
        new_line = re.sub(r',\s*\}', '}', new_line)
        new_line = re.sub(r'\{\s*\}', '{}', new_line)
        
        # もし screen が本文で使われているなら vitest の screen をインポート
        uses_screen = content.count('screen.') > 0
        
        if uses_screen:
            # screen は vitest か @testing-library/dom から取得
            new_line = line.replace(
                "from '@testing-library/react'",
                "from '@testing-library/react'"
            )
            # screen だけ別途インポート
            new_line = re.sub(r'\bscreen\b', '', new_line)
            new_line = re.sub(r'\{\s*,', '{', new_line)
            new_line = re.sub(r',\s*\}', '}', new_line)
            new_lines.append(new_line)
            new_lines.append("import { screen } from '@testing-library/dom';")
            modified = True
            print(f"修正: screen を @testing-library/dom から別途インポート")
        else:
            # screen を import から削除するだけ
            new_lines.append(new_line)
            modified = True
            print(f"修正: import から screen を削除（本文で未使用）")
    else:
        new_lines.append(line)

if modified:
    content = '\n'.join(new_lines)
    with open(filepath, "w") as f:
        f.write(content)
    print("App.test.tsx を保存しました")
    print("\n修正後の内容:")
    print(content)
else:
    print("変更なし（既に修正済みの可能性）")
PYEOF

success "App.test.tsx 修正完了"

# =============================================================================
section "5. ビルド確認"
# =============================================================================

cd "$FRONTEND_DIR"

# nvm 有効化
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && source "$NVM_DIR/nvm.sh"
nvm use 20 2>/dev/null || true

info "npm run build を実行中..."
BUILD_OUT=$(npm run build 2>&1)
BUILD_EXIT=$?

echo "$BUILD_OUT" | tail -20

if [[ $BUILD_EXIT -eq 0 ]]; then
  success "ビルド成功！ TSエラー解消済み ✅"
else
  # エラーが残っている場合は詳細表示
  warn "ビルドエラーが残っています:"
  echo "$BUILD_OUT" | grep -E "error|Error" || true
  echo ""
  warn "修正が必要な箇所を確認してください"
  
  # 現在のファイル状態を表示
  info "InputNew.tsx の現在の状態（15〜30行目）:"
  sed -n '15,30p' "$FRONTEND_DIR/src/pages/InputNew.tsx"
  echo ""
  info "App.test.tsx の現在の状態:"
  cat "$FRONTEND_DIR/src/test/App.test.tsx" 2>/dev/null || \
    find "$FRONTEND_DIR/src" -name "App.test.tsx" -exec cat {} \;
fi

# =============================================================================
section "完了"
# =============================================================================

echo ""
echo -e "${YELLOW}確認コマンド:${RESET}"
echo "  npm run build   # エラーゼロを確認"
echo "  npm run dev     # 開発サーバーは既に起動中"
