---
title: OpenSearch：Document 與 Index 基礎
description: 深入理解 OpenSearch 的文件與索引概念，包含 CRUD 操作與路由機制
pubDate: 2025-12-05
slug: observability-003-opensearch-index
tags:
  - "observibility"
  - "opensearch"
---

<!--
- what is document
    - what is document id
    - create/update document / upsert
    - script update
    - replace / delete document
- how data update/delete works in opensearch
- how doc routing works
- what is index
    - update by query
    - delete by query
    - batch operations
-->

## OpenSearch document 與 index 基礎介紹

在 OpenSearch 中，資料是以文件（document）的形式儲存的，而這些文件則被組織在
索引（index）中。理解文件與索引的概念對於有效地使用 OpenSearch 至關重要。

## Document

Document 是 OpenSearch 中的基本資料單位，類似於關聯式資料庫中的一行資料。
每個 Document 都是以 JSON 格式表示的，包含多個欄位（fields）及其對應的值。
每個 Document 都有一個唯一的識別碼，稱為 Document ID，用於在索引中定位該文件。

### Create a Document

Index 如果沒有 document 一點意義都沒有，所以我們需要先建立一些 document。
以下是一個使用 OpenSearch Dev Tools 插件來建立 document 的範例：

```
# create an index
PUT /my-first-index
{
    "settings": {
        "number_of_shards": 1,
        "number_of_replicas": 1
    }
}

POST /my-first-index/_doc/
{
  "title": "Hello World",
  "content": "This is my first document in OpenSearch.",
  "timestamp": "2024-06-01T12:00:00Z"
}
```

以下是 return 的結果：

```
{
  "_index": "my-first-index",
  "_type": "_doc",
  "_id": "sOB88poBfrhnZ2803MoC",
  "_version": 1,
  "result": "created",
  "_shards": {
    "total": 2,
    "successful": 1,
    "failed": 0
  },
  "_seq_no": 0,
  "_primary_term": 1
}
```

:::info
注意看 \_shards 的部分，total 是 2，successful 是 1，表示這個 index 有兩個
shard，但是只有一個 shard 成功寫入資料，這是因為我們在建立 index 的時候，
設定了 number_of_replicas 為 1，但是我們只有一個節點，所以無法建立 replica shard。

可以在 Devtools 中執行以下指令來查看 shard 的狀態：

```
GET _cat/shards/my-first-index?v
```

現在就會看到有 UNASSIGNED 的 replica shard，因此 successful 的 shard 只有 1 個：

```
index          shard prirep state      docs store ip         node
my-first-index 0     p      STARTED       1 5.1kb 172.19.0.3 opensearch
my-first-index 0     r      UNASSIGNED
```

:::

:::info
請看一下 \_id 的部分，這是 OpenSearch 自動產生的 Document ID，如果你想要自己指定 Document ID， 可以使用 PUT 方法來建立 document

```
PUT /my-first-index/_doc/2
{
  "title": "Hello World",
  "content": "This is my second document in OpenSearch.",
  "timestamp": "2024-06-01T12:00:00Z"
}
```

以下是 return 的結果：

```
{
  "_index": "my-first-index",
  "_type": "_doc",
  "_id": "1",
  "_version": 1,
  "result": "created",
  "_shards": {
    "total": 2,
    "successful": 1,
    "failed": 0
  },
  "_seq_no": 0,
  "_primary_term": 1
}
```

:::

### Get Document by ID

你可以使用 Document ID 來取得特定的 document，以下是一個使用 OpenSearch Dev Tools 插件來取得 document 的範例：

```
GET /my-first-index/_doc/2
```

以下是 return 的結果：

```
{
  "_index": "my-first-index",
  "_type": "_doc",
  "_id": "2",
  "_version": 1,
  "_seq_no": 1,
  "_primary_term": 1,
  "found": true,
  "_source": {
    "title": "Hello World",
    "content": "This is my second document in OpenSearch.",
    "timestamp": "2024-06-01T12:00:00Z"
  }
}
```

如果查詢的 Document ID 不存在，則會回傳以下結果(found = false)：

```
{
  "_index": "my-first-index",
  "_type": "_doc",
  "_id": "3",
  "found": false
}
```

### Update Document

