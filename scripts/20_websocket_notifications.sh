#!/usr/bin/env bash
# =============================================================================
# decision-os / 20_websocket_notifications.sh
# WebSocket リアルタイム通知
# BE: /ws/notifications  接続管理 + ブロードキャスト
# FE: useNotifications hook + 🔔 ベルアイコン + トースト
# =============================================================================
set -euo pipefail

GREEN='\033[0;32m'; CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'
ok()      { echo -e "${GREEN}[OK]${RESET}    $*"; }
info()    { echo -e "${CYAN}[INFO]${RESET}  $*"; }
section() { echo -e "\n${BOLD}========== $* ==========${RESET}"; }

PROJECT_DIR="$HOME/projects/decision-os"
BACKUP_DIR="$HOME/projects/decision-os/backup_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"
info "バックアップ先: $BACKUP_DIR/"

# ─────────────────────────────────────────────
# BE-1: websockets インストール確認
# ─────────────────────────────────────────────
section "BE-1: websockets 依存確認"
cd "$PROJECT_DIR/backend"
source .venv/bin/activate

python3 -c "import websockets; print('websockets ok')" 2>/dev/null \
  && ok "websockets 既にインストール済み" \
  || { pip install websockets --quiet && ok "websockets インストール完了"; }

# FastAPI の WebSocket は標準搭載なので追加不要
python3 -c "from fastapi import WebSocket; print('FastAPI WebSocket ok')" && ok "FastAPI WebSocket 確認"

# ─────────────────────────────────────────────
# BE-2: core/notifier.py 作成（接続管理 + ブロードキャスト）
# ─────────────────────────────────────────────
section "BE-2: app/core/notifier.py 作成"

mkdir -p "$PROJECT_DIR/backend/app/core"
cat > "$PROJECT_DIR/backend/app/core/notifier.py" << 'PYEOF'
"""
ConnectionManager: WebSocket 接続管理 + ブロードキャスト

使用例（router 内）:
    from app.core.notifier import manager
    await manager.broadcast({"type": "issue.created", "data": {...}})
"""
import json
import asyncio
import logging
from typing import Dict, Set
from fastapi import WebSocket

logger = logging.getLogger(__name__)


class ConnectionManager:
    def __init__(self):
        # user_id → Set[WebSocket]（同一ユーザーが複数タブで接続可能）
        self._connections: Dict[str, Set[WebSocket]] = {}
        # プロジェクト購読: project_id → Set[user_id]
        self._project_subs: Dict[str, Set[str]] = {}

    async def connect(self, websocket: WebSocket, user_id: str, project_id: str = None):
        await websocket.accept()
        if user_id not in self._connections:
            self._connections[user_id] = set()
        self._connections[user_id].add(websocket)
        if project_id:
            if project_id not in self._project_subs:
                self._project_subs[project_id] = set()
            self._project_subs[project_id].add(user_id)
        logger.info(f"WS connected: user={user_id} total={self.total_connections}")

    def disconnect(self, websocket: WebSocket, user_id: str):
        if user_id in self._connections:
            self._connections[user_id].discard(websocket)
            if not self._connections[user_id]:
                del self._connections[user_id]
        logger.info(f"WS disconnected: user={user_id} total={self.total_connections}")

    @property
    def total_connections(self) -> int:
        return sum(len(sockets) for sockets in self._connections.values())

    async def send_to_user(self, user_id: str, message: dict):
        """特定ユーザーにのみ送信"""
        if user_id not in self._connections:
            return
        dead = set()
        for ws in self._connections[user_id]:
            try:
                await ws.send_text(json.dumps(message, ensure_ascii=False))
            except Exception:
                dead.add(ws)
        for ws in dead:
            self._connections[user_id].discard(ws)

    async def broadcast(self, message: dict, project_id: str = None):
        """全員 or プロジェクト購読者にブロードキャスト"""
        if project_id and project_id in self._project_subs:
            target_users = self._project_subs[project_id]
        else:
            target_users = set(self._connections.keys())

        payload = json.dumps(message, ensure_ascii=False)
        dead_ws = []
        for uid in target_users:
            for ws in list(self._connections.get(uid, [])):
                try:
                    await ws.send_text(payload)
                except Exception:
                    dead_ws.append((uid, ws))
        for uid, ws in dead_ws:
            if uid in self._connections:
                self._connections[uid].discard(ws)

    async def broadcast_notification(
        self,
        event_type: str,
        title: str,
        body: str,
        url: str = None,
        project_id: str = None,
        data: dict = None,
    ):
        """通知イベントのショートカット"""
        await self.broadcast(
            {
                "type": event_type,
                "title": title,
                "body": body,
                "url": url,
                "data": data or {},
                "ts": __import__("datetime").datetime.utcnow().isoformat() + "Z",
            },
            project_id=project_id,
        )


