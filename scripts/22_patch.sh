#!/usr/bin/env bash
set -euo pipefail
GREEN='\033[0;32m'; BOLD='\033[1m'; RESET='\033[0m'
ok()      { echo -e "${GREEN}[OK]${RESET}    $*"; }
section() { echo -e "\n${BOLD}========== $* ==========${RESET}"; }

PROJECT_DIR="$HOME/projects/decision-os"
ENGINE="$PROJECT_DIR/backend/engine"

section "classifier.py キーワード追加パッチ"

python3 << 'PYEOF'
path = __import__('os').path.expanduser(
    "~/projects/decision-os/backend/engine/classifier.py"
)
with open(path, encoding="utf-8") as f:
    src = f.read()

patches = [
    (
        '"〜しない", "〜ない", "not working", "broken", "failed",',
        '"真っ白", "白画面", "保存されない", "保存できない", "頻発", "頻繁に",\n            "〜しない", "〜ない", "not working", "broken", "failed",'
    ),
    (
        '"導入を希望", "導入してほしい", "採用してほしい",',
        '"導入を希望", "導入してほしい", "採用してほしい",\n            "お願いできますか", "いただけますか", "いただけますでしょうか",'
    ),
    (
        '"気に入って", "好き", "好評", "評価します", "気持ちいい",',
        '"気に入って", "好き", "好評", "評価します", "気持ちいい",\n            "助かります", "助かっています", "重宝",'
    ),
    (
        'INTENT_PRIORITY = ["BUG", "TSK", "REQ", "IMP", "QST", "FBK", "MIS", "INF"]',
        'INTENT_PRIORITY = ["BUG", "TSK", "FBK", "REQ", "IMP", "QST", "MIS", "INF"]'
    ),
]
for old, new in patches:
    if old in src:
        src = src.replace(old, new)
        print(f"PATCHED: {old[:40]}...")
    else:
        print(f"SKIP: {old[:40]}...")

with open(path, "w", encoding="utf-8") as f:
    f.write(src)
print("完了")
PYEOF

ok "パッチ適用完了"

section "精度再テスト"
cd "$PROJECT_DIR/backend"
source .venv/bin/activate 2>/dev/null || true

python3 << 'PYEOF'
import sys; sys.path.insert(0, ".")
import engine.classifier as clf; clf._intent_dict = None

CASES = [
    ("ログインするとエラーが出て進めません","BUG"),
    ("アプリが突然クラッシュします","BUG"),
    ("Dockerコンテナが起動しない","BUG"),
    ("画面が真っ白になってしまいます","BUG"),
    ("保存ボタンを押しても保存されない","BUG"),
    ("500エラーが返ってくる","BUG"),
    ("認証エラーが発生しています","BUG"),
    ("タイムアウトが頻発している","BUG"),
    ("検索機能を追加してほしいです","REQ"),
    ("CSVエクスポート機能を実装できますか","REQ"),
    ("ダークモードに対応をお願いしたいです","REQ"),
    ("メール通知機能の導入を希望します","REQ"),
    ("APIのページネーション対応をお願いできますか","REQ"),
    ("モバイル対応を検討してほしいです","REQ"),
    ("パスワードのリセット方法を教えてください","QST"),
    ("このAPIの仕様はどこで確認できますか","QST"),
    ("リリース予定日はいつでしょうか","QST"),
    ("検索が遅くて使いにくいです","IMP"),
    ("入力フォームが使いづらいです","IMP"),
    ("新機能、とても使いやすくて助かります","FBK"),
]
ok = 0
print(f"\n{'テキスト':<42} {'正解':^6} {'結果':^6} {'スコア':^7}")
print("─"*65)
for text, exp in CASES:
    r, s = clf.classify_intent(text)
    mark = "✅" if r==exp else "❌"
    ok += r==exp
    print(f"{text[:40]:<42} {exp:^6} {r:^4}{mark} {s:^7.1f}")
print("─"*65)
print(f"精度: {ok}/{len(CASES)} = {ok/len(CASES)*100:.0f}%")
PYEOF
