"""
Classifier v2: Intent / Domain の分類
- スコア累積方式（先着順 → 全キーワードを集計）
- 正規表現パターンマッチに +2.0 の重み
- 優先順位テーブルで同スコア時の決定
- 信頼度スコアは scorer.py が担当
"""
import re
import json
import math
from pathlib import Path
from typing import Tuple

# Intent 優先順位（同スコア時に上位を選択）
INTENT_PRIORITY = ["BUG", "TSK", "REQ", "IMP", "QST", "FBK", "MIS", "INF"]

# ─── インライン辞書（JSON読み込み失敗時のフォールバック）────────────────────
INTENT_DICT_INLINE = {
    "BUG": {
        "keywords": [
            # エラー系
            "エラー", "error", "Error", "ERROR", "例外", "exception",
            "スタックトレース", "stack trace", "500", "404", "400", "503",
            # 動作不良系
            "動かない", "動作しない", "起動しない", "落ちる", "クラッシュ",
            "フリーズ", "ハング", "止まる", "止まった", "応答しない", "応答なし",
            "反応しない", "反応なし", "固まる", "固まった",
            # 失敗系
            "失敗", "失敗する", "失敗した", "できない", "できません",
            "うまくいかない", "うまくいきません", "正常に動かない",
            # バグ・不具合系
            "バグ", "bug", "Bug", "不具合", "障害", "インシデント",
            "問題が発生", "問題が起きて", "壊れ", "壊れた", "壊れている",
            "おかしい", "おかしな", "異常", "異常動作", "誤動作",
            # 接続・認証エラー
            "接続できない", "接続エラー", "接続失敗", "ログインできない",
            "認証エラー", "認証に失敗", "タイムアウト", "timeout",
            # 表示・UI エラー
            "表示されない", "表示されません", "表示がおかしい",
            "画面が崩れ", "画面が真っ白", "真っ白", "白画面",
            # データ系
            "保存できない", "保存されない", "消えた", "消えてしまった",
            "データが消え", "更新されない", "反映されない",
            # 症状説明
            "〜しない", "〜ない", "not working", "broken", "failed",
        ],
        "patterns": [
            r"エラー(?:が|を|に|で)",
            r"(?:が|を)?(?:落ち|クラッシュ|フリーズ)(?:する|した|しています)",
            r"(?:動か|起動し|ログインでき|接続でき)(?:ない|ません|なかった)",
            r"\d{3}\s*(?:エラー|Error|error)",
            r"(?:NullPointer|TypeError|KeyError|ValueError|AttributeError)",
            r"(?:予期しない|予期せぬ)(?:エラー|動作|挙動)",
        ]
    },
    "TSK": {
        "keywords": [
            "してください", "お願いします", "やってください", "対応してください",
            "確認してください", "チェックしてください", "修正してください",
            "直してください", "調査してください", "調べてください",
            "レビューしてください", "デプロイしてください", "リリースしてください",
            "作業してください", "進めてください",
        ],
        "patterns": [
            r"(?:して|お願い|やって|確認して|対応して)(?:ください|下さい)",
            r"(?:〜を?|を)(?:修正|調査|確認|対応)(?:すること|する必要)",
        ]
    },
    "REQ": {
        "keywords": [
            # 要望・希望表現
            "してほしい", "して欲しい", "して頂きたい", "していただきたい",
            "希望", "要望", "リクエスト", "要求",
            "追加してほしい", "追加して欲しい", "追加を希望",
            "実装してほしい", "実装を希望", "実装して欲しい",
            "できますか", "できるでしょうか", "可能ですか", "可能でしょうか",
            "対応可能", "対応お願い", "対応してほしい",
            # 機能追加系
            "機能を追加", "機能の追加", "新機能", "新しい機能",
            "機能が欲しい", "機能を作って", "機能を付けて",
            "を追加", "の追加", "追加したい", "追加できますか",
            # 開発依頼
            "開発してほしい", "作ってほしい", "作って欲しい",
            "実装してください", "対応をお願い",
            "サポートしてほしい", "サポートを追加",
            # 改善要望
            "改善してほしい", "改善を希望", "改善できますか",
            "対応してもらえますか", "してもらえますか", "してもらいたい",
            # 検討依頼
            "検討してほしい", "検討をお願い", "考えてほしい",
            "導入を希望", "導入してほしい", "採用してほしい",
        ],
        "patterns": [
            r"(?:して|して欲し|していただ)[いきます](?:たい|ます|ません)",
            r"(?:を|の)?(?:追加|実装|開発|導入|対応)(?:して|を)(?:ほしい|欲しい|希望|お願い)",
            r"(?:できます|可能です|対応でき)(?:か|でしょうか)",
            r"〜(?:機能|対応)(?:が|を)(?:ほしい|希望|追加)",
        ]
    },
    "IMP": {
        "keywords": [
            "使いづらい", "使いにくい", "わかりにくい", "分かりにくい",
            "見づらい", "見にくい", "読みにくい", "操作しにくい",
            "遅い", "重い", "もっさり", "パフォーマンスが悪い",
            "改善", "改善してほしい", "もっと", "せめて",
            "UX改善", "UI改善", "使い勝手", "使い勝手が悪い",
            "直して", "なんとかして", "もっとよく",
        ],
        "patterns": [
            r"(?:使い|操作し|見|読み)(?:づらい|にくい)",
            r"(?:もっと|せめて)(?:〜|使い|見|分かり)",
            r"(?:UX|UI|ユーザー)(?:を|の)?(?:改善|向上)",
        ]
    },
    "QST": {
        "keywords": [
            "？", "?", "でしょうか", "ですか", "ますか",
            "教えて", "教えてください", "教えていただけますか",
            "どうすれば", "どうすれば良い", "どうやって", "どうしたら",
            "いつ", "なぜ", "なぜか", "なぜならば", "何故",
            "どこ", "どこで", "どこに", "どのように",
            "仕様", "仕様は", "仕様を教えて", "どういう仕様",
            "確認したい", "確認させてください", "聞きたい",
        ],
        "patterns": [
            r"[？?]\s*$",
            r"(?:どう|どのように)(?:すれば|したら|やって)",
            r"(?:教えて|確認|質問)(?:ください|いただけますか|させてください)",
            r"(?:でしょうか|ですか|ますか)\s*$",
        ]
    },
    "FBK": {
        "keywords": [
            "便利", "いい", "良い", "よい", "助かる", "助かります",
            "使いやすい", "ありがとう", "ありがとうございます",
            "すばらしい", "素晴らしい", "最高", "完璧", "満足",
            "気に入って", "好き", "好評", "評価します", "気持ちいい",
        ],
        "patterns": [
            r"(?:ありがとう|感謝)(?:ございます|します)?",
        ]
    },
    "MIS": {
        "keywords": [
            "違う", "違います", "そうではない", "そうではなく",
            "誤解", "誤解している", "そういう意味ではない",
            "そういうことではなく", "そういうことではありません",
            "違った", "間違い", "間違っている", "間違えた",
        ],
        "patterns": [
            r"(?:そう|そういう意味)ではなく",
            r"(?:違い|誤解)(?:ます|です|している)",
        ]
    },
    "INF": {
        "keywords": [],
        "patterns": []
    },
}

