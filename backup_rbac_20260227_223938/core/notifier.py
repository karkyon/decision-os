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
