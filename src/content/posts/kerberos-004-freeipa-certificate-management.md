---
title: FreeIPA Certificate 管理：從手動到自動化
description: 深入了解 FreeIPA 的 PKI 架構，學習使用 ipa-getcert、certmonger 和 ACME 管理主機與服務 certificate
date: 2026-02-01
slug: freeipa-certificate-management
series: "freeipa"
tags:
    - "kerberos"
    - "freeipa"
    - "tls"
    - "certificate"
    - "note"
---

在前面的文章中，我們使用 FreeIPA 建立了完整的 Kerberos 認證環境。你可能注意到，安裝過程中自動產生了許多 certificate——LDAPS、Web UI、CA 本身都使用 TLS 加密。這篇文章要深入探討 FreeIPA 的 certificate 管理機制，讓你能夠為自己的服務申請和管理 certificate。

:::note
**前置閱讀**

本文假設你已經讀過系列的前幾篇文章，特別是：
- [FreeIPA 實戰：部署企業級 Kerberos 環境](/posts/freeipa-kerberos-deployment)——理解 FreeIPA 架構和 Kerberos Principal

如果你不熟悉 Kerberos，建議先閱讀上述文章。本文會使用「Principal」、「keytab」等 Kerberos 術語。
:::

## TLS 與 Certificate 基礎概念

在深入 FreeIPA 的 certificate 管理之前，先快速回顧 TLS 和 certificate 的基本概念。如果你已經熟悉這些，可以跳到下一節。

### 為什麼需要 TLS？

當你的瀏覽器連接到 `https://` 網站時，資料是加密傳輸的。這個加密是由 **TLS（Transport Layer Security）** 協議提供的。TLS 解決兩個問題：

1. **加密**：防止第三方竊聽通訊內容
2. **身份驗證**：確認你連接的真的是目標伺服器，而不是中間人攻擊

### Public Key 密碼學簡介

TLS 使用 **public key 密碼學**（Public Key Cryptography）。每個參與者有一對密鑰：

| 密鑰 | 特性 | 用途 |
|---|---|---|
| **Private Key** | 必須保密，只有擁有者知道 | 解密資料、數位簽章 |
| **Public Key** | 可以公開，任何人都能取得 | 加密資料、驗證簽章 |

```
用 public key 加密 → 只有對應的 private key 能解密
用 private key 簽章 → 任何人都能用 public key 驗證簽章來自 private key 擁有者
```

### Certificate 是什麼？

**Certificate** 是一份「數位身份證」，包含：
- 擁有者的身份資訊（如 `www.example.com`）
- 擁有者的 public key
- 有效期限
- 發行者（CA）的數位簽章

當你連接到 `https://www.example.com` 時：
1. 伺服器出示 certificate
2. 你的瀏覽器檢查 certificate 是否由可信任的 CA 簽發
3. 瀏覽器用 certificate 中的 public key 建立加密連線

### CA（Certificate Authority）的角色

**CA（Certificate Authority）** 是負責簽發 certificate 的可信任機構。CA 的運作原理：

1. CA 擁有自己的密鑰對（CA certificate）
2. 當你申請 certificate 時，CA 驗證你的身份
3. CA 用自己的 private key 在你的 certificate 上簽章
4. 瀏覽器預先信任許多 CA 的 public key
5. 瀏覽器看到 CA 簽章的 certificate，就相信這個 certificate 是可信的

```
Trust Chain：
瀏覽器信任 → CA certificate（預先安裝）
CA certificate 簽發 → Server certificate（你申請的）
因此瀏覽器信任 → Server certificate
```

### CSR（Certificate Signing Request）

**CSR** 是你向 CA 申請 certificate 時提交的文件，包含：
- 你的 public key
- 你想要的 certificate 資訊（如網域名稱）

CSR **不包含** private key——private key 永遠不應該離開你的伺服器。CA 收到 CSR 後，用 CA 的 private key 簽章，產生你的 certificate。

### 常見術語速查

| 術語 | 說明 |
|---|---|
| TLS | Transport Layer Security，HTTPS 使用的加密協議 |
| SSL | TLS 的前身，現在常和 TLS 混用 |
| Private Key | 必須保密的密鑰，用於解密和簽章 |
| Public Key | 可公開的密鑰，用於加密和驗證簽章 |
| Certificate | 包含 public key 和身份資訊的數位文件，由 CA 簽章 |
| CA | Certificate Authority，簽發 certificate 的可信任機構 |
| CSR | Certificate Signing Request，向 CA 申請 certificate 的請求文件 |
| SAN | Subject Alternative Name，certificate 可以包含的額外網域名稱 |
| Certificate Chain | 從終端 certificate 到 Root CA 的信任路徑 |

## 傳統 Certificate 管理的痛點

在沒有集中式 certificate 管理的環境中，管理員通常這樣處理 certificate：

