---
title: Ansible 實戰：專案結構與 Convention
description: 介紹 Ansible 專案的標準目錄結構、常見 Convention，以及本系列將要建構的 Flask + Nginx + PostgreSQL 三層架構
pubDate: 2026-02-02
slug: ansible-001-project-structure
series: "ansible"
tags:
    - "ansible"
    - "devops"
    - "note"
---

這是 Ansible 實戰系列的第一篇文章。在這個系列中，我們會從零開始建構一個完整的 **Flask + Nginx + PostgreSQL** 三層式應用部署專案，過程中學習 Ansible 的各種功能與最佳實踐。

本系列假設你已經有 Ansible 的基礎知識——知道什麼是 playbook、跑過幾個簡單的 playbook，但還沒有自己從頭寫過 role。

## 系列文章總覽

| 篇章 | 主題 | 核心內容 |
|------|------|----------|
| 1 | [專案結構與 Convention](/posts/ansible-001-project-structure) | 目錄結構、Role 組織、ansible.cfg、CLI 工具 |
| 2 | [Inventory 與變數管理](/posts/ansible-002-inventory-variables) | group_vars、host_vars、變數優先順序 |
| 3 | [撰寫 PostgreSQL Role](/posts/ansible-003-postgresql-role) | Role 結構、Template/Jinja2、Handlers |
| 4 | [撰寫 Flask App Role](/posts/ansible-004-flask-app-role) | virtualenv、systemd、條件執行、迴圈 |
| 5 | [Nginx Role 與專案整合](/posts/ansible-005-nginx-integration) | 反向代理、Tags 策略、多 Playbook 設計 |
| 6 | [Vault、進階技巧與測試](/posts/ansible-006-vault-advanced-testing) | 加密、Lookup Plugins、Rolling Update、Ansible Lint |

## 為什麼需要標準化的專案結構？

當你剛開始學 Ansible 時，可能會把所有東西塞進一個 playbook 裡：

```yaml
# deploy.yml - 100+ 行的單一 playbook
- hosts: all
  tasks:
    - name: Install Nginx
      apt: name=nginx state=present
    - name: Configure Nginx
      template: src=nginx.conf.j2 dest=/etc/nginx/nginx.conf
    # ... 50 個 tasks
    - name: Install PostgreSQL
      apt: name=postgresql state=present
    # ... 又 50 個 tasks
```

這在專案小的時候還可以，但當專案開始成長：

| 問題 | 後果 |
|-----|------|
| 單一 playbook 過長 | 難以閱讀和維護 |
| tasks 無法重用 | 每個專案都要複製貼上 |
| 變數散落各處 | 不知道某個變數是在哪裡定義的 |
| 多環境部署困難 | dev/staging/production 的差異難以管理 |
| 團隊協作困難 | 不知道該改哪個檔案 |

標準化的專案結構解決這些問題：**每個檔案都有明確的職責，團隊成員一看就知道東西放在哪裡。**

## Ansible 官方推薦的專案結構

