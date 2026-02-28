#!/bin/bash
set -e
PROJECT_DIR=~/projects/decision-os
BACKEND_DIR=$PROJECT_DIR/backend
FRONTEND_DIR=$PROJECT_DIR/frontend
PAGES_DIR=$FRONTEND_DIR/src/pages

section() { echo ""; echo "========== $1 =========="; }
ok()      { echo "  ✅ $1"; }
info()    { echo "  [INFO] $1"; }
warn()    { echo "  ⚠️  $1"; }

# ============================================================
section "1. バックエンド起動確認"
# ============================================================
if curl -s http://localhost:8089/api/v1/health > /dev/null 2>&1 || \
   curl -s http://localhost:8089/docs > /dev/null 2>&1; then
  ok "バックエンド起動中"
else
  warn "バックエンドが起動していません。起動します..."
  cd $BACKEND_DIR
  source .venv/bin/activate
  pkill -f "uvicorn app.main" 2>/dev/null; sleep 1
  nohup uvicorn app.main:app --host 0.0.0.0 --port 8089 --reload \
    > $PROJECT_DIR/logs/backend.log 2>&1 &
  sleep 4
  ok "バックエンド起動完了"
fi

# ============================================================
section "2. デモアカウントでログイン & トークン取得"
# ============================================================
cd $BACKEND_DIR
source .venv/bin/activate 2>/dev/null || true

