import sys, os
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from engine.main import analyze

def test_analyze_bug():
    result = analyze("ログインするとエラーが出て使えない")
    assert len(result) > 0
    intents = [r["intent"] for r in result]
    assert "BUG" in intents

def test_analyze_request():
    result = analyze("CSV出力機能を追加してほしい")
    assert len(result) > 0
    assert result[0]["intent"] == "REQ"

def test_analyze_question():
    result = analyze("この機能はいつ対応できますか？")
    assert len(result) > 0
    assert result[0]["intent"] == "QST"

def test_confidence_range():
    result = analyze("改善してほしい")
    for item in result:
        assert 0.0 <= item["confidence"] <= 1.0
