---
title: Kerberos 委派：讓 Web App 代替使用者存取後端服務
description: 深入理解 Kerberos Delegation 機制，從 Unconstrained 到 Constrained Delegation，實作 Web App 代替使用者存取資料庫的完整流程
date: 2026-02-01
slug: kerberos-delegation-web-app
series: "freeipa"
tags:
    - "kerberos"
    - "freeipa"
    - "authentication"
    - "note"
---

在上一篇文章中，我們使用 FreeIPA 建立了完整的 Kerberos 環境並學會了基本操作。但有一個常見情境還沒解決：**當使用者透過 Web App 存取後端資料庫時，資料庫如何知道「真正的使用者」是誰？**

這就是 Kerberos Delegation（委派）要解決的問題。

## Kerberos 核心概念回顧

在深入委派之前，先快速回顧 Kerberos 的核心術語。如果你已經熟悉這些概念，可以跳到下一節。

### 關鍵術語

| 術語 | 說明 |
|---|---|
| **KDC**（Key Distribution Center） | Kerberos 的核心伺服器，負責發放 Ticket。包含 AS 和 TGS 兩個服務 |
| **AS**（Authentication Service） | KDC 的一部分，驗證使用者密碼並發放 TGT |
| **TGS**（Ticket Granting Service） | KDC 的一部分，用 TGT 換取 Service Ticket |
| **TGT**（Ticket Granting Ticket） | 「換票證」，用來向 TGS 證明身份，換取各種 Service Ticket |
| **Service Ticket**（ST） | 「服務票」，用來向特定服務證明身份 |
| **Principal** | Kerberos 中的身份識別，格式為 `名稱@REALM`（使用者）或 `服務/主機@REALM`（服務） |
| **Realm** | Kerberos 的管理域，通常用大寫的 DNS 網域名稱（如 `LAB.EXAMPLE.COM`） |
| **Keytab** | 儲存服務密鑰的檔案，讓服務不需密碼就能驗證 Ticket |
| **GSSAPI** | 通用安全服務介面，應用程式透過它使用 Kerberos，不需直接操作協議細節 |

### 認證流程圖解

```
┌───────────────────────────────────────────────────────────────┐
│                            KDC                                │
│  ┌─────────────────────┐    ┌─────────────────────┐          │
│  │         AS          │    │        TGS          │          │
│  │  (Authentication    │    │  (Ticket Granting   │          │
│  │      Service)       │    │      Service)       │          │
│  └──────────┬──────────┘    └──────────┬──────────┘          │
│             │                          │                      │
└─────────────┼──────────────────────────┼──────────────────────┘
              │                          │
     ① AS-REQ │                          │ ③ TGS-REQ
   (密碼驗證) │                          │ (用 TGT 換票)
              ▼                          ▼
         ┌──────────┐            ┌───────────────┐
         │   TGT    │            │ Service Ticket│
         │ (換票證) │            │   (服務票)    │
         └────┬─────┘            └───────┬───────┘
              │                          │
     ② 儲存   │                          │ ④ AP-REQ
       TGT    │                          │ (出示服務票)
              ▼                          ▼
        ┌───────────┐            ┌────────────┐
        │  使用者   │ ────────►  │    服務    │
        │  (alice)  │            │ (HTTP/web) │
        └───────────┘            └────────────┘
```

**流程說明**

1. **AS-REQ**：使用者用密碼向 AS 認證，取得 TGT
2. **儲存 TGT**：TGT 存在本機的 credential cache 中
3. **TGS-REQ**：要存取服務時，用 TGT 向 TGS 請求 Service Ticket
4. **AP-REQ**：將 Service Ticket 出示給服務，完成認證

**為什麼 TGT 重要？**

TGT 是「萬能換票證」——持有它就能向 TGS 請求任何服務的 Service Ticket。這就是為什麼 TGT 被視為最敏感的憑據：**如果攻擊者取得你的 TGT，就等於取得你的身份**。

### Ticket 的加密保護

Ticket 為什麼無法偽造？因為它們被特定密鑰加密：

| Ticket 類型 | 加密密鑰 | 誰能解密 |
|---|---|---|
| TGT | TGS 的密鑰 | 只有 KDC 的 TGS |
| Service Ticket | 服務的密鑰 | 只有目標服務 |

