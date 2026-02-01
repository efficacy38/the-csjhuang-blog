---
title: Keycloak 與 FreeIPA 整合：User Federation 與 Writeback 機制
description: 深入理解 Keycloak 如何透過 LDAP User Federation 與 FreeIPA 整合，探討三種 Edit Mode 的差異、Writeback 機制的限制，以及實務上的最佳實踐
date: 2026-02-01
slug: keycloak-freeipa-user-federation
series: "freeipa"
tags:
    - "kerberos"
    - "keycloak"
    - "freeipa"
    - "authentication"
    - "note"
---

在上一篇文章中，我們使用 FreeIPA 建立了完整的 Kerberos 環境。但在現代企業環境中，往往需要同時支援多種認證方式——Kerberos 用於內部桌面環境，而 Web 應用程式則需要 OAuth2/OIDC。這時就需要一個身份代理（Identity Broker）來整合這些不同的認證協議。

本文將介紹如何使用 **Keycloak** 作為身份代理，透過 **User Federation** 機制與 FreeIPA 整合，讓你的 Web 應用程式能夠使用 FreeIPA 中的使用者帳號。

:::note
**本文假設你已閱讀過 Kerberos 入門指南**，了解 Kerberos 的基本概念（KDC、TGT、Service Ticket 等）。如果你對 Kerberos 還不熟悉，建議先閱讀系列的第一篇文章。
:::

## 術語速查

本文會用到一些身份管理領域的專有名詞，這裡先簡單介紹：

| 術語 | 說明 |
|---|---|
| **FreeIPA** | Red Hat 開發的開源身份管理平台，整合了 Kerberos（認證）和 LDAP（使用者資料儲存） |
| **Keycloak** | Red Hat 開發的開源身份代理（Identity Provider），提供 SSO 和多種認證協議支援 |
| **LDAP** | Lightweight Directory Access Protocol，一種用來查詢和管理使用者資料的協議，類似一個專門存放使用者資訊的資料庫 |
| **OAuth2/OIDC** | 現代 Web 應用程式常用的授權/認證協議。OAuth2 處理「授權」（允許應用程式存取資源），OIDC 在 OAuth2 之上加入「認證」（確認使用者身份） |
| **SSO** | Single Sign-On（單一登入），使用者只需登入一次，就能存取多個系統 |
| **IdP** | Identity Provider（身份提供者），負責驗證使用者身份並發放認證憑證的服務 |
| **MFA** | Multi-Factor Authentication（多因素認證），除了密碼外還需要其他驗證方式（如手機 OTP） |

## 先從一個問題開始

想像你是一家公司的 IT 管理員，公司已經使用 FreeIPA 管理所有員工的帳號——員工用 Kerberos SSO 登入 Linux 工作站、存取內部服務。現在公司要導入一套新的 Web 應用程式（例如 GitLab、Grafana、或自行開發的系統），這些應用程式使用 OAuth2/OIDC 進行認證。

**你面臨的選擇：**

| 方案 | 做法 | 問題 |
|---|---|---|
| 各自管理 | 在每個 Web 應用程式建立獨立帳號 | 員工要記多組密碼，離職時要各別停用 |
| 直接連 LDAP | 每個應用程式直接連 FreeIPA 的 LDAP | 每個應用程式都要設定 LDAP，無法統一控制存取政策 |
| 身份代理 | 用 Keycloak 整合 FreeIPA，應用程式只連 Keycloak | 統一管理、支援多種協議、可設定細緻的存取控制 |

**身份代理**是目前業界的主流做法。Keycloak 作為中間層，對內連接 FreeIPA（透過 LDAP），對外提供 OAuth2/OIDC 給 Web 應用程式。

