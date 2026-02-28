import { useEffect, useState } from "react";
import { useNavigate } from "react-router-dom";
import { projectApi, issueApi } from "../api/client";
import { Issue, IssueStatus, Priority, STATUS_LABELS, PRIORITY_COLORS, Project } from "../types";

const STATUS_ORDER: IssueStatus[] = ["open","doing","review","done","hold"];



export default function IssueList() {
  const navigate = useNavigate();
  const [projects, setProjects] = useState<Project[]>([]);
  const [projectId, setProjectId] = useState("");
  const [issues, setIssues] = useState<Issue[]>([]);
  const [filterStatus, setFilterStatus] = useState("");
  const [loading, setLoading] = useState(false);

  useEffect(() => {
    projectApi.list().then((r: any) => {
      setProjects(r.data);
      if (r.data.length > 0) setProjectId(r.data[0].id);
    });
  }, []);

  useEffect(() => {
    if (!projectId) return;
    setLoading(true);
    issueApi.list({ project_id: projectId, ...(filterStatus ? { status: filterStatus } : {}) })
      .then((r: any) => setIssues(r.data))
      .finally(() => setLoading(false));
  }, [projectId, filterStatus]);

  return (
    <div style={{padding:"24px",color:"#e2e8f0"}}>
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: "24px" }}>
        <h1 style={{ margin: 0, fontSize: "24px" }}>📋 課題一覧</h1>
        <button onClick={() => navigate("/inputs/new")} style={btnStyle("#3b82f6")}>
          + 要望から課題作成
        </button>
      </div>

      {/* フィルター */}
      <div style={{ display: "flex", gap: "8px", marginBottom: "20px" }}>
        <select value={projectId} onChange={e => setProjectId(e.target.value)} style={selStyle}>
          {projects.map(p => <option key={p.id} value={p.id}>{p.name}</option>)}
        </select>
        <select value={filterStatus} onChange={e => setFilterStatus(e.target.value)} style={selStyle}>
          <option value="">すべてのステータス</option>
          {STATUS_ORDER.map(s => <option key={s} value={s}>{STATUS_LABELS[s]}</option>)}
        </select>
      </div>

      {/* カンバン風表示 */}
      {loading ? <p style={{ color: "#64748b" }}>読み込み中...</p> :
        issues.length === 0 ? (
          <div style={{ textAlign: "center", padding: "60px", color: "#64748b" }}>
            <p style={{ fontSize: "48px" }}>📭</p>
            <p>課題はありません</p>
            <button onClick={() => navigate("/inputs/new")} style={btnStyle("#3b82f6")}>
              要望を登録して課題を作成する
            </button>
          </div>
        ) : (
          <div style={{ display: "flex", flexDirection: "column", gap: "8px" }}>
            {issues.map((issue) => (
              <div key={issue.id} onClick={() => navigate(`/issues/${issue.id}`)}
                style={{ background: "#1e293b", borderRadius: "8px", padding: "16px",
                  cursor: "pointer", display: "flex", gap: "16px", alignItems: "center",
                  borderLeft: `4px solid ${PRIORITY_COLORS[issue.priority as Priority]}` }}>
                <div style={{ flex: 1 }}>
                  <p style={{ margin: "0 0 4px", fontSize: "15px", fontWeight: "500" }}>{"⬜"} {issue.title}</p>
                  <p style={{ margin: 0, fontSize: "12px", color: "#64748b" }}>
                    {new Date(issue.created_at).toLocaleDateString("ja-JP")}
                  </p>
                </div>
                <div style={{ display: "flex", gap: "8px", alignItems: "center" }}>
                  <span style={{ fontSize: "12px", padding: "3px 10px", borderRadius: "12px",
                    background: "#334155", color: "#94a3b8" }}>
                    {STATUS_LABELS[issue.status as IssueStatus]}
                  </span>
                  <span style={{ fontSize: "12px", padding: "3px 10px", borderRadius: "12px",
                    background: PRIORITY_COLORS[issue.priority as Priority] + "22",
                    color: PRIORITY_COLORS[issue.priority as Priority] }}>
                    {issue.priority}
                  </span>
                  <span style={{ color: "#475569" }}>→</span>
                </div>
              </div>
            ))}
          </div>
        )
      }
    </div>
  );
}

const selStyle: React.CSSProperties = {
  padding: "8px 12px", background: "#1e293b", color: "#f1f5f9",
  border: "1px solid #334155", borderRadius: "6px", fontSize: "13px",
};
const btnStyle = (bg: string): React.CSSProperties => ({
  padding: "8px 18px", background: bg, color: "#fff", border: "none",
  borderRadius: "8px", cursor: "pointer", fontSize: "14px", fontWeight: "600",
});
