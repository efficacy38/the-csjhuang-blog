---
title: FreeIPA 集中式 Sudo 管理：hostgroup 與 netgroup 實戰
description: 使用 FreeIPA 集中管理 sudo 權限，透過 hostgroup 和 netgroup 實現靈活的存取控制
date: 2026-02-01
slug: freeipa-sudo-hostgroup
series: "freeipa"
tags:
    - "freeipa"
    - "sudo"
    - "authorization"
    - "note"
---

在上一篇文章中，我們學習了 FreeIPA 的權限系統，包括 Group、Nested Group 和 RBAC。這篇文章要進入存取控制層，介紹如何使用 FreeIPA 集中管理 sudo 權限。

:::note
**前置閱讀**

本文假設你已經讀過系列的前幾篇文章，特別是：
- [FreeIPA 權限系統：從 Group 到 RBAC 完整指南](/posts/freeipa-permission-system)——理解 Group 和 Nested Group 概念

本文會使用「Group」、「Nested Group」等術語，不再重複解釋。
:::

:::tip
**實驗環境**

本文有配套的 Docker 範例環境，已預先建立本文使用的測試資料：

```bash
git clone https://github.com/csjhuang/the-csjhuang-blog
cd the-csjhuang-blog/examples/blog-freeipa-example
just up      # 部署 FreeIPA（約 10-15 分鐘）
just seed    # 建立 hostgroup、sudo 規則等測試資料
just shell   # 進入 FreeIPA 容器
```

範例會建立 webservers、dbservers 等 hostgroup，以及 dba-postgresql、developers-docker 等 sudo 規則。
:::

## 背景知識速查

| 術語 | 說明 |
|-----|------|
| **SSSD** | System Security Services Daemon，在每台 Client 上運行的服務。負責：(1) 從 FreeIPA 取得使用者/群組資訊並快取 (2) 處理 sudo 規則查詢 (3) 離線時使用快取 |
| **PAM** | Pluggable Authentication Modules，Linux 的認證框架。當你 SSH 登入或執行 `su` 時，PAM 負責驗證身份 |
| **kinit** | 取得 Kerberos Ticket 的命令。執行 `ipa` 命令前需要先 `kinit admin`（或其他有權限的帳號） |

執行本文的 `ipa` 命令時：
- 可以在 FreeIPA Server 或任何已加入網域的 Client 上執行
- 需要先執行 `kinit admin` 取得管理員權限

## 為什麼需要集中式 Sudo 管理

### 傳統 /etc/sudoers 的問題

在沒有集中管理的環境中，sudo 權限是這樣設定的：

```bash
# 在 server1 上
sudo visudo
# 加入：alice ALL=(ALL) /usr/bin/systemctl restart nginx

# 在 server2 上
sudo visudo
# 加入：alice ALL=(ALL) /usr/bin/systemctl restart nginx

# 在 server3 上
sudo visudo
# ...重複 100 次
```

這種方式的問題：

| 問題 | 影響 |
|-----|------|
| 分散管理 | 每台機器都要個別設定 |
| 難以維護 | 人員異動時要逐一修改 |
| 難以稽核 | 「alice 在哪些機器有什麼 sudo 權限？」無法快速回答 |
| 容易出錯 | sudoers 語法錯誤會導致 sudo 完全失效 |
| 無版本控制 | 不知道誰在什麼時候改了什麼 |

### FreeIPA 的解決方案

FreeIPA 將 sudo 規則存在 LDAP 中，透過 SSSD 自動同步到各個 Client：