LOGIN_RESP=$(curl -s -X POST http://localhost:8089/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"demo@example.com","password":"demo1234"}')

TOKEN=$(echo $LOGIN_RESP | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('access_token',''))" 2>/dev/null)

if [ -z "$TOKEN" ]; then
  warn "ログイン失敗。レスポンス: $LOGIN_RESP"
  warn "デモアカウントが存在しない可能性があります"
  exit 1
fi
ok "ログイン成功 (token取得済み)"

# ============================================================
section "3. dashboard/counts API 疎通確認"
# ============================================================
COUNTS=$(curl -s http://localhost:8089/api/v1/dashboard/counts \
  -H "Authorization: Bearer $TOKEN")

echo "  レスポンス: $COUNTS"

STATUS=$(echo $COUNTS | python3 -c "import sys,json; d=json.load(sys.stdin); print('ok' if 'inputs' in d else 'ng')" 2>/dev/null || echo "error")
if [ "$STATUS" = "ok" ]; then
  ok "dashboard/counts API 正常"
else
  warn "dashboard/counts API 異常。レスポンス確認してください"
fi

# ============================================================
section "4. プロジェクト確認 & 未作成なら自動作成"
# ============================================================
PROJECTS=$(curl -s http://localhost:8089/api/v1/projects \
  -H "Authorization: Bearer $TOKEN")

PROJECT_COUNT=$(echo $PROJECTS | python3 -c "
import sys, json
d = json.load(sys.stdin)
if isinstance(d, list):
    print(len(d))
elif isinstance(d, dict) and 'items' in d:
    print(len(d['items']))
else:
    print(0)
" 2>/dev/null || echo "0")

info "既存プロジェクト数: $PROJECT_COUNT"

if [ "$PROJECT_COUNT" = "0" ]; then
  info "プロジェクトが0件のため自動作成します..."
  CREATE_RESP=$(curl -s -X POST http://localhost:8089/api/v1/projects \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d '{"name":"Phase1デモ","description":"decision-os Phase1動作確認用プロジェクト"}')
  echo "  作成レスポンス: $CREATE_RESP"
  PROJECT_ID=$(echo $CREATE_RESP | python3 -c "import sys,json; print(json.load(sys.stdin).get('id',''))" 2>/dev/null)
  ok "プロジェクト作成完了 (id: $PROJECT_ID)"
else
  ok "プロジェクト既存 ($PROJECT_COUNT 件)"
  PROJECT_ID=$(echo $PROJECTS | python3 -c "
import sys, json
d = json.load(sys.stdin)
items = d if isinstance(d, list) else d.get('items', [])
print(items[0]['id'] if items else '')
" 2>/dev/null || echo "")
fi

# ============================================================
section "5. Dashboard.tsx — 直近課題リスト表示の確認・追加"
# ============================================================
DASH_FILE=$PAGES_DIR/Dashboard.tsx

# recent_issues の表示があるか確認
HAS_RECENT=$(grep -c "recent" $DASH_FILE 2>/dev/null || echo "0")
info "recent_issues 表示コード: $HAS_RECENT 箇所"

if [ "$HAS_RECENT" = "0" ]; then
  warn "直近課題リストのUIが未実装。追加します..."
  # Dashboard.tsx全体を上書き
  cat > $DASH_FILE << 'DASH_EOF'
import { useState, useEffect } from "react";
import { useNavigate } from "react-router-dom";
import client from "../api/client";
import { PRIORITY_COLORS, type Priority } from "../types/index";

interface RecentIssue {
  id: string;
  title: string;
  status: string;
  priority: string;
}

interface DashboardCounts {
  inputs: { total: number; unprocessed: number };
  items: { pending_action: number };
  issues: {
    open: number;
    total: number;
    recent: RecentIssue[];
  };
}

const STATUS_LABEL: Record<string, string> = {
  open: "未着手",
  in_progress: "進行中",
  review: "レビュー",
  done: "完了",
  closed: "クローズ",
};

const STATUS_COLOR: Record<string, string> = {
  open: "#f59e0b",
  in_progress: "#3b82f6",
  review: "#8b5cf6",
  done: "#10b981",
  closed: "#64748b",
};

function CountCard({
  icon, label, value, sub, onClick, accent
}: {
  icon: string; label: string; value: number; sub?: string;
  onClick?: () => void; accent: string;
}) {
  return (
    <div
      onClick={onClick}
      style={{
        background: "#1e293b",
        border: `1px solid #334155`,
        borderLeft: `4px solid ${accent}`,
        borderRadius: "10px",
        padding: "20px",
        cursor: onClick ? "pointer" : "default",
        transition: "transform 0.1s",
      }}
      onMouseEnter={e => onClick && ((e.currentTarget as HTMLElement).style.transform = "translateY(-2px)")}
      onMouseLeave={e => onClick && ((e.currentTarget as HTMLElement).style.transform = "translateY(0)")}
    >
      <div style={{ fontSize: "24px", marginBottom: "8px" }}>{icon}</div>
      <div style={{ fontSize: "28px", fontWeight: "700", color: accent }}>{value}</div>
      <div style={{ fontSize: "14px", color: "#e2e8f0", marginTop: "4px" }}>{label}</div>
      {sub && <div style={{ fontSize: "12px", color: "#64748b", marginTop: "4px" }}>{sub}</div>}
    </div>
  );
}

export default function Dashboard() {
  const navigate = useNavigate();
  const [counts, setCounts] = useState<DashboardCounts | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");

  const fetchCounts = () => {
    setLoading(true);
    client.get("/dashboard/counts")
      .then(res => setCounts(res.data))
      .catch(() => setError("データ取得に失敗しました"))
      .finally(() => setLoading(false));
  };

  useEffect(() => { fetchCounts(); }, []);

  if (loading) return (
    <div style={{ padding: "24px", color: "#e2e8f0" }}>
      <div style={{ textAlign: "center", padding: "80px", color: "#64748b" }}>
        🔄 読み込み中...
      </div>
    </div>
  );

  return (
    <div style={{ padding: "24px", color: "#e2e8f0" }}>

      {/* ヘッダー */}
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: "28px" }}>
        <div>
          <h1 style={{ margin: 0, fontSize: "22px", fontWeight: "700" }}>ダッシュボード</h1>
          <p style={{ margin: "4px 0 0", fontSize: "13px", color: "#64748b" }}>
            意思決定の現在地を確認
          </p>
        </div>
        <div style={{ display: "flex", gap: "10px" }}>
          <button
            onClick={fetchCounts}
            style={{
              padding: "8px 16px", borderRadius: "8px",
              background: "transparent", color: "#94a3b8",
              border: "1px solid #334155", cursor: "pointer", fontSize: "13px",
            }}
          >
            🔄 更新
          </button>
          <button
            onClick={() => navigate("/inputs/new")}
            style={{
              padding: "10px 20px", borderRadius: "8px",
              background: "#3b82f6", color: "#fff", border: "none",
              cursor: "pointer", fontSize: "14px", fontWeight: "600",
            }}
          >
            ＋ 要望を登録
          </button>
        </div>
      </div>

      {error && (
        <div style={{
          background: "#450a0a", border: "1px solid #7f1d1d",
          borderRadius: "8px", padding: "12px 16px", marginBottom: "16px",
          color: "#fca5a5", fontSize: "14px",
        }}>
          ⚠️ {error}
        </div>
      )}

      {/* カウントカード 3列 */}
      <div style={{ display: "grid", gridTemplateColumns: "repeat(3, 1fr)", gap: "16px", marginBottom: "32px" }}>
        <CountCard
          icon="📥"
          label="未処理 INPUT"
          value={counts?.inputs.unprocessed ?? 0}
          sub={`総数 ${counts?.inputs.total ?? 0}件`}
          onClick={() => navigate("/inputs/new")}
          accent="#f59e0b"
        />
        <CountCard
          icon="🧩"
          label="ACTION待ち ITEM"
          value={counts?.items.pending_action ?? 0}
          sub="要判断"
          accent="#8b5cf6"
        />
        <CountCard
          icon="📋"
          label="未完了 ISSUE"
          value={counts?.issues.open ?? 0}
          sub={`総数 ${counts?.issues.total ?? 0}件`}
          onClick={() => navigate("/issues")}
          accent="#3b82f6"
        />
      </div>

      {/* 直近5件の要対応課題 */}
      <div style={{
        background: "#1e293b", border: "1px solid #334155",
        borderRadius: "12px", padding: "20px",
      }}>
        <div style={{
          display: "flex", justifyContent: "space-between", alignItems: "center",
          marginBottom: "16px",
        }}>
          <h2 style={{ margin: 0, fontSize: "16px", fontWeight: "600" }}>
            📌 直近の要対応課題
          </h2>
          <button
            onClick={() => navigate("/issues")}
            style={{
              background: "transparent", border: "none",
              color: "#3b82f6", cursor: "pointer", fontSize: "13px",
            }}
          >
            一覧を見る →
          </button>
        </div>

        {counts?.issues.recent && counts.issues.recent.length > 0 ? (
          <div style={{ display: "flex", flexDirection: "column", gap: "10px" }}>
            {counts.issues.recent.map((issue) => (
              <div
                key={issue.id}
                onClick={() => navigate(`/issues/${issue.id}`)}
                style={{
                  display: "flex", justifyContent: "space-between", alignItems: "center",
                  padding: "12px 16px",
                  background: "#0f172a",
                  border: "1px solid #334155",
                  borderLeft: `3px solid ${PRIORITY_COLORS[issue.priority as Priority] ?? "#64748b"}`,
                  borderRadius: "8px",
                  cursor: "pointer",
                  transition: "background 0.15s",
                }}
                onMouseEnter={e => (e.currentTarget as HTMLElement).style.background = "#1e293b"}
                onMouseLeave={e => (e.currentTarget as HTMLElement).style.background = "#0f172a"}
              >
                <span style={{ fontSize: "14px", color: "#e2e8f0", flex: 1 }}>
                  {issue.title}
                </span>
                <span style={{
                  fontSize: "12px", padding: "2px 10px", borderRadius: "12px",
                  background: "#1e293b",
                  color: STATUS_COLOR[issue.status] ?? "#94a3b8",
                  border: `1px solid ${STATUS_COLOR[issue.status] ?? "#334155"}`,
                  marginLeft: "12px", whiteSpace: "nowrap",
                }}>
                  {STATUS_LABEL[issue.status] ?? issue.status}
                </span>
              </div>
            ))}
          </div>
        ) : (
          <div style={{
            textAlign: "center", padding: "32px",
            color: "#64748b", fontSize: "14px",
          }}>
            <div style={{ fontSize: "36px", marginBottom: "8px" }}>🎉</div>
            要対応の課題はありません
          </div>
        )}
      </div>

    </div>
  );
}
DASH_EOF
  ok "Dashboard.tsx — 直近課題リスト追加完了"
else
  ok "Dashboard.tsx — 直近課題リスト既に実装済み"
fi

# ============================================================
section "6. TypeScript ビルド確認"
# ============================================================
cd $FRONTEND_DIR
info "npm run build 実行中..."
if npm run build > /tmp/dash_build.log 2>&1; then
  ok "フロントエンドビルド成功"
else
  echo "  ビルドログ:"
  cat /tmp/dash_build.log | grep -E "error|Error" | head -20
  warn "ビルドエラーあり。確認してください"
fi

# ============================================================
section "7. 最終確認: dashboard/counts の値"
# ============================================================
FINAL=$(curl -s http://localhost:8089/api/v1/dashboard/counts \
  -H "Authorization: Bearer $TOKEN")
echo "  INPUT  : $(echo $FINAL | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['inputs'])" 2>/dev/null)"
echo "  ITEMS  : $(echo $FINAL | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['items'])" 2>/dev/null)"
echo "  ISSUES : $(echo $FINAL | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['issues'])" 2>/dev/null)"

echo ""
echo "=============================================="
echo "🎉 ダッシュボード カウント修正完了！"
echo "  → http://localhost:3008 でダッシュボードを確認してください"
echo "  → 全0の場合は要望登録（＋ 要望を登録）を1件実行してください"
echo "=============================================="
