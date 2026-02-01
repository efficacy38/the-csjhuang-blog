---
title: FreeIPA 實戰：部署企業級 Kerberos 環境
description: 使用 FreeIPA 建立完整的 Kerberos + LDAP 認證環境，從架構理解到實際操作
date: 2026-02-01
slug: freeipa-kerberos-deployment
series: "freeipa"
tags:
    - "kerberos"
    - "freeipa"
    - "authentication"
    - "note"
---

在上一篇文章中，我們理解了 Kerberos 的協議細節與設計原則。這篇文章要進入實戰環節：使用 FreeIPA 建立一個完整的企業級認證環境。

## 為什麼選擇 FreeIPA？

在開始部署之前，先理解 FreeIPA 解決了什麼問題。

**單獨部署 Kerberos 的挑戰**

如果你嘗試只安裝 MIT Kerberos 或 Heimdal，會遇到這些問題：

```
1. 只有認證，沒有使用者資訊
   → Kerberos 只能回答「這個人是 alice」
   → 無法回答「alice 的 email 是什麼」「alice 屬於哪個部門」

2. 手動管理 Principal
   → 新增使用者要分別在 Kerberos 和 LDAP 各操作一次
   → 密碼要分開維護

3. 沒有 DNS 整合
   → 服務發現需要手動設定
   → 跨 Realm 信任設定複雜

4. 沒有憑證管理
   → LDAP over TLS 需要另外設定 CA
   → 服務憑證要手動申請
```

**FreeIPA 的解決方案**

FreeIPA 將多個元件整合成一個統一的身份管理平台：

| 元件 | FreeIPA 中的角色 | 解決的問題 |
|---|---|---|
| MIT Kerberos | KDC | 認證 |
| 389 Directory Server | LDAP | 使用者/群組/政策儲存 |
| Dogtag | CA | 憑證簽發 |
| BIND | DNS | 服務發現、SRV 記錄 |
| SSSD | Client Agent | 本機快取、離線認證 |

這些元件透過 FreeIPA 的 Web UI 和 CLI 統一管理，使用者只需操作一次就能完成所有設定。

## FreeIPA 架構總覽

在深入操作之前，先建立 FreeIPA 架構的完整圖像。

### 元件關係圖

```
┌───────────────────────────────────────────────────────────────────┐
│                        FreeIPA Server                             │
├───────────────────────────────────────────────────────────────────┤
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌──────────┐ │
│  │  Kerberos   │  │    LDAP     │  │     CA      │  │   DNS    │ │
│  │   (KDC)     │  │  (389 DS)   │  │  (Dogtag)   │  │  (BIND)  │ │
│  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘  └─────┬────┘ │
│         │                │                │               │      │
│         └────────────────┼────────────────┼───────────────┘      │
│                          │                │                      │
│                   ┌──────▼──────┐  ┌──────▼──────┐               │
│                   │  IPA API    │  │  IPA API    │               │
│                   │  (LDAP)     │  │  (HTTP)     │               │
│                   └──────┬──────┘  └──────┬──────┘               │
│                          │                │                      │
│                   ┌──────▼────────────────▼──────┐               │
│                   │        Web UI / CLI          │               │
│                   └──────────────────────────────┘               │
└───────────────────────────────────────────────────────────────────┘
                                   │
                                   │ (Kerberos / LDAP / HTTPS)
                                   ▼
┌───────────────────────────────────────────────────────────────────┐
│                        FreeIPA Client                             │
├───────────────────────────────────────────────────────────────────┤
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐            │
│  │     SSSD     │  │  certmonger  │  │  /etc/krb5   │            │
│  │ (快取+離線)  │  │  (憑證更新)  │  │    .conf     │            │
│  └──────────────┘  └──────────────┘  └──────────────┘            │
└───────────────────────────────────────────────────────────────────┘
```

### 資料儲存位置

FreeIPA 使用 LDAP（389 Directory Server）作為統一的資料儲存：

| 資料類型 | LDAP 位置 | 說明 |
|---|---|---|
| 使用者 | `cn=users,cn=accounts,dc=...` | 帳號、密碼 hash、屬性 |
| 群組 | `cn=groups,cn=accounts,dc=...` | 群組成員關係 |
| 服務 | `cn=services,cn=accounts,dc=...` | HTTP/host.example.com 等 |
| Kerberos Principal | `cn=kerberos,dc=...` | Principal 對應的密鑰 |
| HBAC 規則 | `cn=hbac,dc=...` | Host-Based Access Control |
| Sudo 規則 | `cn=sudo,dc=...` | Sudo 權限設定 |

