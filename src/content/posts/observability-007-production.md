---
title: 生產環境架構設計
description: OpenSearch 生產環境的高可用架構、TLS 憑證管理、容量規劃與備份策略
date: 2025-12-08
slug: observability-007-production
series: "observability"
tags:
  - "observability"
  - "opensearch"
  - "production"
---

:::note
**前置閱讀**

本文假設你已經讀過系列的前幾篇文章，並對 OpenSearch 和 Vector 有基本了解。

本文聚焦於生產環境的架構考量，適合準備將 log 系統部署到正式環境的讀者。
:::

## 生產環境 vs 開發環境

在開發環境中，我們使用單節點 Docker 快速上手。但生產環境需要考慮：

| 面向 | 開發環境 | 生產環境 |
|------|----------|----------|
| 節點數 | 單節點 | 3+ 節點 |
| 高可用 | 無 | 必須 |
| TLS | 可選 | 必須 |
| 認證 | 簡單密碼 | LDAP/SSO 整合 |
| 備份 | 無 | 定期備份 |
| 監控 | 手動檢查 | 自動告警 |

## 高可用架構

### OpenSearch 節點角色

OpenSearch 節點可以扮演不同角色：

| 角色 | 說明 | 建議配置 |
|------|------|----------|
| **Master** | 管理 cluster 狀態、index metadata | 3 個專用節點（奇數個）|
| **Data** | 儲存資料、執行查詢 | 依容量需求 |
| **Ingest** | 預處理資料（類似 Logstash） | 可選 |
| **Coordinating** | 接收請求、聚合結果 | 高查詢負載時使用 |

:::info
**為什麼 Master 節點要用奇數個（3 個）？**

這跟分散式系統的「投票機制」有關。當網路出問題導致節點彼此無法通訊時，系統需要決定「哪一邊是真正的 cluster」。

假設有 3 個 master 節點，其中 2 個在機房 A、1 個在機房 B。如果機房間網路斷線：
- 機房 A 有 2/3 的節點（超過半數），可以繼續運作
- 機房 B 只有 1/3 的節點，會停止服務

如果只有 2 個 master 節點，網路斷線時雙方各有 1 個節點，誰都無法達成「過半數」，系統就會完全停擺。這就是為什麼要用奇數個節點。

這個「過半數才能做決定」的機制叫做 **Quorum**，用來防止「腦裂」（split brain）——兩邊都以為自己是正牌 cluster，各自接受寫入，導致資料不一致。
:::

### 最小高可用架構

```
                    ┌─────────────────┐
                    │   Load Balancer │
                    │   (HAProxy/Nginx)│
                    └────────┬────────┘
                             │
         ┌───────────────────┼───────────────────┐
         │                   │                   │
         ▼                   ▼                   ▼
┌─────────────────┐ ┌─────────────────┐ ┌─────────────────┐
│   OpenSearch    │ │   OpenSearch    │ │   OpenSearch    │
│   Node 1        │ │   Node 2        │ │   Node 3        │
│   master + data │ │   master + data │ │   master + data │
└─────────────────┘ └─────────────────┘ └─────────────────┘
```

對於小型部署，可以讓每個節點同時擔任 master 和 data 角色。

### 大型生產架構

```
                         ┌─────────────────┐
                         │   Load Balancer │
                         └────────┬────────┘
                                  │
    ┌─────────────────────────────┼─────────────────────────────┐
    │                             │                             │
    ▼                             ▼                             ▼
┌─────────┐                 ┌─────────┐                 ┌─────────┐
│ Master 1│                 │ Master 2│                 │ Master 3│
│ (專用)  │                 │ (專用)  │                 │ (專用)  │
└─────────┘                 └─────────┘                 └─────────┘

┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐
│  Data 1 │ │  Data 2 │ │  Data 3 │ │  Data 4 │ │  Data 5 │
└─────────┘ └─────────┘ └─────────┘ └─────────┘ └─────────┘

                    ┌─────────────────────┐
                    │  OpenSearch         │
                    │  Dashboards         │
                    └─────────────────────┘
```

