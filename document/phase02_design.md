# フェーズ2 設計

## 目的
- MVPを実装可能なUI・API・データモデルの詳細設計を確定し、フロントエンド/バックエンドの開発着手条件を満たす

## 設計対象範囲
- フロントエンド：POS Webアプリ（PWA対応、iPad/Androidハンディ最適化）
- バックエンド：APIサーバー（Node.js + NestJS想定）、認証、同期キュー処理
- データ層：AWS RDS(PostgreSQL)とS3、CloudWatch、SQS
- 外部：社内会計システムへのCSV連携、メール送信サービス（SES）

## UI/UX設計
- 主要画面
  1. ログイン（PIN入力、スタッフ/マネージャー切替）
  2. 会計（スキャンタブ／検索タブ、カート、合計パネル）
  3. 決済確認（決済種別選択、金額表示、確定ボタン）
  4. 取引完了（レシート送信、次取引ボタン、サマリ）
  5. 取引履歴（一覧、詳細モーダル、取消ボタン）
- レイアウト仕様
  - 12カラムグリッド、最小幅1024px、ハンディ端末はブレークポイント768pxで縦レイアウト
  - 主要ボタン：高さ56px、Primaryカラー #0051A2、ホバー時 #1B64B5、無効時 #7FA9D6
  - アラートトースト：右上表示、4秒で自動消滅、ARIAライブリージョンを設定
- 状態管理
  - グローバルストア（Redux Toolkit/ Zustand検討）でカート、ユーザー、ネットワーク状態を保持
  - ネットワーク状態はService Workerで監視し、`isOffline`フラグを更新
  - エラー種類（バリデーション/通信/システム）ごとにUIコンポーネントを分離
- アクセシビリティ
  - フォーカスインジケータを2pxアウトラインで統一
  - スクリーンリーダー向けにボタンへ`aria-label`を設定（例：削除ボタン → `aria-label="カートから削除"`）
  - 日本語/英語トグルをヘッダー右上へ配置、i18n辞書はJSONで管理

## 画面遷移・状態図
- ログイン → 会計 → 決済確認 → 取引完了 → (新規会計 or 終了)
- 取引履歴はヘッダーからモーダル遷移（セッション維持）。マネージャー承認モーダルはPIN入力成功時に取消APIを実行。
- オフライン遷移：会計画面で通信断検知 → バナー表示 → 会計確定時に`pendingSync`ステータスでローカル保存 → 後段の同期サービスが成功時`completed`へ変換

## コンポーネント仕様（抜粋）
| コンポーネント | 主要Props | イベント | エラーハンドリング |
| --- | --- | --- | --- |
| `ScannerPanel` | `onScan`, `deviceId`, `mode` | `SCAN_SUCCESS`, `SCAN_ERROR` | カメラ拒否→`PermissionDialog`表示 |
| `ProductSearch` | `query`, `onSelect` | `SEARCH_SUBMIT`, `ITEM_SELECTED` | 0件時は"該当なし"ラベルとCSVインポート案内 |
| `CartList` | `items`, `onUpdateQuantity`, `onRemove` | `QUANTITY_CHANGED`, `ITEM_REMOVED` | 在庫不足→`StockWarning`バナー |
| `PaymentSheet` | `total`, `discount`, `onSubmit` | `PAYMENT_CONFIRMED` | オフライン時はカード選択不可でトグル無効化 |

## API設計
- 共通仕様
  - Base URL：`/api/v1`
  - 認証：Deviceトークン + ユーザーPIN（初回ログインでJWT発行、リフレッシュ有効期限8時間）
  - エラーフォーマット：`{ "code": "string", "message": "string", "details": {...} }`
  - タイムアウト：フロント10秒、再試行は冪等エンドポイントのみ（最大3回指数バックオフ）
- エンドポイント一覧

| Method | Path | 概要 | 主なResponse | エラーコード |
| --- | --- | --- | --- | --- |
| POST | /auth/login | PINログイン | 200: `{token, role, expiresAt}` | AUTH_INVALID_PIN, DEVICE_UNREGISTERED |
| GET | /products/{barcode} | バーコード検索 | 200: `{sku, name, price, taxRate, stock}` | PRODUCT_NOT_FOUND |
| GET | /products | クエリ検索 | 200: `[{sku, name, price, stock}]` | VALIDATION_ERROR |
| POST | /transactions | 取引登録 | 201: `{transactionId, status}` | STOCK_SHORTAGE, PAYMENT_DECLINED, OFFLINE_QUEUED |
| GET | /transactions | 取引一覧 | 200: `[{transactionId, total, createdAt, status}]` | AUTH_FORBIDDEN |
| POST | /transactions/{id}/void | 取消 | 200: `{transactionId, status: "voided"}` | VOID_NOT_ALLOWED |
| POST | /sync/offline | オフラインキュー同期 | 202: `{accepted, failed}` | PAYLOAD_TOO_LARGE |
| GET | /reports/daily | 日次レポートCSV | 200: `text/csv` | REPORT_NOT_READY |

