---
title: Kerberos 入門指南
description: 從零開始學習 Kerberos 認證協議，包含歷史背景、核心概念、協議細節與設計原則
date: 2026-02-01
slug: kerberos-101
series: "freeipa"
tags:
    - "kerberos"
    - "authentication"
    - "note"
---

Kerberos 是企業環境中最常見的網路認證協議。無論是 Active Directory、FreeIPA，還是 Hadoop 叢集的安全認證，底層都是 Kerberos。這篇文章會從歷史背景開始，帶你理解 Kerberos 的設計理念與協議細節。

## 先從一個例子開始

在深入技術細節之前，讓我們用一個生活化的例子來建立直覺。

想像你到一間大型遊樂園玩，這個遊樂園有幾十個遊樂設施，每個設施都需要驗證你的身份才能使用。

**傳統做法的問題**

```
你想玩雲霄飛車：
  → 到雲霄飛車入口，出示身分證，工作人員打電話給售票處確認
  → 確認完畢，可以玩

你想玩旋轉木馬：
  → 到旋轉木馬入口，再次出示身分證，工作人員又打電話確認
  → 確認完畢，可以玩

你想玩摩天輪：
  → 又要出示身分證，又要打電話確認...
```

問題顯而易見：
- 你的身分證要給每個工作人員看
- 每次都要重複驗證，很麻煩
- 任何一個工作人員都可以記下你的身分證號碼

**更好的做法**

```
進入遊樂園時：
  → 到服務中心出示身分證
  → 服務中心確認後，給你一個「通行手環」
  → 這個手環只有服務中心能製作，而且上面有時效

你想玩雲霄飛車：
  → 到服務中心說「我要玩雲霄飛車」，出示手環
  → 服務中心給你一張「雲霄飛車專用票」
  → 這張票只有雲霄飛車的驗票機能讀取

實際去玩：
  → 到雲霄飛車入口，刷專用票
  → 驗票機確認票是真的 → 可以玩
  → 全程不需要再出示身分證！
```

這個做法的好處：
- 身分證只在一開始出示一次
- 每個設施拿到的是專屬的票，不是你的身分證
- 票有時效性，過期就要重新取得
- 即使某個設施的驗票機被駭，攻擊者也拿不到你的身分證

這就是 Kerberos 的運作邏輯。接下來讓我們了解它的背景和正式術語。

## 歷史沿革與背景

Kerberos 是由 MIT（Massachusetts Institute of Technology）在 1980 年代開發的網路認證協議，名字來自希臘神話中守護冥界的三頭犬 Cerberus（希臘文 Κέρβερος）。這個命名暗示了協議的三方參與者：Client、Server、以及可信任的第三方認證中心。

**版本演進：**
- **Kerberos v1-v3**（1983-1987）：MIT 內部使用，未公開
- **Kerberos v4**（1989）：首次公開發布，廣泛使用但有安全性限制
- **Kerberos v5**（1993）：RFC 1510 發布，後更新為 RFC 4120，是目前的標準

**為什麼需要 Kerberos？**

在 1980 年代，MIT 的 Project Athena 計畫面臨一個問題：如何讓數千名學生安全地存取分散在校園各處的工作站和服務？當時的解決方案（如 `.rhosts`、NIS）都有明顯的安全缺陷：

- 密碼以明文傳輸
- 容易被 MITM（Man-in-the-Middle）攻擊
- 每個服務都要維護自己的帳號密碼

Kerberos 的設計目標就是在不安全的網路上，提供一個安全、集中式的認證機制。

## 核心概念

在進入協議細節之前，先介紹 Kerberos 的核心術語。

### KDC（Key Distribution Center）

Kerberos 架構的核心，負責驗證身份並發放 Ticket。KDC 包含兩個邏輯元件：

- **AS（Authentication Server）**：處理初次登入，驗證密碼並發放 TGT
- **TGS（Ticket Granting Server）**：處理後續請求，用 TGT 換發 Service Ticket

在實務部署中，AS 和 TGS 通常是同一台伺服器上的同一個程序。

對應到遊樂園的比喻：**KDC 就是服務中心**，負責驗證你的身分證並發放手環和專用票。

### Principal 與 Realm

**Principal** 是 Kerberos 中的身份識別單位，格式為 `name@REALM`，例如：
- 使用者：`alice@EXAMPLE.COM`
- 服務：`HTTP/www.example.com@EXAMPLE.COM`

**Realm** 是一個 Kerberos 管理網域，通常用大寫的 DNS 網域名稱表示（如 `EXAMPLE.COM`）。一個 Realm 由一個 KDC 管轄。

對應到遊樂園的比喻：**Principal 是你的名字**，**Realm 是遊樂園的名稱**。

### Ticket 的本質

Ticket 是一段由 KDC 加密的資料，用來證明「某個 Principal 已經通過驗證」。重點是：**Ticket 是用目標服務的密鑰加密的，所以只有該服務能解開。**

Ticket 內容包含：
- Client Principal（誰）
- 目標服務 Principal（要存取誰）
- Session Key（這次通訊用的臨時密鑰，由 KDC 產生）
- 有效期限
- Client IP（可選）

> **Session Key** 是 KDC 為每次認證產生的臨時密鑰，讓 Client 和服務能夠安全通訊。詳細的運作方式會在後面的「資料流動與 Session Key 的角色」章節說明。

對應到遊樂園的比喻：**Ticket 就是專用票**，只有對應的驗票機能讀取。

### TGT（Ticket Granting Ticket）

TGT 是一種特殊的 Ticket，它的「目標服務」就是 TGS 本身。可以把 TGT 理解成「一張可以用來領取其他票的票」。

這個概念類似 DNSSEC 的信任鏈：在 DNSSEC 中，root zone 的公鑰（trust anchor）用來驗證 TLD 的簽章，TLD 再驗證各網域的簽章。同樣地，在 Kerberos 中：

- **TGT** 就像是 trust anchor，證明你已經通過 KDC 的認證
- **Service Ticket** 就像是各網域的簽章，由 TGT 衍生而來
- 服務只需要信任 KDC，就能驗證任何持有有效 Ticket 的使用者

```
┌─────────────────────────────────────────────────┐
│  普通 Service Ticket                            │
│  ├── 證明: alice 已驗證                         │
│  ├── 目標: HTTP/www.example.com                 │
│  └── 用途: 存取 Web Server                      │
├─────────────────────────────────────────────────┤
│  TGT (特殊的 Ticket)                            │
│  ├── 證明: alice 已驗證                         │
│  ├── 目標: krbtgt/EXAMPLE.COM (TGS 服務本身)    │
│  └── 用途: 向 TGS 請求其他服務的 Ticket         │
└─────────────────────────────────────────────────┘
```

對應到遊樂園的比喻：**TGT 就是通行手環**，有了它就能領取各種專用票。

**為什麼要分成 TGT 和 Service Ticket 兩層？**

這是為了減少密碼的使用次數：

