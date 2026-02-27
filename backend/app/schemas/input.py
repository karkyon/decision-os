from pydantic import BaseModel, model_validator
from typing import Optional
from datetime import datetime


class InputCreate(BaseModel):
    raw_text: Optional[str] = None
    text: Optional[str] = None
    project_id: Optional[str] = None
    source_type: str = "manual"
    summary: Optional[str] = None
    importance: int = 3

    @model_validator(mode="before")
    @classmethod
    def normalize_text(cls, values):
        # text → raw_text へ自動変換
        if not values.get("raw_text") and values.get("text"):
            values["raw_text"] = values["text"]
        return values

    def get_raw_text(self) -> str:
        return self.raw_text or self.text or ""


class InputResponse(BaseModel):
    id: str
    project_id: Optional[str] = None
    author_id: Optional[str] = None
    source_type: str
    raw_text: str
    summary: Optional[str] = None
    importance: int
    created_at: datetime
    updated_at: Optional[datetime] = None

    model_config = {"from_attributes": True}
