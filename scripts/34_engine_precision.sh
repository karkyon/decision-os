#!/usr/bin/env bash
# =============================================================================
# 34_engine_precision.sh — 分解エンジン精度改善（エッジケース対応）
# 修正対象:
#   1. INF落ち → 口語・過去形・変化表現をBUG/IMPに追加
#   2. FBK誤爆 → 「助かります」をREQへ、FBKは純粋な感謝表現のみに絞る
#   3. MIS弱い → 「違う挙動」「思ってた」などを強化
# =============================================================================
set -euo pipefail
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BOLD='\033[1m'; RESET='\033[0m'
ok()      { echo -e "${GREEN}[OK]${RESET}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
section() { echo -e "\n${BOLD}========== $* ==========${RESET}"; }

PROJECT_DIR="$HOME/projects/decision-os"
ENGINE="$PROJECT_DIR/backend/engine"
BACKUP="$PROJECT_DIR/backup_engine_34_$(date +%Y%m%d_%H%M%S)"

mkdir -p "$BACKUP"
cp -r "$ENGINE" "$BACKUP/"
echo "バックアップ: $BACKUP"

cd "$PROJECT_DIR/backend"
source .venv/bin/activate

section "1. classifier.py パッチ適用"

python3 << 'PYEOF'
import re

path = __import__('os').path.expanduser(
    "~/projects/decision-os/backend/engine/classifier.py"
)
with open(path, encoding="utf-8") as f:
    src = f.read()

patches = [
    # ── BUG: 口語・過去形・変化表現を追加 ──────────────────────────────────
    (
        '"〜しない", "〜ない", "not working", "broken", "failed",',
        '''"なにも起きない", "何も起きない", "なにも変わらない",
            "切れる", "切れた", "切れることがある", "切れてしまう",
            "起きない", "動かなくなった", "動かなくなっている",
            "落ちることがある", "落ちることがあります",
            "〜しない", "〜ない", "not working", "broken", "failed",'''
    ),
    # ── BUG: パターンに「〜ことがある」系を追加 ─────────────────────────────
    (
        r'r"(?:動か|起動し|ログインでき|接続でき)(?:ない|ません|なかった)",',
        r'''r"(?:動か|起動し|ログインでき|接続でき)(?:ない|ません|なかった)",
            r"(?:切れ|落ち|止まり|固まり)(?:ることがある|ることがあります|た)",
            r"(?:なにも|何も)(?:起き|変わら)(?:ない|ません)",'''
    ),
    # ── IMP: 口語・過去形・変化表現を追加 ──────────────────────────────────
    (
        '"使いにくい", "わかりにくい", "もっと", "変えて", "直して", "見直し",',
        '''"使いにくい", "わかりにくい", "もっと", "変えて", "直して", "見直し",
            "重くなった", "重くなっている", "遅くなった", "遅くなっている",
            "使いにくくなった", "使いにくくなっている",
            "以前より", "前より", "前の方が", "前のUIの方が",
            "なんか重い", "なんか遅い", "気がします", "気がする",'''
    ),
    # ── FBK: 「助かります」「助かる」を削除（REQ側に移動） ─────────────────
    (
        '"助かる", "助かります", "助かっています", "重宝",',
        '"重宝",'
    ),
    # ── REQ: 「助かります」「〜いただけると」などを追加 ────────────────────
    (
        '"お願いできますか", "いただけますか", "いただけますでしょうか",',
        '''"お願いできますか", "いただけますか", "いただけますでしょうか",
            "助かります", "助かるのですが", "助かりますので",
            "いただけると助かります", "いただけると幸いです",
            "できたらいいな", "できればいいな", "あれば嬉しい", "あったらいいな",
            "〜と思いまして", "いいなと思いまして",'''
    ),
    # ── MIS: キーワード大幅強化 ─────────────────────────────────────────────
    (
        '"思っていた", "だと思う", "違う", "認識", "そうじゃない", "ではなく", "異なる",',
        '''"思っていた", "だと思う", "違う", "認識", "そうじゃない", "ではなく", "異なる",
            "違う挙動", "想定と違う", "期待と違う", "思ってたのと違う",
            "そういう意味ではなく", "そういうことではなく",
            "仕様が違う", "動作が違う", "挙動が違う", "認識のずれ", "認識相違",
            "思っていたより", "思ったより", "イメージと違う",'''
    ),
]

applied = 0
for old, new in patches:
    if old in src:
        src = src.replace(old, new, 1)
        print(f"  PATCHED: {old[:50]}...")
        applied += 1
    else:
        print(f"  SKIP   : {old[:50]}...")

with open(path, "w", encoding="utf-8") as f:
    f.write(src)

print(f"\n{applied}/{len(patches)} パッチ適用完了")
PYEOF

section "2. 精度テスト（エッジケース 15件）"

python3 << 'PYEOF'
import sys; sys.path.insert(0, ".")

# キャッシュリセット
import importlib
import engine.classifier as clf
importlib.reload(clf)

HARD_CASES = [
    ("なんか動かないんですけど",                    "BUG"),
    ("最近重くなった気がします",                    "IMP"),
    ("ボタン押してもなにも起きない",                 "BUG"),
    ("たまにエラーになります",                      "BUG"),
    ("〇〇機能はありますか？",                      "QST"),
    ("エクスポートできたらいいなと思いまして",          "REQ"),
    ("対応いただけると助かります",                   "REQ"),
    ("ログインできないので修正してほしいです",          "BUG"),
    ("エラーが出るので機能を追加してください",          "BUG"),
    ("DBの接続が切れることがあります",               "BUG"),
    ("先週から検索が遅くなっています",               "IMP"),
    ("ユーザー数が増えてきました",                   "INF"),
    ("思ってたのと違う挙動をしています",              "MIS"),
    ("前のUIの方が使いやすかったです",               "IMP"),
    ("ありがとうございます、解決しました",             "FBK"),
]

ok_count = 0
print(f"\n{'テキスト':<42} {'正解':^6} {'結果':^6} {'スコア':^7}")
print("─"*65)
for text, exp in HARD_CASES:
    r, s = clf.classify_intent(text)
    mark = "✅" if r == exp else "❌"
    ok_count += r == exp
    print(f"{text[:40]:<42} {exp:^6} {r:^4}{mark} {s:^7.1f}")
print("─"*65)
print(f"エッジケース精度: {ok_count}/{len(HARD_CASES)} = {ok_count/len(HARD_CASES)*100:.0f}%")
PYEOF

section "3. 既存20ケース 回帰テスト"

python3 << 'PYEOF'
import sys; sys.path.insert(0, ".")
import importlib
import engine.classifier as clf
importlib.reload(clf)

CASES = [
    ("ログインするとエラーが出て進めません", "BUG"),
    ("アプリが突然クラッシュします", "BUG"),
    ("Dockerコンテナが起動しない", "BUG"),
    ("画面が真っ白になってしまいます", "BUG"),
    ("保存ボタンを押しても保存されない", "BUG"),
    ("500エラーが返ってくる", "BUG"),
    ("認証エラーが発生しています", "BUG"),
    ("タイムアウトが頻発している", "BUG"),
    ("検索機能を追加してほしいです", "REQ"),
    ("CSVエクスポート機能を実装できますか", "REQ"),
    ("ダークモードに対応をお願いしたいです", "REQ"),
    ("メール通知機能の導入を希望します", "REQ"),
    ("APIのページネーション対応をお願いできますか", "REQ"),
    ("モバイル対応を検討してほしいです", "REQ"),
    ("パスワードのリセット方法を教えてください", "QST"),
    ("このAPIの仕様はどこで確認できますか", "QST"),
    ("リリース予定日はいつでしょうか", "QST"),
    ("検索が遅くて使いにくいです", "IMP"),
    ("入力フォームが使いづらいです", "IMP"),
    ("新機能、とても使いやすくて助かります", "FBK"),
]
ok_count = sum(1 for text, exp in CASES if clf.classify_intent(text)[0] == exp)
print(f"回帰テスト: {ok_count}/{len(CASES)} = {ok_count/len(CASES)*100:.0f}%")
if ok_count < len(CASES):
    print("⚠️  回帰テストで❌あり！詳細:")
    for text, exp in CASES:
        r, s = clf.classify_intent(text)
        if r != exp:
            print(f"  ❌ {text[:40]} → 正解:{exp} 結果:{r}")
else:
    print("✅ 全件OK（回帰なし）")
PYEOF

section "4. 総合スコア"
python3 << 'PYEOF'
import sys; sys.path.insert(0, ".")
import importlib
import engine.classifier as clf
importlib.reload(clf)

ALL = [
    ("ログインするとエラーが出て進めません", "BUG"),
    ("アプリが突然クラッシュします", "BUG"),
    ("Dockerコンテナが起動しない", "BUG"),
    ("画面が真っ白になってしまいます", "BUG"),
    ("保存ボタンを押しても保存されない", "BUG"),
    ("500エラーが返ってくる", "BUG"),
    ("認証エラーが発生しています", "BUG"),
    ("タイムアウトが頻発している", "BUG"),
    ("検索機能を追加してほしいです", "REQ"),
    ("CSVエクスポート機能を実装できますか", "REQ"),
    ("ダークモードに対応をお願いしたいです", "REQ"),
    ("メール通知機能の導入を希望します", "REQ"),
    ("APIのページネーション対応をお願いできますか", "REQ"),
    ("モバイル対応を検討してほしいです", "REQ"),
    ("パスワードのリセット方法を教えてください", "QST"),
    ("このAPIの仕様はどこで確認できますか", "QST"),
    ("リリース予定日はいつでしょうか", "QST"),
    ("検索が遅くて使いにくいです", "IMP"),
    ("入力フォームが使いづらいです", "IMP"),
    ("新機能、とても使いやすくて助かります", "FBK"),
    ("なんか動かないんですけど", "BUG"),
    ("最近重くなった気がします", "IMP"),
    ("ボタン押してもなにも起きない", "BUG"),
    ("たまにエラーになります", "BUG"),
    ("〇〇機能はありますか？", "QST"),
    ("エクスポートできたらいいなと思いまして", "REQ"),
    ("対応いただけると助かります", "REQ"),
    ("ログインできないので修正してほしいです", "BUG"),
    ("エラーが出るので機能を追加してください", "BUG"),
    ("DBの接続が切れることがあります", "BUG"),
    ("先週から検索が遅くなっています", "IMP"),
    ("ユーザー数が増えてきました", "INF"),
    ("思ってたのと違う挙動をしています", "MIS"),
    ("前のUIの方が使いやすかったです", "IMP"),
    ("ありがとうございます、解決しました", "FBK"),
]
ok_count = sum(1 for text, exp in ALL if clf.classify_intent(text)[0] == exp)
n = len(ALL)
pct = ok_count/n*100
print(f"\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
print(f"  総合精度: {ok_count}/{n} = {pct:.0f}%")
status = "✅ 目標達成（90%以上）" if pct >= 90 else f"⚠️  目標未達（あと{90-pct:.0f}%）"
print(f"  {status}")
print(f"━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
PYEOF
