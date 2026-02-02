---
title: Log Pipeline 架構與工具選型
description: 理解 Log Pipeline 的核心元件，以及 Vector、Fluentd、Logstash 的選型比較
date: 2025-12-02
slug: observability-001-log-pipeline
series: "observability"
tags:
  - "observability"
  - "logging"
  - "vector"
---

:::note
**前置閱讀**

本文假設你已經讀過系列的第一篇文章：
- [為什麼需要 Observability？](/posts/observability-000-intro)——理解 Observability 的核心概念

如果你不熟悉 Observability 三支柱（Logs、Metrics、Traces），建議先閱讀上述文章。
:::

## Log Pipeline 是什麼？

在上一篇文章中，我們提到了集中式 Log 管理的架構。這個從「收集 → 處理 → 儲存 → 查詢」的完整流程，就稱為 **Log Pipeline**。

```
┌──────────────────────────────────────────────────────────────────┐
│                        Log Pipeline                               │
│                                                                    │
│   ┌─────────┐     ┌─────────────┐     ┌─────────┐     ┌─────────┐ │
│   │ Sources │ ──▶ │ Processing  │ ──▶ │ Storage │ ──▶ │  Query  │ │
│   │         │     │             │     │         │     │         │ │
│   └─────────┘     └─────────────┘     └─────────┘     └─────────┘ │
│                                                                    │
│   syslog          parse, filter,      OpenSearch      Dashboards  │
│   nginx           enrich, route       Elasticsearch   Kibana      │
│   app logs                            Loki            Grafana     │
└──────────────────────────────────────────────────────────────────┘
```

每個階段都有對應的工具和技術選擇。這篇文章會幫助你理解各個元件的角色，並提供工具選型的參考。

## Log Pipeline 的四個階段

### 1. Collection（收集）

**收集**是指從各個來源取得 log 資料。常見的 log 來源包括：

| 來源類型 | 範例 |
|----------|------|
| 系統 log | syslog、journald、Windows Event Log |
| 應用程式 log | stdout/stderr、log 檔案 |
| Web server | nginx access/error log、Apache log |
| Container | Docker logs、Kubernetes pod logs |
| Cloud | AWS CloudWatch、GCP Logging |

收集的方式通常有兩種：

- **Push**：應用程式主動將 log 送到收集器（例如透過 syslog 協議）
- **Pull**：收集器主動讀取 log 檔案或 API

### 2. Processing（處理）

**處理**是指對原始 log 進行解析和轉換。這個階段通常包括：

| 操作 | 說明 | 範例 |
|------|------|------|
| **Parsing**（解析） | 將非結構化文字轉為結構化資料 | 從 nginx log 解析出 IP、URL、status code |
| **Filtering**（過濾） | 移除不需要的 log | 過濾掉 health check 請求 |
| **Enrichment**（豐富） | 加入額外資訊 | 加入 hostname、環境標籤、GeoIP |
| **Routing**（路由） | 將 log 送往不同目的地 | error log 送告警系統，access log 送分析系統 |

#### 處理範例：Nginx Access Log

原始 log：
```
192.168.1.1 - - [01/Jun/2024:12:00:00 +0000] "GET /api/users HTTP/1.1" 200 1234 "-" "curl/7.68.0"
```

處理後的結構化資料：
```json
{
  "timestamp": "2024-06-01T12:00:00Z",
  "client_ip": "192.168.1.1",
  "method": "GET",
  "path": "/api/users",
  "status": 200,
  "bytes": 1234,
  "user_agent": "curl/7.68.0",
  "host": "web-server-01",
  "env": "production"
}
```

### 3. Storage（儲存）

**儲存**是指將處理後的 log 持久化，並建立索引以支援查詢。常見的 log 儲存系統：

| 系統 | 特色 | 適用場景 |
|------|------|----------|
| **OpenSearch** | 全文搜尋、豐富的查詢語法、Dashboard | 通用 log 分析 |
| **Elasticsearch** | OpenSearch 的前身，功能類似 | Elastic Stack 生態系 |
| **Loki** | 輕量、只索引 label 不索引內容 | Kubernetes、Grafana 生態系 |
| **ClickHouse** | 列式儲存、極高壓縮率 | 大量 log、長期保留 |

