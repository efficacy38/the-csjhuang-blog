---
title: Vector 實戰：收集與轉換 Log
description: 使用 Vector 收集 syslog 和 nginx log，學習 VRL 語法進行 log 解析
date: 2025-12-06
slug: observability-005-vector-hands-on
series: "observability"
tags:
  - "observability"
  - "vector"
  - "logging"
---

:::note
**前置閱讀**

本文假設你已經讀過系列的前幾篇文章：
- [Log Pipeline 架構與工具選型](/posts/observability-001-log-pipeline)——理解 Vector 的架構和核心元件

本文會實際操作 Vector，建議準備一個 Linux 環境（可以是 VM 或 Docker）。
:::

## 安裝 Vector

Vector 支援多種安裝方式，這裡介紹最常用的幾種。

### 使用官方腳本安裝（Linux）

```bash
curl --proto '=https' --tlsv1.2 -sSfL https://sh.vector.dev | bash
```

### 使用套件管理器

```bash
# Debian/Ubuntu
curl -1sLf 'https://repositories.timber.io/public/vector/cfg/setup/bash.deb.sh' | sudo -E bash
sudo apt install vector

# RHEL/CentOS
curl -1sLf 'https://repositories.timber.io/public/vector/cfg/setup/bash.rpm.sh' | sudo -E bash
sudo yum install vector

# macOS
brew install vector
```

### 使用 Docker

```bash
docker run -v $(pwd)/vector.yaml:/etc/vector/vector.yaml:ro timberio/vector:latest-alpine
```

### 驗證安裝

```bash
vector --version
```

## Vector 配置基礎

Vector 的配置檔預設位於 `/etc/vector/vector.yaml`。基本結構如下：

```yaml
sources:
  # 定義資料來源

transforms:
  # 定義資料處理邏輯

sinks:
  # 定義資料輸出目的地
```

### 第一個範例：echo 測試

建立一個最簡單的配置來驗證 Vector 運作正常：

```yaml
# vector.yaml
sources:
  demo:
    type: demo_logs
    format: shuffle
    interval: 1

sinks:
  console:
    type: console
    inputs:
      - demo
    encoding:
      codec: json
```

執行：

```bash
vector --config vector.yaml
```

你會看到 Vector 每秒輸出一條假的 log 到終端機。按 `Ctrl+C` 停止。

## 收集 Syslog

**Syslog** 是 Unix/Linux 系統標準的日誌協議。Vector 可以作為 syslog server 接收來自其他系統的 log。

### 配置 Vector 接收 Syslog

```yaml
sources:
  syslog:
    type: syslog
    address: "0.0.0.0:514"
    mode: udp

sinks:
  console:
    type: console
    inputs:
      - syslog
    encoding:
      codec: json
```

### 測試發送 Syslog

在另一個終端機發送測試訊息：

```bash
# 使用 logger 命令發送 syslog
logger -n 127.0.0.1 -P 514 --udp "Test message from logger"

# 或使用 nc
echo "<14>Test message from nc" | nc -u 127.0.0.1 514
```

### Syslog 解析結果

Vector 會自動解析 syslog 格式，產生結構化資料：

```json
{
  "appname": "logger",
  "facility": "user",
  "host": "myhost",
  "message": "Test message from logger",
  "severity": "info",
  "timestamp": "2024-06-01T12:00:00Z"
}
```

### 讀取 Journald（Systemd 日誌）

如果你的系統使用 systemd，可以直接讀取 journald：

```yaml
sources:
  journald:
    type: journald
    include_units:
      - sshd.service
      - nginx.service

sinks:
  console:
    type: console
    inputs:
      - journald
    encoding:
      codec: json
```

## 收集 Nginx Log

Nginx 是最常見的 web server 之一。我們來看如何收集和解析 nginx access log。

### Nginx Log 格式

預設的 nginx combined log format：

```
192.168.1.1 - - [01/Jun/2024:12:00:00 +0800] "GET /api/users HTTP/1.1" 200 1234 "https://example.com" "Mozilla/5.0..."
```

### 配置 Vector 讀取 Nginx Log 檔案

```yaml
sources:
  nginx_access:
    type: file
    include:
      - /var/log/nginx/access.log
    read_from: beginning

sinks:
  console:
    type: console
    inputs:
      - nginx_access
    encoding:
      codec: json
```

此時輸出的 `message` 欄位是原始的 log 字串，還沒有被解析。

## VRL：Vector Remap Language

**VRL**（Vector Remap Language）是 Vector 的資料處理語言。它提供了豐富的函數來解析、轉換、過濾 log。

### VRL 核心概念

在學習 VRL 語法之前，先理解一個關鍵概念：

:::info
**`.` 是什麼？**

在 VRL 中，**`.`（點）代表「當前正在處理的事件」**。

