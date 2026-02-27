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