| 如果沒有 TGT | 有 TGT 的設計 |
|---|---|
| 每次存取服務都要輸入密碼向 KDC 驗證 | 只在登入時輸入一次密碼取得 TGT |
| 密碼使用 N 次（N = 服務數量） | 密碼只使用 1 次 |
| 密碼外洩風險高 | TGT 有時效性，風險可控 |

### 完整的登入與存取流程

```
早上 9:00 登入（只有這步需要密碼）
[alice] --密碼--> [AS] --TGT--> [alice 的 credential cache]

9:05 存取 Mail Server
[alice] --TGT--> [TGS] --Mail Service Ticket--> [alice]
[alice] --Mail Service Ticket--> [Mail Server] ✓

9:10 存取 Wiki（不用再輸入密碼）
[alice] --TGT--> [TGS] --Wiki Service Ticket--> [alice]
[alice] --Wiki Service Ticket--> [Wiki Server] ✓

... 整天都不用再輸入密碼，直到 TGT 過期（預設通常是 10 小時）
```

### Keytab：服務的密碼檔

前面提到 Ticket 是用「服務的密鑰」加密的，但服務（如 Apache、SSH、NFS）是 daemon 程式，無法像人一樣「輸入密碼」。**Keytab**（Key Table）就是解決這個問題的機制。

Keytab 是一個檔案，儲存了服務 Principal 的長期密鑰：

| | 使用者密碼 | Keytab |
|---|---|---|
| 儲存位置 | 使用者的腦袋 | 服務主機上的檔案 |
| 使用方式 | 使用者手動輸入 | 服務程式自動讀取 |
| 互動性 | 需要人工介入 | 無需人工介入（適合 daemon） |
| 典型路徑 | N/A | `/etc/krb5.keytab` 或服務專屬路徑 |

對應到遊樂園的比喻：**Keytab 就是驗票機的解鎖密碼**——驗票機需要這個密碼才能讀取專用票的內容。

**為什麼需要 Keytab？**

當 Client 向服務出示 Service Ticket 時，服務需要能夠解密 Ticket 來取得 Session Key。Ticket 是用服務的長期密鑰加密的，而這個密鑰就存在 keytab 裡。

```
管理員部署流程：
$ ipa-getkeytab -s ipa.example.com -p HTTP/www.example.com -k /etc/httpd/http.keytab

服務驗證流程：
┌───────────────────┐
│  Service Ticket   │  ←  用服務的長期密鑰加密
└─────────┬─────────┘
          │
          ▼
┌───────────────────┐
│     Service       │
│  用 keytab 解密   │  →  取得 Session Key，驗證 Client
└───────────────────┘
```

:::warning
Keytab 檔案包含服務的長期密鑰，必須妥善保護。如果 keytab 洩漏，攻擊者可以偽裝成該服務、解密所有發給該服務的 Ticket。

最佳實踐：
- 設定嚴格的檔案權限（`chmod 600`，僅 root 或服務帳號可讀）
- 每個服務使用獨立的 keytab
- 定期輪換 keytab
:::


### 術語對照表

現在你已經了解 Kerberos 的核心術語，讓我們把遊樂園的比喻對應起來：

| 遊樂園 | Kerberos |
|---|---|
| 身分證 | 密碼 |
| 服務中心 | KDC（Key Distribution Center） |
| 服務中心確認身分 | AS（Authentication Server） |
| 服務中心發票 | TGS（Ticket Granting Server） |
| 通行手環 | TGT（Ticket Granting Ticket） |
| 雲霄飛車專用票 | Service Ticket |
| 驗票機 | 服務的認證模組 |
| 驗票機的解鎖密碼 | Keytab |
| 遊樂園名稱 | Realm |
| 你的名字 | Principal |

### 思考題

在繼續之前，試著回答以下問題：

<details>
<summary>Q1：TGT 和 Service Ticket 有什麼不同？為什麼不能直接用 TGT 存取服務？</summary>

**差異**：
- TGT 的目標是 TGS（`krbtgt/REALM`），用於向 KDC 請求其他 Ticket
- Service Ticket 的目標是特定服務（如 `HTTP/www.example.com`），用於存取該服務

**為什麼不能直接用 TGT 存取服務**：

TGT 是用 TGS 的密鑰加密的，只有 TGS 能解開。如果 alice 拿 TGT 去找 HTTP Server，HTTP Server 沒有 TGS 的密鑰，根本無法解密 TGT，也就無法驗證 alice 的身份。

每個 Service Ticket 都是用該服務的密鑰加密的，所以只有對應的服務能解開。這就是為什麼需要「先用 TGT 換 Service Ticket，再用 Service Ticket 存取服務」這個兩步驟流程。

</details>

<details>
<summary>Q2：alice 能不能修改 TGT 的內容，例如延長有效期限？</summary>

**不能。**

TGT 的內容（包括有效期限、alice 的身份、Session Key）都在 `ticket.enc-part` 裡面，而這部分是用 TGS 的密鑰加密的。alice 沒有 TGS 的密鑰，所以：

1. 她無法解開 TGT 看到裡面的內容
2. 她無法修改內容後重新加密
3. 任何竄改都會導致 TGS 解密失敗

alice 只是 TGT 的「搬運工」——她拿著這個加密的黑盒子從 AS 搬到 TGS，完全不知道裡面裝了什麼。

</details>

<details>
<summary>Q3：如果 alice 的 TGT 被偷了，攻擊者能用多久？</summary>

攻擊者能使用這個 TGT 直到它**過期**為止（預設通常是 10 小時）。在這段時間內，攻擊者可以用這個 TGT 向 TGS 請求任何服務的 Service Ticket，以 alice 的身份存取服務。

**但攻擊者無法**：
- 延長 TGT 的有效期限（無法修改加密內容）
- 取得 alice 的密碼（密碼不在 TGT 裡）
- 在 TGT 過期後繼續使用（需要密碼才能取得新 TGT）

這也是為什麼 Kerberos 環境通常會設定較短的 TGT 有效期限，並搭配 Ticket Renewal 機制——減少被盜用的時間窗口。

</details>

<details>
<summary>Q4：可以用 Kerberos 更改使用者密碼嗎？</summary>

**可以，但不是透過核心的 AS/TGS/AP 流程。**

Kerberos 有一個擴展協議叫 **kpasswd**（RFC 3244），專門用於更改密碼：

```bash
$ kpasswd
Password for alice@EXAMPLE.COM: [舊密碼]
Enter new password: [新密碼]
Enter it again: [新密碼]
Password changed.
```

這個服務通常運行在 port 464，是 KDC 的一部分。

**核心協議 vs 擴展協議**：

| 流程 | 用途 | 是否核心協議 |
|---|---|---|
| AS Exchange | 用密碼換 TGT | ✅ 核心（RFC 4120） |
| TGS Exchange | 用 TGT 換 Service Ticket | ✅ 核心（RFC 4120） |
| AP Exchange | 向服務證明身份 | ✅ 核心（RFC 4120） |
| kpasswd | 更改密碼 | ❌ 擴展（RFC 3244） |

嚴格來說：**Kerberos 核心協議只做 authentication**，密碼更改是生態系統的擴展功能。

