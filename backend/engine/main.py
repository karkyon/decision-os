"""
Engine Main: 分解エンジンのオーケストレーター
"""
from engine.normalizer import normalize
from engine.segmenter  import segment
from engine.classifier import classify
from engine.scorer     import score

def analyze(text: str) -> list[dict]:
    """テキストを受け取り、分解・分類結果のリストを返す"""
    text = normalize(text)
    sentences = segment(text)

    items = []
    for i, sent in enumerate(sentences):
        result = classify(sent)
        result["text"] = sent
        result["position"] = i
        result["confidence"] = score(result)
        items.append(result)

    return items

if __name__ == "__main__":
    sample = input("テキストを入力してください > ")
    from pprint import pprint
    pprint(analyze(sample))