```
1. 手動產生 CSR（Certificate Signing Request）
   $ openssl req -new -key server.key -out server.csr

2. 把 CSR 寄給 CA 管理員（或上傳到商業 CA）

3. 等待審核，取得 certificate

4. 把 certificate 複製到伺服器，設定服務

5. 在日曆上標記「certificate 將於 2027-02-01 過期」

6. 一年後忘記這件事，服務因 certificate 過期而中斷
```

這個流程的問題：

| 問題 | 後果 |
|---|---|
| Certificate 散落在各台伺服器 | 難以追蹤哪些 certificate 快過期 |
| 手動更新 | 容易忘記，導致服務中斷 |
| 沒有統一的 CA | 每個服務可能用不同的 CA，管理混亂 |
| Private key 管理不一致 | 有些用檔案、有些用 HSM、有些權限設錯 |

FreeIPA 透過內建的 CA（Dogtag）和自動更新機制（certmonger）解決這些問題。

## FreeIPA PKI 架構概覽

### 核心元件

FreeIPA 的 PKI（Public Key Infrastructure）由以下元件組成：

```
┌───────────────────────────────────────────────────────────────────┐
│                        FreeIPA Server                             │
├───────────────────────────────────────────────────────────────────┤
│  ┌─────────────────────────────────────────────────────────────┐  │
│  │                       Dogtag CA                             │  │
│  │  ┌───────────────┐  ┌─────────────┐  ┌─────────────┐       │  │
│  │  │ CA Signing    │  │   Profile   │  │    ACME     │       │  │
│  │  │  (簽發引擎)   │  │   (範本)    │  │   Server    │       │  │
│  │  └───────────────┘  └─────────────┘  └─────────────┘       │  │
│  └─────────────────────────────────────────────────────────────┘  │
│                              │                                    │
│                              ▼                                    │
│  ┌─────────────────────────────────────────────────────────────┐  │
│  │                     IPA Framework                           │  │
│  │    ipa cert-request    ipa-getcert    ACME Protocol         │  │
│  └─────────────────────────────────────────────────────────────┘  │
└───────────────────────────────────────────────────────────────────┘
                               │
                               ▼
┌───────────────────────────────────────────────────────────────────┐
│                        FreeIPA Client                             │
├───────────────────────────────────────────────────────────────────┤
│  ┌───────────────┐  ┌─────────────────┐  ┌─────────────────┐     │
│  │  certmonger   │  │   /etc/ipa/     │  │   certbot/      │     │
│  │ (自動更新)    │  │   ca.crt        │  │   acme.sh       │     │
│  └───────────────┘  └─────────────────┘  └─────────────────┘     │
└───────────────────────────────────────────────────────────────────┘
```

**Dogtag CA** 是 FreeIPA 內建的 Certificate Authority，負責：
- 簽發 certificate（主機、服務、使用者）
- 管理 certificate 生命週期（發行、撤銷、更新）
- 提供 ACME 服務（FreeIPA 4.7+）

**certmonger** 是 Client 端的 certificate 管理 daemon，負責：
- 追蹤已安裝的 certificate
- 在 certificate 過期前自動更新
- 執行更新後的動作（如重啟服務）

### 三種 Certificate 申請方式

FreeIPA 提供三種方式申請 certificate，適用不同場景：

| 方式 | 命令/工具 | 適用場景 | 自動更新 |
|---|---|---|---|
| ipa-getcert | `ipa-getcert request` | FreeIPA Client 主機上的服務 | ✅ certmonger |
| ipa cert-request | `ipa cert-request` | 手動申請、非 Client 主機、特殊需求 | ❌ 手動 |
| ACME | `certbot`、`acme.sh` | 容器環境、標準化工具、跨平台 | ✅ certbot 內建 |

選擇建議：
- **首選 ipa-getcert**：如果服務運行在 FreeIPA Client 上，這是最簡單的方式
- **使用 ACME**：如果你偏好標準化工具，或服務運行在容器中
- **使用 ipa cert-request**：需要細緻控制、或無法安裝 certmonger 時

### 思考題

<details>
<summary>Q1：為什麼 FreeIPA 內建 CA，而不是只整合外部 CA？</summary>

**內建 CA 大幅簡化了部署和管理。**

如果只支援外部 CA：
- 管理員需要另外架設或購買 CA 服務
- 每次申請 certificate 都要和外部系統互動
- certificate 更新流程更複雜
- 無法做到「加入網域就自動取得 certificate」

內建 Dogtag CA 的好處：
- 安裝 FreeIPA 時自動建立完整的 PKI
- Client 加入網域時自動取得主機 certificate
- certmonger 可以直接和本地 CA 溝通更新 certificate
- 所有certificate 集中管理，容易追蹤和稽核

當然，FreeIPA 也支援使用外部 CA 簽發的certificate（例如企業已有的 Root CA），這在需要和現有 PKI 整合時很有用。

</details>

