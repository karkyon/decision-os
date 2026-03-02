"""
audit_logs ルーター (N-007)

エンドポイント:
  GET /api/v1/audit-logs  - 監査ログ一覧（admin のみ、テナントスコープ）
"""
from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session
from typing import Optional
from datetime import datetime

from app.db.session import get_db
from app.core.deps import require_admin
from app.models.audit_log import AuditLog
from app.schemas.audit_log import AuditLogResponse

router = APIRouter()


@router.get("/audit-logs", response_model=list[AuditLogResponse])
def list_audit_logs(
    action:      Optional[str]  = Query(None, description="フィルタ: LOGIN / CREATE_INPUT 等"),
    entity_type: Optional[str]  = Query(None, description="フィルタ: input / issue 等"),
    user_id:     Optional[str]  = Query(None),
    since:       Optional[datetime] = Query(None, description="開始日時 (ISO8601)"),
    until:       Optional[datetime] = Query(None, description="終了日時 (ISO8601)"),
    limit:       int = Query(100, le=500),
    offset:      int = Query(0),
    db:          Session = Depends(get_db),
    current_user = Depends(require_admin()),
):
    q = db.query(AuditLog).filter(AuditLog.tenant_id == current_user.tenant_id)
    if action:      q = q.filter(AuditLog.action == action)
    if entity_type: q = q.filter(AuditLog.entity_type == entity_type)
    if user_id:     q = q.filter(AuditLog.user_id == user_id)
    if since:       q = q.filter(AuditLog.created_at >= since)
    if until:       q = q.filter(AuditLog.created_at <= until)
    return q.order_by(AuditLog.created_at.desc()).offset(offset).limit(limit).all()
