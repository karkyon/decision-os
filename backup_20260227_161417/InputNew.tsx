import { useState, useEffect } from "react";
import { useNavigate } from "react-router-dom";
import Layout from "../components/Layout";
import { projectApi, inputApi, analyzeApi, itemApi, actionApi } from "../api/client";
import { Item, IntentCode, DomainCode, ActionType, INTENT_LABELS, DOMAIN_LABELS, ACTION_LABELS, Project } from "../types";

const INTENTS: IntentCode[] = ["BUG","REQ","IMP","QST","MIS","FBK","INF","TSK"];
const DOMAINS: DomainCode[] = ["UI","API","DB","AUTH","PERF","SEC","OPS","SPEC"];
const ACTIONS: ActionType[] = ["CREATE_ISSUE","ANSWER","STORE","REJECT","HOLD","LINK_EXISTING"];

type ItemWithAction = Item & { selectedAction?: ActionType; reason?: string; actionSaved?: boolean };

export default function InputNew() {
  const navigate = useNavigate();
  const [projects, setProjects] = useState<Project[]>([]);
  const [projectId, setProjectId] = useState("");
  const [sourceType, setSourceType] = useState("email");
  const [rawText, setRawText] = useState("");
  const [step, setStep] = useState<1|2|3>(1);
  const [items, setItems] = useState<ItemWithAction[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState("");

  useEffect(() => {
    projectApi.list().then(r => {
      setProjects(r.data);
      if (r.data.length > 0) setProjectId(r.data[0].id);
    });
  }, []);

  // Step1: 原文登録 → 分解
  const handleAnalyze = async () => {
    if (!rawText.trim()) { setError("原文を入力してください"); return; }
    if (!projectId) { setError("プロジェクトを選択してください"); return; }
    setLoading(true); setError("");
    try {
      const inpRes = await inputApi.create({ project_id: projectId, source_type: sourceType, raw_text: rawText });
      const anlRes = await analyzeApi.analyze(inpRes.data.id);
      setItems(anlRes.data.map((item: Item) => ({
        ...item,
        selectedAction: item.intent_code === "BUG" ? "CREATE_ISSUE" :
                        item.intent_code === "REQ" ? "HOLD" : "STORE",
      })));
      setStep(2);
    } catch (e: any) {
      setError(e.response?.data?.detail || "分解に失敗しました");
    } finally { setLoading(false); }
  };

  // Step2: 分類修正
  const updateItemField = (id: string, field: string, value: string) => {
    setItems(prev => prev.map(item => item.id === id ? { ...item, [field]: value } : item));
  };

  const saveItemCorrection = async (item: ItemWithAction) => {
    await itemApi.update(item.id, { intent_code: item.intent_code, domain_code: item.domain_code });
  };

  // Step3: ACTION確定
  const handleSaveActions = async () => {
    setLoading(true); setError("");
    try {
      for (const item of items) {
        if (item.selectedAction) {
          await actionApi.create({
            item_id: item.id,
            action_type: item.selectedAction,
            decision_reason: item.reason || "",
          });
        }
      }
      setStep(3);
    } catch (e: any) {
      setError(e.response?.data?.detail || "Action保存に失敗しました");
    } finally { setLoading(false); }
  };

  const confidenceColor = (c: number) =>
    c >= 0.75 ? "#22c55e" : c >= 0.5 ? "#f59e0b" : "#ef4444";

  return (
    <Layout>
      {/* ステップインジケーター */}
      <div style={{ display: "flex", gap: "8px", marginBottom: "24px", alignItems: "center" }}>
        {["1. 原文入力", "2. 分類確認", "3. ACTION決定"].map((s, i) => (
          <div key={s} style={{ display: "flex", alignItems: "center", gap: "8px" }}>
            <div style={{ padding: "6px 16px", borderRadius: "20px", fontSize: "13px",
              background: step === i+1 ? "#3b82f6" : step > i+1 ? "#22c55e" : "#334155",
              color: "#fff" }}>{step > i+1 ? `✓ ${s}` : s}</div>
            {i < 2 && <span style={{ color: "#475569" }}>→</span>}
          </div>
        ))}
      </div>

      {/* Step 1: 原文入力 */}
      {step === 1 && (
        <div style={cardStyle}>
          <h2 style={{ margin: "0 0 20px", fontSize: "18px" }}>📥 原文を入力</h2>
          <div style={{ display: "flex", gap: "12px", marginBottom: "16px" }}>
            <select value={projectId} onChange={e => setProjectId(e.target.value)} style={selectStyle}>
              {projects.map(p => <option key={p.id} value={p.id}>{p.name}</option>)}
            </select>
            <select value={sourceType} onChange={e => setSourceType(e.target.value)} style={selectStyle}>
              {["email","voice","meeting","bug","other"].map(s => (
                <option key={s} value={s}>{s}</option>
              ))}
            </select>
          </div>
          <textarea value={rawText} onChange={e => setRawText(e.target.value)}
            placeholder="メール本文・会話録音テキスト・会議メモ等を貼り付けてください..."
            style={{ ...inputStyle, height: "200px", resize: "vertical" }} />
          {error && <p style={{ color: "#f87171", margin: "8px 0" }}>{error}</p>}
          <button onClick={handleAnalyze} disabled={loading} style={btnStyle("#3b82f6")}>
            {loading ? "分解中..." : "🔍 解析する"}
          </button>
        </div>
      )}

      {/* Step 2: 分類確認・修正 */}
      {step === 2 && (
        <div style={cardStyle}>
          <h2 style={{ margin: "0 0 8px", fontSize: "18px" }}>🔍 分解結果を確認・修正</h2>
          <p style={{ color: "#64748b", margin: "0 0 20px", fontSize: "13px" }}>
            AIの自動判定を確認し、必要に応じて修正してください
          </p>
          {items.map((item, idx) => (
            <div key={item.id} style={{ background: "#0f172a", borderRadius: "8px",
              padding: "16px", marginBottom: "12px",
              borderLeft: `4px solid ${confidenceColor(item.confidence)}` }}>
              <div style={{ display: "flex", justifyContent: "space-between", marginBottom: "8px" }}>
                <span style={{ fontSize: "13px", color: "#64748b" }}>#{idx + 1}</span>
                <span style={{ fontSize: "12px", color: confidenceColor(item.confidence) }}>
                  信頼度: {(item.confidence * 100).toFixed(0)}%
                  {item.confidence < 0.75 && " ⚠️要確認"}
                </span>
              </div>
              <p style={{ margin: "0 0 12px", fontSize: "14px", color: "#e2e8f0" }}>{item.text}</p>
              <div style={{ display: "flex", gap: "8px" }}>
                <select value={item.intent_code}
                  onChange={e => { updateItemField(item.id, "intent_code", e.target.value); saveItemCorrection(item); }}
                  style={selectStyle}>
                  {INTENTS.map(i => <option key={i} value={i}>{INTENT_LABELS[i]}</option>)}
                </select>
                <select value={item.domain_code}
                  onChange={e => { updateItemField(item.id, "domain_code", e.target.value); saveItemCorrection(item); }}
                  style={selectStyle}>
                  {DOMAINS.map(d => <option key={d} value={d}>{DOMAIN_LABELS[d]}</option>)}
                </select>
                <select value={item.selectedAction || "STORE"}
                  onChange={e => updateItemField(item.id, "selectedAction", e.target.value)}
                  style={{ ...selectStyle, background: "#1e293b" }}>
                  {ACTIONS.map(a => <option key={a} value={a}>{ACTION_LABELS[a]}</option>)}
                </select>
              </div>
              {(item.selectedAction === "REJECT" || item.selectedAction === "HOLD") && (
                <input type="text" placeholder="理由を入力（必須）" value={item.reason || ""}
                  onChange={e => updateItemField(item.id, "reason", e.target.value)}
                  style={{ ...inputStyle, marginTop: "8px" }} />
              )}
            </div>
          ))}
          {error && <p style={{ color: "#f87171" }}>{error}</p>}
          <div style={{ display: "flex", gap: "12px", marginTop: "16px" }}>
            <button onClick={() => setStep(1)} style={btnStyle("#334155")}>← 戻る</button>
            <button onClick={handleSaveActions} disabled={loading} style={btnStyle("#3b82f6")}>
              {loading ? "保存中..." : "✅ ACTION確定"}
            </button>
          </div>
        </div>
      )}

      {/* Step 3: 完了 */}
      {step === 3 && (
        <div style={{ ...cardStyle, textAlign: "center" }}>
          <p style={{ fontSize: "48px", margin: "0 0 16px" }}>✅</p>
          <h2 style={{ margin: "0 0 8px" }}>登録完了</h2>
          <p style={{ color: "#94a3b8", margin: "0 0 24px" }}>
            {items.filter(i => i.selectedAction === "CREATE_ISSUE").length}件の課題が自動作成されました
          </p>
          <div style={{ display: "flex", gap: "12px", justifyContent: "center" }}>
            <button onClick={() => { setStep(1); setRawText(""); setItems([]); }} style={btnStyle("#334155")}>
              続けて登録
            </button>
            <button onClick={() => navigate("/issues")} style={btnStyle("#3b82f6")}>
              課題一覧へ
            </button>
          </div>
        </div>
      )}
    </Layout>
  );
}

const cardStyle: React.CSSProperties = {
  background: "#1e293b", borderRadius: "12px", padding: "24px", maxWidth: "900px"
};
const inputStyle: React.CSSProperties = {
  width: "100%", padding: "10px 12px", background: "#0f172a", color: "#f1f5f9",
  border: "1px solid #334155", borderRadius: "8px", fontSize: "14px",
  boxSizing: "border-box", fontFamily: "inherit",
};
const selectStyle: React.CSSProperties = {
  padding: "8px 12px", background: "#334155", color: "#f1f5f9",
  border: "none", borderRadius: "6px", fontSize: "13px", cursor: "pointer",
};
const btnStyle = (bg: string): React.CSSProperties => ({
  padding: "10px 24px", background: bg, color: "#fff", border: "none",
  borderRadius: "8px", cursor: "pointer", fontSize: "14px", fontWeight: "600",
});