# シングルトン
manager = ConnectionManager()
PYEOF
ok "app/core/notifier.py 作成完了"

# ─────────────────────────────────────────────
# BE-3: routers/ws.py 作成（WebSocket エンドポイント）
# ─────────────────────────────────────────────
section "BE-3: routers/ws.py 作成"

cat > "$PROJECT_DIR/backend/app/api/v1/routers/ws.py" << 'PYEOF'
"""
WebSocket エンドポイント

接続: ws://host:8089/api/v1/ws/notifications?token=<JWT>
"""
import logging
from fastapi import APIRouter, WebSocket, WebSocketDisconnect, Query
from jose import jwt, JWTError

from app.core.notifier import manager
from app.core.config import settings

logger = logging.getLogger(__name__)
router = APIRouter(prefix="/ws", tags=["websocket"])


def _get_user_id_from_token(token: str) -> str | None:
    try:
        payload = jwt.decode(token, settings.SECRET_KEY, algorithms=["HS256"])
        return payload.get("sub")
    except (JWTError, Exception):
        return None


@router.websocket("/notifications")
async def ws_notifications(
    websocket: WebSocket,
    token: str = Query(...),
    project_id: str = Query(None),
):
    user_id = _get_user_id_from_token(token)
    if not user_id:
        await websocket.close(code=4001)
        return

    await manager.connect(websocket, user_id, project_id)
    try:
        # 接続確認メッセージ
        import json
        await websocket.send_text(json.dumps({
            "type": "connected",
            "title": "接続しました",
            "body": "リアルタイム通知が有効です",
            "ts": __import__("datetime").datetime.utcnow().isoformat() + "Z",
        }))
        # クライアントからのメッセージを待ち続ける（ping/pong対応）
        while True:
            data = await websocket.receive_text()
            if data == "ping":
                await websocket.send_text("pong")
    except WebSocketDisconnect:
        manager.disconnect(websocket, user_id)
    except Exception as e:
        logger.error(f"WS error: {e}")
        manager.disconnect(websocket, user_id)


@router.get("/stats")
async def ws_stats():
    """接続数確認（デバッグ用）"""
    return {"total_connections": manager.total_connections}
PYEOF
ok "routers/ws.py 作成完了"

# ─────────────────────────────────────────────
# BE-4: api.py に ws_router 追加
# ─────────────────────────────────────────────
section "BE-4: api.py に ws_router 追加"

API_PY="$PROJECT_DIR/backend/app/api/v1/api.py"
cp "$API_PY" "$BACKUP_DIR/api.py.bak"

if ! grep -q "ws" "$API_PY"; then
  python3 - << 'PYEOF'
import os
path = os.path.expanduser("~/projects/decision-os/backend/app/api/v1/api.py")
with open(path) as f:
    src = f.read()

# import 追加
src = src.replace(
    "from .routers import auth, inputs, analyze, items, actions, issues, trace, projects",
    "from .routers import auth, inputs, analyze, items, actions, issues, trace, projects, ws"
)

# router include 追加（既存の最後の include_router の後）
ws_include = '\napi_router.include_router(ws.router)\n'
src = src.rstrip() + ws_include

with open(path, "w") as f:
    f.write(src)
print("ADDED")
PYEOF
  ok "api.py: ws_router 追加完了"
else
  info "api.py: ws は既に追加済み"
fi

# ─────────────────────────────────────────────
# BE-5: issues.py / conversations.py にブロードキャスト追加
# ─────────────────────────────────────────────
section "BE-5: issues.py に create/update 通知を追加"

python3 - << 'PYEOF'
import os, re
path = os.path.expanduser("~/projects/decision-os/backend/app/api/v1/routers/issues.py")
with open(path) as f:
    src = f.read()

