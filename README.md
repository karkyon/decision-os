# decision-os — 開発判断OS

> **「タスク管理」ではなく「判断管理」。**  
> 要望の発生から意思決定・実装・リリースまでを一本線で追える、開発チーム特化型マネジメントツール。

---

## コンセプト

既存ツール（Jira / Backlog / Slack）の根本的な問題は「機能が点在していること」です。

- Slackの議論が課題に紐づかない
- なぜこの仕様になったのか1年後に追跡できない
- 顧客の要望がどの実装に反映されたか分からない

**decision-osが管理するのは「情報」ではなく「意思決定の履歴」です。**

```
顧客のメール・会話
    ↓ 自動分解・分類（AIエンジン）
意味単位（ITEM）
    ↓ 対応判断（ACTION）
課題（ISSUE）
    ↓ 実装・リリース
決定ログ（なぜそうなったか）
```

すべての情報が一本の線でつながり、1クリックで根拠まで遡れます。

---

## 現在の実装状態（Phase 1 MVP 完了）

| 機能 | 状態 |
|---|---|
| 要望分解エンジン（AI分類） | ✅ 完了（Intent正解率 87%以上） |
| ダッシュボード（INPUT/ITEM/ISSUE カウント） | ✅ 完了 |
| 要望登録フロー（3ステップUI） | ✅ 完了 |
| ITEM編集・削除（STEP2） | ✅ 完了 |
| ACTION設定・課題化 | ✅ 完了 |
| 課題一覧・詳細 | ✅ 完了 |
| 意思決定トレーサー（右パネル） | ✅ 完了 |
| コメント機能（課題詳細） | ✅ 完了 |
| Action↔Issue 双方向リンク | ✅ 完了 |
| バックエンドテストカバレッジ | ✅ **80.1%** |
| 外部アクセス（LAN内） | ✅ 完了（192.168.1.11） |

---

## 主要機能

| 機能 | 説明 |
|---|---|
| **要望分解エンジン** | メール・会話テキストをAI+ルールで自動分解・分類。Intent（8種）× Domain（8種）で分類し信頼度を算出 |
| **意思決定トレーサー** | 課題→ACTION→ITEM→原文（RAW_INPUT）まで一発で遡れる。「なぜこの仕様か」が常に追跡可能 |
| **対応漏れゼロ設計** | すべてのITEMにACTIONが必須。未処理は視覚的に強調表示され対応漏れを防ぐ |
| **コンテキスト統合** | 課題・会話・要望・決定ログを横断検索。情報は必ず何かに紐づく設計（フローティング情報なし） |

---

## 技術スタック

| レイヤー | 技術 | バージョン |
|---|---|---|
| Frontend | React + Vite + TypeScript | Node.js 20 LTS |
| Backend API | FastAPI | Python 3.12 |
| 分解エンジン | Python（独自実装） | pyenv管理 |
| Database | PostgreSQL | 16（Docker） |
| Cache | Redis | 7（Docker） |
| Web Server | nginx | 1.27（Docker） |
| ORM | SQLAlchemy + Alembic | 2.0系 |
| 認証 | OAuth2 + JWT | python-jose |
| コンテナ | Docker + Docker Compose v2 | — |

---

## ポート構成

| サービス | ポート | URL |
|---|---|---|
| フロントエンド | 3008 | http://localhost:3008 |
| バックエンドAPI | 8089 | http://localhost:8089 |
| Swagger UI | 8089 | http://localhost:8089/docs |
| nginx（統合） | 8888 | http://localhost:8888 |
| PostgreSQL | 5439 | localhost:5439 |
| Redis | 6380 | localhost:6380 |

> **Note:** 他サービスとの衝突回避のため標準ポートを使用していません。変更不可。

---

## 必要環境

- Ubuntu 24.04 LTS
- Docker + Docker Compose v2
- Node.js 20 LTS（nvm管理）
- Python 3.12（pyenv管理）
- CPU: 2コア以上 / メモリ: 4GB以上 / ディスク: 20GB以上

---

## セットアップ手順

### 初回セットアップ（スクリプト順実行）

```bash
cd ~/projects/decision-os/scripts

# Step 1: OS・Docker・Node.js・Python 環境整備
bash 01_server_setup.sh

# Dockerグループ反映（初回のみ）
newgrp docker

# Step 2: プロジェクト構成生成（ディレクトリ・docker-compose・.env・Makefile）
bash 02_project_setup.sh

# Step 3: バックエンドセットアップ（Python venv・FastAPI・Alembic・エンジン）
bash 03_backend_setup.sh

# Step 4: フロントエンドセットアップ（npm install・ビルド確認）
bash 04_frontend_setup.sh

# Step 5: 全サービス起動
bash 05_launch.sh
```

