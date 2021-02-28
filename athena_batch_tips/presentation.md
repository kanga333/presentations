---
marp: true
---

## Athenaを使ったバッチ処理のTIPS

###### kagawa shoichi (@kanga333)
###### 2021/3/1
###### BigData-JAWS 勉強会#16 LT

---
<!-- *template: invert -->

## 自己紹介

- Kagawa Shoichi(@kanga333)
- Infra Engineer @Speee,Inc
- ネイティブアドプラットフォームのUZOUの開発/運用
  - 主にインフラやデータ基盤周りを見ています
- 好きなAWSサービスはAthenaとCost Exploreとサポート

---

## はじめに 
- UZOUではデータ基盤にAthenaを使っていています
  - Daily3万件くらいのクエリが流れてます
  - ほとんどがバッチ処理
- この資料ではAthenaの設計/運用で培ったTIPSについて取り留めなく話ます

--- 

# Athenaが遅いと感じたら

---

## まずは基本を抑える

- データをパーティショニングする
  - `partition projection`を使うとパーティション管理不要で便利
- 列指向フォーマット+圧縮を使用する
  - 列指向: `ORC` or `Parquet`
    - おすすめは`Parquet`
    - 各種SaaSやミドルウェアのサポートが手厚い
      - `S3 Select`とか
  - 圧縮: `Snappy` or `Gzip`
    - おすすめは`Gzip`
    - Athenaはスキャン量課金なのでCPUコストより圧縮率が大事

---

## それでも遅いケース（`GetQueryExecution API`は遅い）
- バッチ処理でAthenaにクエリを投げて結果を習得したい場合を想定
- 使っているライブラリがAPIからデータを取得していると遅い
- `GetQueryExecution API`はクエリの実行結果をページネーションして返す
- 結果の件数が大きいとページネーションにより何度もリクエストを送る必要があるので遅い
  - TODO: ページネーションの件数確かめる

---

## 対応: クエリ結果ファイル(csv)をダイレクトにDLして使う
- Athenaはクエリの実行結果をcsvで`Output Location`に書き出す
- このファイルをS3から直接DLして使用すると通信回数が抑えられる
- いくつかのクライアントライブラリにこの機能を実装しているものがあります（ありがたや）
  - `awslabs/aws-data-wrangler`
  - `laughingman7743/PyAthena`
  - `burtcorp/athena-jdbc`
  - `speee/go-athena`
    - など

---

## それでも尚遅い場合（クエリ結果のサイズが大きいと遅い）
- Athenaはクエリの結果のデータサイズが大きくなるほど遅くなる特性がある
  - そもそもクエリが完了するまでにかかる時間が遅くなる

---

## クエリ結果のサイズが大きいと遅い実例
- Parquet形式のALBログ（30ファイル、計1.8GB）から`request_url`を取るクエリ

```sql
SELECT request_url
FROM alb_log
```

- 結果
  - Run time: 1 minute 27 seconds
  - Data scanned: 976.47 MB
  - クエリ結果ファイル: 5GB

---

## クエリ結果のサイズが大きいと遅い実例
- Parquet形式のALBログ（30ファイル、計1.8GB）から`request_url`のパス別の件数を取得するクエリ

```sql
SELECT url_extract_path(request_url),
       count(*)
FROM alb_logs
GROUP BY url_extract_path(request_url) 
```
- 結果
  - Run time: 4.64 seconds
  - Data scanned: 976.47 MB
  - クエリ結果ファイル: 6KB
- クエリとしては複雑になってるが素朴なSELECTより遥かに早い
  - **クエリ結果ファイルがデカくなるとAthenaは遅くなる**

---

## クエリ結果ファイルが大きくなると遅くなる原因（想像）
- なぜこのような特性となるか？
- Athena(のベースとなってるPresto)は分散処理のSQL実行エンジン
  - 大量のデータを複数のWorkerが処理するから早い
- しかしクエリ結果ファイルは最終的に1つのCSVとして出す必要がある
  - 出力の箇所を分散できないから遅い
  - おまけに結果ファイルは無圧縮なのでS3とのIO時間もかかる

---