使用者拿到的 Ticket 是「密封的信封」——可以出示給正確的對象，但無法偽造或篡改內容。

---

## 問題情境：誰在存取資料庫？

想像一個典型的三層式架構：

```
┌───────────┐      ┌──────────┐      ┌────────────┐
│  使用者   │ ───► │  Web App │ ───► │   資料庫   │
│  (Alice)  │      │ (Apache) │      │ (Postgres) │
└───────────┘      └──────────┘      └────────────┘
```

**沒有委派時的問題**

當 Alice 透過瀏覽器存取 Web App：

1. Alice 用 Kerberos 認證登入 Web App ✓
2. Web App 確認「這是 Alice」✓
3. Web App 要查詢資料庫...

此時 Web App 面臨選擇：

| 方案 | 做法 | 問題 |
|---|---|---|
| 服務帳號 | Web App 用自己的帳號連資料庫 | 資料庫只知道「Web App」在查詢，不知道是 Alice |
| 儲存密碼 | Web App 儲存 Alice 的密碼，用來認證 | 嚴重安全問題：Web App 知道使用者密碼 |

這兩個方案都不理想。我們需要的是：**Web App 能夠「代表 Alice」存取資料庫，讓資料庫知道真正的請求者是 Alice**。

**有委派時的解法**

```
Alice ──(Kerberos認證)──► Web App ──(以Alice身份)──► 資料庫
                              │
                              └── "我是代表 Alice 來的"
```

資料庫收到的請求帶有 Alice 的身份資訊，可以：
- 套用 Alice 的權限（Row-Level Security）
- 稽核日誌記錄「Alice 查詢了什麼」
- 根據 Alice 的部門顯示不同資料

這就是 Kerberos Delegation 的價值。

## 委派的核心概念

在深入機制之前，先建立幾個核心概念。

### 什麼是「委派」？

**委派（Delegation）** 是指：一個服務（如 Web App）獲得授權，可以「代表使用者」去存取其他服務（如資料庫）。

用生活比喻：

```
委派 = 授權書

Alice 給 Web App 一張授權書：
「我 Alice 授權 Web App 代表我去銀行（資料庫）辦事」

銀行看到這張授權書，知道：
- 真正的客戶是 Alice
- Web App 只是代理人
- 應該用 Alice 的帳戶權限
```

### Kerberos 中的委派類型

Kerberos 支援三種委派機制，依照安全性遞增：

| 類型 | 英文名稱 | 說明 | 安全性 |
|---|---|---|---|
| TGT 轉發 | TGT Forwarding | 把自己的 TGT 給服務 | 低 |
| 無限制委派 | Unconstrained Delegation | 服務可以代表使用者存取任何服務 | 低 |
| 受限委派 | Constrained Delegation | 服務只能代表使用者存取特定服務 | 高 |

本文會依序介紹這三種機制，但**實務上只建議使用受限委派**。

### 思考題

<details>
<summary>Q1：為什麼不能讓 Web App 儲存使用者密碼來解決這個問題？</summary>

**這違反了最小權限原則，且增加了攻擊面。**

如果 Web App 儲存使用者密碼：
1. **攻擊面擴大**：攻擊者入侵 Web App 就能取得所有使用者密碼
2. **違反職責分離**：Web App 只需要「代表使用者」，不需要「成為使用者」
3. **密碼管理複雜**：密碼更新時 Web App 要同步更新

Kerberos 委派的設計原則是：**服務只取得代表使用者存取特定資源的能力，而不是使用者的認證憑據**。

</details>

<details>
<summary>Q2：「代表使用者」和「偽裝成使用者」有什麼差異？</summary>

**關鍵差異在於可稽核性和授權範圍。**

| 面向 | 代表使用者（Delegation） | 偽裝成使用者（Impersonation） |
|---|---|---|
| 身份識別 | 資料庫知道「Web App 代表 Alice」 | 資料庫以為「就是 Alice 本人」 |
| 稽核紀錄 | 可追蹤到 Web App 是代理人 | 無法區分 |
| 授權範圍 | 可限制只能存取特定服務 | 等同於擁有使用者完整權限 |

在 Kerberos 術語中，Delegation 產生的 Ticket 會標記原始請求者（Alice）和代理服務（Web App），讓後端服務能夠完整稽核。

</details>

## TGT 轉發：最簡單但最危險的方式

