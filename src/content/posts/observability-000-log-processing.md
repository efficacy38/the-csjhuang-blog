---
title: Log 處理工具比較
description: 比較 Vector、Fluentd 與 Logstash 三大日誌處理工具的架構與效能
pubDate: 2025-09-30
slug: observability-000-log-processing
tags:
  - "log"
  - "observability"
---

## Intro

在現代的軟體系統中，日誌處理是可觀測性 (Observability) 的重要一環。有效的日誌收集、轉換和轉發，
能幫助我們更好地理解系統行為、進行故障排查和性能分析。
目前有許多優秀的日誌處理工具，這篇文章將針對其中三個有名的工具進行比較：

- `Vector`
- `Fluentd`
- `Logstash`

## 架構與效能

比較這三款工具的底層架構、處理效能、記憶體使用情況以及整體資源效率，有助於了解這些差異有助於根據專案需求選擇最適合的工具，
尤其是在處理大量日誌數據時，效能和資源消耗可能是關鍵考量因素

- [vector sizing planning](https://vector.dev/docs/setup/going-to-prod/sizing/)
- [fluentd sizing planning](https://docs.fluentd.org/deployment/performance-tuning-single-process)
- [fluentd and logstash performance testing](https://edgedelta.com/company/blog/fluentd-vs-logstash)

| Aspect                  | Datadog Vector                                         | Fluentd                                         | Logstash                                                     |
| :---------------------- | :----------------------------------------------------- | :---------------------------------------------- | :----------------------------------------------------------- |
| **Architecture**        | Rust-based, unified data model for logs/metrics/traces | Ruby-based with C extensions, tag-based routing | JRuby/JVM-based, pipeline architecture (input-filter-output) |
| **Performance**         | 60x faster ingestion, 25 MiB/s/vCPU structured events  | ~18,000 events/sec, moderate performance        | Lower performance due to JVM overhead                        |
| **Memory Usage**        | ~2 GiB per vCPU, highly efficient                      | ~40MB typical load                              | ~120MB typical load                                          |
| **Resource Efficiency** | Excellent (Rust performance)                           | Good (Ruby with C extensions)                   | Moderate (JVM overhead)                                      |

## 資料處理與生態系統

本節將探討這三款工具在資料處理能力、插件生態系統、配置方式以及支援的資料類型方面的差異

了解它們如何處理、轉換和路由日誌數據，以及其擴展性，對於選擇能夠滿足特定日誌處理需求的工具至關重要

| Aspect               | Datadog Vector                                        | Fluentd                                               | Logstash                                        |
| :------------------- | :---------------------------------------------------- | :---------------------------------------------------- | :---------------------------------------------- |
| **Data Processing**  | Vector Remap Language (VRL), compiled transformations | Ruby plugins, flexible filtering                      | Grok patterns (120+ built-in), powerful parsing |
| **Plugin Ecosystem** | Built-in comprehensive functionality                  | 500+ plugins (decentralized)                          | 199 plugins (centralized repository)            |
| **Configuration**    | YAML-based, sources/transforms/sinks                  | Directive-based with`<source>`, `<filter>`, `<match>` | Pipeline syntax with input/filter/output        |
| **Data Types**       | Logs, metrics, traces                                 | Primarily logs                                        | Primarily logs                                  |

### Configuration 語法

- vector:
  - pros:
    - fast, small footprint
  - cons:
    - lost some sink or source's support, needs to do some parsing by yourself(maybe is pros?)
- fluentd
  - pros:
    - easy to setup, tag-based routing is simple
    - otherone may write some parsing rule for you(keep your hand clean)
  - cons:
    - tag-based is hard to keep in complex situation
- logstash
  - pros:
    - otherone may write some parsing rule for you(keep your hand clean)
    - integrated with opensearch or elasticsearch
  - cons:
    - FIXME: not using this tool, add it after some try

## 社群與授權

本節將比較這三款工具的授權模式。

| Aspect               | Datadog Vector                    | Fluentd                             | Logstash                                 |
| :------------------- | :-------------------------------- | :---------------------------------- | :--------------------------------------- |
| **License**          | MPL-2.0 (Datadog maintained)      | Apache 2.0 (CNCF graduated)         | SSPL/Elastic License v2 (dual licensing) |
| **Community Status** | 13k+ GitHub stars, vendor-neutral | CNCF graduated, 7,400+ contributors | Part of Elastic ecosystem                |

## 使用案例與部署模式

本節將探討這三款工具最適合的使用場景和部署方式。了解它們在不同環境下的優勢，
例如高吞吐量、雲原生、Kubernetes 環境或與 Elastic Stack 的整合，
將有助於選擇最符合特定業務需求和基礎設施的日誌處理解決方案。

| Aspect               | Datadog Vector                                        | Fluentd                                      | Logstash                                       |
| :------------------- | :---------------------------------------------------- | :------------------------------------------- | :--------------------------------------------- |
| **Best Use Cases**   | High-performance, cloud-native, unified observability | Complex distributed environments, Kubernetes | Elastic Stack integration, complex log parsing |
| **Deployment Modes** | Agent or aggregator                                   | Flexible across environments                 | Primarily pipeline processor                   |
