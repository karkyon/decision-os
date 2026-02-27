import { useState, useEffect } from "react";
import { useNavigate } from "react-router-dom";
import Layout from "../components/Layout";
import client from "../api/client";
import { PRIORITY_COLORS, type Priority } from "../types/index";

interface DashboardCounts {
  inputs: { total: number; unprocessed: number };
  items: { pending_action: number };
  issues: {
    open: number;
    total: number;
    recent: { id: string; title: string; status: string; priority: string }[];
  };
}

export default function Dashboard() {
  const navigate = useNavigate();
  const [counts, setCounts] = useState<DashboardCounts | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");

  useEffect(() => {
    client.get("/dashboard/counts")
      .then(res => setCounts(res.data))
      .catch(() => setError("データ取得に失敗しました"))
      .finally(() => setLoading(false));
  }, []);

  if (loading) return (
    <Layout>
      <div style={{ textAlign: "center", padding: "80px", color: "#64748b" }}>
        🔄 読み込み中...
      </div>
    </Layout>
  );

  return (
    <Layout>
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: "28px" }}>
        <h1 style={{ margin: 0, fontSize: "22px" }}>ダッシュボード</h1>
        <button
          onClick={() => navigate("/inputs/new")}
          style={{
            padding: "10px 20px", borderRadius: "8px",
            background: "#3b82f6", color: "#fff", border: "none",
            cursor: "pointer", fontSize: "14px", fontWeight: "600",
          }}
        >
          ＋ 要望を登録
        </button>
      </div>

      {error && (
        <div style={{
          background: "#fef2f2", border: "1px solid #fca5a5",
          borderRadius: "8px", padding: "12px 16px", marginBottom: "16px",
          color: "#dc2626", fontSize: "14px",
        }}>
          ⚠️ {error}
        </div>
      )}

      {/* カウントカード */}
      <div style={{ display: "grid", gridTemplateColumns: "repeat(3, 1fr)", gap: "16px", marginBottom: "32px" }}>
        <CountCard
          icon="📥"
          label="未処理 INPUT"
          value={counts?.inputs.unprocessed ?? 0}
          sub={`総数 ${counts?.inputs.total ?? 0}件`}
          onClick={() => navigate("/inputs/new")}
          accent="#f59e0b"
        />
        <CountCard
          icon="🧩"
          label="ACTION待ち ITEM"
          value={counts?.items.pending_action ?? 0}
          sub="要判断"
          accent="#8b5cf6"
        />
        <CountCard
          icon="📋"
          label="未完了 ISSUE"
          value={counts?.issues.open ?? 0}
          sub={`総数 ${counts?.issues.total ?? 0}件`}
          onClick={() => navigate("/issues")}
          accent="#3b82f6"
        />
      </div>

      {/* 直近の課題 */}
      {counts && counts.issues.recent.length > 0 && (
        <div style={{ background: "#1e293b", borderRadius: "12px", padding: "20px" }}>
          <h2 style={{ margin: "0 0 16px", fontSize: "16px", color: "#94a3b8" }}>
            🕐 直近の課題
          </h2>
          <div style={{ display: "flex", flexDirection: "column", gap: "10px" }}>
            {counts.issues.recent.map(issue => (
              <div
                key={issue.id}
                onClick={() => navigate(`/issues/${issue.id}`)}
                style={{
                  display: "flex", alignItems: "center", gap: "12px",
                  padding: "12px 16px", borderRadius: "8px",
                  background: "#0f172a", cursor: "pointer",
                  border: "1px solid #334155",
                  transition: "border-color 0.15s",
                }}
                onMouseEnter={e => (e.currentTarget.style.borderColor = "#3b82f6")}
                onMouseLeave={e => (e.currentTarget.style.borderColor = "#334155")}
              >
                <div style={{
                  width: "8px", height: "8px", borderRadius: "50%", flexShrink: 0,
                  background: PRIORITY_COLORS[issue.priority as Priority] || "#94a3b8",
                }} />
                <span style={{ flex: 1, fontSize: "14px", color: "#e2e8f0" }}>{issue.title}</span>
                <span style={{
                  fontSize: "12px", padding: "2px 8px", borderRadius: "4px",
                  background: "#334155", color: "#94a3b8",
                }}>
                  {issue.status}
                </span>
              </div>
            ))}
          </div>
          <div style={{ marginTop: "12px", textAlign: "right" }}>
            <button
              onClick={() => navigate("/issues")}
              style={{
                background: "none", border: "none", color: "#3b82f6",
                cursor: "pointer", fontSize: "13px",
              }}
            >
              すべての課題を見る →
            </button>
          </div>
        </div>
      )}

      {/* データがない場合 */}
      {counts && counts.issues.total === 0 && counts.inputs.total === 0 && (
        <div style={{
          background: "#1e293b", borderRadius: "12px", padding: "48px",
          textAlign: "center", color: "#64748b",
        }}>
          <div style={{ fontSize: "48px", marginBottom: "16px" }}>🚀</div>
          <p style={{ margin: "0 0 20px", fontSize: "16px" }}>
            まだデータがありません。要望・不具合を登録してみましょう！
          </p>
          <button
            onClick={() => navigate("/inputs/new")}
            style={{
              padding: "12px 28px", borderRadius: "8px",
              background: "#3b82f6", color: "#fff", border: "none",
              cursor: "pointer", fontSize: "15px", fontWeight: "600",
            }}
          >
            ＋ 最初の要望を登録
          </button>
        </div>
      )}
    </Layout>
  );
}

function CountCard({
  icon, label, value, sub, onClick, accent,
}: {
  icon: string; label: string; value: number; sub: string;
  onClick?: () => void; accent: string;
}) {
  return (
    <div
      onClick={onClick}
      style={{
        background: "#1e293b", borderRadius: "12px", padding: "20px 24px",
        cursor: onClick ? "pointer" : "default",
        border: `1px solid ${accent}33`,
        transition: "border-color 0.15s",
      }}
      onMouseEnter={e => onClick && (e.currentTarget.style.borderColor = accent)}
      onMouseLeave={e => onClick && (e.currentTarget.style.borderColor = `${accent}33`)}
    >
      <div style={{ fontSize: "24px", marginBottom: "8px" }}>{icon}</div>
      <div style={{ fontSize: "32px", fontWeight: "700", color: accent, lineHeight: 1 }}>
        {value}
      </div>
      <div style={{ fontSize: "13px", color: "#e2e8f0", marginTop: "4px" }}>{label}</div>
      <div style={{ fontSize: "11px", color: "#64748b", marginTop: "4px" }}>{sub}</div>
    </div>
  );
}