這個設計的好處是：當你用 `ipa user-add alice` 新增使用者時，FreeIPA 會：
1. 在 LDAP 建立使用者條目
2. 在 Kerberos 建立對應的 Principal
3. 設定密碼（同時更新 LDAP 和 Kerberos）

你不需要分別操作兩個系統。

### 思考題

<details>
<summary>Q1：為什麼 FreeIPA 選擇把 Kerberos Principal 資訊也存在 LDAP 裡？</summary>

**統一管理與資料一致性。**

傳統 MIT Kerberos 使用自己的資料庫（通常是 Berkeley DB 或 LMDB）。這代表：
- 新增使用者要操作兩個資料庫
- 密碼更新要同步兩邊
- 備份要分別處理

把 Kerberos 資訊存在 LDAP 後：
- 使用者帳號和 Principal 是同一筆資料
- 密碼更新自動同步
- 只需要備份 LDAP

FreeIPA 使用 KDB（Kerberos Database）的 LDAP 後端模式（`kldap`）實現這個整合。

</details>

<details>
<summary>Q2：Client 端的 SSSD 是做什麼的？為什麼不直接用 PAM + Kerberos？</summary>

**SSSD（System Security Services Daemon）提供快取和離線認證。**

如果直接用 PAM + Kerberos：
- 每次登入都要連線到 KDC
- KDC 無法連線時，使用者無法登入
- 沒有本機的使用者資訊快取

SSSD 的功能：
1. **快取使用者資訊**：從 LDAP 拉回來的使用者資料會存在本機
2. **離線認證**：上次成功登入的 credential 會被快取，KDC 斷線時仍可登入
3. **統一介面**：整合 LDAP、Kerberos、sudo 規則等多種資料來源
4. **效能優化**：減少對 Server 的查詢次數

這對筆電使用者特別重要——在沒有網路的環境也能登入系統。

</details>

## 實驗環境準備

本文使用以下環境進行示範：

| 角色 | Hostname | IP | OS |
|---|---|---|---|
| IPA Server | ipa.lab.example.com | 192.168.122.10 | Rocky Linux 9 |
| IPA Client | client.lab.example.com | 192.168.122.20 | Rocky Linux 9 |

### 事前準備

在開始安裝前，需要完成以下設定：

**1. 設定 Hostname**

FreeIPA 對 hostname 有嚴格要求——必須是 FQDN（Fully Qualified Domain Name）：

```bash
# 在 IPA Server 上
sudo hostnamectl set-hostname ipa.lab.example.com

# 在 Client 上
sudo hostnamectl set-hostname client.lab.example.com
```

**2. 設定 /etc/hosts**

在安裝 DNS 之前，需要手動設定 hosts 檔案：

```bash
# 在兩台機器上都要設定
echo "192.168.122.10 ipa.lab.example.com ipa" | sudo tee -a /etc/hosts
```

**3. 開啟防火牆**

FreeIPA Server 需要開放多個 port：

```bash
sudo firewall-cmd --add-service={freeipa-ldap,freeipa-ldaps,dns,ntp} --permanent
sudo firewall-cmd --add-service={http,https,kerberos,kpasswd} --permanent
sudo firewall-cmd --reload
```

| Port | 服務 | 用途 |
|---|---|---|
| 88/tcp, 88/udp | Kerberos | 認證 |
| 464/tcp, 464/udp | kpasswd | 密碼變更 |
| 389/tcp | LDAP | 目錄查詢 |
| 636/tcp | LDAPS | 加密的目錄查詢 |
| 80/tcp, 443/tcp | HTTP/HTTPS | Web UI 和 API |
| 53/tcp, 53/udp | DNS | 名稱解析 |
| 123/udp | NTP | 時間同步（Kerberos 必需） |

## 安裝 FreeIPA Server

### 安裝套件

```bash
sudo dnf install -y freeipa-server freeipa-server-dns
```

這會安裝 FreeIPA Server 以及整合的 DNS 伺服器。

### 執行安裝程式

FreeIPA 提供互動式安裝程式：

```bash
sudo ipa-server-install --setup-dns
```

安裝程式會詢問一系列問題：

```
Server host name [ipa.lab.example.com]: [Enter]

Please confirm the domain name [lab.example.com]: [Enter]

Please provide a realm name [LAB.EXAMPLE.COM]: [Enter]
```

:::note
**Realm 命名慣例**：Kerberos Realm 傳統上使用大寫的 DNS 網域名稱。這不是技術限制，而是慣例——讓管理者能夠一眼區分 Realm（`LAB.EXAMPLE.COM`）和 DNS 網域（`lab.example.com`）。
:::

