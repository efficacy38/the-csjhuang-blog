---
title: FreeIPA 與 NFS 整合：Kerberized 家目錄共享完整指南
description: 使用 FreeIPA 與 NFSv4 + Kerberos 建立安全的家目錄共享，包含 automount 自動掛載設定
date: 2026-02-01
slug: freeipa-nfs-kerberos
series: "freeipa"
tags:
    - "freeipa"
    - "nfs"
    - "kerberos"
    - "note"
---

在前面的文章中，我們建立了完整的 FreeIPA 環境，學習了權限系統和 sudo 管理。這篇文章要解決一個常見的企業需求：**讓使用者在任何一台機器登入時，都能存取同一個家目錄**。

:::note
**前置閱讀**

本文假設你已經讀過系列的前幾篇文章，特別是：
- [FreeIPA 實戰：部署企業級 Kerberos 環境](/posts/freeipa-kerberos-deployment)——理解 FreeIPA 架構、keytab 概念

本文會使用「Principal」、「keytab」、「Service Ticket」等 Kerberos 術語。
:::

:::tip
**實驗環境**

本文有配套的 Docker 範例環境，可以快速建立 FreeIPA + NFS 環境：

```bash
git clone https://github.com/csjhuang/the-csjhuang-blog
cd the-csjhuang-blog/examples/blog-freeipa-example
just up      # 部署 FreeIPA 和 NFS Server（約 10-15 分鐘）
just seed    # 建立測試使用者
just shell   # 進入 FreeIPA 容器
```

範例環境已包含 NFS Server（nfs.lab.example.com），可直接用於測試 Kerberized NFS。
:::

## 背景知識速查

| 術語 | 說明 |
|-----|------|
| **Principal** | Kerberos 中的身份識別。使用者 Principal 如 `alice@LAB.EXAMPLE.COM`，服務 Principal 如 `nfs/nfs.lab.example.com@LAB.EXAMPLE.COM` |
| **keytab** | 存放 Principal 密鑰的檔案。服務用它來驗證 Kerberos Ticket，不需要互動式輸入密碼 |
| **TGT** | Ticket Granting Ticket，使用者登入後取得的「通行證」，用來換取其他服務的 Service Ticket |
| **kinit** | 取得 TGT 的命令。`kinit alice` 會提示輸入密碼，成功後 alice 就有了 TGT |
| **rpc-gssd** | RPC GSS-API Daemon，負責處理 NFS 的 Kerberos 認證。Client 和 Server 都需要運行 |
| **idmapd** | NFSv4 ID Mapping Daemon，負責將 `user@domain` 格式轉換為本機 UID/GID |
| **SSSD** | 在 Client 端快取使用者資訊和處理認證的服務 |

詳細說明請參考 [Kerberos 入門指南](/posts/kerberos-101)。

## 擴展實驗環境

本文需要一台額外的機器作為 NFS Server：

| 角色 | Hostname | IP | 說明 |
|-----|----------|-----|------|
| IPA Server | ipa.lab.example.com | 192.168.122.10 | 既有 |
| IPA Client | client.lab.example.com | 192.168.122.20 | 既有 |
| **NFS Server** | **nfs.lab.example.com** | **192.168.122.30** | **新增** |

NFS Server 需要安裝 Rocky Linux 9 或相容的系統，並確保：
- 已設定正確的 hostname（`hostnamectl set-hostname nfs.lab.example.com`）
- DNS 能解析 FreeIPA Server（或手動加入 `/etc/hosts`）
- 防火牆開放 NFS 相關 port

## 為什麼 NFS 需要 Kerberos

### 傳統 NFS 的安全問題

NFSv3 和早期的 NFSv4 使用 `sec=sys`（AUTH_SYS）認證方式，有嚴重的安全隱患：

**問題 1：IP-based Trust**

```
/etc/exports (NFS Server)
─────────────────────────
/export/home  192.168.122.0/24(rw,sync)
```

這表示「只要來自 192.168.122.0/24 網段的請求就信任」。攻擊者只要能偽造來源 IP，就能存取共享目錄。

**問題 2：UID 偽造**

```
┌─────────────────┐                    ┌─────────────────┐
│   NFS Client    │                    │   NFS Server    │
│                 │                    │                 │
│ alice (UID=1000)│ ── request ────►   │ check UID=1000  │
│                 │    UID=1000        │ is this alice?  │
│                 │                    │ (cannot verify) │
└─────────────────┘                    └─────────────────┘
```