根據 [Ansible 官方文件](https://docs.ansible.com/projects/ansible/latest/tips_tricks/sample_setup.html)，推薦的專案結構如下：

```
my-ansible-project/
├── ansible.cfg              # Ansible 設定檔
├── requirements.yml         # 外部 Collection/Role 依賴
│
├── inventory/               # Inventory 目錄
│   ├── production/          # Production 環境
│   │   ├── hosts            # 主機清單
│   │   ├── group_vars/      # 群組變數（YAML 格式）
│   │   │   ├── all.yml      # 套用到所有主機
│   │   │   ├── webservers.yml
│   │   │   └── dbservers.yml
│   │   └── host_vars/       # 主機變數（YAML 格式）
│   │       └── web01.yml    # 套用到 web01 主機
│   │
│   └── staging/             # Staging 環境
│       ├── hosts
│       ├── group_vars/
│       └── host_vars/
│
├── roles/                   # 自訂 Roles
│   ├── common/              # 通用設定 role
│   │   ├── tasks/
│   │   │   └── main.yml
│   │   ├── handlers/
│   │   │   └── main.yml
│   │   ├── templates/
│   │   ├── files/
│   │   ├── defaults/
│   │   │   └── main.yml
│   │   └── meta/
│   │       └── main.yml
│   │
│   ├── nginx/
│   ├── flask_app/
│   └── postgresql/
│
├── playbooks/               # Playbooks（可選，也可放在根目錄）
│   ├── site.yml             # 完整部署
│   ├── webservers.yml       # 只部署 Web 層
│   └── dbservers.yml        # 只部署 DB 層
│
└── site.yml                 # 主 playbook（或放在 playbooks/）
```

### 各目錄職責

| 目錄/檔案 | 職責 |
|----------|------|
| `ansible.cfg` | Ansible 的行為設定（inventory 路徑、SSH 設定等） |
| `requirements.yml` | 外部 Collection/Role 的依賴清單 |
| `inventory/` | 主機清單和變數，依環境分開 |
| `group_vars/` | 套用到特定 group 的變數 |
| `host_vars/` | 套用到特定 host 的變數 |
| `roles/` | 可重用的 role，每個 role 負責一個單一職責 |
| `playbooks/` | 各種 playbook，組合 roles 完成特定任務 |

### group_vars 與 host_vars 的 YAML 格式

變數檔案使用標準 YAML 格式：

```yaml
# inventory/production/group_vars/all.yml
---
# 通用設定
timezone: "Asia/Taipei"
ntp_servers:
  - time.google.com
  - time.cloudflare.com

# 應用程式設定
app_env: production
app_debug: false
```

```yaml
# inventory/production/group_vars/webservers.yml
---
nginx_worker_processes: 4
nginx_worker_connections: 2048
```

```yaml
# inventory/production/host_vars/web01.yml
---
# 這台主機的特定設定
ansible_host: 192.168.1.101
nginx_worker_processes: 8  # 覆寫 group_vars 的值
```

## Role 的目錄結構

Role 是 Ansible 最重要的重用單位。每個 role 有固定的目錄結構：

```
roles/nginx/
├── tasks/
│   └── main.yml        # 必要：主要的 tasks
├── handlers/
│   └── main.yml        # 可選：handlers（如 restart service）
├── templates/
│   └── nginx.conf.j2   # 可選：Jinja2 模板
├── files/
│   └── ssl.crt         # 可選：靜態檔案
├── defaults/
│   └── main.yml        # 可選：預設變數（優先順序最低）
├── vars/
│   └── main.yml        # 可選：role 變數（優先順序較高）
└── meta/
    └── main.yml        # 可選：role 依賴、metadata
```

### defaults vs vars

這兩個目錄都是放變數，差別在於**優先順序**：

| 目錄 | 優先順序 | 用途 |
|-----|---------|------|
| `defaults/` | 最低 | 「預設值」，使用者應該覆寫的變數 |
| `vars/` | 較高 | 「內部變數」，使用者通常不該覆寫 |

```yaml
# roles/nginx/defaults/main.yml
# 使用者可以覆寫這些值
nginx_worker_processes: auto
nginx_worker_connections: 1024

# roles/nginx/vars/main.yml
# 內部使用，使用者不該覆寫
nginx_config_path: /etc/nginx/nginx.conf
nginx_service_name: nginx
```

### 思考題

<details>
<summary>Q1：為什麼要把 inventory 依環境（production/staging）分開，而不是用一個大的 hosts 檔案？</summary>

**安全性和清晰度**：

1. **降低誤操作風險**：當你執行 `ansible-playbook -i inventory/staging` 時，不可能誤觸 production 的主機
2. **變數隔離**：每個環境有自己的 `group_vars/`，可以設定不同的密碼、endpoint、資源規格
3. **權限控制**：可以讓部分人員只存取 staging inventory，不能看到 production 的資訊
4. **清晰度**：一眼就知道這次部署的目標環境

**反例**：如果用一個大的 hosts 檔案，你可能會這樣寫：

```ini
[webservers_production]
prod-web01

[webservers_staging]
staging-web01
```

這樣 `group_vars/webservers_production.yml` 的名稱很長，而且執行時還要用 `--limit` 來限制，很容易出錯。

</details>

<details>
<summary>Q2：什麼時候該把變數放在 defaults/，什麼時候放在 vars/？</summary>

**放在 defaults/ 的情況**：

- 使用者「應該」或「可能」要覆寫的值
- 例如：port number、worker count、app version

```yaml
# defaults/main.yml
flask_app_port: 5000       # 使用者可能想改成其他 port
flask_workers: 4           # 使用者可能依機器規格調整
flask_app_version: "1.0.0" # 使用者會指定要部署的版本
```

**放在 vars/ 的情況**：

- role 內部使用的值，使用者通常不該改
- 例如：config 檔路徑、service name、package name

```yaml
# vars/main.yml
flask_config_path: /etc/flask-app/config.py  # 這是我們 role 的設計
flask_service_name: flask-app                # 這是我們 role 建立的 service
```

**經驗法則**：如果你在文件中會寫「使用者可以設定這個變數來...」，就放 defaults/；如果是 role 實作細節，就放 vars/。

</details>

## 常見的 Ansible 專案範例

在開始寫自己的專案之前，看看別人怎麼做是很有幫助的。

### 1. Ansible 官方範例

Ansible 官方文件中的 [Sample Setup](https://docs.ansible.com/projects/ansible/latest/tips_tricks/sample_setup.html) 提供了兩種佈局：

**單一 inventory 佈局**（適合小型專案）：
```
production          # inventory file
staging             # inventory file
group_vars/
host_vars/
roles/
site.yml
```

**依環境分離的佈局**（適合中大型專案）：
```
inventories/
    production/
    staging/
roles/
site.yml
```

### 2. DebOps

[DebOps](https://github.com/debops/debops) 是一個大型的 Ansible 專案集合，提供了 200+ 個 roles 用於 Debian/Ubuntu 系統管理。

特點：
- 每個 role 職責單一，高度模組化
- 完整的文件和測試
- 適合學習「大型專案如何組織」

### 3. Geerlingguy 的 Roles

[Jeff Geerling](https://github.com/geerlingguy) 是 Ansible 社群的知名貢獻者，他的 roles 是學習 best practices 的好素材：

- [geerlingguy.docker](https://github.com/geerlingguy/ansible-role-docker)
- [geerlingguy.nginx](https://github.com/geerlingguy/ansible-role-nginx)
- [geerlingguy.postgresql](https://github.com/geerlingguy/ansible-role-postgresql)

這些 roles 的特點：
- 結構清晰，遵循 Ansible 慣例
- 變數設計合理，有完整的 defaults
- 支援多個 Linux 發行版
- 有 Molecule 測試

## 本系列的專案結構

在這個系列中，我們會建構一個 Flask + Nginx + PostgreSQL 的專案。以下是我們的目標結構：

```
flask-deploy/
├── ansible.cfg
├── requirements.yml         # 使用官方 collection
│
├── inventory/
│   ├── dev/                 # 開發環境
│   │   ├── hosts
│   │   └── group_vars/
│   │       ├── all.yml
│   │       ├── web.yml
│   │       └── db.yml
│   │
│   └── production/          # 生產環境
│       ├── hosts
│       └── group_vars/
│           └── ...
│
├── roles/
│   ├── common/              # 基礎設定（時區、套件等）
│   ├── postgresql/          # PostgreSQL 安裝與設定
│   ├── flask_app/           # Flask 應用部署
│   └── nginx/               # Nginx 安裝與反向代理
│
├── site.yml                 # 完整部署
├── deploy_app.yml           # 只更新應用
└── rolling_restart.yml      # 滾動重啟
```

### 我們會使用的官方 Collections

```yaml
# requirements.yml
collections:
  - name: community.postgresql
    version: ">=3.0.0"
  - name: community.general
    version: ">=8.0.0"
```

使用官方 collection 的好處：
- 不用自己實作 PostgreSQL 的各種 module
- 有社群維護，bug fix 和新功能持續更新
- 文件完整，有大量使用範例

## 環境準備

### 安裝 Ansible

```bash
# Ubuntu/Debian
sudo apt update
sudo apt install ansible

# 或使用 pip（推薦，版本較新）
pip install ansible

# 確認版本
ansible --version
```

### 安裝 Collection

```bash
# 安裝 requirements.yml 中的 collections
ansible-galaxy collection install -r requirements.yml
```

### 建立專案骨架

```bash
# 建立專案目錄
mkdir flask-deploy && cd flask-deploy

# 建立目錄結構
mkdir -p inventory/{dev,production}/group_vars
mkdir -p roles/{common,postgresql,flask_app,nginx}/{tasks,handlers,templates,defaults}

# 建立基本檔案
touch ansible.cfg requirements.yml site.yml
touch inventory/dev/hosts
touch inventory/dev/group_vars/{all,web,db}.yml
```

### 基本的 ansible.cfg

```ini
# ansible.cfg
[defaults]
inventory = inventory/dev
roles_path = roles
host_key_checking = False
retry_files_enabled = False

[privilege_escalation]
become = True
become_method = sudo
```

### 進階 ansible.cfg 設定

以下是一些實用的進階設定：

```ini
# ansible.cfg
[defaults]
inventory = inventory/dev
roles_path = roles
host_key_checking = False
retry_files_enabled = False

# === 輸出格式 ===
# 使用 YAML 格式輸出（更易讀）
stdout_callback = yaml
# 其他選項：json, debug, minimal, dense

# 顯示 task 執行時間
callback_whitelist = profile_tasks, timer
# profile_tasks: 顯示每個 task 的執行時間
# timer: 顯示總執行時間

# 彩色輸出
force_color = True

# === 效能優化 ===
# 同時連線的主機數
forks = 20

# 使用 SSH pipelining（減少 SSH 連線次數）
pipelining = True

# Fact caching（避免每次都重新收集 facts）
gathering = smart
fact_caching = jsonfile
fact_caching_connection = .ansible_fact_cache
fact_caching_timeout = 86400

# === 其他實用設定 ===
# 顯示跳過的 task
display_skipped_hosts = True

# 顯示 diff（設定檔變更時）
diff_always = True

# Vault 密碼檔（小心不要 commit）
# vault_password_file = .vault_password

[privilege_escalation]
become = True
become_method = sudo

[ssh_connection]
# SSH 連線優化
ssh_args = -o ControlMaster=auto -o ControlPersist=60s
# 傳輸壓縮
transfer_method = smart
```

**常用的 stdout_callback 選項**：

| Callback | 說明 |
|----------|------|
| `yaml` | YAML 格式，易讀 |
| `json` | JSON 格式，適合程式處理 |
| `debug` | 詳細 debug 資訊 |
| `minimal` | 最精簡輸出 |
| `dense` | 單行顯示每個 task |
| `unixy` | Unix 風格的簡潔輸出 |

你可以用 `ansible-config list` 查看所有可用設定，或用 `ansible-doc -t callback -l` 列出所有 callback plugins。

### 思考題

<details>
<summary>Q1：為什麼建議用 pip 安裝 Ansible 而不是用系統套件管理器？</summary>

**版本問題**：

系統套件管理器（apt/yum）提供的 Ansible 通常版本較舊。以 Ubuntu 22.04 為例，apt 提供的可能是 Ansible 2.10，但最新版是 Ansible 8.x（core 2.15）。

新版本的好處：
- 新功能（如更好的 collection 支援）
- Bug fixes
- 效能改進
- 新 module 和 plugin

**虛擬環境**：

用 pip 安裝還可以搭配 virtualenv，讓不同專案使用不同版本的 Ansible：

```bash
python -m venv venv
source venv/bin/activate
pip install ansible==8.0.0
```

</details>

<details>
<summary>Q2：ansible.cfg 中的 host_key_checking = False 有什麼安全隱患？</summary>

**風險**：

當 `host_key_checking = False` 時，Ansible 不會驗證 SSH host key，這表示：

1. **MITM 攻擊**：攻擊者可以在你和目標主機之間插入一台假主機，Ansible 不會發現
2. **主機被替換**：如果目標主機被攻擊者替換（IP 相同但機器不同），你不會收到警告

**何時可以關閉**：

- 開發/測試環境（經常重建 VM，host key 會變）
- 受信任的內網環境
- 使用其他方式驗證主機身份（如 cloud provider 的 metadata）

**生產環境建議**：

```ini
[defaults]
host_key_checking = True
```

並在第一次連線時手動確認 host key，或使用 `known_hosts` 檔案預先部署正確的 host key。

</details>

## 常用的 Ansible CLI 工具

除了 `ansible-playbook`，Ansible 還提供許多實用的 CLI 工具：

### ansible-doc：查詢 Module 文件

```bash
# 列出所有可用的 module
ansible-doc -l

# 查詢特定 module 的用法
ansible-doc ansible.builtin.apt
ansible-doc community.postgresql.postgresql_db

# 只顯示範例
ansible-doc -s ansible.builtin.template
```

這比上網查文件更快，而且保證和你安裝的版本一致。

### ansible-inventory：檢視 Inventory 結構

```bash
# 顯示 inventory 的主機清單
ansible-inventory -i inventory/dev --list

# 以樹狀結構顯示
ansible-inventory -i inventory/dev --graph

# 顯示特定主機的所有變數
ansible-inventory -i inventory/dev --host web01
```

這對於 debug 變數優先順序特別有用——你可以看到最終套用到某台主機的所有變數。

### ansible-config：檢視設定

```bash
# 顯示目前的設定（包含來源）
ansible-config dump

# 只顯示已變更的設定
ansible-config dump --only-changed

# 列出所有可用的設定項目
ansible-config list
```

### ansible-lint：靜態分析

```bash
# 安裝
pip install ansible-lint

# 檢查 playbook
ansible-lint site.yml

# 檢查整個專案
ansible-lint
```

Ansible Lint 會檢查最佳實踐違規，例如沒有使用 FQCN、task 沒有 name 等。

### ansible-test：測試框架（進階）

```bash
# 主要用於 Collection 開發
ansible-test sanity
ansible-test units
ansible-test integration
```

`ansible-test` 主要用於開發 Collection 時進行測試，一般專案較少使用。

### 實用組合技

```bash
# 查看某個 module 有哪些參數
ansible-doc community.postgresql.postgresql_user | grep -A5 "PARAMETERS"

# 確認變數是否正確套用到主機
ansible-inventory -i inventory/dev --host db01 | grep postgresql

# Dry-run 前先檢查語法
ansible-lint site.yml && ansible-playbook site.yml --syntax-check
```

## 總結

在這篇文章中，我們介紹了：

1. **為什麼需要標準化的專案結構**
   - 提高可讀性和可維護性
   - 促進程式碼重用
   - 簡化團隊協作

2. **Ansible 官方推薦的專案結構**
   - inventory 依環境分離
   - roles 職責單一
   - group_vars/host_vars 管理變數

3. **Role 的目錄結構**
   - tasks, handlers, templates, files
   - defaults vs vars 的差異

4. **常見的開源專案參考**
   - DebOps、Geerlingguy 的 roles

5. **本系列的目標專案結構**
   - Flask + Nginx + PostgreSQL 三層架構
   - 使用官方 community.postgresql collection

## 下一篇預告

在下一篇文章中，我們會深入探討 **Inventory 與變數管理**，包括：

- 如何設計多環境的 inventory
- group_vars 和 host_vars 的使用時機
- Ansible 的變數優先順序（Variable Precedence）
- 建立我們 Flask 專案的 inventory

## Reference

- [Ansible Documentation - Sample Setup](https://docs.ansible.com/projects/ansible/latest/tips_tricks/sample_setup.html)
- [Ansible Documentation - Best Practices](https://docs.ansible.com/ansible/latest/tips_tricks/ansible_tips_tricks.html)
- [Good Practices for Ansible - Red Hat Community of Practice](https://redhat-cop.github.io/automation-good-practices/)
