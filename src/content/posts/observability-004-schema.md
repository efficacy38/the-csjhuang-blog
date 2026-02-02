---
title: OpenSearch：Analyzer 與 Mapping 設定
description: 學習 OpenSearch 的文字分析器與映射設定，包含動態模板與 Multi-fields
date: 2025-12-05
slug: observability-004-schema
series: "observability"
tags:
  - "observability"
  - "opensearch"
---

:::note
**前置閱讀**

本文假設你已經讀過系列的前幾篇文章：
- [OpenSearch：Document 與 Index 基礎](/posts/observability-003-opensearch-index)——理解 Document 與 Index 的基本概念

本文會深入探討 OpenSearch 如何處理文字資料，以及如何透過 Mapping 控制資料的儲存方式。
:::

## Analysis and Analyzers

當你把一段文字存入 OpenSearch 時，OpenSearch 不會直接儲存原始文字來做搜尋。相反地，它會透過 **Analyzer**（分析器）將文字拆解成一個個 **Token**（詞元），讓搜尋更有效率。

這個過程稱為 **Text Analysis**（文字分析）。我們會先解釋 Analyzer 如何運作，再說明它產生的結果如何被儲存（Inverted Index）。

### 為什麼需要 Analyzer？

假設你有一份 document 包含這段文字：

```
"The Quick Brown Fox jumps over the lazy dog."
```

如果使用者搜尋 `quick`（小寫），你會希望這份 document 被搜尋到嗎？答案通常是「會」。

這就是 Analyzer 的作用：
1. 將 `Quick` 轉成小寫 `quick`
2. 移除標點符號
3. 將句子拆解成獨立的詞

### Analyzer 的組成

每個 Analyzer 由三個部分組成，按順序執行：

```
原始文字 → [Character Filters] → [Tokenizer] → [Token Filters] → Tokens
```

| 元件 | 數量 | 作用 |
|------|------|------|
| **Character Filter** | 0 個或多個 | 在切詞前處理字元（新增、刪除、替換） |
| **Tokenizer** | 剛好 1 個 | 將文字切成多個 token |
| **Token Filter** | 0 個或多個 | 對 token 進行處理（轉小寫、移除停用詞等） |

### Character Filter

**Character Filter** 在 tokenizer 之前處理原始文字。常見的 character filter：

| Filter | 作用 | 範例 |
|--------|------|------|
| `html_strip` | 移除 HTML 標籤 | `<p>Hello</p>` → `Hello` |
| `mapping` | 字元替換 | `&` → `and` |
| `pattern_replace` | 正規表達式替換 | 移除特定 pattern |

### Tokenizer

**Tokenizer** 負責將文字切成多個 token。常見的 tokenizer：

| Tokenizer | 切詞規則 | 範例輸入 | 輸出 |
|-----------|----------|----------|------|
| `standard` | 根據空白和標點符號 | `happy birth-day, friend!` | `["happy", "birth", "day", "friend"]` |
| `whitespace` | 只根據空白 | `The quick brown fox.` | `["The", "quick", "brown", "fox."]` |
| `keyword` | 不切詞（整段視為一個 token） | `Hello World` | `["Hello World"]` |
| `pattern` | 根據正規表達式 | 可自訂 | 可自訂 |

### Token Filter

**Token Filter** 對 token 進行後處理。常見的 token filter：

| Filter | 作用 | 範例 |
|--------|------|------|
| `lowercase` | 轉小寫 | `["The", "Quick"]` → `["the", "quick"]` |
| `stop` | 移除停用詞 | 移除 `the`, `a`, `is` 等 |
| `stemmer` | 詞幹提取 | `running` → `run` |
| `synonym` | 同義詞擴展 | `quick` → `quick, fast` |

:::info
**為什麼要移除停用詞？為什麼要詞幹提取？**

- **停用詞**（Stop Words）：像 `the`、`a`、`is` 這些詞幾乎每個句子都有，對搜尋沒有幫助。移除它們可以減少索引大小，提升搜尋效率。
- **詞幹提取**（Stemming）：將 `running`、`runs`、`ran` 都歸納成 `run`，這樣搜尋 `run` 就能找到所有相關文件，不需要使用者猜測正確的時態。