```
┌────────────────────────────────────────────────────────────────────┐
│                         FreeIPA Server                             │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │                      LDAP (389 DS)                            │  │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐           │  │
│  │  │ Sudo Rules  │  │ Hostgroups  │  │   Groups    │           │  │
│  │  └─────────────┘  └─────────────┘  └─────────────┘           │  │
│  └──────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────┬──────────────────────────────────┘
                                  │
                     LDAP Query (SSSD)
                                  │
        ┌─────────────────────────┼─────────────────────────┐
        │                         │                         │
        ▼                         ▼                         ▼
┌──────────────┐          ┌──────────────┐          ┌──────────────┐
│   Client 1   │          │   Client 2   │          │   Client N   │
│    (SSSD)    │          │    (SSSD)    │          │    (SSSD)    │
│              │          │              │          │              │
│  sudo -l     │          │  sudo -l     │          │  sudo -l     │
│  -> query    │          │  -> query    │          │  -> query    │
└──────────────┘          └──────────────┘          └──────────────┘
```

優勢：

- **單點管理**：在 FreeIPA Web UI 或 CLI 設定一次，所有 Client 自動套用
- **即時生效**：不需要 SSH 到每台機器
- **完整稽核**：FreeIPA 記錄所有變更
- **語法檢查**：FreeIPA 會驗證規則，避免語法錯誤
- **與身份整合**：直接使用 FreeIPA 的 User 和 Group

## HBAC 與 Sudo：兩層存取控制

在深入 sudo 之前，先理解 FreeIPA 的兩層存取控制模型：

```
使用者想要登入主機並執行特權指令

        ┌─────────────────────────────────────────┐
        │           HBAC (Host-Based AC)          │
        │         "能不能登入這台機器？"            │
        └────────────────────┬────────────────────┘
                             │
                    ┌────────┴────────┐
                    │                 │
                    ▼                 ▼
               允許登入            拒絕登入
                    │              (結束)
                    ▼
        ┌─────────────────────────────────────────┐
        │              Sudo Rule                  │
        │      "登入後能執行什麼特權指令？"          │
        └────────────────────┬────────────────────┘
                             │
                    ┌────────┴────────┐
                    │                 │
                    ▼                 ▼
              允許 sudo            拒絕 sudo
```

| 控制層 | 問題 | 範例 |
|-------|------|------|
| HBAC | 誰能登入哪台機器？ | alice 能 SSH 到 db-server 嗎？ |
| Sudo Rule | 登入後能執行什麼？ | alice 能 `sudo systemctl restart postgresql` 嗎？ |

**HBAC（Host-Based Access Control）** 是第一道關卡。如果 HBAC 不允許，使用者連登入都無法登入，更不用說執行 sudo。

### HBAC 快速設定

FreeIPA 預設有一個 `allow_all` HBAC 規則，允許所有使用者登入所有主機。在生產環境中，通常會停用它並建立更細緻的規則：

```bash
# 查看現有 HBAC 規則
ipa hbacrule-find

# 停用 allow_all（小心！確保有其他規則）
ipa hbacrule-disable allow_all

# 建立新規則：developers 可以登入 dev-servers
ipa hbacrule-add allow-developers-dev
ipa hbacrule-add-user allow-developers-dev --groups=developers
ipa hbacrule-add-host allow-developers-dev --hostgroups=dev-servers
ipa hbacrule-add-service allow-developers-dev --hbacsvcs=sshd
```

HBAC 規則的組成：
- **Who**：User 或 Group
- **Where**：Host 或 Hostgroup
- **What service**：sshd、login、su 等 PAM 服務

本文會聚焦在 **Sudo Rule**，但 Hostgroup 的概念同時適用於 HBAC 和 Sudo。

## Hostgroup：主機的邏輯分組

在設定 sudo 規則之前，需要先理解 Hostgroup——它讓你能夠把多台主機歸類，簡化規則管理。

### 概念

Hostgroup 是主機（Host）的集合，類似於使用者的 Group：

