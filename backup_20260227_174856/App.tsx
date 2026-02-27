import { Routes, Route, Navigate } from "react-router-dom";
import { authStore } from "./store/auth";
import Login from "./pages/Login";
import Dashboard from "./pages/Dashboard";
import InputNew from "./pages/InputNew";
import IssueList from "./pages/IssueList";
import IssueDetail from "./pages/IssueDetail";

function PrivateRoute({ children }: { children: React.ReactNode }) {
  return authStore.isLoggedIn() ? <>{children}</> : <Navigate to="/login" replace />;
}

export default function App() {
  return (
    <Routes>
      <Route path="/login" element={<Login />} />
      <Route path="/" element={<PrivateRoute><Dashboard /></PrivateRoute>} />
      <Route path="/inputs/new" element={<PrivateRoute><InputNew /></PrivateRoute>} />
      <Route path="/issues" element={<PrivateRoute><IssueList /></PrivateRoute>} />
      <Route path="/issues/:id" element={<PrivateRoute><IssueDetail /></PrivateRoute>} />
      <Route path="*" element={<Navigate to="/" replace />} />
    </Routes>
  );
}