這些技術讓搜尋更「智慧」，但也可能帶來意外結果（例如 `running` 和 `run` 被視為相同）。根據使用場景決定是否啟用。
:::

### OpenSearch 預設 Analyzer

OpenSearch 預設使用 **Standard Analyzer**，組成如下：

1. Character Filter：無
2. Tokenizer：`standard`
3. Token Filter：`lowercase`

### 使用 Analyze API 測試

你可以使用 `_analyze` API 測試不同 analyzer 的效果：

```
POST /_analyze
{
  "analyzer": "standard",
  "text": "The Quick Brown Fox :< AHHHHH."
}
```

回應會顯示切出的 tokens：`["the", "quick", "brown", "fox", "ahhhhh"]`

也可以自訂 analyzer 組合來測試：

```
POST /_analyze
{
  "char_filter": ["html_strip"],
  "tokenizer": "standard",
  "filter": ["lowercase"],
  "text": "<p>The Quick Brown Fox</p>"
}
```

### Inverted Index

OpenSearch 使用 **Inverted Index**（倒排索引）來加速搜尋。概念類似書本的索引：

```
傳統索引：Document → 包含哪些詞
倒排索引：詞 → 出現在哪些 Document
```

範例：

| Token | Documents |
|-------|-----------|
| quick | doc1, doc3 |
| brown | doc1, doc2 |
| fox   | doc1 |

當搜尋 `quick` 時，OpenSearch 直接查表找到 `doc1, doc3`，而不需要掃描所有 document。

## Mapping 基礎

**Mapping**（映射）定義了 index 中每個 field 的資料類型和處理方式。可以把它想成資料庫的 schema。

### Dynamic Mapping vs Explicit Mapping

OpenSearch 支援兩種 mapping 方式：

| 類型 | 說明 | 適用場景 |
|------|------|----------|
| **Dynamic Mapping** | OpenSearch 自動推斷 field 類型 | 快速開發、探索性分析 |
| **Explicit Mapping** | 手動定義 field 類型 | 生產環境、需要精確控制 |

兩者可以同時存在：你可以先定義重要 field 的 mapping，讓 OpenSearch 自動處理其他 field。

### 常用 Data Types

| 類型 | 說明 | 使用場景 |
|------|------|----------|
| `text` | 會被 analyzer 處理 | 全文搜尋（文章內容、描述） |
| `keyword` | 不會被分析，原樣儲存 | 精確匹配、聚合、排序（ID、標籤、狀態） |
| `long` / `integer` | 整數 | 數量、計數 |
| `double` / `float` | 浮點數 | 價格、分數 |
| `boolean` | 布林值 | 開關、狀態 |
| `date` | 日期時間 | 時間戳記、建立日期 |
| `object` | 巢狀 JSON 物件 | 結構化資料 |
| `nested` | 獨立索引的物件陣列 | 需要精確查詢陣列中物件的場景 |
| `geo_point` | 地理座標 | 位置資料 |

### text vs keyword

這是最常見的選擇題：

| 面向 | `text` | `keyword` |
|------|--------|-----------|
| 分析 | 會被 analyzer 處理 | 不處理，原樣儲存 |
| 搜尋 | 全文搜尋（match query） | 精確匹配（term query） |
| 聚合 | 不支援 | 支援 |
| 排序 | 不支援 | 支援 |
| 範例 | 文章內容、商品描述 | user_id、email、status |

:::info
**什麼是聚合（Aggregation）？**

聚合是對資料進行統計分析的操作，例如：
- 「每個 status code 出現幾次？」→ 結果：200 出現 5000 次、404 出現 120 次
- 「每小時的請求數量？」→ 結果：12:00 有 300 筆、13:00 有 450 筆
- 「response_time 的平均值和最大值？」→ 結果：平均 50ms、最大 2000ms

聚合讓你可以建立 Dashboard 圖表（如 pie chart、histogram）來視覺化 log 資料的分布和趨勢。