```
┌─────────────────────────────────────────────────────────────┐
│                        hostgroup                             │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌────────────┐      ┌────────────┐      ┌────────────┐    │
│  │ webservers │      │ dbservers  │      │ production │    │
│  ├────────────┤      ├────────────┤      ├────────────┤    │
│  │ web1       │      │ db1        │      │ web1       │    │
│  │ web2       │      │ db2        │      │ db1        │    │
│  │ web3       │      │ db-replica │      │ app1       │    │
│  └────────────┘      └────────────┘      └────────────┘    │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

一台主機可以屬於多個 Hostgroup（例如 web1 同時屬於 `webservers` 和 `production`）。

### 建立 Hostgroup

```bash
# 確保有有效的 Kerberos ticket
kinit admin

# 建立 Hostgroup
ipa hostgroup-add webservers --desc="Web Servers"
ipa hostgroup-add dbservers --desc="Database Servers"
ipa hostgroup-add production --desc="Production Environment"
ipa hostgroup-add staging --desc="Staging Environment"

# 將主機加入 Hostgroup
ipa hostgroup-add-member webservers --hosts=web1.lab.example.com,web2.lab.example.com
ipa hostgroup-add-member dbservers --hosts=db1.lab.example.com,db2.lab.example.com
ipa hostgroup-add-member production --hosts=web1.lab.example.com,db1.lab.example.com
```

### Hostgroup 巢狀

和 User Group 一樣，Hostgroup 也支援巢狀：

```bash
# 建立環境層級的 Hostgroup
ipa hostgroup-add all-servers --desc="All Servers"

# 將其他 Hostgroup 加入
ipa hostgroup-add-member all-servers --hostgroups=webservers,dbservers
```

現在 `all-servers` 包含 webservers 和 dbservers 的所有主機。

### 查看 Hostgroup

```bash
ipa hostgroup-show webservers
```

```
  Host-group: webservers
  Description: Web Servers
  Member hosts: web1.lab.example.com, web2.lab.example.com
```

```bash
# 顯示完整資訊，包括間接成員
ipa hostgroup-show all-servers --all
```

```
  Host-group: all-servers
  Description: All Servers
  Member host-groups: webservers, dbservers
  Indirect Member hosts: web1.lab.example.com, web2.lab.example.com,
                         db1.lab.example.com, db2.lab.example.com
```

**Indirect Member**（間接成員）是指透過巢狀 Hostgroup 繼承的成員。`all-servers` 直接包含 `webservers` 和 `dbservers` 這兩個 Hostgroup，而這些主機是從子 Hostgroup「間接」成為 `all-servers` 的成員。

### 思考題

<details>
<summary>Q1：Hostgroup 和 User Group 有什麼相似和不同之處？</summary>

**相似之處：**
- 都是邏輯分組
- 都支援巢狀（Nested）
- 都存在 LDAP 中
- 都可以用於 HBAC 和 Sudo 規則

**不同之處：**

| 特性 | User Group | Hostgroup |
|-----|------------|-----------|
| 成員類型 | User | Host |
| POSIX 支援 | 有（GID） | 無 |
| 檔案權限 | 可用 | 不適用 |
| RBAC | 可用 | 不適用 |

Hostgroup 沒有 POSIX/Non-POSIX 的區分，因為主機不需要 GID。

</details>

## Netgroup：傳統 NIS 的現代替代

Netgroup 是來自 1980-90 年代 NIS（Network Information Service，又稱 Yellow Pages）的概念。當時的 Unix 系統用它來定義「哪些使用者可以從哪些主機存取」。

FreeIPA 支援 Netgroup 主要是為了相容舊系統。**如果你沒有需要整合的 legacy 系統，可以跳過這節。**

### 什麼是 Netgroup

Netgroup 是一個三元組（triple）的集合：`(host, user, domain)`

```
netgroup "developers" = {
    (web1.example.com, alice, example.com),
    (web1.example.com, bob, example.com),
    (db1.example.com, alice, example.com)
}
```

這個 netgroup 定義了：
- alice 可以從 web1 和 db1 存取
- bob 只能從 web1 存取

### Hostgroup vs Netgroup

| 特性 | Hostgroup | Netgroup |
|-----|-----------|----------|
| 成員類型 | 只有 Host | Host + User + Domain 三元組 |
| 複雜度 | 簡單 | 複雜 |
| 用途 | HBAC、Sudo（推薦） | NFS exports、legacy 系統 |
| FreeIPA 推薦度 | 優先使用 | 相容性需求時使用 |

### 何時使用 Netgroup

1. **NFS exports**：傳統的 `/etc/exports` 語法支援 netgroup
   ```
   /export/home @developers(rw,sec=krb5p)
   ```

2. **Legacy 系統整合**：某些舊系統只認得 netgroup

3. **細粒度控制**：需要同時限制 host 和 user 的組合

### 建立 Netgroup（簡化版）

FreeIPA 的 netgroup 可以簡化使用，只指定 host 或 user：

```bash
# 建立 netgroup
ipa netgroup-add nfs-users --desc="Users who can access NFS"

