---
title: Vector + OpenSearch 整合實戰
description: 建立完整的 Log Pipeline，包含 Index Template 和 Index Lifecycle Management
date: 2025-12-07
slug: observability-006-vector-opensearch
series: "observability"
tags:
  - "observability"
  - "vector"
  - "opensearch"
---

:::note
**前置閱讀**

本文假設你已經讀過系列的前幾篇文章：
- [OpenSearch 入門](/posts/observability-002-opensearch-get-start)——完成 OpenSearch 環境架設
- [OpenSearch：Analyzer 與 Mapping](/posts/observability-004-schema)——理解 Mapping 和 Index Template
- [Vector 實戰](/posts/observability-005-vector-hands-on)——理解 Vector 配置和 VRL

本文會將 Vector 和 OpenSearch 整合，建立完整的 log pipeline。
:::

## 整體架構

我們要建立的 pipeline 架構如下：

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│  Nginx Logs     │     │                 │     │                 │
│  /var/log/nginx │────▶│     Vector      │────▶│   OpenSearch    │
│                 │     │                 │     │                 │
├─────────────────┤     │  - parse        │     │  - logs-nginx   │
│  Syslog         │────▶│  - enrich       │────▶│  - logs-system  │
│  UDP:514        │     │  - route        │     │                 │
└─────────────────┘     └─────────────────┘     └─────────────────┘
```

## Vector Elasticsearch Sink

Vector 使用 `elasticsearch` sink 來發送資料到 OpenSearch。

:::info
**為什麼用 `elasticsearch` sink 連接 OpenSearch？**

**OpenSearch** 是 **Elasticsearch** 的開源分支。2021 年，Elastic 公司將 Elasticsearch 的授權從 Apache 2.0 改為更限制性的授權，AWS 因此 fork 了最後一個開源版本，創建了 OpenSearch。

因為兩者有共同的起源，OpenSearch 完全相容 Elasticsearch 7.x 的 API。所以 Vector、Logstash、各種 client library 都可以用 Elasticsearch 的設定連接 OpenSearch——不需要特別的「OpenSearch sink」。
:::

### 基本配置

```yaml
sinks:
  opensearch:
    type: elasticsearch
    inputs:
      - parse_nginx
    endpoints:
      - "https://localhost:9200"
    auth:
      strategy: basic
      user: admin
      password: "your_password"
    tls:
      verify_certificate: false  # 開發環境用，生產環境應設為 true
    bulk:
      index: "logs-%Y-%m-%d"
```

### 配置說明

| 參數 | 說明 |
|------|------|
| `endpoints` | OpenSearch 節點位址（可以是多個） |
| `auth.strategy` | 認證方式：`basic`、`aws` |
| `tls.verify_certificate` | 是否驗證 TLS 憑證 |
| `bulk.index` | 目標 index 名稱，支援時間格式 |

### 動態 Index 名稱

可以根據 log 內容決定 index 名稱：

```yaml
sinks:
  opensearch:
    type: elasticsearch
    inputs:
      - route_logs
    endpoints:
      - "https://localhost:9200"
    bulk:
      index: "{{ log_type }}-%Y-%m-%d"