在 FreeIPA/Active Directory 環境中，`kpasswd` 會同時更新 Kerberos 資料庫和 LDAP 中的密碼，所以使用者只需要操作一次。

</details>

## Kerberos 與 LDAP 的關係

在理解 Kerberos 之後，必須釐清它與 LDAP（Lightweight Directory Access Protocol）的分工：

| | Kerberos | LDAP |
|---|---|---|
| **用途** | Authentication（認證） | Directory Service（目錄服務） |
| **回答的問題** | 「你是誰？」 | 「你有什麼屬性？你屬於哪些群組？」 |
| **儲存內容** | Principal、密鑰、Ticket Policy | 使用者資訊、群組、OU、權限 |
| **協議標準** | RFC 4120 | RFC 4511 |

**為什麼常常一起出現？**

單獨使用 Kerberos 只能驗證「這個人是 alice@EXAMPLE.COM」，但無法得知 alice 的 email、所屬部門、或她有沒有權限存取某個資源。這時就需要 LDAP 來補充這些資訊。

實務上的整合方式：

1. **使用者登入** → Kerberos 驗證身份，取得 TGT
2. **存取服務** → Kerberos 發放 Service Ticket
3. **服務查詢權限** → 透過 LDAP 查詢該使用者的群組與屬性
4. **授權決策** → 服務根據 LDAP 資訊決定是否放行

這也是為什麼 FreeIPA、Active Directory 這類解決方案都會同時整合 Kerberos + LDAP——前者負責「你是誰」，後者負責「你能做什麼」。

### 為什麼有 LDAP 還需要 Kerberos？

LDAP 確實支援認證，最常見的是 Simple Bind——Client 直接把帳號密碼傳給 LDAP Server 驗證。但這種方式有幾個根本性的問題：

**1. 密碼重複傳輸**

每次存取不同服務時，都要重新輸入密碼並傳送一次：

```
使用者 → [密碼] → Mail Server → [密碼] → LDAP
使用者 → [密碼] → File Server → [密碼] → LDAP
使用者 → [密碼] → Web App    → [密碼] → LDAP
```

密碼在網路上傳輸的次數越多，被攔截的風險就越高。即使用 TLS 加密，密碼仍然以明文形式存在於每個服務的記憶體中。

**2. 服務端必須接觸密碼**

使用 LDAP Simple Bind 時，每個服務都會拿到使用者的明文密碼（即使只是為了轉發給 LDAP）。這代表：

- 惡意服務可以記錄你的密碼
- 服務被入侵時，攻擊者可以取得密碼
- 你必須信任每一個服務

**3. 沒有 SSO（Single Sign-On）**

使用者登入 Mail Server 後，存取 File Server 還要再輸入一次密碼。在有幾十個服務的企業環境中，這對使用者體驗是災難。

**Kerberos 如何解決這些問題？**

Kerberos 採用 Ticket 機制，密碼只在登入時使用一次：

```
1. 使用者 → [密碼] → KDC（只有這次需要密碼）
2. KDC    → [TGT] → 使用者

3. 使用者 → [TGT] → KDC（請求存取 Mail Server）
4. KDC    → [Service Ticket] → 使用者

5. 使用者 → [Service Ticket] → Mail Server（不需要密碼！）
```

| | LDAP Simple Bind | Kerberos |
|---|---|---|
| 密碼傳輸次數 | 每次存取服務都傳 | 只在登入時傳一次 |
| 服務是否接觸密碼 | 是 | 否，只看到 Ticket |
| SSO 支援 | 無 | 有，TGT 有效期間內免密碼 |
| MITM 防護 | 依賴 TLS | Ticket 本身有加密與時間戳 |

簡單來說：**LDAP 解決的是「去哪裡查資料」，Kerberos 解決的是「如何安全地證明身份」**。兩者互補而非競爭。

## Kerberos 解決什麼問題？

### 問題一：密碼在網路上裸奔

在沒有 Kerberos 的環境中，考慮這個場景：

```bash
# 傳統的 telnet/rlogin
$ telnet server.example.com
Username: alice
Password: mysecretpassword  # 明文傳輸！
```

即使改用加密連線，每個服務都會經手你的密碼：

```
[alice] --密碼--> [Web App] --密碼--> [LDAP]
                        ↑
                 密碼存在記憶體中
                 被入侵就洩漏
```

### 問題二：N 個服務 = 輸入 N 次密碼

一個典型的企業環境可能有：

- Email（Outlook/Thunderbird）
- 檔案伺服器（NFS/SMB）
- 內部 Wiki（Confluence）
- 程式碼倉庫（GitLab）
- 工單系統（Jira）

沒有 SSO 的情況下，使用者每天早上要輸入 5 次以上的密碼。結果就是：
- 使用者設定簡單密碼
- 使用者在各處使用相同密碼
- 使用者把密碼貼在螢幕旁邊

### 問題三：服務之間的信任

假設你有一個 Web App 需要代替使用者存取後端的資料庫：

```
[User] --> [Web App] --> [Database]
```

傳統做法：
- Web App 用一個共用帳號連資料庫（無法追蹤是誰的操作）
- 或者 Web App 儲存使用者密碼再轉發（極度危險）

Kerberos 的 **Delegation** 機制可以讓 Web App 以使用者的身份存取 Database，同時不需要知道使用者的密碼。

### 思考題

<details>
<summary>Q1：Kerberos 和 LDAP 各自負責什麼？為什麼企業環境通常兩者都需要？</summary>

**分工**：
- **Kerberos**：Authentication（認證）—— 回答「你是誰？」
- **LDAP**：Directory Service（目錄服務）—— 回答「你有什麼屬性？你能做什麼？」

**為什麼都需要**：

單獨使用 Kerberos 只能確認「這個人是 alice@EXAMPLE.COM」，但無法得知：
- alice 的 email 地址是什麼
- alice 屬於哪個部門
- alice 有沒有權限存取某個資源

LDAP 儲存這些屬性資訊，讓服務能夠做出授權決策。

實務流程：Kerberos 驗證身份 → 服務向 LDAP 查詢權限 → 服務決定是否放行

</details>

<details>
<summary>Q2：為什麼不直接用 LDAP Simple Bind 做認證？</summary>

LDAP Simple Bind 有三個根本問題：

1. **密碼重複傳輸**：每次存取不同服務都要傳一次密碼
2. **服務接觸密碼**：每個服務都會拿到明文密碼（即使只是轉發）
3. **沒有 SSO**：登入 Mail Server 後，存取 File Server 還要再輸入密碼

Kerberos 用 Ticket 機制解決這些問題：密碼只在登入時使用一次，之後都用 Ticket 證明身份。

</details>

<details>
<summary>Q3：如果沒有 SSO，企業環境會發生什麼事？</summary>

沒有 SSO 的企業環境（假設有 10 個服務）：

**使用者行為**：
- 每天早上要輸入 10 次密碼
- 為了方便，設定簡單密碼（如 `password123`）
- 各處使用相同密碼
- 把密碼寫在便利貼上

**安全後果**：
- 簡單密碼容易被暴力破解
- 一個服務被入侵 = 所有服務都被入侵（相同密碼）
- 便利貼密碼被路過的人看到