DOMAIN_DICT_INLINE = {
    "UI": {
        "keywords": [
            "画面", "ボタン", "UI", "UX", "デザイン", "レイアウト",
            "表示", "フォーム", "入力欄", "モーダル", "ダイアログ",
            "メニュー", "ナビ", "ナビゲーション", "タブ", "アイコン",
            "フロントエンド", "frontend", "React", "Vue", "CSS", "HTML",
            "スタイル", "色", "フォント", "アニメーション", "検索",
        ],
    },
    "API": {
        "keywords": [
            "API", "エンドポイント", "endpoint", "REST", "GraphQL",
            "リクエスト", "request", "レスポンス", "response",
            "HTTPメソッド", "GET", "POST", "PUT", "PATCH", "DELETE",
            "ステータスコード", "status code", "JSON", "XML",
            "Webhook", "webhook", "swagger", "OpenAPI",
        ],
    },
    "DB": {
        "keywords": [
            "DB", "データベース", "database", "SQL", "クエリ", "query",
            "テーブル", "table", "カラム", "column", "インデックス", "index",
            "マイグレーション", "migration", "PostgreSQL", "MySQL",
            "Redis", "MongoDB", "データ", "保存", "永続化",
        ],
    },
    "AUTH": {
        "keywords": [
            "ログイン", "login", "ログアウト", "logout",
            "認証", "authentication", "auth", "JWT", "token",
            "権限", "permission", "ロール", "role", "アクセス制御",
            "パスワード", "password", "OAuth", "SSO",
            "セッション", "session", "2FA", "MFA",
        ],
    },
    "PERF": {
        "keywords": [
            "遅い", "重い", "パフォーマンス", "performance",
            "速度", "レスポンスタイム", "応答速度", "タイムアウト", "timeout",
            "ボトルネック", "負荷", "スケール", "最適化",
            "CPU", "メモリ", "memory", "キャッシュ", "cache",
        ],
    },
    "SEC": {
        "keywords": [
            "セキュリティ", "security", "脆弱性", "vulnerability",
            "XSS", "CSRF", "SQLインジェクション", "injection",
            "暗号化", "encryption", "TLS", "SSL", "HTTPS",
            "ファイアウォール", "DoS", "DDoS", "不正アクセス",
        ],
    },
    "OPS": {
        "keywords": [
            "運用", "operation", "ops", "監視", "monitoring",
            "ログ", "log", "アラート", "alert", "通知",
            "バックアップ", "backup", "リストア", "restore",
            "設定", "config", "環境変数", "デプロイ", "deploy",
            "CI/CD", "Jenkins", "GitHub Actions",
        ],
    },
    "INFRA": {
        "keywords": [
            "サーバー", "server", "インフラ", "infrastructure",
            "Docker", "Kubernetes", "k8s", "コンテナ", "container",
            "クラウド", "cloud", "AWS", "GCP", "Azure",
            "CPU", "メモリ", "ディスク", "ネットワーク", "network",
            "nginx", "Apache", "ロードバランサー", "load balancer",
        ],
    },
    "SPEC": {
        "keywords": [],
    },
}