接下來設定管理員密碼：

```
Directory Manager password: [輸入 LDAP 管理員密碼]
IPA admin password: [輸入 IPA admin 密碼]
```

| 帳號 | 用途 | 使用時機 |
|---|---|---|
| Directory Manager | LDAP 超級管理員 | 底層 LDAP 維護、災難復原 |
| admin | IPA 管理員 | 日常使用者/群組/服務管理 |

DNS 設定：

```
Do you want to configure DNS forwarders? [yes]: yes
Enter an IP address for a DNS forwarder: 8.8.8.8
```

安裝過程會執行：
1. 設定 389 Directory Server（LDAP）
2. 設定 MIT Kerberos KDC
3. 設定 Dogtag CA
4. 設定 BIND DNS
5. 取得並安裝 TLS 憑證
6. 建立 admin 使用者和初始資料

安裝完成後會顯示：

```
==============================================================================
Setup complete

Next steps:
    1. You must make sure these network ports are open:
        TCP Ports: 80, 443, 389, 636, 88, 464
        UDP Ports: 88, 464, 53
    2. You can now obtain a Kerberos ticket using the command: 'kinit admin'
==============================================================================
```

### 驗證安裝

確認各服務狀態：

```bash
# 檢查 IPA 服務狀態
sudo ipactl status
```

預期輸出：

```
Directory Service: RUNNING
krb5kdc Service: RUNNING
kadmin Service: RUNNING
named Service: RUNNING
httpd Service: RUNNING
ipa-custodia Service: RUNNING
pki-tomcatd Service: RUNNING
ipa-otpd Service: RUNNING
ipa-dnskeysyncd Service: RUNNING
ipa: INFO: The ipactl command was successful
```

測試 Kerberos 認證：

```bash
kinit admin
# 輸入 admin 密碼

klist
```

預期輸出：

```
Ticket cache: KCM:0
Default principal: admin@LAB.EXAMPLE.COM

Valid starting       Expires              Service principal
02/01/2026 10:00:00  02/01/2026 20:00:00  krbtgt/LAB.EXAMPLE.COM@LAB.EXAMPLE.COM
```

這表示你已經成功取得 TGT，Kerberos 環境運作正常。

### 思考題

<details>
<summary>Q1：為什麼 FreeIPA 安裝時要設定兩個不同的管理員密碼？</summary>

**權限分離原則。**

- **Directory Manager**（`cn=Directory Manager`）：
  - LDAP 的超級管理員，可以存取所有資料
  - 用於底層維護：schema 修改、replication 設定、災難復原
  - 不受 IPA 的存取控制限制
  - 應該只有 DBA 或系統管理員知道

- **admin**（`uid=admin`）：
  - IPA 的管理員，受 IPA 存取控制限制
  - 用於日常操作：新增使用者、管理群組、設定政策
  - 可以透過 Web UI 和 `ipa` 命令操作
  - 可以給多人使用（透過群組授權）

這種分離讓日常操作有稽核紀錄，而底層維護保留給特定人員。

</details>

<details>
<summary>Q2：Ticket cache 顯示 `KCM:0` 是什麼意思？和傳統的 FILE:/tmp/krb5cc_xxx 有什麼不同？</summary>

**KCM（Kerberos Credential Manager）是 SSSD 提供的集中式 Ticket 快取。**

傳統的 `FILE:/tmp/krb5cc_1000`：
- 每個使用者的 Ticket 存在獨立檔案
- 檔案權限保護（600）
- 問題：檔案被複製就能竊取 Ticket

KCM 的優點：
- Ticket 存在 SSSD 的 daemon 記憶體中
- 透過 Unix Socket 存取，不是檔案
- 支援多個 credential cache（例如同時持有多個 Realm 的 TGT）
- 更好的權限控制

在現代 Linux 發行版（RHEL 8+、Fedora）中，KCM 是預設的 credential cache type。

</details>

## 安裝 FreeIPA Client

在 Client 機器上加入 FreeIPA 網域。

### 設定 DNS

先將 Client 的 DNS 指向 IPA Server：

```bash
# 使用 NetworkManager 設定 DNS
sudo nmcli con mod "System eth0" ipv4.dns "192.168.122.10"
sudo nmcli con up "System eth0"

# 驗證 DNS 解析
dig ipa.lab.example.com
```

### 安裝 Client 套件

```bash
sudo dnf install -y freeipa-client
```

### 執行 Client 安裝

```bash
sudo ipa-client-install --mkhomedir
```

安裝程式會自動發現 IPA Server（透過 DNS SRV 記錄）：

