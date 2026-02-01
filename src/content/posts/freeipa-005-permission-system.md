---
title: FreeIPA 權限系統：從 Group 到 RBAC 完整指南
description: 深入理解 FreeIPA 的權限模型，從基礎群組管理到 RBAC 權限委派的完整指南
date: 2026-02-01
slug: freeipa-permission-system
series: "freeipa"
tags:
    - "freeipa"
    - "authentication"
    - "authorization"
    - "note"
---

在 FreeIPA 部署完成後，下一步就是設計權限架構。這篇文章會從基礎的 Group 管理開始，逐步深入到 Nested Group、RBAC 權限委派，讓你能夠建立一個完整的企業級權限系統。

:::note
**前置閱讀**

本文假設你已經讀過系列的前幾篇文章，特別是：
- [FreeIPA 實戰：部署企業級 Kerberos 環境](/posts/freeipa-kerberos-deployment)——理解 FreeIPA 架構和基本操作

本文會使用 `ipa` 命令和 FreeIPA Web UI，假設你已有運作中的 FreeIPA 環境。
:::

:::tip
**實驗環境**

本文有配套的 Docker 範例環境，可以快速建立包含測試資料的 FreeIPA 環境：

```bash
git clone https://github.com/csjhuang/the-csjhuang-blog
cd the-csjhuang-blog/examples/blog-freeipa-example
just up      # 部署 FreeIPA（約 10-15 分鐘）
just seed    # 建立本文使用的測試資料
just shell   # 進入 FreeIPA 容器
```

範例會建立 alice、bob、carol、dave 等使用者，以及 developers、dbas、tier1-support 等群組。
:::

## 背景知識速查

如果你對以下術語不熟悉，這裡有簡短說明：

| 術語 | 說明 |
|-----|------|
| **LDAP** | Lightweight Directory Access Protocol，一種目錄服務協議。FreeIPA 用它儲存使用者、群組、權限等資料，類似於一個專門存身份資訊的資料庫 |
| **kinit** | Kerberos 認證命令，用來「登入」取得 Kerberos Ticket。執行 `ipa` 命令前需要先 `kinit` |
| **389 DS** | 389 Directory Server，FreeIPA 使用的 LDAP 伺服器實作 |
| **SSSD** | System Security Services Daemon，在 Client 端負責快取使用者資訊和處理認證 |

這些概念在 [Kerberos 入門指南](/posts/kerberos-101) 和 [FreeIPA 部署](/posts/freeipa-kerberos-deployment) 有詳細說明。

## 如果你熟悉其他系統

FreeIPA 的權限概念和其他系統有相似之處，如果你已經熟悉以下系統，可以用這個對照表快速建立概念：

| FreeIPA | Kubernetes | Linux/POSIX | AWS IAM |
|---------|------------|-------------|---------|
| User | User / ServiceAccount | User (UID) | IAM User |
| Group | Group | Group (GID) | IAM Group |
| Role | ClusterRole / Role | - | IAM Role |
| Permission | 動詞 (get, list, create...) | rwx | Action |
| Privilege | - | - | Policy |
| HBAC Rule | NetworkPolicy | hosts.allow | Security Group |
| Sudo Rule | - | sudoers | - |

**與 Kubernetes RBAC 的對比**：

```
Kubernetes:
  ClusterRole ─► RoleBinding ─► User/ServiceAccount
       │
       └── rules: [verbs, resources, apiGroups]

FreeIPA:
  Role ─► (直接指派) ─► User/Group
    │
    └── Privilege ─► Permission [target, rights, attrs]
```

主要差異：
- K8s 的 Role 直接包含 rules；FreeIPA 多了一層 Privilege 做分組
- K8s 需要 RoleBinding 連結；FreeIPA 直接在 Role 上指派成員
- FreeIPA 的 Permission 可以細到 LDAP 屬性層級

如果你不熟悉這些系統也沒關係，接下來會從頭解釋。

## FreeIPA 權限模型總覽

在深入細節之前，先建立 FreeIPA 權限模型的整體圖像。

