# OpenProject PJ 管理環境

OpenProject Community Edition をベースにした、小規模PJ向けの進捗管理環境です。

以下をDocker Composeでまとめて起動します。

- OpenProject: チケット、ガントチャート、工数管理
- Nginx: OpenProjectの前段プロキシ、ガント向けCSSの追加配信
- Baseline API: 名前付き計画スナップショットの保存
- 計画比較画面: ベースラインと現在計画の一覧・ガント比較

Enterprise add-ons は利用しません。Enterprise案内と設定画面は非表示にしています。

## 対応環境

### 推奨

- Ubuntu Server
- WSL 2 上の Ubuntu

### 必要なもの

- Docker Engine
- Docker Compose Plugin
- Git

Docker Desktop は不要です。

## 最短構築手順

Docker Engineが導入済みのUbuntuで、以下を1行ずつ実行します。

### 1. リポジトリをクローンする

```bash
git clone <repository-url>
```

### 2. ディレクトリへ移動する

```bash
cd sandbox-custom-openproject4docker
```

### 3. 初期構築スクリプトを実行する

```bash
bash scripts/Bootstrap.sh
```

初回実行時に `.env` とランダムな `SECRET_KEY_BASE` が自動生成されます。

### 4. 起動を確認する

```bash
docker compose ps
```

3つのコンテナが `Up` または `running` になれば起動完了です。

```text
openproject
web
baseline-api
```

### 5. ブラウザで開く

```text
http://localhost:8080
```

初回ログイン:

```text
ユーザー名: admin
パスワード: admin
```

ログイン直後に管理者パスワードを変更してください。

## Docker Engine 未導入の場合

### WSL 2 上の Ubuntu

#### 1. WindowsでWSL 2とUbuntuを導入する

管理者権限のPowerShellで実行します。

```powershell
wsl --install -d Ubuntu
```

Windowsを再起動し、Ubuntuの初回起動時にLinuxユーザーを作成します。

#### 2. Ubuntuを開く

```powershell
wsl -d Ubuntu
```

#### 3. Gitを導入する

```bash
sudo apt-get update
```

```bash
sudo apt-get install -y git
```

#### 4. リポジトリをクローンする

```bash
git clone <repository-url>
```

```bash
cd sandbox-custom-openproject4docker
```

#### 5. Docker Engineと本環境を構築する

```bash
bash scripts/Setup-WslDocker.sh
```

途中でUbuntuの `sudo` パスワードを入力します。Docker Engine、Docker Compose Plugin、OpenProjectが順番に導入されます。

### Ubuntu Server

Docker公式手順でDocker EngineとDocker Compose Pluginを導入してください。

- [Install Docker Engine on Ubuntu](https://docs.docker.com/engine/install/ubuntu/)

導入後は「最短構築手順」を実行します。

## デモPJを投入する

「出庫状況照会機能」と「出庫状況登録機能」を題材にしたアジャイル開発サンプルを投入できます。

構成:

- PJリーダー: 1名
- メンバー: 3名
- スプリント: 4件
- チケット: 23件
- 初期予定工数: 235時間

### 1. デモ投入スクリプトをコンテナへコピーする

```bash
docker compose cp scripts/Seed-AgileShipmentDemo.rb openproject:/tmp/Seed-AgileShipmentDemo.rb
```

### 2. デモPJを投入する

```bash
docker compose exec -T openproject env RAILS_ENV=production bundle exec rails runner /tmp/Seed-AgileShipmentDemo.rb
```

### 3. 初期計画をベースラインとして保存する

```bash
bash scripts/Manage-Baseline.sh snapshot shipment-status-agile-demo "初期計画" "デモPJ作成直後"
```

### 4. ガントチャートを開く

```text
http://localhost:8080/projects/shipment-status-agile-demo/gantt
```

## 比較表示用の模擬変更を投入する

追加、削除、工数変更、期間変更の表示を確認できます。

### 1. 模擬変更スクリプトをコンテナへコピーする

```bash
docker compose cp scripts/Apply-BaselineDiffDemo.rb openproject:/tmp/Apply-BaselineDiffDemo.rb
```

### 2. 模擬変更を投入する

```bash
docker compose exec -T openproject env RAILS_ENV=production bundle exec rails runner /tmp/Apply-BaselineDiffDemo.rb
```

### 3. 現在計画を更新する

```bash
bash scripts/Manage-Baseline.sh refresh shipment-status-agile-demo
```

### 4. 計画比較画面を開く

```text
http://localhost:8080/baseline/?project=shipment-status-agile-demo
```

## 計画比較機能

OpenProject画面の「計画比較」ボタンから開きます。

確認できる差分:

- チケット追加・削除
- 開始日・終了日の変更
- 予定工数の変更
- 担当者の変更
- ステータスの変更
- ガントチャート上の差分

比較画面の「スナップショットを作成」ボタンから、任意時点の計画を保存できます。

コマンドで保存する場合:

```bash
bash scripts/Manage-Baseline.sh snapshot shipment-status-agile-demo "Sprint 1開始時点" "照会機能着手前"
```

## 日常操作

### 起動する

```bash
docker compose up -d
```

### 状態を確認する

```bash
docker compose ps
```

### 停止する

```bash
docker compose down
```

### ログを確認する

```bash
docker compose logs --tail=100
```

### OpenProjectを更新する

更新前にバックアップを取得してください。

```bash
docker compose pull
```

```bash
docker compose up -d
```

## データ保存先

Docker Volume:

- `openproject_pgdata`: PostgreSQLデータ
- `openproject_assets`: 添付ファイルなど

ホスト側:

- `data/baselines`: 計画スナップショット

`.env` と `data/baselines` 内のJSONはGit管理対象外です。

## カスタマイズ

### ガントチャートCSS

```text
infra/nginx/gantt-theme.css
```

### 計画比較画面

```text
infra/nginx/baseline
```

### 計画保存API

```text
infra/baseline-api/server.py
```

## 本番運用前の注意

現在の構成は評価・小規模利用向けです。本番運用へ移す場合は以下を実施してください。

- Ubuntu Serverなどの常時起動環境へ配置する
- TLS対応のリバースプロキシを配置する
- `.env` の `OPENPROJECT_HOST_NAME` と `OPENPROJECT_HTTPS` を変更する
- PostgreSQL、添付ファイル、`data/baselines` を定期バックアップする
- 計画比較画面とBaseline APIに認証を追加する
- Dockerイメージのバージョンを固定し、更新前にバックアップする

## 公式資料

- [OpenProject Community Edition](https://www.openproject.org/community-edition/)
- [OpenProject Gantt charts](https://www.openproject.org/docs/user-guide/gantt-chart/)
- [OpenProject Time tracking](https://www.openproject.org/docs/user-guide/time-and-costs/time-tracking/)
- [OpenProject Docker installation](https://www.openproject.org/docs/installation-and-operations/installation/docker/)
- [Docker Engine on Ubuntu](https://docs.docker.com/engine/install/ubuntu/)