Server 無法驗證 UID 是否真的是 alice。攻擊者在惡意 Client 上建立 `UID=1000` 的使用者，就能冒充 alice 存取她的檔案。

**問題 3：無加密傳輸**

所有資料以明文傳輸，在網路上可以被竊聽。

### NFSv4 + Kerberos 的解決方案

```
┌─────────────────┐                    ┌─────────────────┐
│   NFS Client    │                    │   NFS Server    │
│                 │                    │                 │
│  alice has      │                    │  verify Ticket  │
│  Kerberos TGT   │                    │  confirm alice  │
│       │         │                    │       ▲         │
│       ▼         │                    │       │         │
│  get Service    │ ── Ticket ───────► │  use keytab    │
│  Ticket         │   (encrypted)      │  to decrypt    │
└─────────────────┘                    └─────────────────┘
```

Kerberos 解決了所有問題：
- **身份驗證**：透過 Ticket 確認使用者身份
- **防偽造**：Ticket 由 KDC 簽發，無法偽造
- **加密傳輸**：資料可以加密傳輸

### 安全等級比較

NFSv4 支援多種安全等級，透過 `sec=` 選項指定：

| 安全等級 | 認證 | 完整性檢查 | 加密 | 說明 |
|---------|------|-----------|------|------|
| `sec=sys` | 無 | 無 | 無 | 傳統 UID-based，不安全 |
| `sec=krb5` | Kerberos | 無 | 無 | 只驗證身份 |
| `sec=krb5i` | Kerberos | 有 | 無 | 加上資料完整性檢查（防竄改） |
| `sec=krb5p` | Kerberos | 有 | 有 | 完整保護（Privacy） |

**建議**：
- 內部受信任網路：至少使用 `krb5i`
- 跨網段或有安全需求：使用 `krb5p`
- 永遠不要在生產環境使用 `sec=sys`

### 思考題

<details>
<summary>Q1：為什麼有 krb5i 還需要 krb5p？完整性檢查不夠嗎？</summary>

**krb5i 防竄改，krb5p 防竊聽。**

`krb5i`（integrity）：
- 資料以明文傳輸
- 附帶簽章，確保資料沒被修改
- 攻擊者無法修改資料，但**可以看到內容**

`krb5p`（privacy）：
- 資料加密傳輸
- 攻擊者既無法修改，也**無法看到內容**

使用場景：
- 如果只是防止中間人竄改（例如內部網路）→ `krb5i`
- 如果資料本身是機密（例如跨公網、含敏感資訊）→ `krb5p`

代價是 `krb5p` 需要加解密，效能會稍差。

</details>

## NFS Server 加入 FreeIPA

首先，將 NFS Server 加入 FreeIPA 網域。

### 設定 DNS

確保 NFS Server 能解析 FreeIPA Server：

```bash
# 設定 DNS 指向 IPA Server（如果使用 FreeIPA 的 DNS）
sudo nmcli con mod "System eth0" ipv4.dns "192.168.122.10"
sudo nmcli con up "System eth0"

# 驗證
dig ipa.lab.example.com
dig nfs.lab.example.com
```

### 安裝 FreeIPA Client

```bash
sudo dnf install -y freeipa-client nfs-utils
```

### 加入 FreeIPA 網域

```bash
sudo ipa-client-install --mkhomedir
```

按照提示完成安裝：

```
Discovery was successful!
Client hostname: nfs.lab.example.com
Realm: LAB.EXAMPLE.COM
DNS Domain: lab.example.com
IPA Server: ipa.lab.example.com

Continue to configure the system with these values? [no]: yes
User authorized to enroll computers: admin
Password for admin@LAB.EXAMPLE.COM: [輸入密碼]
```

### 建立 NFS Service Principal

```bash
# 取得 admin ticket
kinit admin

# 建立 NFS service principal
ipa service-add nfs/nfs.lab.example.com
```

這會建立一個 Principal：`nfs/nfs.lab.example.com@LAB.EXAMPLE.COM`

### 取得 Keytab

```bash
# 在 NFS Server 上取得 keytab
sudo ipa-getkeytab \
    -s ipa.lab.example.com \
    -p nfs/nfs.lab.example.com \
    -k /etc/krb5.keytab
```

驗證：

```bash
sudo klist -k /etc/krb5.keytab
```

