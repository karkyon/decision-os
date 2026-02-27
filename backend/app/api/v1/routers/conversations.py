from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session, joinedload
from typing import List, Optional
from ....core.deps import get_db, get_current_user
from ....models.conversation import Conversation
from ....models.issue import Issue
from ....models.user import User
from ....schemas.conversation import ConversationCreate, ConversationUpdate, ConversationResponse

router = APIRouter(prefix="/conversations", tags=["conversations"])


@router.get("", response_model=List[ConversationResponse])
def list_conversations(
    issue_id: str = Query(..., description="課題ID（必須）"),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """課題に紐づくコメント一覧を取得（時系列昇順）"""
    issue = db.query(Issue).filter(Issue.id == issue_id).first()
    if not issue:
        raise HTTPException(status_code=404, detail="Issue not found")

    convs = (
        db.query(Conversation)
        .options(joinedload(Conversation.author))
        .filter(Conversation.issue_id == issue_id)
        .order_by(Conversation.created_at)
        .all()
    )
    return convs


@router.post("", response_model=ConversationResponse, status_code=201)
def create_conversation(
    payload: ConversationCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """コメントを投稿する"""
    issue = db.query(Issue).filter(Issue.id == payload.issue_id).first()
    if not issue:
        raise HTTPException(status_code=404, detail="Issue not found")

    if not payload.body.strip():
        raise HTTPException(status_code=422, detail="本文が空です")

    conv = Conversation(
        issue_id=payload.issue_id,
        author_id=current_user.id,
        body=payload.body.strip(),
    )
    db.add(conv)
    db.commit()
    db.refresh(conv)

    # author をロード
    db.refresh(conv)
    conv_with_author = (
        db.query(Conversation)
        .options(joinedload(Conversation.author))
        .filter(Conversation.id == conv.id)
        .first()
    )
    return conv_with_author


@router.patch("/{conv_id}", response_model=ConversationResponse)
def update_conversation(
    conv_id: str,
    payload: ConversationUpdate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """自分のコメントを編集する"""
    conv = db.query(Conversation).filter(Conversation.id == conv_id).first()
    if not conv:
        raise HTTPException(status_code=404, detail="Comment not found")
    if conv.author_id != current_user.id:
        raise HTTPException(status_code=403, detail="自分のコメントのみ編集できます")

    conv.body = payload.body.strip()
    db.commit()
    db.refresh(conv)
    return conv


@router.delete("/{conv_id}", status_code=204)
def delete_conversation(
    conv_id: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """自分のコメントを削除する（Adminは全削除可）"""
    conv = db.query(Conversation).filter(Conversation.id == conv_id).first()
    if not conv:
        raise HTTPException(status_code=404, detail="Comment not found")
    if conv.author_id != current_user.id and current_user.role != "admin":
        raise HTTPException(status_code=403, detail="自分のコメントのみ削除できます")

    db.delete(conv)
    db.commit()
    return None
