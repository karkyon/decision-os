"""
Engine Main v2: 分解エンジンのオーケストレーター
- classify_intent/classify_domain の raw_score を scorer に流す
"""
from engine.normalizer  import normalize
from engine.segmenter   import segment
from engine.classifier  import classify_intent, classify_domain
from engine.scorer      import score as calc_score, get_confidence_label

def analyze(text: str) -> list[dict]:
    """テキストを受け取り、分解・分類結果のリストを返す"""
    text = normalize(text)
    sentences = segment(text)

    items = []
    for i, sent in enumerate(sentences):
        intent_code, intent_raw = classify_intent(sent)
        domain_code, domain_raw = classify_domain(sent)

        item = {
            "text":              sent,
            "position":          i,
            "intent":            intent_code,
            "domain":            domain_code,
            "intent_raw_score":  intent_raw,
            "domain_raw_score":  domain_raw,
        }
        item["confidence"]       = calc_score(item)
        item["confidence_label"] = get_confidence_label(item["confidence"])
        items.append(item)

    return items


if __name__ == "__main__":
    sample = input("テキストを入力してください > ")
    from pprint import pprint
    pprint(analyze(sample))
