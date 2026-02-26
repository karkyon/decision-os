-- decision-os 初期スキーマ設定
-- Alembic が本マイグレーションを担うため、ここでは最低限の設定のみ

-- タイムゾーン設定
SET timezone = 'Asia/Tokyo';

-- UUID拡張（PostgreSQL組み込み）
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- 全文検索用（日本語対応はpg_bigmが必要だが、まずは標準で）
CREATE EXTENSION IF NOT EXISTS pg_trgm;
