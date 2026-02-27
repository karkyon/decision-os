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