<details>
<summary>Q2：Profile（certificate 範本）是做什麼的？</summary>

**Profile 定義了certificate 的屬性和用途。**

不同類型的certificate 有不同的需求：

| certificate 類型 | Key Usage | Extended Key Usage | 有效期 |
|---|---|---|---|
| CA certificate | keyCertSign, cRLSign | - | 10-20 年 |
| Server certificate | digitalSignature, keyEncipherment | TLS Web Server | 1-2 年 |
| Client certificate | digitalSignature | TLS Web Client | 1 年 |
| Code Signing | digitalSignature | Code Signing | 1-3 年 |

Profile 就是這些設定的範本。FreeIPA 內建幾個常用的 Profile：

- `caIPAserviceCert`：服務 certificate（HTTP、LDAP 等）
- `IECUserRoles`：使用者 certificate
- `KDCs_PKINIT_Certs`：Kerberos PKINIT 用

使用正確的 Profile 確保certificate 有適當的屬性。例如，如果用 CA Profile 簽發一般服務 certificate，那個certificate 可能被誤用來簽發其他certificate。

</details>

## 主機 Certificate（Client Certificate）

當你執行 `ipa-client-install` 加入 FreeIPA 網域時，Client 會自動取得：

1. **CA certificate**：`/etc/ipa/ca.crt`——用來驗證 FreeIPA 簽發的所有certificate
2. **主機 Client certificate**：存在 NSS 資料庫 `/etc/pki/nssdb/` 或 `/etc/ipa/nssdb/`

:::note
**這是 Client Certificate，不是 Server Certificate**

主機 certificate 是用於「主機作為 Client」向其他服務證明身份的certificate。例如：
- SSSD 連接 LDAPS 時，使用這個certificate 進行 mutual TLS（雙向認證）
- certmonger 向 IPA CA 請求新 certificate時

這和「服務 certificate」（如 HTTP Server certificate）不同——服務 certificate 是讓 Server 向 Client 證明身份。
:::

### 查看主機 Certificate

```bash
# 列出 certmonger 追蹤的所有certificate
sudo getcert list
```

輸出範例：

```
Number of certificates and calculation requests being tracked: 2.
Request ID 'ipa-host':
    status: MONITORING
    stuck: no
    key pair storage: type=FILE,location='/etc/pki/tls/private/host.key'
    certificate: type=FILE,location='/etc/pki/tls/certs/host.crt'
    CA: IPA
    issuer: CN=Certificate Authority,O=LAB.EXAMPLE.COM
    subject: CN=client.lab.example.com,O=LAB.EXAMPLE.COM
    expires: 2028-02-01 10:00:00 UTC
    principal name: host/client.lab.example.com@LAB.EXAMPLE.COM
    ...
```

重要欄位說明：

| 欄位 | 說明 |
|---|---|
| status | `MONITORING` 表示正常追蹤中，會自動更新 |
| expires | certificate 過期時間，certmonger 會在過期前自動更新 |
| principal name | 對應的 Kerberos Principal |
| CA | 使用的 CA（IPA 表示 FreeIPA 內建 CA） |

### CA Certificate 信任

Client 安裝時會自動將 FreeIPA CA 加入系統信任儲存區：

```bash
# 查看系統信任的 CA
trust list | grep -A2 "IPA CA"

# 或直接查看 CA certificate
openssl x509 -in /etc/ipa/ca.crt -text -noout | head -20
```

這讓所有使用系統 CA 儲存區的應用程式（如 curl、Python requests）都能自動信任 FreeIPA 簽發的certificate。

### 思考題

<details>
<summary>Q1：主機 certificate 和服務 certificate有什麼不同？</summary>

**主機 certificate 是 Client Certificate，服務 certificate 是 Server Certificate。**

| | 主機 certificate（Client Cert） | 服務 certificate（Server Cert） |
|---|---|---|
| 類型 | Client Certificate | Server Certificate |
| Principal | `host/client.example.com@REALM` | `HTTP/www.example.com@REALM` |
| 用途 | 主機作為 Client 向服務證明身份 | 服務作為 Server 向 Client 證明身份 |
| 使用場景 | SSSD 連接 LDAPS（mutual TLS） | HTTPS、LDAPS Server 端 |
| 自動取得 | ipa-client-install 時自動 | 需要手動申請 |

**實際運作差異**：

1. **主機 certificate**：當 SSSD 連接 FreeIPA 的 LDAPS 時，FreeIPA Server 要求 Client 也出示certificate（mutual TLS）。主機 certificate 讓 SSSD 可以向 Server 證明「我是 client.example.com 這台機器」。

2. **服務 certificate**：當使用者瀏覽器連接到 `https://www.example.com` 時，Web Server 用服務 certificate 向瀏覽器證明「我是 www.example.com」。

為什麼要分開？