```
┌───────────────────────────────────────────────────────────────────┐
│                        企業身份架構                               │
├───────────────────────────────────────────────────────────────────┤
│                                                                   │
│  ┌──────────────┐                                                 │
│  │   FreeIPA    │ ◄─── 使用者帳號的「唯一真實來源」               │
│  │ (Kerberos +  │      (Single Source of Truth)                   │
│  │    LDAP)     │                                                 │
│  └──────┬───────┘                                                 │
│         │                                                         │
│         │ LDAP User Federation                                    │
│         │ (同步使用者資料)                                        │
│         ▼                                                         │
│  ┌──────────────┐                                                 │
│  │   Keycloak   │ ◄─── 身份代理 (Identity Broker)                 │
│  │   (IdP)      │      提供 OAuth2/OIDC/SAML                      │
│  └──────┬───────┘                                                 │
│         │                                                         │
│         │ OAuth2 / OIDC                                           │
│         ▼                                                         │
│  ┌────────────────────────────────────────────────────┐           │
│  │                 Web 應用程式                       │           │
│  │  ┌────────┐  ┌────────┐  ┌────────┐  ┌─────────┐  │           │
│  │  │ GitLab │  │Grafana │  │ Jira   │  │ 自建App │  │           │
│  │  └────────┘  └────────┘  └────────┘  └─────────┘  │           │
│  └────────────────────────────────────────────────────┘           │
│                                                                   │
└───────────────────────────────────────────────────────────────────┘
```

## 核心概念

在進入實作之前，先介紹幾個重要的概念。

### User Federation（使用者聯合）

**User Federation** 是 Keycloak 的一個功能，允許 Keycloak 從外部身份儲存（如 LDAP、Active Directory）取得使用者資訊，而不是在 Keycloak 自己的資料庫中管理使用者。

用生活比喻：

```
User Federation = 代理商

FreeIPA 是原廠（擁有所有員工資料）
Keycloak 是代理商（從原廠取得資料，提供給下游客戶）
Web 應用程式是下游客戶（從代理商取得資料）

代理商（Keycloak）不需要自己生產商品（使用者帳號），
只需要從原廠（FreeIPA）進貨，然後轉賣給客戶。
```

### 為什麼需要 User Federation？

| 不用 Federation | 用 Federation |
|---|---|
| Keycloak 維護獨立的使用者資料庫 | Keycloak 從 FreeIPA 取得使用者資料 |
| 使用者資料在兩邊要手動同步 | 自動同步，FreeIPA 是唯一來源 |
| 員工入職/離職要操作兩個系統 | 只需操作 FreeIPA |
| 密碼可能不同步 | 密碼驗證委派給 FreeIPA |

### Import vs No-Import 模式

Keycloak 的 User Federation 有兩種運作模式：

**Import 模式（預設）**

```
FreeIPA LDAP ──同步──► Keycloak DB ──查詢──► Keycloak
                           │
                           └── 使用者資料存一份在 Keycloak 資料庫
```

- 使用者資料會複製一份到 Keycloak 的資料庫（但**密碼不會複製**）
- 複製的資料：使用者名稱、email、姓名、群組成員等**屬性資訊**
- 不複製的資料：密碼（每次登入仍向 LDAP 驗證）
- 優點：效能較好（查詢不需連 LDAP）、可離線運作
- 缺點：需要同步機制、可能有資料不一致的問題

:::note
**「Import」不代表「取代」**——即使資料被匯入 Keycloak，FreeIPA 仍是「唯一真實來源」。Keycloak 的本地資料只是快取，透過同步機制保持更新。
:::

**No-Import 模式**

```
FreeIPA LDAP ◄──即時查詢──► Keycloak
                               │
                               └── 每次都直接查 LDAP
```

- 使用者資料不存在 Keycloak，每次都即時查詢 LDAP
- 優點：資料即時、沒有同步問題
- 缺點：效能較差、依賴 LDAP 可用性

### 思考題

<details>
<summary>Q1：User Federation 和直接讓應用程式連 LDAP 有什麼不同？</summary>

**關鍵差異在於協議轉換和統一管理。**

直接連 LDAP：
- 每個應用程式都要支援 LDAP 認證
- 每個應用程式都要設定 LDAP 連線資訊
- 難以實作細緻的存取控制（哪些使用者可以存取哪些應用程式）
- 難以加入額外的認證因素（如 MFA）