# 加入使用者
ipa netgroup-add-member nfs-users --users=alice,bob

# 加入主機
ipa netgroup-add-member nfs-users --hosts=client.lab.example.com
```

### 建議

**除非有特定需求，否則優先使用 Hostgroup + User Group 的組合**，而不是 Netgroup。原因：

- Hostgroup + User Group 概念清晰，分開管理
- Netgroup 的三元組模型較複雜，容易混淆
- 現代 FreeIPA 的 HBAC 和 Sudo 規則已經可以分別指定 host 和 user

## Sudo Rule 設計

現在進入核心主題：如何在 FreeIPA 設定 sudo 規則。

### Sudo Rule 的組成元素

```
┌───────────────────────────────────────────────────────────────────┐
│                          Sudo Rule                                │
├───────────────────────────────────────────────────────────────────┤
│                                                                   │
│  WHO            on            WHERE          run          WHAT    │
│  ───            ──            ─────          ───          ────    │
│  User        ───────►        Host        ───────►      Command   │
│  Group                       Hostgroup                 Cmd Group │
│                                                                   │
│  RunAs               Options                                      │
│  ─────               ───────                                      │
│  RunAs User          NOPASSWD                                     │
│  RunAs Group         SETENV                                       │
│                                                                   │
└───────────────────────────────────────────────────────────────────┘
```

| 元素 | 說明 | 範例 |
|-----|------|------|
| WHO | 誰可以執行 | alice、developers group |
| WHERE | 在哪些主機上 | dbservers hostgroup |
| WHAT | 可以執行什麼命令 | /usr/bin/systemctl |
| RunAs | 以什麼身份執行 | root、postgres |
| Options | 額外選項 | NOPASSWD |

### 建立 Sudo Rule 的完整流程

**範例情境**：DBA 群組可以在 dbservers 上執行 PostgreSQL 管理指令。

**步驟 1：建立 Sudo Command**

```bash
# 定義允許的命令
ipa sudocmd-add "/usr/bin/systemctl restart postgresql"
ipa sudocmd-add "/usr/bin/systemctl stop postgresql"
ipa sudocmd-add "/usr/bin/systemctl start postgresql"
ipa sudocmd-add "/usr/bin/systemctl status postgresql"
```

**步驟 2：建立 Sudo Command Group（可選但推薦）**

```bash
# 將相關命令組成群組
ipa sudocmdgroup-add postgresql-management --desc="PostgreSQL Management Commands"

ipa sudocmdgroup-add-member postgresql-management \
    --sudocmds="/usr/bin/systemctl restart postgresql"
ipa sudocmdgroup-add-member postgresql-management \
    --sudocmds="/usr/bin/systemctl stop postgresql"
ipa sudocmdgroup-add-member postgresql-management \
    --sudocmds="/usr/bin/systemctl start postgresql"
ipa sudocmdgroup-add-member postgresql-management \
    --sudocmds="/usr/bin/systemctl status postgresql"
