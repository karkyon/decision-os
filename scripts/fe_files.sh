#!/bin/bash
# FE ファイル直接配置（SSOButtons / TOTPSetup / TOTPLogin）
set -e

FE="$HOME/projects/decision-os/frontend/src"
GREEN='\033[0;32m'; CYAN='\033[0;36m'; NC='\033[0m'
ok()      { echo -e "${GREEN}✅ $1${NC}"; }
section() { echo -e "\n${CYAN}━━━ $1 ━━━${NC}"; }

section "FE ディレクトリ確認"
ls "$FE/pages/" | head -20
ls "$FE/components/" 2>/dev/null || echo "(componentsなし)"

# ─────────────────────────────────────────────
# SSOButtons.tsx
# ─────────────────────────────────────────────
section "SSOButtons.tsx 作成"
mkdir -p "$FE/components"

cat > "$FE/components/SSOButtons.tsx" << 'EOF'
import React from "react";

const API_BASE = (import.meta as any).env?.VITE_API_URL ?? "http://localhost:8089";

export function SSOButtons() {
  return (
    <div style={{ display: "flex", flexDirection: "column", gap: "12px", marginTop: "16px" }}>
      <div style={{ display: "flex", alignItems: "center", gap: "8px" }}>
        <hr style={{ flex: 1, border: "none", borderTop: "1px solid #e5e7eb" }} />
        <span style={{ fontSize: "12px", color: "#9ca3af" }}>または</span>
        <hr style={{ flex: 1, border: "none", borderTop: "1px solid #e5e7eb" }} />
      </div>

      {/* Google */}
      <button
        onClick={() => { window.location.href = `${API_BASE}/api/v1/auth/google`; }}
        style={{
          display: "flex", alignItems: "center", justifyContent: "center", gap: "10px",
          padding: "10px 16px", border: "1px solid #d1d5db", borderRadius: "8px",
          backgroundColor: "#fff", cursor: "pointer", fontSize: "14px", fontWeight: 500,
        }}
      >
        <svg width="18" height="18" viewBox="0 0 48 48">
          <path fill="#EA4335" d="M24 9.5c3.54 0 6.71 1.22 9.21 3.6l6.85-6.85C35.9 2.38 30.47 0 24 0 14.62 0 6.51 5.38 2.56 13.22l7.98 6.19C12.43 13.72 17.74 9.5 24 9.5z"/>
          <path fill="#4285F4" d="M46.98 24.55c0-1.57-.15-3.09-.38-4.55H24v9.02h12.94c-.58 2.96-2.26 5.48-4.78 7.18l7.73 6c4.51-4.18 7.09-10.36 7.09-17.65z"/>
          <path fill="#FBBC05" d="M10.53 28.59c-.48-1.45-.76-2.99-.76-4.59s.27-3.14.76-4.59l-7.98-6.19C.92 16.46 0 20.12 0 24c0 3.88.92 7.54 2.56 10.78l7.97-6.19z"/>
          <path fill="#34A853" d="M24 48c6.48 0 11.93-2.13 15.89-5.81l-7.73-6c-2.15 1.45-4.92 2.3-8.16 2.3-6.26 0-11.57-4.22-13.47-9.91l-7.98 6.19C6.51 42.62 14.62 48 24 48z"/>
        </svg>
        Google でログイン
      </button>

      {/* GitHub */}
      <button
        onClick={() => { window.location.href = `${API_BASE}/api/v1/auth/github`; }}
        style={{
          display: "flex", alignItems: "center", justifyContent: "center", gap: "10px",
          padding: "10px 16px", border: "none", borderRadius: "8px",
          backgroundColor: "#24292e", color: "#fff", cursor: "pointer",
          fontSize: "14px", fontWeight: 500,
        }}
      >
        <svg width="18" height="18" viewBox="0 0 16 16" fill="#fff">
          <path d="M8 0C3.58 0 0 3.58 0 8c0 3.54 2.29 6.53 5.47 7.59.4.07.55-.17.55-.38 0-.19-.01-.82-.01-1.49-2.01.37-2.53-.49-2.69-.94-.09-.23-.48-.94-.82-1.13-.28-.15-.68-.52-.01-.53.63-.01 1.08.58 1.23.82.72 1.21 1.87.87 2.33.66.07-.52.28-.87.51-1.07-1.78-.2-3.64-.89-3.64-3.95 0-.87.31-1.59.82-2.15-.08-.2-.36-1.02.08-2.12 0 0 .67-.21 2.2.82.64-.18 1.32-.27 2-.27.68 0 1.36.09 2 .27 1.53-1.04 2.2-.82 2.2-.82.44 1.1.16 1.92.08 2.12.51.56.82 1.27.82 2.15 0 3.07-1.87 3.75-3.65 3.95.29.25.54.73.54 1.48 0 1.07-.01 1.93-.01 2.2 0 .21.15.46.55.38A8.013 8.013 0 0016 8c0-4.42-3.58-8-8-8z"/>
        </svg>
        GitHub でログイン
      </button>
    </div>
  );
}
EOF
ok "SSOButtons.tsx 作成完了"

