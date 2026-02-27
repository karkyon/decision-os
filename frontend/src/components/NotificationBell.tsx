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
