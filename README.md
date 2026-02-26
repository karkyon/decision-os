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
    ↓ 自動分解・分類
意味単位（ITEM）
    ↓ 対応判断（ACTION）
課題（ISSUE）
    ↓ 実装・リリース
決定ログ（なぜそうなったか）
```

すべての情報が一本の線でつながり、1クリックで根拠まで遡れます。

---

## 主要機能

| 機能 | 説明 |
|---|---|
| **要望分解エンジン** | メール・会話テキストをAI+ルールで自動分解・分類。Intent（8種）× Domain（8種）で分類し信頼度を算出 |
| **意思決定トレーサー** | 課題→ACTION→ITEM→原文（RAW_INPUT）まで一発で遡れる。「なぜこの仕様か」が常に追跡可能 |
| **対応漏れゼロ設計** | すべてのITEMにACTIONが必須。未処理は視覚的に強調表示され対応漏れを防ぐ |
| **自己進化型辞書** | ユーザーの分類修正を学習し、分類精度が継続的に向上（目標F1スコア90%以上） |
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

### 2回目以降の起動

```bash
cd ~/projects/decision-os/scripts
bash 05_launch.sh
```

または

```bash
cd ~/projects/decision-os
make up        # Docker起動
make be        # バックエンド起動（別ターミナル）
make fe        # フロントエンド起動（別ターミナル）
```

---

## プロセス管理

```bash
# ログ確認
tail -f ~/projects/decision-os/logs/backend.log
tail -f ~/projects/decision-os/logs/frontend.log

# バックエンド停止
kill $(cat ~/projects/decision-os/.backend.pid)

# フロントエンド停止
kill $(cat ~/projects/decision-os/.frontend.pid)

# Docker停止
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

## APIエンドポイント一覧

| Method | Path | 機能 |
|---|---|---|
| GET | `/health` | ヘルスチェック |
| GET | `/api/v1/ping` | 疎通確認 |
| POST | `/api/v1/auth/login` | ログイン・JWT発行 |
| POST | `/api/v1/inputs` | 原文登録 |
| POST | `/api/v1/analyze` | テキスト分解・分類 |
| PATCH | `/api/v1/items/{id}` | 分類手動修正 |
| POST | `/api/v1/actions` | ACTION設定 |
| POST | `/api/v1/actions/{id}/convert` | 課題化 |
| GET | `/api/v1/issues` | 課題一覧 |
| POST | `/api/v1/issues` | 課題作成 |
| PATCH | `/api/v1/issues/{id}` | 課題更新 |
| GET | `/api/v1/trace/{issue_id}` | トレーサビリティ取得 |
| POST | `/api/v1/decisions` | 決定ログ記録 |
| GET | `/api/v1/search?q=` | 横断検索 |

完全なAPI仕様は Swagger UI で確認できます：http://localhost:8089/docs

---

## コアオブジェクト構造

```
RAW_INPUT（原文）
  └─ INTERPRETATION（解釈・要約）
       └─ ITEM（意味単位）× N
            └─ ACTION（対応判断）
                 └─ ISSUE（課題）
                      └─ DECISION（決定ログ）
```

| オブジェクト | 役割 |
|---|---|
| RAW_INPUT | 原文の完全保存・改変禁止。メール・会話・会議メモ等 |
| INTERPRETATION | 文書全体の意図・トーン・重要度の解釈 |
| ITEM | 1文書をN個の意味単位に分解したもの。Intent × Domain で分類 |
| ACTION | 各ITEMへの対応判断（課題化/回答/保存/却下/保留） |
| ISSUE | 課題チケット。状態・担当者・期限・優先度を持つ |
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

| フェーズ | 期間 | 内容 |
|---|---|---|
| Phase 0（完了） | — | 要件定義・設計・環境構築 |
| **Phase 1 MVP** | **3週間** | 入力・分解・分類・Action判定・基本UI |
| Phase 2 精度改善 | 4週間 | 自己学習・辞書強化・精度90%達成 |
| Phase 3 実運用 | 2週間 | 権限管理・監査ログ・WebSocket |
| Phase 4 商用化 | 4週間 | マルチテナント・課金・SaaS公開 |

**総開発工数見積：85人日（最速9週間）**

---

## ディレクトリ構成

```
decision-os/
├── docker-compose.yml
├── .env                        # 環境変数（コミット禁止）
├── Makefile                    # 開発コマンド集
├── scripts/                   # セットアップスクリプト
│   ├── 01_server_setup.sh
│   ├── 02_project_setup.sh
│   ├── 03_backend_setup.sh
│   ├── 04_frontend_setup.sh
│   └── 05_launch.sh
├── backend/
│   ├── .venv/                  # Python仮想環境
│   ├── requirements.txt
│   ├── alembic.ini
│   ├── alembic/versions/       # マイグレーションファイル
│   ├── app/
│   │   ├── main.py             # FastAPIエントリポイント
│   │   ├── core/config.py      # 設定管理
│   │   ├── db/session.py       # DB接続
│   │   ├── models/             # SQLAlchemyモデル（実装予定）
│   │   ├── schemas/            # Pydanticスキーマ（実装予定）
│   │   └── api/v1/             # APIルーター（実装予定）
│   └── engine/                 # 分解エンジン
│       ├── normalizer.py       # 前処理
│       ├── segmenter.py        # テキスト分解
│       ├── classifier.py       # Intent/Domain分類
│       ├── scorer.py           # 信頼度スコア算出
│       └── dictionary/         # 分類辞書
├── frontend/
│   ├── vite.config.ts
│   └── src/
│       ├── App.tsx
│       ├── pages/
│       │   └── Dashboard.tsx   # ダッシュボード（雛形）
│       ├── api/client.ts       # APIクライアント
│       └── types/index.ts      # 型定義
└── docker/
    ├── nginx/nginx.conf        # リバースプロキシ設定
    └── postgres/init.sql       # DB初期化
```

---

## 権限モデル

| ロール | 権限 |
|---|---|
| Admin | 全操作・辞書編集・テナント管理 |
| PM | 要望管理・ACTION判定・ガントチャート |
| Dev | 課題操作・会話・ステータス更新 |
| Viewer | 閲覧のみ |

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
