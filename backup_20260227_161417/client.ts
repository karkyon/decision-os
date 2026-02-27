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