透過 Keycloak User Federation：
- 應用程式只需支援 OAuth2/OIDC（現代標準）
- 統一在 Keycloak 設定 LDAP 連線
- 可在 Keycloak 設定應用程式層級的存取控制
- 可在 Keycloak 統一啟用 MFA

簡單說：**User Federation 讓 Keycloak 負責和 LDAP 溝通，應用程式只需和 Keycloak 溝通**。

</details>

<details>
<summary>Q2：為什麼密碼驗證要委派給 FreeIPA，而不是同步密碼到 Keycloak？</summary>

**因為密碼是敏感資料，多一份複製就多一份風險。**

如果同步密碼到 Keycloak：
- Keycloak 資料庫被入侵 = 密碼外洩
- 需要同步密碼 hash（格式可能不相容）
- 密碼變更時需要即時同步

委派驗證給 FreeIPA：
- 密碼只存在 FreeIPA（單一來源）
- Keycloak 只問「這個密碼對不對」，不知道密碼是什麼
- 密碼變更即時生效（不需同步）

這也是為什麼 Keycloak 即使在 Import 模式下，也不會匯入密碼。

</details>

## Edit Mode：三種資料同步策略

當 Keycloak 與 FreeIPA 整合時，最重要的設定之一是 **Edit Mode**——決定資料如何在兩個系統之間流動。

### READ_ONLY：唯讀模式

```
FreeIPA ──────────► Keycloak
         單向同步

FreeIPA 是主人，Keycloak 是觀察者
```

**行為：**
- 使用者資料從 FreeIPA 單向同步到 Keycloak
- 在 Keycloak 中無法修改使用者的 LDAP 屬性（名字、email 等）
- 密碼無法在 Keycloak 端更改

**適用場景：**
- FreeIPA 是唯一的使用者管理入口
- 不希望透過 Keycloak 修改 LDAP 資料
- 最安全的選項

### WRITABLE：可寫入模式

```
FreeIPA ◄───────────► Keycloak
          雙向同步

變更可以從任一端發起
```

**行為：**
- 使用者資料雙向同步
- 在 Keycloak 修改使用者屬性，會回寫到 FreeIPA
- 密碼更改會同步到 FreeIPA

**適用場景：**
- 需要讓使用者透過 Keycloak 更新自己的 profile
- 管理員需要透過 Keycloak Admin Console 管理使用者

**注意：** 這裡的「可寫入」主要指**修改現有使用者的屬性**，而非建立新使用者。新使用者的 writeback 有額外的限制，稍後會詳細說明。

### UNSYNCED：不同步模式

```
FreeIPA ──初始匯入──► Keycloak ──本地儲存──► Keycloak DB
                                   │
                                   └── 之後的變更只存在 Keycloak
```

**行為：**
- 使用者初始從 FreeIPA 匯入
- 之後在 Keycloak 的變更只存在 Keycloak 本地資料庫
- 不會回寫到 FreeIPA

**適用場景：**
- FreeIPA 的 LDAP 是唯讀的
- 需要在 Keycloak 擴充使用者屬性，但不影響 FreeIPA
- 測試環境

### 三種模式比較

| 面向 | READ_ONLY | WRITABLE | UNSYNCED |
|---|---|---|---|
| 資料流向 | FreeIPA → Keycloak | 雙向 | 初始匯入後分離 |
| 修改 LDAP 屬性 | ❌ | ✅ | ❌（存在本地） |
| 密碼更改 | ❌ 必須在 FreeIPA | ✅ 回寫到 FreeIPA | ❌ 存在 Keycloak |
| 資料一致性 | 高（單一來源） | 中（可能衝突） | 低（分離後各自管理） |
| 適合場景 | 生產環境 | 需要雙向同步 | 測試或特殊需求 |

### 思考題

<details>
<summary>Q1：如果選擇 WRITABLE 模式，兩邊同時修改同一個使用者會發生什麼？</summary>

**取決於同步時機，可能導致資料覆蓋。**