### 節點配置範例

Master 節點：
```yaml
# opensearch.yml
node.name: master-1
node.roles:
  - master
cluster.name: production-cluster
discovery.seed_hosts:
  - master-1
  - master-2
  - master-3
cluster.initial_master_nodes:
  - master-1
  - master-2
  - master-3
```

Data 節點：
```yaml
# opensearch.yml
node.name: data-1
node.roles:
  - data
  - ingest
cluster.name: production-cluster
discovery.seed_hosts:
  - master-1
  - master-2
  - master-3
```

## TLS 憑證管理

:::info
**TLS/SSL 和憑證基礎知識**

在網路上傳輸資料時，如果沒有加密，任何人只要能「監聽」網路流量（例如在同一個 WiFi 網路），就能看到你傳送的內容——包括密碼、資料庫查詢結果等敏感資訊。

**TLS**（Transport Layer Security，傳輸層安全協議）解決這個問題。它的前身是 SSL，現在這兩個名詞常被混用。TLS 做兩件事：

1. **加密**：資料在傳輸過程中被加密，即使被攔截也無法讀取
2. **身份驗證**：確認你連接的真的是目標伺服器，而不是冒充者

**憑證（Certificate）** 是 TLS 身份驗證的核心。它就像伺服器的「身分證」：
- 包含伺服器的名稱、公鑰等資訊
- 由受信任的機構（CA）簽發，證明「這個公鑰確實屬於這台伺服器」

**CA**（Certificate Authority，憑證授權機構）是發放和驗證憑證的機構。就像戶政事務所發身分證一樣，CA 負責確認申請者的身份後才簽發憑證。在企業內部，通常會建立自己的「內部 CA」來簽發內部系統使用的憑證。

**PKI**（Public Key Infrastructure，公鑰基礎建設）是整個憑證管理的體系，包括 CA、憑證的發放流程、撤銷機制等。
:::

生產環境必須啟用 TLS 加密通訊。OpenSearch 需要兩種憑證：

| 憑證類型 | 用途 |
|----------|------|
| **Transport** | 節點間通訊（必須） |
| **HTTP** | 客戶端連線（建議） |

:::info
**為什麼需要兩種憑證？**

- **Transport 憑證**：OpenSearch 節點之間會互相傳送資料（例如 replica 同步、分散式查詢）。這些通訊必須加密，否則敏感資料可能在內網被攔截。
- **HTTP 憑證**：客戶端（例如 Vector、Dashboards、你的應用程式）連接 OpenSearch 時使用。如果不加密，帳號密碼和查詢內容都是明文傳輸。

為什麼要分開？因為 Transport 層是節點之間的「內部對話」，通常用內部 CA 簽發的憑證就夠了。HTTP 層面對外部客戶端，有時候會需要使用公開 CA 簽發的憑證（例如讓瀏覽器信任）。
:::

### 憑證架構

```
Root CA
├── Transport CA
│   ├── node-1 cert
│   ├── node-2 cert
│   └── node-3 cert
└── HTTP CA
    ├── opensearch cert
    └── dashboards cert
```

### 使用 OpenSSL 產生憑證

```bash
# 1. 建立 Root CA
openssl genrsa -out root-ca-key.pem 4096
openssl req -new -x509 -sha256 -key root-ca-key.pem -out root-ca.pem -days 3650 \
  -subj "/CN=Root CA"

# 2. 建立節點憑證
openssl genrsa -out node-key.pem 4096
openssl req -new -key node-key.pem -out node.csr \
  -subj "/CN=opensearch-node-1"

# 3. 簽署憑證
openssl x509 -req -in node.csr -CA root-ca.pem -CAkey root-ca-key.pem \
  -CAcreateserial -out node.pem -days 365 -sha256
```

### OpenSearch TLS 配置

