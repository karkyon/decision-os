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