1. **不同的信任方向**：主機 certificate 是「我向你證明身份」，服務 certificate 是「我讓別人驗證我」
2. **最小權限原則**：Apache 只需要 HTTP 服務的 Server certificate，不需要主機層級的 Client certificate
3. **獨立生命週期**：服務 certificate 可以獨立更新、撤銷，不影響主機

</details>

<details>
<summary>Q2：如果 CA certificate 過期會發生什麼事？</summary>

**所有由該 CA 簽發的certificate 都會變成不可信任。**

CA certificate 過期的影響：
- 所有 TLS 連線驗證失敗
- LDAPS 連線失敗 → SSSD 無法運作 → 使用者無法登入
- Web UI 顯示certificate 錯誤
- 服務之間的 TLS 通訊中斷

FreeIPA CA certificate 的預設有效期是 20 年，但仍需要注意：
- 定期檢查 CA certificate 有效期
- 規劃 CA certificate 更新流程（這是複雜的操作，需要更新所有 Client）

```bash
# 檢查 CA certificate 有效期
openssl x509 -in /etc/ipa/ca.crt -noout -dates
```

</details>

## 服務 Certificate：ipa-getcert 方式

這是在 FreeIPA Client 上申請服務 certificate最推薦的方式。

### 場景：為 Apache 申請 TLS Certificate

假設我們要在 `client.lab.example.com` 上設定 Apache HTTPS。

**步驟 1：建立服務 Principal**

服務 certificate 需要對應的 Kerberos Principal：

```bash
# 需要 admin 權限
kinit admin

# 建立 HTTP 服務
ipa service-add HTTP/client.lab.example.com
```

**步驟 2：申請 certificate**

使用 `ipa-getcert` 申請 certificate，certmonger 會自動處理 CSR 產生、送出、取得 certificate：

```bash
sudo ipa-getcert request \
    -K HTTP/client.lab.example.com \
    -k /etc/pki/tls/private/httpd.key \
    -f /etc/pki/tls/certs/httpd.crt \
    -D client.lab.example.com \
    -C "systemctl reload httpd"
```

參數說明：

| 參數 | 說明 |
|---|---|
| `-K` | Kerberos Principal |
| `-k` | private key儲存位置 |
| `-f` | certificate儲存位置 |
| `-D` | Subject Alternative Name（SAN），可以多次指定 |
| `-C` | certificate 更新後執行的命令 |

**步驟 3：確認certificate狀態**

```bash
sudo getcert list -f /etc/pki/tls/certs/httpd.crt
```

```
Request ID 'ipa-http':
    status: MONITORING
    stuck: no
    key pair storage: type=FILE,location='/etc/pki/tls/private/httpd.key'
    certificate: type=FILE,location='/etc/pki/tls/certs/httpd.crt'
    CA: IPA
    issuer: CN=Certificate Authority,O=LAB.EXAMPLE.COM
    subject: CN=client.lab.example.com,O=LAB.EXAMPLE.COM
    dns: client.lab.example.com
    expires: 2028-02-01 12:34:56 UTC
    pre-save command:
    post-save command: systemctl reload httpd
    ...
```

**步驟 4：設定 Apache**

```apache
# /etc/httpd/conf.d/ssl.conf
<VirtualHost *:443>
    ServerName client.lab.example.com

    SSLEngine on
    SSLCertificateFile /etc/pki/tls/certs/httpd.crt
    SSLCertificateKeyFile /etc/pki/tls/private/httpd.key
    SSLCertificateChainFile /etc/ipa/ca.crt

    # ... 其他設定
</VirtualHost>
```

```bash
sudo systemctl restart httpd
```

### 多個 SAN（Subject Alternative Name）

如果服務需要多個 hostname：

```bash
sudo ipa-getcert request \
    -K HTTP/client.lab.example.com \
    -k /etc/pki/tls/private/httpd.key \
    -f /etc/pki/tls/certs/httpd.crt \
    -D client.lab.example.com \
    -D www.lab.example.com \
    -D api.lab.example.com \
    -C "systemctl reload httpd"
```

:::note
**SAN 權限限制**

預設情況下，只能申請和主機 Principal 相關的 SAN。如果需要申請其他 hostname，需要：
1. 在 FreeIPA 中建立對應的 Host 或 DNS 記錄
2. 或者使用有更高權限的帳號
:::

### 思考題

<details>
<summary>Q1：為什麼要指定 `-C "systemctl reload httpd"`？</summary>

**因為大多數服務只在啟動時讀取certificate，更新 certificate後需要重新載入。**

certmonger 自動更新 certificate 的流程：

```
1. certmonger 發現certificate 快過期（預設在過期前 28 天）
2. 向 CA 請求新 certificate
3. 收到新 certificate，寫入指定的檔案位置
4. 執行 post-save command（-C 指定的命令）
```

如果沒有 `-C` 參數：
- 檔案中的certificate 是新的
- 但 Apache 記憶體中還是舊的
- 直到下次重啟 Apache，才會使用新 certificate

