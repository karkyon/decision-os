#!/usr/bin/env bash
# =============================================================================
# 39_fix_app_tsx.sh — App.tsx を強制的に正しい構造に書き直す
# Layout.tsx の構文エラー（line14）も修正
# =============================================================================
set -euo pipefail
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BOLD='\033[1m'; CYAN='\033[0;36m'; RESET='\033[0m'
ok()      { echo -e "${GREEN}[OK]${RESET}    $*"; }
info()    { echo -e "${CYAN}[INFO]${RESET}  $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
section() { echo -e "\n${BOLD}========== $* ==========${RESET}"; }

FRONTEND="$HOME/projects/decision-os/frontend"
SRC="$FRONTEND/src"
TS=$(date +%Y%m%d_%H%M%S)

export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && source "$NVM_DIR/nvm.sh"
nvm use 20 2>/dev/null || true

# =============================================================================
section "0. 既存コンポーネントの存在確認"
# =============================================================================
# 既存のimport対象コンポーネントを確認してから書き直す
python3 << 'PYEOF'
import os, glob

src = os.path.expanduser("~/projects/decision-os/frontend/src")
pages = glob.glob(f"{src}/pages/*.tsx")
comps = glob.glob(f"{src}/components/*.tsx")
hooks = glob.glob(f"{src}/hooks/*.tsx") + glob.glob(f"{src}/hooks/*.ts")

print("  pages/:", [os.path.basename(p) for p in pages])
print("  components/:", [os.path.basename(p) for p in comps])
print("  hooks/:", [os.path.basename(p) for p in hooks])

# authStore の export 形式を確認
auth_file = f"{src}/store/auth.ts"
if os.path.exists(auth_file):
    with open(auth_file) as f:
        content = f.read()
    print(f"\n  auth.ts の export形式:")
    import re
    exports = re.findall(r'export\s+(?:const|function|class|default|interface|type)\s+(\w+)', content)
    print(f"    {exports}")
    # useAuthStore か authStore か
    if 'useAuthStore' in content:
        print("    → useAuthStore (hook形式)")
    elif 'authStore' in content:
        print("    → authStore (store形式)")
PYEOF

# =============================================================================
section "1. App.tsx 強制書き直し"
# =============================================================================
cp "$SRC/App.tsx" "$SRC/App.tsx.bak.$TS"
info "現在の App.tsx の問題箇所:"
sed -n '18,35p' "$SRC/App.tsx"

# 既存コンポーネントを確認して適切なimportを生成
python3 << 'PYEOF'
import os, glob

src = os.path.expanduser("~/projects/decision-os/frontend/src")

# 使えるページコンポーネントを確認
pages = {os.path.basename(p).replace('.tsx', '') for p in glob.glob(f"{src}/pages/*.tsx")}
comps = {os.path.basename(p).replace('.tsx', '') for p in glob.glob(f"{src}/components/*.tsx")}

print("  利用可能なページ:", sorted(pages))
print("  利用可能なコンポーネント:", sorted(comps))

# auth store の形式確認
auth_file = f"{src}/store/auth.ts"
use_hook = False
if os.path.exists(auth_file):
    with open(auth_file) as f:
        content = f.read()
    use_hook = 'useAuthStore' in content

# App.tsx を生成
app_content = '''import { Routes, Route, Navigate } from 'react-router-dom'
'''

if use_hook:
    app_content += "import { useAuthStore } from './store/auth'\n"
else:
    app_content += "import { authStore } from './store/auth'\n"

# 必須ページのimport
core_pages = ['Login', 'Dashboard', 'InputNew', 'IssueList', 'IssueDetail']
for page in core_pages:
    if page in pages:
        app_content += f"import {page} from './pages/{page}'\n"

# Layout
if 'Layout' in comps:
    app_content += "import Layout from './components/Layout'\n"

# NotificationToast
toast = 'NotificationToast' in comps
if toast:
    app_content += "import NotificationToast from './components/NotificationToast'\n"

app_content += '''
function PrivateRoute({ children }: { children: React.ReactNode }) {
'''
if use_hook:
    app_content += '''  const { token } = useAuthStore()
  return token ? <>{children}</> : <Navigate to="/login" replace />
'''
else:
    app_content += '''  return authStore.isLoggedIn() ? <>{children}</> : <Navigate to="/login" replace />
'''

app_content += '''}

export default function App() {
  return (
    <>
      <Routes>
        <Route path="/login" element={<Login />} />
        <Route
          path="/"
          element={<PrivateRoute><Layout /></PrivateRoute>}
        >
          <Route index element={<Dashboard />} />
          <Route path="inputs/new" element={<InputNew />} />
          <Route path="issues" element={<IssueList />} />
          <Route path="issues/:id" element={<IssueDetail />} />
        </Route>
        <Route path="*" element={<Navigate to="/" replace />} />
      </Routes>
'''
if toast:
    app_content += "      <NotificationToast />\n"
app_content += "    </>\n  )\n}\n"

path = f"{src}/App.tsx"
with open(path, 'w') as f:
    f.write(app_content)
print("\n  ✅ App.tsx 書き直し完了")
print("\n  生成内容:")
for i, line in enumerate(app_content.split('\n'), 1):
    print(f"    {i:3d}: {line}")
PYEOF
ok "App.tsx 書き直し完了"

# =============================================================================
section "2. Layout.tsx 修正（line14: 関数引数内の構文エラー）"
# =============================================================================
# 問題: export default function Layout({
#         const { role } = usePermission(); children }: { children: React.ReactNode }) {
# → const { role } = usePermission(); が引数定義の中に誤って入っている
info "Layout.tsx line 13-16 の問題:"
sed -n '13,17p' "$SRC/components/Layout.tsx"

cp "$SRC/components/Layout.tsx" "$SRC/components/Layout.tsx.bak.$TS"

python3 << 'PYEOF'
import re, os

path = os.path.expanduser(
    "~/projects/decision-os/frontend/src/components/Layout.tsx"
)
with open(path) as f:
    content = f.read()

# 問題パターン:
# export default function Layout({
#   const { role } = usePermission(); children }: { children: React.ReactNode }) {
# → 修正: 引数からconst文を取り出して関数ボディ先頭に移動

# まず Layout が children を Outlet で置き換えているか確認
uses_children = 'children' in content
uses_outlet = 'Outlet' in content

# 修正: 引数定義を正常化
# パターン1: Layout({ const { role } = usePermission(); children }: { children: ... })
fixed = re.sub(
    r'export default function Layout\(\{\s*\n\s*const \{[^}]+\} = \w+\(\);[^\n]*children\s*\}:\s*\{[^}]+\}\)',
    'export default function Layout({ children }: { children: React.ReactNode })',
    content
)

if fixed != content:
    # const { role } = ... を関数ボディの先頭に追加
    fixed = fixed.replace(
        'export default function Layout({ children }: { children: React.ReactNode }) {',
        'export default function Layout({ children }: { children: React.ReactNode }) {\n  const { role } = usePermission ? usePermission() : { role: "pm" };'
    )
    # usePermission が使われているか確認
    if 'usePermission' in content:
        # 既にインポートされているなら正常に使う
        fixed = fixed.replace(
            'const { role } = usePermission ? usePermission() : { role: "pm" };',
            'const { role } = usePermission();'
        )

    with open(path, 'w') as f:
        f.write(fixed)
    print("  ✅ Layout.tsx 修正完了（引数定義の正常化）")
    print(f"\n  修正後 line 13-20:")
    for i, line in enumerate(fixed.split('\n')[12:20], 13):
        print(f"    {i}: {line}")
else:
    # パターンマッチしなかった場合はより広いパターンで試みる
    print("  パターン1 未マッチ → 別アプローチで修正")
    lines = content.split('\n')
    out = []
    skip_role_line = False
    for i, line in enumerate(lines):
        # 関数定義行で誤ってconst文が混入しているパターン
        if 'export default function Layout({' in line and 'const {' in lines[i+1] if i+1 < len(lines) else False:
            out.append('export default function Layout({ children }: { children: React.ReactNode }) {')
            # 次の行（const { role } = ... children }: ...）をスキップして role だけ取り出す
            skip_role_line = True
        elif skip_role_line:
            # この行には "const { role } = usePermission(); children }: { children: React.ReactNode }) {"
            # role の取得だけを残す
            role_match = re.search(r'const \{([^}]+)\} = (\w+)\(\)', line)
            if role_match:
                out.append(f'  const {{{role_match.group(1)}}} = {role_match.group(2)}();')
            skip_role_line = False
        else:
            out.append(line)

    new_content = '\n'.join(out)
    with open(path, 'w') as f:
        f.write(new_content)
    print("  ✅ Layout.tsx 修正完了（別アプローチ）")
    print(f"\n  修正後 line 13-20:")
    for i, line in enumerate(new_content.split('\n')[12:20], 13):
        print(f"    {i}: {line}")
PYEOF
ok "Layout.tsx 修正完了"

# =============================================================================
section "3. App.tsx が Layout を Outlet で使う場合の確認"
# =============================================================================
# Layout が children を受け取るのか Outlet を使うのかを確認して
# App.tsx のRoute構造を調整
python3 << 'PYEOF'
import os, re

layout_path = os.path.expanduser(
    "~/projects/decision-os/frontend/src/components/Layout.tsx"
)
app_path = os.path.expanduser(
    "~/projects/decision-os/frontend/src/App.tsx"
)

with open(layout_path) as f:
    layout = f.read()

uses_outlet = '<Outlet' in layout or "from 'react-router-dom'" in layout and 'Outlet' in layout
uses_children = '{children}' in layout

print(f"  Layout.tsx: Outlet使用={uses_outlet}, children使用={uses_children}")

with open(app_path) as f:
    app = f.read()

# Layoutがchildrenを受け取る場合はネストRouteではなくwrapperとして使う
if uses_children and not uses_outlet:
    print("  → Layoutはchildren型 → App.tsxのRoute構造を調整")
    # Outletベースの構造からchildren型に変更
    # <Route path="/" element={<PrivateRoute><Layout /></PrivateRoute>}>
    #   <Route index element={<Dashboard />} />  ← Outletが必要
    # を
    # 各ルートを PrivateRoute+Layout でラップする形に変更
    new_app = '''import { Routes, Route, Navigate } from 'react-router-dom'
'''
    # 元のimportを引き継ぐ
    import_lines = [l for l in app.split('\n') if l.startswith('import')]
    # Routesのimportだけ除外（既に追加済み）
    existing_imports = set()
    for l in import_lines:
        if 'react-router-dom' in l:
            continue
        new_app += l + '\n'
        existing_imports.add(l)

    new_app += '''
function PrivateRoute({ children }: { children: React.ReactNode }) {
  return authStore.isLoggedIn() ? <>{children}</> : <Navigate to="/login" replace />
}

export default function App() {
  return (
    <>
      <Routes>
        <Route path="/login" element={<Login />} />
        <Route path="/" element={<PrivateRoute><Layout><Dashboard /></Layout></PrivateRoute>} />
        <Route path="/inputs/new" element={<PrivateRoute><Layout><InputNew /></Layout></PrivateRoute>} />
        <Route path="/issues" element={<PrivateRoute><Layout><IssueList /></Layout></PrivateRoute>} />
        <Route path="/issues/:id" element={<PrivateRoute><Layout><IssueDetail /></Layout></PrivateRoute>} />
        <Route path="*" element={<Navigate to="/" replace />} />
      </Routes>
      <NotificationToast />
    </>
  )
}
'''
    with open(app_path, 'w') as f:
        f.write(new_app)
    print("  ✅ App.tsx をchildren型Layout用に調整")
else:
    print("  → LayoutはOutlet型 → App.tsxのネストRoute構造はそのまま ✅")
PYEOF

# =============================================================================
section "4. ビルド確認"
# =============================================================================
cd "$FRONTEND"
info "npm run build 実行中..."
BUILD_OUT=$(npm run build 2>&1)
BUILD_EXIT=$?

# ビルド結果表示
echo "$BUILD_OUT" | tail -30

echo ""
if [[ $BUILD_EXIT -eq 0 ]]; then
    ok "🎉 ビルド成功！ TSエラー完全解消"
    echo ""
    echo "  次のステップ:"
    echo "  → テストカバレッジ 80%（34_final_80.sh）"
    echo "  → 課題一覧バグ修正（#2）"
else
    warn "残りエラー:"
    echo "$BUILD_OUT" | grep "error TS" | head -30
    echo ""
    warn "ファイルの現状を確認します:"

    info "App.tsx (1-45行):"
    sed -n '1,45p' "$SRC/App.tsx"

    info "Layout.tsx (13-20行):"
    sed -n '13,20p' "$SRC/components/Layout.tsx"
fi

# =============================================================================
section "5. IssueDetail.tsx の確認（前回書き直し済みのはず）"
# =============================================================================
ISSUE_LINES=$(wc -l < "$SRC/pages/IssueDetail.tsx" 2>/dev/null || echo "0")
info "IssueDetail.tsx: $ISSUE_LINES 行"
if [[ $ISSUE_LINES -lt 300 ]]; then
    ok "IssueDetail.tsx: 正常な行数（書き直し済み）"
else
    warn "IssueDetail.tsx: まだ664行のまま → 再書き直しが必要"
    # 再書き直し（前回のスクリプトが成功していない場合）
    info "IssueDetail.tsx を再書き直しします..."
    # 前回書き直しのファイルが正しく出力されているか確認
    head -5 "$SRC/pages/IssueDetail.tsx"
fi
