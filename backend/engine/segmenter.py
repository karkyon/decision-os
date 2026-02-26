"""
Segmenter: テキストを意味単位に分解する
"""
import re

CONJUNCTIONS = [
    "しかし", "ただし", "また", "なお", "一方",
    "ちなみに", "さらに", "加えて", "それから",
]

def segment(text: str) -> list[str]:
    """テキストを文単位に分解する"""
    lines = text.split("\n")
    results = []
    for line in lines:
        # 句点・感嘆符・疑問符で分割
        parts = re.split(r"[。！？!?]", line)
        for part in parts:
            part = part.strip()
            if not part:
                continue
            # 接続詞での分割
            split_done = False
            for conj in CONJUNCTIONS:
                if conj in part and not part.startswith(conj):
                    idx = part.index(conj)
                    before = part[:idx].strip()
                    after = part[idx:].strip()
                    if before:
                        results.append(before)
                    if after:
                        results.append(after)
                    split_done = True
                    break
            if not split_done:
                results.append(part)
    return [r for r in results if len(r) > 1]
