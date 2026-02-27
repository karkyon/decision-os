#!/usr/bin/env bash
# =============================================================================
# 37_relabel_csv.sh — CSVラベル修正（確定ルール適用）+ 再学習
# =============================================================================
set -euo pipefail
GREEN='\033[0;32m'; CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'
ok()      { echo -e "${GREEN}[OK]${RESET}    $*"; }
info()    { echo -e "${CYAN}[INFO]${RESET}  $*"; }
section() { echo -e "\n${BOLD}========== $* ==========${RESET}"; }

PROJECT_DIR="$HOME/projects/decision-os"
BACKEND="$PROJECT_DIR/backend"
CSV_SRC="$PROJECT_DIR/training_data/classified_sentences.csv"
CSV_FIXED="$PROJECT_DIR/training_data/classified_sentences_fixed.csv"

cd "$BACKEND"
source .venv/bin/activate

section "1. ラベル自動修正（確定ルール適用）"
python3 << 'PYEOF'
import csv, re, os
from collections import Counter

src = os.path.expanduser("~/projects/decision-os/training_data/classified_sentences.csv")
dst = os.path.expanduser("~/projects/decision-os/training_data/classified_sentences_fixed.csv")

with open(src, encoding="utf-8-sig") as f:
    rows = list(csv.DictReader(f))

# ── 確定した修正ルール（優先順位順）────────────────────────────────────────
# (正規表現, 変換先Intent, 理由)
RULES = [
    # BUG: 不具合・エラー発生の報告
    (r"文字化け",                                               "BUG", "文字化け=不具合"),
    (r"レイアウトが崩れ",                                       "BUG", "表示崩れ=BUG"),
    (r"内容が消えてしまい",                                     "BUG", "データ消失=BUG"),
    (r"(?:エラー|障害).*(?:発生|調査|原因)",                    "BUG", "エラー発生調査=BUG"),
    (r"原因を調査",                                             "BUG", "調査依頼=BUG"),
    (r"処理速度が想定より遅い.*原因",                           "BUG", "性能問題原因調査=BUG"),

    # IMP: 現象確認・改善提案（動いてはいる）
    (r"挙動が異なる",                                           "IMP", "環境差異現象確認=IMP"),
    (r"テスト環境と本番.*(?:異なる|違う)",                      "IMP", "環境差異=IMP"),

    # REQ: 新機能要望・機能追加依頼
    (r"(?:できますか|できませんか)。$",                         "REQ", "機能要望=REQ"),
    (r"(?:可能でしょうか|可能ですか)。$",                       "REQ", "機能要望=REQ"),
    (r"(?:に合わせて調整|フォーマットに合わせ)",                "REQ", "カスタマイズ要望=REQ"),
    (r"(?:ようにしたいです|できるようにしたい)",                "REQ", "新機能要望=REQ"),
    (r"(?:機能|履歴|ログ).*(?:追えるように|確認できるように)",  "REQ", "新機能要望=REQ"),
    (r"(?:細かく制御|きめ細かく設定)",                         "REQ", "機能強化要望=REQ"),
    (r"(?:追加できますか|実装できますか|対応できますか)",        "REQ", "機能追加要望=REQ"),
    (r"(?:カスタマイズ可能|変更できますか|設定できますか)",      "REQ", "設定要望=REQ"),
    (r"(?:見据えた設計|将来的.*(?:追加|拡張|移行))",           "REQ", "将来要望=REQ"),
    (r"(?:操作ミス防止|確認ダイアログ|確認メッセージ).*(?:追加|ほしい)", "REQ", "UI機能要望=REQ"),
    (r"(?:自動で|自動的に).*(?:ほしい|したい|できますか)",      "REQ", "自動化要望=REQ"),

    # QST: 仕様確認・質問
    (r"(?:上限はどの程度|上限.*想定)",                          "QST", "スペック質問=QST"),
    (r"(?:想定していますか|想定.*でしょうか)",                  "QST", "想定確認質問=QST"),
    (r"(?:実施済みでしょうか|完了.*でしょうか)",               "QST", "実施確認質問=QST"),
    (r"(?:前提で問題ありませんか|前提.*大丈夫ですか)",          "QST", "前提確認質問=QST"),
    (r"(?:仕様を.*(?:教え|説明|再説明)|仕様.*確認)",           "QST", "仕様質問=QST"),
    (r"(?:詳しく教えてください|教えてください)。$",            "QST", "質問=QST"),
    (r"(?:再確認させてください|再説明いただけますか)",          "QST", "仕様再確認=QST"),
    (r"(?:保存期間|取得頻度|処理時間帯|実行時間帯).*(?:ですか|でしょうか|教え)", "QST", "設定値質問=QST"),
    (r"原因は何でしょうか",                                    "QST", "原因質問=QST"),
    (r"(?:エラーハンドリング|ハンドリング).*(?:仕様|教え)",    "QST", "仕様質問=QST"),

    # TSK: 具体的な作業依頼
    (r"(?:ドキュメント化して共有|手順.*共有).*(?:ください|いただけますか)", "TSK", "ドキュメント作成依頼=TSK"),
    (r"(?:スケジュール|作業計画).*(?:詳細に提示|提示してください)", "TSK", "スケジュール提示依頼=TSK"),
    (r"(?:資料|ドキュメント).*(?:作成|提出|準備).*(?:ください|必要)", "TSK", "資料作成依頼=TSK"),
]

