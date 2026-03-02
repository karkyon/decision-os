from pydantic import BaseModel, EmailStr
from typing import Optional
from datetime import datetime

class InviteCreate(BaseModel):
    email: EmailStr
    role: str = "dev"
    tenant_id: Optional[str] = None  # 未指定時はdefaultテナント

class InviteAccept(BaseModel):
    token: str
    name: str
    password: str

class InviteResponse(BaseModel):
    id: str
    email: str
    role: str
    token: str          # 本番はメール送信のみ・APIレスポンスには含めない
    expires_at: datetime
    invite_url: str

class InviteAcceptResponse(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"
    user_id: str
    name: str
    role: str