```
Discovery was successful!
Client hostname: client.lab.example.com
Realm: LAB.EXAMPLE.COM
DNS Domain: lab.example.com
IPA Server: ipa.lab.example.com
BaseDN: dc=lab,dc=example,dc=com

Continue to configure the system with these values? [no]: yes
```

輸入有權限加入網域的帳號：

```
User authorized to enroll computers: admin
Password for admin@LAB.EXAMPLE.COM: [輸入密碼]
```

安裝完成後，Client 會：
1. 設定 Kerberos（`/etc/krb5.conf`）
2. 設定 SSSD（`/etc/sssd/sssd.conf`）
3. 設定 PAM（使用 authselect）
4. 取得 Client 的 keytab（`/etc/krb5.keytab`）
5. 設定 certmonger 自動更新憑證

### 驗證 Client 安裝

```bash
# 測試 Kerberos 認證
kinit admin
klist

# 測試 SSSD 使用者查詢
id admin
# uid=686600000(admin) gid=686600000(admins) groups=...

# 測試 SSH 登入（使用 Kerberos 認證）
ssh admin@ipa.lab.example.com
# 應該不需要輸入密碼（使用 TGT）
```

### 思考題

<details>
<summary>Q1：`--mkhomedir` 選項做了什麼？為什麼需要它？</summary>

**`--mkhomedir` 啟用 pam_mkhomedir 模組，在使用者首次登入時自動建立家目錄。**

FreeIPA 使用者定義在中央 LDAP，但家目錄預設存在各個 Client 的本機。當使用者首次登入一台新機器時：

```
1. PAM 驗證使用者身份 → 成功
2. 系統嘗試 chdir 到 /home/alice → 目錄不存在 → 登入失敗
```

加上 `--mkhomedir` 後：

```
1. PAM 驗證使用者身份 → 成功
2. pam_mkhomedir 檢查 /home/alice → 不存在
3. pam_mkhomedir 建立 /home/alice，複製 /etc/skel 內容
4. 系統 chdir 到 /home/alice → 成功
```

如果你使用 NFS 共享家目錄，就不需要這個選項。

</details>

<details>
<summary>Q2：Client 安裝時取得的 `/etc/krb5.keytab` 是做什麼用的？</summary>

**這是 Client 主機的 keytab，用於主機層級的 Kerberos 認證。**

當你安裝 FreeIPA Client 時，系統會：
1. 在 IPA Server 建立一個 host Principal：`host/client.lab.example.com@LAB.EXAMPLE.COM`
2. 產生這個 Principal 的 keytab
3. 將 keytab 安全傳輸到 Client 並存為 `/etc/krb5.keytab`

這個 keytab 的用途：
- **SSH 雙向認證**：SSH Server 需要 keytab 來驗證自己是真正的 `client.lab.example.com`
- **SSSD 認證**：SSSD 使用 keytab 向 LDAP Server 證明自己的身份
- **其他服務**：NFS、CUPS 等服務可以使用主機 keytab

和服務 keytab（如 `HTTP/www.example.com`）的差異在於：
- 主機 keytab 代表整台機器的身份
- 服務 keytab 代表特定服務的身份

</details>

## 使用者與群組管理

FreeIPA 安裝完成後，接下來學習日常的使用者管理操作。

### 建立使用者

使用 `ipa` 命令建立使用者：

```bash
# 確保有有效的 Kerberos ticket
kinit admin

# 建立使用者
ipa user-add alice \
    --first=Alice \
    --last=Chen \
    --email=alice@example.com \
    --password
```

系統會提示輸入初始密碼。使用者首次登入時會被要求更改密碼。

查看使用者資訊：

```bash
ipa user-show alice
```

輸出：

```
  User login: alice
  First name: Alice
  Last name: Chen
  Full name: Alice Chen
  Email address: alice@example.com
  UID: 686600001
  GID: 686600001
  Home directory: /home/alice
  Login shell: /bin/bash
  Principal name: alice@LAB.EXAMPLE.COM
  Principal alias: alice@LAB.EXAMPLE.COM
  Email address: alice@example.com
  Account disabled: False
  Password: True
  Kerberos keys available: True
```

注意 **Principal name** 欄位——這確認了 Kerberos Principal 和 LDAP 使用者是連動的。

### 建立群組

```bash
# 建立群組
ipa group-add developers --desc="Development Team"

# 將使用者加入群組
ipa group-add-member developers --users=alice
```

### 使用者密碼管理

```bash
# 管理員重設使用者密碼
ipa user-mod alice --password

# 使用者自己更改密碼
kpasswd alice
```