`systemctl reload httpd` 讓 Apache 重新讀取設定和certificate，而不需要完全重啟。

</details>

<details>
<summary>Q2：ipa-getcert 和 ipa cert-request 有什麼不同？</summary>

**ipa-getcert 整合 certmonger 自動管理，ipa cert-request 是單次操作。**

| | ipa-getcert | ipa cert-request |
|---|---|---|
| 背後機制 | 透過 certmonger daemon | 直接呼叫 IPA API |
| 自動更新 | ✅ certmonger 追蹤 | ❌ 手動更新 |
| private key 產生 | certmonger 自動產生 | 需要先手動產生 CSR |
| 適用場景 | FreeIPA Client 上的服務 | 非 Client 主機、特殊需求 |

**使用 ipa cert-request 的流程**：

```bash
# 1. 手動產生private key 和 CSR
openssl req -new -newkey rsa:2048 -nodes \
    -keyout server.key -out server.csr \
    -subj "/CN=server.example.com"

# 2. 送出 CSR 請求certificate
ipa cert-request server.csr \
    --principal HTTP/server.example.com

# 3. 手動追蹤過期時間，手動更新
```

除非有特殊需求，否則建議使用 ipa-getcert。

</details>

<details>
<summary>Q3：如果申請 certificate時出現 "Insufficient access" 錯誤怎麼辦？</summary>

**這通常是權限問題——執行命令的主機或使用者沒有權限為該服務申請 certificate。**

常見情況和解法：

1. **沒有建立服務 Principal**
   ```bash
   # 先建立服務
   ipa service-add HTTP/server.example.com
   ```

2. **在錯誤的主機上執行**
   預設情況下，只能在服務的「管理主機」上申請 certificate。如果 HTTP/server.example.com 的管理主機是 server.example.com，你就需要在那台機器上執行 ipa-getcert。

3. **需要額外授權**
   ```bash
   # 允許 client.example.com 管理該服務
   ipa service-add-host HTTP/server.example.com \
       --hosts=client.example.com
   ```

4. **使用管理員身份**
   ```bash
   kinit admin
   sudo ipa-getcert request ...
   ```

</details>

## 服務 Certificate：ACME 方式

ACME（Automatic Certificate Management Environment）是標準化的certificate 自動管理協議，最初由 Let's Encrypt 推廣。FreeIPA 4.7+ 內建 ACME 服務，讓你可以使用 certbot 等標準工具申請 certificate。

### 啟用 FreeIPA ACME 服務

ACME 服務預設是停用的，需要手動啟用：

```bash
# 在 IPA Server 上執行
ipa-acme-manage enable

# 確認狀態
ipa-acme-manage status
```

輸出：

```
ACME is enabled
```

ACME 服務會在 `https://ipa.lab.example.com/acme/` 提供標準的 ACME API。

### 使用 certbot 申請 certificate

**步驟 1：安裝 certbot**

```bash
sudo dnf install certbot
```

**步驟 2：申請 certificate（HTTP-01 Challenge）**

HTTP-01 challenge 是最常見的驗證方式，ACME Server 會嘗試存取 `http://你的網域/.well-known/acme-challenge/` 來驗證你擁有該網域：

```bash
sudo certbot certonly \
    --server https://ipa.lab.example.com/acme/directory \
    --standalone \
    -d client.lab.example.com
```

:::note
**HTTP-01 Challenge 需要開放 Port 80**

certbot 的 `--standalone` 模式會在 port 80 啟動臨時 HTTP Server 來回應 challenge。確保：
- Port 80 沒有被其他服務佔用
- 防火牆允許 IPA Server 連入 port 80
:::

**步驟 3：設定自動更新**

certbot 安裝時會自動建立 systemd timer 進行自動更新：

```bash
# 確認 timer 狀態
sudo systemctl status certbot-renew.timer

# 測試更新（dry-run）
sudo certbot renew --dry-run
```

### DNS-01 Challenge

如果無法開放 port 80（例如內部服務），可以使用 DNS-01 challenge：

```bash
sudo certbot certonly \
    --server https://ipa.lab.example.com/acme/directory \
    --manual \
    --preferred-challenges dns \
    -d internal.lab.example.com
```

certbot 會提示你新增一筆 TXT 記錄來證明你擁有該網域。由於 FreeIPA 整合了 DNS，你可以直接用 ipa 命令新增：

```bash
# certbot 會顯示類似這樣的提示：
# Please deploy a DNS TXT record under the name:
# _acme-challenge.internal.lab.example.com
# with the following value:
# gfj9Xq...Rg85nM

# 新增 TXT 記錄
ipa dnsrecord-add lab.example.com _acme-challenge.internal \
    --txt-rec="gfj9Xq...Rg85nM"

# 驗證完成後可以刪除
ipa dnsrecord-del lab.example.com _acme-challenge.internal \
    --txt-rec="gfj9Xq...Rg85nM"
```

