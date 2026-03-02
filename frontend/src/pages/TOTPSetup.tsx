import React, { useState } from "react";
import { useNavigate } from "react-router-dom";
import axios from "axios";

type SetupData = { secret: string; otpauth_uri: string; qr_base64: string };

const btn: React.CSSProperties = {
  width: "100%", padding: "12px", background: "#4f46e5", color: "#fff",
  border: "none", borderRadius: "8px", fontSize: "14px", fontWeight: 600, cursor: "pointer",
};

export default function TOTPSetup() {
  const navigate = useNavigate();
  const [step, setStep] = useState<"idle"|"scan"|"verify"|"done">("idle");
  const [data, setData] = useState<SetupData | null>(null);
  const [code, setCode] = useState("");
  const [err, setErr]   = useState("");
  const [loading, setLoading] = useState(false);

  const token = localStorage.getItem("access_token") ?? sessionStorage.getItem("token") ?? "";
  const headers = { Authorization: `Bearer ${token}` };

  const setup = async () => {
    setLoading(true); setErr("");
    try {
      const res = await axios.post<SetupData>(
        "http://localhost:8089/api/v1/auth/totp/setup", {}, { headers }
      );
      setData(res.data); setStep("scan");
    } catch (e: any) { setErr(e.response?.data?.detail ?? "エラーが発生しました"); }
    finally { setLoading(false); }
  };

  const verify = async () => {
    if (code.length !== 6) { setErr("6桁のコードを入力してください"); return; }
    setLoading(true); setErr("");
    try {
      await axios.post("http://localhost:8089/api/v1/auth/totp/verify", { code }, { headers });
      setStep("done");
    } catch (e: any) { setErr(e.response?.data?.detail ?? "コードが正しくありません"); }
    finally { setLoading(false); }
  };

  const wrap: React.CSSProperties = {
    maxWidth: 420, margin: "60px auto", padding: "32px",
    background: "#fff", borderRadius: "12px",
    boxShadow: "0 4px 24px rgba(0,0,0,0.08)", fontFamily: "Arial,sans-serif",
  };

  return (
    <div style={wrap}>
      <h2 style={{ margin: "0 0 8px", fontSize: "20px" }}>🔐 2要素認証（2FA）</h2>
      <p style={{ color: "#6b7280", fontSize: "14px", margin: "0 0 24px" }}>
        Authenticator アプリでログインを保護します
      </p>

      {step === "idle" && (
        <button onClick={setup} disabled={loading} style={btn}>
          {loading ? "準備中..." : "2FA を有効にする"}
        </button>
      )}

      {step === "scan" && data && (
        <>
          <p style={{ fontSize: "14px", marginBottom: "16px" }}>
            Authenticator アプリで QR コードをスキャンしてください。
          </p>
          <div style={{ textAlign: "center", marginBottom: "16px" }}>
            <img
              src={`data:image/png;base64,${data.qr_base64}`}
              alt="QR Code" style={{ width: 200, height: 200, border: "1px solid #e5e7eb", borderRadius: 8 }}
            />
          </div>
          <details style={{ marginBottom: "20px" }}>
            <summary style={{ fontSize: "12px", color: "#9ca3af", cursor: "pointer" }}>
              手動入力する場合
            </summary>
            <code style={{ display: "block", marginTop: 8, padding: 8, background: "#f9fafb",
              borderRadius: 6, fontSize: 13, wordBreak: "break-all", letterSpacing: 2 }}>
              {data.secret}
            </code>
          </details>
          <button onClick={() => setStep("verify")} style={btn}>
            スキャンしました → コードを入力
          </button>
        </>
      )}

      {step === "verify" && (
        <>
          <p style={{ fontSize: "14px", marginBottom: "12px" }}>
            Authenticator に表示されている 6 桁のコードを入力してください。
          </p>
          <input
            type="text" inputMode="numeric" maxLength={6} placeholder="123456"
            value={code} onChange={e => setCode(e.target.value.replace(/\D/g, ""))} autoFocus
            style={{ width: "100%", padding: "12px", border: "1px solid #d1d5db",
              borderRadius: 8, fontSize: 24, textAlign: "center", letterSpacing: 6,
              boxSizing: "border-box" }}
          />
          {err && <p style={{ color: "#ef4444", fontSize: 13, margin: "8px 0 0" }}>{err}</p>}
          <button onClick={verify} disabled={loading || code.length !== 6}
            style={{ ...btn, marginTop: 16, opacity: code.length === 6 ? 1 : 0.5 }}>
            {loading ? "確認中..." : "コードを確認して有効化"}
          </button>
        </>
      )}

      {step === "done" && (
        <div style={{ textAlign: "center" }}>
          <div style={{ fontSize: 48, marginBottom: 12 }}>✅</div>
          <p style={{ fontSize: 16, fontWeight: 600, color: "#065f46" }}>2FA が有効になりました</p>
          <p style={{ fontSize: 13, color: "#6b7280", margin: "8px 0 20px" }}>
            次回ログインから Authenticator コードが必要になります。
          </p>
          <button onClick={() => navigate(-1)} style={btn}>戻る</button>
        </div>
      )}

      {err && step !== "verify" && (
        <p style={{ color: "#ef4444", fontSize: 13, marginTop: 12 }}>{err}</p>
      )}
    </div>
  );
}