為什麼 `text` 不支援聚合？因為 `text` 會被拆成多個 token，OpenSearch 不知道該對哪個 token 做統計。
:::

### object vs nested

當 field 包含 JSON 物件時，需要選擇 `object` 或 `nested`：

```json
{
  "comments": [
    { "author": "Alice", "text": "Great!" },
    { "author": "Bob", "text": "Thanks!" }
  ]
}
```

| 類型 | 內部儲存方式 | 查詢能力 |
|------|-------------|----------|
| `object` | 扁平化儲存 | 無法精確查詢「Alice 說 Great」 |
| `nested` | 各物件獨立索引 | 可以精確查詢物件內的關聯 |

`object` 類型會將上述資料扁平化為：
```
comments.author: ["Alice", "Bob"]
comments.text: ["Great!", "Thanks!"]
```

這樣查詢 `author=Alice AND text=Thanks` 會錯誤地匹配到這份 document。

## Explicit Mapping

在生產環境中，建議使用 **Explicit Mapping** 明確定義 field 類型。

### 建立 Index 時定義 Mapping

```
PUT /logs
{
  "mappings": {
    "properties": {
      "timestamp": {
        "type": "date"
      },
      "level": {
        "type": "keyword"
      },
      "message": {
        "type": "text"
      },
      "host": {
        "type": "keyword"
      },
      "response_time_ms": {
        "type": "integer"
      },
      "request": {
        "type": "object",
        "properties": {
          "method": { "type": "keyword" },
          "path": { "type": "keyword" },
          "body": { "type": "text" }
        }
      }
    }
  }
}
```

### 查看現有 Mapping

```
GET /logs/_mapping
```

### 新增 Field 到現有 Index

你可以新增 field，但 **不能修改已存在 field 的類型**：

```
PUT /logs/_mapping
{
  "properties": {
    "user_agent": {
      "type": "text"
    }
  }
}
```

如果需要修改 field 類型，必須 reindex 到新的 index。

## Multi-fields

有時候同一個 field 需要支援多種搜尋方式。例如 `title` 欄位：
- 全文搜尋時需要 `text` 類型
- 排序和聚合時需要 `keyword` 類型

**Multi-fields** 可以讓同一個 field 以多種方式索引：

```
PUT /articles
{
  "mappings": {
    "properties": {
      "title": {
        "type": "text",
        "fields": {
          "keyword": {
            "type": "keyword"
          },
          "english": {
            "type": "text",
            "analyzer": "english"
          }
        }
      }
    }
  }
}
```

這樣你可以：
- 用 `title` 做全文搜尋（standard analyzer）
- 用 `title.keyword` 做精確匹配、排序、聚合
- 用 `title.english` 做英文詞幹搜尋

### 查詢 Multi-fields

```
# 全文搜尋
GET /articles/_search
{
  "query": {
    "match": { "title": "quick brown fox" }
  }
}

# 精確匹配
GET /articles/_search
{
  "query": {
    "term": { "title.keyword": "The Quick Brown Fox" }
  }
}

# 按 title 排序
GET /articles/_search
{
  "sort": [
    { "title.keyword": "asc" }
  ]
}
```

## Dynamic Template

當你有大量 field 需要設定類似的 mapping 規則時，可以使用 **Dynamic Template** 自動套用。

### 範例：所有字串欄位同時建立 text 和 keyword

```
PUT /logs-with-template
{
  "mappings": {
    "dynamic_templates": [
      {
        "strings_as_text_and_keyword": {
          "match_mapping_type": "string",
          "mapping": {
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
    ]
  }
}
```

### 範例：根據 field 名稱套用規則

```
PUT /logs-with-template
{
  "mappings": {
    "dynamic_templates": [
      {
        "longs_for_count_fields": {
          "match": "*_count",
          "mapping": {
            "type": "long"
          }
        }
      },
      {
        "dates_for_timestamp_fields": {
          "match": "*_at",
          "mapping": {
            "type": "date"
          }
        }
      }
    ]
  }
}
```

