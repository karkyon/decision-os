import axios from "axios";

const API_BASE = "/api/v1";

const client = axios.create({ baseURL: API_BASE });

client.interceptors.request.use((config) => {
  // "token" と "access_token" 両方に対応
  const token = localStorage.getItem("token") ?? localStorage.getItem("access_token");
  if (token) config.headers.Authorization = `Bearer ${token}`;
  return config;
});

client.interceptors.response.use(
  (res) => res,
  (err) => {
    if (err.response?.status === 401) {
      localStorage.removeItem("token");
      localStorage.removeItem("access_token"); // こっちも消す
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
  trace: (inputId: string) => client.get(`/inputs/${inputId}/trace`),
};

// Analyze
export const analyzeApi = {
  analyze: (inputId: string) => client.post("/analyze", { input_id: inputId }),
};

// Items
export const itemApi = {
  update: (id: string, data: any) => client.patch(`/items/${id}`, data),
  delete: (id: string) => client.delete(`/items/${id}`),
};

// Actions
export const actionApi = {
  get: (id: string) => client.get(`/actions/${id}`),
  create: (data: any) => client.post("/actions", data),
};

// Issues
export const issueApi = {
  list: (params: {
    project_id?: string;
    status?: string;
    priority?: string;
    assignee_id?: string;
    intent_code?: string;
    label?: string;
    date_from?: string;
    date_to?: string;
    q?: string;
    sort?: string;
    limit?: number;
    offset?: number;
  } = {}) => {
    const p = new URLSearchParams();
    Object.entries(params).forEach(([k, v]) => { if (v !== undefined && v !== "") p.append(k, String(v)); });
    return client.get(`/issues${p.toString() ? "?" + p.toString() : ""}`);
  },
  get:    (id: string)               => client.get(`/issues/${id}`),
  create: (body: object)             => client.post("/issues", body),
  update: (id: string, body: object) => client.patch(`/issues/${id}`, body),

  children: (id: string) => client.get(`/issues/${id}/children`),
  tree:     (id: string) => client.get(`/issues/${id}/tree`),
};

// Trace
export const traceApi = {
  get: (issueId: string) => client.get(`/trace/${issueId}`),
};

// Conversations (コメント)
export const conversationApi = {
  list: (issueId: string) => client.get(`/conversations?issue_id=${issueId}`),
  create: (data: { issue_id: string; body: string }) => client.post("/conversations", data),
  update: (id: string, body: string) => client.patch(`/conversations/${id}`, { body }),
  delete: (id: string) => client.delete(`/conversations/${id}`),
};

// Search（横断全文検索）
export const searchApi = {
  search: (params: { q: string; type?: string; limit?: number }) =>
    client.get("/search", { params }),
};

// Decisions（決定ログ）
export const decisionApi = {
  list:   (params?: { project_id?: string; issue_id?: string; limit?: number }) =>
    client.get("/decisions", { params }),
  get:    (id: string) => client.get(`/decisions/${id}`),
  create: (data: {
    project_id: string;
    decision_text: string;
    reason: string;
    related_issue_id?: string;
    related_request_id?: string;
  }) => client.post("/decisions", data),
  delete: (id: string) => client.delete(`/decisions/${id}`),
};

export const labelApi = {
  list:    (q?: string, projectId?: string) => {
    const p = new URLSearchParams();
    if (q)         p.append("q", q);
    if (projectId) p.append("project_id", projectId);
    return client.get(`/labels${p.toString() ? "?" + p.toString() : ""}`);
  },
  suggest: (q: string, projectId?: string) => {
    const p = new URLSearchParams({ q });
    if (projectId) p.append("project_id", projectId);
    return client.get(`/labels/suggest?${p.toString()}`);
  },
  merge:   (fromLabel: string, toLabel: string, projectId?: string) =>
    client.post("/labels/merge", { from_label: fromLabel, to_label: toLabel, project_id: projectId }),
  delete:  (label: string, projectId?: string) => {
    const p = projectId ? `?project_id=${projectId}` : "";
    return client.delete(`/labels/${encodeURIComponent(label)}${p}`);
  },
};

