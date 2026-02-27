#!/bin/bash
# ============================================================
# Phase 1 MVP - Step 2: 認証API（JWT）実装
# ============================================================
set -e

PROJECT="$HOME/projects/decision-os"
BACKEND="$PROJECT/backend"

echo "=== Step 2: 認証API実装 ==="

# ---- JWT依存ライブラリ確認 ----
cd "$BACKEND"
source .venv/bin/activate
pip install python-jose[cryptography] passlib[bcrypt] --quiet

# ---- セキュリティユーティリティ ----
mkdir -p "$BACKEND/app/core"
cat > "$BACKEND/app/core/security.py" << 'EOF'
from datetime import datetime, timedelta
from typing import Optional
from jose import JWTError, jwt
from passlib.context import CryptContext
from .config import settings

pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")

def verify_password(plain_password: str, hashed_password: str) -> bool:
    return pwd_context.verify(plain_password, hashed_password)

def get_password_hash(password: str) -> str:
    return pwd_context.hash(password)

def create_access_token(data: dict, expires_delta: Optional[timedelta] = None) -> str:
    to_encode = data.copy()
    expire = datetime.utcnow() + (expires_delta or timedelta(minutes=settings.ACCESS_TOKEN_EXPIRE_MINUTES))
    to_encode.update({"exp": expire})
    return jwt.encode(to_encode, settings.SECRET_KEY, algorithm=settings.ALGORITHM)

def decode_token(token: str) -> Optional[dict]:
    try:
        return jwt.decode(token, settings.SECRET_KEY, algorithms=[settings.ALGORITHM])
    except JWTError:
        return None
EOF

# ---- 依存注入: 現在のユーザー取得 ----
cat > "$BACKEND/app/core/deps.py" << 'EOF'
from typing import Generator, Optional
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from sqlalchemy.orm import Session
from .security import decode_token
from ..db.session import SessionLocal
from ..models.user import User

bearer_scheme = HTTPBearer()

def get_db() -> Generator:
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()

def get_current_user(
    credentials: HTTPAuthorizationCredentials = Depends(bearer_scheme),
    db: Session = Depends(get_db),
) -> User:
    token = credentials.credentials
    payload = decode_token(token)
    if not payload:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid token")
    user_id: str = payload.get("sub")
    user = db.query(User).filter(User.id == user_id).first()
    if not user:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="User not found")
    return user

def require_role(*roles: str):
    def _checker(current_user: User = Depends(get_current_user)):
        if current_user.role not in roles:
            raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Insufficient permissions")
        return current_user
    return _checker
EOF

# ---- Pydantic スキーマ ----
mkdir -p "$BACKEND/app/schemas"
cat > "$BACKEND/app/schemas/__init__.py" << 'EOF'
EOF

cat > "$BACKEND/app/schemas/auth.py" << 'EOF'
from pydantic import BaseModel, EmailStr

class UserRegister(BaseModel):
    name: str
    email: EmailStr
    password: str
    role: str = "dev"

class UserLogin(BaseModel):
    email: EmailStr
    password: str

class TokenResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"
    user_id: str
    name: str
    role: str
EOF

# ---- 認証ルーター ----
mkdir -p "$BACKEND/app/api/v1/routers"
cat > "$BACKEND/app/api/v1/routers/__init__.py" << 'EOF'
EOF

cat > "$BACKEND/app/api/v1/routers/auth.py" << 'EOF'
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from ....core.deps import get_db
from ....core.security import get_password_hash, verify_password, create_access_token
from ....models.user import User
from ....schemas.auth import UserRegister, UserLogin, TokenResponse

router = APIRouter(prefix="/auth", tags=["auth"])

@router.post("/register", response_model=TokenResponse, status_code=201)
def register(payload: UserRegister, db: Session = Depends(get_db)):
    existing = db.query(User).filter(User.email == payload.email).first()
    if existing:
        raise HTTPException(status_code=400, detail="Email already registered")
    user = User(
        name=payload.name,
        email=payload.email,
        hashed_password=get_password_hash(payload.password),
        role=payload.role,
    )
    db.add(user)
    db.commit()
    db.refresh(user)
    token = create_access_token({"sub": user.id})
    return TokenResponse(access_token=token, user_id=user.id, name=user.name, role=user.role)

@router.post("/login", response_model=TokenResponse)
def login(payload: UserLogin, db: Session = Depends(get_db)):
    user = db.query(User).filter(User.email == payload.email).first()
    if not user or not verify_password(payload.password, user.hashed_password):
        raise HTTPException(status_code=401, detail="Invalid credentials")
    token = create_access_token({"sub": user.id})
    return TokenResponse(access_token=token, user_id=user.id, name=user.name, role=user.role)

@router.get("/me")
def me(db: Session = Depends(get_db)):
    # JWT検証はフロント側で実装、ここではスタブ
    return {"message": "use Authorization: Bearer <token>"}
EOF

echo "✅ 認証API生成完了"
echo "✅✅✅ Step 2 完了: 認証API（register/login/JWT）"