## 対応: CTASクエリでデータを書き出してダイレクトにDLする
- `CREATE TABLE AS SELECT`(`CTAS`)クエリはSELECT結果を新しいテーブルとして作成できる
- CTASクエリは参照結果を新しいテーブル定義+S3上のデータとして作成する
- データは分散されたワーカーから複数個に分割されて作成されるので効率が良い
- バッチのクライアントはCTASでS3にデータを生成して直接DLして使用する
- クエリ実行時に透過的にCTASで実行してくれるモードを持つライブラリ
  - `awslabs/aws-data-wrangler`
  - `speee/go-athena`


---

## 実例のクエリをCTASで実行すると

```sql
CREATE TABLE tmp_table WITH (format='PARQUET') AS
SELECT request_url
FROM alb_logs
```

- 結果
  - Run time: 11.68 seconds
  - Data scanned: 976.47 MB
  - CTASで生成したデータ: 30ファイル、計977.3 MB
- 同じデータを取り出すにしてもCTASの方が7倍以上早い

---

## パーティションについてのTIPS

---

## 時系列パーティション、細かく切るか？ざっくり切るか？
- 時系列データのパーティションをどの粒度で切るか？
  - 細かく切ると
    - `year=yyyy/month=MM/day=dd`のような形式
  - ざっくり切ると
    - `dt=yyyyMMdd`のような形式
  - 年月を跨いだクエリがシンプルに書けるのでざっくり切るほうがオススメ！
    - だけども最終的にはどっちでもある程度シンプルに書けます

---

## 時系列パーティション、細かく切るか？ざっくり切るか？
- 例: 2021年1月30日から2021年2月1日までのデータを参照したい

```sql
-- 細く切った場合
year='2021' AND (
  (month='01' AND day >= '30')
  OR
  (month='02' AND day <= '01') )
)
```

```sql
-- ざっくり切った場合
dt BETWEEN '20210130' AND '20210201'
```

- ざっくり切った場合は開始と終了だけ指定すれば良いので楽


---


## 時系列パーティション、細かく切るか？ざっくり切るか？
- 例: 2021年2月のデータを参照したい
  - この場合どっちでもシンプルに書ける

```sql
-- 細く切った場合
year='2021' AND month='01'
```

```sql
-- ざっくり切った場合
dt LIKE '202102%'
```

---

## 細く切っても大丈夫！パーティションに複雑な時間指定をする
- ケース
  - パーティションをUTCの日付(`dt`)と時間(`hour`)で区切って格納している
  - 但し集計ではJSTの`2021-02-01`~`2021-02-03`の値を出したい
    - 時差を考慮するのがめんどい

---

## 細く切っても大丈夫！複雑な時間指定でパーティションを絞る

- DATE_PARSEのような関数を通してもパーティションのフィルタリングは効く

```sql
WHERE
  DATE_PARSE(concat(dt, hour),'%Y%m%d%H') >= timestamp '2021-02-01 00:00:00 Asia/Tokyo'
  AND 
  DATE_PARSE(concat(dt, hour),'%Y%m%d%H') < timestamp '2021-02-04 00:00:00 Asia/Tokyo'
```

- このクエリとスキャン量の絞り込みは同じ

```sql
 WHERE
   (dt = '20210131' AND hour >= '15' ) 
   OR dt = '20210201' 
   OR dt = '20210202' 
   OR (dt = '20210203' AND hour < '15' )
```

- ただし関数を通しているケースだとシンプルな絞り込みと比べて多少遅い

---

## Parquetを使っていればパーティションはざっくり指定でも大丈夫
- Parquetを使っていてデータ本体に時刻カラムがある場合パーティションカラムでざっくり絞って時刻カラムでちゃんと絞ってもスキャン量は抑えることでできる
- こんな感じのクエリ（timeはデータ本体にあるdatetime型のカラムと仮定）

```sql
 WHERE
   dt BETWEEN '20210131' AND '20210203'
   AND
   time >= timestamp '2021-02-01 00:00:00 Asia/Tokyo'
   AND 
   time < timestamp '2021-02-04 00:00:00 Asia/Tokyo'
```

- Parquetファイルはフッターに各カラムの統計情報（Max/Min/Count）を持っておりAthenaはそこを参照して効率よくスキャンをスキップできる
- 但しS3のGET APIのコストは余分にかかるので注意

---

## おわり