```yaml
# opensearch.yml
plugins.security.ssl.transport.pemcert_filepath: node.pem
plugins.security.ssl.transport.pemkey_filepath: node-key.pem
plugins.security.ssl.transport.pemtrustedcas_filepath: root-ca.pem
plugins.security.ssl.transport.enforce_hostname_verification: true

plugins.security.ssl.http.enabled: true
plugins.security.ssl.http.pemcert_filepath: node.pem
plugins.security.ssl.http.pemkey_filepath: node-key.pem
plugins.security.ssl.http.pemtrustedcas_filepath: root-ca.pem

plugins.security.nodes_dn:
  - CN=opensearch-node-*
plugins.security.authcz.admin_dn:
  - CN=admin
```

### 憑證更新策略

憑證會過期，需要有更新計畫：

1. **監控憑證過期時間**：設定告警在過期前 30 天通知
2. **Rolling Update**：逐個節點更新憑證，不中斷服務
3. **自動化**：使用 Ansible 或類似工具自動化更新流程

## 容量規劃

### 儲存空間估算

Log 儲存空間的粗略估算公式：

```
日儲存量 = 每秒事件數 × 86400 × 平均事件大小
月儲存量 = 日儲存量 × 30 × (1 + replica 數)
```

範例：
- 每秒 1000 events
- 平均每個 event 500 bytes
- 1 replica

```
日儲存量 = 1000 × 86400 × 500 bytes = 43.2 GB
月儲存量 = 43.2 × 30 × 2 = 2.6 TB
```

### Shard 規劃

| 建議 | 原因 |
|------|------|
| 單一 shard 大小 10-50 GB | 太大影響 recovery，太小浪費資源 |
| 每個節點 shard 數 < 20 per GB heap | 避免 memory 壓力 |
| Primary shard 數 = 資料量 / 30GB | 初始估算 |

範例：每日 43GB log，使用 2 個 primary shard（每個約 20GB）。

### JVM Heap 配置

```bash
# /etc/opensearch/jvm.options
-Xms16g
-Xmx16g
```

:::info
**為什麼 -Xms 和 -Xmx 要設成一樣？**

`-Xms` 是 JVM 啟動時的初始 heap 大小，`-Xmx` 是最大 heap 大小。

如果兩者不同，JVM 會在需要時動態擴展 heap。這個擴展過程會導致：
- 暫停應用程式（Stop-the-World）
- 可能觸發 Full GC（完整垃圾回收）

對於 OpenSearch 這種需要穩定效能的服務，我們希望避免這種動態調整。將兩者設成一樣，JVM 啟動時就會分配好所有記憶體，運行時不需要再調整。
:::

**重要規則**：
- Heap 不超過可用 RAM 的 50%
- Heap 不超過 32GB（超過會停用 compressed oops）
- 留足夠 RAM 給檔案系統 cache

:::info
**為什麼有這些限制？**

**為什麼不超過 RAM 的 50%？**
OpenSearch 大量使用「檔案系統 cache」來加速查詢。當你搜尋資料時，作業系統會把常用的 index 檔案快取在記憶體中。如果 heap 佔用太多 RAM，留給 cache 的空間就不夠，查詢效能會大幅下降。

**為什麼不超過 32GB？**
這跟 JVM 的「Compressed Ordinary Object Pointers」（壓縮指標）技術有關。簡單說：
- Heap < 32GB 時，JVM 用 32-bit 指標，每個物件引用只佔 4 bytes
- Heap ≥ 32GB 時，JVM 被迫改用 64-bit 指標，每個引用佔 8 bytes

結果是：設定 32GB heap 實際可用空間可能比 30GB 還少！這就是為什麼建議最大設到 30-31GB。
:::

| 可用 RAM | 建議 Heap |
|----------|-----------|
| 16 GB | 8 GB |
| 32 GB | 16 GB |
| 64 GB | 30-31 GB |

### 資源監控指標

