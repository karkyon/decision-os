#!/bin/bash
# App.tsx を正しい内容で完全上書き
set -e

APP="$HOME/projects/decision-os/frontend/src/App.tsx"
GREEN='\033[0;32m'; CYAN='\033[0;36m'; NC='\033[0m'
ok()      { echo -e "${GREEN}✅ $1${NC}"; }
section() { echo -e "\n${CYAN}━━━ $1 ━━━${NC}"; }

section "1. App.tsx バックアップ"
cp "$APP" "${APP}.bak"
ok "バックアップ: ${APP}.bak"

section "2. App.tsx 完全上書き"

cat > "$APP" << 'APPEOF'
import { Routes, Route, Navigate } from 'react-router-dom'
import Layout from '@/components/Layout'
import Dashboard from '@/pages/Dashboard'
import ProjectList from '@/pages/ProjectList'
import IssueList from '@/pages/IssueList'
import IssueDetail from '@/pages/IssueDetail'
import InputNew from '@/pages/InputNew'
import InputHistory from '@/pages/InputHistory'
import InputDetail from '@/pages/InputDetail'
import Login from '@/pages/Login'
import UserManagement from '@/pages/UserManagement'
import WorkspaceSelect from '@/pages/WorkspaceSelect'
import InviteAccept from '@/pages/InviteAccept'
import TOTPSetup from '@/pages/TOTPSetup'
import TOTPLogin from '@/pages/TOTPLogin'

function PrivateRoute({ children }: { children: React.ReactNode }) {
  const token = localStorage.getItem('access_token')
  return token ? <>{children}</> : <Navigate to="/login" replace />
}

export default function App() {
  return (
    <Routes>
      <Route path="/login" element={<Login />} />
      <Route path="/invite" element={<InviteAccept />} />
      <Route path="/workspaces" element={
        <PrivateRoute><WorkspaceSelect /></PrivateRoute>
      } />
      <Route path="/totp-setup" element={
        <PrivateRoute><TOTPSetup /></PrivateRoute>
      } />
      <Route path="/totp-login" element={<TOTPLogin />} />
      <Route
        path="/"
        element={
          <PrivateRoute>
            <Layout />
          </PrivateRoute>
        }
      >
        <Route index element={<Dashboard />} />
        <Route path="projects" element={<ProjectList />} />
        <Route path="issues" element={<IssueList />} />
        <Route path="issues/:id" element={<IssueDetail />} />
        <Route path="inputs/new" element={<InputNew />} />
        <Route path="inputs" element={<InputHistory />} />
        <Route path="inputs/:id" element={<InputDetail />} />
        <Route path="users" element={<UserManagement />} />
      </Route>
    </Routes>
  )
}
APPEOF

ok "App.tsx 上書き完了"

section "3. 確認"
cat -n "$APP"

section "4. TypeScript チェック"
cd "$HOME/projects/decision-os/frontend"
npx tsc --noEmit 2>&1
if [ ${PIPESTATUS[0]} -eq 0 ]; then
  ok "TypeScript エラーなし"
else
  echo "⚠️ TSエラーあり（上記を確認）"
fi

section "5. Vite 再起動"
pkill -f "vite" 2>/dev/null || true
sleep 1
nohup npm run dev -- --host 0.0.0.0 --port 3008 \
  > "$HOME/projects/decision-os/logs/frontend.log" 2>&1 &
sleep 4

tail -6 "$HOME/projects/decision-os/logs/frontend.log"

if curl -s http://localhost:3008 | grep -q "html\|vite\|react"; then
  ok "フロントエンド起動 ✅  → http://localhost:3008/login"
else
  echo "⚠️ 応答なし:"
  tail -20 "$HOME/projects/decision-os/logs/frontend.log"
fi
