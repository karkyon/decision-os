import { useEffect, useState } from "react";
import { useParams, useNavigate } from "react-router-dom";
import Layout from "../components/Layout";
import { issueApi, traceApi } from "../api/client";
import { Issue, STATUS_LABELS, PRIORITY_COLORS, Priority, IssueStatus } from "../types";

export default function IssueDetail() {
  const { id } = useParams<{ id: string }>();
  const navigate = useNavigate();
  const [issue, setIssue] = useState<Issue | null>(null);
  const [trace, setTrace] = useState<any>(null);
  const [tab, setTab] = useState<"detail"|"trace">("detail");
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    if (!id) return;
    Promise.all([issueApi.get(id), traceApi.get(id)])
      .then(([iRes, tRes]) => { setIssue(iRes.data); setTrace(tRes.data); })
      .finally(() => setLoading(false));
  }, [id]);

  const updateStatus = async (status: string) => {
    if (!id) return;
    const res = await issueApi.update(id, { status });
    setIssue(res.data);
  };

  if (loading) return <Layout><p style={{ color: "#64748b" }}>読み込み中...</p></Layout>;
  if (!issue) return <Layout><p style={{ color: "#f87171" }}>課題が見つかりません</p></Layout>;

  return (
    <Layout>
      <div style={{ marginBottom: "16px" }}>
        <button onClick={() => navigate("/issues")} style={{ background: "none", border: "none",
          color: "#60a5fa", cursor: "pointer", fontSize: "13px" }}>← 課題一覧</button>
      </div>

      {/* ヘッダー */}
      <div style={{ background: "#1e293b", borderRadius: "12px", padding: "24px", marginBottom: "16px",
        borderLeft: `4px solid ${PRIORITY_COLORS[issue.priority as Priority]}` }}>
        <h1 style={{ margin: "0 0 16px", fontSize: "20px" }}>{issue.title}</h1>
        <div style={{ display: "flex", gap: "12px", flexWrap: "wrap" }}>
          <span style={badge("#334155")}>{STATUS_LABELS[issue.status as IssueStatus]}</span>
          <span style={badge(PRIORITY_COLORS[issue.priority as Priority] + "33",
            PRIORITY_COLORS[issue.priority as Priority])}>{issue.priority}</span>
          <span style={badge("#334155")}>🕒 {new Date(issue.created_at).toLocaleString("ja-JP")}</span>
        </div>
        {issue.description && (
          <p style={{ margin: "16px 0 0", color: "#94a3b8", fontSize: "14px", lineHeight: "1.6" }}>
            {issue.description}
          </p>
        )}

        {/* ステータス変更 */}
        <div style={{ marginTop: "16px", display: "flex", gap: "8px" }}>
          {(["open","doing","review","done","hold"] as IssueStatus[]).map(s => (
            <button key={s} onClick={() => updateStatus(s)}
              style={{ padding: "6px 12px", borderRadius: "6px", border: "none", cursor: "pointer",
                fontSize: "12px", background: issue.status === s ? "#3b82f6" : "#334155",
                color: "#fff" }}>
              {STATUS_LABELS[s]}
            </button>
          ))}
        </div>
      </div>

      {/* タブ */}
      <div style={{ display: "flex", gap: "4px", marginBottom: "16px" }}>
        {["detail","trace"].map(t => (
          <button key={t} onClick={() => setTab(t as any)}
            style={{ padding: "8px 20px", borderRadius: "8px", border: "none", cursor: "pointer",
              background: tab === t ? "#3b82f6" : "#1e293b", color: "#fff", fontSize: "14px" }}>
            {t === "detail" ? "📋 詳細" : "🔍 トレーサビリティ"}
          </button>
        ))}
      </div>

      {/* 詳細タブ */}
      {tab === "detail" && (
        <div style={{ background: "#1e293b", borderRadius: "12px", padding: "24px" }}>
          <p style={{ color: "#64748b", margin: 0 }}>課題ID: {issue.id}</p>
          {issue.labels && <p style={{ margin: "8px 0 0", color: "#94a3b8" }}>ラベル: {issue.labels}</p>}
        </div>
      )}

      {/* トレーサビリティタブ */}
      {tab === "trace" && trace && (
        <div style={{ background: "#1e293b", borderRadius: "12px", padding: "24px" }}>
          <h3 style={{ margin: "0 0 20px", fontSize: "16px" }}>🔍 意思決定トレーサー</h3>
          <div style={{ display: "flex", flexDirection: "column", gap: "0" }}>
            {[
              { label: "📋 課題", data: trace.issue, fields: ["title","status","priority"] },
              { label: "⚡ Action", data: trace.action, fields: ["action_type","decision_reason","decided_at"] },
              { label: "🧩 分解ITEM", data: trace.item, fields: ["text","intent_code","domain_code","confidence"] },
              { label: "📥 原文（RAW_INPUT）", data: trace.input, fields: ["source_type","raw_text","created_at"] },
            ].map((layer, idx) => (
              <div key={layer.label}>
                <div style={{ background: "#0f172a", borderRadius: "8px", padding: "16px",
                  borderLeft: "4px solid #3b82f6" }}>
                  <p style={{ margin: "0 0 8px", fontSize: "13px", color: "#60a5fa", fontWeight: "600" }}>
                    {layer.label}
                  </p>
                  {layer.data ? (
                    layer.fields.map(f => (
                      <div key={f} style={{ marginBottom: "4px" }}>
                        <span style={{ color: "#64748b", fontSize: "12px" }}>{f}: </span>
                        <span style={{ color: "#e2e8f0", fontSize: "13px" }}>
                          {String(layer.data[f] || "—").slice(0, 200)}
                        </span>
                      </div>
                    ))
                  ) : (
                    <p style={{ margin: 0, color: "#475569", fontSize: "13px" }}>データなし（直接登録）</p>
                  )}
                </div>
                {idx < 3 && (
                  <div style={{ display: "flex", justifyContent: "center", padding: "6px 0" }}>
                    <span style={{ color: "#3b82f6", fontSize: "20px" }}>↑</span>
                  </div>
                )}
              </div>
            ))}
          </div>
        </div>
      )}
    </Layout>
  );
}

const badge = (bg: string, color = "#94a3b8"): React.CSSProperties => ({
  padding: "4px 12px", borderRadius: "12px", background: bg,
  color, fontSize: "12px", display: "inline-block",
});