| 指標 | 健康值 | 警告值 |
|------|--------|--------|
| CPU 使用率 | < 70% | > 85% |
| Heap 使用率 | < 75% | > 85% |
| 磁碟使用率 | < 80% | > 85% |
| GC 時間佔比 | < 5% | > 10% |

## 備份策略

### Snapshot Repository

OpenSearch 支援多種 snapshot 儲存位置：

| 類型 | 適用場景 |
|------|----------|
| `fs` | 共享檔案系統（NFS） |
| `s3` | AWS S3 或相容儲存 |
| `azure` | Azure Blob Storage |
| `gcs` | Google Cloud Storage |

### 配置 NFS Snapshot Repository

1. 掛載 NFS 到所有節點：
```bash
mount -t nfs nfs-server:/snapshots /var/lib/opensearch/snapshots
```

2. 設定 OpenSearch：
```yaml
# opensearch.yml
path.repo:
  - /var/lib/opensearch/snapshots
```

3. 建立 repository：
```
PUT _snapshot/backup
{
  "type": "fs",
  "settings": {
    "location": "/var/lib/opensearch/snapshots"
  }
}
```

### 建立 Snapshot

```
# 備份所有 index
PUT _snapshot/backup/snapshot-2024-06-01

# 備份特定 index
PUT _snapshot/backup/snapshot-logs-2024-06-01
{
  "indices": "logs-*",
  "ignore_unavailable": true,
  "include_global_state": false
}
```

### 自動化備份

使用 OpenSearch 的 Snapshot Management 功能：

```
PUT _plugins/_sm/policies/daily-backup
{
  "description": "Daily backup policy",
  "creation": {
    "schedule": {
      "cron": {
        "expression": "0 0 * * *",
        "timezone": "Asia/Taipei"
      }
    }
  },
  "deletion": {
    "schedule": {
      "cron": {
        "expression": "0 1 * * *",
        "timezone": "Asia/Taipei"
      }
    },
    "condition": {
      "max_age": "30d",
      "max_count": 30
    }
  },
  "snapshot_config": {
    "indices": "*",
    "ignore_unavailable": true,
    "include_global_state": false
  },
  "notification": {
    "channel": {
      "id": "slack-channel-id"
    }
  }
}
```

### 還原 Snapshot

```
# 查看可用 snapshots
GET _snapshot/backup/_all

# 還原特定 snapshot
POST _snapshot/backup/snapshot-2024-06-01/_restore
{
  "indices": "logs-2024.05.*",
  "rename_pattern": "(.+)",
  "rename_replacement": "restored-$1"
}
```

## Vector 生產配置

### 高可用部署

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│   Server 1  │     │   Server 2  │     │   Server 3  │
│   Vector    │     │   Vector    │     │   Vector    │
│   (Agent)   │     │   (Agent)   │     │   (Agent)   │
└──────┬──────┘     └──────┬──────┘     └──────┬──────┘
       │                   │                   │
       └───────────────────┼───────────────────┘
                           │
                           ▼
              ┌────────────────────────┐
              │     Load Balancer      │
              └────────────┬───────────┘
                           │
       ┌───────────────────┼───────────────────┐
       │                   │                   │
       ▼                   ▼                   ▼
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│   Vector    │     │   Vector    │     │   Vector    │
│ (Aggregator)│     │ (Aggregator)│     │ (Aggregator)│
└─────────────┘     └─────────────┘     └─────────────┘
       │                   │                   │
       └───────────────────┼───────────────────┘
                           │
                           ▼
                    ┌─────────────┐
                    │  OpenSearch │
                    │  Cluster    │
                    └─────────────┘
```

### Vector Agent 配置

```yaml
# agent 配置：收集本機 log，送到 aggregator
sources:
  journald:
    type: journald

  files:
    type: file
    include:
      - /var/log/**/*.log

