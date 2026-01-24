---
title: OpenSearch：Analyzer 與 Mapping 設定
description: 學習 OpenSearch 的文字分析器與映射設定，包含動態模板
pubDate: 2025-12-06
slug: observability-004-schema
tags:
  - "observibility"
  - "opensearch"
---

<!--
- analysis
    - what is analyzer
    - built-in analyzers
    - custom analyzers
- mapping
    - what is mapping
    - dynamic mapping
    - explicit mapping
    - data types
    - multi-fields
- dynamic template
-->

## Analysis and Analyzers

- 有些時候被稱為 text analysis
- analyzer 會被用來處理 text field
- analyzer 會把 text field 切成多個 token，並且存成適合快速搜尋的格式
- \_source 裡面的文字仍然會保留原本的內容，但不會參與搜尋
- text 會在 index 時被 analyzer 處理

## Intro of Analyzer

analyzer 由三個部分組成：

1. character filter
2. tokenizer
3. token filter

### character filter

- 在 tokenizer 之前處理文字(新增、刪除、取代字元)
- analyzer 可以有零個或多個 character filter
- character filter 會根據定義的順序來處理文字

以下是一些常見的 character filter 使用範例：

- `html_strip`: 移除 HTML 標籤
  - `<p>This is a <strong>test</strong>.</p>` 會被轉換成 `This is a test.`

### tokenizer

- analyzer 必須有且只能有一個 tokenizer
- tokenizer 會把文字切成多個 token (通常是字詞)
- 不同的 tokenizer 有不同的切割規則

以下是一些常見的 tokenizer：

- `standard`: 預設的 tokenizer，會根據空白字元和標點符號來切割文字
  - 例如：`happy birth-day, friend!` 會被切成 `["happy", "birth", "day", "friend"]`
- `whitespace`: 只根據空白字元來切割文字
  - 例如：`The quick brown fox.` 會被切成 `["The", "quick", "brown", "fox."]`
- `keyword`: 不切割文字

### token filter

- 在 tokenizer 之後處理 token (新增、刪除、取代 token)
- analyzer 可以有零個或多個 token filter
- token filter 會根據定義的順序來處理 token

以下是一些常見的 token filter 使用範例：

- `lowercase`: 把 token 轉成小寫
  - 例如：`["The", "Quick", "Brown", "Fox"]` 會被轉換成 `["the", "quick", "brown", "fox"]`

### OpenSearch 預設 analyzer

OpenSearch 預設處理 text field 時,會使用以下的 analyzer 組合(aka standard analyzer)：

1. chahracter filter 會使用 `none`
2. 會使用 `standard` tokenizer
3. token filter 會使用 `lowercase`

### 有用的 Opensearch analyze API

你可以使用 analyze API 來測試不同的 analyzer 組合對文字的處理效果(通常用在自定
analyzer)。
以下是使用 Dev Tools 來執行 analyze API 的範例：

```
POST /_analyze
{
  "analyzer": "standard",
  "text": "The     Quick Brown Fox :< AHHHHH."
}
```

```
POST /_analyze
{
  "char_filter": [
    {
      "type": "html_strip"
    }
  ],
  "tokenizer": {
    "type": "standard"
  },
  "filter": [
    {
      "type": "lowercase"
    }
  ],
  "text": "<p>The     Quick Brown Fox :< AHHHHH.</p>"
}
```

### Inverted Indics

- OpenSearch 使用倒排索引 (Inverted Index) 來加速搜尋
- fields 裡面的值會根據不同的 data type 來決定如何建立 inverted index
- 以上行為都是由 Apache Lucene 負責實作，OpenSearch 只是提供一個介面來操作 Lucene

## Intro to Mapping

- mapping 是用來定義 index 裡面 fields 的結構和屬性
- mapping 可以定義 field 的 data type、analyzer、indexing options 等等
- mapping 可以在建立 index 時定義，也可以在 index 建立後更新
- mapping 可以分為 dynamic mapping 和 explicit mapping
  - dynamic mapping: OpenSearch 會自動根據文件的內容來推斷 field 的 data type
  - explicit mapping: 使用者手動定義 field 的 data type 和屬性
- dynamic mapping 以及 explicit mapping 可以同時存在於同一個 index 中

### Overview of Data Types

常用的 data types 包括：

- text: 用來儲存大量文字資料，會被 analyzer 處理(適合全文搜尋)
- keyword: 用來儲存不需要被分析的文字資料(適合 exact match search)
- date: 用來儲存日期和時間資料
- long/integer/short/byte/double/float/half_float/scaled_float: 用來儲存數值資料
- boolean: 用來儲存布林值 (true/false)
- object: 用來儲存 JSON 物件
- nested: 用來儲存陣列中的 JSON 物件 (支援複雜查詢)
- geo_point: 用來儲存地理座標

### `object` object type

- object type 用來儲存 JSON 物件
- object 可以是 nested 的 object
- 在 Mapping 定義裡使用 properties 來定義 object 裡面的欄位
- object 不諱在 apache lucene 裡面直接以 object 的形式儲存，而是會把 object
  裡面的欄位展開(flatten)成多個欄位來儲存，讓我們可以正確 index 以及搜尋
  object 裡面的欄位

### `nested` object type

- nested type 用來儲存陣列中的 JSON 物件
- 相比 `object` type，`nested` type 可以針對陣列中的物件進行複雜查詢
- 在 Mapping 定義裡使用 type: nested 來定義 nested type
- apache lucene 內部並沒有 object type，因此裡面會被儲存為多個 hidden document
  ，以便支援複雜查詢

### `keyword` data type

- keyword type 用來儲存不需要被分析的文字資料
- keyword type 適合用來做 exact match search、aggregations、sorting
- keyword type 不會被 analyzer 處理，會以原始形式儲存
- 如果需要 full text search，請使用 text type 儲存

## Type Coercion

```
PUT /coercion-example/_doc/2
{
  "number": 456
}

PUT /coercion-example/_doc/1
{
  "number": "123.1"

}

PUT /coercion-example/_doc/3
{
  "number": "7.1m"
}

# get current mappings
# check _source, some fields is string, and it actually convert to number when
# build up inverted index
GET /coercion-example/_search
{
  "query": {
    "match_all": {}
  }
```

## Explicit mapping

## Reference

- [text analysis](https://www.elastic.co/docs/manage-data/data-store/text-analysis)
