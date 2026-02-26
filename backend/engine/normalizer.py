"""
Normalizer: テキストの前処理・正規化
"""
import unicodedata
import json
import os

# ライブ辞書を読み込む（起動時のみ）
_LIVE_DICT_PATH = os.path.join(os.path.dirname(__file__), "../dictionary/live.json")

def _load_live_dict() -> dict:
    try:
        with open(_LIVE_DICT_PATH, "r", encoding="utf-8") as f:
            return json.load(f)
    except FileNotFoundError:
        return {}

_REPLACE_MAP = {
    "ログイン出来ない": "ログインできない",
    "落ちちゃう": "落ちる",
    "できませんか": "できるか",
    "使えない": "使用できない",
    **_load_live_dict(),
}

def normalize(text: str) -> str:
    """全角半角統一・表記ゆれ補正"""
    text = unicodedata.normalize("NFKC", text)
    for src, dst in _REPLACE_MAP.items():
        text = text.replace(src, dst)
    return text.strip()