### ACME vs ipa-getcert：如何選擇？

| 考量 | ipa-getcert | ACME |
|---|---|---|
| 前提條件 | 必須是 FreeIPA Client | 只需要網路可達 ACME Server |
| 工具相容性 | FreeIPA 專屬 | 標準協議，任何 ACME Client 都可用 |
| 容器環境 | 需要掛載 keytab/設定 SSSD | 只需 certbot |
| Kerberos 整合 | 使用主機 keytab 認證 | 使用 HTTP/DNS challenge |
| certificate追蹤 | certmonger 集中管理 | certbot 獨立管理 |

**選擇建議**：

- **用 ipa-getcert**：服務運行在 FreeIPA Client 上，想要集中追蹤所有certificate
- **用 ACME**：
  - 服務運行在容器中
  - 團隊已經熟悉 certbot
  - 需要和非 FreeIPA 環境保持一致的流程
  - 服務主機無法加入 FreeIPA 網域

### 思考題

<details>
<summary>Q1：為什麼 FreeIPA 需要支援 ACME？ipa-getcert 不夠用嗎？</summary>

**ACME 提供標準化和更好的跨平台支援。**

ipa-getcert 的限制：
- 只能在 FreeIPA Client 上使用
- 依賴 certmonger daemon
- 需要主機加入 FreeIPA 網域（需要 Kerberos keytab）

這在以下場景會有問題：

1. **容器環境**
   容器通常是短暫的，不適合「加入網域」。ACME 只需要 HTTP 存取就能申請 certificate。

2. **混合環境**
   如果組織同時使用 FreeIPA 和 Let's Encrypt，管理員需要學習兩套工具。支援 ACME 後，可以統一使用 certbot。

3. **非 Linux 系統**
   certmonger 主要在 Linux 上運行。其他 OS 可以使用任何支援 ACME 的 Client。

</details>

<details>
<summary>Q2：HTTP-01 和 DNS-01 challenge 各有什麼優缺點？</summary>

**HTTP-01**

優點：
- 設定簡單，certbot --standalone 就能完成
- 不需要 DNS 管理權限

缺點：
- 需要開放 port 80
- ACME Server 必須能夠連入你的主機
- 無法申請 wildcard certificate

**DNS-01**

優點：
- 不需要開放任何 port
- 可以申請 wildcard certificate（`*.example.com`）
- 適合內部服務（ACME Server 不需要能連入你的主機）

缺點：
- 需要 DNS 管理權限
- 手動操作較繁瑣（除非有 DNS API 整合）
- DNS 傳播需要時間

**選擇建議**：
- 公開服務、有固定 IP → HTTP-01
- 內部服務、需要 wildcard → DNS-01

</details>

## certmonger 深入解析

certmonger 是 FreeIPA Client 端certificate 管理的核心。理解它的運作機制有助於排解問題。

### 運作原理

```
┌─────────────────────────────────────────────────────────────────────┐
│                         certmonger daemon                           │
├─────────────────────────────────────────────────────────────────────┤
│  ┌────────────────┐                                                 │
│  │  追蹤資料庫    │  /var/lib/certmonger/requests/                  │
│  │   (tracking)   │  - 每個 certificate 一個檔案                    │
│  └───────┬────────┘  - 記錄狀態、過期時間、CA 資訊                  │
│          │                                                          │
│          ▼                                                          │
│  ┌────────────────┐                                                 │
│  │    排程器      │  定期檢查每個 certificate                       │
│  │  (scheduler)   │  - 是否快過期？（預設 28 天前開始嘗試）         │
│  └───────┬────────┘  - 上次更新是否失敗？需要重試？                 │
│          │                                                          │
│          ▼                                                          │
│  ┌───────────────┐    ┌───────────────┐    ┌───────────────┐       │
│  │    IPA CA     │    │   自簽 CA     │    │   外部 CA     │       │
│  │   Handler     │    │   Handler     │    │   Handler     │       │
│  └───────────────┘    └───────────────┘    └───────────────┘       │
└─────────────────────────────────────────────────────────────────────┘
```

### getcert 命令詳解

**列出所有追蹤的certificate**

```bash
sudo getcert list
```

**列出特定certificate 的詳細資訊**

```bash
sudo getcert list -f /path/to/cert.crt
```

**重要狀態說明**

| 狀態 | 說明 | 處理方式 |
|---|---|---|
| MONITORING | 正常追蹤中 | 無需處理 |
| SUBMITTING | 正在向 CA 請求 | 等待完成 |
| POST_SAVED_CERT | 正在執行 post-save 命令 | 等待完成 |
| NEED_GUIDANCE | 需要人工介入 | 查看錯誤訊息 |
| CA_UNREACHABLE | 無法連線 CA | 檢查網路/CA 服務 |
| CA_REJECTED | CA 拒絕請求 | 檢查權限/Principal |