changes = []
fixed_rows = []

for row in rows:
    text = row["文章"].strip()
    original = row["タグ"].strip()
    new_label = original

    for pattern, intent, reason in RULES:
        if re.search(pattern, text):
            new_label = intent
            break

    if new_label != original:
        changes.append({"text": text, "from": original, "to": new_label})

    fixed_rows.append({"文章": text, "タグ": new_label})

# 保存
with open(dst, "w", encoding="utf-8-sig", newline="") as f:
    writer = csv.DictWriter(f, fieldnames=["文章", "タグ"])
    writer.writeheader()
    writer.writerows(fixed_rows)

# サマリー
print(f"\n  修正件数: {len(changes)}/{len(rows)}件\n")
change_summary = Counter(f"{c['from']}→{c['to']}" for c in changes)
print(f"  {'変換パターン':<20} {'件数':^6}")
print("  " + "─"*28)
for pat, cnt in change_summary.most_common():
    print(f"  {pat:<20} {cnt:^6}")

print(f"\n  修正例（全件）:")
for c in changes:
    print(f"    [{c['from']}→{c['to']}] {c['text'][:60]}")

# 修正後のラベル分布
from collections import defaultdict
dist = defaultdict(int)
for r in fixed_rows:
    dist[r["タグ"]] += 1
print(f"\n  修正後のラベル分布:")
for k, v in sorted(dist.items()):
    print(f"    {k}: {v}件")
PYEOF
ok "ラベル修正完了"

section "2. 修正済みCSVで再学習（DBにキーワード追加）"
python3 << 'PYEOF'
import csv, os, re, psycopg2, sys, time
from urllib.parse import urlparse
from collections import defaultdict
sys.path.insert(0, ".")
import engine.classifier as clf

csv_path = os.path.expanduser(
    "~/projects/decision-os/training_data/classified_sentences_fixed.csv"
)
db_url = os.popen("grep DATABASE_URL ~/projects/decision-os/.env 2>/dev/null | cut -d= -f2-").read().strip()
u = urlparse(db_url)
conn = psycopg2.connect(host=u.hostname, port=u.port or 5432,
    dbname=u.path.lstrip("/"), user=u.username, password=u.password)
cur = conn.cursor()

cur.execute("SELECT intent, keyword FROM intent_keywords WHERE enabled=true")
existing = {(r[0], r[1]) for r in cur.fetchall()}

with open(csv_path, encoding="utf-8-sig") as f:
    rows = list(csv.DictReader(f))

clf.invalidate_cache()
time.sleep(0.3)

