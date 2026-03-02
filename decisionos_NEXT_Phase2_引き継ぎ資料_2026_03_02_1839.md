# decision-os NEXT — Phase 2 SSO/TOTP 実装完了 引き継ぎ資料
作成日：2026-03-02 18:39（本セッション完了時点）

---

## 0. 前セッションからの変更点

前回資料（decisionos_NEXT_Phase1_引き継ぎ資料_2026_03_02_session2完了版.md）からの差分を記載。

---

## 1. 環境情報（変更なし）

| 項目 | 値 |
|---|---|
| サーバー | omega-dev2 / 192.168.1.11 |
| プロジェクトパス | `~/projects/decision-os/` |
| フロントエンド | http://localhost:3008 |
| バックエンドAPI | http://localhost:8089 |
| Swagger UI | http://localhost:8089/docs |
| nginx | http://localhost:8888 |
| DB | PostgreSQL @ localhost:5439 / DB名: decisionos |
| Redis | localhost:6380 |
| デモアカウント | demo@example.com / demo1234（role: pm） |
| テストアカウント | newuser@example.com / test1234（role: dev） |

**ポートは絶対に変更しないこと。**

---

## 2. Phase 2 実装状況

| 機能ID | 内容 | 状態 | 備考 |
|---|---|---|---|
| A-002 | Google OAuth2 SSO | ✅ 完了 | クレデンシャル設定で即利用可 |
| A-002 | GitHub OAuth2 SSO | ✅ 完了 | クレデンシャル設定で即利用可 |
| A-003 | TOTP 2要素認証 | ✅ 完了 | setup/verify/login/disable |
| - | FE: SSOボタン | ✅ 完了 | ログイン画面に Google/GitHub ボタン |
| - | FE: TOTPセットアップ画面 | ✅ 完了 | /totp-setup |
| - | FE: TOTPログイン画面 | ✅ 完了 | /totp-login |

---

## 3. 本セッションで実装した内容

### 3.1 バックエンド 新規ファイル

```
backend/app/core/sso.py       - Google / GitHub OAuth2 ユーティリティ
backend/app/core/totp.py      - TOTP 生成・QR生成・検証ユーティリティ
backend/app/api/v1/routers/sso.py  - SSO / TOTP 全エンドポイント
```

### 3.2 バックエンド 変更ファイル

```
backend/app/core/config.py    - GOOGLE_/GITHUB_/TOTP_ 設定追加
backend/app/api/v1/api.py     - sso.router 登録追加
backend/app/api/v1/routers/auth.py - 通常ログインに totp_required フラグ追加
backend/requirements.txt      - authlib, httpx, pyotp, qrcode[pil] 追加
```

### 3.3 フロントエンド 新規ファイル

```
frontend/src/components/SSOButtons.tsx  - Google / GitHub ログインボタン
frontend/src/pages/TOTPSetup.tsx        - 2FA セットアップ（QR → コード確認）
frontend/src/pages/TOTPLogin.tsx        - 2FA ログインステップ
```

### 3.4 フロントエンド 変更ファイル

```
frontend/src/pages/Login.tsx  - SSOButtons 追加 / totp_required 対応
frontend/src/App.tsx          - /totp-setup / /totp-login ルート追加
```

---

## 4. API エンドポイント一覧（本セッション追加分）

| Method | Path | 説明 | 認証 |
|---|---|---|---|
| GET | /api/v1/auth/google | Google ログイン開始（リダイレクト） | 不要 |
| GET | /api/v1/auth/google/callback | Google コールバック・JWT発行 | 不要 |
| GET | /api/v1/auth/github | GitHub ログイン開始（リダイレクト） | 不要 |
| GET | /api/v1/auth/github/callback | GitHub コールバック・JWT発行 | 不要 |
| POST | /api/v1/auth/totp/setup | TOTP シークレット生成・QR発行 | Bearer |
| POST | /api/v1/auth/totp/verify | TOTP コード確認・有効化 | Bearer |
| DELETE | /api/v1/auth/totp | TOTP 無効化 | Bearer |
| POST | /api/v1/auth/totp/login | TOTP 付きログイン | 不要 |

---

## 5. SSO 有効化手順（クレデンシャル設定）

現在は `.env` にプレースホルダーが入っているだけ。実際に使うには以下が必要。

### Google OAuth2

1. https://console.cloud.google.com/ → 「APIとサービス」→「認証情報」
2. 「OAuth 2.0 クライアント ID」作成（種類: ウェブアプリケーション）
3. 承認済みリダイレクト URI に追加:
   `http://localhost:8089/api/v1/auth/google/callback`
4. `.env` を更新:

```bash
GOOGLE_CLIENT_ID=取得したクライアントID
GOOGLE_CLIENT_SECRET=取得したシークレット
```

### GitHub OAuth2

1. https://github.com/settings/developers → 「OAuth Apps」→「New OAuth App」
2. Authorization callback URL:
   `http://localhost:8089/api/v1/auth/github/callback`
3. `.env` を更新:

