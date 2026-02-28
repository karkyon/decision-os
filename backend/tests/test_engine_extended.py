import pytest
import sys
sys.path.insert(0, ".")

def test_normalizer_basic():
    from engine.normalizer import normalize
    result = normalize("  ログイン　エラー　が　発生した  ")
    assert isinstance(result, str)
    assert len(result) > 0

def test_normalizer_empty():
    from engine.normalizer import normalize
    result = normalize("")
    assert isinstance(result, str)

def test_segmenter_basic():
    from engine.segmenter import segment
    result = segment("ログインするとエラーが出ます。検索機能も追加してほしい。")
    assert isinstance(result, list)
    assert len(result) >= 1

def test_segmenter_single():
    from engine.segmenter import segment
    result = segment("バグがあります")
    assert isinstance(result, list)

def test_segmenter_empty():
    from engine.segmenter import segment
    result = segment("")
    assert isinstance(result, list)

def test_classifier_bug():
    from engine.classifier import classify_intent
    intent, score = classify_intent("ログインするとエラーが出ます")
    assert intent == "BUG"
    assert score >= 0

def test_classifier_req():
    from engine.classifier import classify_intent
    intent, score = classify_intent("検索機能を追加してほしい")
    assert intent == "REQ"
    assert score >= 0

def test_classifier_fbk():
    from engine.classifier import classify_intent
    intent, score = classify_intent("使いやすくて良かったです")
    assert intent == "FBK"
    assert score >= 0

def test_classifier_score_range():
    """score は 0 以上であること（上限は実装依存）"""
    from engine.classifier import classify_intent
    texts = [
        "アプリがクラッシュします",
        "新機能を追加してほしい",
        "動作が重い",
        "ありがとうございます",
        "使い方を教えてください",
    ]
    for text in texts:
        intent, score = classify_intent(text)
        assert intent in ("BUG", "REQ", "QST", "IMP", "FBK", "INF")
        assert score >= 0

def test_classify_multiple():
    from engine.classifier import classify_intent
    results = []
    for text in ["バグがあります", "追加してほしい", "助かります", "使いにくい"]:
        intent, score = classify_intent(text)
        results.append((intent, score))
    assert all(i in ("BUG", "REQ", "QST", "IMP", "FBK", "INF") for i, _ in results)