# notifier import 追加
if "notifier" not in src:
    src = src.replace(
        "from app.models.user import User",
        "from app.models.user import User\nfrom app.core.notifier import manager"
    )

# create_issue の db.commit() 後にブロードキャスト追加
old_create_end = '''    db.commit()
    db.refresh(issue)
    return _issue_dict(issue)


@router.get("/{issue_id}")'''

new_create_end = '''    db.commit()
    db.refresh(issue)
    # リアルタイム通知
    import asyncio
    try:
        asyncio.get_event_loop().create_task(
            manager.broadcast_notification(
                event_type="issue.created",
                title="新しい課題",
                body=issue.title[:50],
                url=f"/issues/{issue.id}",
                project_id=str(issue.project_id) if issue.project_id else None,
            )
        )
    except Exception:
        pass
    return _issue_dict(issue)


@router.get("/{issue_id}")'''

if old_create_end in src:
    src = src.replace(old_create_end, new_create_end)
    print("CREATE NOTIFY ADDED")

# update_issue にも通知
old_update_end = '''    db.commit()
    db.refresh(issue)
    return _issue_dict(issue)


def _issue_dict'''

new_update_end = '''    db.commit()
    db.refresh(issue)
    import asyncio
    try:
        asyncio.get_event_loop().create_task(
            manager.broadcast_notification(
                event_type="issue.updated",
                title="課題が更新されました",
                body=issue.title[:50],
                url=f"/issues/{issue.id}",
                project_id=str(issue.project_id) if issue.project_id else None,
            )
        )
    except Exception:
        pass
    return _issue_dict(issue)


def _issue_dict'''

if old_update_end in src:
    src = src.replace(old_update_end, new_update_end)
    print("UPDATE NOTIFY ADDED")

with open(path, "w") as f:
    f.write(src)
print("ISSUES NOTIFY DONE")
PYEOF
ok "issues.py: 通知追加完了"

# conversations.py にも通知追加
python3 - << 'PYEOF'
import os, re
path = os.path.expanduser("~/projects/decision-os/backend/app/api/v1/routers/conversations.py")
if not os.path.exists(path):
    print("SKIP: conversations.py not found")
    exit()

with open(path) as f:
    src = f.read()

if "notifier" not in src:
    src = src.replace(
        "from app.models.user import User",
        "from app.models.user import User\nfrom app.core.notifier import manager"
    )

# POST 後の return 前に通知を挿入
old = "    db.commit()\n    db.refresh(conv)\n    return"
new = '''    db.commit()
    db.refresh(conv)
    import asyncio
    try:
        asyncio.get_event_loop().create_task(
            manager.broadcast_notification(
                event_type="comment.posted",
                title="新しいコメント",
                body=(conv.body or "")[:50],
                url=f"/issues/{conv.issue_id}" if conv.issue_id else None,
            )
        )
    except Exception:
        pass
    return'''

if old in src:
    src = src.replace(old, new, 1)
    print("COMMENT NOTIFY ADDED")

with open(path, "w") as f:
    f.write(src)
print("CONVERSATIONS NOTIFY DONE")
PYEOF
ok "conversations.py: 通知追加完了"

# ─────────────────────────────────────────────
# FE-1: useNotifications.ts フック作成
# ─────────────────────────────────────────────
section "FE-1: useNotifications.ts 作成"

mkdir -p "$PROJECT_DIR/frontend/src/hooks"
cat > "$PROJECT_DIR/frontend/src/hooks/useNotifications.ts" << 'TSEOF'
/**
 * useNotifications
 * WebSocket 接続を管理し、通知を受け取る
 */
import { useState, useEffect, useRef, useCallback } from "react";

export interface Notification {
  id: string;
  type: string;
  title: string;
  body: string;
  url?: string;
  ts: string;
  read: boolean;
}

const WS_BASE = `ws://${window.location.hostname}:8089/api/v1/ws/notifications`;
const MAX_NOTIFICATIONS = 50;

