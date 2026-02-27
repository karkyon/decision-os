"""
分解エンジン メインオーケストレーター

フロー:
  normalize → segment → classify(intent/domain) → resolve → score

変更点（Phase 1.5 精度改善）:
- classify_intent / classify_domain が raw_score を返すようになった
- scorer.calc_confidence を呼び出す形に変更
- item に intent_raw / domain_raw を保持
"""
from .normalizer import normalize
from .segmenter import segment
from .classifier import classify_intent, classify_domain
from .resolver import resolve
from .scorer import calc_confidence, confidence_label


def analyze(text: str) -> list[dict]:
    """
    テキストを分解・分類して ITEM リストを返す。

    Returns
    -------
    list[dict]
        [
            {
                "text": str,
                "intent": str,
                "domain": str,
                "intent_raw": float,
                "domain_raw": float,
                "confidence": float,
                "confidence_label": str,
                "ai_assisted": bool,
            },
            ...
        ]
    """
    # 1. 正規化
    normalized = normalize(text)

    # 2. 分解
    segments = segment(normalized)

    # 3. 分類
    items = []
    for seg in segments:
        intent_code, intent_raw = classify_intent(seg)
        domain_code, domain_raw = classify_domain(seg)

        confidence = calc_confidence(
            text=seg,
            intent_code=intent_code,
            intent_raw=intent_raw,
            domain_code=domain_code,
            domain_raw=domain_raw,
        )

        items.append({
            "text":             seg,
            "intent":           intent_code,
            "domain":           domain_code,
            "intent_raw":       intent_raw,
            "domain_raw":       domain_raw,
            "confidence":       confidence,
            "confidence_label": confidence_label(confidence),
            "ai_assisted":      False,
        })

    # 4. 文間関係の解決
    items = resolve(items)

    # 5. 信頼度が低い場合は AI 補助（ai_assist.py が存在する場合のみ）
    items = _maybe_ai_assist(items)

    return items


def _maybe_ai_assist(items: list[dict]) -> list[dict]:
    """
    信頼度 < 0.40 のアイテムに AI 補助分類を適用する。
    ai_assist モジュールが存在しない場合はスキップ。
    """
    try:
        from .ai_assist import ai_classify
        for item in items:
            if item["confidence"] < 0.40:
                result = ai_classify(item["text"])
                if result:
                    item.update(result)
                    item["ai_assisted"] = True
    except ImportError:
        pass  # AI補助モジュールなし → スキップ
    return items


if __name__ == "__main__":
    import json

    sample_texts = [
        "ログインするとエラーが出て先に進めません。認証画面が壊れているようです。",
        "検索機能を追加してほしいです。また、ページネーションも実装できますか？",
        "APIのレスポンスが遅いです。改善をお願いします。",
        "デプロイの手順を教えてください。",
        "ありがとうございます。共有します。",
    ]

    for text in sample_texts:
        print(f"\n{'='*60}")
        print(f"入力: {text}")
        results = analyze(text)
        for item in results:
            print(
                f"  [{item['intent']:3s}|{item['domain']:5s}] "
                f"conf={item['confidence']:.2f}({item['confidence_label']:10s}) "
                f"ai={item['ai_assisted']} "
                f"| {item['text'][:50]}"
            )
