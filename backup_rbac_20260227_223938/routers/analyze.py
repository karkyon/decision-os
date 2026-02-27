from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from typing import List
from pydantic import BaseModel
from ....core.deps import get_db, get_current_user
from ....models.input import Input
from ....models.item import Item
from ....models.interpretation import Interpretation
from ....models.user import User
from ....schemas.item import ItemResponse

router = APIRouter(prefix="/analyze", tags=["analyze"])

class AnalyzeRequest(BaseModel):
    input_id: str

@router.post("", response_model=List[ItemResponse])
def analyze_input(
    payload: AnalyzeRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    inp = db.query(Input).filter(Input.id == payload.input_id).first()
    if not inp:
        raise HTTPException(status_code=404, detail="Input not found")

    # 既存ITEMがあれば返す（冪等）
    existing_items = db.query(Item).filter(Item.input_id == payload.input_id).all()
    if existing_items:
        return existing_items

    # 分解エンジン呼び出し
    import sys, os
    sys.path.insert(0, os.path.join(os.path.dirname(__file__), "../../../../../engine"))
    try:
        from engine.main import analyze_text
        results = analyze_text(inp.raw_text)
    except Exception as e:
        # エンジンが未実装の場合のフォールバック
        results = _fallback_analyze(inp.raw_text)

    # Interpretation生成
    interp = Interpretation(
        input_id=inp.id,
        summary=f"（自動解析）{inp.raw_text[:100]}...",
        overall_intent=results[0]["intent_code"] if results else "INF",
        confidence=results[0]["confidence"] if results else 0.5,
    )
    db.add(interp)

    # Item生成
    items = []
    for i, r in enumerate(results):
        item = Item(
            input_id=inp.id,
            text=r["text"],
            intent_code=r["intent_code"],
            domain_code=r["domain_code"],
            confidence=r["confidence"],
            position=i,
        )
        db.add(item)
        items.append(item)

    db.commit()
    for item in items:
        db.refresh(item)
    return items

def _fallback_analyze(text: str) -> list:
    """分解エンジン未実装時のシンプルフォールバック"""
    import re
    sentences = re.split(r'[。\n]+', text.strip())
    sentences = [s.strip() for s in sentences if s.strip()]

    results = []
    bug_words = ["エラー", "バグ", "不具合", "動かない", "おかしい", "失敗"]
    req_words = ["ほしい", "したい", "追加", "実装", "対応", "欲しい"]
    qst_words = ["？", "ですか", "でしょうか", "どう", "どの"]

    for s in sentences:
        if any(w in s for w in bug_words):
            intent, domain, conf = "BUG", "API", 0.80
        elif any(w in s for w in req_words):
            intent, domain, conf = "REQ", "SPEC", 0.75
        elif any(w in s for w in qst_words):
            intent, domain, conf = "QST", "SPEC", 0.70
        else:
            intent, domain, conf = "INF", "SPEC", 0.60

        # domain推定
        if any(w in s for w in ["画面", "UI", "ボタン", "表示"]):
            domain = "UI"
        elif any(w in s for w in ["API", "エンドポイント", "レスポンス"]):
            domain = "API"
        elif any(w in s for w in ["DB", "データベース", "テーブル", "SQL"]):
            domain = "DB"
        elif any(w in s for w in ["認証", "ログイン", "権限"]):
            domain = "AUTH"

        results.append({"text": s, "intent_code": intent, "domain_code": domain, "confidence": conf})

    return results if results else [{"text": text, "intent_code": "INF", "domain_code": "SPEC", "confidence": 0.5}]
