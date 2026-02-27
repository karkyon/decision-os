"""
Normalizer: テキスト前処理
- 全角半角統一
- 表記ゆれ修正
- 改行・空白の正規化
"""
import re
import unicodedata


REPLACE_MAP = {
    "ｴﾗｰ": "エラー",
    "ﾊﾞｸﾞ": "バグ",
    "UI": "UI",
    "ＵＩ": "UI",
    "ＡＰＩ": "API",
    "ＤＢ": "DB",
    "ＵＲＬ": "URL",
}


def normalize(text: str) -> str:
    if not text:
        return ""

    # Unicode NFKC正規化（全角→半角変換を含む）
    text = unicodedata.normalize("NFKC", text)

    # カスタム表記ゆれ変換
    for src, dst in REPLACE_MAP.items():
        text = text.replace(src, dst)

    # 連続空白・タブを単一スペースに
    text = re.sub(r"[ \t\u3000]+", " ", text)

    # 3行以上の連続改行を2行に圧縮
    text = re.sub(r"\n{3,}", "\n\n", text)

    return text.strip()