```

**步驟 3：建立 Sudo Rule**

```bash
# 建立規則
ipa sudorule-add dba-postgresql --desc="DBA can manage PostgreSQL"

# 指定 WHO（誰可以執行）
ipa sudorule-add-user dba-postgresql --groups=dbas

# 指定 WHERE（在哪些主機）
ipa sudorule-add-host dba-postgresql --hostgroups=dbservers

# 指定 WHAT（可以執行什麼）
ipa sudorule-add-allow-command dba-postgresql \
    --sudocmdgroups=postgresql-management

# 設定 RunAs（以什麼身份執行）—— 預設是 root
ipa sudorule-add-runasuser dba-postgresql --users=root

# 設定選項（可選）
ipa sudorule-add-option dba-postgresql --sudooption='!authenticate'
# !authenticate 等同於 NOPASSWD
```

**步驟 4：驗證規則**

```bash
# 查看規則
ipa sudorule-show dba-postgresql --all
```

```
  Rule name: dba-postgresql
  Description: DBA can manage PostgreSQL
  Enabled: TRUE
  User Groups: dbas
  Host Groups: dbservers
  Sudo Allow Command Groups: postgresql-management
  RunAs Users: root
  Sudo Option: !authenticate
```

### 更多範例情境

**範例 2：開發者可以在所有主機執行 docker 指令**

```bash
# 命令
ipa sudocmd-add "/usr/bin/docker"
ipa sudocmd-add "/usr/bin/docker-compose"

ipa sudocmdgroup-add docker-commands
ipa sudocmdgroup-add-member docker-commands \
    --sudocmds="/usr/bin/docker,/usr/bin/docker-compose"

# 規則
ipa sudorule-add developers-docker
ipa sudorule-add-user developers-docker --groups=developers
ipa sudorule-add-host developers-docker --hostcategory=all  # 所有主機
ipa sudorule-add-allow-command developers-docker --sudocmdgroups=docker-commands
```

**範例 3：Helpdesk 可以重設使用者密碼**

```bash
ipa sudocmd-add "/usr/sbin/passwd *"  # * 代表任何參數

ipa sudorule-add helpdesk-passwd
ipa sudorule-add-user helpdesk-passwd --groups=tier1-support
ipa sudorule-add-host helpdesk-passwd --hostcategory=all
ipa sudorule-add-allow-command helpdesk-passwd --sudocmds="/usr/sbin/passwd *"