```
Keytab name: FILE:/etc/krb5.keytab
KVNO Principal
---- --------------------------------------------------------------------------
   1 host/nfs.lab.example.com@LAB.EXAMPLE.COM
   1 nfs/nfs.lab.example.com@LAB.EXAMPLE.COM
```

應該會看到 `nfs/nfs.lab.example.com` 這個 Principal。

## NFS Server 設定

### 建立共享目錄

```bash
# 建立目錄結構
sudo mkdir -p /export/home

# 設定權限
sudo chmod 755 /export
sudo chmod 755 /export/home
```

### 設定 /etc/exports

```bash
sudo tee /etc/exports << 'EOF'
/export/home  *.lab.example.com(rw,sync,sec=krb5p,no_subtree_check)
EOF
```

參數說明：

| 參數 | 說明 |
|-----|------|
| `rw` | 讀寫權限 |
| `sync` | 同步寫入（較安全） |
| `sec=krb5p` | 使用 Kerberos 認證 + 加密 |
| `no_subtree_check` | 停用子目錄檢查（效能考量） |

### 啟用服務

```bash
# 啟用 NFS server
sudo systemctl enable --now nfs-server

# 啟用 rpc-gssd（處理 Kerberos 認證）
sudo systemctl enable --now rpc-gssd

# 重新載入 exports
sudo exportfs -rav
```

預期輸出：

```
exporting *.lab.example.com:/export/home
```

### 防火牆設定

```bash
sudo firewall-cmd --permanent --add-service=nfs
sudo firewall-cmd --permanent --add-service=mountd
sudo firewall-cmd --permanent --add-service=rpc-bind
sudo firewall-cmd --reload
```

### 驗證 NFS Server 設定

```bash
# 檢查 exports
showmount -e localhost
```

```
Export list for localhost:
/export/home *.lab.example.com
```

## NFS Client 設定

在 `client.lab.example.com` 上設定掛載。

### 手動掛載測試

首先，確保有有效的 Kerberos ticket：

```bash
kinit alice
klist
```

**為什麼需要 kinit？** 當使用 `sec=krb5p` 掛載時，NFS Client 需要向 NFS Server 證明「我是 alice」。流程是：
1. `kinit alice` 讓 alice 取得 TGT（向 KDC 證明身份）
2. 掛載時，`rpc-gssd` 用 TGT 向 KDC 請求 NFS Server 的 Service Ticket
3. Service Ticket 被送到 NFS Server，Server 用 keytab 驗證
4. 驗證成功，掛載完成

嘗試掛載：

```bash
# 建立掛載點
sudo mkdir -p /mnt/nfs-test

# 手動掛載
sudo mount -t nfs4 -o sec=krb5p nfs.lab.example.com:/export/home /mnt/nfs-test
```

驗證：

```bash
mount | grep nfs
# nfs.lab.example.com:/export/home on /mnt/nfs-test type nfs4 (rw,relatime,sec=krb5p,...)

# 測試寫入
touch /mnt/nfs-test/testfile
ls -la /mnt/nfs-test/
```

如果成功，卸載測試掛載：

```bash
sudo umount /mnt/nfs-test
```

### /etc/fstab 永久掛載

```bash
# 加入 fstab
echo "nfs.lab.example.com:/export/home /mnt/home nfs4 sec=krb5p,_netdev 0 0" | sudo tee -a /etc/fstab

# 建立掛載點
sudo mkdir -p /mnt/home

# 掛載
sudo mount /mnt/home
```

`_netdev` 選項告訴系統這是網路檔案系統，需要在網路啟動後才掛載。

## idmapd 設定

NFSv4 使用 `user@domain` 格式傳輸檔案擁有者資訊，idmapd 負責轉換為本機 UID/GID。

### NFSv4 ID Mapping 原理

```
┌───────────────────┐                  ┌───────────────────┐
│    NFS Client     │                  │    NFS Server     │
│                   │                  │                   │
│ alice             │                  │ alice             │
│ (UID=686600001)   │                  │ (UID=686600001)   │
│       │           │                  │       ▲           │
│       ▼           │                  │       │           │
│    idmapd         │                  │    idmapd         │
│ UID -> user@domain│ ─ alice@lab.example.com ─►│ user@domain -> UID
└───────────────────┘                  └───────────────────┘
```

Client 和 Server 的 idmapd 都需要設定相同的 Domain。

### 設定 /etc/idmapd.conf

在 **NFS Server** 和 **所有 NFS Client** 上：