每條 log 進入 Vector 時，會被轉換成一個 JSON 物件。`.` 就是這個物件的「根」：
- `.message` — 存取物件的 `message` 欄位
- `.request.path` — 存取巢狀欄位 `request` 下的 `path`
- `. = { ... }` — 完全覆蓋整個物件

可以把 `.` 想成「this」或「self」：它指向你正在處理的那筆資料。
:::

### VRL 基本語法

```yaml
transforms:
  parse_log:
    type: remap
    inputs:
      - nginx_access
    source: |
      # 這裡寫 VRL 程式碼
      # . 代表當前的 log 事件
      .processed_at = now()    # 新增一個欄位
      .env = "production"      # 新增另一個欄位
```

### 常用 VRL 操作

#### 存取欄位

```ruby
# 讀取欄位
.message           # 讀取 message 欄位
.request.path      # 讀取巢狀欄位

# 設定欄位
.new_field = "value"        # 新增欄位
.request.method = "GET"     # 設定巢狀欄位

# 刪除欄位
del(.unwanted_field)        # 移除不需要的欄位
```

#### 型別轉換

```ruby
# 字串轉整數
.status = to_int!(.status)

# 字串轉浮點數
.response_time = to_float!(.response_time)

# 字串轉布林
.is_error = to_bool!(.is_error)
```

:::info
**`!` 是什麼意思？**

VRL 中有些函數可能會失敗（例如把 `"abc"` 轉成數字）。這些函數叫做 **fallible function**（可失敗函數）。

- `to_int(.status)` — 如果失敗，回傳 `null`
- `to_int!(.status)` — 如果失敗，**中止處理這筆 log**（log 會被丟棄）

使用 `!` 是一種「快速失敗」策略：與其讓錯誤資料進入系統，不如直接丟棄。

你也可以用 `??` 提供預設值：
```ruby
.status = to_int(.status) ?? 0  # 失敗時使用 0
```
:::

#### 條件判斷

```ruby
if .status >= 500 {
  .level = "error"
} else if .status >= 400 {
  .level = "warn"
} else {
  .level = "info"
}
```

#### 字串處理

```ruby
# 取代
.message = replace(.message, "password", "[REDACTED]")

# 分割
.parts = split(.path, "/")

# 擷取子字串
.first_char = slice!(.message, 0, 1)
```

### 解析 Nginx Combined Log

使用 `parse_regex` 解析 nginx log：

```yaml
transforms:
  parse_nginx:
    type: remap
    inputs:
      - nginx_access
    source: |
      # 解析 nginx combined log format
      . = parse_regex!(.message, r'^(?P<client_ip>\S+) \S+ \S+ \[(?P<timestamp>[^\]]+)\] "(?P<method>\S+) (?P<path>\S+) \S+" (?P<status>\d+) (?P<bytes>\d+) "(?P<referrer>[^"]*)" "(?P<user_agent>[^"]*)"')

      # 轉換資料類型
      .status = to_int!(.status)
      .bytes = to_int!(.bytes)

      # 解析時間戳記
      .timestamp = parse_timestamp!(.timestamp, "%d/%b/%Y:%H:%M:%S %z")

      # 加入 metadata
      .source = "nginx"
      .host = get_hostname!()
```

:::info
**Regex 拆解說明**

上面的 regex 看起來很複雜，讓我們逐段解析：

| Log 部分 | Regex | 說明 |
|----------|-------|------|
| `192.168.1.1` | `(?P<client_ip>\S+)` | 捕獲非空白字元，命名為 `client_ip` |
| `- -` | `\S+ \S+` | 跳過兩個欄位（ident 和 auth） |
| `[01/Jun/2024:12:00:00 +0800]` | `\[(?P<timestamp>[^\]]+)\]` | 捕獲方括號內的內容 |
| `"GET` | `"(?P<method>\S+)` | 捕獲 HTTP method |
| `/api/users` | `(?P<path>\S+)` | 捕獲請求路徑 |
| `HTTP/1.1"` | `\S+"` | 跳過 protocol |
| `200` | `(?P<status>\d+)` | 捕獲數字，命名為 `status` |
| `1234` | `(?P<bytes>\d+)` | 捕獲數字，命名為 `bytes` |
| `"https://..."` | `"(?P<referrer>[^"]*)"` | 捕獲引號內內容 |
| `"Mozilla/5.0..."` | `"(?P<user_agent>[^"]*)"` | 捕獲 User-Agent |

**語法說明：**
- `(?P<name>...)` — 具名捕獲群組，結果會成為欄位名稱
- `\S+` — 一個或多個非空白字元
- `\d+` — 一個或多個數字
- `[^\]]+` — 一個或多個非 `]` 的字元
- `[^"]*` — 零個或多個非 `"` 的字元
:::

### 使用內建 Parser

VRL 提供了常見格式的內建 parser：