# 但不能改 root 密碼
ipa sudocmd-add "/usr/sbin/passwd root"
ipa sudorule-add-deny-command helpdesk-passwd --sudocmds="/usr/sbin/passwd root"
```

### Allow vs Deny Command

FreeIPA sudo rule 支援 allow 和 deny 兩種類型：

- **Allow Command**：明確允許的命令
- **Deny Command**：明確禁止的命令（優先於 allow）

處理順序：
1. 檢查是否在 Deny 清單中 → 如果是，拒絕
2. 檢查是否在 Allow 清單中 → 如果是，允許
3. 都不是 → 拒絕

### 思考題

<details>
<summary>Q1：為什麼要建立 Sudo Command Group，而不是直接把命令加到規則裡？</summary>

**可重用性和可維護性。**

假設你有三個規則都需要允許 PostgreSQL 管理命令：
- DBA 在 production
- DBA 在 staging
- 緊急維護人員在所有環境

如果不使用 Command Group：
- 每個規則都要重複加入 4 個命令
- 新增命令時要修改 3 個規則
- 容易遺漏

使用 Command Group：
- 三個規則都引用同一個 `postgresql-management` group
- 新增命令只需修改 group 一處
- 規則定義更清晰

</details>

<details>
<summary>Q2：sudo rule 中的 command 使用絕對路徑有什麼安全考量？</summary>

**防止 PATH 劫持攻擊。**

如果規則是：
```
alice ALL=(ALL) systemctl restart nginx
```

攻擊者可以：
1. 在 alice 的 PATH 前面加入 `/tmp/evil`
2. 建立 `/tmp/evil/systemctl`（惡意程式）
3. 執行 `sudo systemctl restart nginx` 會執行惡意程式

使用絕對路徑：
```
alice ALL=(ALL) /usr/bin/systemctl restart nginx
```

就能確保執行的是正確的程式。

FreeIPA 預設要求命令使用絕對路徑，這是正確的安全實踐。

</details>

<details>
<summary>Q3：如果 FreeIPA sudo rule 和本機 /etc/sudoers 衝突，哪個優先？</summary>

**取決於 SSSD 和 sudoers 的設定順序。**

在 `/etc/nsswitch.conf` 中：
```
sudoers: files sss
```

這表示：
1. 先查 files（`/etc/sudoers`）
2. 再查 sss（FreeIPA via SSSD）

如果 `/etc/sudoers` 已經允許或拒絕，就不會再查 FreeIPA。

**建議配置**：
```
sudoers: sss files
```

這樣 FreeIPA 的規則優先，本機 `/etc/sudoers` 作為備援（例如 root 帳號的 sudo 權限）。

修改後需要確保本機 `/etc/sudoers` 只保留最基本的設定：
```sudoers
root ALL=(ALL) ALL
```

</details>

## SSSD 與 Sudo 整合

FreeIPA Client 安裝時會自動設定 SSSD 的 sudo provider，但了解其運作方式有助於疑難排解。

### SSSD 設定

查看 `/etc/sssd/sssd.conf`：

```ini
[domain/lab.example.com]
# ... 其他設定 ...

# Sudo provider
sudo_provider = ipa

# 快取設定（可選調整）
# entry_cache_sudo_timeout = 180
```

`sudo_provider = ipa` 告訴 SSSD 從 FreeIPA 取得 sudo 規則。

### 快取機制

SSSD 會快取 sudo 規則以提升效能：

```
User 執行 sudo -l
        │
        ▼
┌───────────────┐
│ SSSD Cache    │ ──► 快取有效？ ──► 是 ──► 直接回傳
│               │           │
└───────────────┘           │ 否
                            ▼
                    ┌───────────────┐
                    │ Query FreeIPA │
                    │    (LDAP)     │
                    └───────────────┘
                            │
                            ▼
                    更新快取，回傳結果
```

預設快取時間是 5400 秒（90 分鐘）。在快取有效期間，FreeIPA 的變更不會立即生效。

### 手動重新整理快取

```bash
# 清除所有快取
sudo sss_cache -E

# 只清除 sudo 快取
sudo sss_cache -s
```

或重啟 SSSD：

```bash
sudo systemctl restart sssd
```

### 驗證 Sudo 規則

```bash
# 以 alice 身份檢查可用的 sudo 權限
sudo -l -U alice
```

輸出範例：

```
Matching Defaults entries for alice on client.lab.example.com:
    !visiblepw, always_set_home, match_group_by_gid, env_reset

User alice may run the following commands on client.lab.example.com:
    (root) NOPASSWD: /usr/bin/docker
    (root) NOPASSWD: /usr/bin/docker-compose
```

如果規則沒有出現：

1. 確認規則已在 FreeIPA 建立：`ipa sudorule-show <rule-name>`
2. 確認使用者/主機符合規則條件
3. 清除 SSSD 快取：`sudo sss_cache -E`
4. 檢查 SSSD 日誌：`journalctl -u sssd`

### SSSD Debug

如果需要深入排查，可以啟用 debug：

```bash
# 編輯 /etc/sssd/sssd.conf
# [domain/lab.example.com]
# debug_level = 6

