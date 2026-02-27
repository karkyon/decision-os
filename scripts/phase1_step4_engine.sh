#!/bin/bash
# ============================================================
# Phase 1 MVP - Step 4: 分解エンジン実装
# Normalizer → Segmenter → Classifier → Scorer
# ============================================================
set -e

PROJECT="$HOME/projects/decision-os"
ENGINE="$PROJECT/backend/engine"

echo "=== Step 4: 分解エンジン実装 ==="

mkdir -p "$ENGINE/dictionary"

# ---- 辞書ファイル ----
cat > "$ENGINE/dictionary/intent.json" << 'EOF'
{
  "BUG": {
    "keywords": ["エラー","バグ","不具合","おかしい","壊れ","失敗","動かない","動作しない","例外","クラッシュ","落ちる","固まる","表示されない","出ない"],
    "patterns": ["エラーが(出|発生|起き)", "うまく(いかない|動かない)", "(正しく|正常に)動かない"]
  },
  "REQ": {
    "keywords": ["ほしい","したい","追加","実装","対応","機能","要望","欲しい","作って","入れて","できるように","できれば","あれば"],
    "patterns": ["〜(し|き)たい", "〜(が|を)ほしい", "(追加|実装)(して|をお願い)"]
  },
  "IMP": {
    "keywords": ["改善","使いにくい","わかりにくい","もっと","変えて","直して","見直し","整理","最適化","効率"],
    "patterns": ["(もっと|より)(使|見|わかり)やすく"]
  },
  "QST": {
    "keywords": ["ですか","でしょうか","？","どう","どの","何","いつ","なぜ","どうして","確認","教えて","聞きたい"],
    "patterns": ["(〜)?(は|が)(どう|何|いつ|なぜ)"]
  },
  "MIS": {
    "keywords": ["思っていた","だと思う","違う","認識","そうじゃない","ではなく","異なる"],
    "patterns": ["(〜と)思っていた(が|ら|けど)", "認識(が|の)ズレ"]
  },
  "FBK": {
    "keywords": ["便利","良い","使いやすい","助かる","ありがとう","好評","評価","満足","気に入って"],
    "patterns": []
  },
  "INF": {
    "keywords": ["共有","報告","連絡","お知らせ","ご連絡","現状","状況","FYI"],
    "patterns": []
  },
  "TSK": {
    "keywords": ["してください","お願い","やる","やって","対応よろしく","確認してください","実施"],
    "patterns": ["(〜を?)(して|やって)ください"]
  }
}
EOF

cat > "$ENGINE/dictionary/domain.json" << 'EOF'
{
  "UI": {
    "keywords": ["画面","UI","ボタン","表示","フォーム","レイアウト","色","デザイン","メニュー","ページ","アイコン","モーダル","テーブル","リスト","入力欄"]
  },
  "API": {
    "keywords": ["API","エンドポイント","レスポンス","リクエスト","HTTP","REST","JSON","パラメータ","ヘッダー","ステータスコード"]
  },
  "DB": {
    "keywords": ["DB","データベース","テーブル","SQL","クエリ","レコード","カラム","インデックス","マイグレーション","トランザクション"]
  },
  "AUTH": {
    "keywords": ["認証","ログイン","ログアウト","権限","パスワード","トークン","JWT","セッション","アカウント","ユーザー管理"]
  },
  "PERF": {
    "keywords": ["遅い","重い","パフォーマンス","速度","応答","タイムアウト","最適化","負荷","スロー","レイテンシ"]
  },
  "SEC": {
    "keywords": ["セキュリティ","脆弱性","XSS","CSRF","インジェクション","暗号化","SSL","TLS","不正アクセス"]
  },
  "OPS": {
    "keywords": ["デプロイ","サーバー","インフラ","Docker","CI/CD","監視","ログ","アラート","障害","本番","環境"]
  },
  "SPEC": {
    "keywords": ["仕様","設計","要件","定義","ドキュメント","フロー","プロセス","ルール","ポリシー"]
  }
}
EOF

# ---- normalizer.py ----
cat > "$ENGINE/normalizer.py" << 'EOF'
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
EOF

# ---- segmenter.py ----
cat > "$ENGINE/segmenter.py" << 'EOF'
"""
Segmenter: 文境界でテキストを分割
- 句点（。）
- 改行
- 接続詞境界
優先度: 意味の完全な分割 > 長さ均一化
"""
import re
from typing import List


# 接続詞: この後は独立文として扱う
CONJUNCTIONS = ["また、", "そして、", "ただし、", "なお、", "一方、", "しかし、", "それと、", "さらに、"]

MAX_SEGMENT_LEN = 200  # 超えたら強制分割


def segment(text: str) -> List[str]:
    if not text:
        return []

    # まず句点・改行で分割
    parts = re.split(r"(?<=[。！？\n])", text)
    sentences = []

    for part in parts:
        part = part.strip()
        if not part:
            continue

        # 接続詞で再分割
        sub = _split_by_conjunctions(part)
        sentences.extend(sub)

    # 空文字除去・長すぎる文を分割
    result = []
    for s in sentences:
        s = s.strip()
        if not s:
            continue
        if len(s) > MAX_SEGMENT_LEN:
            # 読点で分割を試みる
            chunks = re.split(r"(?<=、)", s)
            result.extend([c.strip() for c in chunks if c.strip()])
        else:
            result.append(s)

    return result if result else [text.strip()]