SSO 讓使用者只需登入一次，可以接受較強的密碼政策（因為只需記住一個）。

</details>

## Kerberos 協議細節

Kerberos 認證分為三個階段，共六個訊息。以下逐一介紹每個階段的流程與訊息格式。

Kerberos 訊息使用 **ASN.1（Abstract Syntax Notation One）** 編碼，以下用較易讀的格式說明各訊息的結構。

### AS Exchange：用密碼換取 TGT

這是認證流程的第一階段，也是**唯一需要密碼的階段**。

```
Client                                  KDC (AS)
  │                                        │
  │ ──── AS-REQ ─────────────────────────> │
  │   (我是 alice，這是加密的時間戳)       │
  │                                        │
  │ <─── AS-REP ─────────────────────────  │
  │   (這是你的 TGT + Session Key)         │
```

| 訊息 | 全名 | 方向 | 用途 |
|---|---|---|---|
| AS-REQ | Authentication Service Request | Client → KDC | 請求 TGT，包含加密的時間戳證明身份 |
| AS-REP | Authentication Service Reply | KDC → Client | 回傳 TGT 和 TGS Session Key |

Client 用密碼加密時間戳放在 AS-REQ 的 padata 中，證明自己知道密碼。KDC 驗證成功後，回傳 TGT 和用於後續與 TGS 通訊的 Session Key。

#### AS-REQ（Authentication Service Request）

```
AS-REQ {
    pvno            = 5                          -- 協議版本號
    msg-type        = AS-REQ (10)                -- 訊息類型

    padata          = [                          -- Pre-Authentication Data
        {
            type    = PA-ENC-TIMESTAMP           -- 加密的時間戳
            value   = 用 alice 密碼加密的當前時間
        }
    ]

    req-body        = {
        kdc-options = FORWARDABLE, RENEWABLE     -- Ticket 選項
        cname       = alice                      -- Client Principal 名稱
        realm       = EXAMPLE.COM                -- Realm 名稱
        sname       = krbtgt/EXAMPLE.COM         -- 請求的服務（TGS）
        till        = 20260202000000Z            -- 請求的過期時間
        nonce       = 123456789                  -- 隨機數，確保 response 的 freshness
        etype       = [aes256-cts, aes128-cts]   -- 支援的加密類型
    }
}
```

**padata（Pre-Authentication Data）** 是用來防止離線密碼猜測攻擊。沒有它的話，任何人都可以以 alice 的名義請求 TGT，然後離線嘗試破解。加密的時間戳證明請求者確實知道密碼。

**nonce** 是讓 Client 能驗證 response 的 freshness，確保收到的是對應這次請求的回應，而不是被重放的舊回應。

<details>
<summary>padata vs nonce 的差異</summary>

兩者都與 replay attack 防護有關，但防護的對象和攻擊場景完全不同：

**padata（Pre-Authentication Data）**

- **目的**：讓 KDC 驗證「發送請求的人確實知道密碼」
- **運作方式**：Client 用自己的密碼加密當前時間戳，KDC 嘗試解密並檢查時間是否合理
- **防止的攻擊**：離線密碼猜測（Offline Password Guessing）

如果沒有 padata：
```
1. 攻擊者發送 AS-REQ：「我是 alice，給我 TGT」
2. KDC 不驗證身份，直接回傳 AS-REP（其中 enc-part 是用 alice 密碼加密的）
3. 攻擊者拿到 AS-REP 後可以離線暴力破解：
   for password in wordlist:
       if decrypt(enc-part, password) 成功:
           print("alice 的密碼是", password)
```

有 padata 後：
```
1. 攻擊者發送 AS-REQ：「我是 alice，給我 TGT」
2. KDC：「你的 padata 解密失敗或時間戳不對」→ 請求被拒絕
3. 攻擊者根本拿不到 AS-REP，無法進行離線破解
```

**nonce**

- **目的**：讓 Client 驗證「收到的 response 是針對這次請求的」
- **運作方式**：Client 在 request 中放入隨機數，KDC 將相同的 nonce 放入加密的 response 中
- **防止的攻擊**：Response Replay（回應重放）

攻擊場景：
```
1. 攻擊者之前側錄到一個合法的 AS-REP（nonce = 99999）
2. alice 發送新的 AS-REQ（nonce = 12345）
3. 攻擊者攔截，把舊的 AS-REP 丟給 alice
4. alice 解密 enc-part，發現 nonce = 99999，不是自己送的 12345 → 拒絕
```

**總結比較**

| | padata | nonce |
|---|---|---|
| **保護方向** | Request（KDC 驗證 Client） | Response（Client 驗證 KDC） |
| **防止的攻擊** | 離線密碼猜測 | 舊 Response 被重放 |
| **檢查者** | KDC | Client |
| **內容** | 用密碼加密的時間戳 | 隨機數 |

簡單說：**padata 保護 request 方向，nonce 保護 response 方向**。

</details>

<details>
<summary>如果攻擊者立刻重放 AS-REQ 呢？</summary>

假設攻擊者側錄到 alice 的合法 AS-REQ（包含有效的 padata 時間戳），然後立刻重送：

**防護層 1：Replay Cache**

KDC 會維護一個 Replay Cache，記錄最近處理過的 `(client principal, timestamp, microsecond)` 組合。如果收到重複的組合，請求會被拒絕。

```
第一次收到 alice 的請求：
  → (alice@EXAMPLE.COM, T1, 123456) → 放入 cache，處理請求

攻擊者重送相同請求：
  → (alice@EXAMPLE.COM, T1, 123456) → 已存在於 cache，拒絕！
```

**防護層 2：就算拿到 AS-REP 也沒用**

假設 Replay Cache 失效，攻擊者真的拿到了 AS-REP：

```
AS-REP {
    ticket = TGT（用 TGS 密鑰加密）
    enc-part = { session_key, nonce, ... }（用 alice 密碼加密）
}
```

攻擊者的困境：
- 有 TGT，但它是加密的，無法讀取內容
- 有 enc-part，但它是用 alice 密碼加密的
- 沒有 alice 的密碼 → 無法解出 Session Key
- 沒有 Session Key → 無法產生後續的 Authenticator → 無法使用 TGT

結論：Kerberos 的設計讓「知道密碼」成為整個流程的關鍵——沒有密碼，即使攔截到所有封包也無法進行後續操作。

</details>

#### AS-REP（Authentication Service Reply）

```
AS-REP {
    pvno            = 5
    msg-type        = AS-REP (11)

    crealm          = EXAMPLE.COM
    cname           = alice

    ticket          = {                          -- 這就是 TGT！
        tkt-vno     = 5
        realm       = EXAMPLE.COM
        sname       = krbtgt/EXAMPLE.COM
        enc-part    = {                          -- 用 TGS 的密鑰加密
            etype   = aes256-cts
            cipher  = <加密的 EncTicketPart>
            -- 內含：Session Key, alice, 有效期限等
            -- 只有 TGS 能解開這段！
        }
    }

    enc-part        = {                          -- 用 alice 的密碼加密
        etype       = aes256-cts
        cipher      = <加密的 EncASRepPart>
        -- 內含：Session Key, nonce, 有效期限等
        -- 只有 alice 能解開這段！
    }
}
```