---

## 🚀 起動方法（2回目以降）

### ワンコマンド起動（推奨）

```bash
cd ~/projects/decision-os/scripts
bash 05_launch.sh
```

### 手動起動

```bash
# ① Docker（DB・Redis）
cd ~/projects/decision-os
docker compose up -d db redis

# ② バックエンド（ターミナル1）
cd ~/projects/decision-os/backend
source .venv/bin/activate
nohup uvicorn app.main:app --host 0.0.0.0 --port 8089 --reload \
  > ~/projects/decision-os/logs/backend.log 2>&1 &
sleep 3 && curl -s http://localhost:8089/docs > /dev/null && echo "✅ バックエンド起動OK"

# ③ フロントエンド（ターミナル2）
cd ~/projects/decision-os/frontend
npm run dev
```

### Makeコマンド

```bash
make up    # Docker起動
make be    # バックエンド起動
make fe    # フロントエンド起動
```

---

## ✅ 動作確認手順

### 1. ブラウザでアクセス

```
# 同じPC
http://localhost:3008

# LAN内の別PC・スマホ（サーバーのIPアドレスを指定）
http://192.168.1.11:3008

# API仕様書（Swagger UI）
http://localhost:8089/docs
```

### 2. ログイン

```
メールアドレス: demo@example.com
パスワード:     demo1234
ロール:         PM
```

### 3. E2Eフロー確認（一本通し）

```
① ダッシュボード確認
   → INPUT件数 / ITEM件数 / ISSUE件数が表示されることを確認

② 要望登録（STEP1）
   → 「＋要望を登録」をクリック
   → テキストを入力して「分解実行」
   → ITEMリストが表示されることを確認

③ ITEM編集（STEP2）
   → ✏️ ボタンでテキスト編集
   → 🗑 ボタンで不要なITEM削除
   → 各ITEMに「CREATE_ISSUE」を選択

④ 課題化（STEP3）
   → 「ACTIONを確定する」をクリック
   → 「課題一覧へ」ボタンで遷移を確認

⑤ 課題詳細・トレーサー確認
   → 課題一覧から任意の課題をクリック
   → 右パネルに ISSUE→ACTION→ITEM→INPUT の連鎖が表示されることを確認

⑥ コメント投稿
   → 課題詳細の左カラム下部にコメントを入力
   → Ctrl+Enter で送信
   → ✏️編集 / 🗑削除 ボタンが表示されることを確認

⑦ ダッシュボードに戻り
   → ISSUEのカウントが増えていることを確認
```

---

## プロセス管理

```bash
# ログ確認
tail -f ~/projects/decision-os/logs/backend.log

# バックエンド再起動
pkill -f "uvicorn app.main"
cd ~/projects/decision-os/backend && source .venv/bin/activate
nohup uvicorn app.main:app --host 0.0.0.0 --port 8089 --reload \
  > ~/projects/decision-os/logs/backend.log 2>&1 &

# 全停止
pkill -f "uvicorn app.main"
pkill -f "vite"
cd ~/projects/decision-os && docker compose down
```

---

## DBマイグレーション

```bash
cd ~/projects/decision-os/backend
source .venv/bin/activate

# マイグレーションファイル生成（モデル変更後）
alembic revision --autogenerate -m "変更内容の説明"

# 適用
alembic upgrade head

# 状態確認
alembic current
```

---

## テスト実行

```bash
cd ~/projects/decision-os/backend
source .venv/bin/activate

# 全テスト実行（カバレッジ付き）
python -m pytest tests/ -q \
  --cov=app --cov=engine \
  --cov-report=term-missing \
  --ignore=tests/test_engine_accuracy.py

# 特定ファイルのみ
python -m pytest tests/test_issues.py -v

# カバレッジのみ確認
python -m pytest tests/ -q --cov=app --cov=engine --cov-report=json:.coverage.json \
  --ignore=tests/test_engine_accuracy.py
python3 -c "import json; d=json.load(open('.coverage.json')); print(f'{d[\"totals\"][\"percent_covered\"]:.1f}%')"
```

**現在のカバレッジ: 80.1%**

---

## APIエンドポイント一覧