export function useNotifications() {
  const [notifications, setNotifications] = useState<Notification[]>([]);
  const [connected, setConnected]         = useState(false);
  const wsRef   = useRef<WebSocket | null>(null);
  const timerRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  const unreadCount = notifications.filter(n => !n.read).length;

  const connect = useCallback(() => {
    const token = localStorage.getItem("access_token");
    if (!token) return;

    if (wsRef.current?.readyState === WebSocket.OPEN) return;

    const projectId = localStorage.getItem("current_project_id");
    const url = `${WS_BASE}?token=${token}${projectId ? `&project_id=${projectId}` : ""}`;

    const ws = new WebSocket(url);
    wsRef.current = ws;

    ws.onopen = () => {
      setConnected(true);
      // 定期 ping
      timerRef.current = setInterval(() => {
        if (ws.readyState === WebSocket.OPEN) ws.send("ping");
      }, 30000);
    };

    ws.onmessage = (event) => {
      try {
        const msg = JSON.parse(event.data);
        if (msg.type === "connected" || event.data === "pong") return;

        const notif: Notification = {
          id:    `${Date.now()}-${Math.random()}`,
          type:  msg.type,
          title: msg.title || msg.type,
          body:  msg.body  || "",
          url:   msg.url,
          ts:    msg.ts    || new Date().toISOString(),
          read:  false,
        };
        setNotifications(prev =>
          [notif, ...prev].slice(0, MAX_NOTIFICATIONS)
        );
      } catch { /* ignore */ }
    };

    ws.onclose = () => {
      setConnected(false);
      if (timerRef.current) clearInterval(timerRef.current);
      // 5秒後に再接続
      setTimeout(connect, 5000);
    };

    ws.onerror = () => ws.close();
  }, []);

  useEffect(() => {
    connect();
    return () => {
      wsRef.current?.close();
      if (timerRef.current) clearInterval(timerRef.current);
    };
  }, [connect]);

  const markAllRead = useCallback(() => {
    setNotifications(prev => prev.map(n => ({ ...n, read: true })));
  }, []);

  const markRead = useCallback((id: string) => {
    setNotifications(prev => prev.map(n => n.id === id ? { ...n, read: true } : n));
  }, []);

  const clear = useCallback(() => setNotifications([]), []);

  return { notifications, unreadCount, connected, markAllRead, markRead, clear };
}
TSEOF
ok "useNotifications.ts 作成完了"

# ─────────────────────────────────────────────
# FE-2: NotificationBell.tsx コンポーネント作成
# ─────────────────────────────────────────────
section "FE-2: NotificationBell.tsx 作成"

cat > "$PROJECT_DIR/frontend/src/components/NotificationBell.tsx" << 'TSEOF'
/**
 * NotificationBell
 * レイアウトヘッダーに表示する🔔ベルアイコン + ドロップダウン
 */
import { useState, useRef, useEffect } from "react";
import { useNavigate } from "react-router-dom";
import { useNotifications, Notification } from "../hooks/useNotifications";

const EVENT_ICON: Record<string, string> = {
  "issue.created":  "🆕",
  "issue.updated":  "✏️",
  "comment.posted": "💬",
  "input.created":  "📥",
  "connected":      "🔗",
};

