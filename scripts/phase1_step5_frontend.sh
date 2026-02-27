#!/bin/bash
# ============================================================
# Phase 1 MVP - Step 5: フロントエンド実装
# - ログイン画面
# - ダッシュボード
# - 要望登録・分解画面（最重要）
# - 課題一覧・詳細
# - トレーサビリティ画面
# ============================================================
set -e

PROJECT="$HOME/projects/decision-os"
FRONTEND="$PROJECT/frontend"
SRC="$FRONTEND/src"

echo "=== Step 5: フロントエンド実装 ==="

cd "$FRONTEND"
npm install react-router-dom axios @tanstack/react-query --save --legacy-peer-deps 2>/dev/null || true

mkdir -p "$SRC/pages" "$SRC/components" "$SRC/hooks" "$SRC/api" "$SRC/types" "$SRC/store"

# ---- 型定義 ----
cat > "$SRC/types/index.ts" << 'EOF'
export interface User {
  id: string;
  name: string;
  email: string;
  role: "admin" | "pm" | "dev" | "viewer";
}

export interface Project {
  id: string;
  name: string;
  description?: string;
  status: string;
}

export interface Input {
  id: string;
  project_id: string;
  source_type: string;
  raw_text: string;
  summary?: string;
  importance?: string;
  created_at: string;
}

export interface Item {
  id: string;
  input_id: string;
  text: string;
  intent_code: IntentCode;
  domain_code: DomainCode;
  confidence: number;
  position: number;
  is_corrected?: string;
  created_at: string;
}

export interface Action {
  id: string;
  item_id: string;
  action_type: ActionType;
  decision_reason?: string;
  decided_at: string;
}

export interface Issue {
  id: string;
  project_id: string;
  action_id?: string;
  title: string;
  description?: string;
  status: IssueStatus;
  priority: Priority;
  assignee_id?: string;
  labels?: string;
  created_at: string;
  updated_at?: string;
}

export type IntentCode = "BUG" | "REQ" | "IMP" | "QST" | "MIS" | "FBK" | "INF" | "TSK";
export type DomainCode = "UI" | "API" | "DB" | "AUTH" | "PERF" | "SEC" | "OPS" | "SPEC";
export type ActionType = "CREATE_ISSUE" | "ANSWER" | "STORE" | "REJECT" | "HOLD" | "LINK_EXISTING";
export type IssueStatus = "open" | "doing" | "review" | "done" | "hold";
export type Priority = "low" | "medium" | "high" | "critical";

export const INTENT_LABELS: Record<IntentCode, string> = {
  BUG: "🐛 不具合", REQ: "✨ 要望", IMP: "🔧 改善",
  QST: "❓ 質問", MIS: "⚠️ 認識相違", FBK: "👍 評価",
  INF: "📋 情報", TSK: "📌 タスク",
};

export const DOMAIN_LABELS: Record<DomainCode, string> = {
  UI: "画面", API: "API", DB: "DB", AUTH: "認証",
  PERF: "性能", SEC: "セキュリティ", OPS: "運用", SPEC: "仕様",
};

export const ACTION_LABELS: Record<ActionType, string> = {
  CREATE_ISSUE: "📋 課題化", ANSWER: "💬 回答", STORE: "📁 保存",
  REJECT: "❌ 却下", HOLD: "⏸ 保留", LINK_EXISTING: "🔗 既存紐付",
};

export const STATUS_LABELS: Record<IssueStatus, string> = {
  open: "未着手", doing: "作業中", review: "レビュー", done: "完了", hold: "保留",
};

export const PRIORITY_COLORS: Record<Priority, string> = {
  low: "#94a3b8", medium: "#3b82f6", high: "#f59e0b", critical: "#ef4444",
};
EOF

# ---- APIクライアント ----
cat > "$SRC/api/client.ts" << 'EOF'
import axios from "axios";

const API_BASE = "/api/v1";

const client = axios.create({ baseURL: API_BASE });

client.interceptors.request.use((config) => {
  const token = localStorage.getItem("token");
  if (token) config.headers.Authorization = `Bearer ${token}`;
  return config;
});

client.interceptors.response.use(
  (res) => res,
  (err) => {
    if (err.response?.status === 401) {
      localStorage.removeItem("token");
      window.location.href = "/login";
    }
    return Promise.reject(err);
  }
);

export default client;