情境：
1. 管理員 A 在 FreeIPA 把 alice 的 email 改成 alice@new.com
2. 同時，管理員 B 在 Keycloak 把 alice 的 email 改成 alice@other.com
3. Keycloak 回寫到 FreeIPA

結果取決於誰最後寫入。這種競爭條件（race condition）可能導致：
- 資料不一致
- 其中一個變更被覆蓋

**最佳實踐：**
- 選擇一個主要的管理入口（通常是 FreeIPA）
- 在另一邊只做必要的修改
- 或者使用 READ_ONLY 避免衝突

</details>

<details>
<summary>Q2：UNSYNCED 模式下，如果使用者在 FreeIPA 改了密碼，Keycloak 會怎麼處理？</summary>

**密碼驗證仍然委派給 FreeIPA（透過 LDAP Bind），所以新密碼會立即生效。**

> **什麼是 LDAP Bind？** 在 LDAP 協議中，「Bind」是認證操作——Client 提供帳號密碼，LDAP Server 驗證是否正確。可以理解為「用帳號密碼登入 LDAP」。

UNSYNCED 模式的「不同步」是指**屬性資料**（名字、email 等），不影響認證流程：

1. alice 在 FreeIPA 改密碼為 `newpass`
2. alice 嘗試用 `newpass` 登入 Keycloak
3. Keycloak 用 alice 的帳號密碼向 FreeIPA 做 LDAP Bind（驗證密碼）
4. FreeIPA 驗證 `newpass` 正確 → 登入成功

這是因為 Keycloak 不儲存密碼，每次都向 LDAP 驗證。

例外：如果同時啟用了 Keycloak 的本地密碼（某些特殊設定），可能有不同行為。

</details>

## Sync Registrations：新使用者的 Writeback

**Sync Registrations** 是一個獨立的設定，控制是否將 Keycloak 建立的新使用者回寫到 LDAP。

```
Keycloak 建立新使用者 ──(Sync Registrations)──► FreeIPA LDAP
                              │
                              └── 預設是關閉的
```

### 為什麼需要獨立控制？

修改現有使用者和建立新使用者是不同層級的操作：

| 操作 | 影響 | 風險 |
|---|---|---|
| 修改現有使用者 | 更新 LDAP 屬性 | 低（使用者已存在） |
| 建立新使用者 | 在 LDAP 新增條目 | 高（需要正確的 objectClass 和必填屬性） |

### FreeIPA 的特殊挑戰

這裡要談到一個**重要的限制**：**在 WRITABLE 模式下，Keycloak 建立的新使用者無法正確同步到 FreeIPA**。

根據社群討論，問題在於 FreeIPA 對使用者條目有嚴格的要求：

> **什麼是 objectClass？** 在 LDAP 中，`objectClass` 定義了一個條目（entry）必須和可以擁有哪些屬性。類似程式設計中的「類別（class）」概念——`inetOrgPerson` 定義了一般使用者的屬性，`posixAccount` 定義了 Linux 系統帳號需要的屬性（UID、GID、home 目錄等）。FreeIPA 使用者需要同時符合多個 objectClass 的要求。

```
一般的 LDAP 使用者條目：
  objectClass: inetOrgPerson     # 基本使用者資訊
  uid: alice
  cn: Alice Chen
  sn: Chen
  mail: alice@example.com
  # 大約 5-10 個屬性

FreeIPA 的使用者條目：
  objectClass: inetOrgPerson     # 基本使用者資訊
  objectClass: posixAccount      # Linux 系統帳號（UID、GID、home）
  objectClass: krbPrincipalAux   # Kerberos 認證資訊
  objectClass: ipaObject         # FreeIPA 專屬屬性
  # ... 還有更多 objectClass
  uid: alice
  uidNumber: 686600001           # Linux UID
  gidNumber: 686600001           # Linux GID
  homeDirectory: /home/alice
  loginShell: /bin/bash
  krbPrincipalName: alice@LAB.EXAMPLE.COM  # Kerberos Principal
  ipaUniqueID: a1b2c3d4-...      # FreeIPA 內部 ID
  # 40+ 個屬性！
```