| Method | Path | 機能 |
|---|---|---|
| GET | `/health` | ヘルスチェック |
| GET | `/api/v1/ping` | 疎通確認 |
| POST | `/api/v1/auth/login` | ログイン・JWT発行 |
| POST | `/api/v1/inputs` | 原文登録 |
| GET | `/api/v1/inputs` | 原文一覧 |
| GET | `/api/v1/inputs/{id}` | 原文詳細 |
| POST | `/api/v1/analyze` | テキスト分解・分類 |
| GET | `/api/v1/items` | ITEM一覧 |
| PATCH | `/api/v1/items/{id}` | 分類手動修正 |
| DELETE | `/api/v1/items/{id}` | ITEM削除 |
| GET | `/api/v1/actions/{id}` | ACTION取得 |
| POST | `/api/v1/actions` | ACTION設定 |
| POST | `/api/v1/actions/{id}/convert` | 課題化 |
| GET | `/api/v1/issues` | 課題一覧（フィルタ・ソート対応） |
| POST | `/api/v1/issues` | 課題作成 |
| GET | `/api/v1/issues/{id}` | 課題詳細 |
| PATCH | `/api/v1/issues/{id}` | 課題更新 |
| GET | `/api/v1/conversations` | コメント一覧 |
| POST | `/api/v1/conversations` | コメント投稿 |
| PATCH | `/api/v1/conversations/{id}` | コメント編集 |
| DELETE | `/api/v1/conversations/{id}` | コメント削除 |
| GET | `/api/v1/trace/{issue_id}` | トレーサビリティ取得（ISSUE→ACTION→ITEM→INPUT） |
| GET | `/api/v1/dashboard/counts` | ダッシュボード集計 |
| POST | `/api/v1/decisions` | 決定ログ記録 |
| GET | `/api/v1/decisions` | 決定ログ一覧 |
| GET | `/api/v1/search?q=` | 横断検索 |
| GET | `/api/v1/labels` | ラベル一覧 |
| GET | `/api/v1/projects` | プロジェクト一覧 |

完全なAPI仕様は Swagger UI で確認できます：http://localhost:8089/docs

### 課題一覧フィルタ・ソートオプション

```
GET /api/v1/issues
  ?status=open|in_progress|resolved|closed
  ?priority=high|medium|low
  ?assignee_id=<uuid>
  ?label=<文字列>
  ?date_from=2026-01-01
  ?date_to=2026-12-31
  ?intent_code=BUG,REQ
  ?q=<キーワード>
  ?sort=created_at_desc|created_at_asc|priority_desc|due_date_asc
```

---

## コアオブジェクト構造

```
RAW_INPUT（原文）
  └─ INTERPRETATION（解釈・要約）
       └─ ITEM（意味単位）× N
            └─ ACTION（対応判断）
                 ├─ ISSUE（課題）← CREATE_ISSUE の場合
                 │    ├─ CONVERSATION（コメント）× N
                 │    └─ DECISION（決定ログ）× N
                 └─ linked_issue（既存課題へのリンク）← LINK_EXISTING の場合
```

| オブジェクト | 役割 |
|---|---|
| RAW_INPUT | 原文の完全保存・改変禁止。メール・会話・会議メモ等 |
| INTERPRETATION | 文書全体の意図・トーン・重要度の解釈 |
| ITEM | 1文書をN個の意味単位に分解したもの。Intent × Domain で分類 |
| ACTION | 各ITEMへの対応判断（課題化/回答/保存/却下/保留/既存リンク） |
| ISSUE | 課題チケット。状態・担当者・期限・優先度を持つ |
| CONVERSATION | 課題に紐づくコメント（編集・削除対応） |
| DECISION | 誰が・なぜ・何を・どう変えたかの完全記録 |

---

## Intent分類コード

| コード | 意味 | 例 |
|---|---|---|
| BUG | 不具合報告 | エラーが出る、動かない |
| REQ | 機能要望 | ～してほしい、～があれば |
| IMP | 改善提案 | ～の方が使いやすい |
| QST | 質問 | ～はどうすれば？ |
| MIS | 認識相違 | ～と思っていたが違う |
| FBK | フィードバック | ～は良かった |
| INF | 情報提供 | ～という状況です |
| TSK | タスク | ～をやること |

---

## Domain分類コード

| コード | 意味 |
|---|---|
| UI | ユーザーインターフェース |
| API | バックエンドAPI |
| DB | データベース |
| AUTH | 認証・権限 |
| PERF | パフォーマンス |
| SEC | セキュリティ |
| OPS | 運用・インフラ |
| SPEC | 仕様・設計 |

---

## 開発ロードマップ

| フェーズ | 状態 | 内容 |
|---|---|---|
| Phase 0 | ✅ 完了 | 要件定義・設計・環境構築 |
| **Phase 1 MVP** | ✅ **完了** | 入力・分解・分類・Action判定・基本UI・テスト80% |
| Phase 2 精度改善 | 🟡 次フェーズ | 自己学習・辞書強化・精度90%達成・WebSocket通知 |
| Phase 3 実運用 | 🔵 未着手 | 権限管理強化・監査ログ・横断検索UI |
| Phase 4 商用化 | 🔵 未着手 | マルチテナント・課金・SaaS公開 |