這個系列會使用 **OpenSearch** 作為儲存系統，原因包括：
- 強大的全文搜尋能力
- 完整的 Dashboard 支援
- 開源且社群活躍
- 與 Elasticsearch 相容

### 4. Query & Visualization（查詢與視覺化）

最後一個階段是讓使用者能夠查詢和分析 log。這包括：

- **即時查詢**：搜尋特定時間範圍、關鍵字、欄位值
- **Dashboard**：建立視覺化圖表監控趨勢
- **Alerting**：設定條件觸發告警

## Log Shipper 工具比較

**Log Shipper**（日誌收集器）負責收集和處理 log。目前主流的三個工具是：

- **Vector** — Datadog 開發，Rust 實作
- **Fluentd** — **CNCF** 畢業專案，Ruby 實作
- **Logstash** — Elastic 開發，JVM 實作

:::info
**什麼是 CNCF？**

**CNCF**（Cloud Native Computing Foundation）是 Linux 基金會旗下的組織，專門推廣和維護雲原生技術。知名專案如 Kubernetes、Prometheus、Envoy 都是 CNCF 的專案。

CNCF 專案分三個成熟度等級：Sandbox → Incubating → **Graduated**（畢業）。「畢業」代表該專案經過嚴格審查，被認為是生產就緒、社群活躍、治理健全的成熟專案。Fluentd 在 2019 年成為 CNCF 畢業專案。
:::

### 架構與效能比較

| 面向 | Vector | Fluentd | Logstash |
|------|--------|---------|----------|
| **實作語言** | Rust | Ruby + C extensions | JRuby/JVM |
| **效能** | 極佳（~25 MiB/s/vCPU） | 中等（~18,000 events/sec） | 較低（JVM overhead） |
| **記憶體使用** | ~2 GiB/vCPU（高負載） | ~40 MB（一般負載） | ~120 MB（一般負載） |
| **資料類型** | Logs、Metrics、Traces | 主要 Logs | 主要 Logs |

:::info
**關於 Vector 的記憶體使用**

你可能注意到 Vector 的記憶體使用（~2 GiB/vCPU）看起來比 Fluentd（~40 MB）高很多。這是因為測量條件不同：

- **Vector 的數據**來自官方的高吞吐量壓力測試（每 vCPU 處理 25 MiB/s）
- **Fluentd 的數據**是一般使用情境的典型值

在相同負載下，Vector 實際上更省資源。Vector 用 Rust 編寫，沒有垃圾回收開銷；而 Logstash 跑在 JVM 上，光啟動就需要數百 MB 記憶體。
:::

### 資料處理與生態系

| 面向 | Vector | Fluentd | Logstash |
|------|--------|---------|----------|
| **轉換語言** | VRL（編譯式） | Ruby plugins | Grok patterns |
| **Plugin 生態** | 內建完整功能 | 500+ plugins | 199 plugins |
| **設定格式** | YAML | Directive-based | Pipeline syntax |
| **學習曲線** | 中等（VRL 需學習） | 較低 | 中等 |

### 授權與社群

| 面向 | Vector | Fluentd | Logstash |
|------|--------|---------|----------|
| **授權** | MPL-2.0 | Apache 2.0 | SSPL/Elastic License v2 |
| **維護者** | Datadog | CNCF | Elastic |
| **GitHub Stars** | 13k+ | 12k+ | 14k+ |

### 工具選型建議

| 場景 | 建議工具 | 原因 |
|------|----------|------|
| 高吞吐量、效能優先 | **Vector** | Rust 效能優勢明顯 |
| Kubernetes 環境 | **Fluentd** | CNCF 生態整合佳 |
| 已有 Elastic Stack | **Logstash** | 整合最緊密 |
| 需要處理 Metrics/Traces | **Vector** | 唯一支援三種資料類型 |
| 團隊熟悉 Ruby | **Fluentd** | Plugin 開發容易 |

這個系列選擇 **Vector** 的原因：
1. 效能最佳，資源消耗最低
2. VRL 語言強大且安全（編譯時檢查錯誤）
3. 同時支援 Logs、Metrics、Traces
4. 開源且授權友善（MPL-2.0）