```
┌───────────────────────────────────────────────────────────────────────┐
│                     FreeIPA Permission Model                          │
├───────────────────────────────────────────────────────────────────────┤
│                                                                       │
│  ┌─────────────────────────────────────────────────────────────────┐  │
│  │              Administration Layer (who manages FreeIPA)         │  │
│  │  ┌────────┐    ┌──────────┐    ┌──────────┐    ┌────────────┐  │  │
│  │  │  Role  │ ─► │ Privilege│ ─► │Permission│    │Self-service│  │  │
│  │  └────────┘    └──────────┘    └──────────┘    └────────────┘  │  │
│  └─────────────────────────────────────────────────────────────────┘  │
│                                  │                                    │
│                                  ▼                                    │
│  ┌─────────────────────────────────────────────────────────────────┐  │
│  │              Access Control Layer (who accesses what)           │  │
│  │  ┌────────────────┐                ┌────────────────┐           │  │
│  │  │   HBAC Rule    │                │   Sudo Rule    │           │  │
│  │  └────────────────┘                └────────────────┘           │  │
│  └─────────────────────────────────────────────────────────────────┘  │
│                                  │                                    │
│                                  ▼                                    │
│  ┌─────────────────────────────────────────────────────────────────┐  │
│  │                Identity Layer (users and groups)                │  │
│  │  ┌────────┐    ┌────────┐    ┌────────┐    ┌────────┐          │  │
│  │  │  User  │ ─► │ Group  │ ─► │ Nested │    │  Host  │          │  │
│  │  │        │    │        │    │ Group  │    │        │          │  │
│  │  └────────┘    └────────┘    └────────┘    └────────┘          │  │
│  └─────────────────────────────────────────────────────────────────┘  │
│                                                                       │
└───────────────────────────────────────────────────────────────────────┘
```

- **管理權限層**（Administration Layer）：控制誰能管理 FreeIPA
- **存取控制層**（Access Control Layer）：控制誰能存取什麼資源
- **身份層**（Identity Layer）：定義使用者與群組

**三層架構的職責：**

| 層級 | 職責 | 典型問題 |
|-----|------|---------|
| 身份層 | 定義「誰」和「什麼」 | alice 屬於哪個部門？這台機器是什麼角色？ |
| 存取控制層 | 定義「誰能存取什麼」 | alice 能 SSH 到 db-server 嗎？能執行 sudo 嗎？ |
| 管理權限層 | 定義「誰能管理 FreeIPA」 | helpdesk 能重設密碼嗎？能新增使用者嗎？ |

這篇文章會聚焦在**身份層**和**管理權限層**。存取控制層（HBAC、Sudo）會在下一篇文章詳細介紹。

## Group 基礎

Group 是 FreeIPA 權限系統的基石。理解 POSIX group 和 non-POSIX group 的差異是正確設計權限架構的第一步。

### POSIX Group vs Non-POSIX Group

FreeIPA 支援兩種類型的 Group：

| 特性 | POSIX Group | Non-POSIX Group |
|-----|-------------|-----------------|
| 有 GID | 是 | 否 |
| 用於檔案權限 | 是 | 否 |
| 用於 HBAC/Sudo | 是 | 是 |
| 用於 RBAC | 是 | 是 |
| 預設類型 | 是 | 否 |

**POSIX Group** 具有 GID（Group ID），可以用於 Linux 檔案系統的權限控制。當你在 NFS 共享或本機檔案設定 `chown :developers file.txt` 時，需要的就是 POSIX Group。

**Non-POSIX Group** 沒有 GID，純粹是邏輯上的分組。它的用途是在 FreeIPA 內部組織使用者，例如用於 RBAC 權限指派、HBAC 規則等。

### 什麼時候用哪種？

```
需要檔案權限？
    │
    ├─► 是 ──► POSIX Group
    │         例：developers、dbadmins
    │
    └─► 否 ──► Non-POSIX Group
              例：tier1-support、project-alpha-members
```

實務建議：
- **職能型群組**（developers、sysadmins、dbas）：使用 POSIX Group，因為通常需要檔案權限
- **專案型群組**（project-x-members）：考慮 Non-POSIX，除非專案有共享檔案目錄
- **權限型群組**（can-reset-password、can-view-logs）：使用 Non-POSIX，這類群組只用於權限控制

### Group 操作示範

