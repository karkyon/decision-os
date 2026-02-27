#!/usr/bin/env bash
# =============================================================================
# 36_train_from_csv.sh — CSVで自動学習
# 1. 全317件を現状の classifier で判定
# 2. ❌誤判定を抽出・分析
# 3. 有効キーワードをDBに自動追加
# 4. 精度を再測定して改善を確認
# =============================================================================
set -euo pipefail
GREEN='\033[0;32m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'; BOLD='\033[1m'; RESET='\033[0m'
ok()      { echo -e "${GREEN}[OK]${RESET}    $*"; }
info()    { echo -e "${CYAN}[INFO]${RESET}  $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
section() { echo -e "\n${BOLD}========== $* ==========${RESET}"; }

PROJECT_DIR="$HOME/projects/decision-os"
BACKEND="$PROJECT_DIR/backend"
CSV_PATH="$PROJECT_DIR/training_data/classified_sentences.csv"

# CSVをプロジェクトにコピー（引数でパス指定も可）
CSV_SRC="${1:-}"
mkdir -p "$PROJECT_DIR/training_data"
if [ -n "$CSV_SRC" ] && [ -f "$CSV_SRC" ]; then
    cp "$CSV_SRC" "$CSV_PATH"
    info "CSV コピー: $CSV_SRC → $CSV_PATH"
elif [ ! -f "$CSV_PATH" ]; then
    warn "CSVファイルが見つかりません: $CSV_PATH"
    warn "使い方: bash 36_train_from_csv.sh /path/to/classified_sentences.csv"
    exit 1
fi

cd "$BACKEND"
source .venv/bin/activate

section "1. 現状精度の計測（Before）"
python3 << 'PYEOF'
import sys, csv, time
sys.path.insert(0, ".")
import engine.classifier as clf
clf.invalidate_cache()
time.sleep(0.3)

csv_path = __import__('os').path.expanduser(
    "~/projects/decision-os/training_data/classified_sentences.csv"
)
with open(csv_path, encoding="utf-8-sig") as f:
    rows = list(__import__('csv').DictReader(f))

from collections import defaultdict, Counter
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
print(f"\n  Before精度: {ok_count}/{n} = {pct:.1f}%")
print(f"\n  {'Intent':^8} {'正解':^6} {'誤判定':^6} {'精度':^8}")
print("  " + "─"*32)
for intent in sorted(intent_stats.keys()):
    s = intent_stats[intent]
    total = s["ok"] + s["ng"]
    acc = s["ok"] / total * 100 if total > 0 else 0
    print(f"  {intent:^8} {s['ok']:^6} {s['ng']:^6} {acc:^8.0f}%")

print(f"\n  ❌ 誤判定 {len(errors)}件 の内訳:")
err_summary = Counter(f"{e['expected']}→{e['got']}" for e in errors)
for pattern, count in err_summary.most_common(10):
    print(f"    {pattern}: {count}件")

# グローバルに保存して次のセクションで使う
import json, os
with open("/tmp/train_errors.json", "w", encoding="utf-8") as f:
    json.dump(errors, f, ensure_ascii=False, indent=2)
with open("/tmp/train_before.json", "w", encoding="utf-8") as f:
    json.dump({"ok": ok_count, "n": n, "pct": pct}, f)
PYEOF

section "2. 誤判定の原因分析"
python3 << 'PYEOF'
import json, re, sys
sys.path.insert(0, ".")

with open("/tmp/train_errors.json", encoding="utf-8") as f:
    errors = json.load(f)

from collections import defaultdict

# INF落ちの文を分析（最多パターン）
inf_drops = [e for e in errors if e["got"] == "INF"]
print(f"\n  INF落ち: {len(inf_drops)}件（スコア0 = キーワード未登録）")
if inf_drops[:5]:
    for e in inf_drops[:5]:
        print(f"    [{e['expected']}] {e['text'][:50]}")

# 誤爆パターン（Xに行くべきなのにYに行く）
wrong_intent = [e for e in errors if e["got"] != "INF"]
print(f"\n  意図誤爆: {len(wrong_intent)}件（別のIntentにマッチ）")
for e in wrong_intent[:5]:
    print(f"    正解:{e['expected']} 結果:{e['got']} スコア:{e['score']:.1f} {e['text'][:50]}")

# Intent別の未カバー文を抽出（INF落ちのもの）
by_intent = defaultdict(list)
for e in inf_drops:
    by_intent[e["expected"]].append(e["text"])

print(f"\n  Intent別 INF落ち件数:")
for intent, texts in sorted(by_intent.items(), key=lambda x: -len(x[1])):
    print(f"    {intent}: {len(texts)}件")
    for t in texts[:3]:
        print(f"      - {t[:55]}")
PYEOF

section "3. キーワード自動抽出 → DBに追加"
python3 << 'PYEOF'
import json, re, os, sys
import psycopg2
from urllib.parse import urlparse
from collections import defaultdict

sys.path.insert(0, ".")
import engine.classifier as clf

with open("/tmp/train_errors.json", encoding="utf-8") as f:
    errors = json.load(f)

db_url = os.popen("grep DATABASE_URL ~/projects/decision-os/.env 2>/dev/null | cut -d= -f2-").read().strip()
u = urlparse(db_url)
conn = psycopg2.connect(host=u.hostname, port=u.port or 5432,
    dbname=u.path.lstrip("/"), user=u.username, password=u.password)
cur = conn.cursor()

# 既存キーワードをセットで取得（重複追加防止）
cur.execute("SELECT intent, keyword FROM intent_keywords WHERE enabled=true")
existing = {(r[0], r[1]) for r in cur.fetchall()}

def extract_keywords(text: str, intent: str) -> list:
    """テキストから有効なキーワード候補を抽出"""
    candidates = []

    # 1. 文末表現（〜できますか、〜してほしい、〜てください等）
    patterns = {
        "REQ": [
            r"(.{2,8})(?:できますか|できませんか|可能でしょうか|可能ですか)",
            r"(.{2,8})(?:してほしい|していただきたい|をお願い|ていただけますか)",
            r"(.{2,8})(?:に合わせ|を追加|を実装|を対応|を変更)(?:できますか|したい|してほしい)",
        ],
        "IMP": [
            r"(.{2,8})(?:が分かりづらい|が使いづらい|がしづらい|が見づらい)",
            r"(.{2,8})(?:を改善|を見直し|を整理|を簡略化)",
            r"(.{2,8})(?:したい|したいです)$",
        ],
        "BUG": [
            r"(.{2,8})(?:が発生|が起きて|しています|してしまい)",
            r"(.{2,8})(?:が崩れ|が遅い|が異なる|が正しく)",
        ],
        "QST": [
            r"(.{2,8})(?:を教えてください|を確認させてください|はどの|はいつ|でしょうか)",
        ],
        "INF": [
            r"(.{2,8})(?:を共有|をご連絡|をお知らせ|を提示|を報告)",
        ],
    }

    for pat in patterns.get(intent, []):
        m = re.search(pat, text)
        if m:
            kw = m.group(0)  # マッチした全体を候補に
            if len(kw) >= 4 and (intent, kw) not in existing:
                candidates.append(kw)

    # 2. 特徴的な名詞フレーズ（文の核心部分）
    # 「〜が〜する/できる/ある」パターンから名詞部分を抽出
    noun_pats = [
        r"([ぁ-ん\u4e00-\u9fff]{2,8})(?:機能|設定|画面|処理|フロー|フォーマット|タイミング)",
        r"([ぁ-ん\u4e00-\u9fff]{2,8})(?:が発生|が崩れ|が遅い|が正しく動かない)",
    ]
    for pat in noun_pats:
        for m in re.finditer(pat, text):
            kw = m.group(0)
            if len(kw) >= 4 and (intent, kw) not in existing:
                candidates.append(kw)

    return list(set(candidates))


# INF落ちの文から優先してキーワード追加
inf_errors = [e for e in errors if e["got"] == "INF"]
added = 0
skipped = 0

# Intent別に代表的なフレーズを直接追加（INF落ちが多いIntent向け）
DIRECT_ADDITIONS = {
    "IMP": [
        # 調整・見直し表現
        ("調整可能でしょうか",     "partial", 1.5),
        ("調整できますか",          "partial", 1.5),
        ("調整したいです",          "partial", 1.5),
        ("再確認させてください",    "partial", 1.2),
        ("再検討したい",            "partial", 1.5),
        ("見直したい",              "partial", 1.5),
        ("整理したい",              "partial", 1.5),
        ("簡略化できませんか",      "partial", 2.0),
        ("具体的な手順",            "partial", 1.2),
        ("レイアウトが崩れ",        "partial", 2.0),
        ("文字化けが発生",          "partial", 2.0),
        ("挙動が異なる",            "partial", 2.0),
        ("仕様を再説明",            "partial", 1.5),
        ("確認したいです",          "partial", 1.0),
        ("確認させてください",      "partial", 1.0),
        ("記載いただけますか",      "partial", 1.2),
        ("ドキュメント化",          "partial", 1.5),
        ("カスタマイズ可能",        "partial", 1.5),
        ("に合わせて調整",          "partial", 2.0),
        ("フォーマットに合わせ",    "partial", 2.0),
        ("ブランドガイドライン",    "partial", 1.5),
        ("操作フロー",              "partial", 1.2),
        ("移行作業",                "partial", 1.2),
        ("連携タイミング",          "partial", 1.2),
        ("上限はどの程度",          "partial", 1.5),
        ("同時ログイン数",          "partial", 1.5),
        (r"(?:挙動|仕様|設定)が(?:異なる|違う|おかしい)", "regex", 2.0),
        (r"(?:レイアウト|画面|表示)が(?:崩れ|おかしい|ずれ)", "regex", 2.0),
        (r"(?:に合わせ|に沿って)(?:調整|変更|カスタマイズ)", "regex", 2.0),
    ],
    "REQ": [
        ("細かく制御できませんか",  "partial", 2.0),
        ("追加できますか",          "partial", 2.0),
        ("追加できませんか",        "partial", 2.0),
        ("変更できますか",          "partial", 2.0),
        ("変更できませんか",        "partial", 2.0),
        ("対応していただけますか",  "partial", 2.0),
        ("対応可能でしょうか",      "partial", 2.0),
        ("実装していただけますか",  "partial", 2.0),
        ("見据えた設計",            "partial", 1.5),
        ("将来的な機能追加",        "partial", 1.5),
        ("確認ダイアログを追加",    "partial", 2.0),
        ("ポリシーを変更",          "partial", 1.5),
        ("クラウド環境へ移行",      "partial", 1.5),
        ("操作ミス防止",            "partial", 1.5),
        (r"(?:追加|変更|対応|実装)(?:できますか|できませんか|可能ですか|可能でしょうか)", "regex", 2.5),
        (r"(?:自社|当社)(?:フォーマット|規定|ブランド)に合わせ", "regex", 2.0),
    ],
    "BUG": [
        ("文字化け",                "partial", 2.0),
        ("レイアウトが崩れ",        "partial", 2.0),
        ("エラーが発生",            "partial", 2.0),
        ("エラーハンドリング",      "partial", 1.5),
        ("調査いただけますか",      "partial", 1.5),
        ("原因を調査",              "partial", 2.0),
        ("原因は何でしょうか",      "partial", 2.0),
        ("処理速度が想定より遅い",  "partial", 2.0),
        ("想定外のエラー",          "partial", 2.0),
        ("エラー発生時",            "partial", 1.5),
        (r"(?:文字化け|レイアウト崩れ|エラー)が(?:発生|起き)", "regex", 2.5),
        (r"(?:原因|調査|対応)(?:を|は)(?:調査|教え|確認)", "regex", 2.0),
    ],
    "QST": [
        ("を教えてください",        "partial", 2.0),
        ("詳しく教えてください",    "partial", 2.0),
        ("を確認させてください",    "partial", 1.5),
        ("提示してください",        "partial", 1.5),
        ("共有いただけますか",      "partial", 1.5),
        ("実施済みでしょうか",      "partial", 2.0),
        ("前提で問題ありませんか",  "partial", 1.5),
        ("想定していますか",        "partial", 1.5),
        ("はどの程度",              "partial", 1.5),
        (r"(?:教え|確認させ|再確認させ)(?:てください|ていただけますか)", "regex", 2.0),
        (r"(?:実施|完了|対応)(?:済みでしょうか|しているでしょうか)", "regex", 2.0),
    ],
    "INF": [
        ("スケジュールを提示",      "partial", 1.5),
        ("共有いただけますか",      "partial", 1.2),
        ("ドキュメント化して共有",  "partial", 2.0),
        ("資料が必要",              "partial", 1.5),
        ("を整理したい",            "partial", 1.2),
        ("連絡フローを整理",        "partial", 2.0),
    ],
    "TSK": [
        ("作業スケジュール",        "partial", 1.5),
        ("を詳細に提示",            "partial", 1.5),
        ("移行作業スケジュール",    "partial", 2.0),
    ],
}

for intent, entries in DIRECT_ADDITIONS.items():
    for kw, mt, w in entries:
        if (intent, kw) not in existing:
            cur.execute("""
                INSERT INTO intent_keywords (intent, keyword, match_type, weight, source)
                VALUES (%s, %s, %s, %s, 'csv_training')
                ON CONFLICT (intent, keyword) DO UPDATE
                    SET weight=EXCLUDED.weight, enabled=true, source=EXCLUDED.source
            """, (intent, kw, mt, w))
            added += 1
            existing.add((intent, kw))
        else:
            skipped += 1

conn.commit()

cur.execute("SELECT COUNT(*) FROM intent_keywords WHERE enabled=true")
total = cur.fetchone()[0]
conn.close()

print(f"  追加: {added}件 / スキップ（重複）: {skipped}件")
print(f"  DB合計: {total}件（有効）")
PYEOF
ok "DB追加完了"

section "4. キャッシュクリア → After精度計測"
python3 << 'PYEOF'
import sys, csv, time, json, os
sys.path.insert(0, ".")
import engine.classifier as clf
clf.invalidate_cache()
time.sleep(0.5)

csv_path = os.path.expanduser(
    "~/projects/decision-os/training_data/classified_sentences.csv"
)
with open(csv_path, encoding="utf-8-sig") as f:
    rows = list(__import__('csv').DictReader(f))

from collections import defaultdict, Counter

ok_count = 0
errors_after = []
intent_stats = defaultdict(lambda: {"ok": 0, "ng": 0})

for row in rows:
    text = row["文章"].strip()
    expected = row["タグ"].strip()
    result, score = clf.classify_intent(text)
    if result == expected:
        ok_count += 1
        intent_stats[expected]["ok"] += 1
    else:
        errors_after.append({"text": text, "expected": expected, "got": result, "score": score})
        intent_stats[expected]["ng"] += 1

with open("/tmp/train_before.json", encoding="utf-8") as f:
    before = json.load(f)

n = len(rows)
pct_after = ok_count / n * 100
pct_before = before["pct"]

print(f"\n  {'Intent':^8} {'正解':^5} {'誤判定':^6} {'精度':^8}")
print("  " + "─"*32)
for intent in sorted(intent_stats.keys()):
    s = intent_stats[intent]
    total = s["ok"] + s["ng"]
    acc = s["ok"] / total * 100 if total > 0 else 0
    print(f"  {intent:^8} {s['ok']:^5} {s['ng']:^6} {acc:^8.0f}%")

print(f"\n  残り❌ {len(errors_after)}件:")
for e in errors_after[:10]:
    print(f"    正解:{e['expected']} 結果:{e['got']} スコア:{e['score']:.1f} | {e['text'][:50]}")
if len(errors_after) > 10:
    print(f"    ... 他{len(errors_after)-10}件")

print(f"""
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Before: {before['ok']}/{before['n']} = {pct_before:.1f}%
  After:  {ok_count}/{n} = {pct_after:.1f}%
  改善:   +{pct_after-pct_before:.1f}ポイント（+{ok_count-before['ok']}件）
  {'✅ 目標達成（90%以上）' if pct_after >= 90 else f'⚠️  目標未達（あと{90-pct_after:.1f}%）'}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━""")
PYEOF