```bash
sudo vi /etc/idmapd.conf
```

修改 `[General]` 區段：

```ini
[General]
Domain = lab.example.com
```

重啟服務：

```bash
# Server
sudo systemctl restart nfs-idmapd
sudo systemctl restart nfs-server

# Client
sudo systemctl restart nfs-idmapd
```

### 常見問題：nobody/nogroup

**症狀**：掛載後，所有檔案的擁有者都顯示 `nobody` 或 `nogroup`。

```bash
ls -la /mnt/home/
# drwxr-xr-x. 2 nobody nobody 4096 Feb  1 10:00 alice
```

**原因**：idmapd 無法將 `user@domain` 轉換為本機 UID。

**排查步驟**：

1. **檢查 Domain 設定是否一致**
   ```bash
   # Server 和 Client 都要檢查
   grep Domain /etc/idmapd.conf
   ```

2. **確認使用者存在於 SSSD**
   ```bash
   id alice
   # 應該顯示 UID/GID，不是錯誤
   ```

3. **檢查 idmapd 日誌**
   ```bash
   journalctl -u nfs-idmapd
   ```

4. **清除 idmap 快取**
   ```bash
   sudo nfsidmap -c
   ```

5. **重新掛載**
   ```bash
   sudo umount /mnt/home
   sudo mount /mnt/home
   ```

### 思考題

<details>
<summary>Q1：為什麼 NFSv4 需要 idmapd？NFSv3 不需要嗎？</summary>

**NFSv3 直接傳輸 UID/GID 數字，NFSv4 改用 `user@domain` 格式。**

NFSv3 的做法：
```
Client 傳送：UID=1000, GID=1000
Server 直接使用這些數字
```

問題：如果 Server 上 UID=1000 是 bob，但 Client 上 UID=1000 是 alice，就會造成權限混亂。

NFSv4 的做法：
```
Client 傳送：alice@lab.example.com
Server 用 idmapd 轉換為本機的 alice (可能是不同的 UID)
```

這讓 Server 和 Client 可以有不同的 UID 映射，只要使用者名稱一致即可。

在 FreeIPA 環境中，因為 SSSD 確保所有機器的 UID 一致，idmapd 的映射通常是 1:1。但它仍然是必要的，因為 NFSv4 協議要求使用 `user@domain` 格式。

</details>

## Automount 整合

手動設定 `/etc/fstab` 適合固定的掛載點，但對於動態的使用者家目錄，automount 是更好的選擇。

### Automount 的優勢

| 方式 | 優點 | 缺點 |
|-----|------|------|
| /etc/fstab | 簡單、開機即掛載 | 要掛載所有使用者目錄？還是手動新增？ |
| Automount | 動態掛載、使用時才連線 | 設定較複雜 |

使用 automount 時：
- 使用者登入 → 自動掛載 `/home/alice`
- 閒置一段時間 → 自動卸載
- 新使用者不需要修改 Client 設定

### FreeIPA Automount 架構

FreeIPA 的 automount 設定存在 LDAP 中：

```
Location
    │
    └── Map
            │
            └── Key
```

- **Location**（環境）：代表一個環境或站點（如 `default`、`taipei-office`）
- **Map**（掛載對應表）：一組掛載規則的集合（如 `auto.home`）
- **Key**（掛載規則）：具體的掛載規則

### 設定步驟

**步驟 1：建立 Automount Location**

```bash
kinit admin

# 查看現有 location（FreeIPA 預設有 default）
ipa automountlocation-find
```

如果沒有 `default`，建立它：

```bash
ipa automountlocation-add default
```

**步驟 2：建立 Automount Map**

```bash
# 建立 auto.home map
ipa automountmap-add default auto.home
```

**步驟 3：設定 auto.master**

讓 `/home` 使用 `auto.home` map：

```bash
# 在 auto.master 中加入 /home 的設定
ipa automountkey-add default auto.master \
    --key="/home" \
    --info="auto.home"
```

**步驟 4：設定 auto.home 規則**

```bash
# 使用萬用字元：任何使用者都掛載對應的目錄
ipa automountkey-add default auto.home \
    --key="*" \
    --info="-sec=krb5p,rw nfs.lab.example.com:/export/home/&"
```

參數說明：
- `--key="*"`：萬用字元，匹配任何名稱（這是 autofs 標準語法）
- `--info=`：掛載選項和來源
- `&`：autofs 特殊符號，會被替換為實際的 key 值（即使用者名稱）