### Web UI 操作

FreeIPA 也提供 Web UI，適合不熟悉命令列的管理者：

```
https://ipa.lab.example.com/
```

使用 admin 帳號登入後，可以在圖形介面完成所有操作。

### 思考題

<details>
<summary>Q1：使用者首次登入為什麼要被強制改密碼？這個機制如何實作？</summary>

**這是 Kerberos 的 `password expiration` 機制。**

當管理員用 `--password` 設定初始密碼時，FreeIPA 會：
1. 將密碼過期時間設為「現在」
2. 標記 Principal 需要更改密碼

使用者嘗試登入時：

```
$ kinit alice
Password for alice@LAB.EXAMPLE.COM: [輸入初始密碼]
Password expired. You must change it now.
Enter new password: [輸入新密碼]
Enter it again: [確認新密碼]
```

技術上，這是透過 Kerberos Principal 的 `REQUIRES_PRE_AUTH` 和 `CHANGE_PW` 旗標實現的。

這個設計的安全考量：
- 管理員設定的初始密碼可能透過不安全的管道傳遞（email、電話）
- 強制更改確保只有使用者知道最終密碼
- 符合資安合規要求（如 PCI DSS）

</details>

<details>
<summary>Q2：UID 顯示 686600001 這個很大的數字是怎麼來的？</summary>

**這是 FreeIPA 的 ID Range 機制，用於避免 UID 衝突。**

傳統本機使用者的 UID 通常從 1000 開始。如果 FreeIPA 使用者也從 1000 開始，可能會發生：
- 本機有 UID 1001 的 bob
- FreeIPA 也有 UID 1001 的 alice
- 檔案權限混亂

FreeIPA 預設使用一個很大的 UID 範圍（通常從 686600000 開始），確保不會和本機使用者衝突。

這個範圍在安裝時設定，存在 LDAP 中：

```bash
ipa idrange-find
# 顯示 ID Range 設定
```

如果你需要和 Active Directory 信任，還會有專門給 AD 使用者的 ID Range。

</details>

## 服務 Principal 與 Keytab 管理

上一篇文章解釋過，服務需要 keytab 來驗證 Kerberos Ticket。現在來實際操作。

### 範例情境：設定 HTTP 服務的 Kerberos 認證

假設我們要在 `client.lab.example.com` 上設定 Apache Web Server 使用 Kerberos 認證。

**步驟 1：建立服務 Principal**

```bash
# 在 IPA Server 上（或任何有 admin ticket 的機器）
ipa service-add HTTP/client.lab.example.com
```

這會在 FreeIPA 建立一個服務 Principal：`HTTP/client.lab.example.com@LAB.EXAMPLE.COM`

**步驟 2：產生 Keytab**

在服務主機（client.lab.example.com）上產生 keytab：

```bash
# 需要 admin 權限
kinit admin

# 產生 keytab
ipa-getkeytab \
    -s ipa.lab.example.com \
    -p HTTP/client.lab.example.com \
    -k /etc/httpd/conf.d/http.keytab
```

**步驟 3：設定檔案權限**

```bash
# keytab 只能讓 Apache 程序讀取
sudo chown apache:apache /etc/httpd/conf.d/http.keytab
sudo chmod 600 /etc/httpd/conf.d/http.keytab
```

**步驟 4：設定 Apache**

```apache
# /etc/httpd/conf.d/auth_kerb.conf
LoadModule auth_gssapi_module modules/mod_auth_gssapi.so

<Location "/protected">
    AuthType GSSAPI
    AuthName "Kerberos Login"
    GssapiCredStore keytab:/etc/httpd/conf.d/http.keytab
    Require valid-user
</Location>
```

### Keytab 管理最佳實踐

```bash
# 查看 keytab 內容（不會顯示密鑰）
klist -k /etc/httpd/conf.d/http.keytab
```

輸出：

```
Keytab name: FILE:/etc/httpd/conf.d/http.keytab
KVNO Principal
---- --------------------------------------------------------------------------
   2 HTTP/client.lab.example.com@LAB.EXAMPLE.COM
   2 HTTP/client.lab.example.com@LAB.EXAMPLE.COM
```

**KVNO（Key Version Number）** 是密鑰版本號。每次更換密鑰時會遞增。

### 輪換 Keytab

定期輪換 keytab 是安全最佳實踐：

```bash
# 重新產生 keytab（會產生新的密鑰，KVNO 遞增）
ipa-getkeytab \
    -s ipa.lab.example.com \
    -p HTTP/client.lab.example.com \
    -k /etc/httpd/conf.d/http.keytab

# 重啟服務以載入新 keytab
sudo systemctl restart httpd
```