```yaml
transforms:
  parse_nginx:
    type: remap
    inputs:
      - nginx_access
    source: |
      # 使用內建的 common log format parser
      . = parse_common_log!(.message)

      # 或使用 grok pattern
      . = parse_grok!(.message, "%{COMBINEDAPACHELOG}")
```

### 過濾不需要的 Log

使用 `filter` transform 過濾 log：

```yaml
transforms:
  filter_health_check:
    type: filter
    inputs:
      - parse_nginx
    condition: |
      # 只保留非 health check 的請求
      !starts_with(string!(.path), "/health")
```

或在 remap 中使用 `abort`：

```yaml
transforms:
  parse_and_filter:
    type: remap
    inputs:
      - nginx_access
    source: |
      . = parse_regex!(.message, r'...')

      # 過濾 health check
      if starts_with(string!(.path), "/health") {
        abort
      }
```

## 完整範例：Nginx + Syslog

結合以上所學，建立一個完整的配置：

```yaml
# /etc/vector/vector.yaml

# 資料來源
sources:
  nginx_access:
    type: file
    include:
      - /var/log/nginx/access.log

  nginx_error:
    type: file
    include:
      - /var/log/nginx/error.log

  syslog:
    type: syslog
    address: "0.0.0.0:514"
    mode: udp

# 資料處理
transforms:
  parse_nginx_access:
    type: remap
    inputs:
      - nginx_access
    source: |
      . = parse_regex!(.message, r'^(?P<client_ip>\S+) \S+ \S+ \[(?P<timestamp>[^\]]+)\] "(?P<method>\S+) (?P<path>\S+) \S+" (?P<status>\d+) (?P<bytes>\d+) "(?P<referrer>[^"]*)" "(?P<user_agent>[^"]*)"')

      .status = to_int!(.status)
      .bytes = to_int!(.bytes)
      .timestamp = parse_timestamp!(.timestamp, "%d/%b/%Y:%H:%M:%S %z")

      .log_type = "nginx_access"
      .host = get_hostname!()

  parse_nginx_error:
    type: remap
    inputs:
      - nginx_error
    source: |
      # nginx error log 格式較簡單
      . = parse_regex!(.message, r'^(?P<timestamp>\d{4}/\d{2}/\d{2} \d{2}:\d{2}:\d{2}) \[(?P<level>\w+)\] (?P<pid>\d+)#(?P<tid>\d+): (?P<message>.*)$')

      .log_type = "nginx_error"
      .host = get_hostname!()

  enrich_syslog:
    type: remap
    inputs:
      - syslog
    source: |
      .log_type = "syslog"
      .host = get_hostname!()

  filter_noise:
    type: filter
    inputs:
      - parse_nginx_access
    condition: |
      # 過濾 health check 和靜態資源
      !starts_with(string!(.path), "/health") &&
      !ends_with(string!(.path), ".js") &&
      !ends_with(string!(.path), ".css") &&
      !ends_with(string!(.path), ".png")

# 輸出到終端機（開發測試用）
sinks:
  console:
    type: console
    inputs:
      - filter_noise
      - parse_nginx_error
      - enrich_syslog
    encoding:
      codec: json
```

## 除錯技巧

### 1. 使用 vector tap 監看資料流

```bash
# 監看特定 source 的資料
vector tap 'nginx_access'

# 監看 transform 後的資料
vector tap 'parse_nginx_access'
```

### 2. 使用 vector vrl 測試 VRL 語法

```bash
# 進入互動式 VRL 環境
vector vrl

# 測試解析
> parse_regex!("192.168.1.1 - - [01/Jun/2024:12:00:00 +0800] \"GET /api HTTP/1.1\" 200 123", r'^(?P<ip>\S+)')
```

### 3. 檢查配置檔語法

```bash
vector validate /etc/vector/vector.yaml
```

### 4. 增加 Log Level

```bash
VECTOR_LOG=debug vector --config vector.yaml
```

## 小結

1. Vector 可以透過 `file` source 讀取 log 檔案，`syslog` source 接收 syslog
2. **VRL** 是 Vector 的資料處理語言，提供豐富的解析和轉換功能
3. 使用 `parse_regex` 或內建 parser 解析 log 格式
4. 使用 `filter` transform 或 VRL 的 `abort` 過濾不需要的 log
5. `vector tap` 和 `vector vrl` 是重要的除錯工具

下一篇，我們會將 Vector 與 OpenSearch 整合，建立完整的 log pipeline。

## 參考資料

- [Vector 官方文件](https://vector.dev/docs/)
- [VRL 函數參考](https://vector.dev/docs/reference/vrl/functions/)
- [Vector Sources](https://vector.dev/docs/reference/configuration/sources/)
- [Vector Transforms](https://vector.dev/docs/reference/configuration/transforms/)