這個規則的效果：
- 存取 `/home/alice` → 掛載 `nfs.lab.example.com:/export/home/alice`
- 存取 `/home/bob` → 掛載 `nfs.lab.example.com:/export/home/bob`

**步驟 5：驗證設定**

```bash
ipa automountkey-find default auto.master
ipa automountkey-find default auto.home
```

### NFS Server 端準備

確保 NFS Server 上每個使用者都有家目錄：

```bash
# 在 NFS Server 上
sudo mkdir /export/home/alice
sudo chown alice:alice /export/home/alice

sudo mkdir /export/home/bob
sudo chown bob:bob /export/home/bob
```

或建立一個腳本自動處理新使用者：

```bash
#!/bin/bash
# /usr/local/bin/create-home.sh
USER=$1
mkdir -p /export/home/$USER
chown $USER:$USER /export/home/$USER
chmod 700 /export/home/$USER
```

### Client 端設定

**步驟 1：安裝 autofs**

```bash
sudo dnf install -y autofs
```

**步驟 2：設定 SSSD autofs provider**

編輯 `/etc/sssd/sssd.conf`，加入：

```ini
[domain/lab.example.com]
# ... 現有設定 ...

# Autofs provider
autofs_provider = ipa
```

**步驟 3：設定 /etc/nsswitch.conf**

確保 automount 使用 sss：

```bash
grep automount /etc/nsswitch.conf
# automount: files sss
```

如果沒有，修改為：

```bash
sudo sed -i 's/^automount:.*/automount: files sss/' /etc/nsswitch.conf
```

**步驟 4：啟用服務**

```bash
# 重啟 SSSD 載入新設定
sudo systemctl restart sssd

# 啟用 autofs
sudo systemctl enable --now autofs
```

**步驟 5：如果使用 fstab 掛載過 /home，先移除**

```bash
# 卸載
sudo umount /home 2>/dev/null

# 從 fstab 移除 /home 相關的行
sudo vi /etc/fstab
```

### 驗證 Automount

```bash
# 取得 Kerberos ticket
kinit alice

# 嘗試 cd 到家目錄
cd /home/alice
pwd

# 檢查掛載狀態
mount | grep home
```

應該會看到自動掛載：

```
nfs.lab.example.com:/export/home/alice on /home/alice type nfs4 (rw,relatime,sec=krb5p,...)
```

### 思考題

<details>
<summary>Q1：Automount 相比於 /etc/fstab 有什麼優勢？</summary>

**按需掛載、動態管理、減少資源佔用。**

| 面向 | /etc/fstab | Automount |
|-----|-----------|-----------|
| 掛載時機 | 開機時全部掛載 | 使用時才掛載 |
| 資源佔用 | 持續佔用連線 | 閒置時自動卸載 |
| 新使用者 | 需修改 fstab | 自動支援 |
| NFS Server 當機 | 可能造成開機卡住 | 只有存取時才受影響 |
| 適用場景 | 固定、少量掛載點 | 大量動態掛載（如家目錄） |

對於家目錄共享：
- 100 個使用者，只有 10 個在線 → automount 只掛載 10 個
- 使用 fstab 則要掛載全部 100 個，或只掛載 `/home` 根目錄

</details>

<details>
<summary>Q2：如果 NFS Server 暫時無法連線，automount 會怎麼處理？</summary>

**依設定而定，通常會返回錯誤或等待超時。**

當使用者嘗試存取 `/home/alice` 但 NFS Server 無法連線時：

1. autofs 收到請求
2. 嘗試掛載 NFS
3. 連線失敗
4. 返回錯誤（如 "No such file or directory" 或 "Host is down"）

使用者的感受是 `cd /home/alice` 失敗。

優點：
- 不影響系統開機
- 不影響其他使用者
- Server 恢復後自動可用

可調整的超時設定在 `/etc/autofs.conf`：
```ini
# 掛載超時
mount_wait = 30

# 閒置卸載時間
timeout = 300
```

</details>

## 效能調校

Kerberized NFS 會比傳統 NFS 慢，因為需要加解密和驗證。以下是一些調校建議。

### 掛載參數

```bash
# 調整讀寫區塊大小
mount -t nfs4 -o sec=krb5p,rsize=1048576,wsize=1048576 \
    nfs.lab.example.com:/export/home /mnt/home
```

