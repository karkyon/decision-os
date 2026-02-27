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