這是最早期的委派方式，概念直接：**使用者把自己的 TGT 交給服務**。

### 運作原理

```
1. Alice 取得自己的 TGT（可轉發）
   kinit -f alice  # -f = forwardable

2. Alice 連線到 Web App，並轉發 TGT
   └── SSH/HTTP 連線時，可設定 GSSAPIDelegateCredentials yes

3. Web App 收到 Alice 的 TGT
   └── 可以用這張 TGT 向 TGS 請求任何服務的 Ticket

4. Web App 用 Alice 的 TGT 取得資料庫的 Service Ticket
   └── 資料庫看到的是「Alice」在請求
```

### 為什麼危險？

TGT 是 Kerberos 中最敏感的憑據——擁有 TGT 就等於擁有使用者身份。

```
如果 Web App 被入侵：
    攻擊者取得所有轉發過來的 TGT
    ├── 可以存取任何服務（不只資料庫）
    ├── 可以存取任何資料（不只 Web App 需要的）
    └── 可以維持存取直到 TGT 過期（通常 10 小時）
```

這就像你把家裡所有鑰匙都給了快遞員，只因為他需要進你家簽收包裹。

### 實際設定（僅供理解，不建議使用）

**Client 端**

```bash
# 取得可轉發的 TGT
kinit -f alice

# 確認 Ticket 有 Forwardable 旗標
klist -f
# Flags: FIA  ← F = Forwardable
```

**SSH 設定**

```
# ~/.ssh/config
Host webserver.lab.example.com
    GSSAPIDelegateCredentials yes
```

當 SSH 連線時，Client 會將 TGT 轉發給 Server。

### 思考題

<details>
<summary>Q1：如果 TGT 被轉發到 Web App，Web App 重啟後 TGT 還在嗎？</summary>

**取決於 TGT 的儲存方式，但通常不會持久保存。**

轉發的 TGT 通常存在記憶體中（如 KCM 或行程的 credential cache）。當 Web App 重啟：
- 記憶體中的 TGT 消失
- 使用者需要重新認證並轉發 TGT

這反而是一個小優點——限制了 TGT 洩露後的可利用時間。但這不足以彌補 TGT 轉發的根本安全問題。

</details>

<details>
<summary>Q2：為什麼 SSH 預設是 GSSAPIDelegateCredentials no？</summary>

**因為大多數情況下，使用者不需要在遠端機器代表自己存取其他服務。**

SSH 的主要用途是登入遠端機器操作。只有在特定情況（如從跳板機存取其他內部服務）才需要委派。

預設關閉委派符合「預設安全」原則——如果使用者不知道自己在做什麼，至少不會不小心把 TGT 交給不信任的機器。

</details>

## 無限制委派（Unconstrained Delegation）

這是 Windows 2000 引入的委派機制，比 TGT 轉發稍微結構化，但安全性同樣堪憂。

### 運作原理

無限制委派的核心概念是：**標記某個服務帳號「可以代表任何使用者存取任何服務」**。

```
1. 管理員將 Web App 的服務帳號設為「Trusted for Delegation」

2. 當使用者向 Web App 認證時：
   - KDC 發現 Web App 被信任委派
   - 自動在 Service Ticket 中夾帶使用者的 TGT

3. Web App 收到 Service Ticket，從中取出使用者的 TGT

4. Web App 可用這個 TGT 存取任何服務
```

### 與 TGT 轉發的差異

| 面向 | TGT 轉發 | 無限制委派 |
|---|---|---|
| TGT 來源 | 使用者主動轉發 | KDC 自動夾帶 |
| 使用者控制 | 可以選擇不轉發 | 無法控制（只要連上就會被委派） |
| 設定位置 | Client 端 | Server 端（服務帳號屬性） |

### 為什麼仍然危險？

無限制委派的問題和 TGT 轉發相同：**服務取得完整的 TGT，可以存取任何資源**。

更糟的是：
- 使用者可能不知道自己的 TGT 被轉發了
- 高權限帳號（如 Domain Admin）連上這台機器時，TGT 會被收集

這個攻擊手法在滲透測試中很常見——找到一台設定了無限制委派的機器，誘使 Domain Admin 連上，就能取得其 TGT。

### FreeIPA 中的無限制委派

FreeIPA 也支援無限制委派，但預設不啟用：

