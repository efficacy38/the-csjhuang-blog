---
title: Vector 入門指南
description: Datadog Vector 可觀測性 data pipeline 工具的基礎介紹與架構解析
pubDate: 2025-09-30
slug: observability-001-vector-get-start
tags:
  - "observibility"
  - "vector"
---

Datadog Vector 是一個高效能、開源的可觀測性 data pipeline 工具，
能夠收集、轉換並傳遞 logs、metrics、traces 等數據，
讓企業可以完全掌控其觀測性資料的流向與內容。

## Vector 介紹

Vector 由 Datadog 開發與維護，目標是提供可靠、統一且高效的 data pipeline solution。

它既可部署於代理模式（agent）監控主機，也可作為聚合器（aggregator）集中處理大規模資料。
Vector 支援多種資料來源與目標，包括 Datadog、Elasticsearch、Loki、HTTP API 等，
並透過自定義的轉換語言（VRL）靈活操控資料內容。

## Vector 架構

Vector 的核心架構包括三個主要組件：

- **Sources（來源）**：負責資料的接入，如檔案、syslog、Docker logs 等
- **Transforms（轉換）**：對進來的資料進行各種處理與變形，包括資料格式化、過濾、加標籤、數值運算等。最常用的是 Remap Transform，
  它實現了 Vector Remap Language (VRL) 的高彈性腳本化轉換功能
- **Sinks（輸出）**：資料被處理後最後送出的地方，如 Datadog、Loki、Elasticsearch、Websocket 等

下列是 Vector 配置的範例結構：

```yaml
sources:
  my_source:
    type: file
    # 來源設定
transforms:
  my_transform:
    type: remap
    # VRL 腳本邏輯
sinks:
  my_sink:
    type: datadog_logs
    # 輸出目標設定
```

架構詳細說明：

- Vector 會先從 source 進行資料收集
- 經由 transforms 進行 transform、clean、format
- 最後由 sinks 將處理後的資料送往各自的目標平台或儲存介質
- 支援多線程、高效能、代理/聚合模式以及插件式架構，能靈活部署於不同場景與雲原生系統（如 Kubernetes）內

## 參考資料

- Datadog Vector 官方網站與架構文件：[官方架構說明](https://vector.dev/docs/architecture/)，[官方總覽](https://opensource.datadoghq.com/projects/vector/)
- Vector 社群文檔與運用經驗：[BetterStack 教學](https://betterstack.com/community/guides/logging/vector-explained/)
- Datadog Open Source Hub：[vector data pipeline](https://opensource.datadoghq.com/projects/vector/)
- Rapdev 專業評述：[How Vector Enhances Datadog Logs \& Metrics](https://www.rapdev.io/blog/how-vector-enhances-datadog-logs-metrics)
- GitHub repo：[vectordotdev/vector](https://github.com/vectordotdev/vector)
