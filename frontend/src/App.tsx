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

function PrivateRoute({ children }: { children: React.ReactNode }) {
  const token = localStorage.getItem('access_token')
  return token ? <>{children}</> : <Navigate to="/login" replace />
}

export default function App() {
  return (
    <Routes>
      <Route path="/login" element={<Login />} />
      <Route path="/workspaces" element={
        <PrivateRoute><WorkspaceSelect /></PrivateRoute>
      } />
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