// Auth
export const authApi = {
  register: (data: { name: string; email: string; password: string; role?: string }) =>
    client.post("/auth/register", data),
  login: (data: { email: string; password: string }) =>
    client.post("/auth/login", data),
};

// Projects
export const projectApi = {
  list: () => client.get("/projects"),
  create: (data: { name: string; description?: string }) => client.post("/projects", data),
};

// Inputs
export const inputApi = {
  create: (data: any) => client.post("/inputs", data),
  get: (id: string) => client.get(`/inputs/${id}`),
  list: (projectId: string) => client.get(`/inputs?project_id=${projectId}`),
};

// Analyze
export const analyzeApi = {
  analyze: (inputId: string) => client.post("/analyze", { input_id: inputId }),
};

// Items
export const itemApi = {
  update: (id: string, data: any) => client.patch(`/items/${id}`, data),
};

// Actions
export const actionApi = {
  create: (data: any) => client.post("/actions", data),
};

// Issues
export const issueApi = {
  list: (projectId: string, params?: any) =>
    client.get(`/issues?project_id=${projectId}`, { params }),
  get: (id: string) => client.get(`/issues/${id}`),
  create: (data: any) => client.post("/issues", data),
  update: (id: string, data: any) => client.patch(`/issues/${id}`, data),
};

// Trace
export const traceApi = {
  get: (issueId: string) => client.get(`/trace/${issueId}`),
};
EOF

# ---- 認証ストア（シンプルなlocalStorage）----
cat > "$SRC/store/auth.ts" << 'EOF'
export const authStore = {
  getToken: () => localStorage.getItem("token"),
  setToken: (token: string) => localStorage.setItem("token", token),
  getUser: () => {
    const u = localStorage.getItem("user");
    return u ? JSON.parse(u) : null;
  },
  setUser: (user: any) => localStorage.setItem("user", JSON.stringify(user)),
  clear: () => {
    localStorage.removeItem("token");
    localStorage.removeItem("user");
  },
  isLoggedIn: () => !!localStorage.getItem("token"),
};
EOF

# ---- ログイン画面 ----
cat > "$SRC/pages/Login.tsx" << 'EOF'
import { useState } from "react";
import { useNavigate } from "react-router-dom";
import { authApi } from "../api/client";
import { authStore } from "../store/auth";

export default function Login() {
  const navigate = useNavigate();
  const [email, setEmail] = useState("demo@example.com");
  const [password, setPassword] = useState("demo1234");
  const [error, setError] = useState("");
  const [loading, setLoading] = useState(false);
  const [isRegister, setIsRegister] = useState(false);
  const [name, setName] = useState("デモユーザー");

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setLoading(true);
    setError("");
    try {
      let res;
      if (isRegister) {
        res = await authApi.register({ name, email, password, role: "pm" });
      } else {
        res = await authApi.login({ email, password });
      }
      const { access_token, user_id, name: userName, role } = res.data;
      authStore.setToken(access_token);
      authStore.setUser({ id: user_id, name: userName, role });
      navigate("/");
    } catch (err: any) {
      setError(err.response?.data?.detail || "ログインに失敗しました");
    } finally {
      setLoading(false);
    }
  };

  return (
    <div style={styles.container}>
      <div style={styles.card}>
        <h1 style={styles.logo}>⚖️ decision-os</h1>
        <p style={styles.subtitle}>開発判断OS — 意思決定の透明化</p>
        <form onSubmit={handleSubmit} style={styles.form}>
          {isRegister && (
            <input style={styles.input} type="text" placeholder="名前" value={name}
              onChange={(e) => setName(e.target.value)} required />
          )}
          <input style={styles.input} type="email" placeholder="メールアドレス" value={email}
            onChange={(e) => setEmail(e.target.value)} required />
          <input style={styles.input} type="password" placeholder="パスワード" value={password}
            onChange={(e) => setPassword(e.target.value)} required />
          {error && <p style={styles.error}>{error}</p>}
          <button style={styles.button} type="submit" disabled={loading}>
            {loading ? "処理中..." : isRegister ? "新規登録" : "ログイン"}
          </button>
        </form>
        <button style={styles.link} onClick={() => setIsRegister(!isRegister)}>
          {isRegister ? "ログインはこちら" : "新規登録はこちら"}
        </button>
      </div>
    </div>
  );
}