| 參數 | 說明 | 建議值 |
|-----|------|--------|
| `rsize` | 讀取區塊大小 | 1048576 (1MB) |
| `wsize` | 寫入區塊大小 | 1048576 (1MB) |
| `async` | 非同步寫入（較快但較不安全） | 視需求 |
| `noatime` | 不更新存取時間 | 推薦 |

### Kerberos 加密對效能的影響

測試比較（僅供參考，實際數值因環境而異）：

| 安全等級 | 相對效能 | 說明 |
|---------|---------|------|
| sec=sys | 100% | 基準（不安全，不建議使用） |
| sec=krb5 | ~95% | 只驗證，影響小 |
| sec=krb5i | ~85% | 加上完整性檢查 |
| sec=krb5p | ~70% | 加上加密 |

如果效能是關鍵考量：
1. 內部受信任網路可考慮 `krb5i`
2. 確保網路頻寬足夠
3. 考慮使用 SSD 作為 NFS Server 的儲存

### 監控指標

```bash
# NFS 統計資訊
nfsstat -c    # Client 端
nfsstat -s    # Server 端

# 詳細的掛載統計
cat /proc/self/mountstats
```

重點觀察：
- `retrans`：重傳次數（過高表示網路問題）
- `timeout`：超時次數
- `read`/`write`：讀寫操作統計

## 疑難排解

### 問題 1：mount 失敗 - "access denied by server"

**症狀**：

```bash
sudo mount -t nfs4 -o sec=krb5p nfs.lab.example.com:/export/home /mnt/test
# mount.nfs4: access denied by server while mounting nfs.lab.example.com:/export/home
```

**排查**：

1. **檢查 exports 設定**
   ```bash
   # 在 NFS Server 上
   cat /etc/exports
   exportfs -v
   ```

2. **確認 Client 在允許的範圍內**
   - `*.lab.example.com` 是否匹配 Client 的 hostname？
   - DNS 正向和反向解析是否正確？

3. **檢查 rpc-gssd 服務**
   ```bash
   # Server 和 Client 都要檢查
   systemctl status rpc-gssd
   ```

### 問題 2：mount 失敗 - "No supported authentication"

**症狀**：

```bash
# mount.nfs4: No supported authentication
```

**原因**：Kerberos 相關問題。

**排查**：

1. **確認有有效的 TGT**
   ```bash
   klist
   ```

2. **確認 keytab 正確**
   ```bash
   # 在 NFS Server 上
   sudo klist -k /etc/krb5.keytab | grep nfs
   ```

3. **檢查時間同步**
   ```bash
   timedatectl
   chronyc tracking
   ```

### 問題 3：可以掛載但無法寫入

**症狀**：掛載成功，但 `touch file` 顯示 "Permission denied"。

**排查**：

1. **檢查 exports 是否有 `rw`**
   ```bash
   exportfs -v
   ```

2. **檢查目錄權限**
   ```bash
   # 在 NFS Server 上
   ls -la /export/home/
   ```

3. **確認 idmapd 正確映射**
   ```bash
   ls -la /mnt/home/
   # 如果顯示 nobody，是 idmapd 問題
   ```

### 問題 4：GSS-API 錯誤

**症狀**：日誌中出現 `GSS-API` 相關錯誤。

**排查**：

```bash
# 在 NFS Server 上啟用 RPC debug
rpcdebug -m nfs -s all
rpcdebug -m rpc -s all

# 檢查日誌
journalctl -f

# 完成後關閉 debug
rpcdebug -m nfs -c all
rpcdebug -m rpc -c all
```

常見 GSS 錯誤：

| 錯誤 | 可能原因 |
|-----|---------|
| "Server not found in Kerberos database" | NFS Principal 不存在或 keytab 錯誤 |
| "Clock skew too great" | 時間不同步 |
| "Ticket expired" | TGT 過期，需重新 kinit |

### Debug 清單

```bash
# 1. 基本連通性
ping nfs.lab.example.com
showmount -e nfs.lab.example.com

# 2. DNS
dig nfs.lab.example.com
dig -x 192.168.122.30

# 3. Kerberos
klist
kvno nfs/nfs.lab.example.com@LAB.EXAMPLE.COM

# 4. 服務狀態
systemctl status nfs-server rpc-gssd    # Server
systemctl status rpc-gssd autofs        # Client

# 5. 日誌
journalctl -u nfs-server -u rpc-gssd --since "10 minutes ago"
```

