#!/bin/bash
# ============================================================
# segmenter.py 無限再帰バグ修正 + Step5実行
# ============================================================
set -e

BACKEND="$HOME/projects/decision-os/backend"

echo "=== segmenter.py バグ修正 ==="

cat > "$BACKEND/engine/segmenter.py" << 'EOF'
"""
Segmenter: 文境界でテキストを分割
"""
import re
from typing import List

CONJUNCTIONS = ["また、", "そして、", "ただし、", "なお、", "一方、", "しかし、", "それと、", "さらに、"]
MAX_SEGMENT_LEN = 200


def segment(text: str) -> List[str]:
    if not text:
        return []

    # 句点・改行・！？で分割
    parts = re.split(r'(?<=[。！？\n])', text)
    sentences = []

    for part in parts:
        part = part.strip()
        if not part:
            continue
        # 接続詞で再分割（再帰なし・ループで処理）
        sub = _split_by_conjunctions(part)
        sentences.extend(sub)

    # 長すぎる文を読点で分割
    result = []
    for s in sentences:
        s = s.strip()
        if not s:
            continue
        if len(s) > MAX_SEGMENT_LEN:
            chunks = re.split(r'(?<=、)', s)
            result.extend([c.strip() for c in chunks if c.strip()])
        else:
            result.append(s)

    return result if result else [text.strip()]


def _split_by_conjunctions(text: str) -> List[str]:
    """接続詞でテキストを分割（ループ実装・再帰なし）"""
    result = []
    remaining = text

    while remaining:
        found = False
        for conj in CONJUNCTIONS:
            idx = remaining.find(conj)
            if idx > 0:  # 先頭一致は除外（0の場合はスキップ）
                before = remaining[:idx].strip()
                if before:
                    result.append(before)
                remaining = remaining[idx:].strip()
                found = True
                break
        if not found:
            # どの接続詞にも一致しなかったら残りを全部追加して終了
            if remaining.strip():
                result.append(remaining.strip())
            break

    return result if result else [text]
EOF

echo "✅ segmenter.py 修正完了"

echo ""
echo "=== 分解エンジン動作テスト ==="
cd "$BACKEND"
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
さらに、APIのレスポンスが遅い場合があります。
"""

results = analyze_text(test_text)
print("\n=== 分解エンジンテスト結果 ===")
for i, r in enumerate(results):
    ai_flag = "🤖AI補助" if r["needs_ai_assist"] else "✅"
    print(f"[{i+1}] {ai_flag} {r['intent_code']}/{r['domain_code']} (conf:{r['confidence']:.2f})")
    print(f"     テキスト: {r['text'][:60]}")
print("\n✅ 分解エンジン動作確認完了")
PYEOF

echo ""
echo "=== Step 5: フロントエンド ==="
bash "$HOME/projects/decision-os/scripts/phase1_step5_frontend.sh"

echo ""
echo "=== バックエンド再起動 ==="
pkill -f "uvicorn app.main" 2>/dev/null && sleep 1 || true
cd "$BACKEND"
source .venv/bin/activate
nohup uvicorn app.main:app --host 0.0.0.0 --port 8089 --reload \
  > "$HOME/projects/decision-os/logs/backend.log" 2>&1 &
echo "✅ バックエンド起動 PID: $!"

sleep 3
echo ""
echo "=== 動作確認 ==="
curl -s http://localhost:8089/health && echo ""
curl -s http://localhost:8089/api/v1/ping && echo ""

echo ""
echo "============================================"
echo "  Phase 1 MVP 全実装完了！"
echo "============================================"
echo ""
echo "【アクセスURL】"
echo "  フロントエンド:  http://192.168.1.11:3008"
echo "  nginx統合:       http://192.168.1.11:8888"
echo "  API Swagger:     http://192.168.1.11:8089/docs"
echo ""
echo "【デモアカウント作成】"
echo "curl -X POST http://localhost:8089/api/v1/auth/register \\"
echo "  -H 'Content-Type: application/json' \\"
echo "  -d '{\"name\":\"デモユーザー\",\"email\":\"demo@example.com\",\"password\":\"demo1234\",\"role\":\"pm\"}'"