注意這裡有兩個 `enc-part`：

- **ticket.enc-part**：用 TGS 密鑰加密，alice 無法解開，只能原封不動地轉交給 TGS。這是 Kerberos 安全模型的核心——alice 永遠無法讀取或修改 Ticket 內容，因此無法偽造身份、延長有效期限、或提升權限。即使 alice 的電腦被入侵，攻擊者也只能使用現有的 Ticket，無法產生新的。

- **enc-part**：用 alice 密碼加密，alice 解開後取得 Session Key，用於後續與 TGS 的通訊。

#### 思考題

<details>
<summary>Q1：為什麼 Kerberos 不直接把密碼傳給 KDC 驗證，而是用密碼加密時間戳？</summary>

如果直接傳密碼：
- 密碼會在網路上傳輸，可能被攔截
- KDC 會看到明文密碼，增加洩漏風險

用密碼加密時間戳的做法：
- 密碼從未離開 Client 端
- KDC 用自己資料庫中的密鑰嘗試解密，成功就代表 Client 知道密碼
- 這是「證明你知道密碼，但不傳送密碼本身」的 Zero-Knowledge Proof 概念

</details>

<details>
<summary>Q2：攻擊者攔截到 AS-REP 後，能不能離線破解 alice 的密碼？</summary>

**可以嘗試，但難度取決於密碼強度。**

AS-REP 中的 `enc-part`（不是 ticket.enc-part）是用 alice 的密碼加密的。攻擊者可以：

```
for password in wordlist:
    if decrypt(enc-part, password) 成功且內容合理:
        print("alice 的密碼是", password)
```

這就是為什麼 Kerberos 環境需要強密碼政策。這種攻擊稱為 **AS-REP Roasting**（針對沒有啟用 padata 的帳號）或一般的離線暴力破解。

**緩解措施**：
- 強制使用強密碼
- 啟用 Pre-Authentication（padata）防止未驗證的 AS-REP 發放
- 監控異常的 AS-REQ 請求

</details>

<details>
<summary>Q3：為什麼 AS-REP 要有兩個 enc-part？不能只用一個嗎？</summary>

兩個 enc-part 服務不同對象：

1. **ticket.enc-part**（給 TGS 看）：用 TGS 密鑰加密
   - alice 無法解開，只能原封不動轉交
   - 確保 alice 無法偽造或修改 Ticket 內容

2. **enc-part**（給 alice 看）：用 alice 密碼加密
   - 包含 Session Key，alice 需要這個來產生後續的 Authenticator
   - 包含 nonce，alice 用來驗證這是對應她請求的回應

如果只有一個 enc-part：
- 如果用 alice 密碼加密 → alice 可以修改 Ticket 內容（偽造身份、延長期限）
- 如果用 TGS 密鑰加密 → alice 無法取得 Session Key，後續流程無法進行

兩個 enc-part 的設計讓「alice 能取得需要的資訊，但無法修改不該碰的內容」。

</details>

### TGS Exchange：用 TGT 換取 Service Ticket

這是認證流程的第二階段。alice 用上一階段取得的 TGT 向 TGS 請求存取特定服務的 Ticket。

```
Client                                  KDC (TGS)
  │                                        │
  │ ──── TGS-REQ ─────────────────────────>│
  │    (這是我的 TGT，我要存取 HTTP)       │
  │                                        │
  │ <─── TGS-REP ───────────────────────── │
  │    (這是 HTTP 的 Service Ticket)       │
```

| 訊息 | 全名 | 方向 | 用途 |
|---|---|---|---|
| TGS-REQ | Ticket Granting Service Request | Client → KDC | 用 TGT 請求 Service Ticket |
| TGS-REP | Ticket Granting Service Reply | KDC → Client | 回傳 Service Ticket 和 Service Session Key |

Client 出示 TGT 並說明要存取哪個服務。TGS 驗證 TGT 有效後，發放該服務專屬的 Service Ticket。**這個階段不需要密碼**——TGT 就是身份證明。

#### TGS-REQ（Ticket Granting Service Request）

當 alice 要存取某個服務（例如 HTTP Server），她用 TGT 向 TGS 請求 Service Ticket：

```
TGS-REQ {
    pvno            = 5
    msg-type        = TGS-REQ (12)

    padata          = [
        {
            type    = PA-TGS-REQ
            value   = AP-REQ {                   -- 把 TGT 包在 AP-REQ 裡
                ticket        = TGT              -- 之前拿到的 TGT
                authenticator = {                -- 用 Session Key 加密
                    cname     = alice
                    crealm    = EXAMPLE.COM
                    ctime     = 當前時間
                    cusec     = 微秒
                }
            }
        }
    ]

    req-body        = {
        kdc-options = FORWARDABLE
        realm       = EXAMPLE.COM
        sname       = HTTP/www.example.com       -- 要存取的服務
        till        = 20260202000000Z
        nonce       = 987654321
        etype       = [aes256-cts, aes128-cts]
    }
}
```

**Authenticator** 的作用：

- 證明「現在發送請求的人」就是「當初取得 TGT 的人」
- 因為只有 alice 能從 AS-REP 解出 Session Key
- 能產生正確 Authenticator 的人，一定知道 Session Key

#### TGS-REP（Ticket Granting Service Reply）

```
TGS-REP {
    pvno            = 5
    msg-type        = TGS-REP (13)

    crealm          = EXAMPLE.COM
    cname           = alice

    ticket          = {                          -- Service Ticket
        tkt-vno     = 5
        realm       = EXAMPLE.COM
        sname       = HTTP/www.example.com
        enc-part    = {                          -- 用服務的密鑰加密
            etype   = aes256-cts
            cipher  = <加密的 EncTicketPart>
            -- 內含：Service Session Key, alice, 有效期限
            -- 只有 HTTP 服務能解開！
        }
    }

    enc-part        = {                          -- 用 TGT 的 Session Key 加密
        etype       = aes256-cts
        cipher      = <加密的 EncTGSRepPart>
        -- 內含：Service Session Key, nonce, 有效期限
        -- alice 用 Session Key 解開
    }
}
```

#### 思考題

<details>
<summary>Q1：TGS-REQ 裡面為什麼需要 Authenticator？只出示 TGT 不夠嗎？</summary>

**只有 TGT 不夠，因為無法證明「現在出示 TGT 的人」就是「當初取得 TGT 的人」。**

想像這個攻擊場景：
1. 攻擊者偷到 alice 的 TGT（例如從她的 credential cache）
2. 攻擊者用這個 TGT 向 TGS 請求 Service Ticket
3. 如果不需要 Authenticator，TGS 會直接發放 Service Ticket

有 Authenticator 之後：
1. 攻擊者偷到 alice 的 TGT
2. 攻擊者需要產生 Authenticator，但這需要用 Session Key 加密
3. Session Key 在 AS-REP 的 `enc-part` 裡，用 alice 密碼加密
4. 攻擊者沒有 alice 的密碼 → 無法取得 Session Key → 無法產生 Authenticator → 無法使用 TGT