```bash
# 啟用無限制委派（不建議）
ipa service-mod HTTP/webapp.lab.example.com --ok-as-delegate=true
```

`ok-as-delegate` 旗標告訴 Client：「這個服務可以被委派，你可以把 TGT 給它」。

### 思考題

<details>
<summary>Q1：為什麼 KDC 會「自動」把使用者的 TGT 夾帶給被信任委派的服務？</summary>

**這是為了讓委派對使用者透明——使用者不需要特別操作就能享受 SSO。**

設計假設是：如果管理員信任某個服務可以委派，那使用者連上時就應該自動提供委派所需的 TGT。這簡化了使用者體驗。

問題在於這個假設太樂觀。管理員可能不完全理解「Trusted for Delegation」的含義，或者服務被入侵後這個信任就變成漏洞。

現代最佳實踐是避免使用無限制委派，改用受限委派。

</details>

<details>
<summary>Q2：如何偵測環境中是否有無限制委派的服務？</summary>

**可以透過 LDAP 查詢或 FreeIPA 命令列舉。**

在 FreeIPA 中：
```bash
# 列出所有啟用 ok-as-delegate 的服務
ipa service-find --ok-as-delegate=true
```

在 Active Directory 中：
```powershell
# 查詢 TRUSTED_FOR_DELEGATION 旗標
Get-ADComputer -Filter {TrustedForDelegation -eq $true}
Get-ADUser -Filter {TrustedForDelegation -eq $true}
```

這是滲透測試和安全稽核的常見檢查項目。發現無限制委派的服務應該評估是否能改為受限委派。

</details>

## 受限委派（Constrained Delegation）

這是目前推薦的委派方式，核心改進是：**限制服務只能代表使用者存取特定的後端服務**。

### 設計原則

```
無限制委派：Web App 拿到 TGT → 可以存取任何服務
受限委派：Web App 只能代表使用者存取「資料庫」

如果 Web App 被入侵：
├── 無限制委派：攻擊者可以用收集的 TGT 存取任何資源
└── 受限委派：攻擊者只能存取「資料庫」，其他服務無法觸及
```

這符合最小權限原則——Web App 只需要存取資料庫，就只給它存取資料庫的權限。

### 運作原理：S4U2Proxy

受限委派使用 **S4U2Proxy**（Service for User to Proxy）協議：

```
1. Alice 向 Web App 認證，取得 Service Ticket (ST1)
   └── ST1 是給 HTTP/webapp 的 Ticket

2. Web App 向 KDC 請求「代表 Alice」存取資料庫
   └── TGS-REQ 包含：
       - ST1（證明 Alice 認證過）
       - 目標服務：postgres/db.lab.example.com

3. KDC 檢查：
   ├── Web App 是否被允許委派？
   ├── 目標服務是否在允許清單中？
   └── Alice 是否允許被委派？

4. 如果都通過，KDC 發放 ST2
   └── ST2 是給 postgres/db 的 Ticket，但「代表 Alice」

5. Web App 用 ST2 連線資料庫
   └── 資料庫看到「Alice（透過 Web App）」
```

關鍵差異：**Web App 從未取得 Alice 的 TGT，只取得特定服務的 Service Ticket**。

### 在 FreeIPA 中設定受限委派

**步驟 1：建立委派規則**

```bash
# 建立一個委派規則
ipa servicedelegationrule-add webapp-to-db
```

**步驟 2：指定哪個服務可以委派**

```bash
# 將 Web App 的服務 Principal 加入規則
ipa servicedelegationrule-add-member webapp-to-db \
    --principals=HTTP/webapp.lab.example.com
```

**步驟 3：建立目標清單**

```bash
# 建立目標服務清單
ipa servicedelegationtarget-add db-services

# 加入允許被存取的服務
ipa servicedelegationtarget-add-member db-services \
    --principals=postgres/db.lab.example.com
```

**步驟 4：連結規則和目標**

```bash
# 設定規則的目標
ipa servicedelegationrule-add-target webapp-to-db \
    --servicedelegationtargets=db-services
```

**驗證設定**

```bash
# 檢視規則
ipa servicedelegationrule-show webapp-to-db

# 預期輸出
Rule name: webapp-to-db
  Allowed to perform delegation: HTTP/webapp.lab.example.com@LAB.EXAMPLE.COM
  Delegation targets: db-services
```