sinks:
  aggregator:
    type: vector
    inputs:
      - journald
      - files
    address: "aggregator.internal:9000"
    buffer:
      type: disk
      max_size: 1073741824  # 1GB
```

### Vector Aggregator 配置

```yaml
# aggregator 配置：接收 agent 資料，處理後送到 OpenSearch
sources:
  vector:
    type: vector
    address: "0.0.0.0:9000"

transforms:
  parse_and_enrich:
    type: remap
    inputs:
      - vector
    source: |
      # 共同的解析和豐富邏輯
      .processed_at = now()

sinks:
  opensearch:
    type: elasticsearch
    inputs:
      - parse_and_enrich
    endpoints:
      - "https://opensearch-1:9200"
      - "https://opensearch-2:9200"
      - "https://opensearch-3:9200"
    bulk:
      index: "logs-%Y-%m-%d"
    buffer:
      type: disk
      max_size: 5368709120  # 5GB
```

### Disk Buffer 重要性

生產環境**必須**使用 disk buffer：

```yaml
buffer:
  type: disk
  max_size: 5368709120  # 5GB
  when_full: block
```

:::info
**為什麼 disk buffer 這麼重要？**

想像這個情境：OpenSearch 需要維護升級，暫時停機 30 分鐘。這段時間內：

**沒有 buffer**：所有 log 直接丟失。你永遠不會知道這 30 分鐘內系統發生了什麼事。

**Memory buffer**：log 暫存在記憶體中。但如果 Vector 也重啟（例如更新設定），記憶體內容就消失了。而且如果停機太久，記憶體會滿，後續的 log 還是會丟。

**Disk buffer**：log 寫入硬碟。即使 Vector 重啟、OpenSearch 停機很久，資料都還在。OpenSearch 恢復後，Vector 會自動把積壓的 log 補送出去。

`when_full: block` 的意思是：當 buffer 滿了，Vector 會暫停接收新資料（讓 source 端 backpressure），而不是丟棄資料。這確保在極端情況下也不會遺失 log。
:::

原因：
- OpenSearch 暫時不可用時，log 不會丟失
- 系統重啟後可以繼續發送
- 防止 memory 暴漲

## 監控與告警

### OpenSearch 自身監控

OpenSearch 提供豐富的 metrics：

```
GET _cluster/health
GET _nodes/stats
GET _cat/indices?v
GET _cat/shards?v
```

### 整合 Prometheus

使用 [OpenSearch Exporter](https://github.com/prometheus-community/elasticsearch_exporter) 整合 Prometheus：

```yaml
# prometheus.yml
scrape_configs:
  - job_name: 'opensearch'
    static_configs:
      - targets: ['opensearch-exporter:9114']
```

### 關鍵告警

| 告警 | 條件 | 嚴重程度 |
|------|------|----------|
| Cluster health RED | `cluster_health != green` 持續 5 分鐘 | Critical |
| High heap usage | `heap_used_percent > 85%` | Warning |
| Disk watermark | `disk_used_percent > 85%` | Warning |
| Unassigned shards | `unassigned_shards > 0` 持續 10 分鐘 | Warning |
| 寫入延遲 | `bulk_latency > 500ms` | Warning |

## 小結

1. **高可用**：至少 3 個節點，分離 master 和 data 角色
2. **TLS**：生產環境必須啟用，定期更新憑證
3. **容量規劃**：估算儲存需求，合理配置 shard 和 heap
4. **備份**：設定自動化 snapshot 策略
5. **監控**：整合 Prometheus，設定關鍵告警

## 參考資料

- [OpenSearch Production Recommendations](https://opensearch.org/docs/latest/tuning-your-cluster/)
- [OpenSearch Security Configuration](https://opensearch.org/docs/latest/security/configuration/index/)
- [Vector Production Deployment](https://vector.dev/docs/setup/going-to-prod/)
- [opensearch-ansible](https://github.com/efficacy38/opensearch-ansible) — 本系列作者維護的 Ansible 部署專案（參考用）