:::warning
**輪換 keytab 時的注意事項**

1. 已經發放的 Service Ticket 使用舊密鑰加密
2. 新 keytab 只包含新密鑰
3. 在舊 Ticket 過期前，可能有一段時間認證失敗

解決方案：使用 `-r` 選項保留舊密鑰
```bash
ipa-getkeytab -r -s ipa.lab.example.com \
    -p HTTP/client.lab.example.com \
    -k /etc/httpd/conf.d/http.keytab
```
這會在 keytab 中同時保留新舊兩個版本的密鑰。
:::

### Keytab 的有效期限

一個常見的問題是：「keytab 會過期嗎？需要設定有效期限嗎？」

**答案是：keytab 本身沒有過期機制，它預設就是「無限期」的。**

```bash
# 查看 keytab 內容——注意沒有過期時間欄位
klist -k /etc/httpd/conf.d/http.keytab

Keytab name: FILE:/etc/httpd/conf.d/http.keytab
KVNO Principal
---- --------------------------------------------------------------------------
   2 HTTP/client.lab.example.com@LAB.EXAMPLE.COM
```

keytab 失效的唯一情況：

| 情況 | 說明 |
|---|---|
| 有人重新產生 keytab | `ipa-getkeytab` 會產生新密鑰，舊 keytab 的 KVNO 不符 |
| Principal 被刪除 | 服務帳號從 FreeIPA 移除 |
| 密碼政策強制更換 | 通常只影響使用者，不影響服務 Principal |

:::note
**常見誤解**

- **Ticket 會過期**（預設 10 小時），但這是 Ticket，不是 keytab
- **TLS 憑證會過期**，但這是 X.509 憑證，不是 Kerberos keytab
- **FreeIPA 會自動 rotate 憑證**（透過 certmonger），但**不會**自動 rotate keytab

只要沒有人重新執行 `ipa-getkeytab`，keytab 就會一直有效。
:::

如果你的安全政策要求定期輪換 keytab，需要自行設定排程：

```bash
# 範例：cron job 每月自動更新 keytab
0 3 1 * * kinit -k -t /etc/krb5.keytab && \
  ipa-getkeytab -r -s ipa.lab.example.com \
    -p HTTP/$(hostname) \
    -k /etc/httpd/conf.d/http.keytab && \
  systemctl reload httpd
```

### 思考題

<details>
<summary>Q1：為什麼 HTTP 服務的 Principal 是 `HTTP/client.lab.example.com` 而不是 `httpd/client.lab.example.com`？</summary>

**這是 Kerberos 的服務命名慣例，與實際的服務程式名稱無關。**

常見的服務類型前綴：

| 前綴 | 用途 |
|---|---|
| HTTP | 所有 HTTP 服務（Apache、Nginx、Tomcat） |
| host | SSH、主機層級服務 |
| nfs | NFS 服務 |
| ldap | LDAP 服務 |
| smtp | 郵件服務 |
| imap | IMAP 服務 |
| postgres | PostgreSQL |
| mysql | MySQL |

這個慣例讓 Client 端知道如何組合 Service Principal Name（SPN）。當 Chrome 要存取 `https://client.lab.example.com` 時，它會自動嘗試取得 `HTTP/client.lab.example.com@LAB.EXAMPLE.COM` 的 Service Ticket。

如果你用 `httpd/...` 作為 Principal，Client 端會找不到正確的 SPN。

</details>

<details>
<summary>Q2：如果 keytab 檔案被竊取，攻擊者可以做什麼？</summary>

**Keytab 包含服務的長期密鑰，洩漏後攻擊者可以：**

1. **偽裝成該服務**
   - 架設假的 HTTP Server
   - 使用竊取的 keytab 通過 Kerberos 雙向認證
   - 使用者會相信假服務是真的

2. **解密發給該服務的 Ticket**
   - 攔截網路流量中的 AP-REQ
   - 用 keytab 解開 Service Ticket
   - 取得 Session Key，解密後續通訊

3. **無法做到的事**
   - 無法取得使用者的密碼（不在 Ticket 裡）
   - 無法偽裝成使用者（沒有 TGT）
   - 無法存取其他服務（只能解密發給這個服務的 Ticket）

**發現 keytab 洩漏後的處置：**
```bash
# 1. 撤銷舊密鑰，產生新 keytab
ipa-getkeytab -s ipa.lab.example.com \
    -p HTTP/client.lab.example.com \
    -k /etc/httpd/conf.d/http.keytab

# 2. 重啟服務
sudo systemctl restart httpd

# 3. 檢查稽核日誌，確認是否有可疑存取
```