### 在 Web App 中使用委派

以 Python 為例，使用 `gssapi` 函式庫：

```python
import gssapi

# 1. Web App 已經驗證使用者身份，取得 client_ctx（認證上下文）
# 這個上下文包含使用者的 Service Ticket

# 2. 取得使用者的委派憑據
delegated_creds = client_ctx.delegated_creds

# 3. 用委派憑據連線資料庫
db_ctx = gssapi.SecurityContext(
    name=gssapi.Name("postgres/db.lab.example.com"),
    creds=delegated_creds,
    usage="initiate"
)

# 4. 進行 GSSAPI 握手，取得連線 Token
token = db_ctx.step()

# 5. 將 token 傳給資料庫完成認證
```

### 思考題

<details>
<summary>Q1：受限委派中，如果 Web App 嘗試存取不在允許清單中的服務會發生什麼？</summary>

**KDC 會拒絕發放 Service Ticket，回傳錯誤。**

```
$ kinit -k -t /etc/httpd/http.keytab HTTP/webapp.lab.example.com
$ kvno -U alice ldap/other-server.lab.example.com

kvno: KDC policy rejects request while getting credentials for
      ldap/other-server.lab.example.com@LAB.EXAMPLE.COM
```

這就是受限委派的價值——即使 Web App 被入侵，攻擊者也無法用收集到的憑據存取未授權的服務。

錯誤碼通常是 `KDC_ERR_BADOPTION` 或 `KDC_ERR_POLICY`，表示違反委派政策。

</details>

<details>
<summary>Q2：S4U2Proxy 中的 ST1 有什麼作用？為什麼需要它？</summary>

**ST1 證明「使用者確實向這個服務認證過」。**

這是重要的安全檢查：

```
沒有 ST1 的情況（假設）：
  Web App：「我要代表 Alice 存取資料庫」
  KDC：「Alice 有授權你這樣做嗎？」
  Web App：「呃...信任我？」

有 ST1 的情況：
  Web App：「我要代表 Alice 存取資料庫，這是 Alice 給我的 Ticket（ST1）」
  KDC：「讓我驗證這張 Ticket...確實是 Alice 發給你的，批准」
```

ST1 中包含：
- Alice 的身份（Principal Name）
- 時間戳記（確認是近期的認證）
- 加密保護（無法偽造）

這確保 Web App 只能代表「實際連上來的使用者」，而不能憑空捏造。

</details>

<details>
<summary>Q3：使用者可以禁止自己被委派嗎？</summary>

**可以，透過設定 Principal 的「not delegated」旗標。**

在 FreeIPA 中：
```bash
# 禁止 alice 被任何服務委派
ipa user-mod alice --ok-as-delegate=false
```

實際上是設定 Kerberos Principal 的旗標。當 KDC 處理 S4U2Proxy 請求時，會檢查使用者是否允許被委派。

這對高權限帳號特別重要：
- Domain Admin 帳號應該禁止被委派
- 服務帳號通常也不需要被委派

預設情況下，使用者是允許被委派的。

</details>

## Protocol Transition：處理非 Kerberos 認證

受限委派還有一個進階功能：**S4U2Self**（Protocol Transition），用於處理使用者不是透過 Kerberos 認證的情況。

### 問題情境

考慮這個情況：

```
使用者 ─(表單登入)─► Web App ─(需要Kerberos)─► 資料庫
         ↑
         └── 沒有 Kerberos，只有帳號密碼
```

使用者透過表單（帳號密碼）登入 Web App，沒有 Kerberos Ticket。但 Web App 仍然需要用 Kerberos 存取資料庫。

S4U2Proxy 需要 ST1 作為證明，但使用者沒有提供任何 Kerberos 憑據。

### S4U2Self 的解法

**S4U2Self** 允許服務「為使用者取得一張給自己的 Ticket」：

```
1. Web App 驗證使用者身份（透過表單、LDAP、或其他方式）

2. Web App 向 KDC 請求「為 Alice 取得一張 Ticket 給我自己」
   └── TGS-REQ 包含：
       - Web App 的 keytab（證明自己身份）
       - 使用者名稱：alice

3. KDC 檢查 Web App 是否被允許進行 Protocol Transition

4. 如果允許，KDC 發放「Alice 給 Web App」的 Service Ticket
   └── 這張 Ticket 就等同於 S4U2Proxy 需要的 ST1

5. Web App 用這張 Ticket 進行 S4U2Proxy，取得資料庫的 Ticket
```

