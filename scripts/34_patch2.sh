#!/usr/bin/env bash
# =============================================================================
# 34_patch2.sh — classifier.py に不足キーワードを直接追記
# SKIPされた3箇所（IMP/FBK/MIS）を確実に修正する
# =============================================================================
set -euo pipefail
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BOLD='\033[1m'; RESET='\033[0m'
ok()      { echo -e "${GREEN}[OK]${RESET}    $*"; }
section() { echo -e "\n${BOLD}========== $* ==========${RESET}"; }

PROJECT_DIR="$HOME/projects/decision-os"
ENGINE="$PROJECT_DIR/backend/engine"
cd "$PROJECT_DIR/backend"
source .venv/bin/activate

section "1. classifier.py の現状確認（IMP/FBK/MIS のキーワード行）"
python3 << 'PYEOF'
path = __import__('os').path.expanduser(
    "~/projects/decision-os/backend/engine/classifier.py"
)
with open(path, encoding="utf-8") as f:
    lines = f.readlines()

targets = {"IMP": [], "FBK": [], "MIS": []}
current = None
for i, line in enumerate(lines, 1):
    for k in targets:
        if f'"{k}"' in line and "keywords" in lines[i] if i < len(lines) else False:
            current = k
    if current and ("keywords" in line or any(k in line for k in ["使いにくい","便利","思っていた"])):
        targets[current].append((i, line.rstrip()))
    if current and line.strip() == "],":
        current = None

# IMP/FBK/MISのkeywordsブロック行番号を特定
for intent in ["IMP", "FBK", "MIS"]:
    print(f"\n--- {intent} keywords (周辺) ---")
    in_block = False
    for i, line in enumerate(lines, 1):
        if f'"IMP"' in line and intent == "IMP": in_block = True
        if f'"FBK"' in line and intent == "FBK": in_block = True
        if f'"MIS"' in line and intent == "MIS": in_block = True
        if in_block and "keywords" in line:
            # このブロックを30行表示
            for j in range(i-1, min(i+30, len(lines))):
                print(f"  {j+1:4d}: {lines[j].rstrip()}")
            in_block = False
            break
PYEOF

section "2. Python で直接 IMP/FBK/MIS キーワードを書き換え"
python3 << 'PYEOF'
import re, os

path = os.path.expanduser(
    "~/projects/decision-os/backend/engine/classifier.py"
)
with open(path, encoding="utf-8") as f:
    src = f.read()

# ── IMP キーワードブロックを検索して末尾に追加 ──────────────────────────────
# "IMP" の keywords リストの最後の要素の後に追加
IMP_ADD = '''            # 変化・劣化表現（口語・過去形）
            "重くなった", "重くなっている", "重くなってきた",
            "遅くなった", "遅くなっている", "遅くなってきた",
            "使いにくくなった", "使いにくくなっている",
            "以前より", "前より", "前の方が", "前のUIの方が",
            "なんか重い", "なんか遅い", "気がします", "気がする",
            "劣化", "改悪", "worse",'''

# IMPブロックのkeywordsを見つけて最後の要素の後に挿入
# 「"最適化", "効率",」の後に追記（これは既存のIMP末尾キーワード）
# まず現在のIMP末尾を確認してから挿入
def insert_after_imp(src):
    # IMP セクション内の keywords リストを探す
    # パターン: "IMP" が出現してから最初の ], までの間
    imp_match = re.search(r'"IMP"[^}]+?"keywords"\s*:\s*\[', src, re.DOTALL)
    if not imp_match:
        print("IMP keywords ブロック未発見")
        return src
    
    # IMP keywords の開始位置
    start = imp_match.end()
    # ], を探す（最初の ], がkeywordsの終わり）
    bracket_end = src.find("],", start)
    if bracket_end == -1:
        print("IMP keywords 終端未発見")
        return src
    
    # 終端の直前に追記
    insert_pos = bracket_end
    new_src = src[:insert_pos] + "\n" + IMP_ADD + "\n" + src[insert_pos:]
    print(f"  IMP: {len(IMP_ADD.splitlines())}行のキーワードを追加")
    return new_src

src = insert_after_imp(src)

# ── FBK: 「助かります」「助かる」を削除 ────────────────────────────────────
fbk_removes = ['"助かる", ', '"助かります", ', '"助かっています", ']
for kw in fbk_removes:
    if kw in src:
        src = src.replace(kw, "", 1)
        print(f"  FBK: {kw.strip()} を削除")
    else:
        # スペースなしでも試す
        kw2 = kw.strip().rstrip(',') + ','
        if kw2 in src:
            src = src.replace(kw2, "", 1)
            print(f"  FBK: {kw2} を削除")

# ── MIS: キーワードを末尾に追加 ────────────────────────────────────────────
MIS_ADD = '''            # 違う挙動・想定外
            "違う挙動", "想定と違う", "期待と違う", "思ってたのと違う",
            "挙動が違う", "動作が違う", "仕様が違う",
            "イメージと違う", "思ったより", "思っていたより",
            "そういう意味ではなく", "認識のずれ", "認識相違",'''