**手動觸發更新**

```bash
# 立即嘗試更新（不等過期）
sudo getcert resubmit -f /path/to/cert.crt

# 或使用 Request ID
sudo getcert resubmit -i ipa-http
```

**停止追蹤**

```bash
sudo getcert stop-tracking -f /path/to/cert.crt
```

**開始追蹤現有certificate**

```bash
sudo getcert start-tracking \
    -f /path/to/cert.crt \
    -k /path/to/key.pem \
    -I request-id \
    -C "systemctl reload myservice"
```

### 更新失敗的排解

**步驟 1：確認狀態和錯誤訊息**

```bash
sudo getcert list -f /path/to/cert.crt
```

查看 `status` 和 `stuck` 欄位。如果 `stuck: yes`，查看下方的錯誤訊息。

**步驟 2：檢查 certmonger 日誌**

```bash
sudo journalctl -u certmonger -f
```

**步驟 3：常見問題**

| 錯誤訊息 | 原因 | 解法 |
|---|---|---|
| CA_UNREACHABLE | IPA Server 無法連線 | 檢查網路、DNS、IPA 服務狀態 |
| CA_REJECTED | 權限不足 | 確認服務 Principal 存在且有權限 |
| NEED_GUIDANCE | 需要人工決定 | 查看詳細訊息，可能需要重新設定 |
| post-save command failed | 更新後命令執行失敗 | 檢查 -C 指定的命令是否正確 |

**步驟 4：強制重新申請**

如果問題無法解決，可以移除追蹤後重新申請：

```bash
# 停止追蹤
sudo getcert stop-tracking -f /path/to/cert.crt

# 刪除舊檔案
sudo rm /path/to/cert.crt /path/to/key.pem

# 重新申請
sudo ipa-getcert request ...
```

### 思考題

<details>
<summary>Q1：certmonger 如何知道要用哪個身份向 CA 請求certificate？</summary>

**certmonger 使用主機的 Kerberos keytab（`/etc/krb5.keytab`）進行認證。**

流程：
1. certmonger 讀取 `/etc/krb5.keytab`
2. 使用主機 Principal（`host/client.example.com@REALM`）取得 TGT
3. 向 IPA CA 發送certificate 請求，附帶 Kerberos 認證

這就是為什麼 ipa-getcert 只能在 FreeIPA Client 上使用——它依賴主機 keytab。

如果你需要代替其他主機申請 certificate，需要：
1. 有該主機的管理權限
2. 或使用 admin 身份
3. 或使用 ipa cert-request 手動申請

</details>

<details>
<summary>Q2：如果 certmonger daemon 停止了，certificate 會過期嗎？</summary>

**會的。certmonger 必須運行才能自動更新 certificate。**

確保 certmonger 持續運行：

```bash
# 檢查狀態
sudo systemctl status certmonger

# 設定開機自動啟動
sudo systemctl enable certmonger

# 啟動服務
sudo systemctl start certmonger
```

監控建議：
- 監控 certmonger 服務狀態
- 監控 `getcert list` 輸出，檢查是否有 stuck 或異常狀態
- 設定告警在certificate 過期前 N 天通知

</details>

## 實務操作：完整範例

### 範例 A：Nginx + ipa-getcert

在 FreeIPA Client 上設定 Nginx HTTPS。

**1. 安裝 Nginx**

```bash
sudo dnf install nginx
```

**2. 建立服務 Principal**

```bash
kinit admin
ipa service-add HTTP/client.lab.example.com
```

**3. 申請 certificate**

```bash
sudo ipa-getcert request \
    -K HTTP/client.lab.example.com \
    -k /etc/pki/tls/private/nginx.key \
    -f /etc/pki/tls/certs/nginx.crt \
    -D client.lab.example.com \
    -C "systemctl reload nginx"
```

**4. 設定 Nginx**

```nginx
# /etc/nginx/conf.d/ssl.conf
server {
    listen 443 ssl http2;
    server_name client.lab.example.com;

    ssl_certificate /etc/pki/tls/certs/nginx.crt;
    ssl_certificate_key /etc/pki/tls/private/nginx.key;
    ssl_trusted_certificate /etc/ipa/ca.crt;

    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256;
    ssl_prefer_server_ciphers off;

    location / {
        root /usr/share/nginx/html;
    }
}
```

**5. 啟動服務**

```bash
sudo systemctl enable --now nginx
```

**6. 驗證**

```bash
# 測試 TLS 連線
curl -v https://client.lab.example.com/

# 查看certificate 資訊
openssl s_client -connect client.lab.example.com:443 < /dev/null 2>/dev/null | \
    openssl x509 -noout -subject -issuer -dates
```

### 範例 B：容器服務 + ACME

在不屬於 FreeIPA 網域的 Docker 主機上，為容器化服務申請 certificate。

