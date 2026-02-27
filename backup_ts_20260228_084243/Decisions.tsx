import { useState, useEffect } from "react";
import { useNavigate, useSearchParams } from "react-router-dom";
import Layout from "../components/Layout";
import { decisionApi, projectApi, issueApi } from "../api/client";

interface Decision {
  id: string;
  project_id: string;
  decision_text: string;
  reason: string;
  decided_by?: string;
  related_request_id?: string;
  related_issue_id?: string;
  created_at: string;
  decider?: { id: string; name: string; role: string };
}

interface Project { id: string; name: string }
interface Issue   { id: string; title: string }

export default function Decisions() {
  const navigate = useNavigate();
  const [searchParams] = useSearchParams();
  const filterIssueId = searchParams.get("issue_id") || "";

  const [decisions, setDecisions]   = useState<Decision[]>([]);
  const [projects, setProjects]     = useState<Project[]>([]);
  const [issues, setIssues]         = useState<Issue[]>([]);
  const [loading, setLoading]       = useState(true);
  const [showForm, setShowForm]     = useState(false);
  const [submitting, setSubmitting] = useState(false);
  const [error, setError]           = useState("");

  // フォーム状態
  const [form, setForm] = useState({
    project_id: "",
    decision_text: "",
    reason: "",
    related_issue_id: filterIssueId,
    related_request_id: "",
  });

  useEffect(() => {
    Promise.all([
      projectApi.list().then(r => {
        setProjects(r.data);
        if (r.data.length > 0 && !form.project_id) {
          setForm(f => ({ ...f, project_id: r.data[0].id }));
          // プロジェクト最初のを使って課題一覧も取得
          issueApi.list(r.data[0].id).then(ir => setIssues(ir.data)).catch(() => {});
        }
      }),
      decisionApi.list(
        filterIssueId ? { issue_id: filterIssueId } : {}
      ).then(r => setDecisions(r.data)),
    ])
    .catch(() => setError("データ取得に失敗しました"))
    .finally(() => setLoading(false));
  }, [filterIssueId]);

  const handleProjectChange = async (pid: string) => {
    setForm(f => ({ ...f, project_id: pid, related_issue_id: "" }));
    try {
      const r = await issueApi.list(pid);
      setIssues(r.data);
    } catch { setIssues([]); }
  };

  const handleSubmit = async () => {
    if (!form.project_id || !form.decision_text.trim() || !form.reason.trim()) {
      setError("プロジェクト・決定内容・理由は必須です");
      return;
    }
    setSubmitting(true); setError("");
    try {
      const payload: any = {
        project_id: form.project_id,
        decision_text: form.decision_text.trim(),
        reason: form.reason.trim(),
      };
      if (form.related_issue_id)   payload.related_issue_id   = form.related_issue_id;
      if (form.related_request_id) payload.related_request_id = form.related_request_id;

      const res = await decisionApi.create(payload);
      setDecisions(prev => [res.data, ...prev]);
      setForm(f => ({ ...f, decision_text: "", reason: "", related_issue_id: "", related_request_id: "" }));
      setShowForm(false);
    } catch (e: any) {
      setError(e.response?.data?.detail || "登録に失敗しました");
    } finally { setSubmitting(false); }
  };

  return (
    <Layout>
      {/* ヘッダー */}
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: "24px" }}>
        <div>
          <h1 style={{ margin: 0, fontSize: "20px" }}>📝 決定ログ</h1>
          {filterIssueId && (
            <p style={{ margin: "4px 0 0", fontSize: "13px", color: "#64748b" }}>
              課題に関連する決定のみ表示
              <button onClick={() => navigate("/decisions")}
                style={{ marginLeft: "8px", background: "none", border: "none", color: "#3b82f6", cursor: "pointer", fontSize: "12px" }}>
                × 絞り込み解除
              </button>
            </p>
          )}
        </div>
        <button
          onClick={() => setShowForm(v => !v)}
          style={{
            padding: "10px 20px", borderRadius: "8px", border: "none",
            background: showForm ? "#475569" : "#3b82f6",
            color: "#fff", cursor: "pointer", fontSize: "14px", fontWeight: "600",
          }}
        >
          {showForm ? "✕ キャンセル" : "＋ 決定を記録"}
        </button>
      </div>

      {error && (
        <div style={{
          background: "#fef2f2", border: "1px solid #fca5a5", borderRadius: "8px",
          padding: "10px 16px", marginBottom: "16px", color: "#dc2626", fontSize: "13px",
        }}>⚠️ {error}</div>
      )}

      {/* 登録フォーム */}
      {showForm && (
        <div style={{
          background: "#1e293b", borderRadius: "12px", padding: "24px",
          marginBottom: "24px", border: "1px solid #3b82f6",
        }}>
          <h2 style={{ margin: "0 0 20px", fontSize: "16px", color: "#60a5fa" }}>
            📝 決定内容を記録する
          </h2>

          <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: "16px", marginBottom: "16px" }}>
            {/* プロジェクト */}
            <div>
              <label style={labelStyle}>プロジェクト *</label>
              <select
                value={form.project_id}
                onChange={e => handleProjectChange(e.target.value)}
                style={selectStyle}
              >
                <option value="">選択してください</option>
                {projects.map(p => <option key={p.id} value={p.id}>{p.name}</option>)}
              </select>
            </div>

            {/* 関連課題（任意） */}
            <div>
              <label style={labelStyle}>関連課題（任意）</label>
              <select
                value={form.related_issue_id}
                onChange={e => setForm(f => ({ ...f, related_issue_id: e.target.value }))}
                style={selectStyle}
              >
                <option value="">なし</option>
                {issues.map(i => (
                  <option key={i.id} value={i.id}>
                    {i.title.slice(0, 50)}
                  </option>
                ))}
              </select>
            </div>
          </div>

          {/* 決定内容 */}
          <div style={{ marginBottom: "16px" }}>
            <label style={labelStyle}>決定内容 *</label>
            <textarea
              value={form.decision_text}
              onChange={e => setForm(f => ({ ...f, decision_text: e.target.value }))}
              placeholder="何を決定したか。例：検索機能のタグ選択をドロップダウンからチェックボックスUIに変更する"
              style={{ ...textareaStyle, minHeight: "80px" }}
            />
          </div>

          {/* 理由 */}
          <div style={{ marginBottom: "20px" }}>
            <label style={labelStyle}>決定理由 *</label>
            <textarea
              value={form.reason}
              onChange={e => setForm(f => ({ ...f, reason: e.target.value }))}
              placeholder="なぜその決定をしたか。例：ユーザーから命名ゆれによる検索失敗の報告が複数あり、既存タグから選択させる方式が最善と判断"
              style={{ ...textareaStyle, minHeight: "80px" }}
            />
          </div>

          <div style={{ display: "flex", gap: "10px", justifyContent: "flex-end" }}>
            <button onClick={() => setShowForm(false)} style={cancelBtnStyle}>キャンセル</button>
            <button
              onClick={handleSubmit}
              disabled={submitting || !form.decision_text.trim() || !form.reason.trim()}
              style={{
                padding: "10px 28px", borderRadius: "8px", border: "none",
                background: submitting || !form.decision_text.trim() || !form.reason.trim()
                  ? "#334155" : "#3b82f6",
                color: "#fff",
                cursor: submitting || !form.decision_text.trim() || !form.reason.trim()
                  ? "not-allowed" : "pointer",
                fontSize: "14px", fontWeight: "600",
              }}
            >
              {submitting ? "🔄 保存中..." : "💾 決定を記録"}
            </button>
          </div>
        </div>
      )}

      {/* 一覧 */}
      {loading ? (
        <div style={{ textAlign: "center", padding: "60px", color: "#64748b" }}>🔄 読み込み中...</div>
      ) : decisions.length === 0 ? (
        <div style={{ textAlign: "center", padding: "80px", color: "#475569" }}>
          <div style={{ fontSize: "48px", marginBottom: "16px" }}>📝</div>
          <p style={{ margin: 0, fontSize: "16px" }}>決定ログがまだありません</p>
          <p style={{ margin: "8px 0 0", fontSize: "13px", color: "#334155" }}>
            「＋ 決定を記録」で最初の決定ログを追加しましょう
          </p>
        </div>
      ) : (
        <div style={{ display: "flex", flexDirection: "column", gap: "12px" }}>
          {decisions.map(d => (
            <DecisionCard
              key={d.id}
              decision={d}
              onIssueClick={id => navigate(`/issues/${id}`)}
            />
          ))}
        </div>
      )}
    </Layout>
  );
}