Keycloak 預設的 LDAP Mapper 只會設定基本屬性，無法滿足 FreeIPA 的要求。結果是：

1. Keycloak 顯示「使用者建立成功」
2. LDAP 操作實際上失敗（或部分成功）
3. FreeIPA 中找不到這個使用者
4. 但如果你嘗試在 FreeIPA 建立同名使用者，會說「已存在」

### 實務建議

對於 FreeIPA 整合，**建議關閉 Sync Registrations**：

```
✅ 推薦做法：
   FreeIPA 負責建立使用者
   Keycloak 只負責同步和認證

❌ 不推薦：
   透過 Keycloak 建立使用者並回寫 FreeIPA
   （需要大量自訂 Mapper，且容易出錯）
```

如果真的需要在 Keycloak 端建立使用者，考慮：
- 使用 UNSYNCED 模式（使用者只存在 Keycloak）
- 或透過 FreeIPA API 建立使用者，而非 LDAP 直接寫入

### 思考題

<details>
<summary>Q1：為什麼 Keycloak 顯示「使用者建立成功」但 FreeIPA 看不到？</summary>

**因為 Keycloak 使用 Import 模式時，會同時寫入本地資料庫。**

流程：
1. Keycloak 嘗試在 LDAP 建立使用者
2. LDAP 操作失敗（缺少必要屬性）
3. 但 Keycloak 已經在本地資料庫建立了使用者記錄
4. Keycloak 回報「成功」（因為本地操作成功了）

這是一個設計問題——Keycloak 應該在 LDAP 操作失敗時回滾本地操作，但實際行為並非如此。

解決方案是檢查 Keycloak 的日誌，會看到類似：
```
LDAP: error code 65 - object class violation
LDAP: error code 21 - missing attribute
```

</details>

<details>
<summary>Q2：Active Directory 整合有同樣的 Writeback 問題嗎？</summary>

**AD 的問題較少，但仍有限制。**

Active Directory vs FreeIPA：

| 面向 | Active Directory | FreeIPA |
|---|---|---|
| 必填屬性 | 相對較少 | 非常多（40+） |
| Keycloak 內建支援 | 有專門的 AD Mapper | 使用通用 LDAP Mapper |
| Writeback 相容性 | 較好 | 較差 |

Keycloak 有 `msad-user-account-mapper` 專門處理 AD 的特殊屬性（如帳號狀態、密碼過期）。但對 FreeIPA 沒有類似的專門支援。

這也是社群抱怨的原因：「FreeIPA 和 Keycloak 都是 Red Hat 的產品，但整合度卻不如 AD。」

</details>

## LDAP Mappers：屬性對應

**LDAP Mapper** 定義了 LDAP 屬性如何對應到 Keycloak 的使用者屬性。

可以把 Mapper 想像成一張「翻譯對照表」：

```
LDAP 世界                    Keycloak 世界
─────────                   ──────────────
uid          ─────────────►  username
mail         ─────────────►  email
givenName    ─────────────►  firstName
sn           ─────────────►  lastName
memberOf     ─────────────►  groups
```

沒有設定 Mapper 的 LDAP 屬性不會被同步到 Keycloak。

### 預設的 Mapper

當你建立 LDAP User Federation 時，Keycloak 會根據 Vendor（FreeIPA 選 Red Hat Directory Server）自動建立一組 Mapper：

| Mapper 名稱 | LDAP 屬性 | Keycloak 屬性 |
|---|---|---|
| username | uid | username |
| email | mail | email |
| first name | givenName | firstName |
| last name | sn | lastName |

### 常見的 Mapper 類型

**User Attribute Mapper**
- 一對一對應 LDAP 屬性和 Keycloak 屬性
- 例如：`telephoneNumber` → `phone`

**Full Name Mapper**
- 將 LDAP 的 `cn`（全名）拆分為 firstName 和 lastName
- FreeIPA 通常需要這個（因為 FreeIPA 用 `cn` 存全名）