sudo systemctl restart sssd
sudo -l -U alice
journalctl -u sssd -f
```

Debug level 說明：

| Level | 內容 |
|-------|------|
| 1 | 嚴重錯誤 |
| 2 | 一般錯誤 |
| 4 | 警告 |
| 6 | 操作訊息（推薦 debug 使用） |
| 9 | 非常詳細（大量輸出） |

## 疑難排解

### 問題 1：Sudo 規則不生效

**症狀**：在 FreeIPA 建立了規則，但 `sudo -l` 看不到。

**排查步驟**：

```bash
# 1. 確認規則存在且啟用
ipa sudorule-show <rule-name> --all
# 檢查 Enabled: TRUE

# 2. 確認使用者符合 WHO 條件
ipa sudorule-show <rule-name> --all | grep -E "User|Group"
# 確認使用者在列表中，或屬於指定的 group

# 3. 確認主機符合 WHERE 條件
hostname -f
# 確認主機名稱和 FreeIPA 中的一致

ipa hostgroup-show <hostgroup> --all
# 確認主機在 hostgroup 中

# 4. 清除快取
sudo sss_cache -E

# 5. 重新測試
sudo -l -U <user>
```

### 問題 2：Command Not Found in Sudo Rule

**症狀**：規則顯示正確，但執行時顯示 "sorry, you are not allowed to execute..."

**常見原因**：

1. **路徑不符**：規則中是 `/usr/bin/systemctl`，但使用者執行 `/bin/systemctl`
   ```bash
   # 檢查實際路徑
   which systemctl
   ```

2. **參數不符**：規則中是 `/usr/bin/systemctl restart nginx`，使用者執行 `/usr/bin/systemctl restart httpd`

3. **萬用字元誤用**：
   - `*` 匹配任何參數
   - 但必須放在正確位置

### 問題 3：SSSD 無法連線

**症狀**：所有 sudo 查詢都失敗，使用者甚至無法登入。

**排查**：

```bash
# 檢查 SSSD 狀態
systemctl status sssd

# 檢查 FreeIPA Server 連線
kinit admin
# 如果失敗，檢查網路和 DNS

# 檢查 SSSD 日誌
journalctl -u sssd --since "10 minutes ago"
```

### 問題 4：Sudo 密碼與 Kerberos 密碼不同步

**症狀**：使用者說「我改了密碼但 sudo 還是用舊密碼」

**原因**：SSSD 快取了舊的密碼 hash。

**解決方案**：

```bash
# 清除使用者的快取
sudo sss_cache -u <username>
```

## 總結

在這篇文章中，我們學習了：

1. **集中式 Sudo 管理的優勢**：單點管理、即時生效、完整稽核

2. **Hostgroup**：
   - 主機的邏輯分組
   - 支援巢狀結構
   - 簡化 sudo 和 HBAC 規則

3. **Netgroup**：
   - 傳統 NIS 概念，host+user+domain 三元組
   - 主要用於相容性需求
   - 建議優先使用 Hostgroup

4. **Sudo Rule 設計**：
   - WHO（User/Group）+ WHERE（Host/Hostgroup）+ WHAT（Command）
   - Sudo Command Group 提升可維護性
   - Allow 和 Deny 的優先順序

5. **SSSD 整合**：
   - 快取機制和更新時機
   - Debug 方法

## 下一篇預告

在下一篇文章中，我們會介紹 FreeIPA 與 NFS 的整合：

- NFSv4 + Kerberos 安全架構
- 使用 FreeIPA 管理 NFS service principal
- Automount 自動掛載設定
- 建立安全的家目錄共享環境

## Reference

- [FreeIPA Documentation - Sudo Rules](https://freeipa.readthedocs.io/en/latest/workshop/5-sudorules.html)
- [Red Hat IdM - Configuring Sudo Rules](https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/9/html/managing_idm_users_groups_hosts_and_access_control_rules/granting-sudo-access-to-an-idm-user-on-an-idm-client_managing-idm-users-groups-hosts)
- [SSSD Documentation - Sudo Integration](https://sssd.io/docs/users/sudo_integration.html)
