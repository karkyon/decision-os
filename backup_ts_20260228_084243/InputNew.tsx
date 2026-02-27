import { useState } from "react";
import { useNavigate } from "react-router-dom";
import Layout from "../components/Layout";
import { inputApi, analyzeApi, itemApi, actionApi } from "../api/client";
import {
  INTENT_LABELS, DOMAIN_LABELS, ACTION_LABELS,
  IntentCode, DomainCode, ActionType,
} from "../types/index";

const INTENT_OPTIONS = Object.entries(INTENT_LABELS) as [IntentCode, string][];
const DOMAIN_OPTIONS = Object.entries(DOMAIN_LABELS) as [DomainCode, string][];
const ACTION_OPTIONS = Object.entries(ACTION_LABELS) as [ActionType, string][];

interface ItemWithAction {
  id: string;
  text: string;
  intent_code: IntentCode;
  domain_code: DomainCode;
  confidence: number;
  position: number;
  selectedAction: ActionType;
  reason: string;
  // 編集用
  isEditing: boolean;
  editText: string;
}

const confidenceColor = (c: number) =>
  c >= 0.75 ? "#22c55e" : c >= 0.5 ? "#f59e0b" : "#ef4444";

export default function InputNew() {
  const navigate = useNavigate();
  const [step, setStep] = useState(1);
  const [text, setText] = useState("");
  const [sourceType, setSourceType] = useState("email");
  const [items, setItems] = useState<ItemWithAction[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState("");
  const [createdIssueCount, setCreatedIssueCount] = useState(0);

  // ─── STEP1: 原文登録 → 分解実行 ─────────────────────────────
  const handleAnalyze = async () => {
    if (!text.trim()) { setError("テキストを入力してください"); return; }
    setLoading(true); setError("");
    try {
      // 1. INPUT 登録
      const inpRes = await inputApi.create({ text, source_type: sourceType });
      const newInputId: string = inpRes.data.id;

      // 2. 分解実行
      const anaRes = await analyzeApi.analyze(newInputId);
      const rawItems: any[] = anaRes.data;

      setItems(rawItems.map((it: any) => ({
        ...it,
        // ★ BUG・REQ はデフォルト CREATE_ISSUE, それ以外は STORE
        selectedAction: (it.intent_code === "BUG" || it.intent_code === "REQ")
          ? "CREATE_ISSUE"
          : "STORE",
        reason: "",
        isEditing: false,
        editText: it.text,
      })));
      setStep(2);
    } catch (e: any) {
      setError(e.response?.data?.detail || "分解に失敗しました");
    } finally { setLoading(false); }
  };

  // ─── STEP2: 分類変更 ──────────────────────────────────────────
  const updateItemField = (id: string, field: keyof ItemWithAction, value: any) => {
    setItems(prev => prev.map(it => it.id === id ? { ...it, [field]: value } : it));
  };

  // テキスト編集確定（PATCH API）
  const commitTextEdit = async (item: ItemWithAction) => {
    try {
      await itemApi.update(item.id, { text: item.editText });
      setItems(prev => prev.map(it =>
        it.id === item.id ? { ...it, text: it.editText, isEditing: false } : it
      ));
    } catch {
      setError("テキスト更新に失敗しました");
    }
  };

  // ITEM 削除（DELETE API）
  const deleteItem = async (id: string) => {
    if (!window.confirm("このITEMを削除しますか？")) return;
    try {
      await itemApi.delete(id);
      setItems(prev => prev.filter(it => it.id !== id));
    } catch {
      setError("削除に失敗しました");
    }
  };

  // 分類修正を保存（PATCH）
  const saveItemCorrection = async (item: ItemWithAction) => {
    try {
      await itemApi.update(item.id, {
        intent_code: item.intent_code,
        domain_code: item.domain_code,
      });
    } catch { /* silent */ }
  };

  // ─── STEP3: ACTION 確定 ──────────────────────────────────────
  const handleSaveActions = async () => {
    setLoading(true); setError("");
    let issueCount = 0;
    try {
      for (const item of items) {
        if (!item.selectedAction) continue;
        const res = await actionApi.create({
          item_id: item.id,
          action_type: item.selectedAction,
          decision_reason: item.reason || "",
        });
        if (item.selectedAction === "CREATE_ISSUE") issueCount++;
        // 409 (Action already exists) は無視して続行
        void res;
      }
      setCreatedIssueCount(issueCount);
      setStep(3);
    } catch (e: any) {
      const status = e.response?.status;
      if (status === 409) {
        // 一部が重複登録済みでも続行
        setCreatedIssueCount(issueCount);
        setStep(3);
      } else {
        setError(e.response?.data?.detail || "Action保存に失敗しました");
      }
    } finally { setLoading(false); }
  };

  // ─── Render ──────────────────────────────────────────────────
  return (
    <Layout>
      {/* ステップインジケーター */}
      <div style={{ display: "flex", gap: "8px", marginBottom: "24px", alignItems: "center" }}>
        {["1. 原文入力", "2. 分類確認・修正", "3. ACTION決定"].map((s, i) => (
          <div key={s} style={{ display: "flex", alignItems: "center", gap: "8px" }}>
            <div style={{
              padding: "6px 16px", borderRadius: "20px", fontSize: "13px",
              background: step === i + 1 ? "#3b82f6" : step > i + 1 ? "#22c55e" : "#334155",
              color: "#fff",
            }}>
              {step > i + 1 ? "✓ " : ""}{s}
            </div>
            {i < 2 && <span style={{ color: "#475569" }}>›</span>}
          </div>
        ))}
      </div>

      {error && (
        <div style={{
          background: "#fef2f2", border: "1px solid #fca5a5", borderRadius: "8px",
          padding: "12px 16px", marginBottom: "16px", color: "#dc2626", fontSize: "14px",
        }}>
          ⚠️ {error}
        </div>
      )}

      {/* ─── STEP 1 ─── */}
      {step === 1 && (
        <div style={{ background: "#1e293b", borderRadius: "12px", padding: "24px" }}>
          <h2 style={{ margin: "0 0 20px", fontSize: "18px" }}>📥 原文入力</h2>

          <label style={{ display: "block", marginBottom: "8px", fontSize: "14px", color: "#94a3b8" }}>
            ソース種別
          </label>
          <select
            value={sourceType}
            onChange={e => setSourceType(e.target.value)}
            style={{
              width: "200px", padding: "8px 12px", borderRadius: "8px",
              background: "#0f172a", border: "1px solid #334155",
              color: "#e2e8f0", fontSize: "14px", marginBottom: "16px",
            }}
          >
            {["email", "chat", "meeting", "ticket", "other"].map(s => (
              <option key={s} value={s}>{s}</option>
            ))}
          </select>

          <label style={{ display: "block", marginBottom: "8px", fontSize: "14px", color: "#94a3b8" }}>
            原文テキスト
          </label>
          <textarea
            value={text}
            onChange={e => setText(e.target.value)}
            placeholder="要望・不具合報告・ミーティングメモなどを貼り付けてください"
            style={{
              width: "100%", minHeight: "160px", padding: "12px",
              background: "#0f172a", border: "1px solid #334155",
              borderRadius: "8px", color: "#e2e8f0", fontSize: "14px",
              resize: "vertical", boxSizing: "border-box",
            }}
          />

          <button
            onClick={handleAnalyze}
            disabled={loading || !text.trim()}
            style={{
              marginTop: "16px", padding: "12px 32px", borderRadius: "8px",
              background: loading || !text.trim() ? "#334155" : "#3b82f6",
              color: "#fff", border: "none", cursor: loading || !text.trim() ? "not-allowed" : "pointer",
              fontSize: "15px", fontWeight: "600",
            }}
          >
            {loading ? "🔄 解析中..." : "🔍 解析する"}
          </button>
        </div>
      )}

      {/* ─── STEP 2 ─── */}
      {step === 2 && (
        <div style={{ background: "#1e293b", borderRadius: "12px", padding: "24px" }}>
          <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: "20px" }}>
            <h2 style={{ margin: 0, fontSize: "18px" }}>
              🧩 分解結果確認・修正
              <span style={{ marginLeft: "8px", fontSize: "13px", color: "#94a3b8" }}>
                {items.length}件
              </span>
            </h2>
            <button
              onClick={() => { setStep(1); setItems([]); setText(""); }}
              style={{
                padding: "6px 14px", borderRadius: "6px",
                background: "#334155", color: "#94a3b8", border: "none", cursor: "pointer", fontSize: "13px",
              }}
            >
              ← 原文に戻る
            </button>
          </div>

          {items.length === 0 && (
            <p style={{ color: "#64748b", textAlign: "center", padding: "32px 0" }}>
              分解結果がありません
            </p>
          )}

          <div style={{ display: "flex", flexDirection: "column", gap: "12px" }}>
            {items.map(item => (
              <div
                key={item.id}
                style={{
                  background: "#0f172a", borderRadius: "10px", padding: "16px",
                  border: "1px solid #334155",
                }}
              >
                {/* テキスト行 */}
                <div style={{ display: "flex", alignItems: "flex-start", gap: "8px", marginBottom: "10px" }}>
                  {item.isEditing ? (
                    <>
                      <textarea
                        value={item.editText}
                        onChange={e => updateItemField(item.id, "editText", e.target.value)}
                        style={{
                          flex: 1, padding: "6px 10px", borderRadius: "6px",
                          background: "#1e293b", border: "1px solid #3b82f6",
                          color: "#e2e8f0", fontSize: "14px", resize: "vertical", minHeight: "60px",
                        }}
                      />
                      <div style={{ display: "flex", gap: "4px", flexShrink: 0 }}>
                        <button
                          onClick={() => commitTextEdit(item)}
                          style={btnStyle("#22c55e")}
                          title="保存"
                        >✓</button>
                        <button
                          onClick={() => updateItemField(item.id, "isEditing", false)}
                          style={btnStyle("#475569")}
                          title="キャンセル"
                        >✕</button>
                      </div>
                    </>
                  ) : (
                    <>
                      <p style={{
                        flex: 1, margin: 0, color: "#e2e8f0", fontSize: "14px", lineHeight: "1.5",
                      }}>
                        {item.text}
                      </p>
                      <div style={{ display: "flex", gap: "4px", flexShrink: 0 }}>
                        <button
                          onClick={() => updateItemField(item.id, "isEditing", true)}
                          style={btnStyle("#3b82f6")}
                          title="テキスト編集"
                        >✏️</button>
                        <button
                          onClick={() => deleteItem(item.id)}
                          style={btnStyle("#ef4444")}
                          title="このITEMを削除"
                        >🗑</button>
                      </div>
                    </>
                  )}
                </div>

                {/* ドロップダウン行 */}
                <div style={{ display: "flex", gap: "8px", flexWrap: "wrap", alignItems: "center" }}>
                  {/* 信頼度 */}
                  <span style={{
                    fontSize: "12px", padding: "3px 8px", borderRadius: "4px",
                    background: "#1e293b", color: confidenceColor(item.confidence),
                    border: `1px solid ${confidenceColor(item.confidence)}`,
                    flexShrink: 0,
                  }}>
                    {Math.round(item.confidence * 100)}%
                  </span>

                  {/* Intent */}
                  <select
                    value={item.intent_code}
                    onChange={e => {
                      updateItemField(item.id, "intent_code", e.target.value);
                      saveItemCorrection({ ...item, intent_code: e.target.value as IntentCode });
                    }}
                    style={selectStyle}
                  >
                    {INTENT_OPTIONS.map(([v, l]) => <option key={v} value={v}>{l}</option>)}
                  </select>

                  {/* Domain */}
                  <select
                    value={item.domain_code}
                    onChange={e => {
                      updateItemField(item.id, "domain_code", e.target.value);
                      saveItemCorrection({ ...item, domain_code: e.target.value as DomainCode });
                    }}
                    style={selectStyle}
                  >
                    {DOMAIN_OPTIONS.map(([v, l]) => <option key={v} value={v}>{l}</option>)}
                  </select>

                  {/* Action */}
                  <select
                    value={item.selectedAction}
                    onChange={e => updateItemField(item.id, "selectedAction", e.target.value)}
                    style={{
                      ...selectStyle,
                      background: item.selectedAction === "CREATE_ISSUE" ? "#1e3a5f" : "#1e293b",
                      borderColor: item.selectedAction === "CREATE_ISSUE" ? "#3b82f6" : "#334155",
                    }}
                  >
                    {ACTION_OPTIONS.map(([v, l]) => <option key={v} value={v}>{l}</option>)}
                  </select>
                </div>

                {/* 判断理由 */}
                <input
                  value={item.reason}
                  onChange={e => updateItemField(item.id, "reason", e.target.value)}
                  placeholder="判断理由（任意）"
                  style={{
                    marginTop: "8px", width: "100%", padding: "6px 10px",
                    background: "#1e293b", border: "1px solid #334155",
                    borderRadius: "6px", color: "#e2e8f0", fontSize: "13px",
                    boxSizing: "border-box",
                  }}
                />
              </div>
            ))}
          </div>

          <button
            onClick={handleSaveActions}
            disabled={loading || items.length === 0}
            style={{
              marginTop: "20px", padding: "12px 32px", borderRadius: "8px",
              background: loading || items.length === 0 ? "#334155" : "#3b82f6",
              color: "#fff", border: "none",
              cursor: loading || items.length === 0 ? "not-allowed" : "pointer",
              fontSize: "15px", fontWeight: "600",
            }}
          >
            {loading ? "🔄 保存中..." : "✅ ACTION確定・課題化する"}
          </button>
        </div>
      )}

      {/* ─── STEP 3: 完了 ─── */}
      {step === 3 && (
        <div style={{
          background: "#1e293b", borderRadius: "12px", padding: "40px",
          textAlign: "center",
        }}>
          <div style={{ fontSize: "48px", marginBottom: "16px" }}>🎉</div>
          <h2 style={{ margin: "0 0 12px", fontSize: "22px" }}>登録完了！</h2>

          {createdIssueCount > 0 ? (
            <p style={{ color: "#94a3b8", marginBottom: "24px" }}>
              <span style={{ color: "#22c55e", fontWeight: "700", fontSize: "18px" }}>
                {createdIssueCount}件の課題
              </span>
              が自動生成されました。
            </p>
          ) : (
            <p style={{ color: "#94a3b8", marginBottom: "24px" }}>
              ACTIONを保存しました。課題化されていないITEMは後から対応できます。
            </p>
          )}

          <div style={{ display: "flex", gap: "12px", justifyContent: "center" }}>
            <button
              onClick={() => navigate("/issues")}
              style={{
                padding: "12px 28px", borderRadius: "8px",
                background: "#3b82f6", color: "#fff", border: "none",
                cursor: "pointer", fontSize: "15px", fontWeight: "600",
              }}
            >
              📋 課題一覧を確認
            </button>
            <button
              style={{
                padding: "12px 28px", borderRadius: "8px",
                background: "#334155", color: "#e2e8f0", border: "none",
                cursor: "pointer", fontSize: "15px",
              }}
            >
              ＋ 新規登録
            </button>
          </div>
        </div>
      )}
    </Layout>
  );
}

const selectStyle: React.CSSProperties = {
  padding: "5px 10px", borderRadius: "6px",
  background: "#1e293b", border: "1px solid #334155",
  color: "#e2e8f0", fontSize: "13px", cursor: "pointer",
};

const btnStyle = (bg: string): React.CSSProperties => ({
  padding: "4px 8px", borderRadius: "6px",
  background: bg, color: "#fff", border: "none",
  cursor: "pointer", fontSize: "14px", lineHeight: "1",
});
