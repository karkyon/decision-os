"""
Classifier: Intent / Domain / Semantic の3軸分類

優先順位: BUG > QST > TSK > REQ > IMP > FBK > MIS > INF
疑問文は要望より優先度が高い。
文末の「？」「ですか」「でしょうか」「いつ」などは疑問文の強いシグナル。
"""

# ----- Intent 判定設定 -----
# (intent_code, keywords, 文末疑問チェック)
# 文末疑問チェック=Trueの場合、キーワードに加えて文末「？」も確認する
INTENT_RULES = [
    ("BUG", ["エラー", "落ちる", "動かない", "失敗", "バグ", "不具合",
             "壊れ", "おかしい", "異常", "エラーが出"], False),
    ("QST", ["？", "?", "でしょうか", "ですか", "教えてください",
             "いつ", "どうすれば", "どうやって", "どこで", "なぜ"], False),
    ("TSK", ["してください", "お願いします", "やってください",
             "対応してください"], False),
    ("REQ", ["してほしい", "追加してほしい", "改善してほしい", "希望します",
             "要望", "ほしい", "欲しい", "対応可能ですか", "実装してほしい"], False),
    ("IMP", ["使いづらい", "分かりにくい", "遅い", "重い",
             "もっと", "せめて", "直してほしい"], False),
    ("FBK", ["便利", "助かる", "使いやすい", "ありがとう"], False),
    ("MIS", ["違う", "そうではなく", "誤解", "そういう意味ではない"], False),
]

# ----- QST 強化：これらが含まれたら文脈に関わらずQST ----------
QST_STRONG = ["？", "?", "でしょうか", "ですか", "いつ対応", "いつ頃", "どうすれば"]

# ----- Domain キーワード辞書 -----
DOMAIN_KEYWORDS = {
    "UI":       ["画面", "ボタン", "UI", "デザイン", "レイアウト", "表示"],
    "BACKEND":  ["API", "サーバー", "エンドポイント", "レスポンス"],
    "DATABASE": ["DB", "SQL", "データベース", "データ", "保存", "検索"],
    "AUTH":     ["ログイン", "認証", "権限", "パスワード", "アカウント"],
    "PERF":     ["遅い", "重い", "パフォーマンス", "速度", "タイムアウト"],
    "INFRA":    ["サーバー", "CPU", "メモリ", "Docker", "デプロイ", "インフラ"],
    "OPS":      ["運用", "設定", "環境", "バックアップ"],
}


def detect_intent(text: str) -> str:
    # QST強化チェック：強いシグナルが含まれたら即QST
    if any(sig in text for sig in QST_STRONG):
        return "QST"

    # 通常ルールで順番に評価
    for intent, keywords, _ in INTENT_RULES:
        if any(kw in text for kw in keywords):
            return intent

    return "INF"


def detect_domain(text: str) -> str:
    for domain, keywords in DOMAIN_KEYWORDS.items():
        if any(kw in text for kw in keywords):
            return domain
    return "GENERAL"


def classify(text: str) -> dict:
    return {
        "intent": detect_intent(text),
        "domain": detect_domain(text),
    }