```

這需要在 transform 中設定 `log_type` 欄位。

## Index Template

在大量寫入 log 之前，建議先在 OpenSearch 建立 **Index Template**，確保所有 index 使用一致的 mapping。

### 建立 Index Template

在 OpenSearch Dev Tools 執行：

```
PUT _index_template/logs-template
{
  "index_patterns": ["logs-*"],
  "priority": 100,
  "template": {
    "settings": {
      "number_of_shards": 1,
      "number_of_replicas": 1,
      "refresh_interval": "5s"
    },
    "mappings": {
      "dynamic_templates": [
        {
          "strings_as_keyword": {
            "match_mapping_type": "string",
            "mapping": {
              "type": "keyword",
              "ignore_above": 1024
            }
          }
        }
      ],
      "properties": {
        "@timestamp": {
          "type": "date"
        },
        "timestamp": {
          "type": "date"
        },
        "message": {
          "type": "text"
        },
        "host": {
          "type": "keyword"
        },
        "log_type": {
          "type": "keyword"
        },
        "level": {
          "type": "keyword"
        },
        "client_ip": {
          "type": "ip"
        },
        "status": {
          "type": "integer"
        },
        "bytes": {
          "type": "long"
        },
        "response_time_ms": {
          "type": "float"
        },
        "path": {
          "type": "keyword",
          "fields": {
            "text": {
              "type": "text"
            }
          }
        },
        "user_agent": {
          "type": "text",
          "fields": {
            "keyword": {
              "type": "keyword",
              "ignore_above": 256
            }
          }
        }
      }
    }
  }
}
```

### 驗證 Template

```
GET _index_template/logs-template
```

## Index Lifecycle Management (ILM)

在介紹 ILM 之前，先理解幾個核心概念：

:::info
**核心概念：Shard、Replica、Rollover**

**Shard（分片）**
OpenSearch 會將一個 index 的資料分割成多個 **shard**。這樣可以：
- 將資料分散到多台機器上儲存
- 平行處理查詢，提升效能

每個 index 建立時會指定 primary shard 數量（之後不能改變）。

**Replica（副本）**
每個 primary shard 可以有一個或多個 **replica**。Replica 是 primary shard 的完整複製品，用於：
- **高可用**：primary 掛掉時，replica 可以接手
- **分擔查詢**：讀取請求可以由 replica 處理

**Rollover（滾動）**
當一個 index 太大（例如超過 50GB）或太老（例如超過一天），繼續往裡面寫入會影響效能。**Rollover** 會自動建立一個新的 index，讓寫入導向新的 index，舊的 index 變成唯讀。
:::

**ILM**（Index Lifecycle Management）讓你自動管理 index 的生命週期，包括：
- 自動 rollover（當 index 太大時建立新的）
- 自動刪除過期資料
- 自動調整 replica 數量

### ILM Policy 概念

ILM 將 index 生命週期分為幾個階段：

| 階段 | 說明 | 典型操作 |
|------|------|----------|
| **Hot** | 正在寫入的 index | 高效能設定 |
| **Warm** | 不再寫入但常查詢 | 降低 replica、force merge |
| **Cold** | 很少查詢 | 移到便宜的儲存 |
| **Delete** | 刪除 | 自動刪除 |

### 建立 ILM Policy

```
PUT _plugins/_ism/policies/logs-policy
{
  "policy": {
    "description": "Log retention policy - 30 days hot, then delete",
    "default_state": "hot",
    "states": [
      {
        "name": "hot",
        "actions": [
          {
            "rollover": {
              "min_size": "10gb",
              "min_index_age": "1d"
            }
          }
        ],
        "transitions": [
          {
            "state_name": "delete",
            "conditions": {
              "min_index_age": "30d"
            }
          }
        ]
      },
      {
        "name": "delete",
        "actions": [
          {
            "delete": {}
          }
        ],
        "transitions": []
      }
    ],
    "ism_template": {
      "index_patterns": ["logs-*"],
      "priority": 100
    }
  }
}
```

### ILM Policy 說明

上述 policy 的行為：
1. **Hot 階段**：index 大小超過 10GB 或存在超過 1 天時，觸發 rollover
2. **30 天後**：自動刪除 index

### 使用 Rollover Index

要使用 rollover，需要用 index alias 而非直接寫入 index：

```
# 建立初始 index
PUT logs-nginx-000001
{
  "aliases": {
    "logs-nginx": {
      "is_write_index": true
    }
  }
}
```

Vector 配置改為寫入 alias：

```yaml
sinks:
  opensearch:
    type: elasticsearch
    inputs:
      - parse_nginx
    endpoints:
      - "https://localhost:9200"
    bulk:
      index: "logs-nginx"  # 使用 alias
```

當 rollover 觸發時，OpenSearch 會自動建立 `logs-nginx-000002` 並切換 write index。

## 完整整合範例

### Vector 配置

```yaml
# /etc/vector/vector.yaml

sources:
  nginx_access:
    type: file
    include:
      - /var/log/nginx/access.log

  syslog:
    type: syslog
    address: "0.0.0.0:514"
    mode: udp

transforms:
  parse_nginx:
    type: remap
    inputs:
      - nginx_access
    source: |
      # 解析 nginx combined log
      parsed = parse_regex!(.message, r'^(?P<client_ip>\S+) \S+ \S+ \[(?P<timestamp>[^\]]+)\] "(?P<method>\S+) (?P<path>\S+) (?P<protocol>\S+)" (?P<status>\d+) (?P<bytes>\d+) "(?P<referrer>[^"]*)" "(?P<user_agent>[^"]*)"')

      . = parsed
      .status = to_int!(.status)
      .bytes = to_int!(.bytes)

      # 解析時間並設為 @timestamp（OpenSearch 標準欄位）
      ."@timestamp" = parse_timestamp!(.timestamp, "%d/%b/%Y:%H:%M:%S %z")
      del(.timestamp)

      # 加入 metadata
      .log_type = "nginx"
      .host = get_hostname!()

      # 根據 status code 設定 level
      if .status >= 500 {
        .level = "error"
      } else if .status >= 400 {
        .level = "warn"
      } else {
        .level = "info"
      }

  enrich_syslog:
    type: remap
    inputs:
      - syslog
    source: |
      ."@timestamp" = .timestamp
      .log_type = "syslog"
      .host = get_hostname!()

  filter_health_check:
    type: filter
    inputs:
      - parse_nginx
    condition: |
      !starts_with(string!(.path), "/health")

  route_by_type:
    type: route
    inputs:
      - filter_health_check
      - enrich_syslog
    route:
      nginx: '.log_type == "nginx"'
      syslog: '.log_type == "syslog"'