你可以使用 Document ID 來更新特定的 document(document 同樣可以增加原本沒有的
attribute)，以下是一個使用 OpenSearch Dev Tools 插件來更新 document 的範例：

```
POST /my-first-index/_update/2
{
  "doc": {
    "content": "This is my updated second document in OpenSearch."
    "tags": ["update", "opensearch"]
  }
}
```

以下是 return 的結果：

```
{
  "_index": "my-first-index",
  "_type": "_doc",
  "_id": "2",
  "_version": 2,
  "result": "updated",
  "_shards": {
    "total": 2,
    "successful": 1,
    "failed": 0
  },
  "_seq_no": 2,
  "_primary_term": 1
}
```

可以用以下指令來查看更新後的 document：

```
GET /my-first-index/_doc/2
```

以下是 return 的結果：

```
{
  "_index": "my-first-index",
  "_type": "_doc",
  "_id": "2",
  "_version": 2,
  "_seq_no": 2,
  "_primary_term": 1,
  "found": true,
  "_source": {
    "title": "Hello World",
    "content": "This is my updated second document in OpenSearch.",
    "timestamp": "2024-06-01T12:00:00Z"
  }
}
```

在不考慮 Index mapping 的情況下，OpenSearch 的更新操作實際上是透過建立一個新的
版本來實現的，就有的 doc 其實是 immutable 的。當你更新一個 document 時，
OpenSearch 會創建一個新的版本，並將其標記為最新版本，而舊版本則會被標記為過時。
這種方式確保了資料的一致性和完整性(Optimistic Concurrency Control)

我們甚至可以使用以下 API 查看 document 的版本歷史：

```
GET /my-first-index/_doc/2?realtime=true
```