- 擬似OpenAPI（例：POST /transactions）
```yaml
requestBody:
  application/json:
    schema:
      type: object
      required: [items, payment]
      properties:
        items:
          type: array
          items:
            type: object
            required: [sku, quantity, unitPrice]
            properties:
              sku: { type: string }
              quantity: { type: integer, minimum: 1 }
              unitPrice: { type: integer }
              discount:
                type: object
                properties:
                  type: { enum: [percentage, amount] }
                  value: { type: number }
        payment:
          type: object
          required: [method, amount]
          properties:
            method: { enum: [cash, card] }
            amount: { type: integer }
            reference: { type: string }
        customer:
          type: object
          properties:
            email: { type: string, format: email }
responses:
  '201':
    description: Created
    content:
      application/json:
        schema:
          type: object
          properties:
            transactionId: { type: string }
            status: { enum: [completed, offlineQueued] }
            syncedAt: { type: string, format: date-time, nullable: true }
```

## データモデル設計
- ER概要
  - `users`（スタッフ/マネージャー）
  - `products`（商品マスタ）
  - `inventory_snapshots`（在庫参照キャッシュ）
  - `transactions`（取引ヘッダ）
  - `transaction_items`（取引明細）
  - `offline_queue`（オフライン取引一時保存）
  - `audit_logs`（操作監査）
- テーブル定義（抜粋）

```sql
CREATE TABLE products (
  sku              VARCHAR(32) PRIMARY KEY,
  name             TEXT NOT NULL,
  category         TEXT,
  price            INTEGER NOT NULL,
  tax_rate         NUMERIC(3,2) NOT NULL DEFAULT 0.10,
  barcode          VARCHAR(64) UNIQUE,
  updated_at       TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE TABLE transactions (
  id               UUID PRIMARY KEY,
  total_amount     INTEGER NOT NULL,
  tax_amount       INTEGER NOT NULL,
  discount_total   INTEGER NOT NULL DEFAULT 0,
  payment_method   VARCHAR(16) NOT NULL,
  payment_status   VARCHAR(16) NOT NULL,
  staff_id         UUID REFERENCES users(id),
  store_id         VARCHAR(32) NOT NULL DEFAULT 'popup-2025',
  status           VARCHAR(16) NOT NULL DEFAULT 'completed',
  created_at       TIMESTAMP NOT NULL DEFAULT NOW(),
  updated_at       TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_transactions_created_at ON transactions(created_at DESC);
```

- マイグレーション方針
  - Prisma MigrateまたはKnexを使用し、`schema.prisma`/`migrations`をGit管理
  - 初期シード：商品マスタCSV（150件）、スタッフ5名、マネージャー2名
  - オフライン用テーブルは別スキーマ`offline`に配置し、同期後に削除するジョブを用意

## システム構成
- クライアント：React + Vite、Service Workerでオフライン制御
- APIサーバー：NestJS、JWT認証、OpenAPI自動生成、Redisキャッシュ
- バックオフィスジョブ：同期キュー処理（SQSトリガー Lambda）、CSVエクスポートバッチ（Step Functions）
- インフラ：AWS Fargate(ECS)、Aurora PostgreSQL、CloudFront + S3（静的配信）、SES（メール送信）、CloudWatch Logs/Alarms
- 監視：API 95パーセンタイル応答時間、同期失敗率、オフラインキュー滞留件数をダッシュボード化

## セキュリティ設計
- 認証：端末ごとの登録コード+スタッフPIN。PINはPBKDF2でハッシュ化。
- 権限：`staff`は取引作成/閲覧、`manager`は取消/レポート、`admin`は設定。
- 通信：HTTPS必須、HSTS 6ヶ月。
- ログ/監査：`audit_logs`に操作ログを保存し、CloudWatch Metrics Filterで重要操作をアラート。

## 成果物
- UI仕様書（Figmaリンクを`design/ui-spec.md`で管理予定、プロトタイプ版1.0）
- OpenAPI 3.0定義（`api/openapi.yaml`、本ドキュメントの抜粋をベースに生成）
- DB定義書（`db/schema.sql`、テーブルDDL/インデックス/シード手順）
- アーキテクチャ図（draw.ioまたはMermaidで管理、リポジトリ`docs/architecture/`配下）

## 移行条件
- 設計レビュー完了、指摘反映済み（PO/情シス/開発リード承認）
- モックAPI（`/api/mock`）でフロント実装を開始できる状態、主要エンドポイントのスタブレスポンスを用意
- DBスキーマとマイグレーションがリポジトリに反映され、CIで適用テスト済み