### 安全考量

S4U2Self 的權限很大——服務可以「宣稱」使用者已經認證，即使使用者從未透過 Kerberos 驗證。

因此需要額外的安全控制：

```bash
# 在 FreeIPA 中，需要明確允許 Protocol Transition
ipa servicedelegationrule-mod webapp-to-db --allow-s4u2self=true
```

**使用 S4U2Self 的場景**
- 從非 Kerberos 認證轉換（表單登入、OAuth、SAML）
- 排程任務需要以使用者身份執行
- 遺留系統整合

**不適合的場景**
- 使用者可以透過 Kerberos 認證的情況（直接用 S4U2Proxy 更安全）
- 不需要使用者身份的操作（直接用服務帳號）

### 思考題

<details>
<summary>Q1：S4U2Self 有什麼濫用風險？</summary>

**被允許 S4U2Self 的服務可以偽裝成任何使用者。**

如果 Web App 被入侵，攻擊者可以：
1. 使用 S4U2Self 為 Domain Admin 取得 Ticket
2. 用這張 Ticket 進行 S4U2Proxy
3. 以 Domain Admin 身份存取資料庫

防範措施：
- 只在必要時啟用 S4U2Self
- 高權限帳號設定「not delegated」旗標
- 監控 S4U2Self 請求的稽核日誌

</details>

<details>
<summary>Q2：S4U2Self 產生的 Ticket 和使用者真正認證產生的 Ticket 有什麼不同？</summary>

**S4U2Self 產生的 Ticket 會被標記為「非互動認證」。**

```
使用者認證產生的 Ticket:
  Flags: FIA  (Initial = 使用者親自認證)

S4U2Self 產生的 Ticket:
  Flags: FA   (沒有 Initial 旗標)
```

這讓後端服務可以區分：
- 使用者親自認證 vs 被服務代表
- 可以對 S4U2Self 產生的請求套用額外限制

但要注意：許多服務不會檢查這個旗標，所以這不是可靠的安全邊界。

</details>

## 實戰演練：Web App 委派存取 PostgreSQL

現在來實作一個完整的範例：設定 Apache + mod_auth_gssapi 透過受限委派存取 PostgreSQL。

### 環境準備

| 角色 | Hostname | 服務 |
|---|---|---|
| Web Server | webapp.lab.example.com | Apache + mod_auth_gssapi |
| Database | db.lab.example.com | PostgreSQL |
| IPA Server | ipa.lab.example.com | FreeIPA |

### 步驟 1：建立服務 Principal

```bash
# 在 IPA Server 上
kinit admin

# 建立 Web App 的服務 Principal
ipa service-add HTTP/webapp.lab.example.com

# 建立 PostgreSQL 的服務 Principal
ipa service-add postgres/db.lab.example.com
```

### 步驟 2：產生 Keytab

```bash
# 在 webapp.lab.example.com 上
sudo ipa-getkeytab -s ipa.lab.example.com \
    -p HTTP/webapp.lab.example.com \
    -k /etc/httpd/http.keytab

sudo chown apache:apache /etc/httpd/http.keytab
sudo chmod 600 /etc/httpd/http.keytab

# 在 db.lab.example.com 上
sudo ipa-getkeytab -s ipa.lab.example.com \
    -p postgres/db.lab.example.com \
    -k /var/lib/pgsql/data/postgres.keytab

sudo chown postgres:postgres /var/lib/pgsql/data/postgres.keytab
sudo chmod 600 /var/lib/pgsql/data/postgres.keytab
```

### 步驟 3：設定受限委派規則

```bash
# 建立委派規則
ipa servicedelegationrule-add http-to-postgres

# 加入 Web App 作為委派者
ipa servicedelegationrule-add-member http-to-postgres \
    --principals=HTTP/webapp.lab.example.com

# 建立目標清單
ipa servicedelegationtarget-add postgres-target

# 加入 PostgreSQL 作為目標
ipa servicedelegationtarget-add-member postgres-target \
    --principals=postgres/db.lab.example.com

# 連結規則和目標
ipa servicedelegationrule-add-target http-to-postgres \
    --servicedelegationtargets=postgres-target
```