# ─── 辞書ロード（JSONファイルがあれば優先、なければインライン）─────────────
_DICT_DIR = Path(__file__).parent / "dictionary"

def _load_or_inline(filename: str, inline: dict) -> dict:
    path = _DICT_DIR / filename
    if path.exists():
        try:
            with open(path, encoding="utf-8") as f:
                data = json.load(f)
            # JSON形式: {"BUG": {"keywords": [...], "patterns": [...]}, ...}
            if isinstance(data, dict) and all(
                isinstance(v, dict) for v in data.values()
            ):
                return data
        except Exception:
            pass
    return inline

_intent_dict = None
_domain_dict = None

def _get_intent_dict() -> dict:
    global _intent_dict
    if _intent_dict is None:
        _intent_dict = _load_or_inline("intent.json", INTENT_DICT_INLINE)
    return _intent_dict

def _get_domain_dict() -> dict:
    global _domain_dict
    if _domain_dict is None:
        _domain_dict = _load_or_inline("domain.json", DOMAIN_DICT_INLINE)
    return _domain_dict

def reload_dicts():
    """辞書キャッシュをリセット（学習ループ用）"""
    global _intent_dict, _domain_dict
    _intent_dict = None
    _domain_dict = None


# ─── 分類本体 ────────────────────────────────────────────────────────────────

def classify_intent(text: str) -> tuple:
    """(intent_code, raw_score) を返す"""
    d = _get_intent_dict()
    scores = {code: 0.0 for code in d}

    for code, rules in d.items():
        # キーワードマッチ: +1.0 per hit
        for kw in rules.get("keywords", []):
            if kw in text:
                scores[code] += 1.0
        # パターンマッチ: +2.0 per hit（より確実な証拠）
        for pat in rules.get("patterns", []):
            try:
                if re.search(pat, text):
                    scores[code] += 2.0
            except re.error:
                pass

    # 最高スコアを取得、同スコアは優先順位で決定
    best_code = "INF"
    best_score = 0.0
    for code in INTENT_PRIORITY:
        if code in scores and scores[code] > best_score:
            best_code = code
            best_score = scores[code]

    return best_code, best_score


def classify_domain(text: str) -> tuple:
    """(domain_code, raw_score) を返す"""
    d = _get_domain_dict()
    scores = {code: 0.0 for code in d}

    for code, rules in d.items():
        for kw in rules.get("keywords", []):
            if kw in text:
                scores[code] += 1.0
        for pat in rules.get("patterns", []):
            try:
                if re.search(pat, text):
                    scores[code] += 2.0
            except re.error:
                pass

    best_code = "SPEC"
    best_score = 0.0
    for code, score in scores.items():
        if score > best_score:
            best_code = code
            best_score = score

    return best_code, best_score


def classify(text: str) -> dict:
    """後方互換API: {'intent', 'domain'} を返す"""
    intent, _ = classify_intent(text)
    domain, _ = classify_domain(text)
    return {"intent": intent, "domain": domain}


# ─── 自己テスト ──────────────────────────────────────────────────────────────
if __name__ == "__main__":
    tests = [
        ("ログインするとエラーが出て進めません",      "BUG",  "AUTH"),
        ("検索機能を追加してほしいです",              "REQ",  "UI"),
        ("APIのレスポンスが遅いです",                 "IMP",  "PERF"),
        ("パスワードのリセット方法を教えてください",  "QST",  "AUTH"),
        ("ダッシュボードの画面が崩れている",          "BUG",  "UI"),
        ("バッチ処理の実装をお願いします",            "TSK",  "OPS"),
        ("使いやすくて助かっています",                "FBK",  "UI"),
        ("そういう意味ではなく、別の話です",          "MIS",  "SPEC"),
        ("Dockerコンテナが起動しない",               "BUG",  "INFRA"),
        ("検索APIのエンドポイントを追加できますか",   "REQ",  "API"),
    ]
    correct = 0
    print(f"\n{'テキスト':<40} {'期待':^8} {'結果':^8} {'スコア':^8}")
    print("-" * 72)
    for text, exp_i, exp_d in tests:
        ic, is_ = classify_intent(text)
        dc, ds = classify_domain(text)
        ok = "✅" if ic == exp_i else "❌"
        correct += 1 if ic == exp_i else 0
        print(f"{text[:38]:<40} {exp_i:^8} {ic:^8} {is_:^8.1f} {ok}")
    print(f"\nIntent精度: {correct}/{len(tests)} = {correct/len(tests)*100:.0f}%")