**Group Mapper**
- 將 LDAP 群組對應到 Keycloak 群組
- 可設定群組的 DN 位置（如 `cn=groups,cn=accounts,dc=...`）

> **什麼是 DN？** DN（Distinguished Name）是 LDAP 中條目的「完整路徑」，類似檔案系統的絕對路徑。例如 `cn=alice,cn=users,cn=accounts,dc=example,dc=com` 表示 example.com 網域下、accounts 容器中、users 容器裡的 alice。

**Role Mapper**
- 將 LDAP 群組對應到 Keycloak 的角色（Role）
- 例如：LDAP 的 `admins` 群組 → Keycloak 的 `admin` 角色

> **Realm 和 Role 是什麼？** 在 Keycloak 中，**Realm** 是一個獨立的管理空間（類似租戶），每個 Realm 有自己的使用者、應用程式和設定。**Role** 是權限的集合，分為 Realm Role（全域角色）和 Client Role（特定應用程式的角色）。

### FreeIPA 特殊設定

對 FreeIPA 整合，需要注意以下設定：

**UUID LDAP Attribute**
- FreeIPA 使用 `ipaUniqueID` 而非標準的 `entryUUID`
- 需要手動修改這個設定

**Users DN**
- FreeIPA 的使用者位置：`cn=users,cn=accounts,dc=lab,dc=example,dc=com`

**Groups DN**
- FreeIPA 的群組位置：`cn=groups,cn=accounts,dc=lab,dc=example,dc=com`

### 思考題

<details>
<summary>Q1：如果 LDAP 中有一個屬性 Keycloak 不認識（如 FreeIPA 的 `krbPrincipalName`），會怎麼處理？</summary>

**未設定 Mapper 的屬性會被忽略。**

Keycloak 只會處理有 Mapper 定義的屬性。這代表：
- 使用者的 Kerberos Principal Name 不會被同步到 Keycloak
- 這通常沒問題，因為 Keycloak 有自己的身份識別系統

如果你需要這個屬性，可以：
1. 建立自訂 User Attribute Mapper
2. 將 `krbPrincipalName` 對應到 Keycloak 的自訂屬性

```
Mapper: kerberos-principal
LDAP Attribute: krbPrincipalName
User Model Attribute: kerberosPrincipal
Read Only: Yes
```

</details>

<details>
<summary>Q2：Group Mapper 的 Mode 設定（READ_ONLY / LDAP_ONLY / IMPORT）是什麼意思？</summary>

**這控制群組資訊如何在 LDAP 和 Keycloak 之間流動。**

| Mode | 行為 |
|---|---|
| READ_ONLY | 群組從 LDAP 單向同步到 Keycloak，無法在 Keycloak 修改 |
| LDAP_ONLY | 群組存在 LDAP，Keycloak 每次即時查詢 |
| IMPORT | 群組匯入 Keycloak 資料庫，可雙向同步（如果 Edit Mode 是 WRITABLE） |

對於 FreeIPA 整合，通常使用 **READ_ONLY**——讓群組管理完全在 FreeIPA 進行。

</details>

## 同步機制

Keycloak 提供兩種同步方式來保持資料一致。

### 手動同步

在 Keycloak Admin Console 中：
1. 進入 User Federation → 你的 LDAP Provider
2. 點擊「Synchronize all users」或「Synchronize changed users」

### 定期同步

設定自動同步排程：

| 設定 | 說明 |
|---|---|
| Periodic Full Sync | 定期完整同步所有使用者（會比對並更新） |
| Full Sync Period | 完整同步的間隔（秒） |
| Periodic Changed Users Sync | 定期同步有變更的使用者 |
| Changed Users Sync Period | 變更同步的間隔（秒） |

**建議設定：**

```
Periodic Full Sync: 開啟
Full Sync Period: 86400（每天一次）

Periodic Changed Users Sync: 開啟
Changed Users Sync Period: 3600（每小時一次）
```