```bash
# 確保有有效的 Kerberos ticket
kinit admin

# 建立 POSIX Group（預設）
ipa group-add developers --desc="Development Team"

# 建立 Non-POSIX Group
ipa group-add tier1-support --desc="Tier 1 Support Team" --nonposix

# 將使用者加入群組
ipa group-add-member developers --users=alice,bob

# 查看群組資訊
ipa group-show developers
```

輸出範例：

```
  Group name: developers
  Description: Development Team
  GID: 686600003
  Member users: alice, bob
```

注意 GID 欄位——POSIX Group 會有這個值，Non-POSIX Group 則不會顯示。

```bash
# 查看 Non-POSIX Group
ipa group-show tier1-support
```

```
  Group name: tier1-support
  Description: Tier 1 Support Team
  Member users: carol
```

沒有 GID 欄位，這就是 Non-POSIX Group。

### 思考題

<details>
<summary>Q1：如果一開始建立了 Non-POSIX Group，後來發現需要檔案權限，怎麼辦？</summary>

**可以將 Non-POSIX Group 轉換為 POSIX Group。**

```bash
ipa group-mod tier1-support --posix
```

這會為群組指派一個 GID。不過要注意：
- 轉換後無法再變回 Non-POSIX
- 已存在的檔案權限不會自動更新，需要重新設定

建議：在設計階段就決定好群組類型，避免後續轉換。

</details>

<details>
<summary>Q2：一個使用者可以同時屬於多個群組嗎？群組數量有限制嗎？</summary>

**可以，而且這是常見的設計模式。**

一個使用者通常會屬於多個群組：
- 職能群組（developers）
- 部門群組（engineering）
- 專案群組（project-x）
- 權限群組（can-deploy-production）

Linux 系統對群組數量有限制（傳統上是 16 個，現代系統通常是 65536 個），但 SSSD 會處理這個問題。FreeIPA 本身沒有硬性限制，但過多的群組會影響 LDAP 查詢效能。

實務上，每個使用者屬於 10-30 個群組是常見的，超過 100 個就需要檢視設計是否合理。

</details>

## Nested Group（群組巢狀）

真實的組織架構通常是階層式的：公司有部門，部門有團隊。Nested Group 讓你能夠反映這種階層關係。

### 運作原理

Nested Group 是指「群組包含其他群組作為成員」。當 Group A 包含 Group B 時，Group B 的所有成員也會被視為 Group A 的成員。

```
                  ┌─────────────┐
                  │   company   │
                  └──────┬──────┘
                         │
          ┌──────────────┼──────────────┐
          │              │              │
          ▼              ▼              ▼
   ┌────────────┐ ┌────────────┐ ┌────────────┐
   │engineering │ │  product   │ │   sales    │
   └──────┬─────┘ └────────────┘ └────────────┘
          │
    ┌─────┴─────┐
    │           │
    ▼           ▼
┌────────┐ ┌────────┐
│frontend│ │backend │
└────────┘ └────────┘
  alice      bob
  carol      dave
```

- `company`：公司全體
- `engineering`：工程部、`product`：產品部、`sales`：業務部
- `frontend`：前端組、`backend`：後端組

在這個結構中：
- alice 直接屬於 `frontend`
- alice 間接屬於 `engineering`（因為 frontend 是 engineering 的成員）
- alice 間接屬於 `company`（因為 engineering 是 company 的成員）

### LDAP memberOf 機制

FreeIPA 使用 LDAP 的 `memberOf` 屬性來追蹤群組成員關係。這個屬性會自動維護，包含使用者直接和間接所屬的所有群組。

```bash
# 查看 alice 的完整群組成員資格
ipa user-show alice --all | grep -A 20 "Member of"
```

```
  Member of groups: frontend, engineering, company
```

這三個群組都會出現，即使 alice 只直接加入了 `frontend`。

### 建立 Nested Group

```bash
# 建立階層結構
ipa group-add company --desc="All Employees"
ipa group-add engineering --desc="Engineering Department"
ipa group-add frontend --desc="Frontend Team"
ipa group-add backend --desc="Backend Team"

# 建立巢狀關係
ipa group-add-member engineering --groups=frontend,backend
ipa group-add-member company --groups=engineering

# 將使用者加入最底層的群組
ipa group-add-member frontend --users=alice,carol
ipa group-add-member backend --users=bob,dave
```