### 步驟 4：設定 PostgreSQL

編輯 `/var/lib/pgsql/data/pg_hba.conf`：

```
# Kerberos GSSAPI 認證
hostgssenc all all 0.0.0.0/0 gss include_realm=0
```

編輯 `/var/lib/pgsql/data/postgresql.conf`：

```
# 啟用 GSSAPI
krb_server_keyfile = '/var/lib/pgsql/data/postgres.keytab'
```

重啟 PostgreSQL：

```bash
sudo systemctl restart postgresql
```

### 步驟 5：設定 Apache

安裝必要模組：

```bash
sudo dnf install -y mod_auth_gssapi
```

編輯 `/etc/httpd/conf.d/webapp.conf`：

```apache
<Location "/app">
    AuthType GSSAPI
    AuthName "Kerberos Login"
    GssapiCredStore keytab:/etc/httpd/http.keytab
    GssapiDelegCcacheDir /run/httpd/clientcaches
    GssapiDelegCcacheUnique on
    Require valid-user
</Location>
```

關鍵設定說明：

| 設定 | 說明 |
|---|---|
| `GssapiDelegCcacheDir` | 儲存委派憑據的目錄 |
| `GssapiDelegCcacheUnique` | 每個使用者使用獨立的憑據快取 |

建立目錄並設定權限：

```bash
sudo mkdir /run/httpd/clientcaches
sudo chown apache:apache /run/httpd/clientcaches
sudo chmod 700 /run/httpd/clientcaches
sudo systemctl restart httpd
```

### 步驟 6：Web App 使用委派憑據

以 Python CGI 為例：

```python
#!/usr/bin/env python3
import os
import psycopg2

# mod_auth_gssapi 會設定這個環境變數
# 指向使用者的委派憑據快取
ccache_path = os.environ.get('KRB5CCNAME')

if ccache_path:
    # 設定 Kerberos 使用這個憑據快取
    os.environ['KRB5CCNAME'] = ccache_path

    # 使用 GSSAPI 連線 PostgreSQL
    conn = psycopg2.connect(
        host='db.lab.example.com',
        database='myapp',
        # 使用 GSSAPI 認證，不需要密碼
    )

    # 執行查詢
    cur = conn.cursor()
    cur.execute("SELECT current_user;")
    user = cur.fetchone()[0]

    print(f"Content-Type: text/html\n")
    print(f"<h1>Connected as: {user}</h1>")
else:
    print("Content-Type: text/html\n")
    print("<h1>No delegation credentials available</h1>")
```

### 步驟 7：驗證

```bash
# 取得 TGT
kinit alice

# 存取 Web App（瀏覽器需設定 Negotiate 認證）
curl --negotiate -u : https://webapp.lab.example.com/app/

# 預期輸出
<h1>Connected as: alice</h1>
```

檢查資料庫的連線：

```sql
-- 在 PostgreSQL 中查看目前連線
SELECT usename, client_addr, application_name
FROM pg_stat_activity;

-- 應該看到 alice 的連線
```

### 思考題

<details>
<summary>Q1：為什麼需要 GssapiDelegCcacheDir？直接用記憶體中的憑據不行嗎？</summary>

**因為 Apache 是多行程架構，需要將憑據持久化以供 CGI/後端程式使用。**

Apache 的處理流程：
1. 連線處理程序完成 GSSAPI 認證
2. 需要將委派憑據傳遞給後端程式（CGI、mod_wsgi 等）
3. 環境變數只能傳字串，無法傳記憶體中的憑據

解決方案是將憑據存到檔案，然後透過 `KRB5CCNAME` 環境變數告訴後端程式去哪裡讀取。

`GssapiDelegCcacheUnique` 確保每個使用者使用獨立檔案，避免憑據混用。

</details>

<details>
<summary>Q2：如果 alice 的 Ticket 過期了，會發生什麼？</summary>

**Web App 的委派請求會失敗，需要使用者重新認證。**

委派憑據的有效期不會超過原始 Ticket 的有效期。當 Alice 的 TGT 過期：
1. 儲存在 `GssapiDelegCcacheDir` 的憑據也過期
2. Web App 嘗試使用過期憑據連線資料庫
3. 資料庫拒絕認證（錯誤：`Ticket expired`）

