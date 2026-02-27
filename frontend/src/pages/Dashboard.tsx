import { useEffect, useState } from "react";
import Layout from "../components/Layout";
import { projectApi, issueApi } from "../api/client";
import { Issue, Project } from "../types";
import { useNavigate } from "react-router-dom";

export default function Dashboard() {
  const [projects, setProjects] = useState<Project[]>([]);
  const [openIssues, setOpenIssues] = useState<Issue[]>([]);
  const [loading, setLoading] = useState(true);
  const navigate = useNavigate();

  useEffect(() => {
    const load = async () => {
      try {
        const pRes = await projectApi.list();
        setProjects(pRes.data);
        if (pRes.data.length > 0) {
          const iRes = await issueApi.list(pRes.data[0].id, { status: "open" });
          setOpenIssues(iRes.data.slice(0, 10));
        }
      } catch (e) { console.error(e); }
      finally { setLoading(false); }
    };
    load();
  }, []);

  const priorityColor: Record<string, string> = {
    critical: "#ef4444", high: "#f59e0b", medium: "#3b82f6", low: "#94a3b8"
  };

  return (
    <Layout>
      <h1 style={{ margin: "0 0 24px", fontSize: "24px" }}>ダッシュボード</h1>

      {/* サマリーカード */}
      <div style={{ display: "grid", gridTemplateColumns: "repeat(3, 1fr)", gap: "16px", marginBottom: "32px" }}>
        {[
          { label: "プロジェクト数", value: projects.length, color: "#3b82f6" },
          { label: "未着手の課題", value: openIssues.length, color: "#f59e0b" },
          { label: "今日の作業", value: openIssues.filter(i => i.priority === "high" || i.priority === "critical").length, color: "#ef4444" },
        ].map((card) => (
          <div key={card.label} style={{ background: "#1e293b", borderRadius: "12px", padding: "20px",
            borderTop: `3px solid ${card.color}` }}>
            <p style={{ margin: "0 0 8px", color: "#64748b", fontSize: "13px" }}>{card.label}</p>
            <p style={{ margin: 0, fontSize: "32px", fontWeight: "700", color: card.color }}>{card.value}</p>
          </div>
        ))}
      </div>

      {/* クイックアクション */}
      <div style={{ display: "flex", gap: "12px", marginBottom: "32px" }}>
        <button onClick={() => navigate("/inputs/new")} style={btnStyle("#3b82f6")}>
          📥 要望を登録する
        </button>
        <button onClick={() => navigate("/issues")} style={btnStyle("#334155")}>
          📋 課題一覧を見る
        </button>
      </div>

      {/* 未処理課題一覧 */}
      <div style={{ background: "#1e293b", borderRadius: "12px", padding: "20px" }}>
        <h2 style={{ margin: "0 0 16px", fontSize: "16px" }}>🔴 要対応の課題</h2>
        {loading ? <p style={{ color: "#64748b" }}>読み込み中...</p> :
          openIssues.length === 0 ? <p style={{ color: "#64748b" }}>未着手の課題はありません</p> :
          openIssues.map((issue) => (
            <div key={issue.id} onClick={() => navigate(`/issues/${issue.id}`)}
              style={{ padding: "12px", marginBottom: "8px", background: "#0f172a", borderRadius: "8px",
                cursor: "pointer", borderLeft: `4px solid ${priorityColor[issue.priority]}`,
                display: "flex", justifyContent: "space-between", alignItems: "center" }}>
              <span style={{ fontSize: "14px" }}>{issue.title}</span>
              <span style={{ fontSize: "12px", color: priorityColor[issue.priority],
                background: "#1e293b", padding: "2px 8px", borderRadius: "12px" }}>
                {issue.priority}
              </span>
            </div>
          ))
        }
      </div>
    </Layout>
  );
}

const btnStyle = (bg: string): React.CSSProperties => ({
  padding: "10px 20px", background: bg, color: "#fff", border: "none",
  borderRadius: "8px", cursor: "pointer", fontSize: "14px", fontWeight: "600",
});
