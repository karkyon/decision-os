"""
Segmenter: 文境界でテキストを分割
"""
import re
from typing import List

CONJUNCTIONS = ["また、", "そして、", "ただし、", "なお、", "一方、", "しかし、", "それと、", "さらに、"]
MAX_SEGMENT_LEN = 200


def segment(text: str) -> List[str]:
    if not text:
        return []

    # 句点・改行・！？で分割
    parts = re.split(r'(?<=[。！？\n])', text)
    sentences = []

    for part in parts:
        part = part.strip()
        if not part:
            continue
        # 接続詞で再分割（再帰なし・ループで処理）
        sub = _split_by_conjunctions(part)
        sentences.extend(sub)

    # 長すぎる文を読点で分割
    result = []
    for s in sentences:
        s = s.strip()
        if not s:
            continue
        if len(s) > MAX_SEGMENT_LEN:
            chunks = re.split(r'(?<=、)', s)
            result.extend([c.strip() for c in chunks if c.strip()])
        else:
            result.append(s)

    return result if result else [text.strip()]


def _split_by_conjunctions(text: str) -> List[str]:
    """接続詞でテキストを分割（ループ実装・再帰なし）"""
    result = []
    remaining = text

    while remaining:
        found = False
        for conj in CONJUNCTIONS:
            idx = remaining.find(conj)
            if idx > 0:  # 先頭一致は除外（0の場合はスキップ）
                before = remaining[:idx].strip()
                if before:
                    result.append(before)
                remaining = remaining[idx:].strip()
                found = True
                break
        if not found:
            # どの接続詞にも一致しなかったら残りを全部追加して終了
            if remaining.strip():
                result.append(remaining.strip())
            break

    return result if result else [text]