export default function NotificationBell() {
  const navigate = useNavigate();
  const { notifications, unreadCount, connected, markAllRead, markRead, clear } =
    useNotifications();
  const [open, setOpen] = useState(false);
  const ref = useRef<HTMLDivElement>(null);

  // 外クリックで閉じる
  useEffect(() => {
    const handler = (e: MouseEvent) => {
      if (ref.current && !ref.current.contains(e.target as Node)) setOpen(false);
    };
    document.addEventListener("mousedown", handler);
    return () => document.removeEventListener("mousedown", handler);
  }, []);

  const handleClick = () => {
    setOpen(o => !o);
    if (!open) markAllRead();
  };

  const handleNotifClick = (n: Notification) => {
    markRead(n.id);
    if (n.url) navigate(n.url);
    setOpen(false);
  };

  const formatTime = (ts: string) => {
    try {
      const d = new Date(ts);
      const diff = (Date.now() - d.getTime()) / 1000;
      if (diff < 60)  return "今";
      if (diff < 3600) return `${Math.floor(diff/60)}分前`;
      if (diff < 86400) return `${Math.floor(diff/3600)}時間前`;
      return d.toLocaleDateString("ja-JP");
    } catch { return ""; }
  };

  return (
    <div ref={ref} style={{ position: "relative" }}>
      {/* ベルボタン */}
      <button
        onClick={handleClick}
        title={connected ? "通知（接続中）" : "通知（未接続）"}
        style={{
          position: "relative",
          background: "none",
          border: "none",
          cursor: "pointer",
          fontSize: "20px",
          padding: "4px 8px",
          borderRadius: "8px",
          color: connected ? "#e2e8f0" : "#475569",
          transition: "background 0.15s",
        }}
        onMouseEnter={e => (e.currentTarget.style.background = "#1e293b")}
        onMouseLeave={e => (e.currentTarget.style.background = "none")}
      >
        {connected ? "🔔" : "🔕"}
        {unreadCount > 0 && (
          <span style={{
            position: "absolute", top: "2px", right: "2px",
            background: "#ef4444", color: "#fff",
            borderRadius: "50%", fontSize: "10px", fontWeight: "700",
            minWidth: "16px", height: "16px",
            display: "flex", alignItems: "center", justifyContent: "center",
            padding: "0 2px",
          }}>
            {unreadCount > 99 ? "99+" : unreadCount}
          </span>
        )}
      </button>

      {/* ドロップダウン */}
      {open && (
        <div style={{
          position: "absolute", top: "calc(100% + 8px)", right: 0,
          width: "340px", maxHeight: "480px",
          background: "#0f172a", border: "1px solid #334155",
          borderRadius: "12px", boxShadow: "0 8px 32px rgba(0,0,0,0.5)",
          zIndex: 9999, overflow: "hidden",
          display: "flex", flexDirection: "column",
        }}>
          {/* ヘッダー */}
          <div style={{
            display: "flex", justifyContent: "space-between", alignItems: "center",
            padding: "12px 16px", borderBottom: "1px solid #1e293b",
          }}>
            <span style={{ fontWeight: "600", color: "#e2e8f0", fontSize: "14px" }}>
              🔔 通知
              <span style={{ color: "#64748b", fontSize: "12px", marginLeft: "6px" }}>
                {connected ? "● 接続中" : "○ 未接続"}
              </span>
            </span>
            <div style={{ display: "flex", gap: "8px" }}>
              {notifications.length > 0 && (
                <button onClick={clear} style={{
                  background: "none", border: "none", color: "#64748b",
                  cursor: "pointer", fontSize: "12px",
                }}>すべて削除</button>
              )}
            </div>
          </div>

          {/* 通知リスト */}
          <div style={{ overflowY: "auto", flex: 1 }}>
            {notifications.length === 0 ? (
              <div style={{
                padding: "40px 16px", textAlign: "center",
                color: "#475569", fontSize: "13px",
              }}>
                <div style={{ fontSize: "32px", marginBottom: "8px" }}>🔕</div>
                まだ通知はありません
              </div>
            ) : (
              notifications.map(n => (
                <div
                  key={n.id}
                  onClick={() => handleNotifClick(n)}
                  style={{
                    padding: "12px 16px",
                    borderBottom: "1px solid #1e293b",
                    cursor: n.url ? "pointer" : "default",
                    background: n.read ? "transparent" : "#1e2d3d",
                    transition: "background 0.1s",
                    display: "flex", gap: "10px", alignItems: "flex-start",
                  }}
                  onMouseEnter={e => {
                    if (n.url) e.currentTarget.style.background = "#1e293b";
                  }}
                  onMouseLeave={e => {
                    e.currentTarget.style.background = n.read ? "transparent" : "#1e2d3d";
                  }}
                >
                  <span style={{ fontSize: "18px", flexShrink: 0 }}>
                    {EVENT_ICON[n.type] || "📌"}
                  </span>
                  <div style={{ flex: 1, minWidth: 0 }}>
                    <div style={{
                      fontWeight: n.read ? "400" : "600",
                      color: "#e2e8f0", fontSize: "13px",
                      overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap",
                    }}>
                      {n.title}
                    </div>
                    <div style={{
                      color: "#94a3b8", fontSize: "12px", marginTop: "2px",
                      overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap",
                    }}>
                      {n.body}
                    </div>
                    <div style={{ color: "#475569", fontSize: "11px", marginTop: "2px" }}>
                      {formatTime(n.ts)}
                    </div>
                  </div>
                  {!n.read && (
                    <div style={{
                      width: "8px", height: "8px", borderRadius: "50%",
                      background: "#3b82f6", flexShrink: 0, marginTop: "4px",
                    }} />
                  )}
                </div>
              ))
            )}
          </div>
        </div>
      )}
    </div>
  );
}
TSEOF
ok "NotificationBell.tsx 作成完了"

