# フェーズ3 開発

## 目的
- 設計に基づいてPOSアプリのフロントエンドとバックエンドを実装し統合する
- モックAPIから本番APIへ段階的に切り替え、オフライン要件を満たす

## 開発準備
- リポジトリ構成
  - `/frontend`：React + Vite、TypeScript、状態管理（Redux Toolkit）
  - `/backend`：NestJS + TypeScript、Prisma、Jest
  - `/infrastructure`：Terraform/CDKでAWSリソース定義
  - `/docs`：OpenAPI、設計図、手順書
- ブランチ運用：`main`（安定）、`develop`（統合）、機能ブランチ`feature/*`
- コーディング規約：ESLint(Airbnbベース)、Prettier、コミットメッセージConventional Commits

## フロントエンド実装タスク
- ベースセットアップ
  - PWA設定（`manifest.json`、Service Workerによるオフラインキャッシュ）
  - グローバルスタイル（TailwindまたはCSS変数でテーマ管理）
- 機能コンポーネント
  - `ScannerPanel`：MediaDevices API、失敗時フォールバックフォーム
  - `ProductSearch`：検索API呼び出し、結果リスト、SKU詳細表示
  - `CartList`：明細編集、割引コンポーネント、在庫警告
  - `PaymentSheet`：決済種別選択、金額確認、承認ダイアログ
  - `ReceiptModal`：メール送信フォーム、バリデーション、送信ステータス表示
  - `HistoryView`：無限スクロール、フィルタ、取消モーダル
- 状態管理と非同期
  - RTK QueryでAPIクライアント生成、オフラインキャッシュはIndexedDB + Dexie利用
  - `offlineQueue` sliceで同期状態管理、同期成功時にトースト通知
- ユニット/UIテスト
  - Jest + React Testing Libraryで主要コンポーネントのレンダリングとイベント検証
  - CypressでE2Eシナリオ（ハッピーパス、通信断パターン）を自動化

## バックエンド実装タスク
- プロジェクト骨組み：NestJSモジュール分割（`AuthModule`, `ProductsModule`, `TransactionsModule`, `ReportsModule`）
- 認証
  - デバイス登録エンドポイント（社内ツールから登録）
  - Staff PIN認証 → JWT発行、リフレッシュトークン管理
- 商品・在庫
  - `/products` GETエンドポイント、部分一致検索（ILIKE）、在庫レスポンス
  - CSV取込バッチ：S3アップロードトリガーでLambdaがPrisma経由でUPSERT
- 取引
  - `/transactions` POST：トランザクション処理、税計算、在庫減算、監査ログ
  - `/transactions/{id}/void`：取消ルール（24時間以内、ステータスが`completed`）
  - オフライン同期：`/sync/offline`でバルク受信→SQS投入→ワーカーが順次登録
- レポート
  - `/reports/daily`：指定日の日次売上CSVを生成しS3署名URLを返却
  - バッチ：毎日22:30に日次レポートを作成しSlack通知

## オフライン同期サービス
- フロント：Service Workerが`pendingSync`データをIndexedDBへ保存、バックグラウンド同期APIで送信
- バックエンド：SQSキュー`pos-offline-transactions`、Lambdaワーカーが重複チェックしPrismaトランザクション実行
- リトライ戦略：最大5回、指数バックオフ、死活監視はCloudWatch Alarm

## テスト戦略
- 単体テスト
  - フロント：Jestで主要コンポーネントカバレッジ70%以上
  - バックエンド：Jest + SupertestでAPI単体テスト、DBはTestcontainerでPostgreSQL起動
- 結合テスト
  - docker-composeでフロント/バック/DB/Redisを立ち上げ、E2Eテストスイートを実行
  - オフラインシナリオはPlaywrightでブラウザの`offline`モードを利用
- 負荷テスト
  - k6でピーク時（同時会計4台、1分間50リクエスト）をシミュレーション
- セキュリティテスト
  - OWASP ZAPで簡易脆弱性スキャン、PIN総当たり対策（Rate Limit）を確認

## CI/CDパイプライン
- GitHub Actions想定
  1. `lint`：ESLint/Prettierチェック、`npm run lint`
  2. `test`：`npm run test -- --coverage` / `npm run test:e2e`
  3. `build`：フロントビルド（Vite）、バックエンドビルド（Nest CLI）
  4. `docker`：マルチステージDockerfileでイメージ生成、ECRへプッシュ
  5. `deploy`：mainブランチマージ時にステージングへ自動デプロイ（ECS Blue/Green）

## ローカル開発環境
- 必須ツール：Node.js 20、npm、Docker Desktop、AWS CLI、Git LFS（デザインアセット）
- `.env`サンプル：
  - フロント：`VITE_API_BASE_URL`, `VITE_BUILD_VERSION`
  - バック：`DATABASE_URL`, `JWT_SECRET`, `S3_BUCKET`, `SES_REGION`
- ローカル起動：`docker-compose up`でDB/Redis/SQSローカルエミュレータ(LocalStack)を起動

## 成果物
- フロント/バックの動作するアプリケーション（ステージング環境で動作確認済み）
- 自動テスト（単体・結合・E2E）とCIレポート、主要指標をダッシュボード化
- 開発者向けセットアップ手順書（`docs/setup-guide.md`）
- リリースノートドラフト（MVP完了条件に紐づく機能一覧）

## 移行条件
- 単体テストおよび基本的な結合テストがグリーン（カバレッジ70%以上）
- オフライン同期・取消・CSV出力などクリティカルフローのE2Eテストが合格
- 残タスクと既知の不具合がチケット化され、優先度と担当者が割り当て済み
- ステージング環境の動作検証記録（スクリーンキャプチャ/ログ）が共有済み