def _split_by_conjunctions(text: str) -> List[str]:
    for conj in CONJUNCTIONS:
        if conj in text:
            idx = text.index(conj)
            before = text[:idx].strip()
            after = text[idx:].strip()
            result = []
            if before:
                result.append(before)
            if after:
                result.extend(_split_by_conjunctions(after))
            return result
    return [text]
EOF

# ---- classifier.py ----
cat > "$ENGINE/classifier.py" << 'EOF'
"""
Classifier: Intent / Domain の分類
- 辞書マッチング（キーワード + 正規表現パターン）
- 信頼度スコアは Scorer が担当
"""
import json
import re
from typing import Tuple
from pathlib import Path

DICT_DIR = Path(__file__).parent / "dictionary"


def _load_dict(name: str) -> dict:
    path = DICT_DIR / f"{name}.json"
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


_intent_dict: dict = None
_domain_dict: dict = None


def _get_intent_dict() -> dict:
    global _intent_dict
    if _intent_dict is None:
        _intent_dict = _load_dict("intent")
    return _intent_dict


def _get_domain_dict() -> dict:
    global _domain_dict
    if _domain_dict is None:
        _domain_dict = _load_dict("domain")
    return _domain_dict


def classify_intent(text: str) -> Tuple[str, float]:
    """Intent分類。 (intent_code, raw_score) を返す"""
    d = _get_intent_dict()
    scores = {code: 0.0 for code in d}

    for code, rules in d.items():
        for kw in rules.get("keywords", []):
            if kw in text:
                scores[code] += 1.0

        for pat in rules.get("patterns", []):
            if re.search(pat, text):
                scores[code] += 1.5  # パターンマッチは高めに

    best_code = max(scores, key=scores.get)
    best_score = scores[best_code]

    # スコアが0ならINFにフォールバック
    if best_score == 0:
        return "INF", 0.0

    return best_code, best_score


def classify_domain(text: str) -> Tuple[str, float]:
    """Domain分類。 (domain_code, raw_score) を返す"""
    d = _get_domain_dict()
    scores = {code: 0.0 for code in d}

    for code, rules in d.items():
        for kw in rules.get("keywords", []):
            if kw in text:
                scores[code] += 1.0

    best_code = max(scores, key=scores.get)
    best_score = scores[best_code]

    if best_score == 0:
        return "SPEC", 0.0

    return best_code, best_score
EOF

# ---- scorer.py ----
cat > "$ENGINE/scorer.py" << 'EOF'
"""
Scorer: 分類信頼度スコアの算出
score = keyword_match_rate * 0.4 + pattern_match * 0.3 + context_consistency * 0.3
閾値: 0.75未満はAI補助候補としてフラグ
"""


def calc_confidence(
    text: str,
    intent_raw_score: float,
    domain_raw_score: float,
    text_length: int,
) -> float:
    """
    0.0 ~ 1.0 の信頼度スコアを返す
    """
    # キーワードヒット数から基本スコア算出（5ヒットで0.5相当）
    base = min(intent_raw_score / 5.0, 0.6)

    # ドメインが特定できた場合ボーナス
    domain_bonus = 0.15 if domain_raw_score > 0 else 0.0

    # 文長ボーナス（短すぎる文は信頼度低め）
    length_bonus = 0.0
    if text_length >= 10:
        length_bonus = 0.1
    if text_length >= 30:
        length_bonus = 0.15

    score = base + domain_bonus + length_bonus
    return round(min(score, 1.0), 3)


AI_ASSIST_THRESHOLD = 0.75

def needs_ai_assist(confidence: float) -> bool:
    return confidence < AI_ASSIST_THRESHOLD
EOF

# ---- engine/main.py（オーケストレーター）----
cat > "$ENGINE/main.py" << 'EOF'
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
EOF

cat > "$ENGINE/__init__.py" << 'EOF'
from .main import analyze_text
EOF

echo "✅ 分解エンジン生成完了"

# ---- エンジン動作テスト ----
cd "$PROJECT/backend"
source .venv/bin/activate

python3 - << 'PYEOF'
import sys
sys.path.insert(0, ".")
from engine.main import analyze_text

test_text = """
ログイン画面でエラーが出ています。
パスワードを入力してもログインできない状態です。
CSV出力機能を追加してほしいです。
また、ダッシュボードの表示が遅い気がします。
"""

results = analyze_text(test_text)
print("\n=== 分解エンジンテスト結果 ===")
for i, r in enumerate(results):
    ai_flag = "🤖AI補助" if r["needs_ai_assist"] else "✅"
    print(f"[{i+1}] {ai_flag} {r['intent_code']}/{r['domain_code']} (conf:{r['confidence']:.2f})")
    print(f"     テキスト: {r['text'][:60]}")
print("\n✅ 分解エンジン動作確認完了")
PYEOF

echo "✅✅✅ Step 4 完了: 分解エンジン（Normalizer/Segmenter/Classifier/Scorer）"
