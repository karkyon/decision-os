import { Link, useLocation, useNavigate } from "react-router-dom";
import { authStore } from "../store/auth";

const NAV = [
  { to: "/", label: "🏠 ダッシュボード" },
  { to: "/inputs/new", label: "📥 要望登録" },
  { to: "/issues", label: "📋 課題一覧" },
];

export default function Layout({ children }: { children: React.ReactNode }) {
  const location = useLocation();
  const navigate = useNavigate();
  const user = authStore.getUser();

  const logout = () => { authStore.clear(); navigate("/login"); };

  return (
    <div style={{ display: "flex", minHeight: "100vh", background: "#0f172a", color: "#f1f5f9" }}>
      {/* サイドバー */}
      <aside style={{ width: "220px", background: "#1e293b", padding: "24px 0", display: "flex", flexDirection: "column" }}>
        <div style={{ padding: "0 20px 24px", borderBottom: "1px solid #334155" }}>
          <h2 style={{ margin: 0, fontSize: "18px", color: "#f1f5f9" }}>⚖️ decision-os</h2>
        </div>
        <nav style={{ padding: "16px 0", flex: 1 }}>
          {NAV.map((item) => (
            <Link key={item.to} to={item.to} style={{
              display: "block", padding: "10px 20px", fontSize: "14px", textDecoration: "none",
              color: location.pathname === item.to ? "#3b82f6" : "#94a3b8",
              background: location.pathname === item.to ? "#0f172a" : "transparent",
              borderLeft: location.pathname === item.to ? "3px solid #3b82f6" : "3px solid transparent",
            }}>{item.label}</Link>
          ))}
        </nav>
        <div style={{ padding: "16px 20px", borderTop: "1px solid #334155" }}>
          <p style={{ margin: "0 0 8px", fontSize: "12px", color: "#64748b" }}>{user?.name}</p>
          <button onClick={logout} style={{ background: "none", border: "none", color: "#f87171", cursor: "pointer", fontSize: "12px", padding: 0 }}>ログアウト</button>
        </div>
      </aside>
      {/* メインコンテンツ */}
      <main style={{ flex: 1, padding: "24px", overflow: "auto" }}>{children}</main>
    </div>
  );
}
