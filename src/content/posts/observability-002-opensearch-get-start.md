---
title: OpenSearch 入門：架設你的第一個叢集
description: 學習如何快速架設 OpenSearch 叢集，涵蓋 Bonsai、Docker 與 AWS 方案
date: 2025-12-03
slug: observability-002-opensearch-get-start
series: "observability"
tags:
  - "observability"
  - "opensearch"
---

:::note
**前置閱讀**

本文假設你已經讀過系列的前幾篇文章：
- [為什麼需要 Observability？](/posts/observability-000-intro)——理解 Observability 的核心概念
- [Log Pipeline 架構與工具選型](/posts/observability-001-log-pipeline)——理解 Log Pipeline 各元件的角色

本文會使用 Docker 快速架設 OpenSearch，如果你不熟悉 Docker，建議先了解 Docker 和 Docker Compose 的基本操作。
:::

## 架設你的第一個 OpenSearch

架設一個 OpenSearch Cluster 並不困難，但不是一開始入門 OpenSearch
所應該馬上做的事，因為 OpenSearch Cluster 的架設與維護需要一定的資源與經驗。

以下會介紹幾種常見測試 OpenSearch 架設方式：

1. [Bonsai free trial](https://bonsai.io/pricing)
2. [OpenSearch Docker](https://opensearch.org/docs/latest/opensearch/install/docker/)
3. [AWS OpenSearch Service, little costly](https://aws.amazon.com/tw/opensearch-service/)

### 1. Bonsai free trial

Bonsai 提供免費的 OpenSearch Cluster 服務，適合用來測試與學習 OpenSearch。

基本上如果對 OpenSearch 只是想要快速體驗 or 練習，Bonsai 是一個不錯的選擇。

### 2. OpenSearch Docker

如果你想要在本地端或是自己的伺服器上架設 OpenSearch，
或是想要練習 OpenSearch 的設定與管理，
可以使用 Docker 來快速架設一個 OpenSearch Cluster。

以下是使用 Docker Compose 架設 OpenSearch 以及 OpenSearch Dashboards 的範例：

```yaml
---
services:
  opensearch:
    image: opensearchproject/opensearch:3.1.0
    container_name: opensearch
    environment:
      cluster.name: opensearch-cluster
      node.name: opensearch
      discovery.type: single-node
      bootstrap.memory_lock: true
      # DO NOT USE IN PRODUCTION: minimum security configuration
      OPENSEARCH_INITIAL_ADMIN_PASSWORD: P@ssw0rdqjwekl
      # uncomment following value if your machine has less memory
      # OPENSEARCH_JAVA_OPTS: -Xms512m -Xmx512m
    ulimits:
      memlock:
        soft: -1
        hard: -1
      nofile:
        soft: 65536 # maximum number of open files for the OpenSearch user, set to at least 65536 on modern systems
        hard: 65536
    ports:
      - 9200:9200
      - 9600:9600 # required for Performance Analyzer
    networks:
      - opensearch-net
    volumes:
      - opensearch-data:/usr/share/opensearch/data

  opensearch-dashboards:
    image: opensearchproject/opensearch-dashboards:3.1.0
    container_name: opensearch-dashboards
    ports:
      - 5601:5601
    expose:
      - "5601"
    environment:
      OPENSEARCH_HOSTS: '["https://opensearch:9200"]'
    networks:
      - opensearch-net
volumes:
  opensearch-data:

networks:
  opensearch-net:
```

## 檢測你的 OpenSearch admin 帳號權限

當你架設好 OpenSearch 之後，建議你可以先檢測一下你的 admin 帳號權限是否正確。
因為 OpenSearch 預設可以使用 admin 帳號登入以及預先 boostrap 好的 kirk 帳號，
但有時候會因為設定錯誤導致 admin 帳號權限不足，無法進行後續的操作。

以下兩種方式分別可以檢測你的 OpenSearch admin 帳號權限：

1. 使用 OpenSearch Dashboards 進行檢測
2. 使用 OpenSearch API 進行檢測

### 1. 使用 kirk 帳號進行檢測(Optional, only for docker compose setup)

由於 docker compose 預設會建立一個名為 kirk 的使用者，並且使用預先 bootstrap
好的密碼，你也可以使用 kirk 帳號來檢測權限是否正確。

```bash
# pull opensearch prebuilt certificates
docker cp opensearch:/usr/share/opensearch/config/root-ca.pem ./root-ca.pem
docker cp opensearch:/usr/share/opensearch/config/kirk-key.pem ./kirk-key.pem
docker cp opensearch:/usr/share/opensearch/config/kirk.pem ./kirk.pem

# use kirk account to check cluster health
curl -s --cert ./kirk.pem --key ./kirk-key.pem --cacert ./root-ca.pem \
  https://localhost:9200/_cluster/health
```

### 2. 使用 OpenSearch Dashboards 進行檢測

登入 OpenSearch Dashboards(如果你用 Docker-Compose 部署，你應該會在
localhost:5601 看到對應的 OpenSearch Dashboards web gui)，如果能夠順利使用
admin 帳密登入並且看到 Dashboard 介面，表示你的 admin 帳號權限應該是正確的。

:::warning
若是無法登入，請確認你的 OpenSearch 服務是否有正常啟動，
以及是否跑 security_admin.sh 腳本來初始化安全性設定。

```bash
# 進入 opensearch container
docker exec -it opensearch bash
# 執行 security_admin.sh 來初始化安全性設定
"/usr/share/opensearch/plugins/opensearch-security/tools/securityadmin.sh" \
  -cd "/usr/share/opensearch/config/opensearch-security" \
  -icl -key "/usr/share/opensearch/config/kirk-key.pem" \
  -cert "/usr/share/opensearch/config/kirk.pem" \
  -cacert "/usr/share/opensearch/config/root-ca.pem" -nhnv
```

:::

### 3. 使用 OpenSearch API 進行檢測

你可以使用 curl 或 Postman 等工具來呼叫 OpenSearch API 來檢測 admin 帳號權限。
以下是一個使用 curl 來檢測 admin 帳號權限的範例：

```bash
curl -k -XGET -u admin:P@ssw0rdqjwekl https://localhost:9200/_cluster/health
```

:::info
通常來說 /\_cluster/health API 是不需要特別權限就可以呼叫的，但若是權限設定較為
嚴格的話，可能會需要額外的權限`cluster:monitor/health` 才能呼叫此 API,
[ref](https://docs.opensearch.org/latest/api-reference/cluster-api/cluster-health/)。
如果能夠成功取得回應，表示你的 admin 帳號權限應該是正確的。
:::

## OpenSearch Dashboards 相關 feature

在真正開始使用 OpenSearch 之前，建議你可以先熟悉一下 OpenSearch Dashboards
的 Dev Tools 功能以及 Discover 功能，這兩個功能是你日後使用/管理 OpenSearch
時非常重要的工具。

### Dev Tools

Dev Tools 提供了一個方便的介面讓你可以直接在瀏覽器中執行 OpenSearch API，
並且查看回應結果。你可以使用 Dev Tools 來執行各種 OpenSearch API，例如
建立索引、查詢資料、管理叢集等等。

1. 打開 OpenSearch Dashboards，點擊左側選單中的 Dev Tools。
2. 在 Dev Tools 中，你可以看到一個類似命令列的介面，可以輸入 OpenSearch API 的指令。
3. 輸入你想要執行的 OpenSearch API 指令，然後按下執行按鈕 (或使用快捷鍵 Ctrl + Enter)。

以下是幾個使用 Dev Tools 的範例：

```
# delete an index
DELETE /my-first-index

# create a new index
PUT /my-first-index
{
  "settings": {
    "number_of_shards": 1,
    "number_of_replicas": 0
  }
}
```

### Discover

Discover 提供了一個方便的介面讓你可以瀏覽和搜尋 OpenSearch 中的資料。
你可以使用 Discover 來查看索引中的文件，並且使用各種過濾器和搜尋條件來篩選資料。

## 小結

1. 架設 OpenSearch Cluster 有多種方式，可以根據需求選擇適合的方式。
2. 檢測 admin 帳號權限是確保 OpenSearch 正常運作的重要步驟。
3. OpenSearch Security 插件提供了強大的安全性功能，可以保護你的資料安全，
   並且修改 security 相關設定後，需要重新跑一次 security_admin.sh 指令。
4. 熟悉 OpenSearch Dashboards 的 Dev Tools 和 Discover 功能，
   有助於日後的使用與管理。

## 思考題

<details>
<summary>Q1：為什麼 Docker Compose 範例中設定了 <code>discovery.type: single-node</code>？如果不設定會怎樣？</summary>

OpenSearch 預設會嘗試與其他節點組成叢集。如果不設定 `discovery.type: single-node`，單一節點啟動時會因為找不到其他節點而無法正常運作（會一直等待 master 選舉）。

設定為 `single-node` 後，OpenSearch 會跳過叢集發現流程，直接以單節點模式運作。這只適用於開發和測試環境，生產環境應該使用多節點叢集以確保高可用性。

</details>

<details>
<summary>Q2：為什麼要設定 <code>bootstrap.memory_lock: true</code> 和 <code>ulimits.memlock</code>？</summary>

這兩個設定是為了防止 JVM heap 被 swap 到磁碟。

OpenSearch 使用 JVM 運行，如果 JVM heap 被 swap 到磁碟，會導致嚴重的效能問題（garbage collection 會變得極慢）。設定 `memory_lock: true` 告訴 OpenSearch 鎖定記憶體不被 swap，而 `ulimits.memlock: -1` 則是移除 Linux 對於 memory lock 的限制。

</details>

<details>
<summary>Q3：<code>security_admin.sh</code> 腳本做了什麼？什麼時候需要執行它？</summary>

`security_admin.sh` 是 OpenSearch Security 插件提供的管理工具，用於將安全性設定（使用者、角色、權限、audit 設定等）從 YAML 檔案載入到 OpenSearch 的內部索引中。

需要執行的時機：
1. 首次安裝 OpenSearch Security 插件後
2. 修改了 `opensearch-security/` 目錄下的任何設定檔後
3. 需要重設安全性設定時

注意：執行此腳本需要使用有權限的憑證（如 kirk 憑證），並且會覆蓋現有的安全性設定。

</details>
