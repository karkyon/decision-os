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
