"""
分解エンジン メインオーケストレーター
RAW_TEXT → List[AnalysisResult]

使用法:
    from engine.main import analyze_text
    results = analyze_text("エラーが出ています。ログイン画面が表示されません。")
"""
from typing import List, Dict
from .normalizer import normalize
from .segmenter import segment
from .classifier import classify_intent, classify_domain
from .scorer import calc_confidence, needs_ai_assist


def analyze_text(raw_text: str) -> List[Dict]:
    """
    テキストを分解・分類し、ITEMのリストを返す

    Returns:
        [
            {
                "text": str,
                "intent_code": str,
                "domain_code": str,
                "confidence": float,
                "needs_ai_assist": bool,
            },
            ...
        ]
    """
    # Step1: 正規化
    normalized = normalize(raw_text)

    # Step2: 分割
    sentences = segment(normalized)

    results = []
    for sentence in sentences:
        # Step3: 分類
        intent_code, intent_score = classify_intent(sentence)
        domain_code, domain_score = classify_domain(sentence)

        # Step4: 信頼度算出
        confidence = calc_confidence(
            text=sentence,
            intent_raw_score=intent_score,
            domain_raw_score=domain_score,
            text_length=len(sentence),
        )

        results.append({
            "text": sentence,
            "intent_code": intent_code,
            "domain_code": domain_code,
            "confidence": confidence,
            "needs_ai_assist": needs_ai_assist(confidence),
        })

    return results
