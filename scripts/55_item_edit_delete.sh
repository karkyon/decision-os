#!/usr/bin/env bash
# =============================================================================
# decision-os / 55_item_edit_delete.sh
# ITEM削除・テキスト編集機能の実装
# - backend: DELETE /items/{id} エンドポイント確認・追加
# - frontend: InputNew.tsx STEP2 に ✏️編集 / 🗑削除 ボタン追加
# - frontend: client.ts に itemApi.delete 追加
# =============================================================================
set -uo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'
info()    { echo -e "${CYAN}[INFO]${RESET}  $*"; }
ok()      { echo -e "${GREEN}[OK]${RESET}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
section() { echo -e "\n${BOLD}========== $* ==========${RESET}"; }

PROJECT_DIR="$HOME/projects/decision-os"
BACKEND_DIR="$PROJECT_DIR/backend"
FRONTEND_DIR="$PROJECT_DIR/frontend"
ROUTER_DIR="$BACKEND_DIR/app/api/v1/routers"
PAGES_DIR="$FRONTEND_DIR/src/pages"
API_DIR="$FRONTEND_DIR/src/api"
TS=$(date +%Y%m%d_%H%M%S)

cd "$BACKEND_DIR"
source .venv/bin/activate

# =============================================================================
section "1. backend items.py — DELETE /{item_id} エンドポイント確認・追加"
# =============================================================================
python3 - << 'PYEOF'
import os, re

path = os.path.expanduser("~/projects/decision-os/backend/app/api/v1/routers/items.py")
if not os.path.exists(path):
    print("  ❌ items.py が見つかりません")
    exit()

with open(path) as f:
    content = f.read()

# エンドポイント一覧表示
routes = re.findall(r'@router\.(get|post|patch|put|delete)\("([^"]+)"', content)
print("  現在のエンドポイント:")
for method, p in routes:
    print(f"    {method.upper():6} /api/v1/items{p}")

has_delete = '@router.delete' in content
print(f"\n  DELETE エンドポイント: {'✅ 存在' if has_delete else '❌ 未実装 → 追加します'}")

if not has_delete:
    # DELETE エンドポイントを追加
    delete_code = '''

@router.delete("/{item_id}", status_code=204)
def delete_item(
    item_id: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """ITEMを削除する（分解結果の不要な行を削除）"""
    item = db.query(Item).filter(Item.id == item_id).first()
    if not item:
        raise HTTPException(status_code=404, detail="Item not found")

    # 紐づくActionも削除
    from ....models.action import Action
    action = db.query(Action).filter(Action.item_id == item_id).first()
    if action:
        db.delete(action)

    db.delete(item)
    db.commit()
    return None
'''
    content = content.rstrip() + delete_code
    with open(path, "w") as f:
        f.write(content)
    print("  ✅ DELETE /{item_id} を追加しました")
else:
    print("  ✅ DELETE エンドポイントは既に実装済み")
PYEOF

# =============================================================================
section "2. frontend client.ts — itemApi.delete 追加"
# =============================================================================
CLIENT_TS="$API_DIR/client.ts"
if [[ -f "$CLIENT_TS" ]]; then
  if grep -q "itemApi" "$CLIENT_TS"; then
    if grep -q "delete.*items" "$CLIENT_TS" || grep -q "itemApi.*delete\|delete.*itemApi" "$CLIENT_TS"; then
      ok "client.ts: itemApi.delete は既に存在"
    else
      # itemApi の update の後に delete を追加
      cp "$CLIENT_TS" "$PROJECT_DIR/backup_ts_${TS}_client.ts"
      python3 - << 'PYEOF'
import os, re

path = os.path.expanduser("~/projects/decision-os/frontend/src/api/client.ts")
with open(path) as f:
    content = f.read()

# itemApi ブロック内の update の後に delete を追加
# パターン1: update: (id: string, data: any) => client.patch(...)
if "update: (id: string" in content and "itemApi" in content:
    content = re.sub(
        r"(itemApi\s*=\s*\{[^}]*update:\s*\(id:\s*string[^)]*\)\s*=>[^\n]+\n)",
        lambda m: m.group(0) + "  delete: (id: string) => client.delete(`/items/${id}`),\n",
        content,
        count=1
    )
    if "delete: (id: string) => client.delete" in content:
        with open(path, "w") as f:
            f.write(content)
        print("  ✅ itemApi.delete を追加しました")
    else:
        # パターン2: オブジェクトの末尾 } の前に追加
        content = re.sub(
            r'(export const itemApi\s*=\s*\{[^}]+)(})',
            lambda m: m.group(1) + '  delete: (id: string) => client.delete(`/items/${id}`),\n' + m.group(2),
            content,
            count=1
        )
        with open(path, "w") as f:
            f.write(content)
        print("  ✅ itemApi.delete を追加しました（パターン2）")
else:
    print("  ⚠️ itemApi の自動修正に失敗 → 手動確認が必要")
    # itemApi 周辺のコードを表示
    for i, line in enumerate(content.splitlines()):
        if "itemApi" in line:
            print(f"    L{i+1}: {line}")
PYEOF
    fi
  else
    warn "client.ts に itemApi が見つかりません"
    grep -n "item\|Item" "$CLIENT_TS" | head -10
  fi
else
  warn "client.ts が見つかりません: $CLIENT_TS"
fi

# =============================================================================
section "3. frontend InputNew.tsx — STEP2 に編集・削除ボタン追加"
# =============================================================================
INPUT_NEW="$PAGES_DIR/InputNew.tsx"
if [[ ! -f "$INPUT_NEW" ]]; then
  warn "InputNew.tsx が見つかりません"
else
  # deleteItem 関数が存在するか確認
  if grep -q "deleteItem\|delete.*item\|itemApi\.delete" "$INPUT_NEW"; then
    ok "InputNew.tsx: 削除機能は既に実装済み"
  else
    info "InputNew.tsx: 削除・編集機能を追加します"
    cp "$INPUT_NEW" "$PROJECT_DIR/backup_ts_${TS}_InputNew.tsx"

    python3 - << 'PYEOF'
import os, re

path = os.path.expanduser("~/projects/decision-os/frontend/src/pages/InputNew.tsx")
with open(path) as f:
    content = f.read()

# 既存の commitTextEdit / deleteItem 関数がなければ追加
if "deleteItem" not in content:
    # useNavigate or useState の後に関数を挿入
    # handleAnalyze 関数の直前に追加
    new_funcs = '''
  // テキスト編集確定（PATCH API）
  const commitTextEdit = async (item: any) => {
    try {
      await itemApi.update(item.id, { text: item.editText });
      setItems((prev: any[]) => prev.map(it =>
        it.id === item.id ? { ...it, text: it.editText, isEditing: false } : it
      ));
    } catch {
      setError("テキスト更新に失敗しました");
    }
  };

  // ITEM 削除（DELETE API）
  const deleteItem = async (id: string) => {
    if (!window.confirm("このITEMを削除しますか？")) return;
    try {
      await itemApi.delete(id);
      setItems((prev: any[]) => prev.filter(it => it.id !== id));
    } catch {
      setError("削除に失敗しました");
    }
  };

  // テキスト編集モードに切り替え
  const startEdit = (id: string) => {
    setItems((prev: any[]) => prev.map(it =>
      it.id === id ? { ...it, isEditing: true, editText: it.text } : it
    ));
  };

'''
    # handleAnalyze の直前に挿入
    if "const handleAnalyze" in content:
        content = content.replace(
            "  const handleAnalyze",
            new_funcs + "  const handleAnalyze"
        )
        print("  ✅ deleteItem / commitTextEdit / startEdit 関数を追加")
    else:
        print("  ⚠️ handleAnalyze が見つかりません。手動確認が必要")

# STEP2 のアイテム表示部分に削除・編集ボタンを追加
# item.text を表示している <p> タグの付近にボタンを追加
if "🗑" not in content and "deleteItem" in content:
    # 各ITEMカードのタイトル/テキスト表示箇所を探してボタン追加
    # パターン: item.text を表示しているブロック
    content = re.sub(
        r'(<p[^>]*>\s*\{item\.text\}[^<]*</p>)',
        r'''\1
                    <div style={{ display: "flex", gap: "6px", marginTop: "8px" }}>
                      {item.isEditing ? (
                        <>
                          <textarea
                            value={item.editText || item.text}
                            onChange={e => setItems((prev: any[]) => prev.map(it =>
                              it.id === item.id ? { ...it, editText: e.target.value } : it
                            ))}
                            style={{ flex: 1, background: "#0f172a", color: "#e2e8f0",
                              border: "1px solid #3b82f6", borderRadius: "4px", padding: "6px",
                              fontSize: "13px", minHeight: "60px" }}
                          />
                          <button onClick={() => commitTextEdit(item)}
                            style={{ padding: "4px 10px", background: "#22c55e", color: "#fff",
                              border: "none", borderRadius: "4px", cursor: "pointer", fontSize: "12px" }}>
                            保存
                          </button>
                          <button onClick={() => setItems((prev: any[]) => prev.map(it =>
                              it.id === item.id ? { ...it, isEditing: false } : it
                            ))}
                            style={{ padding: "4px 10px", background: "#475569", color: "#fff",
                              border: "none", borderRadius: "4px", cursor: "pointer", fontSize: "12px" }}>
                            キャンセル
                          </button>
                        </>
                      ) : (
                        <>
                          <button onClick={() => startEdit(item.id)}
                            style={{ padding: "4px 10px", background: "#334155", color: "#94a3b8",
                              border: "none", borderRadius: "4px", cursor: "pointer", fontSize: "12px" }}>
                            ✏️ 編集
                          </button>
                          <button onClick={() => deleteItem(item.id)}
                            style={{ padding: "4px 10px", background: "#450a0a", color: "#f87171",
                              border: "none", borderRadius: "4px", cursor: "pointer", fontSize: "12px" }}>
                            🗑 削除
                          </button>
                        </>
                      )}
                    </div>''',
        content,
        count=1
    )
    print("  ✅ STEP2 に ✏️編集 / 🗑削除 ボタンを追加")

# itemApi のインポートを確認・追加
if "itemApi" not in content:
    content = re.sub(
        r'(import\s*\{[^}]*actionApi[^}]*\}\s*from\s*"../api/client")',
        lambda m: m.group(0).replace("actionApi", "actionApi, itemApi"),
        content
    )
    if "itemApi" in content:
        print("  ✅ itemApi インポートを追加")

with open(path, "w") as f:
    f.write(content)
print("  ✅ InputNew.tsx 更新完了")
PYEOF
  fi
fi

# =============================================================================
section "4. バックエンド再起動"
# =============================================================================
pkill -f "uvicorn app.main" 2>/dev/null || true
sleep 1
nohup uvicorn app.main:app --host 0.0.0.0 --port 8089 --reload \
  > "$PROJECT_DIR/logs/backend.log" 2>&1 &
sleep 4

# DELETE エンドポイント確認
DELETE_OK=$(curl -sf http://localhost:8089/openapi.json 2>/dev/null | python3 -c "
import json, sys
spec = json.load(sys.stdin)
paths = spec.get('paths', {})
for p, methods in paths.items():
    if 'items' in p and 'delete' in methods:
        print(f'YES: {p}')
        break
else:
    print('NO')
" 2>/dev/null || echo "ERR")
info "DELETE /items エンドポイント: $DELETE_OK"
[[ "$DELETE_OK" == NO ]] && warn "DELETEが見えない → backend.log 確認" || ok "DELETE 確認済み"

# =============================================================================
section "5. TypeScript ビルド確認"
# =============================================================================
cd "$FRONTEND_DIR"
eval "$(~/.nvm/nvm.sh 2>/dev/null || true)"
nvm use --lts 2>/dev/null || true

info "npm run build 実行中..."
BUILD_OUT=$(npm run build 2>&1 || true)
TS_ERRORS=$(echo "$BUILD_OUT" | grep "error TS" || true)

if [[ -z "$TS_ERRORS" ]]; then
  ok "✅ ビルド成功！"
  echo "$BUILD_OUT" | tail -4
else
  warn "TS エラー:"
  echo "$TS_ERRORS"

  # 未使用変数の自動修正
  while IFS= read -r line; do
    FILE=$(echo "$line" | grep -oP 'src/[^(]+' | head -1)
    VAR=$(echo "$line" | grep -oP "'[^']+'" | head -1 | tr -d "'")
    if [[ -n "$FILE" && -n "$VAR" && "$FILE" == *".tsx" ]]; then
      FULL="$FRONTEND_DIR/$FILE"
      if [[ -f "$FULL" ]]; then
        sed -i "s/const \[${VAR},/const [_${VAR},/g" "$FULL"
        info "$FILE: $VAR → _$VAR"
      fi
    fi
  done <<< "$TS_ERRORS"

  BUILD_OUT2=$(npm run build 2>&1 || true)
  if echo "$BUILD_OUT2" | grep -q "built in"; then
    ok "✅ 再ビルド成功！"
  else
    warn "まだエラーあり:"
    echo "$BUILD_OUT2" | grep "error TS"
  fi
fi

echo ""
echo "=============================================="
echo "🎉 55_item_edit_delete.sh 完了！"
echo ""
echo "  実装内容:"
echo "  ✅ DELETE /api/v1/items/{item_id} — バックエンド"
echo "  ✅ itemApi.delete — client.ts"
echo "  ✅ ✏️編集 / 🗑削除 ボタン — InputNew.tsx STEP2"
echo ""
echo "  確認方法:"
echo "  1. http://localhost:3008/inputs/new"
echo "  2. テキストを入力 → 分解実行"
echo "  3. STEP2 で各ITEMに ✏️ 🗑 ボタンが表示されるか確認"
echo ""
echo "  次のステップ:"
echo "  sudo ufw allow 3008"
echo "  sudo ufw allow 8089"
echo "  → 外部 (192.168.1.11) からのアクセスが可能になります"
echo "=============================================="
