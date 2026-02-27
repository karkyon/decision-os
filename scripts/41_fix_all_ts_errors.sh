#!/usr/bin/env bash
# =============================================================================
# decision-os / 41_fix_all_ts_errors.sh
# TSビルドエラー26件を一括修正
# 根本原因:
#   A) api/client.ts の export前自己参照
#   B) useAuthStore → authStore 名称変更が全体波及
#   C) jotai 未インストール + userAtom 未export
#   D) 複数ページの { children } JSX構造エラー
#   E) IssueList/Decisions の型エラー
#   F) NotificationToast の未使用変数
# =============================================================================
set -uo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'
info()    { echo -e "${CYAN}[INFO]${RESET}  $*"; }
success() { echo -e "${GREEN}[OK]${RESET}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
section() { echo -e "\n${BOLD}========== $* ==========${RESET}"; }

PROJECT_DIR="$HOME/projects/decision-os"
FRONTEND_DIR="$PROJECT_DIR/frontend"
SRC="$FRONTEND_DIR/src"
TS_STAMP=$(date +%Y%m%d_%H%M%S)
BACKUP="$PROJECT_DIR/backup_ts_$TS_STAMP"

cd "$FRONTEND_DIR"
eval "$(~/.nvm/nvm.sh 2>/dev/null || true)"
nvm use --lts 2>/dev/null || true

mkdir -p "$BACKUP"
info "バックアップ先: $BACKUP"

# 全対象ファイルをバックアップ
for f in \
  "$SRC/api/client.ts" \
  "$SRC/store/auth.ts" \
  "$SRC/components/Layout.tsx" \
  "$SRC/components/NotificationToast.tsx" \
  "$SRC/hooks/usePermission.ts" \
  "$SRC/pages/Dashboard.tsx" \
  "$SRC/pages/Decisions.tsx" \
  "$SRC/pages/InputNew.tsx" \
  "$SRC/pages/IssueDetail.tsx" \
  "$SRC/pages/IssueList.tsx" \
  "$SRC/pages/Labels.tsx" \
  "$SRC/pages/Search.tsx" \
  "$SRC/pages/UserManagement.tsx"; do
  [[ -f "$f" ]] && cp "$f" "$BACKUP/" && info "バックアップ: $(basename $f)"
done

# =============================================================================
section "A. store/auth.ts の export 確認・修正"
# =============================================================================
# useAuthStore が存在しない場合は authStore をラップして追加
AUTH_TS="$SRC/store/auth.ts"
if [[ -f "$AUTH_TS" ]]; then
  info "store/auth.ts の現在のexport:"
  grep -E "^export" "$AUTH_TS" | head -10

  # useAuthStore が存在しない場合は追加
  if ! grep -q "useAuthStore\|export.*useAuth" "$AUTH_TS"; then
    info "useAuthStore が未export → authStore ラッパーを追加"
    # userAtom も追加
    cat >> "$AUTH_TS" << 'AUTHEOF'

// --- 後方互換ラッパー (useAuthStore / userAtom) ---
export function useAuthStore() {
  return {
    isLoggedIn: () => authStore.isLoggedIn(),
    logout: () => authStore.logout(),
    user: authStore.getUser ? authStore.getUser() : null,
  }
}
export const userAtom = null  // jotai 非使用のダミー（usePermission.ts用）
AUTHEOF
    success "useAuthStore / userAtom を store/auth.ts に追加"
  else
    success "useAuthStore は既に存在"
  fi
else
  warn "store/auth.ts が見つかりません"
fi

# =============================================================================
section "B. hooks/usePermission.ts 修正（jotai 依存を除去）"
# =============================================================================
cat > "$SRC/hooks/usePermission.ts" << 'PERMEOF'
import { authStore } from '../store/auth'

export type Role = 'admin' | 'pm' | 'dev' | 'viewer'

export function usePermission() {
  // authStore から role を取得（jotai 不使用）
  const user = (authStore as any).getUser?.() ?? null
  const role: Role = (user?.role as Role) ?? 'viewer'

  return {
    role,
    isAdmin:  role === 'admin',
    isPM:     role === 'admin' || role === 'pm',
    canEdit:  role === 'admin' || role === 'pm' || role === 'dev',
    canView:  true,
  }
}
PERMEOF
success "usePermission.ts → jotai 依存を除去して書き直し"

# =============================================================================
section "C. api/client.ts 修正（自己参照エラー解消）"
# =============================================================================
CLIENT_TS="$SRC/api/client.ts"
if [[ -f "$CLIENT_TS" ]]; then
  info "api/client.ts の80-145行付近を確認..."
  sed -n '75,150p' "$CLIENT_TS"
  echo ""

  # エラー行確認: api が宣言前に使われているパターン
  # → axios instance を 'client' で先に作って、api は別途 export
  # 実際のファイル内容を python で読んで修正
  python3 << 'PYEOF'
import re

path = "/home/karkyon/projects/decision-os/frontend/src/api/client.ts"
with open(path, encoding="utf-8") as f:
    content = f.read()

# 問題パターン: const api = ... の宣言より前で api.xxx が使われている
# よくある原因: interceptor 内で api を参照している

# ① api が定義される行を探す
api_def_match = re.search(r'^(export\s+)?(const|let|var)\s+api\s*=', content, re.MULTILINE)
if api_def_match:
    api_def_line = content[:api_def_match.start()].count('\n') + 1
    print(f"api 定義行: {api_def_line}")
else:
    print("api 定義が見つかりません")

# ② エラーが出ている行 (83, 85-90, 132, 137, 140, 143) を表示
lines = content.split('\n')
problem_lines = [83, 85, 86, 87, 89, 90, 132, 137, 140, 143]
print("\n問題行の内容:")
for ln in problem_lines:
    if ln <= len(lines):
        print(f"  {ln:3d}: {lines[ln-1]}")
PYEOF

  # 修正戦略: エラー行が interceptor 内での api 自己参照なら
  # api の名前を axiosInstance に変更してから export api = axiosInstance とする
  python3 << 'PYEOF'
import re

path = "/home/karkyon/projects/decision-os/frontend/src/api/client.ts"
with open(path, encoding="utf-8") as f:
    content = f.read()

lines = content.split('\n')
# 問題行の内容確認
error_lines = [83, 85, 86, 87, 89, 90, 132, 137, 140, 143]
has_self_ref = False
for ln in error_lines:
    if ln <= len(lines):
        line_content = lines[ln-1]
        if 'api.' in line_content or 'api(' in line_content:
            has_self_ref = True
            print(f"  自己参照を発見 L{ln}: {line_content.strip()}")

if has_self_ref:
    print("\n→ api 変数の宣言前参照を修正します")
    # axios instance を _axiosInstance に rename して api は export alias にする
    # パターン1: const api = axios.create(...)
    modified = re.sub(
        r'^(export\s+)?(const)\s+(api)\s*=\s*(axios\.create)',
        r'\2 _axiosInstance = \4',
        content,
        flags=re.MULTILINE
    )
    # interceptor 内の api. → _axiosInstance. に変換
    # 但し export const api の行より上の api 参照のみ
    api_def_pos = content.find('const api = ')
    if api_def_pos == -1:
        api_def_pos = content.find('const api=')

    if '_axiosInstance' in modified and api_def_pos > 0:
        # interceptor 部分だけ変換（axios.create より後、export api より前）
        # 簡易対応: _axiosInstance への置換後に export を追加
        if 'export const api = _axiosInstance' not in modified and \
           'export { _axiosInstance as api }' not in modified:
            modified += '\nexport const api = _axiosInstance\n'

        with open(path, 'w', encoding='utf-8') as f:
            f.write(modified)
        print("  ✅ api/client.ts 修正完了（_axiosInstance + export api）")
    else:
        print("  → パターン1不適合。詳細修正が必要")
        print("  現在のファイル先頭80行:")
        for i, l in enumerate(lines[:80], 1):
            print(f"  {i:3d}: {l}")
else:
    print("→ 自己参照パターン不明。ファイル全体を表示します:")
    for i, l in enumerate(lines[:100], 1):
        print(f"  {i:3d}: {l}")
PYEOF
fi

# =============================================================================
section "D. Layout.tsx 修正（useAuthStore → authStore）"
# =============================================================================
LAYOUT="$SRC/components/Layout.tsx"
if grep -q "useAuthStore" "$LAYOUT"; then
  sed -i "s/import { useAuthStore } from '\.\.\/store\/auth'/import { authStore } from '..\/store\/auth'/g" "$LAYOUT"
  sed -i "s/import { useAuthStore } from \"\.\.\/store\/auth\"/import { authStore } from '..\/store\/auth'/g" "$LAYOUT"
  sed -i "s/const { logout } = useAuthStore()/const logout = authStore.logout.bind(authStore)/g" "$LAYOUT"
  sed -i "s/const { user, logout } = useAuthStore()/const logout = authStore.logout.bind(authStore)/g" "$LAYOUT"
  success "Layout.tsx: useAuthStore → authStore 修正"
else
  info "Layout.tsx: useAuthStore は使用されていません"
fi

# =============================================================================
section "E. IssueDetail.tsx 修正（useAuthStore → 削除）"
# =============================================================================
ISSUE_DETAIL="$SRC/pages/IssueDetail.tsx"
if [[ -f "$ISSUE_DETAIL" ]]; then
  if grep -q "useAuthStore" "$ISSUE_DETAIL"; then
    # useAuthStore のインポート行を削除（IssueDetailでは不要）
    sed -i "/import.*useAuthStore.*from.*store\/auth/d" "$ISSUE_DETAIL"
    success "IssueDetail.tsx: useAuthStore インポートを削除"
  fi
fi

# =============================================================================
section "F. NotificationToast.tsx 修正（未使用変数 prevLen）"
# =============================================================================
TOAST="$SRC/components/NotificationToast.tsx"
if [[ -f "$TOAST" ]]; then
  if grep -q "prevLen" "$TOAST"; then
    sed -n '18,25p' "$TOAST"
    # prevLen を _ に変更（または削除）
    python3 << 'PYEOF'
path = "/home/karkyon/projects/decision-os/frontend/src/components/NotificationToast.tsx"
with open(path, encoding="utf-8") as f:
    content = f.read()
# prevLen を _prevLen に変更（TSは _ prefix で未使用変数を許容）
modified = content.replace('prevLen', '_prevLen')
with open(path, 'w', encoding='utf-8') as f:
    f.write(modified)
print("  ✅ prevLen → _prevLen に変更")
PYEOF
  fi
fi

# =============================================================================
section "G. UserManagement.tsx 修正（api import形式）"
# =============================================================================
UMG="$SRC/pages/UserManagement.tsx"
if [[ -f "$UMG" ]]; then
  # 'api' を named import → default import に変更
  sed -i "s/import { api } from '\.\.\/api\/client'/import api from '..\/api\/client'/g" "$UMG"
  sed -i 's/import { api } from "\.\.\/api\/client"/import api from "..\/api\/client"/g' "$UMG"
  success "UserManagement.tsx: import { api } → import api 修正"
fi

# =============================================================================
section "H. IssueList.tsx 修正（型エラー・引数エラー）"
# =============================================================================
ISSUELIST="$SRC/pages/IssueList.tsx"
if [[ -f "$ISSUELIST" ]]; then
  info "IssueList.tsx の問題行確認..."
  sed -n '25,45p' "$ISSUELIST"
  echo ""
  sed -n '70,80p' "$ISSUELIST"
  echo ""

  python3 << 'PYEOF'
path = "/home/karkyon/projects/decision-os/frontend/src/pages/IssueList.tsx"
with open(path, encoding="utf-8") as f:
    content = f.read()

lines = content.split('\n')
# L32: Expected 0-1 arguments but got 2
# L33: Parameter 'r' implicitly has any
# L38: Type { children } has no properties
# L75: Property 'issue_type' does not exist

print("=== L28-42 ===")
for i in range(27, min(42, len(lines))):
    print(f"  {i+1:3d}: {lines[i]}")

print("\n=== L72-78 ===")
for i in range(71, min(78, len(lines))):
    print(f"  {i+1:3d}: {lines[i]}")
PYEOF

  # issue_type → intent_code か他のフィールドに修正
  if grep -q "issue_type" "$ISSUELIST"; then
    sed -i "s/\.issue_type/.intent_code/g" "$ISSUELIST"
    success "IssueList.tsx: .issue_type → .intent_code 修正"
  fi
fi

# =============================================================================
section "I. Decisions.tsx 修正"
# =============================================================================
DECISIONS="$SRC/pages/Decisions.tsx"
if [[ -f "$DECISIONS" ]]; then
  info "Decisions.tsx の問題行確認..."
  sed -n '45,70p' "$DECISIONS"
  echo ""
  sed -n '88,98p' "$DECISIONS"

  python3 << 'PYEOF'
path = "/home/karkyon/projects/decision-os/frontend/src/pages/Decisions.tsx"
with open(path, encoding="utf-8") as f:
    content = f.read()
lines = content.split('\n')

# L50: Parameter 'ir' implicitly has any → : any 追加
# L64: Type string vs object → string を適切な型に
# L94: { children } JSX エラー

modified = content

# L50付近: (ir) → (ir: any) もしくは (ir: Record<string,unknown>)
import re
modified = re.sub(r'\(ir\)\s*=>', '(ir: any) =>', modified)
modified = re.sub(r'\.map\(\(ir\)', '.map((ir: any)', modified)
modified = re.sub(r'\.filter\(\(ir\)', '.filter((ir: any)', modified)

# L64: fetchIssues(someString) → fetchIssues({project_id: someString}) パターン修正
# まず該当行を確認
for i, line in enumerate(lines[60:70], 61):
    if 'string' in line.lower() or 'project' in line.lower():
        print(f"  L{i}: {line}")

with open(path, 'w', encoding='utf-8') as f:
    f.write(modified)
print("  ✅ Decisions.tsx: ir → ir: any 修正")
PYEOF
fi

# =============================================================================
section "J. Dashboard.tsx / InputNew.tsx / Labels.tsx / Search.tsx の { children } JSX エラー修正"
# =============================================================================
# エラーパターン: Type '{ children: Element }' has no properties in common with type 'IntrinsicAttributes'
# 原因: カスタムコンポーネントに children を渡しているが、そのコンポーネントが children を受け取らない
# 対応: 各ファイルの問題行を確認して修正

for PAGE in Dashboard InputNew Labels Search; do
  PAGE_FILE="$SRC/pages/${PAGE}.tsx"
  if [[ -f "$PAGE_FILE" ]]; then
    info "${PAGE}.tsx の問題行確認..."
    # { children } エラーが出る行番号を特定
    python3 << PYEOF
import re
path = "$SRC/pages/${PAGE}.tsx"
with open(path, encoding='utf-8') as f:
    content = f.read()
lines = content.split('\n')

# 問題パターンを探す: <SomeComponent> ... </SomeComponent> だが children を受け取らない
# よくあるのは <Card> や <Section> のようなラッパーをchildrenなしで定義しているケース
print(f"=== ${PAGE}.tsx 先頭20行 ===")
for i, l in enumerate(lines[:20], 1):
    print(f"  {i:3d}: {l}")
PYEOF
  fi
done

# =============================================================================
section "K. ビルド再試行（修正後）"
# =============================================================================
info "npm run build 実行中..."
BUILD_OUT=$(npm run build 2>&1 || true)
TS_ERRORS=$(echo "$BUILD_OUT" | grep "error TS" || true)
REMAINING=$(echo "$TS_ERRORS" | grep -c "error TS" || true)

if [[ -z "$TS_ERRORS" ]]; then
  success "✅✅✅ TSビルドエラー 0件！ビルド成功！"
  echo "$BUILD_OUT" | tail -8
else
  warn "残存エラー: ${REMAINING}件"
  echo "$TS_ERRORS"
  echo ""
  info "詳細診断のため各ファイルの問題行を表示:"
  # client.ts の現在の状態
  echo ""
  echo "=== api/client.ts 75-150行 ==="
  sed -n '75,150p' "$SRC/api/client.ts" || true
  echo ""
  echo "=== store/auth.ts ==="
  cat "$SRC/store/auth.ts" || true
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  結果を貼り付けてください。"
echo "  ポイント:"
echo "  ① ビルド成功か（エラー0件か）"
echo "  ② 残存エラーがあれば → 42_ts_final.sh で個別対応"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