sinks:
  opensearch_nginx:
    type: elasticsearch
    inputs:
      - route_by_type.nginx
    endpoints:
      - "https://localhost:9200"
    auth:
      strategy: basic
      user: admin
      password: "${OPENSEARCH_PASSWORD}"
    tls:
      verify_certificate: false
    bulk:
      index: "logs-nginx"
    healthcheck:
      enabled: true

  opensearch_syslog:
    type: elasticsearch
    inputs:
      - route_by_type.syslog
    endpoints:
      - "https://localhost:9200"
    auth:
      strategy: basic
      user: admin
      password: "${OPENSEARCH_PASSWORD}"
    tls:
      verify_certificate: false
    bulk:
      index: "logs-syslog"
```

### 環境變數

建立 `/etc/vector/vector.env`：

```bash
OPENSEARCH_PASSWORD=your_secure_password
```

### Systemd Service

如果使用 systemd 管理 Vector：

```ini
# /etc/systemd/system/vector.service
[Unit]
Description=Vector
After=network.target

[Service]
Type=simple
User=vector
Group=vector
EnvironmentFile=/etc/vector/vector.env
ExecStart=/usr/bin/vector --config /etc/vector/vector.yaml
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
```

```bash
sudo systemctl daemon-reload
sudo systemctl enable vector
sudo systemctl start vector
```

## 驗證資料寫入

### 確認 Index 建立

在 OpenSearch Dev Tools：

```
GET _cat/indices/logs-*?v
```

### 查詢資料

```
GET logs-nginx/_search
{
  "query": {
    "match_all": {}
  },
  "size": 10,
  "sort": [
    { "@timestamp": "desc" }
  ]
}
```

### 檢查 Mapping

```
GET logs-nginx/_mapping
```

## 效能調校

### Vector 端

```yaml
sinks:
  opensearch:
    type: elasticsearch
    # ...
    batch:
      max_bytes: 10485760      # 10MB
      max_events: 10000
      timeout_secs: 1
    buffer:
      type: disk
      max_size: 268435488      # 256MB
      when_full: block
    request:
      concurrency: 10
      rate_limit_num: 100
      retry_attempts: 5
```

| 參數 | 說明 | 建議值 |
|------|------|--------|
| `batch.max_bytes` | 單次 bulk request 大小上限 | 5-15MB |
| `batch.max_events` | 單次 bulk 事件數上限 | 5000-20000 |
| `batch.timeout_secs` | 強制 flush 的時間間隔 | 1-5 秒 |
| `buffer.type` | 緩衝類型（memory/disk） | disk（確保不丟資料） |
| `request.concurrency` | 並行請求數 | 根據 OpenSearch 節點數調整 |

### OpenSearch 端

```
PUT logs-nginx/_settings
{
  "index": {
    "refresh_interval": "30s",
    "translog.durability": "async",
    "translog.sync_interval": "30s"
  }
}
```

| 設定 | 說明 | 效果 |
|------|------|------|
| `refresh_interval` | 資料可被搜尋的延遲 | 增加可提升寫入效能 |
| `translog.durability` | translog 同步模式 | `async` 提升效能但可能丟失少量資料 |

## 常見問題排解

### 1. Vector 無法連線到 OpenSearch

```
ERROR vector::sinks::elasticsearch: Error: Request failed: error sending request
```

檢查項目：
- OpenSearch 是否運行中
- 網路連線是否通暢
- TLS 憑證是否正確
- 認證資訊是否正確

### 2. Bulk Request 被拒絕

```
ERROR elasticsearch: Bulk request rejected
```

原因通常是 OpenSearch 寫入佇列滿了。解決方案：
- 減少 Vector 的 `request.concurrency`
- 增加 OpenSearch 的 thread pool 大小
- 增加 OpenSearch 節點

### 3. Mapping 衝突

```
ERROR elasticsearch: mapper_parsing_exception: failed to parse field
```

原因是資料型別與 mapping 不符。解決方案：
- 在 VRL 中確保型別轉換正確
- 更新 Index Template 的 mapping

## 小結

1. Vector 使用 `elasticsearch` sink 發送資料到 OpenSearch
2. 建立 **Index Template** 確保一致的 mapping
3. 使用 **ILM** 自動管理 index 生命週期
4. 使用 **Rollover** 和 **Alias** 管理大量 log
5. 調整 **batch** 和 **buffer** 設定優化效能

下一篇，我們會介紹生產環境的架構設計，包括高可用性和安全性考量。

## 參考資料

- [Vector Elasticsearch Sink](https://vector.dev/docs/reference/configuration/sinks/elasticsearch/)
- [OpenSearch Index Templates](https://opensearch.org/docs/latest/im-plugin/index-templates/)
- [OpenSearch ISM](https://opensearch.org/docs/latest/im-plugin/ism/index/)