# ─────────────────────────────────────────────
# FE-3: Layout.tsx に NotificationBell 追加
# ─────────────────────────────────────────────
section "FE-3: Layout.tsx に NotificationBell 追加"

LAYOUT="$PROJECT_DIR/frontend/src/components/Layout.tsx"
cp "$LAYOUT" "$BACKUP_DIR/Layout.tsx.bak"

python3 - << 'PYEOF'
import os, re
path = os.path.expanduser("~/projects/decision-os/frontend/src/components/Layout.tsx")
with open(path) as f:
    src = f.read()

# import 追加
if "NotificationBell" not in src:
    src = re.sub(
        r'(import.*from "react-router-dom";)',
        r'\1\nimport NotificationBell from "./NotificationBell";',
        src,
        count=1
    )

# ヘッダー部分に <NotificationBell /> を追加
# ログアウトボタンなどの直前に挿入
if "NotificationBell" not in src or "<NotificationBell" not in src:
    # ヘッダー内の右側エリアを探して追加
    # "ログアウト" ボタンの前に挿入
    src = re.sub(
        r'(<button[^>]*>.*?ログアウト)',
        r'<NotificationBell />\n              \1',
        src,
        count=1,
        flags=re.DOTALL
    )

with open(path, "w") as f:
    f.write(src)
print("Layout updated")
PYEOF
ok "Layout.tsx: NotificationBell 追加完了"

# ─────────────────────────────────────────────
# FE-4: ToastContainer（通知トースト）追加
# ─────────────────────────────────────────────
section "FE-4: NotificationToast.tsx 作成"

cat > "$PROJECT_DIR/frontend/src/components/NotificationToast.tsx" << 'TSEOF'
/**
 * NotificationToast
 * 右下に表示されるポップアップ通知（3秒で自動消去）
 * App.tsx で <NotificationToast /> を1つ配置するだけで動作
 */
import { useEffect, useState } from "react";
import { useNavigate } from "react-router-dom";
import { useNotifications, Notification } from "../hooks/useNotifications";

const EVENT_ICON: Record<string, string> = {
  "issue.created":  "🆕",
  "issue.updated":  "✏️",
  "comment.posted": "💬",
  "input.created":  "📥",
};

export default function NotificationToast() {
  const { notifications } = useNotifications();
  const navigate = useNavigate();
  const [toasts, setToasts] = useState<(Notification & { visible: boolean })[]>([]);
  const prevLen = useState(0);

  // 新着通知をトーストに追加
  useEffect(() => {
    if (notifications.length === 0) return;
    const latest = notifications[0];
    if (latest.type === "connected") return;

    setToasts(prev => {
      // 重複防止
      if (prev.some(t => t.id === latest.id)) return prev;
      return [...prev, { ...latest, visible: true }].slice(-5);
    });

    // 4秒後に非表示
    const timer = setTimeout(() => {
      setToasts(prev => prev.map(t =>
        t.id === latest.id ? { ...t, visible: false } : t
      ));
    }, 4000);

    // 5秒後に削除
    const removeTimer = setTimeout(() => {
      setToasts(prev => prev.filter(t => t.id !== latest.id));
    }, 5000);

    return () => { clearTimeout(timer); clearTimeout(removeTimer); };
  }, [notifications[0]?.id]);

  return (
    <div style={{
      position: "fixed", bottom: "24px", right: "24px",
      zIndex: 9998, display: "flex", flexDirection: "column", gap: "8px",
      pointerEvents: "none",
    }}>
      {toasts.map(toast => (
        <div
          key={toast.id}
          onClick={() => toast.url && navigate(toast.url)}
          style={{
            background: "#1e293b", border: "1px solid #334155",
            borderRadius: "10px", padding: "12px 16px",
            maxWidth: "320px", boxShadow: "0 4px 16px rgba(0,0,0,0.4)",
            display: "flex", gap: "10px", alignItems: "flex-start",
            cursor: toast.url ? "pointer" : "default",
            pointerEvents: "all",
            opacity: toast.visible ? 1 : 0,
            transform: toast.visible ? "translateX(0)" : "translateX(20px)",
            transition: "opacity 0.3s, transform 0.3s",
            borderLeft: "3px solid #3b82f6",
          }}
        >
          <span style={{ fontSize: "18px", flexShrink: 0 }}>
            {EVENT_ICON[toast.type] || "📌"}
          </span>
          <div style={{ flex: 1, minWidth: 0 }}>
            <div style={{ fontWeight: "600", color: "#e2e8f0", fontSize: "13px" }}>
              {toast.title}
            </div>
            <div style={{
              color: "#94a3b8", fontSize: "12px", marginTop: "2px",
              overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap",
            }}>
              {toast.body}
            </div>
          </div>
          <button
            onClick={e => { e.stopPropagation(); setToasts(prev => prev.filter(t => t.id !== toast.id)); }}
            style={{
              background: "none", border: "none", color: "#475569",
              cursor: "pointer", fontSize: "14px", flexShrink: 0, padding: 0,
            }}
          >×</button>
        </div>
      ))}
    </div>
  );
}
TSEOF
ok "NotificationToast.tsx 作成完了"