**結論**：Authenticator 將「擁有 TGT」和「知道 Session Key」綁定在一起，確保只有合法取得 TGT 的人才能使用它。

</details>

<details>
<summary>Q2：TGS-REQ 的 padata 和 AS-REQ 的 padata 有什麼不同？</summary>

| | AS-REQ padata | TGS-REQ padata |
|---|---|---|
| **類型** | PA-ENC-TIMESTAMP | PA-TGS-REQ |
| **內容** | 用密碼加密的時間戳 | AP-REQ（包含 TGT + Authenticator） |
| **加密密鑰** | Client 的密碼 | TGS Session Key |
| **證明什麼** | 「我知道密碼」 | 「我有合法取得的 TGT」 |

AS-REQ 是用「密碼」證明身份，TGS-REQ 是用「TGT + Session Key」證明身份。

這就是 Kerberos 的核心設計：**密碼只在第一步使用，之後都用 Ticket 和 Session Key**。

</details>

<details>
<summary>Q3：為什麼 Service Ticket 是用服務的密鑰加密，而不是用 alice 的密碼？</summary>

**因為 Service Ticket 是給服務看的，不是給 alice 看的。**

如果用 alice 的密碼加密：
- alice 可以解開並修改 Ticket 內容（偽造身份、權限提升）
- 服務需要知道 alice 的密碼才能驗證（違反最小權限原則）

用服務的密鑰加密：
- alice 無法解開或修改 Ticket（她只是搬運工）
- 服務用自己的 keytab 就能驗證，不需要知道任何使用者的密碼
- 只有 KDC 和服務知道這個密鑰，所以 Ticket 無法被偽造

這個設計確保了**服務永遠不會接觸到使用者的密碼**。

</details>

### AP Exchange：向服務證明身份

這是認證流程的最後階段。alice 用上一階段取得的 Service Ticket 向目標服務證明身份。

```
Client                                  Service
  │                                        │
  │ ──── AP-REQ ─────────────────────────> │
  │      (這是我的 Service Ticket)         │
  │                                        │
  │ <─── AP-REP ─────────────────────────  │ (可選，雙向認證時)
  │      (我確認是真正的服務)              │
```

| 訊息 | 全名 | 方向 | 用途 |
|---|---|---|---|
| AP-REQ | Application Request | Client → Service | 向服務出示 Service Ticket |
| AP-REP | Application Reply | Service → Client | 服務回應，證明自己是真正的服務（雙向認證） |

Client 向服務出示 Service Ticket。服務解密 Ticket 驗證 Client 身份。如果 Client 要求雙向認證（MUTUAL-REQUIRED），服務需要回傳 AP-REP 證明自己擁有正確的服務密鑰。

#### AP-REQ（Application Request）

alice 拿著 Service Ticket 去存取服務：

```
AP-REQ {
    pvno            = 5
    msg-type        = AP-REQ (14)

    ap-options      = MUTUAL-REQUIRED            -- 要求雙向認證

    ticket          = Service Ticket             -- 從 TGS-REP 拿到的

    authenticator   = {                          -- 用 Service Session Key 加密
        cname       = alice
        crealm      = EXAMPLE.COM
        ctime       = 當前時間
        cusec       = 微秒
        subkey      = (可選) 後續通訊用的子密鑰
        seq-number  = (可選) 序號，防 replay
    }
}
```

#### AP-REP（Application Reply）

如果 Client 要求雙向認證（MUTUAL-REQUIRED），服務端會回應：

```
AP-REP {
    pvno            = 5
    msg-type        = AP-REP (15)

    enc-part        = {                          -- 用 Service Session Key 加密
        ctime       = 從 Authenticator 複製的時間
        cusec       = 從 Authenticator 複製的微秒
        subkey      = (可選)
        seq-number  = (可選)
    }
}
```

**雙向認證的意義**：

Client 不只要向服務證明自己是 alice，也要確認對方真的是 `HTTP/www.example.com`，而不是攻擊者假冒的。服務能正確解密 Ticket 並回應 Authenticator 中的時間戳，證明它擁有正確的服務密鑰。

#### 思考題

<details>
<summary>Q1：為什麼需要雙向認證？單向認證（只驗證 Client）不夠嗎？</summary>

**單向認證的風險**：釣魚攻擊

```
1. 攻擊者架設假的 mail.example.com
2. alice 連到假服務，出示 Service Ticket
3. 假服務說「驗證成功」（其實它根本無法驗證）
4. alice 開始傳送機密郵件內容
5. 攻擊者取得所有資料
```

**雙向認證的防護**：

```
1. 攻擊者架設假的 mail.example.com
2. alice 連到假服務，出示 Service Ticket，要求 AP-REP
3. 假服務無法解開 Ticket（沒有正確的服務密鑰）
4. 假服務無法產生正確的 AP-REP
5. alice 發現 AP-REP 驗證失敗 → 中斷連線
```

雙向認證確保「我驗證你的同時，你也要驗證你是誰」。

</details>

<details>
<summary>Q2：AP-REP 為什麼只回傳時間戳？這能證明什麼？</summary>

AP-REP 回傳的是「從 Authenticator 複製的時間戳」，用 Service Session Key 加密。

**這能證明什麼**：

1. **服務能解開 Ticket**：Service Session Key 在 Ticket 的 enc-part 裡，用服務密鑰加密。只有擁有正確 keytab 的服務才能解開 Ticket 取得 Session Key。

2. **服務能解開 Authenticator**：Authenticator 是用 Service Session Key 加密的。能解開 Authenticator 取得時間戳，代表服務確實有正確的 Session Key。

3. **回應是針對這次請求的**：時間戳是 alice 這次 Authenticator 的時間戳，不是舊的 AP-REP 被重放。

**簡單說**：「我能正確回覆你的時間戳」= 「我能解開你的 Ticket 和 Authenticator」= 「我有正確的服務密鑰」= 「我是真正的服務」。

</details>

<details>
<summary>Q3：Service 從來沒有向 KDC 驗證過，它怎麼取得 Session Key？</summary>

**關鍵在於 keytab。**

Service 不需要主動向 KDC 驗證。它的驗證流程是「被動」的：

1. **事前準備**：管理員從 KDC 產生 keytab，部署到服務主機
2. **服務啟動**：載入 keytab（包含服務的長期密鑰）
3. **收到 AP-REQ**：
   - 用 keytab 中的密鑰解開 Ticket
   - 從 Ticket 取得 Service Session Key
   - 用 Session Key 解開 Authenticator

Service Session Key 是 KDC 產生的，放在 Ticket 裡面，用服務的長期密鑰加密。所以服務只需要有 keytab，就能取得每個 Client 的 Session Key。

這個設計讓**服務可以離線驗證**——即使 KDC 暫時無法連線，已經取得 Ticket 的 Client 仍然可以存取服務。

</details>

### 訊息交換總覽