const styles: Record<string, React.CSSProperties> = {
  container: { display: "flex", alignItems: "center", justifyContent: "center",
    minHeight: "100vh", background: "#0f172a" },
  card: { background: "#1e293b", padding: "40px", borderRadius: "12px",
    width: "100%", maxWidth: "380px", boxShadow: "0 20px 60px rgba(0,0,0,0.5)" },
  logo: { color: "#f1f5f9", fontSize: "28px", textAlign: "center", margin: "0 0 8px" },
  subtitle: { color: "#94a3b8", textAlign: "center", margin: "0 0 32px", fontSize: "14px" },
  form: { display: "flex", flexDirection: "column", gap: "12px" },
  input: { padding: "12px", borderRadius: "8px", border: "1px solid #334155",
    background: "#0f172a", color: "#f1f5f9", fontSize: "14px", outline: "none" },
  button: { padding: "12px", borderRadius: "8px", background: "#3b82f6", color: "#fff",
    border: "none", fontSize: "15px", cursor: "pointer", fontWeight: "600" },
  error: { color: "#f87171", fontSize: "13px", margin: "0" },
  link: { marginTop: "16px", background: "none", border: "none", color: "#60a5fa",
    cursor: "pointer", width: "100%", textAlign: "center", fontSize: "13px" },
};
EOF

# ---- レイアウト（サイドバー）----
cat > "$SRC/components/Layout.tsx" << 'EOF'
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
EOF

# ---- ダッシュボード ----
cat > "$SRC/pages/Dashboard.tsx" << 'EOF'
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
EOF

# ---- 要望登録・分解画面（最重要）----
cat > "$SRC/pages/InputNew.tsx" << 'EOF'
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
  const [inputId, setInputId] = useState("");
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
      setInputId(inpRes.data.id);
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
EOF

# ---- 課題一覧画面 ----
cat > "$SRC/pages/IssueList.tsx" << 'EOF'
import { useEffect, useState } from "react";
import { useNavigate } from "react-router-dom";
import Layout from "../components/Layout";
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
    projectApi.list().then(r => {
      setProjects(r.data);
      if (r.data.length > 0) setProjectId(r.data[0].id);
    });
  }, []);

  useEffect(() => {
    if (!projectId) return;
    setLoading(true);
    issueApi.list(projectId, filterStatus ? { status: filterStatus } : {})
      .then(r => setIssues(r.data))
      .finally(() => setLoading(false));
  }, [projectId, filterStatus]);

  return (
    <Layout>
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
                  <p style={{ margin: "0 0 4px", fontSize: "15px", fontWeight: "500" }}>{issue.title}</p>
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
    </Layout>
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
EOF

# ---- 課題詳細 + トレーサビリティ ----
cat > "$SRC/pages/IssueDetail.tsx" << 'EOF'
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
EOF

# ---- App.tsx（ルーティング）----
cat > "$SRC/App.tsx" << 'EOF'
import { BrowserRouter, Routes, Route, Navigate } from "react-router-dom";
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
    <BrowserRouter>
      <Routes>
        <Route path="/login" element={<Login />} />
        <Route path="/" element={<PrivateRoute><Dashboard /></PrivateRoute>} />
        <Route path="/inputs/new" element={<PrivateRoute><InputNew /></PrivateRoute>} />
        <Route path="/issues" element={<PrivateRoute><IssueList /></PrivateRoute>} />
        <Route path="/issues/:id" element={<PrivateRoute><IssueDetail /></PrivateRoute>} />
        <Route path="*" element={<Navigate to="/" replace />} />
      </Routes>
    </BrowserRouter>
  );
}
EOF

# ---- グローバルCSS ----
cat > "$SRC/index.css" << 'EOF'
*, *::before, *::after { box-sizing: border-box; }
body {
  margin: 0; padding: 0;
  font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Noto Sans JP", sans-serif;
  background: #0f172a; color: #f1f5f9;
}
select option { background: #1e293b; }
::-webkit-scrollbar { width: 8px; }
::-webkit-scrollbar-track { background: #0f172a; }
::-webkit-scrollbar-thumb { background: #334155; border-radius: 4px; }
EOF

echo "✅ フロントエンド生成完了"

# ---- フロント依存確認・ビルドテスト ----
cd "$FRONTEND"
npm run build 2>&1 | tail -20 || echo "⚠️ ビルドエラーが出た場合は確認してください"

echo "✅✅✅ Step 5 完了: フロントエンド全画面実装"
echo ""
echo "=== Phase 1 MVP 実装完了 ==="
echo "アクセス: http://localhost:8888"