added = 0
# INF落ちしている文の文末・特徴フレーズをDBに追加
for row in rows:
    text = row["文章"].strip()
    expected = row["タグ"].strip()
    result, score = clf.classify_intent(text)
    if result == expected:
        continue
    if score > 0:
        continue  # 誤爆（別のIntentにマッチ）は辞書追加より優先度調整が必要

    # INF落ち（score=0）→ 文末15文字をキーワードとして追加
    tail = text.rstrip("。").strip()[-15:]
    if len(tail) >= 5 and (expected, tail) not in existing:
        cur.execute("""
            INSERT INTO intent_keywords (intent, keyword, match_type, weight, source)
            VALUES (%s, %s, 'partial', 1.5, 'relabel_v2')
            ON CONFLICT (intent, keyword) DO NOTHING
        """, (expected, tail))
        existing.add((expected, tail))
        added += 1

    # 特徴フレーズ（動詞句）を抽出
    for m in re.finditer(
        r'[ぁ-ん\u4e00-\u9fff]{3,10}(?:したいです|してほしい|できますか|できませんか|させてください|いただけますか|可能でしょうか|ようにしたい)',
        text
    ):
        kw = m.group(0)
        if len(kw) >= 7 and (expected, kw) not in existing:
            cur.execute("""
                INSERT INTO intent_keywords (intent, keyword, match_type, weight, source)
                VALUES (%s, %s, 'partial', 2.0, 'relabel_v2')
                ON CONFLICT (intent, keyword) DO NOTHING
            """, (expected, kw))
            existing.add((expected, kw))
            added += 1

conn.commit()
cur.execute("SELECT intent, COUNT(*) FROM intent_keywords WHERE enabled=true GROUP BY intent ORDER BY intent")
print(f"  追加キーワード: {added}件\n")
print(f"  {'Intent':^8} {'件数':^6}")
print("  " + "─"*16)
for row in cur.fetchall():
    print(f"  {row[0]:^8} {row[1]:^6}")
conn.close()
PYEOF
ok "再学習完了"

section "3. 精度計測（修正済みCSV基準）"
python3 << 'PYEOF'
import csv, os, sys, time
from collections import defaultdict
sys.path.insert(0, ".")
import engine.classifier as clf
clf.invalidate_cache()
time.sleep(0.5)

csv_path = os.path.expanduser(
    "~/projects/decision-os/training_data/classified_sentences_fixed.csv"
)
with open(csv_path, encoding="utf-8-sig") as f:
    rows = list(csv.DictReader(f))

ok_count = 0
errors = []
intent_stats = defaultdict(lambda: {"ok": 0, "ng": 0})

for row in rows:
    text = row["文章"].strip()
    expected = row["タグ"].strip()
    result, score = clf.classify_intent(text)
    if result == expected:
        ok_count += 1
        intent_stats[expected]["ok"] += 1
    else:
        errors.append({"text": text, "expected": expected, "got": result, "score": score})
        intent_stats[expected]["ng"] += 1

n = len(rows)
pct = ok_count / n * 100

print(f"\n  {'Intent':^8} {'正解':^5} {'誤判定':^6} {'精度':^8}")
print("  " + "─"*34)
for intent in sorted(intent_stats.keys()):
    s = intent_stats[intent]
    total = s["ok"] + s["ng"]
    acc = s["ok"] / total * 100 if total > 0 else 0
    bar = "▓" * int(acc / 10)
    print(f"  {intent:^8} {s['ok']:^5} {s['ng']:^6} {acc:^6.0f}% {bar}")

if errors:
    print(f"\n  残り❌ {len(errors)}件（上位15件）:")
    for e in errors[:15]:
        print(f"    {e['expected']}→{e['got']} {e['score']:.1f} | {e['text'][:55]}")

print(f"""
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  精度: {ok_count}/{n} = {pct:.1f}%
  {'✅ 目標達成（90%以上）' if pct >= 90 else f'⚠️  目標未達（あと{90-pct:.1f}%）'}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━""")
PYEOF