## 完整流程總結

```
┌─────────────────────────────────────────────────────────────────────┐
│               NFS + Kerberos + FreeIPA Architecture                 │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  ┌───────────────────────────────────────────────────────────────┐  │
│  │                      FreeIPA Server                           │  │
│  │  ┌────────┐  ┌────────┐  ┌────────┐  ┌──────────┐            │  │
│  │  │  KDC   │  │  LDAP  │  │  DNS   │  │ Automount│            │  │
│  │  │        │  │        │  │        │  │   Maps   │            │  │
│  │  └────────┘  └────────┘  └────────┘  └──────────┘            │  │
│  └───────────────────────────────────────────────────────────────┘  │
│          │            │            │            │                   │
│          │ TGT/       │ User/      │ Name       │ Automount         │
│          │ Ticket     │ Group      │ Resolution │ Config            │
│          ▼            ▼            ▼            ▼                   │
│  ┌───────────────────────────────────────────────────────────────┐  │
│  │                       NFS Server                              │  │
│  │  ┌────────┐  ┌────────┐  ┌────────────┐                      │  │
│  │  │  SSSD  │  │ idmapd │  │ nfs-server │                      │  │
│  │  │        │  │        │  │  rpc-gssd  │                      │  │
│  │  └────────┘  └────────┘  └────────────┘                      │  │
│  │       │           │            │                              │  │
│  │       │           │            │ /export/home                 │  │
│  └───────┼───────────┼────────────┼──────────────────────────────┘  │
│          │           │            │                                 │
│          │           │            │ NFSv4 + sec=krb5p               │
│          ▼           ▼            ▼                                 │
│  ┌───────────────────────────────────────────────────────────────┐  │
│  │                       NFS Client                              │  │
│  │  ┌────────┐  ┌────────┐  ┌────────┐  ┌────────┐              │  │
│  │  │  SSSD  │  │ idmapd │  │ autofs │  │rpc-gssd│              │  │
│  │  └────────┘  └────────┘  └────────┘  └────────┘              │  │
│  │                              │                                │  │
│  │                              ▼                                │  │
│  │                        /home/alice                            │  │
│  │                      (auto-mounted)                           │  │
│  └───────────────────────────────────────────────────────────────┘  │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

## 總結

在這篇文章中，我們學習了：

1. **為什麼 NFS 需要 Kerberos**：
   - 傳統 NFS 的安全問題（IP trust、UID 偽造）
   - sec=krb5/krb5i/krb5p 的差異

2. **NFS Server 設定**：
   - 加入 FreeIPA 網域
   - 建立 NFS service principal 和 keytab
   - 設定 /etc/exports

3. **idmapd 設定**：
   - NFSv4 ID mapping 原理
   - nobody/nogroup 問題排解

4. **Automount 整合**：
   - FreeIPA 管理 automount 設定
   - 動態掛載使用者家目錄

5. **效能調校與疑難排解**：
   - 掛載參數最佳化
   - 常見問題排查方法

## 系列回顧

到此，FreeIPA 系列的核心內容已經完成：

| 篇章 | 主題 | 涵蓋內容 |
|-----|------|---------|
| 000 | Kerberos 入門 | 協議原理、核心概念 |
| 001 | FreeIPA 部署 | Server/Client 安裝、使用者管理 |
| 002 | Keycloak 整合 | User Federation、OAuth2/OIDC |
| 003 | Kerberos 委派 | Delegation、Web App 後端存取 |
| 004 | 憑證管理 | PKI、certmonger、ACME |
| 005 | 權限系統 | Group、RBAC、Self-service |
| 006 | Sudo 管理 | Hostgroup、Sudo Rule、SSSD |
| 007 | NFS 整合 | Kerberized NFS、Automount |

這些知識組合起來，你可以建立一個完整的企業級身份管理環境：集中式認證、細粒度權限控制、安全的檔案共享。

## Reference

- [FreeIPA Documentation - NFS](https://freeipa.readthedocs.io/en/latest/workshop/6-automount.html)
- [Red Hat IdM - Configuring NFS](https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/9/html/managing_file_systems/configuring-an-nfs-server-to-use-kerberos_managing-file-systems)
- [Linux NFS-HOWTO](https://tldp.org/HOWTO/NFS-HOWTO/)
- [MIT Kerberos - GSS-API](https://web.mit.edu/kerberos/krb5-latest/doc/appdev/gssapi.html)