```bash
GITHUB_CLIENT_ID=取得したクライアントID
GITHUB_CLIENT_SECRET=取得したシークレット
```

設定後にバックエンドを再起動:
```bash
cd ~/projects/decision-os/scripts && bash 05_launch.sh
```

---

## 6. TOTP 使い方（テスト手順）

```bash
# 1. demo アカウントでログイン → Bearer トークン取得
TOKEN={"detail":[{"type":"missing","loc":["body"],"msg":"Field required","input":null}]}

# 2. TOTP セットアップ（QRコード取得）
curl -X POST http://localhost:8089/api/v1/auth/totp/setup \
  -H "Authorization: Bearer $TOKEN" | python3 -m json.tool
# → secret / qr_base64 / otpauth_uri が返る

# 3. Authenticator でスキャン後、表示されたコードで検証
curl -X POST http://localhost:8089/api/v1/auth/totp/verify \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"code":"123456"}'  # 実際のコードを入力

# 4. 次回ログインは totp/login エンドポイントを使用
curl -X POST http://localhost:8089/api/v1/auth/totp/login \
  -H "Content-Type: application/json" \
  -d '{"email":"demo@example.com","password":"demo1234","totp_code":"123456"}'

# 5. 2FA 無効化（コード確認後）
curl -X DELETE http://localhost:8089/api/v1/auth/totp \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"code":"123456"}'
```

---

## 7. 既知の課題・TODO

### 🔴 本番化前に必須

**SSO クレデンシャル設定**
- .env に実際の Google / GitHub Client ID / Secret を設定
- 本番 URL に合わせてコールバック URI を更新

**SSO state の永続化**
- 現在 `_sso_states` はメモリ内辞書（プロセス再起動で消える）
- 本番化時は Redis に保存するよう変更:

```python
# backend/app/api/v1/routers/sso.py の _sso_states を Redis に置き換え
import redis
r = redis.from_url(settings.REDIS_URL)
r.setex(f"sso_state:{state}", 300, "google")  # 5分TTL
```

### 🟡 中優先

**TOTP バックアップコード**
- 現在は Authenticator アプリを紛失した場合の復旧手段なし
- バックアップコード（8桁 × 8枚）の発行・検証機能を追加推奨

**セッション管理（A-004）**
- 複数端末セッション一覧・強制ログアウト機能
- 仕様設計書 A-004 相当

**パスワードポリシー（A-005）**
- 最小8文字・複雑性チェック
- 初回ログイン強制変更

### 🟢 Phase 2 残タスク

- N-007: 監査ログ画面
- W-003: テナント横断検索
- C-001: アプリ内通知（WebSocket）
- C-002: メール通知 / @メンション
- N-004/N-005: RBAC強化（project_members / PJ別ロール）

---

## 8. 次セッション開始手順

```bash
# 1. サービス起動
cd ~/projects/decision-os/scripts && bash 05_launch.sh

# 2. バックエンド確認
curl http://localhost:8089/health
curl http://localhost:8089/api/v1/auth/google  # → HTTP 307

# 3. E2Eテスト実行（既存の22件がPASSすること）
bash 06_e2e_test.sh

# 4. 次タスク開始
#    推奨: N-007 監査ログ実装 または N-004/N-005 RBAC強化
```

---

## 9. 重要な定数・ID（変更なし）

```
default テナントID : 25c925a6-d371-409b-ab2e-90a9a2d8c8e3
デモユーザーID     : fe4a7ba2-d163-4b90-b52a-4b53611489fb
テストユーザーID   : abad26dc-fe6a-425b-bd2c-73a720db8716

Access Token 有効期限  : 15分
Refresh Token 有効期限 : 30日
招待トークン有効期限   : 72時間
```

---

## 10. alembic マイグレーション（変更なし）

```
06be19dbc154  add_tenants_and_tenant_id_to_users
1fee9816c350  add_invite_tokens
b10866687a0f  sync_tenant_id_models
81e8800d8d52  add_tenant_id_to_inputs
19cfd954b5cc  add_tenant_id_to_items_actions  ← HEAD
```

※ SSO/TOTP は既存の `users.totp_secret` カラム（仕様設計書 6章で定義済み）を使用するため、
　 追加マイグレーションは不要。

---

## 11. 参照ドキュメント

| ファイル | 内容 |
|---|---|
| `decisionos_NEXT_仕様設計書_v1.0.docx` | マルチテナント化の全体仕様 |
| `decisionos_NEXT_Phase1_引き継ぎ資料_2026_03_02_session2完了版.md` | Phase 1 完了時点の資料 |
| `decisionos_NEXT_Phase2_引き継ぎ資料_2026_03_02_1839.md` | 本資料 |

---

> 本資料は 2026-03-02 18:39 本セッション完了時点で作成。
> 次セッションは Phase 2 残タスク（監査ログ / RBAC強化 / テナント横断検索）から開始すること。
> SSO を実際に使う場合は .env への Google/GitHub クレデンシャル設定が先決。
