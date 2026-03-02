# decision-os NEXT — Phase 2 RBAC強化 完了 引き継ぎ資料
作成日：2026-03-03

## 1. 環境情報（変更なし）
| 項目 | 値 |
|---|---|
| サーバー | omega-dev2 / 192.168.1.11 |
| フロントエンド | http://localhost:3008 |
| バックエンドAPI | http://localhost:8089 |
| DB | PostgreSQL @ localhost:5439 / DB名: decisionos |

## 2. 本セッション実装内容（N-004/N-005）

### 2.1 RBAC修正（N-004）
- `GET /api/v1/users` → **admin のみ**（pm以下は 403）
- `PATCH /api/v1/users/{id}/role` → **admin のみ**
- `users.py` の `db=None` パターンを `Depends(get_db)` / `Depends(require_admin())` に修正

### 2.2 project_members テーブル（N-005）
```
project_members
  id          UUID PK
  project_id  UUID FK → projects
  user_id     UUID FK → users
  tenant_id   UUID FK → tenants
  role        ENUM(admin, pm, dev, viewer)
  invited_by  UUID FK → users
  created_at  TIMESTAMP
  updated_at  TIMESTAMP
  UNIQUE(project_id, user_id)
```

### 2.3 project_members API（N-005）
| Method | Path | 説明 | 認証 |
|---|---|---|---|
| GET    | /api/v1/projects/{id}/members          | メンバー一覧         | Bearer |
| POST   | /api/v1/projects/{id}/members          | メンバー追加         | Bearer（PJ admin）|
| PATCH  | /api/v1/projects/{id}/members/{uid}    | ロール変更           | Bearer（PJ admin）|
| DELETE | /api/v1/projects/{id}/members/{uid}    | メンバー削除         | Bearer（PJ admin）|
| GET    | /api/v1/projects/{id}/my-role          | 自分のPJロール確認   | Bearer |

### 2.4 権限ロジック
- **テナントロール** (users.role): admin/pm/dev/viewer — テナント全体に適用
- **PJロール** (project_members.role): admin/pm/dev/viewer — PJ単位で上書き
- `effective_role` = PJロール優先、未参加の場合はテナントロール

## 3. alembicマイグレーション履歴（現在のHEAD）
```
06be19dbc154  add_tenants_and_tenant_id_to_users
1fee9816c350  add_invite_tokens
b10866687a0f  sync_tenant_id_models
81e8800d8d52  add_tenant_id_to_inputs
19cfd954b5cc  add_tenant_id_to_items_actions
71e204eebf2c  add_project_members  ← HEAD
```
※ project_members テーブルはSQLで直接作成済み（alembicと同期済み）

## 4. 重要な定数・ID（変更なし）
```
default テナントID : 25c925a6-d371-409b-ab2e-90a9a2d8c8e3
デモユーザーID     : fe4a7ba2-d163-4b90-b52a-4b53611489fb (role: pm)
テストユーザーID   : abad26dc-fe6a-425b-bd2c-73a720db8716 (role: dev)
```

## 5. 残課題・TODO

### 🟡 Phase 2 残タスク
- N-007: 監査ログ画面
- W-003: テナント横断検索
- C-001: WebSocketリアルタイム通知
- C-002: メール通知 / @メンション

### �� Phase 1 残件
- RLS（Row-Level Security）本格適用

## 6. 次セッション開始手順
```bash
cd ~/projects/decision-os/scripts && bash 05_launch.sh
curl http://localhost:8089/health
bash 06_e2e_test.sh
```