# ─────────────────────────────────────────────
# TOTPSetup.tsx
# ─────────────────────────────────────────────
section "TOTPSetup.tsx 作成"

cat > "$FE/pages/TOTPSetup.tsx" << 'EOF'
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
EOF
ok "TOTPSetup.tsx 作成完了"

# ─────────────────────────────────────────────
# TOTPLogin.tsx
# ─────────────────────────────────────────────
section "TOTPLogin.tsx 作成"

cat > "$FE/pages/TOTPLogin.tsx" << 'EOF'
import React, { useState } from "react";
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
EOF
ok "TOTPLogin.tsx 作成完了"

# ─────────────────────────────────────────────
# App.tsx にルート追加（まだなければ）
# ─────────────────────────────────────────────
section "App.tsx ルート確認・追加"

APP="$FE/App.tsx"
python3 - << 'PYEOF'
import re, os

app_path = os.path.expanduser("~/projects/decision-os/frontend/src/App.tsx")
with open(app_path) as f:
    src = f.read()

changed = False
for comp, filepath in [("TOTPSetup", "./pages/TOTPSetup"), ("TOTPLogin", "./pages/TOTPLogin")]:
    if f"import {comp}" not in src:
        src = re.sub(r"(import React[^\n]*\n)", r"\1" + f'import {comp} from "{filepath}";\n', src, count=1)
        changed = True
        print(f"import {comp} 追加")

for path_str, comp in [("/totp-setup", "TOTPSetup"), ("/totp-login", "TOTPLogin")]:
    if f'"{path_str}"' not in src:
        # 既存の /login Route の後に追加
        src = re.sub(
            r'(<Route[^/]*/login"[^/]*/?>)',
            r'\1\n          <Route path="' + path_str + '" element={<' + comp + ' />} />',
            src, count=1
        )
        changed = True
        print(f"Route {path_str} 追加")

if changed:
    with open(app_path, "w") as f:
        f.write(src)
    print("App.tsx 更新完了")
else:
    print("App.tsx: 変更不要（既存）")
PYEOF
ok "App.tsx 確認完了"

# ─────────────────────────────────────────────
# TS チェック
# ─────────────────────────────────────────────
section "TypeScript ビルドチェック"
cd "$HOME/projects/decision-os/frontend"
npx tsc --noEmit 2>&1 | tail -15
ok "TSチェック完了"

# ─────────────────────────────────────────────
# 最終確認
# ─────────────────────────────────────────────
section "最終確認"
for f in "src/components/SSOButtons.tsx" "src/pages/TOTPSetup.tsx" "src/pages/TOTPLogin.tsx"; do
  [[ -f "$HOME/projects/decision-os/frontend/$f" ]] && \
    echo -e "${GREEN}✅ $f${NC}" || \
    echo -e "${YELLOW}⚠️  $f が見つかりません${NC}"
done

echo ""
echo "ブラウザで確認:"
echo "  http://localhost:3008/login     → Google/GitHub ボタンが表示されること"
echo "  http://localhost:3008/totp-setup → 2FAセットアップ画面"
echo ""
ok "フロントエンド FE ファイル配置完了！"