驗證：

```bash
# 查看 engineering 群組
ipa group-show engineering
```

```
  Group name: engineering
  Description: Engineering Department
  GID: 686600004
  Member groups: frontend, backend
  Indirect Member users: alice, bob, carol, dave
```

注意 **Indirect Member users**——這顯示了從子群組繼承的成員。

### 限制與注意事項

**1. 循環參照檢測**

FreeIPA 會防止循環參照：

```bash
# 嘗試建立循環：engineering → frontend → engineering
ipa group-add-member frontend --groups=engineering
# ipa: ERROR: A group may not be a member of itself
```

**2. 效能考量**

深度巢狀會影響效能：
- 每次查詢成員資格都需要遞迴展開
- LDAP 查詢複雜度增加
- SSSD 快取更新時間變長

建議：巢狀深度控制在 3-4 層以內。

**3. 非 POSIX 群組的巢狀**

POSIX Group 只能包含 POSIX Group 作為成員。如果你嘗試將 Non-POSIX Group 加入 POSIX Group：

```bash
ipa group-add-member developers --groups=tier1-support
# 如果 tier1-support 是 Non-POSIX，這會失敗
```

解決方案：統一群組類型，或將 Non-POSIX 轉為 POSIX。

### 實際應用場景

**場景：部門層級的存取控制**

假設你想要：
- 工程部所有人都能 SSH 到開發伺服器
- 只有後端組能 SSH 到資料庫伺服器

設定方式：
```bash
# HBAC 規則（下篇文章詳述）
ipa hbacrule-add allow-dev-servers
ipa hbacrule-add-user allow-dev-servers --groups=engineering

ipa hbacrule-add allow-db-servers
ipa hbacrule-add-user allow-db-servers --groups=backend
```

當新人加入前端組時，只需要 `ipa group-add-member frontend --users=newbie`，就會自動獲得開發伺服器的存取權限，但不會有資料庫伺服器的權限。

### 思考題

<details>
<summary>Q1：如果 alice 直接屬於 engineering，同時也屬於 frontend（而 frontend 也屬於 engineering），會發生什麼事？</summary>

**沒有問題，FreeIPA 會正確處理重複的成員關係。**

在 LDAP 層面：
- alice 的 `memberOf` 只會列出 engineering 一次
- 群組成員查詢會正確去重

實務上，這種設計雖然可行，但會造成管理上的混亂。建議：
- 使用者只加入最具體的群組（frontend），讓巢狀自動處理上層關係
- 避免同時直接和間接加入同一個群組

</details>

<details>
<summary>Q2：刪除一個中間層群組（如 engineering）會發生什麼事？</summary>

**FreeIPA 會阻止刪除有成員的群組。**

```bash
ipa group-del engineering
# ipa: ERROR: engineering: group not empty
```

你必須先移除所有成員（包括子群組）：

```bash
ipa group-remove-member engineering --groups=frontend,backend
ipa group-del engineering
```

這時 frontend 和 backend 仍然存在，但不再屬於任何上層群組。它們的成員（alice、bob 等）也會失去原本從 engineering 繼承的間接成員資格。

建議：刪除群組前，檢視相依的 HBAC、Sudo、RBAC 規則，確保不會意外中斷存取權限。

</details>

## RBAC 權限委派

RBAC（Role-Based Access Control）是 FreeIPA 管理權限的機制——它控制「誰能管理 FreeIPA 本身」。

### 三層架構

FreeIPA 的 RBAC 由三個元件組成：

```
┌──────────┐   contains   ┌──────────┐   contains   ┌──────────┐
│   Role   │ ──────────►  │Privilege │ ──────────►  │Permission│
└──────────┘              └──────────┘              └──────────┘
     │
     │ assigned to
     ▼
┌──────────┐
│User/Group│
└──────────┘
```

- **Role**（角色）：指派給 User 或 Group
- **Privilege**（權限集）：Permission 的集合
- **Permission**（權限）：最小的權限單位

**Permission（權限）**：最小的權限單位，定義對特定 LDAP 物件的特定操作。

例如：
- `System: Add Users`：新增使用者
- `System: Modify Users`：修改使用者
- `System: Read User Membership`：讀取使用者的群組成員資格