這樣 `request_count` 會自動成為 `long` 類型，`created_at` 會自動成為 `date` 類型。

### Dynamic Template 匹配條件

| 條件 | 說明 |
|------|------|
| `match_mapping_type` | 匹配 JSON 類型（string, long, double, boolean, date, object） |
| `match` | 匹配 field 名稱（支援萬用字元 `*`） |
| `unmatch` | 排除的 field 名稱 |
| `path_match` | 匹配完整路徑（如 `request.headers.*`） |
| `path_unmatch` | 排除的路徑 |

## Type Coercion

OpenSearch 會嘗試將資料轉換成 mapping 定義的類型：

```
PUT /coercion-example/_doc/1
{ "number": 123 }

PUT /coercion-example/_doc/2
{ "number": "456" }  # 字串 "456" 會被轉成數字 456

PUT /coercion-example/_doc/3
{ "number": "7.1m" }  # 無法轉換，會報錯
```

注意：`_source` 中會保留原始值（字串 `"456"`），但 inverted index 中儲存的是轉換後的數字。

可以停用 coercion：

```
PUT /strict-index
{
  "mappings": {
    "properties": {
      "number": {
        "type": "integer",
        "coerce": false
      }
    }
  }
}
```

## 小結

1. **Analyzer** 將文字拆解成 tokens，由 Character Filter、Tokenizer、Token Filter 組成
2. **Inverted Index** 讓 OpenSearch 能快速搜尋文字
3. **Mapping** 定義 field 的資料類型和處理方式
4. **text** 用於全文搜尋，**keyword** 用於精確匹配、聚合、排序
5. **Multi-fields** 讓同一個 field 支援多種搜尋方式
6. **Dynamic Template** 可以自動為符合條件的 field 套用 mapping 規則

## 思考題

<details>
<summary>Q1：為什麼 <code>text</code> 類型不能用於排序和聚合？</summary>

因為 `text` 類型的資料會被 analyzer 拆解成多個 tokens。

例如 `"The Quick Brown Fox"` 會被拆成 `["the", "quick", "brown", "fox"]`。當你要排序時，OpenSearch 不知道該用哪個 token 來排序。

如果需要對文字欄位排序，應該：
1. 使用 `keyword` 類型（如果不需要全文搜尋）
2. 使用 multi-fields，同時建立 `text` 和 `keyword`

</details>

<details>
<summary>Q2：什麼時候應該用 <code>nested</code> 而不是 <code>object</code>？</summary>

當你需要**精確查詢物件陣列中的關聯關係**時，使用 `nested`。

例如你有一個電商訂單，包含多個商品：
```json
{
  "items": [
    { "name": "iPhone", "quantity": 1 },
    { "name": "Case", "quantity": 2 }
  ]
}
```

如果用 `object` 類型，查詢「name=iPhone AND quantity=2」會錯誤地匹配到這個訂單（因為扁平化後失去了關聯）。

使用 `nested` 類型可以正確處理這種查詢。

代價是：`nested` 類型會為每個物件建立獨立的 hidden document，增加儲存和查詢成本。

</details>

<details>
<summary>Q3：為什麼不能修改已存在 field 的類型？</summary>

因為 OpenSearch 的 inverted index 是基於 field 類型建立的。

如果一個 field 原本是 `text` 類型，資料已經被 analyzer 處理並建立了 inverted index。如果允許改成 `keyword` 類型，舊的 inverted index 格式就不相容了。

解決方法：
1. 建立新的 index，使用正確的 mapping
2. 使用 Reindex API 將資料搬移到新 index
3. 使用 alias 切換到新 index

這也是為什麼在生產環境中，應該在一開始就明確定義 mapping。

</details>

## 參考資料

- [OpenSearch Text Analysis](https://opensearch.org/docs/latest/analyzers/)
- [OpenSearch Mapping](https://opensearch.org/docs/latest/field-types/)
- [Elasticsearch Text Analysis](https://www.elastic.co/guide/en/elasticsearch/reference/current/analysis.html)
