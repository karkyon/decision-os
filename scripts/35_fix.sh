#!/usr/bin/env bash
set -euo pipefail
GREEN='\033[0;32m'; BOLD='\033[1m'; RESET='\033[0m'
ok()      { echo -e "${GREEN}[OK]${RESET}    $*"; }
section() { echo -e "\n${BOLD}========== $* ==========${RESET}"; }

PROJECT_DIR="$HOME/projects/decision-os"
BACKEND="$PROJECT_DIR/backend"
cd "$BACKEND"
source .venv/bin/activate

# ─────────────────────────────────────────────
section "1. api.py の import 修正"
# ─────────────────────────────────────────────
python3 << 'PYEOF'
import os, re
path = os.path.expanduser("~/projects/decision-os/backend/app/api/v1/api.py")
with open(path, encoding="utf-8") as f:
    src = f.read()

print("--- 現状 api.py ---")
print(src)
PYEOF

python3 << 'PYEOF'
import os, re
path = os.path.expanduser("~/projects/decision-os/backend/app/api/v1/api.py")
with open(path, encoding="utf-8") as f:
    src = f.read()

# 壊れた import を修正
# "from app.api.v1.routers import dictionary as dictionary_router\nfrom app.api.v1.routers import"
# → まず dictionary_router の import が正しくあるか確認して修正

# パターン1: 二重import行になっている場合を整理
# dictionary_router の import を確実に追加
if "from app.api.v1.routers import dictionary as dictionary_router" not in src:
    # routers の import ブロックを探して dictionary を追加
    src = re.sub(
        r'(from app\.api\.v1\.routers import [^\n]+)',
        r'\1\nfrom app.api.v1.routers import dictionary as dictionary_router',
        src, count=1
    )
    print("  dictionary import 追加")
else:
    print("  dictionary import は既にあり")

# include_router の行が正しいか確認
if "api_router.include_router(dictionary_router.router)" not in src:
    # 最後の include_router の後に追加
    last = src.rfind("api_router.include_router(")
    end = src.find("\n", last) + 1
    src = src[:end] + "api_router.include_router(dictionary_router.router)\n" + src[end:]
    print("  include_router 追加")
else:
    print("  include_router は既にあり")

with open(path, "w", encoding="utf-8") as f:
    f.write(src)
print("  api.py 修正完了")
PYEOF
ok "api.py 修正完了"

# ─────────────────────────────────────────────
section "2. 精度❌2件をDBで修正"
# ─────────────────────────────────────────────
python3 << 'PYEOF'
import os, psycopg2
from urllib.parse import urlparse

db_url = os.popen("grep DATABASE_URL ~/projects/decision-os/.env 2>/dev/null | cut -d= -f2-").read().strip()
u = urlparse(db_url)
conn = psycopg2.connect(host=u.hostname, port=u.port or 5432,
    dbname=u.path.lstrip("/"), user=u.username, password=u.password)
cur = conn.cursor()

# ❌1: 「新機能、とても使いやすくて助かります」→ FBK なのに REQ
#   原因: "助かります" が REQ にあってスコア2.5、FBK のスコアが低い
#   対応: "使いやすくて" "使いやすい" を FBK に追加 + weight を上げる
fbk_add = [
    ("使いやすくて",   "partial", 2.0),
    ("ありがとうございました", "partial", 2.0),
    ("解決しました",   "partial", 1.5),
    ("助かりました",   "partial", 2.0),   # 過去形は感謝 → FBK
    ("よかったです",   "partial", 1.5),
]
for kw, mt, w in fbk_add:
    cur.execute("""
        INSERT INTO intent_keywords (intent, keyword, match_type, weight, source)
        VALUES ('FBK', %s, %s, %s, 'precision_fix')
        ON CONFLICT (intent, keyword) DO UPDATE SET weight=EXCLUDED.weight, enabled=true
    """, (kw, mt, w))
    print(f"  FBK追加: '{kw}' weight={w}")

# ❌2: 「先週から検索が遅くなっています」→ IMP なのに INF (score=0)
#   原因: "遅くなっています" が未登録（"遅くなっている" はあるが "遅くなっています" はない）
imp_add = [
    ("遅くなっています",    "partial", 1.5),
    ("重くなっています",    "partial", 1.5),
    ("遅くなってきました",  "partial", 1.5),
    ("重くなってきました",  "partial", 1.5),
    ("使いにくくなっています", "partial", 1.5),
    ("から遅く",            "partial", 1.0),
    ("から重く",            "partial", 1.0),
    (r"(?:遅く|重く|使いにくく)な(?:っています|ってきました)", "regex", 2.0),
]
for kw, mt, w in imp_add:
    cur.execute("""
        INSERT INTO intent_keywords (intent, keyword, match_type, weight, source)
        VALUES ('IMP', %s, %s, %s, 'precision_fix')
        ON CONFLICT (intent, keyword) DO UPDATE SET weight=EXCLUDED.weight, enabled=true
    """, (kw, mt, w))
    print(f"  IMP追加: '{kw}' weight={w}")

conn.commit()
conn.close()
print("\n  DB修正完了")
PYEOF
ok "DB修正完了"

# ─────────────────────────────────────────────
section "3. バックエンド再起動"
# ─────────────────────────────────────────────
pkill -f "uvicorn" 2>/dev/null || true
sleep 1
nohup uvicorn app.main:app --host 0.0.0.0 --port 8089 --reload \
  > "$PROJECT_DIR/backend.log" 2>&1 &
sleep 4
if curl -s http://localhost:8089/docs > /dev/null 2>&1; then
    ok "バックエンド起動 ✅"
else
    echo "--- backend.log ---"
    tail -15 "$PROJECT_DIR/backend.log"
fi

# ─────────────────────────────────────────────
section "4. 精度テスト（35件）"
# ─────────────────────────────────────────────
python3 << 'PYEOF'
import sys, time
sys.path.insert(0, ".")
import engine.classifier as clf
clf.invalidate_cache()
time.sleep(0.3)

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
ok_count = 0
print(f"\n{'テキスト':<42} {'正解':^6} {'結果':^6} {'スコア':^7}")
print("─"*65)
for text, exp in ALL:
    r, s = clf.classify_intent(text)
    mark = "✅" if r == exp else "❌"
    ok_count += r == exp
    if r != exp:
        print(f"{text[:40]:<42} {exp:^6} {r:^4}{mark} {s:^7.1f}")
if ok_count == len(ALL):
    print("  全件✅ — ❌なし")
print("─"*65)
n = len(ALL)
pct = ok_count/n*100
print(f"\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
print(f"  総合精度: {ok_count}/{n} = {pct:.0f}%")
print(f"  {'✅ 目標達成（90%以上）' if pct>=90 else f'⚠️  目標未達（あと{90-pct:.0f}%）'}")
print(f"━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
PYEOF