**Privilege（權限集）**：Permission 的集合，代表一個邏輯上的職責。

例如：
- `User Administrators`：包含所有使用者管理相關的 Permission
- `Group Administrators`：包含所有群組管理相關的 Permission

**Role（角色）**：Privilege 的集合，指派給 User 或 Group。

例如：
- `helpdesk`：包含 `Modify Users` 和 `Modify Group Membership` Privilege
- `User Administrator`：包含完整的使用者管理 Privilege

### 內建角色介紹

FreeIPA 預設提供幾個常用角色：

```bash
ipa role-find
```

| 角色 | 用途 | 適用對象 |
|-----|------|---------|
| helpdesk | 重設密碼、解鎖帳號 | IT 支援人員 |
| User Administrator | 完整使用者管理 | HR 系統管理員 |
| Group Administrator | 完整群組管理 | 部門主管 |
| Host Administrator | 主機管理 | 系統管理員 |

查看角色詳情：

```bash
ipa role-show helpdesk --all
```

```
  Role name: helpdesk
  Description: Helpdesk
  Privileges: Modify Users, Modify Group membership
```

### 實作範例：建立「密碼重設專員」

假設你需要一個只能重設密碼、不能做其他事的角色。

**步驟 1：了解需要什麼 Permission**

```bash
# 查看密碼相關的 Permission
ipa permission-find --right=write | grep -i password
```

找到 `System: Change User password` 這個 Permission。

**步驟 2：建立 Privilege**

```bash
ipa privilege-add "Password Reset Only" \
    --desc="Can only reset user passwords"

ipa privilege-add-permission "Password Reset Only" \
    --permissions="System: Change User password"
```

**步驟 3：建立 Role**

```bash
ipa role-add "Password Reset Operator" \
    --desc="Operator who can only reset passwords"

ipa role-add-privilege "Password Reset Operator" \
    --privileges="Password Reset Only"
```

**步驟 4：指派給使用者或群組**

```bash
# 指派給單一使用者
ipa role-add-member "Password Reset Operator" --users=carol

# 或指派給群組（推薦）
ipa role-add-member "Password Reset Operator" --groups=tier1-support
```

現在 tier1-support 群組的成員都可以重設密碼，但無法執行其他管理操作。

### 驗證權限

```bash
# 以 carol 身份登入
kinit carol

# 嘗試重設 alice 的密碼
ipa user-mod alice --password
# 成功

# 嘗試新增使用者
ipa user-add newuser --first=New --last=User
# ipa: ERROR: Insufficient access: ...
```

### 自訂 Permission

如果內建的 Permission 不夠用，可以建立自訂 Permission：

```bash
ipa permission-add "Read User Email" \
    --right=read \
    --type=user \
    --attrs=mail

ipa privilege-add-permission "User Viewers" \
    --permissions="Read User Email"
```

這個 Permission 只允許讀取使用者的 email 屬性，無法讀取其他資訊。

### 思考題

<details>
<summary>Q1：如果某人同時屬於多個 Role，權限如何計算？</summary>

**權限是累加的（Union）。**

假設 alice 同時屬於：
- `Password Reset Operator`：可以重設密碼
- `Group Viewer`：可以查看群組

那 alice 可以同時做這兩件事。FreeIPA 的 RBAC 是「允許模型」，沒有「禁止」的概念——你有的權限只會增加，不會減少。

如果需要限制特定使用者的權限，應該：
1. 不要把他加入那個 Role
2. 或建立一個權限更小的 Role

</details>

<details>
<summary>Q2：Permission、Privilege、Role 三層架構看起來很複雜，為什麼不直接把 Permission 指派給使用者？</summary>

**為了可維護性和一致性。**

直接指派 Permission 的問題：
- 新進人員要逐一設定數十個 Permission
- 職責變更時要修改每個人的設定
- 難以稽核「誰有什麼權限」

三層架構的好處：
- **Permission**：由 FreeIPA 管理，代表技術上的能力
- **Privilege**：由管理員定義，代表邏輯上的職責
- **Role**：對應組織架構，方便指派

例如：新的 helpdesk 人員加入時，只需 `ipa role-add-member helpdesk --users=newbie`，不需要知道背後有哪些 Permission。

