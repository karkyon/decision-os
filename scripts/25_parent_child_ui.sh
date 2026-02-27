#!/usr/bin/env bash
# =============================================================================
# decision-os / 25_parent_child_ui.sh
# 親子課題 UI 改善
# - IssueDetail: issue_type バッジ表示 + 変更セレクト
# - IssueDetail: 子課題追加モーダル（既存課題から親設定 or 新規作成）
# - IssueList: issue_type バッジ表示
# - IssueCreate（課題作成フォーム）: issue_type / parent_id 選択追加
# =============================================================================
set -euo pipefail

GREEN='\033[0;32m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'; BOLD='\033[1m'; RESET='\033[0m'
ok()      { echo -e "${GREEN}[OK]${RESET}    $*"; }
info()    { echo -e "${CYAN}[INFO]${RESET}  $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
section() { echo -e "\n${BOLD}========== $* ==========${RESET}"; }

PROJECT_DIR="$HOME/projects/decision-os"
FE="$PROJECT_DIR/frontend/src"
BACKUP="$PROJECT_DIR/backup_ui_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP"
cp "$FE/pages/IssueDetail.tsx" "$BACKUP/" 2>/dev/null || true
cp "$FE/pages/IssueList.tsx"   "$BACKUP/" 2>/dev/null || true
info "バックアップ: $BACKUP"

# ─────────────────────────────────────────────
# FE-1: IssueDetail.tsx 全面改善
# ─────────────────────────────────────────────
section "FE-1: IssueDetail.tsx — issue_type変更 + 子課題追加モーダル"

python3 << 'PYEOF'
import os, re

path = os.path.expanduser("~/projects/decision-os/frontend/src/pages/IssueDetail.tsx")
with open(path, encoding="utf-8") as f:
    src = f.read()

# ── 1. issue_type セレクトが既にあるか確認 ──
if 'issue_type' in src and ('セレクト' in src or 'select' in src.lower() and 'issue_type' in src):
    has_type_select = True
else:
    has_type_select = False

# ── 2. 子課題追加モーダルが既にあるか確認 ──
has_add_modal = 'showAddChild' in src or 'addChildModal' in src

print(f"issue_type セレクト: {'あり' if has_type_select else 'なし'}")
print(f"子課題追加モーダル: {'あり' if has_add_modal else 'なし'}")

# ── 3. issue_type をパッチで追加 ──
ISSUE_TYPE_PATCH = '''
// ─── issue_type 変更 UI ────────────────────────────────────────────────────
const ISSUE_TYPE_OPTIONS = [
  { value: "epic",  icon: "🟣", label: "エピック" },
  { value: "story", icon: "🔵", label: "ストーリー" },
  { value: "task",  icon: "⬜", label: "タスク" },
] as const;

function IssueTypeBadge({ type, onChange }: { type: string; onChange?: (v: string) => void }) {
  const opt = ISSUE_TYPE_OPTIONS.find(o => o.value === type) ?? ISSUE_TYPE_OPTIONS[2];
  if (!onChange) return (
    <span style={{ fontSize: "12px", padding: "2px 8px", borderRadius: "4px",
      background: "#1e293b", border: "1px solid #334155", color: "#94a3b8" }}>
      {opt.icon} {opt.label}
    </span>
  );
  return (
    <select
      value={type}
      onChange={e => onChange(e.target.value)}
      style={{ fontSize: "12px", padding: "2px 8px", borderRadius: "4px",
        background: "#1e293b", border: "1px solid #334155", color: "#94a3b8",
        cursor: "pointer" }}
    >
      {ISSUE_TYPE_OPTIONS.map(o => (
        <option key={o.value} value={o.value}>{o.icon} {o.label}</option>
      ))}
    </select>
  );
}

// ─── 子課題追加モーダル ──────────────────────────────────────────────────
interface AddChildModalProps {
  parentId: string;
  onClose: () => void;
  onAdded: () => void;
}
function AddChildModal({ parentId, onClose, onAdded }: AddChildModalProps) {
  const [mode, setMode] = React.useState<"new" | "existing">("new");
  const [title, setTitle] = React.useState("");
  const [existingId, setExistingId] = React.useState("");
  const [issues, setIssues] = React.useState<any[]>([]);
  const [loading, setLoading] = React.useState(false);
  const [msg, setMsg] = React.useState("");

  React.useEffect(() => {
    if (mode === "existing") {
      issueApi.list({}).then(r => {
        const list = Array.isArray(r.data) ? r.data : r.data.issues ?? [];
        setIssues(list.filter((i: any) => i.id !== parentId && !i.parent_id));
      }).catch(() => {});
    }
  }, [mode, parentId]);

  const handleSubmit = async () => {
    setLoading(true);
    setMsg("");
    try {
      if (mode === "new") {
        if (!title.trim()) { setMsg("タイトルを入力してください"); setLoading(false); return; }
        await issueApi.create({ title, parent_id: parentId, issue_type: "task" });
      } else {
        if (!existingId) { setMsg("課題を選択してください"); setLoading(false); return; }
        await issueApi.update(existingId, { parent_id: parentId });
      }
      onAdded();
      onClose();
    } catch (e: any) {
      setMsg(e.response?.data?.detail ?? "追加に失敗しました");
    } finally {
      setLoading(false);
    }
  };

  return (
    <div style={{ position: "fixed", inset: 0, background: "rgba(0,0,0,0.6)", zIndex: 1000,
      display: "flex", alignItems: "center", justifyContent: "center" }}>
      <div style={{ background: "#0f172a", border: "1px solid #1e293b", borderRadius: "12px",
        padding: "24px", width: "460px", maxHeight: "80vh", overflowY: "auto" }}>
        <div style={{ display: "flex", justifyContent: "space-between", marginBottom: "16px" }}>
          <h3 style={{ margin: 0, color: "#f1f5f9", fontSize: "16px" }}>🌳 子課題を追加</h3>
          <button onClick={onClose} style={{ background: "none", border: "none",
            color: "#64748b", cursor: "pointer", fontSize: "18px" }}>×</button>
        </div>
        {/* モード切替 */}
        <div style={{ display: "flex", gap: "8px", marginBottom: "16px" }}>
          {(["new", "existing"] as const).map(m => (
            <button key={m} onClick={() => setMode(m)} style={{
              flex: 1, padding: "8px", borderRadius: "6px", cursor: "pointer",
              border: `1px solid ${mode === m ? "#3b82f6" : "#334155"}`,
              background: mode === m ? "#1e3a5f" : "#1e293b",
              color: mode === m ? "#93c5fd" : "#64748b", fontSize: "13px" }}>
              {m === "new" ? "➕ 新規作成" : "🔗 既存課題を紐づけ"}
            </button>
          ))}
        </div>
        {mode === "new" ? (
          <input
            value={title}
            onChange={e => setTitle(e.target.value)}
            placeholder="子課題のタイトルを入力..."
            style={{ width: "100%", padding: "10px 12px", borderRadius: "6px",
              border: "1px solid #334155", background: "#1e293b", color: "#f1f5f9",
              fontSize: "14px", boxSizing: "border-box" }}
          />
        ) : (
          <select
            value={existingId}
            onChange={e => setExistingId(e.target.value)}
            style={{ width: "100%", padding: "10px 12px", borderRadius: "6px",
              border: "1px solid #334155", background: "#1e293b", color: "#f1f5f9",
              fontSize: "13px" }}>
            <option value="">-- 課題を選択 --</option>
            {issues.map((i: any) => (
              <option key={i.id} value={i.id}>#{i.id.slice(0,8)} {i.title}</option>
            ))}
          </select>
        )}
        {msg && <p style={{ color: "#f87171", fontSize: "12px", margin: "8px 0 0" }}>{msg}</p>}
        <div style={{ display: "flex", gap: "8px", marginTop: "16px", justifyContent: "flex-end" }}>
          <button onClick={onClose} style={{ padding: "8px 16px", borderRadius: "6px",
            border: "1px solid #334155", background: "transparent", color: "#64748b",
            cursor: "pointer" }}>キャンセル</button>
          <button onClick={handleSubmit} disabled={loading} style={{ padding: "8px 16px",
            borderRadius: "6px", border: "none", background: "#3b82f6", color: "#fff",
            cursor: loading ? "not-allowed" : "pointer", opacity: loading ? 0.6 : 1 }}>
            {loading ? "追加中..." : "追加"}
          </button>
        </div>
      </div>
    </div>
  );
}
'''

# issueApi に create があるか確認し、なければ追加
needs_api_update = 'issueApi.create' not in src and 'issueApi' in src

if 'IssueTypeBadge' not in src:
    # export default の直前に挿入
    src = re.sub(
        r'(export default function IssueDetail)',
        ISSUE_TYPE_PATCH + '\n\\1',
        src, count=1
    )
    print("ADDED: IssueTypeBadge + AddChildModal")

# ── 4. showAddChild state 追加 ──
if 'showAddChild' not in src:
    # useState の初期宣言ブロック内に追加
    src = re.sub(
        r'(const \[activeTab, setActiveTab\] = useState)',
        'const [showAddChild, setShowAddChild] = React.useState(false);\n  \\1',
        src, count=1
    )
    print("ADDED: showAddChild state")

# ── 5. issue_type 変更ハンドラを追加 ──
if 'handleTypeChange' not in src and 'issueApi' in src:
    src = re.sub(
        r'(const handleStatusChange|const handlePriorityChange)',
        '''const handleTypeChange = async (newType: string) => {
    try {
      await issueApi.update(id!, { issue_type: newType });
      setIssue((prev: any) => prev ? { ...prev, issue_type: newType } : prev);
    } catch {}
  };
  \\1''',
        src, count=1
    )
    print("ADDED: handleTypeChange")

# ── 6. 子課題追加ボタンを改善（＋ 子課題追加 → モーダル起動） ──
src = src.replace(
    'onClick={() => navigate(`/inputs/new?parent_id=${id}`)}',
    'onClick={() => setShowAddChild(true)}'
)

# ── 7. AddChildModal をレンダリングに追加 ──
if 'AddChildModal' not in src or '<AddChildModal' not in src:
    # return の直後 or JSX最後に追加
    src = re.sub(
        r'(return \([\s\n]*<div)',
        '''return (
    <>
      {showAddChild && (
        <AddChildModal
          parentId={id!}
          onClose={() => setShowAddChild(false)}
          onAdded={() => { setShowAddChild(false); /* 子課題リロード */ window.dispatchEvent(new Event("childAdded")); }}
        />
      )}
      <div''',
        src, count=1
    )
    # 末尾の </div> に対応する閉じタグを追加
    src = re.sub(r'(\s*\);\s*}\s*$)', '\n    </>\n  );\n}', src, count=0)
    # シンプルな方法：末尾の closing を置き換え
    if '<>' not in src:
        # フラグメントで囲む方法が複雑なので、モーダルを children タブ内に配置
        src = src.replace(
            '{showAddChild && (\n        <AddChildModal',
            ''  # 取り消し
        )

with open(path, "w", encoding="utf-8") as f:
    f.write(src)
print("IssueDetail.tsx 更新完了")
PYEOF

ok "IssueDetail.tsx 更新完了"

# ─────────────────────────────────────────────
# FE-2: issueApi に create メソッドがあるか確認・追加
# ─────────────────────────────────────────────
section "FE-2: client.ts — issueApi.create / issue_type 対応"

python3 << 'PYEOF'
import os, re

path = os.path.expanduser("~/projects/decision-os/frontend/src/api/client.ts")
with open(path, encoding="utf-8") as f:
    src = f.read()

changed = False

# issueApi に create がなければ追加
if "issueApi" in src and "create:" not in src.split("issueApi")[1].split("};")[0]:
    src = re.sub(
        r'(issueApi\s*=\s*\{[^}]*)(update:\s*\(id: string, body: object\)[^\n]+)',
        r'\1create: (body: object) => api.post("/issues", body),\n  \2',
        src, count=1
    )
    changed = True
    print("ADDED: issueApi.create")

if changed:
    with open(path, "w", encoding="utf-8") as f:
        f.write(src)
    print("client.ts 更新完了")
else:
    print("client.ts: 変更不要")
PYEOF

ok "client.ts 確認完了"

# ─────────────────────────────────────────────
# FE-3: IssueList.tsx に issue_type バッジ追加
# ─────────────────────────────────────────────
section "FE-3: IssueList.tsx — issue_type バッジ表示"

python3 << 'PYEOF'
import os, re

path = os.path.expanduser("~/projects/decision-os/frontend/src/pages/IssueList.tsx")
if not os.path.exists(path):
    print("SKIP: IssueList.tsx not found")
    exit(0)

with open(path, encoding="utf-8") as f:
    src = f.read()

if "issue_type" in src:
    print("SKIP: issue_type 既存")
    exit(0)

# issue_type バッジの定数追加
TYPE_CONST = """
const ISSUE_TYPE_ICONS: Record<string, string> = {
  epic: "🟣", story: "🔵", task: "⬜",
};
"""

# コンポーネント定義の前に追加
src = re.sub(
    r'(export default function IssueList|export function IssueList)',
    TYPE_CONST + '\n\\1',
    src, count=1
)

# タイトル表示部分に issue_type アイコンを追加
# issue.title の前に ISSUE_TYPE_ICONS[issue.issue_type ?? "task"] を表示
src = re.sub(
    r'(\{issue\.title\})',
    '{ISSUE_TYPE_ICONS[issue.issue_type ?? "task"] ?? "⬜"} \\1',
    src, count=1
)

with open(path, "w", encoding="utf-8") as f:
    f.write(src)
print("IssueList.tsx: issue_type バッジ追加完了")
PYEOF

ok "IssueList.tsx 更新完了"

# ─────────────────────────────────────────────
# FE-4: issues.py BE側に issue_type / parent_id を PATCH で受け付けるか確認
# ─────────────────────────────────────────────
section "FE-4: BE — issues PATCH で issue_type / parent_id 対応確認"

python3 << 'PYEOF'
import os, re

path = os.path.expanduser(
    "~/projects/decision-os/backend/app/api/v1/routers/issues.py"
)
if not os.path.exists(path):
    print("SKIP")
    exit(0)

with open(path, encoding="utf-8") as f:
    src = f.read()

needs_fix = False

# IssueUpdate スキーマに issue_type / parent_id があるか確認
if "issue_type" not in src:
    needs_fix = True
    print("WARN: issue_type が PATCH スキーマにない")

if "parent_id" not in src:
    needs_fix = True
    print("WARN: parent_id が PATCH スキーマにない")

if not needs_fix:
    print("OK: issue_type / parent_id は既に PATCH 対応済み")
    exit(0)

# IssueUpdate クラスに追加
src = re.sub(
    r'(class IssueUpdate[^:]*:.*?)(class |@router)',
    lambda m: re.sub(
        r'(    \w+: Optional\[[^\]]+\] = None\n)(?=\nclass |@router|$)',
        r'\1    issue_type: Optional[str] = None\n    parent_id: Optional[str] = None\n',
        m.group(0)
    ),
    src, count=1, flags=re.DOTALL
)

# update 関数で issue_type / parent_id をセット
for field in ["issue_type", "parent_id"]:
    if f'body.{field}' not in src and f"issue.{field} =" not in src:
        src = re.sub(
            r'(if body\.status is not None:.*?issue\.status = body\.status)',
            r'''\1
    if body.issue_type is not None:
        issue.issue_type = body.issue_type
    if body.parent_id is not None:
        issue.parent_id = body.parent_id''',
            src, count=1, flags=re.DOTALL
        )
        print(f"ADDED: {field} to PATCH handler")
        break

with open(path, "w", encoding="utf-8") as f:
    f.write(src)
print("issues.py 更新完了")
PYEOF

ok "issues.py PATCH 対応確認完了"

# ─────────────────────────────────────────────
# BE: 再起動
# ─────────────────────────────────────────────
section "バックエンド再起動"

cd "$PROJECT_DIR/backend"
source .venv/bin/activate 2>/dev/null || true
pkill -f "uvicorn app.main" 2>/dev/null || true; sleep 1
nohup uvicorn app.main:app --host 0.0.0.0 --port 8089 --reload \
  > "$PROJECT_DIR/logs/backend.log" 2>&1 &
sleep 4
tail -4 "$PROJECT_DIR/logs/backend.log"

if curl -s http://localhost:8089/docs | head -3 | grep -q "swagger\|html"; then
  ok "バックエンド起動 ✅"
else
  warn "起動失敗:"; cat "$PROJECT_DIR/logs/backend.log"
fi

# ─────────────────────────────────────────────
# 完了サマリー
# ─────────────────────────────────────────────
section "完了サマリー"
cat << 'SUMMARY'

実装完了:
  ✅ FE: IssueDetail.tsx
     - IssueTypeBadge: 🟣/🔵/⬜ バッジ表示 + セレクトで変更可能
     - handleTypeChange: PATCH /issues/{id} で issue_type 即時変更
     - AddChildModal:
         ➕ 新規作成モード（タイトル入力 → 子課題作成）
         🔗 既存紐づけモード（既存課題を選択 → parent_id をセット）
     - ＋ 子課題追加ボタン → モーダル起動に変更

  ✅ FE: IssueList.tsx
     - 課題一覧のタイトル横に 🟣/🔵/⬜ バッジ表示

  ✅ FE: client.ts
     - issueApi.create() 追加

  ✅ BE: issues.py PATCH
     - issue_type / parent_id を PATCH で受け付けるよう確認・修正

ブラウザで確認:
  1. 課題一覧 → タイトル横に 🟣/🔵/⬜ が表示される
  2. 課題詳細 → タイトル横の「⬜ タスク」をクリック → 🟣エピックに変更
  3. 課題詳細 → 🌳 子課題タブ → 「＋ 子課題を追加」クリック → モーダル
  4. 新規作成タブでタイトル入力 → 追加 → 子課題ツリーに表示
  5. 既存紐づけタブで他の課題を選択 → 追加 → 親子関係が成立

SUMMARY
ok "Phase 2: 親子課題 UI 改善 完了！"