解決方案：
- 設定較長的 Ticket 有效期（權衡安全性）
- 使用者使用 `kinit -R` 續期 Ticket
- 應用程式處理認證失敗，引導使用者重新登入

</details>

## 委派安全最佳實踐

### 選擇正確的委派類型

| 情境 | 建議 |
|---|---|
| 只需存取特定後端服務 | 受限委派 |
| 需要存取多種後端服務 | 受限委派 + 多個目標 |
| 遺留系統無法支援 Kerberos | S4U2Self + 受限委派 |
| 需要完整使用者身份 | **避免委派**，考慮其他方案 |

### 保護高權限帳號

```bash
# 禁止 admin 帳號被委派
ipa user-mod admin --ok-as-delegate=false

# 禁止服務帳號被委派
ipa user-mod svc_backup --ok-as-delegate=false
```

### 監控與稽核

FreeIPA 和 Kerberos 都會記錄委派相關事件：

```bash
# 檢視 KDC 日誌
sudo journalctl -u krb5kdc -f

# 搜尋委派相關紀錄
sudo grep -i "s4u" /var/log/krb5kdc.log
```

重要的稽核事件：
- S4U2Self 請求（誰在為誰取得 Ticket）
- S4U2Proxy 請求（誰在代表誰存取什麼服務）
- 委派失敗事件（可能是攻擊嘗試）

### 定期審查委派規則

```bash
# 列出所有委派規則
ipa servicedelegationrule-find

# 檢視特定規則的詳細資訊
ipa servicedelegationrule-show webapp-to-db
```

## 疑難排解

### 問題 1：KDC_ERR_BADOPTION

```
kinit: KDC policy rejects request while getting credentials
```

**原因**：委派規則不存在或設定錯誤。

**檢查步驟**：

```bash
# 確認委派規則存在
ipa servicedelegationrule-show webapp-to-db

# 確認服務 Principal 在規則中
ipa servicedelegationrule-show webapp-to-db | grep "Allowed to perform"

# 確認目標服務在清單中
ipa servicedelegationtarget-show postgres-target
```

### 問題 2：Ticket 中沒有 forwardable 旗標

受限委派需要使用者的 Service Ticket 是 forwardable 的。

```bash
# 檢查使用者的 Ticket
klist -f

# 如果沒有 F 旗標，重新取得
kinit -f alice
```

### 問題 3：憑據快取權限問題

```
GSSAPI Error: Credentials cache file permissions incorrect
```

**解決方案**：

```bash
# 確認目錄權限
ls -la /run/httpd/clientcaches

# 應該是 apache:apache，權限 700
sudo chown apache:apache /run/httpd/clientcaches
sudo chmod 700 /run/httpd/clientcaches
```

### 開啟 Debug 模式

```bash
# Kerberos 詳細日誌
export KRB5_TRACE=/tmp/krb5.log

# GSSAPI 詳細日誌
export GSSAPI_DEBUG=1
```

## 總結

在這篇文章中，我們學習了：

1. **委派的核心概念**
   - 服務代表使用者存取其他服務
   - 解決三層式架構中的身份傳遞問題

2. **三種委派機制**
   - TGT 轉發：最簡單但最危險
   - 無限制委派：結構化但仍危險
   - 受限委派：推薦使用，符合最小權限原則

3. **受限委派實作**
   - 使用 S4U2Proxy 協議
   - 在 FreeIPA 中設定委派規則和目標
   - 實作 Web App 委派存取資料庫

4. **Protocol Transition**
   - S4U2Self 處理非 Kerberos 認證
   - 安全考量和使用場景

5. **安全最佳實踐**
   - 保護高權限帳號
   - 監控和稽核
   - 定期審查委派規則

## Reference

- [MIT Kerberos Documentation - Constrained Delegation](https://web.mit.edu/kerberos/krb5-latest/doc/admin/s4u2proxy.html)
- [FreeIPA Documentation - Service Delegation](https://freeipa.readthedocs.io/en/latest/designs/service-constraint-delegation.html)
- [Microsoft - Kerberos Constrained Delegation Overview](https://docs.microsoft.com/en-us/windows-server/security/kerberos/kerberos-constrained-delegation-overview)
- [Red Hat - Configuring Kerberos Constrained Delegation](https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/9/html/configuring_and_managing_identity_management/)