</details>

<details>
<summary>Q3：admin 帳號和 RBAC 是什麼關係？admin 的權限來自哪裡？</summary>

**admin 屬於 `admins` 群組，這個群組在 FreeIPA 中有特殊地位。**

```bash
ipa group-show admins
```

`admins` 群組不是透過 RBAC 獲得權限，而是 FreeIPA 內建的超級管理員群組，類似 Linux 的 root。它可以：
- 執行所有 RBAC 操作
- 存取所有 LDAP 資料
- 繞過某些存取控制

建議：
- 日常操作使用 RBAC 授權的帳號
- `admin` 只用於初始設定和緊急狀況
- 考慮建立個人的管理員帳號，加入 `admins` 群組，方便稽核

</details>

## Self-service 規則

Self-service 規則讓使用者能夠修改自己的特定屬性，不需要管理員介入。

### 使用場景

常見的 self-service 需求：
- 更新電話號碼
- 上傳 SSH public key
- 修改個人描述
- 變更通知 email

### 建立 Self-service 規則

```bash
# 允許使用者修改自己的電話和手機號碼
ipa selfservice-add "Users can manage their phone numbers" \
    --permissions=write \
    --attrs=telephonenumber,mobile

# 允許使用者管理自己的 SSH key
ipa selfservice-add "Users can manage their SSH keys" \
    --permissions=write \
    --attrs=ipasshpubkey
```

### 驗證

```bash
# 以一般使用者身份
kinit alice

# 修改自己的電話
ipa user-mod alice --phone="+886-2-1234-5678"
# 成功

# 嘗試修改別人的電話
ipa user-mod bob --phone="+886-2-9999-9999"
# ipa: ERROR: Insufficient access: ...

# 嘗試修改自己的 UID（不在 self-service 規則中）
ipa user-mod alice --uid=99999
# ipa: ERROR: Insufficient access: ...
```

### 查看現有規則

```bash
ipa selfservice-find
```

FreeIPA 預設已經有一些 self-service 規則，包括管理 SSH key 和部分聯絡資訊。

### 思考題

<details>
<summary>Q1：Self-service 和 Permission 有什麼關係？可以用 Permission 達到同樣效果嗎？</summary>

**Self-service 是 Permission 的簡化版，專門處理「使用者修改自己」的情境。**

技術上，你可以建立一個 Permission 讓所有人都能修改 `telephonenumber` 屬性：

```bash
ipa permission-add "Modify Phone Numbers" \
    --right=write \
    --type=user \
    --attrs=telephonenumber
```

但這會讓每個人都能修改**任何人**的電話號碼。

Self-service 規則的特殊之處是它內建了「只能改自己」的限制，不需要額外設定 target filter。

</details>

## 總結

在這篇文章中，我們學習了：

1. **FreeIPA 權限模型**：三層架構（身份層、存取控制層、管理權限層）

2. **Group 基礎**：
   - POSIX group（有 GID）vs Non-POSIX group（純邏輯分組）
   - 根據用途選擇正確的群組類型

3. **Nested Group**：
   - 群組可以包含其他群組，形成階層
   - memberOf 自動追蹤直接和間接成員
   - 注意深度限制和效能影響

4. **RBAC 權限委派**：
   - Permission → Privilege → Role 三層架構
   - 內建角色（helpdesk、User Administrator 等）
   - 自訂角色和權限的建立方式

5. **Self-service 規則**：
   - 讓使用者修改自己的特定屬性
   - 減少管理員負擔

## 下一篇預告

在下一篇文章中，我們會深入存取控制層，介紹：

- **Hostgroup**：主機的邏輯分組
- **Netgroup**：傳統 NIS 概念的現代替代
- **Sudo Rule**：集中式 sudo 權限管理
- **SSSD 整合**：如何將這些規則同步到各個 Client

## Reference

- [FreeIPA Documentation - User Groups](https://freeipa.readthedocs.io/en/latest/workshop/4-user-management.html)
- [FreeIPA Documentation - Role-Based Access Control](https://freeipa.readthedocs.io/en/latest/workshop/8-delegation.html)
- [Red Hat IdM - Managing User Groups](https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/9/html/managing_idm_users_groups_hosts_and_access_control_rules/)
