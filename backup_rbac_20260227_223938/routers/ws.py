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