因為 Kerberos 密鑰是隨機產生的，重新產生 keytab 就等於換了一把鎖，舊鑰匙完全失效。

</details>

## Kerberos 操作實務：kinit / klist / kdestroy

最後來熟悉日常使用的 Kerberos 命令。

### kinit：取得 Ticket

```bash
# 基本用法
kinit alice
Password for alice@LAB.EXAMPLE.COM:

# 指定 Ticket 有效期限
kinit -l 4h alice    # 4 小時
kinit -l 1d alice    # 1 天

# 指定 Renewable 期限
kinit -r 7d alice    # 可續期 7 天
```

### klist：查看 Ticket

```bash
klist
```

輸出：

```
Ticket cache: KCM:1000
Default principal: alice@LAB.EXAMPLE.COM

Valid starting       Expires              Service principal
02/01/2026 10:00:00  02/01/2026 20:00:00  krbtgt/LAB.EXAMPLE.COM@LAB.EXAMPLE.COM
02/01/2026 10:05:23  02/01/2026 20:00:00  HTTP/client.lab.example.com@LAB.EXAMPLE.COM
```

這顯示 alice 目前有：
- 一張 TGT（`krbtgt/...`）
- 一張 HTTP 服務的 Service Ticket

```bash
# 顯示更多細節
klist -f
```

輸出會顯示 Ticket 的旗標：

```
Flags: FIA
```

| 旗標 | 意義 |
|---|---|
| F | Forwardable（可轉發） |
| I | Initial（初始取得，不是續期） |
| A | Pre-authenticated |
| R | Renewable（可續期） |

### kdestroy：銷毀 Ticket

```bash
# 銷毀所有 Ticket
kdestroy

# 確認已清除
klist
# klist: Credentials cache 'KCM:1000' not found
```

**什麼時候需要 kdestroy？**

- 離開工作站前（防止 Ticket 被竊取）
- 切換使用者身份時
- 排除認證問題時（取得乾淨的狀態）

### 自動取得 Ticket：GSSAPI 認證

在 FreeIPA 環境中，許多服務會自動使用 Kerberos 認證：

```bash
# SSH 自動使用 TGT（不需輸入密碼）
ssh alice@ipa.lab.example.com

# 檢查 klist，會看到新的 Service Ticket
klist
# 會看到 host/ipa.lab.example.com@LAB.EXAMPLE.COM
```

這就是 SSO（Single Sign-On）的效果——登入一次後，存取其他服務不需要再輸入密碼。

### 思考題

<details>
<summary>Q1：`kinit -r 7d` 的 Renewable 有什麼用？和直接設定 `-l 7d` 有什麼不同？</summary>

**Renewable 允許在不輸入密碼的情況下續期 Ticket，同時保持短期有效的安全性。**

直接設定 `-l 7d`（7 天有效）：
- Ticket 7 天內都有效
- 如果 Ticket 被偷，攻擊者可以用 7 天
- 較不安全

設定 `-l 10h -r 7d`（10 小時有效，7 天可續期）：
- Ticket 10 小時後過期
- 但可以在過期前續期（不需密碼）
- 續期後又有 10 小時效期
- 最多可以續期到第 7 天

```bash
# 續期 Ticket
kinit -R
```

這個設計的好處：
- 每 10 小時 Ticket 就過期，攻擊者可利用的時間窗口短
- 使用者不需要每天輸入密碼
- 系統可以設定自動續期（如 cron job 或 k5start daemon）

</details>

<details>
<summary>Q2：為什麼 SSH 可以自動使用 Kerberos 認證？需要什麼設定？</summary>

**需要 GSSAPI 認證在 SSH Client 和 Server 兩端都啟用。**

**Client 端設定**（`/etc/ssh/ssh_config` 或 `~/.ssh/config`）：
```
Host *
    GSSAPIAuthentication yes
    GSSAPIDelegateCredentials no
```

**Server 端設定**（`/etc/ssh/sshd_config`）：
```
GSSAPIAuthentication yes
GSSAPICleanupCredentials yes
```

認證流程：
1. Client 執行 `ssh alice@server.example.com`
2. SSH Client 檢查是否有 `alice@REALM` 的 TGT
3. SSH Client 向 TGS 請求 `host/server.example.com` 的 Service Ticket
4. SSH Client 在連線時送出 Service Ticket（AP-REQ）
5. SSH Server 用 `/etc/krb5.keytab` 驗證 Ticket
6. 驗證成功，不需密碼即可登入