function DecisionCard({ decision: d, onIssueClick }: {
  decision: Decision;
  onIssueClick: (id: string) => void;
}) {
  const [expanded, setExpanded] = useState(false);

  return (
    <div style={{
      background: "#1e293b", borderRadius: "10px",
      border: "1px solid #334155", overflow: "hidden",
    }}>
      {/* ヘッダー行 */}
      <div
        onClick={() => setExpanded(v => !v)}
        style={{
          padding: "16px 20px", cursor: "pointer",
          display: "flex", alignItems: "flex-start", gap: "12px",
        }}
      >
        <span style={{ fontSize: "20px", flexShrink: 0, marginTop: "2px" }}>📝</span>
        <div style={{ flex: 1, minWidth: 0 }}>
          <p style={{
            margin: 0, fontSize: "14px", fontWeight: "600", color: "#e2e8f0",
            overflow: "hidden", textOverflow: "ellipsis",
            whiteSpace: expanded ? "normal" : "nowrap",
          }}>
            {d.decision_text}
          </p>
          <div style={{ display: "flex", gap: "12px", marginTop: "6px", flexWrap: "wrap" }}>
            <span style={{ fontSize: "12px", color: "#64748b" }}>
              🕐 {new Date(d.created_at).toLocaleString("ja-JP")}
            </span>
            {d.decider && (
              <span style={{ fontSize: "12px", color: "#94a3b8" }}>
                👤 {d.decider.name}
              </span>
            )}
            {d.related_issue_id && (
              <button
                onClick={e => { e.stopPropagation(); onIssueClick(d.related_issue_id!); }}
                style={{
                  background: "#1d3557", border: "1px solid #3b82f6",
                  borderRadius: "4px", padding: "1px 8px",
                  color: "#60a5fa", fontSize: "11px", cursor: "pointer",
                }}
              >
                📋 関連課題を開く
              </button>
            )}
          </div>
        </div>
        <span style={{ color: "#475569", fontSize: "12px", flexShrink: 0 }}>
          {expanded ? "▲" : "▼"}
        </span>
      </div>

      {/* 展開: 理由 */}
      {expanded && (
        <div style={{
          padding: "0 20px 16px 52px",
          borderTop: "1px solid #334155",
          paddingTop: "12px",
        }}>
          <p style={{ margin: "0 0 4px", fontSize: "12px", color: "#64748b", fontWeight: "600" }}>
            決定理由
          </p>
          <p style={{
            margin: 0, fontSize: "14px", color: "#94a3b8",
            lineHeight: 1.7, whiteSpace: "pre-wrap",
          }}>
            {d.reason}
          </p>
          {d.related_request_id && (
            <p style={{ margin: "8px 0 0", fontSize: "12px", color: "#475569" }}>
              🔗 関連原文ID: {d.related_request_id.slice(0, 8)}...
            </p>
          )}
        </div>
      )}
    </div>
  );
}

// スタイル定数
const labelStyle: React.CSSProperties = {
  display: "block", marginBottom: "6px",
  fontSize: "13px", color: "#94a3b8", fontWeight: "500",
};
const selectStyle: React.CSSProperties = {
  width: "100%", padding: "9px 12px", borderRadius: "8px",
  background: "#0f172a", border: "1px solid #334155",
  color: "#e2e8f0", fontSize: "14px",
};
const textareaStyle: React.CSSProperties = {
  width: "100%", padding: "10px 14px", borderRadius: "8px",
  background: "#0f172a", border: "1px solid #334155",
  color: "#e2e8f0", fontSize: "14px", resize: "vertical",
  boxSizing: "border-box", lineHeight: 1.6,
};
const cancelBtnStyle: React.CSSProperties = {
  padding: "10px 20px", borderRadius: "8px", border: "none",
  background: "#334155", color: "#94a3b8", cursor: "pointer", fontSize: "14px",
};
