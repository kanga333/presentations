
<!-- *template: gaia -->

## DockerとMake

###### kagawa shoichi (@kanga333)
###### 2018/5/28 
###### Container SIG Meet-up 2018 Summer LT

---
<!-- *template: invert -->

## 自己紹介

![50%](images/kanga333.jpg)
- @kanga333(香川翔一)
- MicroAd,Inc インフラチーム
  - 広告配信サーバやデータ基盤などを構築/運用

---

## はじめに

- DockerとMakeのTipsについてとりとめなく話します
  - DockerのビルドにMakeを使う
  - Makeの実行環境としてDocker使う

---

## DockerのビルドにMakeを使う

---

## docker buildコマンド打つの面倒

- プライベートレジストリ使ってるとイメージネームは長くなる

```
docker build \
  -t registry.example/infra/container-sig:0.0.1
docker push \
  registry.example/infra/container-sig:0.0.1
```

- 複数タグつけたい場合は尚更

```
export REVISION=`git rev-parse --short HEAD`
docker build \
  -t registry.example/infra/container-sig:0.0.1
  -t registry.example/infra/container-sig:production
  -t registry.example/infra/container-sig:$REVISION
```

---

## Makeの出番

- こんな感じで複数タグでビルドできます(抜粋)

```
NAME      := container-sig
VERSION   := 0.0.1
REVISION  := $(shell git rev-parse --short HEAD)
TAGS      := production $(REVISION) $(VERSION)
REGISTRY  := registry.example
SPACE     := infra

build:
  @docker build \
    $(addprefix -t $(REGISTRY)/$(USER)/$(NAME):,$(TAGS))\
    .
push:
  @for TAG in $(TAGS); do\
    docker push $(REGISTRY)/$(USER)/$(NAME):$$TAG; \
  done
```

- 実行は`make build`と`make push`だけ

---

## 話変わって皆さんイメージにlabel付けてますか？

- Dockerのイメージにメタデータを付与できる

```
FROM alpine:latest

LABEL description="This is a labeled image"
```

```
docker build -t labeled .
```
- inspectで確認可能
```
docker inspect \
  --format "{{ index .Config.Labels }}" \
  labeled
```
```
map[description:This is a labeled image]
```

---

## labelって何に約立つ？

- dockerのlog-optでラベルを指定するとログに出力される
  - gitのrevisionとか埋めるとデバッグに便利
  - けどk8sでサポートされてない...っぽい
    - dockerに依存したオプションのため
    - https://github.com/kubernetes/kubernetes/issues/15478
- cAdvisorの/metricsエンドポイントはlabelを出力してくれる
  - container_label_"label名"という形式で表示される

---

## --build-argと組み合わせてビルド時にlabel情報を渡す

- LABELをARGで定義した変数から渡すようにする

```
FROM alpine:latest

ARG REVISION=unknown
LABEL revision=$REVISION
```

- ビルド時に引数として渡す

```
REVISION=`git rev-parse --short HEAD`

docker build \
  --build-arg REVISION=$REVISION \
  -t labeled .
```

---

## 長くなったbuildコマンドはmakeで簡略化

- 抜粋

```
build:
  @docker build \
    --build-arg REVISION=$(REVISION) \
    $(addprefix -t $(REGISTRY)/$(USER)/$(NAME):,$(TAGS))\
    .
```

---

## Makeの実行環境としてDocker使う

---

## 最近の弊社のリポジトリ構成

File3兄弟

- Dockerfile
  - 本番で使うイメージやMakeで使う実行環境のイメージなど
- Makefile
  - テストやビルドなどの実行を行うタスクランナー
- Jenkinsfile
  - CI/CDの各フェーズでMakeをキックするパイプラインの設定

---

## MakeのタスクをDockerコンテナ内で実行する

- Makefile抜粋

```
DOCKER    := docker run -w /tmp/work -v `pwd`:/tmp/work
CONTAINER := $(DOCKER) $(REGISTRY)/$(USER)/$(NAME):production

build:
	@$(CONTAINER) build_command
```

- docker runのオプションで
  - プロジェクト直下をマウントする`-v `pwd`:/tmp/work`
  - かつworkspaceを使う `-w /tmp/work`

---

## メリット

- 新メンバーの環境構築が楽（MakeとDockerあればよい）
- 環境差分を抑えられる（開発者間, ローカルとCI/CD）
- CI/CDツールやサーバへの依存度を抑えられる
  - Jenkins側にもMakeとDockerがあれば良い
  - Dockerに対応していれば他のツールへの置き換えも楽なはず

---

## まとめ

- Makeを使えばDockerのビルドを簡略化できます
- Dockerを使えばMakeの実行環境の移植性が高められます
- 組織にあった方法で良き開発ライフを