FreeIPA Client 安裝時會自動設定這些參數。

**注意**：`GSSAPIDelegateCredentials yes` 會將 TGT 轉發到遠端機器，讓你在遠端也能存取其他 Kerberized 服務。但這有安全風險——如果遠端機器被入侵，攻擊者可以使用你的 TGT。只在信任的機器上啟用。

</details>

## 疑難排解

在實務操作中，你可能會遇到各種問題。這裡列出常見問題和排解方法。

### 問題 1：時間不同步

```
kinit: Clock skew too great while getting initial credentials
```

**原因**：Kerberos 預設容忍的時間差是 5 分鐘。超過這個時間，Ticket 會被拒絕。

**解決方案**：

```bash
# 檢查時間差
timedatectl

# 同步時間
sudo chronyc -a makestep

# 確認 NTP 同步
chronyc tracking
```

### 問題 2：DNS 解析失敗

```
kinit: Cannot find KDC for realm "LAB.EXAMPLE.COM" while getting initial credentials
```

**原因**：Client 無法透過 DNS SRV 記錄找到 KDC。

**解決方案**：

```bash
# 檢查 DNS SRV 記錄
dig _kerberos._udp.lab.example.com SRV

# 如果 DNS 有問題，可以在 /etc/krb5.conf 手動指定 KDC
# [realms]
# LAB.EXAMPLE.COM = {
#     kdc = ipa.lab.example.com
#     admin_server = ipa.lab.example.com
# }
```

### 問題 3：Keytab 版本不符

```
Server not found in Kerberos database
```

或

```
Decrypt integrity check failed
```

**原因**：Keytab 中的密鑰版本（KVNO）和 KDC 資料庫中的不一致。可能是 keytab 過舊，或密鑰被重新產生但 keytab 沒更新。

**解決方案**：

```bash
# 檢查 keytab 的 KVNO
klist -k /etc/krb5.keytab

# 檢查 KDC 中的 KVNO
kvno host/client.lab.example.com@LAB.EXAMPLE.COM

# 重新產生 keytab
ipa-getkeytab -s ipa.lab.example.com \
    -p host/client.lab.example.com \
    -k /etc/krb5.keytab
```

### 問題 4：SSSD 快取問題

使用者已經在 IPA 新增，但 Client 找不到：

```bash
id alice
# id: 'alice': no such user
```

**解決方案**：

```bash
# 清除 SSSD 快取
sudo sss_cache -E

# 或重啟 SSSD
sudo systemctl restart sssd
```

### 除錯工具

```bash
# 開啟 Kerberos debug 訊息
export KRB5_TRACE=/dev/stderr
kinit alice
# 會顯示詳細的認證過程

# SSSD debug（需要修改設定）
# /etc/sssd/sssd.conf
# [sssd]
# debug_level = 9
sudo systemctl restart sssd
sudo journalctl -u sssd -f
```

## 總結

在這篇文章中，我們完成了：

1. **FreeIPA 架構理解**
   - 整合 Kerberos、LDAP、DNS、CA 的統一身份管理平台
   - 使用 LDAP 作為統一資料儲存

2. **Server 與 Client 安裝**
   - 使用 `ipa-server-install` 和 `ipa-client-install`
   - 理解安裝過程中各元件的設定

3. **使用者與群組管理**
   - 使用 `ipa` 命令新增、修改使用者
   - 理解 Principal 和 LDAP 使用者的整合

4. **服務 Principal 與 Keytab**
   - 建立服務 Principal
   - 使用 `ipa-getkeytab` 產生 keytab
   - Keytab 輪換和安全考量

5. **Kerberos 操作實務**
   - kinit / klist / kdestroy 日常使用
   - 理解 Ticket 旗標和生命週期
   - 常見問題排解

## 其他進階內容
- **Cross-Realm Trust**：不同 Realm 之間的信任關係設定
- **PKINIT**：使用智慧卡/憑證取代密碼認證

## 下一篇預告

在下一篇文章中，我們會介紹如何使用 Keycloak 作為身份代理，與 FreeIPA 整合：

- User Federation 的概念與運作方式
- 三種 Edit Mode（READ_ONLY、WRITABLE、UNSYNCED）的差異
- Writeback 機制的限制與注意事項
- LDAP Mapper 設定與同步機制

## Reference

- [FreeIPA Documentation](https://freeipa.readthedocs.io/)
- [Red Hat Identity Management Guide](https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/9/html/configuring_and_managing_identity_management/)
- [MIT Kerberos Documentation](https://web.mit.edu/kerberos/krb5-latest/doc/)