# ─────────────────────────────────────────────
# FE-5: App.tsx に NotificationToast 追加
# ─────────────────────────────────────────────
section "FE-5: App.tsx に NotificationToast 追加"

APP_TSX="$PROJECT_DIR/frontend/src/App.tsx"
cp "$APP_TSX" "$BACKUP_DIR/App.tsx.bak"

python3 - << 'PYEOF'
import os, re
path = os.path.expanduser("~/projects/decision-os/frontend/src/App.tsx")
with open(path) as f:
    src = f.read()

if "NotificationToast" not in src:
    # import 追加
    src = re.sub(
        r'(import.*Routes.*\n)',
        r'\1import NotificationToast from "./components/NotificationToast";\n',
        src, count=1
    )
    # </Routes> の後に追加
    src = src.replace(
        "</Routes>",
        "</Routes>\n      <NotificationToast />"
    )

with open(path, "w") as f:
    f.write(src)
print("App.tsx updated")
PYEOF
ok "App.tsx: NotificationToast 追加完了"

# ─────────────────────────────────────────────
# BE 再起動 & 確認
# ─────────────────────────────────────────────
section "バックエンド再起動 & 確認"

cd "$PROJECT_DIR/backend"
pkill -f "uvicorn" 2>/dev/null || true
sleep 1
nohup uvicorn app.main:app --host 0.0.0.0 --port 8089 --reload \
  > "$PROJECT_DIR/backend.log" 2>&1 &
sleep 4

echo "--- backend.log (末尾8行) ---"
tail -8 "$PROJECT_DIR/backend.log"
echo "-----------------------------"

if curl -s http://localhost:8089/api/v1/ws/stats > /dev/null 2>&1; then
  ok "バックエンド起動 ✅"
  RES=$(curl -s http://localhost:8089/api/v1/ws/stats)
  ok "WS stats: $RES"
else
  echo "[WARN] バックエンド応答なし → backend.log を確認"
  exit 1
fi

# ─────────────────────────────────────────────
section "完了サマリー"
echo "実装完了:"
echo "  ✅ BE: app/core/notifier.py（ConnectionManager シングルトン）"
echo "  ✅ BE: GET  /api/v1/ws/stats（接続数確認）"
echo "  ✅ BE: WS   /api/v1/ws/notifications?token=JWT（WebSocket エンドポイント）"
echo "  ✅ BE: issues.py に issue.created / issue.updated 通知"
echo "  ✅ BE: conversations.py に comment.posted 通知"
echo "  ✅ FE: src/hooks/useNotifications.ts（自動再接続 + ping/pong）"
echo "  ✅ FE: src/components/NotificationBell.tsx（🔔 ベル + ドロップダウン）"
echo "  ✅ FE: src/components/NotificationToast.tsx（右下トースト・4秒自動消去）"
echo "  ✅ FE: Layout.tsx に NotificationBell 追加"
echo "  ✅ FE: App.tsx に NotificationToast 追加"
echo ""
echo "ブラウザで確認:"
echo "  1. http://localhost:3008 → ヘッダーに 🔔 ベルが表示される"
echo "  2. 別タブで課題を新規作成 → 右下トーストが表示される"
echo "  3. ベルをクリック → 通知一覧ドロップダウンが開く"
echo "  4. curl http://localhost:8089/api/v1/ws/stats → 接続数確認"
ok "Phase 2: WebSocket リアルタイム通知 実装完了！"