完整同步較耗資源，但能確保資料一致性。變更同步較輕量，適合頻繁執行。

### On-Demand 同步

除了排程同步，Keycloak 也會在使用者登入時觸發同步：

1. alice 登入 Keycloak
2. Keycloak 向 LDAP 驗證密碼
3. 順便更新 alice 在 Keycloak 的使用者資料

這確保了即使沒有同步，登入時也能取得最新資料。

### 思考題

<details>
<summary>Q1：如果 FreeIPA 中刪除了一個使用者，Keycloak 會怎麼處理？</summary>

**取決於同步設定和模式。**

在 Import 模式下：
- 使用者資料存在 Keycloak 資料庫
- 完整同步時，Keycloak 會偵測到使用者不存在於 LDAP
- 預設行為是「不刪除」Keycloak 中的使用者（避免誤刪）
- 可設定「Removed LDAP users」策略來決定是否刪除或停用

在 No-Import 模式下：
- 使用者資料即時從 LDAP 查詢
- 使用者不存在 = 無法登入
- 不需要額外處理

</details>

<details>
<summary>Q2：大量使用者的環境下，完整同步會有效能問題嗎？</summary>

**可能會，需要調整策略。**

10,000+ 使用者的環境：
- 完整同步可能需要數分鐘到數十分鐘
- 會對 LDAP Server 造成負載
- 同步期間可能影響登入效能

緩解措施：
1. **減少完整同步頻率**：每天一次或每週一次
2. **增加變更同步頻率**：每 15-30 分鐘
3. **使用 Pagination**：Keycloak 會分批查詢，但仍需時間
4. **錯開同步時間**：避開尖峰時段

對於超大型環境，考慮使用 No-Import 模式（每次即時查詢）或使用 SSSD 整合（下一節介紹）。

</details>

## SSSD 整合：另一種選擇

除了 LDAP User Federation，Keycloak 還支援透過 **SSSD** 與 FreeIPA 整合。

### SSSD 是什麼？

**SSSD**（System Security Services Daemon）是 FreeIPA 生態系統的一部分，提供：
- 本機快取使用者資訊
- 離線認證能力
- 統一的身份查詢介面

### SSSD vs LDAP Federation

| 面向 | LDAP Federation | SSSD Integration |
|---|---|---|
| 連線方式 | Keycloak 直連 LDAP | 透過本機 SSSD daemon |
| 快取 | Keycloak 資料庫 | SSSD 快取 |
| 離線能力 | 依賴 LDAP 可用性 | SSSD 可離線認證 |
| 設定複雜度 | 較低 | 較高（需設定 SSSD） |
| 適用場景 | 一般環境 | Keycloak 運行在 FreeIPA client 上 |

### 何時選擇 SSSD？

- Keycloak 運行在已經加入 FreeIPA 網域的主機上
- 需要離線認證能力
- 希望利用 SSSD 的快取機制
- 大量使用者環境（SSSD 快取減少 LDAP 查詢）

### 設定概要

1. 主機加入 FreeIPA（`ipa-client-install`）
2. 確認 SSSD 服務運作正常
3. 在 Keycloak 啟用 SSSD Federation Provider
4. 設定 D-Bus 權限讓 Keycloak 可以查詢 SSSD

這比 LDAP Federation 需要更多的系統層級設定，但提供更好的整合度。

## 實務建議與最佳實踐

### 選擇適合的 Edit Mode

```
生產環境、FreeIPA 是唯一管理入口：
  → READ_ONLY

需要讓使用者透過 Keycloak 更新 profile：
  → WRITABLE（但關閉 Sync Registrations）

測試環境或特殊需求：
  → UNSYNCED
```

### 處理新使用者

```
推薦流程：
  1. 在 FreeIPA 建立使用者（透過 ipa user-add）
  2. 等待 Keycloak 同步（或手動觸發）
  3. 使用者登入 Keycloak

不推薦流程：
  1. 在 Keycloak 建立使用者（Sync Registrations = true）
  2. 期待使用者出現在 FreeIPA
  → 可能失敗或資料不完整
```

