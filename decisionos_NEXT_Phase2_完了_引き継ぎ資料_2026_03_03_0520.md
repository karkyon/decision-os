# decision-os NEXT — Phase 2 完了 引き継ぎ資料
作成日：2026-03-03

## 1. 環境情報（変更なし）
| 項目 | 値 |
|---|---|
| サーバー | omega-dev2 / 192.168.1.11 |
| フロントエンド | http://localhost:3008 |
| バックエンドAPI | http://localhost:8089 |
| DB | PostgreSQL @ localhost:5439 / DB名: decisionos |
| デモアカウント | demo@example.com / demo1234（role: pm） |
| テストアカウント | newuser@example.com / test1234（role: dev） |

## 2. Phase 2 実装状況（全完了）

| 機能ID | 内容 | 状態 |
|---|---|---|
| A-002 | Google / GitHub OAuth2 SSO | ✅ 完了（要クレデンシャル設定） |
| A-003 | TOTP 2要素認証 | ✅ 完了 |
| N-004 | RBAC強化（/users admin限定） | ✅ 完了 |
| N-005 | project_members テーブル・API | ✅ 完了 |
| N-007 | 監査ログ（audit_logs） | ✅ 完了 |

## 3. 本セッション修正内容（バグ修正）

| 問題 | 修正内容 |
|---|---|
| `GET /actions?item_id=` 405 | actions.py に GET エンドポイント追加 |
| `GET /users` 403（InputNew） | `/users/assignees` エンドポイント追加（pm以上） |
| `dashboard/stats` 404 | FE を `/dashboard/counts` に修正 |
| `audit_logs` Internal Server Error | tenant_id カラム追加 |
| `users.py` get_current_user 未定義 | import 修正 |

## 4. APIエンドポイント全一覧（Phase 2完了時点）

### 認証・テナント
| Method | Path | 認証 |
|---|---|---|
| POST | /api/v1/auth/login | 不要 |
| POST | /api/v1/auth/register | 不要 |
| POST | /api/v1/auth/refresh | 不要 |
| GET  | /api/v1/auth/me | Bearer |
| POST | /api/v1/auth/invite | Bearer（admin/pm） |
| POST | /api/v1/auth/invite/accept | 不要 |
| GET  | /api/v1/auth/invites | Bearer（admin/pm） |
| GET  | /api/v1/auth/google | 不要 |
| GET  | /api/v1/auth/github | 不要 |
| POST | /api/v1/auth/totp/setup | Bearer |
| POST | /api/v1/auth/totp/verify | Bearer |
| DELETE | /api/v1/auth/totp | Bearer |
| POST | /api/v1/auth/totp/login | 不要 |

### RBAC・ユーザー管理
| Method | Path | 認証 |
|---|---|---|
| GET | /api/v1/users | Bearer（admin のみ） |
| GET | /api/v1/users/assignees | Bearer（pm以上） |
| PATCH | /api/v1/users/{id}/role | Bearer（admin のみ） |
| GET | /api/v1/projects/{id}/members | Bearer |
| POST | /api/v1/projects/{id}/members | Bearer（PJ admin） |
| PATCH | /api/v1/projects/{id}/members/{uid} | Bearer（PJ admin） |
| DELETE | /api/v1/projects/{id}/members/{uid} | Bearer（PJ admin） |
| GET | /api/v1/projects/{id}/my-role | Bearer |

### 監査ログ
| Method | Path | 認証 |
|---|---|---|
| GET | /api/v1/audit-logs | Bearer（admin のみ） |

## 5. alembicマイグレーション履歴（HEAD）
```
06be19dbc154  add_tenants_and_tenant_id_to_users
1fee9816c350  add_invite_tokens
b10866687a0f  sync_tenant_id_models
81e8800d8d52  add_tenant_id_to_inputs
19cfd954b5cc  add_tenant_id_to_items_actions
71e204eebf2c  add_project_members  ← HEAD
```
※ audit_logs / project_members は SQL で直接作成済み

## 6. 重要な定数・ID
```
default テナントID : 25c925a6-d371-409b-ab2e-90a9a2d8c8e3
デモユーザーID     : fe4a7ba2-d163-4b90-b52a-4b53611489fb (role: pm)
テストユーザーID   : abad26dc-fe6a-425b-bd2c-73a720db8716 (role: dev)
Access Token       : 15分
Refresh Token      : 30日
招待トークン       : 72時間
```

## 7. 残課題・TODO

### 🟡 Phase 2 残タスク
- W-003: テナント横断検索
- C-001: WebSocketリアルタイム通知
- C-002: メール通知 / @メンション
- SMTP実装（招待メール現在はAPIレスポンス返却のみ）
- SSO クレデンシャル設定（.env に Google/GitHub ID/Secret）

### 🟢 Phase 1 残件
- RLS（Row-Level Security）本格適用

### UI改善メモ
- ステータスドロップダウンの背景色（var(--bg-card)で設定済み、要ブラウザ確認）
- ダッシュボードのカウントが0表示（/dashboard/counts → /dashboard/stats パス修正済み）

## 8. 次セッション開始手順
```bash
cd ~/projects/decision-os/scripts && bash 05_launch.sh
curl http://localhost:8089/health
bash 06_e2e_test.sh
```