def insert_after_mis(src):
    mis_match = re.search(r'"MIS"[^}]+?"keywords"\s*:\s*\[', src, re.DOTALL)
    if not mis_match:
        print("MIS keywords ブロック未発見")
        return src
    start = mis_match.end()
    bracket_end = src.find("],", start)
    if bracket_end == -1:
        print("MIS keywords 終端未発見")
        return src
    insert_pos = bracket_end
    new_src = src[:insert_pos] + "\n" + MIS_ADD + "\n" + src[insert_pos:]
    print(f"  MIS: {len(MIS_ADD.splitlines())}行のキーワードを追加")
    return new_src

src = insert_after_mis(src)

with open(path, "w", encoding="utf-8") as f:
    f.write(src)
print("  classifier.py 書き込み完了")
PYEOF

section "3. 精度テスト（エッジケース 15件）"
python3 << 'PYEOF'
import sys, importlib
sys.path.insert(0, ".")
import engine.classifier as clf
importlib.reload(clf)

HARD_CASES = [
    ("なんか動かないんですけど",              "BUG"),
    ("最近重くなった気がします",              "IMP"),
    ("ボタン押してもなにも起きない",           "BUG"),
    ("たまにエラーになります",               "BUG"),
    ("〇〇機能はありますか？",               "QST"),
    ("エクスポートできたらいいなと思いまして",   "REQ"),
    ("対応いただけると助かります",            "REQ"),
    ("ログインできないので修正してほしいです",   "BUG"),
    ("エラーが出るので機能を追加してください",   "BUG"),
    ("DBの接続が切れることがあります",        "BUG"),
    ("先週から検索が遅くなっています",         "IMP"),
    ("ユーザー数が増えてきました",            "INF"),
    ("思ってたのと違う挙動をしています",       "MIS"),
    ("前のUIの方が使いやすかったです",        "IMP"),
    ("ありがとうございます、解決しました",      "FBK"),
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

section "4. 回帰テスト（既存20件）"
python3 << 'PYEOF'
import sys, importlib
sys.path.insert(0, ".")
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
for text, exp in CASES:
    r, _ = clf.classify_intent(text)
    if r != exp:
        print(f"  ❌ {text[:40]} → 正解:{exp} 結果:{r}")
if ok_count == len(CASES):
    print("✅ 全件OK（回帰なし）")
PYEOF

section "5. 総合スコア（35件）"
python3 << 'PYEOF'
import sys, importlib
sys.path.insert(0, ".")
import engine.classifier as clf
importlib.reload(clf)

ALL = [
    ("ログインするとエラーが出て進めません","BUG"),("アプリが突然クラッシュします","BUG"),
    ("Dockerコンテナが起動しない","BUG"),("画面が真っ白になってしまいます","BUG"),
    ("保存ボタンを押しても保存されない","BUG"),("500エラーが返ってくる","BUG"),
    ("認証エラーが発生しています","BUG"),("タイムアウトが頻発している","BUG"),
    ("検索機能を追加してほしいです","REQ"),("CSVエクスポート機能を実装できますか","REQ"),
    ("ダークモードに対応をお願いしたいです","REQ"),("メール通知機能の導入を希望します","REQ"),
    ("APIのページネーション対応をお願いできますか","REQ"),("モバイル対応を検討してほしいです","REQ"),
    ("パスワードのリセット方法を教えてください","QST"),("このAPIの仕様はどこで確認できますか","QST"),
    ("リリース予定日はいつでしょうか","QST"),("検索が遅くて使いにくいです","IMP"),
    ("入力フォームが使いづらいです","IMP"),("新機能、とても使いやすくて助かります","FBK"),
    ("なんか動かないんですけど","BUG"),("最近重くなった気がします","IMP"),
    ("ボタン押してもなにも起きない","BUG"),("たまにエラーになります","BUG"),
    ("〇〇機能はありますか？","QST"),("エクスポートできたらいいなと思いまして","REQ"),
    ("対応いただけると助かります","REQ"),("ログインできないので修正してほしいです","BUG"),
    ("エラーが出るので機能を追加してください","BUG"),("DBの接続が切れることがあります","BUG"),
    ("先週から検索が遅くなっています","IMP"),("ユーザー数が増えてきました","INF"),
    ("思ってたのと違う挙動をしています","MIS"),("前のUIの方が使いやすかったです","IMP"),
    ("ありがとうございます、解決しました","FBK"),
]
ok_count = sum(1 for t, e in ALL if clf.classify_intent(t)[0] == e)
n = len(ALL)
pct = ok_count/n*100
print(f"\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
print(f"  総合精度: {ok_count}/{n} = {pct:.0f}%")
status = "✅ 目標達成（90%以上）" if pct >= 90 else f"⚠️  目標未達（あと{90-pct:.0f}%）"
print(f"  {status}")
print(f"━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
PYEOF