### 監控與維護

- 定期檢查同步日誌，確認沒有錯誤
- 監控 LDAP 連線狀態
- 設定告警：當同步失敗時通知管理員
- 定期審查 Mapper 設定，確認屬性對應正確

### 安全考量

- 使用 LDAPS（TLS）連線，避免明文傳輸
- 限制 Keycloak 使用的 LDAP 帳號權限（只給必要的讀取權限）
- 如果使用 WRITABLE，確認只授權必要的寫入權限
- 啟用 Keycloak 的稽核日誌

## 常見問題排解

### 問題 1：使用者無法登入

```
錯誤訊息：Invalid username or password
```

**檢查步驟：**

1. 確認使用者存在於 FreeIPA：
   ```bash
   ipa user-show alice
   ```

2. 確認 Keycloak 可以連線 LDAP：
   - 在 Admin Console 測試 LDAP 連線
   - 檢查 Keycloak 日誌

3. 確認使用者已同步到 Keycloak：
   - 在 Users 頁面搜尋使用者
   - 手動執行同步

### 問題 2：屬性沒有同步

```
FreeIPA 中的 email 已更新，但 Keycloak 顯示舊的
```

**檢查步驟：**

1. 確認有對應的 Mapper：
   - 檢查 User Federation → Mappers
   - 確認 `mail` 屬性有對應

2. 手動觸發同步：
   - 點擊「Synchronize all users」

3. 檢查同步模式：
   - 如果是 UNSYNCED，屬性不會自動更新

### 問題 3：新使用者無法回寫 FreeIPA

```
Keycloak 日誌：LDAP: error code 65 - object class violation
```

**原因：** FreeIPA 要求的屬性比 Keycloak 預設 Mapper 多很多。

**解決方案：**
- 不在 Keycloak 建立使用者（在 FreeIPA 建立）
- 或使用 UNSYNCED 模式

## 總結

在這篇文章中，我們學習了：

1. **User Federation 的概念**
   - Keycloak 作為身份代理，從 FreeIPA 取得使用者資料
   - Import vs No-Import 模式的差異

2. **三種 Edit Mode**
   - READ_ONLY：單向同步，最安全
   - WRITABLE：雙向同步，可修改現有使用者
   - UNSYNCED：初始匯入後分離

3. **Writeback 的限制**
   - 修改現有使用者：WRITABLE 模式下可行
   - 建立新使用者：FreeIPA 有嚴格的屬性要求，不建議透過 Keycloak 建立

4. **LDAP Mapper 設定**
   - 屬性對應
   - FreeIPA 的特殊設定（ipaUniqueID 等）

5. **同步機制**
   - 手動、定期、On-Demand 同步
   - 大型環境的效能考量

6. **最佳實踐**
   - FreeIPA 負責建立使用者
   - Keycloak 負責認證和協議轉換
   - 使用 READ_ONLY 或 WRITABLE（關閉 Sync Registrations）

## 下一篇預告

在下一篇文章中，我們會深入探討 Kerberos Delegation（委派）機制：

- 為什麼 Web App 需要代替使用者存取後端服務
- TGT 轉發、無限制委派、受限委派的差異
- 在 FreeIPA 中設定 Constrained Delegation
- 實作 Web App 委派存取資料庫的完整流程

## Reference

- [Keycloak Documentation - LDAP/AD Integration](https://wjw465150.gitbooks.io/keycloak-documentation/content/server_admin/topics/user-federation/ldap.html)
- [Keycloak Documentation - SSSD and FreeIPA Integration](https://wjw465150.gitbooks.io/keycloak-documentation/content/server_admin/topics/user-federation/sssd.html)
- [GitHub Discussion - FreeIPA Writeback Issues](https://github.com/keycloak/keycloak/discussions/13691)
- [keycloak-freeipa-docker - Example Integration](https://github.com/mposolda/keycloak-freeipa-docker)
- [Red Hat - Federation with Keycloak and FreeIPA](https://access.redhat.com/solutions/3010401)
