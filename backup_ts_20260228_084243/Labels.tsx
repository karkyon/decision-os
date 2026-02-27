import { useState, useEffect } from "react";
import Layout from "../components/Layout";
import { labelApi } from "../api/client";

interface LabelInfo {
  label:       string;
  issue_count: number;
  last_used:   string | null;
}

export default function Labels() {
  const [labels,   setLabels]   = useState<LabelInfo[]>([]);
  const [loading,  setLoading]  = useState(true);
  const [q,        setQ]        = useState("");
  const [mergeFrom, setMergeFrom] = useState("");
  const [mergeTo,   setMergeTo]   = useState("");
  const [merging,   setMerging]   = useState(false);
  const [msg,       setMsg]       = useState("");

  const fetchLabels = async (query = "") => {
    setLoading(true);
    try {
      const res = await labelApi.list(query);
      setLabels(res.data.labels || []);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => { fetchLabels(); }, []);

  const handleMerge = async () => {
    if (!mergeFrom || !mergeTo) return;
    setMerging(true);
    try {
      const res = await labelApi.merge(mergeFrom, mergeTo);
      setMsg(`✅ 「${mergeFrom}」→「${mergeTo}」に ${res.data.merged} 件統合しました`);
      setMergeFrom(""); setMergeTo("");
      fetchLabels(q);
    } catch (e: any) {
      setMsg(`❌ エラー: ${e.response?.data?.detail || "統合に失敗しました"}`);
    } finally {
      setMerging(false);
    }
  };

  const handleDelete = async (label: string) => {
    if (!confirm(`「${label}」を全課題から削除しますか？`)) return;
    try {
      await labelApi.delete(label);
      setMsg(`✅ 「${label}」を削除しました`);
      fetchLabels(q);
    } catch {
      setMsg("❌ 削除に失敗しました");
    }
  };

  const filtered = labels.filter(l =>
    q === "" || l.label.toLowerCase().includes(q.toLowerCase())
  );

  return (
    <Layout>
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: "24px" }}>
        <h1 style={{ margin: 0, fontSize: "20px" }}>🏷 ラベル管理</h1>
        <span style={{ color: "#64748b", fontSize: "13px" }}>{labels.length} ラベル使用中</span>
      </div>

      {msg && (
        <div style={{
          padding: "10px 16px", borderRadius: "8px", marginBottom: "16px",
          background: msg.startsWith("✅") ? "#14532d" : "#7f1d1d",
          color: msg.startsWith("✅") ? "#86efac" : "#fca5a5", fontSize: "13px",
        }}>
          {msg}
          <button onClick={() => setMsg("")} style={{ float: "right", background: "none", border: "none", color: "inherit", cursor: "pointer" }}>×</button>
        </div>
      )}

      {/* 統合パネル */}
      <div style={{
        background: "#1e293b", border: "1px solid #334155",
        borderRadius: "12px", padding: "16px", marginBottom: "20px",
      }}>
        <h3 style={{ margin: "0 0 12px", fontSize: "14px", color: "#94a3b8" }}>🔀 ラベル統合（命名ゆれ修正）</h3>
        <div style={{ display: "flex", gap: "8px", alignItems: "center", flexWrap: "wrap" }}>
          <input
            value={mergeFrom}
            onChange={e => setMergeFrom(e.target.value)}
            placeholder="統合元のラベル（例: バグ）"
            style={inputStyle}
          />
          <span style={{ color: "#64748b" }}>→</span>
          <input
            value={mergeTo}
            onChange={e => setMergeTo(e.target.value)}
            placeholder="統合先のラベル（例: BUG）"
            style={inputStyle}
          />
          <button
            onClick={handleMerge}
            disabled={!mergeFrom || !mergeTo || merging}
            style={{
              padding: "8px 20px", borderRadius: "8px", border: "none",
              background: !mergeFrom || !mergeTo ? "#334155" : "#3b82f6",
              color: "#fff", cursor: !mergeFrom || !mergeTo ? "not-allowed" : "pointer",
              fontSize: "13px", fontWeight: "600",
            }}
          >
            {merging ? "統合中..." : "統合する"}
          </button>
        </div>
      </div>

      {/* 検索 */}
      <div style={{ marginBottom: "16px" }}>
        <input
          value={q}
          onChange={e => setQ(e.target.value)}
          placeholder="ラベルを検索..."
          style={{ ...inputStyle, width: "100%", boxSizing: "border-box" }}
        />
      </div>

      {/* ラベル一覧 */}
      {loading ? (
        <div style={{ textAlign: "center", padding: "60px", color: "#64748b" }}>読み込み中...</div>
      ) : filtered.length === 0 ? (
        <div style={{ textAlign: "center", padding: "60px", color: "#475569" }}>
          <div style={{ fontSize: "40px", marginBottom: "12px" }}>🏷</div>
          <p>ラベルがありません</p>
        </div>
      ) : (
        <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fill, minmax(240px, 1fr))", gap: "10px" }}>
          {filtered.map(info => (
            <div key={info.label} style={{
              background: "#1e293b", border: "1px solid #334155",
              borderRadius: "10px", padding: "14px 16px",
              display: "flex", justifyContent: "space-between", alignItems: "center",
            }}>
              <div>
                <div style={{
                  display: "inline-block", padding: "3px 12px", borderRadius: "20px",
                  background: "#0f172a", border: "1px solid #334155",
                  color: "#e2e8f0", fontSize: "13px", fontWeight: "500",
                  marginBottom: "6px",
                }}>
                  {info.label}
                </div>
                <div style={{ fontSize: "12px", color: "#64748b" }}>
                  📋 {info.issue_count} 件の課題
                </div>
                {info.last_used && (
                  <div style={{ fontSize: "11px", color: "#475569", marginTop: "2px" }}>
                    最終: {new Date(info.last_used).toLocaleDateString("ja-JP")}
                  </div>
                )}
              </div>
              <div style={{ display: "flex", flexDirection: "column", gap: "4px" }}>
                <button
                  onClick={() => { setMergeFrom(info.label); }}
                  title="このラベルを統合元に設定"
                  style={{
                    padding: "4px 10px", borderRadius: "6px", border: "none",
                    background: "#334155", color: "#94a3b8",
                    cursor: "pointer", fontSize: "11px",
                  }}
                >統合</button>
                {info.issue_count === 0 && (
                  <button
                    onClick={() => handleDelete(info.label)}
                    style={{
                      padding: "4px 10px", borderRadius: "6px", border: "none",
                      background: "#7f1d1d", color: "#fca5a5",
                      cursor: "pointer", fontSize: "11px",
                    }}
                  >削除</button>
                )}
              </div>
            </div>
          ))}
        </div>
      )}
    </Layout>
  );
}

const inputStyle: React.CSSProperties = {
  padding: "8px 12px", borderRadius: "8px",
  background: "#0f172a", border: "1px solid #334155",
  color: "#e2e8f0", fontSize: "13px", outline: "none",
};