```
┌─────────┐                ┌─────────┐                ┌─────────┐
│  Alice  │                │   KDC   │                │ Service │
└────┬────┘                └────┬────┘                └────┬────┘
     │                          │                          │
     │  AS-REQ (密碼驗證)       │                          │
     │ ──────────────────────>  │                          │
     │                          │                          │
     │  AS-REP (TGT)            │                          │
     │ <──────────────────────  │                          │
     │                          │                          │
     │  TGS-REQ (TGT)           │                          │
     │ ──────────────────────>  │                          │
     │                          │                          │
     │  TGS-REP (Ticket)        │                          │
     │ <──────────────────────  │                          │
     │                          │                          │
     │  AP-REQ (Ticket)                                    │
     │ ─────────────────────────────────────────────────>  │
     │                                                     │
     │  AP-REP (確認)                                      │
     │ <─────────────────────────────────────────────────  │
     │                                                     │
     │  正常通訊 (Session Key 加密)                        │
     │ <─────────────────────────────────────────────────> │
```

### 資料流動與 Session Key 的角色

整個 Kerberos 流程中，**KDC 是唯一產生 Session Key 的角色**。每個階段都會產生新的 Session Key，用於下一階段的安全通訊。

#### Session Key 的產生與分發

```
┌───────────────────────────────────────────────────────────────┐
│  AS Exchange: 產生 TGS Session Key                            │
├───────────────────────────────────────────────────────────────┤
│                                                               │
│  KDC 產生 TGS Session Key (K_tgs), 放在兩個地方:              │
│                                                               │
│  ┌───────────────────┐                                        │
│  │      AS-REP       │                                        │
│  ├───────────────────┤                                        │
│  │ TGT               │  ← enc-part 用 TGS 密鑰加密            │
│  │ (給 TGS 看)       │    內含 K_tgs, Alice 無法解開          │
│  ├───────────────────┤                                        │
│  │ enc-part          │  ← 用 Alice 密碼加密, 內含 K_tgs       │
│  │ (給 Alice 看)     │    Alice 解開後取得 K_tgs              │
│  └───────────────────┘                                        │
│                                                               │
│  結果: Alice 和 TGS 都有 K_tgs, 可以安全通訊                  │
│                                                               │
└───────────────────────────────────────────────────────────────┘

┌───────────────────────────────────────────────────────────────┐
│  TGS Exchange: 產生 Service Session Key                       │
├───────────────────────────────────────────────────────────────┤
│                                                               │
│  KDC 產生 Service Session Key (K_service):                    │
│                                                               │
│  ┌───────────────────┐                                        │
│  │     TGS-REP       │                                        │
│  ├───────────────────┤                                        │
│  │ Service Ticket    │  ← enc-part 用服務密鑰加密             │
│  │ (給服務看)        │    內含 K_service                      │
│  ├───────────────────┤                                        │
│  │ enc-part          │  ← 用 K_tgs 加密, 內含 K_service       │
│  │ (給 Alice 看)     │    Alice 解開後取得 K_service          │
│  └───────────────────┘                                        │
│                                                               │
│  結果: Alice 和服務都有 K_service, 可以安全通訊               │
│  注意: K_service 是 KDC 產生的, 不是服務產生的!               │
│                                                               │
└───────────────────────────────────────────────────────────────┘

┌───────────────────────────────────────────────────────────────┐
│  AP Exchange: 使用 Service Session Key                        │
├───────────────────────────────────────────────────────────────┤
│                                                               │
│  Alice 用 K_service 加密 Authenticator 並送出:                │
│                                                               │
│  ┌───────────────────┐          ┌───────────────────┐         │
│  │      AP-REQ       │          │      Service      │         │
│  ├───────────────────┤          ├───────────────────┤         │
│  │ Service Ticket    │ ───────> │  用服務密鑰解密   │         │
│  │                   │          │  取得 K_service   │         │
│  ├───────────────────┤          ├───────────────────┤         │
│  │ Authenticator     │ ───────> │  用 K_service     │         │
│  │ (K_service加密)   │          │  解密驗證         │         │
│  └───────────────────┘          └───────────────────┘         │
│                                                               │
│  雙向認證: Service 用 K_service 加密 AP-REP 回傳              │
│  證明自己能解開 Ticket, 確實擁有服務密鑰                      │
│                                                               │
└───────────────────────────────────────────────────────────────┘
```

#### Service 如何取得 Session Key？

一個常見的疑問：Service 怎麼取得 Service Session Key？它需要在啟動時向 KDC 驗證嗎？

**答案是不需要。** Service 是被動地從 Client 送來的 Ticket 中取得 Session Key：

1. Service 啟動時載入 keytab（包含長期密鑰，詳見前面的「Keytab：服務的密碼檔」章節）
2. 收到 AP-REQ 時，用 keytab 中的密鑰解開 Service Ticket
3. 從 Ticket 中取得 Service Session Key

這是 Kerberos 的一個重要優點：**服務不需要在每次認證時連接 KDC**。即使 KDC 暫時無法連線，已經取得 Ticket 的 Client 仍然可以存取服務。

#### 密鑰使用總覽

| 密鑰 | 誰知道 | 用途 | 生命週期 |
|---|---|---|---|
| Alice 密碼 | Alice, KDC | AS-REQ 的 padata 加密、AS-REP 的 enc-part 解密 | 長期（直到改密碼） |
| TGS 密鑰 | KDC | 加密 TGT 的 enc-part | 長期 |
| 服務密鑰 | 服務, KDC | 加密 Service Ticket 的 enc-part | 長期（存在 keytab） |
| TGS Session Key | Alice, KDC | TGS-REQ 的 Authenticator 加密、TGS-REP 的 enc-part 解密 | 短期（TGT 有效期內） |
| Service Session Key | Alice, 服務 | AP-REQ/REP 加密、後續應用層通訊 | 短期（Ticket 有效期內） |

#### 為什麼這樣設計？

**Session Key 解決的核心問題**：如何讓兩個從未直接交換密鑰的實體（Alice 和服務）能夠安全通訊？

1. **Alice 不知道服務的密鑰**：她無法直接加密訊息給服務
2. **服務不知道 Alice 的密碼**：它無法驗證 Alice 的身份
3. **解法**：由雙方都信任的 KDC 產生一個臨時的 Session Key，分別用各自的密鑰加密後發送

```
傳統做法 (問題):
Alice 和 Service 需要事先交換密鑰, 或者 Alice 把密碼給 Service

Kerberos 做法 (解法):
                        ┌─────┐
                        │ KDC │  ← 產生 K_service
                        └──┬──┘
                           │
            ┌──────────────┼──────────────┐
            │              │              │
            ▼              │              ▼
       ┌─────────┐         │         ┌─────────┐
       │  Alice  │         │         │ Service │
       └─────────┘         │         └─────────┘
            │              │              │
            │  K_service   │   K_service  │
            │ (用 K_tgs    │  (用服務    │
            │  加密傳送)   │   密鑰加密) │
            │              │              │
            └──────────────┴──────────────┘
                           │
                           ▼
                  雙方都有 K_service
                  可以安全通訊
```

這就是為什麼 Kerberos 被稱為「第三方認證協議」——KDC 作為可信任的第三方，負責產生和分發所有的 Session Key。

