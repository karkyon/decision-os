"""
audit.py - 監査ログ書き込みユーティリティ

使い方:
    from app.core.audit import log_action
    log_action(db, user=current_user, action="CREATE_INPUT",
               entity_type="input", entity_id=input.id,
               detail={"project_id": str(project_id)}, request=request)
"""
from __future__ import annotations
from typing import Optional, Any
from uuid import UUID
from sqlalchemy.orm import Session
from app.models.audit_log import AuditLog


def log_action(
    db: Session,
    action: str,
    user=None,
    entity_type: Optional[str] = None,
    entity_id=None,
    detail: Optional[dict] = None,
    request=None,
) -> AuditLog:
    """監査ログを1件書き込んで返す。例外は握り潰してサービスを止めない。"""
    try:
        entry = AuditLog(
            user_id     = getattr(user, "id", None),
            tenant_id   = getattr(user, "tenant_id", None),
            action      = action,
            entity_type = entity_type,
            entity_id   = entity_id if entity_id is None or isinstance(entity_id, UUID) else UUID(str(entity_id)),
            detail      = detail,
            ip_address  = _get_ip(request),
            user_agent  = _get_ua(request),
        )
        db.add(entry)
        db.commit()
        return entry
    except Exception as e:
        db.rollback()
        # 監査ログ失敗でサービスを止めない
        import logging
        logging.getLogger("audit").warning(f"audit log failed: {e}")
        return None


def _get_ip(request) -> Optional[str]:
    if request is None:
        return None
    forwarded = getattr(getattr(request, "headers", None), "get", lambda k, d=None: d)("x-forwarded-for")
    if forwarded:
        return forwarded.split(",")[0].strip()
    client = getattr(request, "client", None)
    return getattr(client, "host", None)


def _get_ua(request) -> Optional[str]:
    if request is None:
        return None
    return getattr(getattr(request, "headers", None), "get", lambda k, d=None: d)("user-agent")
