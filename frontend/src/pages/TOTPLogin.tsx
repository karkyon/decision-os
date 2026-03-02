import { useState } from "react";
import { useNavigate, useLocation } from "react-router-dom";
import axios from "axios";

export default function TOTPLogin() {
  const navigate  = useNavigate();
  const location  = useLocation();
  const { email, password } = (location.state as any) ?? {};
  const [code, setCode]     = useState("");
  const [err, setErr]       = useState("");
  const [loading, setLoading] = useState(false);

  if (!email || !password) { navigate("/login"); return null; }

  const submit = async () => {
    if (code.length !== 6) { setErr("6桁のコードを入力してください"); return; }
    setLoading(true); setErr("");
    try {
      const res = await axios.post<any>(
        "http://localhost:8089/api/v1/auth/totp/login",
        { email, password, totp_code: code }
      );
      // 既存の認証状態管理に合わせてトークン保存
      localStorage.setItem("access_token", res.data.access_token);
      navigate("/workspaces");
    } catch (e: any) { setErr(e.response?.data?.detail ?? "コードが正しくありません"); }
    finally { setLoading(false); }
  };

  return (
    <div style={{
      maxWidth: 380, margin: "80px auto", padding: "32px",
      background: "#fff", borderRadius: "12px",
      boxShadow: "0 4px 24px rgba(0,0,0,0.08)", fontFamily: "Arial,sans-serif",
    }}>
      <div style={{ textAlign: "center", marginBottom: 24 }}>
        <div style={{ fontSize: 36 }}>🔐</div>
        <h2 style={{ margin: "8px 0 4px", fontSize: 20 }}>2段階認証</h2>
        <p style={{ color: "#6b7280", fontSize: 13 }}>Authenticator の 6 桁コードを入力</p>
      </div>

      <input
        type="text" inputMode="numeric" maxLength={6} placeholder="000000"
        value={code} onChange={e => setCode(e.target.value.replace(/\D/g, ""))} autoFocus
        onKeyDown={e => e.key === "Enter" && submit()}
        style={{ width: "100%", padding: 14, border: "1px solid #d1d5db", borderRadius: 8,
          fontSize: 28, textAlign: "center", letterSpacing: 8, boxSizing: "border-box", marginBottom: 16 }}
      />

      {err && <p style={{ color: "#ef4444", fontSize: 13, textAlign: "center", margin: "0 0 12px" }}>{err}</p>}

      <button onClick={submit} disabled={loading || code.length !== 6}
        style={{
          width: "100%", padding: 12, border: "none", borderRadius: 8,
          background: code.length === 6 ? "#4f46e5" : "#e5e7eb",
          color: code.length === 6 ? "#fff" : "#9ca3af",
          fontSize: 14, fontWeight: 600,
          cursor: code.length === 6 ? "pointer" : "default",
        }}>
        {loading ? "確認中..." : "ログイン"}
      </button>

      <p style={{ textAlign: "center", marginTop: 16, fontSize: 12, color: "#9ca3af" }}>
        コードは 30 秒ごとに更新されます
      </p>
    </div>
  );
}
