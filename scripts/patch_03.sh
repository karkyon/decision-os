#!/usr/bin/env bash
# =============================================================================
# decision-os  /  patch_03.sh
# 03_backend_setup.sh の不具合を直接修正するパッチ
# 実行方法: bash patch_03.sh
# =============================================================================
set -euo pipefail

GREEN='\033[0;32m'; CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'
success() { echo -e "${GREEN}[OK]${RESET}    $*"; }
info()    { echo -e "${CYAN}[INFO]${RESET}  $*"; }
section() { echo -e "\n${BOLD}========== $* ==========${RESET}"; }

PROJECT_DIR="$HOME/projects/decision-os"
cd "$PROJECT_DIR/backend"
source .venv/bin/activate

# ---------- 1. 辞書ディレクトリ・ファイルの作成 ----------
section "1. 辞書ファイルの作成"

mkdir -p dictionary/common dictionary/dev dictionary/infra
echo '{}' > dictionary/live.json

cat > dictionary/common/intent_keywords.yml << 'EOF'
entries:
  - { term: "エラー",       intent_hint: "BUG", priority: 5 }
  - { term: "動かない",     intent_hint: "BUG", priority: 5 }
  - { term: "落ちる",       intent_hint: "BUG", priority: 5 }
  - { term: "不具合",       intent_hint: "BUG", priority: 5 }
  - { term: "してほしい",   intent_hint: "REQ", priority: 4 }
  - { term: "追加",         intent_hint: "REQ", priority: 3 }
  - { term: "改善",         intent_hint: "IMP", priority: 3 }
  - { term: "使いづらい",   intent_hint: "IMP", priority: 4 }
  - { term: "？",           intent_hint: "QST", priority: 4 }
  - { term: "でしょうか",   intent_hint: "QST", priority: 4 }
EOF

cat > dictionary/dev/domain_terms.yml << 'EOF'
entries:
  - { term: "API",         domain: "BACKEND" }
  - { term: "画面",        domain: "UI" }
  - { term: "DB",          domain: "DATABASE" }
  - { term: "SQL",         domain: "DATABASE" }
  - { term: "ログイン",    domain: "AUTH" }
  - { term: "デプロイ",    domain: "INFRA" }
  - { term: "レイテンシ",  domain: "PERF" }
EOF

success "辞書ファイルを作成しました"

# ---------- 2. classifier.py を修正（優先順位 + QSTを疑問符で最優先判定）----------
section "2. classifier.py の修正（QST優先順位バグ）"

cat > engine/classifier.py << 'EOF'
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
EOF

success "classifier.py を修正しました"

# ---------- 3. テスト再実行 ----------
section "3. テスト再実行"

python -m pytest tests/test_engine.py -v 2>&1

section "パッチ完了"
echo -e "${GREEN}"
echo "  ✔ 辞書ファイル作成（dictionary/）"
echo "  ✔ classifier.py 修正（QST優先順位）"
echo -e "${RESET}"
echo "次のステップ:"
echo "  bash 04_frontend_setup.sh"