**1. 確認 ACME 服務已啟用**

```bash
# 在 IPA Server 上
ipa-acme-manage status
```

**2. 使用 certbot 申請 certificate**

```bash
# 在 Docker 主機上
sudo certbot certonly \
    --server https://ipa.lab.example.com/acme/directory \
    --standalone \
    -d container-host.lab.example.com
```

certificate 會存放在 `/etc/letsencrypt/live/container-host.lab.example.com/`。

**3. 掛載到容器**

```yaml
# docker-compose.yml
version: '3'
services:
  web:
    image: nginx
    ports:
      - "443:443"
    volumes:
      - /etc/letsencrypt/live/container-host.lab.example.com/fullchain.pem:/etc/nginx/ssl/cert.pem:ro
      - /etc/letsencrypt/live/container-host.lab.example.com/privkey.pem:/etc/nginx/ssl/key.pem:ro
      - ./nginx.conf:/etc/nginx/nginx.conf:ro
```

**4. 設定自動更新**

certbot 的 systemd timer 會自動更新 certificate。更新後需要重新載入容器：

```bash
# /etc/letsencrypt/renewal-hooks/deploy/reload-container.sh
#!/bin/bash
docker compose -f /path/to/docker-compose.yml restart web
```

```bash
chmod +x /etc/letsencrypt/renewal-hooks/deploy/reload-container.sh
```

## 疑難排解

### 問題 1：certificate 申請失敗 "CA_REJECTED"

```bash
sudo getcert list -f /path/to/cert.crt
# status: CA_REJECTED
```

**可能原因**：
- 服務 Principal 不存在
- 主機沒有權限為該服務申請 certificate
- Principal 名稱和 SAN 不匹配

**解法**：

```bash
# 確認服務存在
ipa service-show HTTP/server.example.com

# 如果不存在，建立它
ipa service-add HTTP/server.example.com

# 確認主機有管理權限
ipa service-show HTTP/server.example.com | grep "Managed by"

# 如果需要，加入管理主機
ipa service-add-host HTTP/server.example.com --hosts=$(hostname -f)
```

### 問題 2：certificate 更新失敗 "CA_UNREACHABLE"

```bash
sudo getcert list
# status: CA_UNREACHABLE
```

**可能原因**：
- IPA Server 無法連線
- DNS 解析失敗
- Kerberos 認證問題

**解法**：

```bash
# 測試 IPA Server 連線
ping ipa.lab.example.com
curl -k https://ipa.lab.example.com/ipa/json

# 測試 Kerberos
kinit -k -t /etc/krb5.keytab host/$(hostname -f)
klist

# 檢查 IPA 服務狀態（在 Server 上）
sudo ipactl status
```

### 問題 3：ACME challenge 失敗

```
Challenge failed for domain example.com
```

**HTTP-01 失敗原因**：
- Port 80 被佔用
- 防火牆阻擋
- IPA Server 無法連入主機

**解法**：

```bash
# 確認 port 80 可用
sudo ss -tlnp | grep :80

# 暫時開放防火牆
sudo firewall-cmd --add-port=80/tcp

# 測試從 IPA Server 能否存取
# 在 IPA Server 上執行
curl http://client.lab.example.com/
```

### 問題 4：certificate chain不完整

瀏覽器顯示「certificate 不受信任」，但certificate 本身沒過期。

**原因**：服務只回傳了終端certificate，沒有包含 CA certificate。

**解法**：

```bash
# 確認有設定 CA certificate
# Apache
SSLCertificateChainFile /etc/ipa/ca.crt

# Nginx
ssl_trusted_certificate /etc/ipa/ca.crt;
```

## 總結

在這篇文章中，我們學習了：

1. **FreeIPA PKI 架構**
   - Dogtag CA 作為內建的certificate 授權中心
   - 三種certificate 申請方式：ipa-getcert、ipa cert-request、ACME

2. **主機 certificate**
   - Client 安裝時自動取得
   - CA certificate 自動加入系統信任

3. **服務 certificate 管理**
   - 使用 ipa-getcert 申請和自動更新
   - 設定 post-save 命令確保服務重新載入

4. **ACME 服務**
   - 啟用 FreeIPA ACME
   - 使用 certbot 申請 certificate
   - HTTP-01 vs DNS-01 challenge

5. **certmonger 運作機制**
   - 追蹤、排程、自動更新
   - 狀態監控和問題排解

6. **實務範例**
   - Nginx + ipa-getcert
   - 容器服務 + ACME

## Reference

- [FreeIPA Certificate Management](https://freeipa.readthedocs.io/en/latest/designs/certificate-management.html)
- [certmonger Documentation](https://www.freeipa.org/page/Certmonger)
- [FreeIPA ACME](https://freeipa.readthedocs.io/en/latest/designs/acme.html)
- [RFC 8555 - ACME Protocol](https://datatracker.ietf.org/doc/html/rfc8555)