除此之外，OpenSearch 也支援使用 script 來更新 document 的內容，這樣可以更靈活的
修改 OpenSearch document。若是有需要可以看以下的[官方文件](https://docs.opensearch.org/latest/api-reference/document-apis/update-document/)]

### UpSert Document

Upsert 是指如果 document 存在就更新它，如果不存在就建立一個新的 document。在
RESTful API 中，有些時候我們不想多做一次查詢來確認 document 是否存在，並且用
PUT 或 POST 來建立或更新 document，因此 OpenSearch 提供了 upsert 的功能。

以下是一個使用 OpenSearch Dev Tools 插件來進行 upsert 的範例

```
POST /my-first-index/_update/3
{
  "doc": {
    "title": "Hello World",
    "content": "This is my third document in OpenSearch.",
    "timestamp": "2024-06-01T12:00:00Z"
  },
  "doc_as_upsert": true
}
```

以下是 return 的結果：

```
{
  "_index": "my-first-index",
  "_type": "_doc",
  "_id": "3",
  "_version": 1,
  "result": "created",
  "_shards": {
    "total": 2,
    "successful": 1,
    "failed": 0
  },
  "_seq_no": 0,
  "_primary_term": 1
}
```

:::info
可以看到 result 是 created，表示這個 document 是被建立的，而不是被更新的。
:::

我們再次使用相同的 API 來更新這個 document：

```
POST /my-first-index/_update/3
{
  "doc": {
    "content": "This is my updated third document in OpenSearch."
  },
  "doc_as_upsert": true
}
```

以下是 return 的結果：

```
{
  "_index": "my-first-index",
  "_type": "_doc",
  "_id": "3",
  "_version": 2,
  "result": "updated",
  "_shards": {
    "total": 2,
    "successful": 1,
    "failed": 0
  },
  "_seq_no": 1,
  "_primary_term": 1
}
```

:::info
可以看到 result 是 updated，表示這個 document 是被更新的，而不是被建立的
:::

### Replace Document

如果你想要完全替換一個 document 的內容，可以使用 PUT 方法來實現。以下是一個
使用 OpenSearch Dev Tools 插件來替換 document 的範例：

```
PUT /my-first-index/_doc/3
{
    "title": "Hello World",
    "content": "This is my replaced third document in OpenSearch.",
}
```

會發現 timestamp 這個欄位不見了，因為我們是用 PUT 方法來替換整個 document
的內容，而不是 update 他的值。

### Delete Document

你可以使用 Document ID 來刪除特定的 document，以下是一個使用 OpenSearch Dev Tools 插件來刪除 document 的範例：

```
DELETE /my-first-index/_doc/3
```

以下是 return 的結果：

```
{
  "_index": "my-first-index",
  "_type": "_doc",
  "_id": "3",
  "_version": 3,
  "result": "deleted",
  "_shards": {
    "total": 2,
    "successful": 1,
    "failed": 0
  },
  "_seq_no": 2,
  "_primary_term": 1
}
```

## Shard Allocation and Document Routing

在這篇教學裡，只簡單介紹 shard allocation 以及 document routing 的概念。若是有
想要深入瞭解的，可以參考 ElasticSearch [官方文件](https://www.elastic.co/docs/reference/elasticsearch/configuration-reference/cluster-level-shard-allocation-routing-settings) (寫的比較完整)

在真正進入到介紹前，可以先思考一下下面幾個問題：

1. OpenSearch 怎麼知道要把某個 document 存到哪一個 shard？
2. Document 如何被 OpenSearch 查詢到他的位置(CRUD operation)？

答案其實就是我們要介紹的 shard allocation 以及 document routing。

### Shard Allocation

Shard Allocation 是指 OpenSearch 如何將索引的分片（shard）分配到不同的節點上。
每個索引可以被分成多個分片，這些分片可以分佈在不同的節點上，以提高資料的可用性和查詢效能。
當你建立一個索引時，可以指定分片的數量（number_of_shards）和副本的數量（number_of_replicas）。
當 OpenSearch 接收到一個新的 document 時，會根據索引的分片數量和副本數量，將 document 分配到適當的分片上。這個過程稱為 shard allocation。

### Document Routing

Document Routing 是指 OpenSearch 如何決定將一個 document 存儲到哪一個分片上。
當你建立一個新的 document 時，OpenSearch 會使用一個 hash 函數來計算 document 的路由值（routing value）。
這個路由值是根據 document 的 ID 計算出來的，然後 OpenSearch 會根據路由值將 document 分配到適當的分片上。
這個過程稱為 document routing。

因此，primary shard 的數量在建立 index 時就已經決定了，也是無法更改的，因為若是
要更改 primary shard 的數量，會影響到 document routing 的計算方式，導致
document 無法正確地被路由到適當的分片上。

若是因為效能的需求，想要更改 index 的 shard 數量，可以使用[Reindex API](https://docs.opensearch.org/latest/api-reference/index-apis/reindex/)來達成。

## 其他有用 OpenSearch document API

### bulk API

bulk API 允許你在單一請求中執行多個 CRUD 操作，這對於需要處理大量資料的應用程式
非常有用。

以下是使用 Dev Tools 來執行 bulk API 的範例：

```
POST /_bulk
{ "index" : { "_index" : "my-first-index", "_id" : "4" } }
{ "title": "Bulk Document 1", "content": "This is the first bulk document." }
{ "index" : { "_index" : "my-first-index", "_id" : "5" } }
{ "title": "Bulk Document 2", "content": "This is the second bulk document." }
{ "delete" : { "_index" : "my-first-index", "_id" : "2" } }
```

### update / deltete by query API

update by query API 允許你根據查詢條件來更新多個 document，而 delete by query API 允許你根據查詢條件來刪除多個 document。

以下是使用 Dev Tools 來執行 update by query API 的範例：

```
POST /my-first-index/_update_by_query
{
    "script": {
        "source": "ctx._source.content = 'This document has been updated by query.'",
        "lang": "painless"
    },
    "query": {
        "match": {
            "title": "Bulk Document 1"
        }
    }
}
```

以下是使用 Dev Tools 來執行 delete by query API 的範例：

```
POST /my-first-index/_delete_by_query
{
    "query": {
        "match": {
            "title": "Bulk Document 2"
        }
    }
}
```

## 小結

1. Document 是 OpenSearch 中的基本資料單位，以 JSON 格式表示，包含多個欄位及其對應的值。
2. document ID 是用來唯一識別每個 Document 的標識符。
3. Index 是用來組織和管理 Document 的結構，可以包含多個 Document。
4. 了解如何建立、取得、更新和刪除 Document 是有效使用 OpenSearch 的關鍵。
5. Shard Allocation 和 Document Routing 是 OpenSearch 中重要的概念，
   影響資料的分佈和查詢效能。
6. bulk API 和 update/delete by query API 提供了高效處理大量資料的能力。