### Phase 2 候補タスク

- WebSocket対応（リアルタイム通知・更新）
- 権限管理強化（admin/pm/dev/viewer の操作制限）
- 横断検索UI（GET /search の画面実装）
- 決定ログ画面（POST /decisions の UI）
- 親子課題（エピック）・一括ACTION機能
- 分解エンジン精度改善（目標F1スコア90%以上）

---

## ディレクトリ構成

```
decision-os/
├── docker-compose.yml
├── .env                          # 環境変数（コミット禁止）
├── Makefile                      # 開発コマンド集
├── scripts/                      # セットアップ・運用スクリプト
│   ├── 01_server_setup.sh
│   ├── 02_project_setup.sh
│   ├── 03_backend_setup.sh
│   ├── 04_frontend_setup.sh
│   └── 05_launch.sh
├── backend/
│   ├── .venv/                    # Python仮想環境
│   ├── requirements.txt
│   ├── alembic.ini
│   ├── alembic/versions/         # マイグレーションファイル
│   ├── app/
│   │   ├── main.py               # FastAPIエントリポイント
│   │   ├── core/
│   │   │   ├── config.py         # 設定管理
│   │   │   ├── deps.py           # 依存性注入
│   │   │   └── security.py       # JWT認証
│   │   ├── db/session.py         # DB接続
│   │   ├── models/               # SQLAlchemyモデル
│   │   │   ├── action.py         # ACTION（issue_id / linked_issue_id）
│   │   │   ├── conversation.py   # コメント
│   │   │   ├── decision.py       # 決定ログ
│   │   │   ├── input.py          # 原文
│   │   │   ├── issue.py          # 課題
│   │   │   ├── item.py           # 意味単位
│   │   │   ├── project.py        # プロジェクト
│   │   │   └── user.py           # ユーザー
│   │   ├── schemas/              # Pydanticスキーマ
│   │   └── api/v1/routers/       # APIルーター
│   │       ├── actions.py
│   │       ├── analyze.py
│   │       ├── auth.py
│   │       ├── conversations.py
│   │       ├── dashboard.py
│   │       ├── decisions.py
│   │       ├── inputs.py
│   │       ├── issues.py
│   │       ├── items.py
│   │       ├── labels.py
│   │       ├── projects.py
│   │       ├── search.py
│   │       ├── trace.py
│   │       └── ws.py
│   ├── engine/                   # 分解エンジン
│   │   ├── normalizer.py         # 前処理
│   │   ├── segmenter.py          # テキスト分解
│   │   ├── classifier.py         # Intent/Domain分類
│   │   ├── scorer.py             # 信頼度スコア算出
│   │   └── dictionary/           # 分類辞書
│   └── tests/                    # テスト（カバレッジ 80.1%）
├── frontend/
│   ├── vite.config.ts
│   └── src/
│       ├── App.tsx
│       ├── pages/
│       │   ├── Dashboard.tsx     # ダッシュボード（INPUT/ITEM/ISSUEカウント）
│       │   ├── InputNew.tsx      # 要望登録（3ステップ）
│       │   ├── IssueList.tsx     # 課題一覧
│       │   └── IssueDetail.tsx   # 課題詳細（トレーサー＋コメント）
│       ├── api/client.ts         # APIクライアント
│       └── types/index.ts        # 型定義
└── docker/
    ├── nginx/nginx.conf          # リバースプロキシ設定
    └── postgres/init.sql         # DB初期化
```

---

## 権限モデル

| ロール | 権限 |
|---|---|
| Admin | 全操作・辞書編集・テナント管理 |
| PM | 要望管理・ACTION判定・ガントチャート |
| Dev | 課題操作・会話・ステータス更新 |
| Viewer | 閲覧のみ |

> **現状:** 全ロールでフルアクセス（Phase 3で権限制御を実装予定）

---

## Makeコマンド一覧

```bash
make up          # Dockerサービス起動
make down        # Dockerサービス停止
make be          # バックエンド起動（ホットリロード）
make fe          # フロントエンド起動（ホットリロード）
make migrate     # DBマイグレーション実行
make test        # 全テスト実行
make test-be     # バックエンドテスト
make test-fe     # フロントエンドテスト
make lint        # 全Lint実行
make reset-db    # DB完全リセット（開発用・データ消去）
```

---

## ライセンス

社内限定 / Internal use only