## 為什麼這樣設計？

### 設計原則一：密碼永遠不在網路上傳輸

```
傳統做法:
[Client] ──密碼──> [Server] ──密碼──> [驗證]
                         ↑
                  密碼在網路上傳輸

Kerberos:
[Client] ──用密碼加密的時間戳──> [KDC]
                       ↑
               密碼本身沒有離開 Client
```

KDC 用它資料庫中儲存的 alice 密鑰嘗試解密時間戳：
- 解密成功且時間正確 → alice 知道密碼
- 解密失敗 → 密碼錯誤

這種「用密碼證明你知道密碼，但不傳送密碼本身」的方式是 **Zero-Knowledge Proof** 概念的應用。

### 設計原則二：最小權限曝露

每個階段只曝露必要的資訊：

| 階段 | 誰能解密什麼 |
|---|---|
| AS-REP.ticket | 只有 TGS（用 TGS 密鑰加密） |
| AS-REP.enc-part | 只有 alice（用 alice 密碼加密） |
| TGS-REP.ticket | 只有目標服務（用服務密鑰加密） |
| TGS-REP.enc-part | 只有 alice（用 Session Key 加密） |

**alice 從來沒有能力看到 Ticket 的內容**——她只是個搬運工，把加密的 Ticket 從 KDC 搬到服務端。這確保了：

- alice 無法偽造或修改 Ticket
- alice 無法延長 Ticket 有效期限
- 就算 alice 的電腦被入侵，攻擊者也無法產生任意 Ticket

### 設計原則三：雙向認證

傳統模式只有「服務驗證 Client」：

```
危險場景:
[alice] ──密碼──> [假的 Mail Server]
                            ↑
                     攻擊者架設的釣魚服務
                     成功取得 alice 的密碼
```

Kerberos 的雙向認證：

```
[alice] ──AP-REQ──> [服務]
        <──AP-REP──
              ↑
      服務必須證明它能解開 Ticket
      才能正確回應 Authenticator 的時間戳
```

假服務沒有正確的服務密鑰，無法：
1. 解開 Ticket 取得 Session Key
2. 用 Session Key 解開 Authenticator
3. 產生正確的 AP-REP

### 設計原則四：時間戳防 Replay

為什麼 Kerberos 這麼依賴時間同步？

```
Authenticator {
    ctime = 2026-02-01 09:30:45
    cusec = 123456
}
```

服務收到後檢查：
- 時間戳是否在 ±5 分鐘內？
- 這個 (alice, timestamp) 組合是否已經見過？

**如果沒有時間戳**，攻擊者可以無限重放：

```
1. 側錄 alice 的 AP-REQ
2. 一小時後重送 → 服務接受
3. 一天後重送 → 服務還是接受
```

**有時間戳後**：

```
1. 側錄 alice 的 AP-REQ（時間戳 = 09:30）
2. 10 分鐘後重送（現在 09:40）
3. 服務檢查：09:30 不在 09:40 ±5 分鐘內 → 拒絕
```

這也是為什麼 Kerberos 環境必須配置 NTP——時間偏差超過 5 分鐘會導致認證失敗。

### 設計原則五：Session Key 隔離

每次認證都產生新的 Session Key：

```
alice 存取 Mail：
  AS Exchange → Session Key A（用於 TGS 通訊）
  TGS Exchange → Session Key B（用於 Mail 通訊）

alice 存取 Wiki：
  TGS Exchange → Session Key C（用於 Wiki 通訊）
```

好處：
- 每個服務的通訊用不同密鑰，互不影響
- 一個 Session Key 洩漏不影響其他服務
- Session Key 有時效性，過期自動失效

### 設計取捨：為什麼需要 KDC？

Kerberos 是**集中式**架構，所有認證都依賴 KDC。這是刻意的設計取捨：

| 優點 | 缺點 |
|---|---|
| 單一管理點，政策統一 | KDC 是 Single Point of Failure |
| 服務不需儲存使用者密碼 | KDC 被入侵代表整個 Realm 淪陷 |
| 新增服務不需改動 Client | 需要高可用部署 |

**KDC 被入侵的後果**：

KDC 的資料庫儲存了所有 Principal 的密鑰（包括使用者密碼的 hash 和所有服務的 keytab）。如果攻擊者取得 KDC 的控制權：

1. **可以偽造任意 Ticket**：攻擊者可以用任何使用者的身份存取任何服務，這種攻擊稱為 Golden Ticket Attack
2. **可以解密所有通訊**：因為所有 Session Key 都是由 KDC 產生的
3. **可以竄改認證政策**：例如延長 Ticket 有效期限、停用特定帳號
4. **可以進行離線密碼破解**：取得所有使用者的密碼 hash

這就是為什麼 KDC 需要最高等級的保護。

**實務上的緩解措施**：
- 部署多個 KDC（primary + replica）以確保高可用
- KDC 放在高度保護的網路區段，限制存取
- 定期備份 KDC 資料庫
- 使用 HSM（Hardware Security Module）保護 master key
- 啟用稽核日誌，監控異常行為

## 總結

在這篇文章中，我們介紹了：

1. **Kerberos 的歷史背景**
   - 源自 MIT Project Athena，解決大規模分散式系統的認證問題
   - 目前標準為 Kerberos v5（RFC 4120）

2. **核心概念**
   - KDC（AS + TGS）：認證中心
   - TGT：用來換取其他 Ticket 的 Ticket，類似 DNSSEC 的 trust anchor
   - Service Ticket：存取特定服務的憑證
   - Principal / Realm：身份識別與管理網域

3. **Kerberos 與 LDAP 的分工**
   - Kerberos：Authentication（你是誰）
   - LDAP：Directory Service（你有什麼屬性、權限）
   - LDAP Simple Bind 的問題：密碼重複傳輸、服務端接觸密碼、無 SSO

4. **協議流程（三階段、六訊息）**
   - AS Exchange：密碼 → TGT（AS-REQ / AS-REP）
   - TGS Exchange：TGT → Service Ticket（TGS-REQ / TGS-REP）
   - AP Exchange：Service Ticket → 服務存取（AP-REQ / AP-REP）

5. **設計原則**
   - 密碼不在網路傳輸
   - 最小權限曝露
   - 雙向認證
   - 時間戳防 Replay
   - Session Key 隔離

## 下一篇預告

在下一篇文章中，我們會使用 FreeIPA 實際部署一個 Kerberos 環境，包含：

- FreeIPA 架構介紹（Kerberos + LDAP + DNS + CA）
- 安裝與設定 KDC
- 建立使用者與服務 Principal
- 產生與使用 Keytab
- 實際驗證 kinit / klist / kdestroy 流程

## Reference

- [RFC 4120 - The Kerberos Network Authentication Service (V5)](https://datatracker.ietf.org/doc/html/rfc4120)
- [MIT Kerberos Documentation](https://web.mit.edu/kerberos/krb5-latest/doc/)
- [Designing an Authentication System: a Dialogue in Four Scenes](https://web.mit.edu/kerberos/dialogue.html)