## Vector 架構介紹

既然選擇了 Vector，讓我們深入了解它的架構。

### 核心元件

Vector 的配置由三個核心元件組成：

```yaml
# vector.yaml
sources:
  my_source:
    type: file
    include:
      - /var/log/*.log

transforms:
  my_transform:
    type: remap
    inputs:
      - my_source
    source: |
      .processed_at = now()

sinks:
  my_sink:
    type: elasticsearch
    inputs:
      - my_transform
    endpoints:
      - "https://opensearch:9200"
```

#### Sources（來源）

**Source** 負責接收或讀取資料。常用的 source 類型：

| Type | 說明 |
|------|------|
| `file` | 讀取 log 檔案（支援 glob pattern） |
| `journald` | 讀取 systemd journal |
| `syslog` | 接收 syslog 協議 |
| `docker_logs` | 讀取 Docker container logs |
| `http` | 接收 HTTP POST 請求 |

#### Transforms（轉換）

**Transform** 負責處理和轉換資料。最常用的是 `remap` transform，它使用 **VRL**（Vector Remap Language）進行資料操作：

```yaml
transforms:
  parse_nginx:
    type: remap
    inputs:
      - nginx_source
    source: |
      # 解析 nginx combined log format
      . = parse_regex!(.message, r'^(?P<client>\S+) \S+ \S+ \[(?P<timestamp>[^\]]+)\] "(?P<method>\S+) (?P<path>\S+) \S+" (?P<status>\d+) (?P<bytes>\d+)')

      # 轉換資料類型
      .status = to_int!(.status)
      .bytes = to_int!(.bytes)

      # 加入 metadata
      .env = "production"
```

#### Sinks（輸出）

**Sink** 負責將處理後的資料送往目的地。常用的 sink 類型：

| Type | 說明 |
|------|------|
| `elasticsearch` | 送往 OpenSearch/Elasticsearch |
| `loki` | 送往 Grafana Loki |
| `file` | 寫入檔案 |
| `console` | 輸出到 stdout（除錯用） |
| `http` | 送往 HTTP endpoint |

### 部署模式

Vector 支援兩種部署模式：

```
Agent 模式：每台機器部署一個 Vector，直接收集本機 log
┌─────────────────┐   ┌─────────────────┐
│  Server A       │   │  Server B       │
│  ┌───────────┐  │   │  ┌───────────┐  │
│  │  Vector   │──┼───┼──│  Vector   │──┼──▶ OpenSearch
│  └───────────┘  │   │  └───────────┘  │
│  app logs       │   │  app logs       │
└─────────────────┘   └─────────────────┘

Aggregator 模式：各機器送 log 到集中的 Vector 處理
┌─────────────────┐   ┌─────────────────┐
│  Server A       │   │  Server B       │
│  (syslog/http)──┼───┼──(syslog/http)──┼──┐
└─────────────────┘   └─────────────────┘  │
                                           ▼
                                   ┌───────────────┐
                                   │   Vector      │
                                   │  (Aggregator) │──▶ OpenSearch
                                   └───────────────┘
```

生產環境通常會結合兩種模式：
- 每台機器用 Agent 收集 log
- 送到 Aggregator 集中處理和路由

## 小結

- **Log Pipeline** 包含四個階段：收集、處理、儲存、查詢
- 主流的 Log Shipper 工具有 **Vector**、**Fluentd**、**Logstash**
- **Vector** 效能最佳、支援多種資料類型，是這個系列的選擇
- Vector 由 **Sources**、**Transforms**、**Sinks** 三個元件組成
- Vector 可以用 **Agent** 或 **Aggregator** 模式部署

下一篇，我們會用 Docker 快速架設 OpenSearch，實際體驗 log 儲存和查詢。

## 參考資料

- [Vector 官方文件](https://vector.dev/docs/)
- [Vector 架構說明](https://vector.dev/docs/about/under-the-hood/architecture/)
- [Fluentd 官方文件](https://docs.fluentd.org/)
- [Logstash 官方文件](https://www.elastic.co/guide/en/logstash/current/index.html)
- [Vector Sizing Planning](https://vector.dev/docs/setup/going-to-prod/sizing/)
