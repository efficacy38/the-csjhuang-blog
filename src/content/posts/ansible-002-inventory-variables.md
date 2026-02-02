---
title: Ansible 實戰：Inventory 與變數管理
description: 深入介紹 Ansible 的 Inventory 設計、group_vars/host_vars 的使用時機，以及變數優先順序
pubDate: 2026-02-02
slug: ansible-002-inventory-variables
series: "ansible"
tags:
    - "ansible"
    - "devops"
    - "note"
---

:::note
**前置閱讀**

本文假設你已經讀過系列的第一篇文章：
- [Ansible 實戰：專案結構與 Convention](/posts/ansible-001-project-structure)——理解 Ansible 專案的目錄結構

本文會使用「role」、「playbook」等 Ansible 基礎術語。
:::

在上一篇文章中，我們介紹了 Ansible 專案的標準結構。這篇文章會深入探討 **Inventory**——Ansible 用來定義「要管理哪些主機」的機制，以及如何透過 **group_vars** 和 **host_vars** 來管理變數。

## Inventory 基礎

Inventory 是 Ansible 的核心概念之一，它定義了：
- 有哪些主機（hosts）
- 主機如何分組（groups）
- 每個主機/群組的變數

### INI 格式

最簡單的 inventory 是 INI 格式：

```ini
# inventory/dev/hosts

# 單獨的主機
192.168.1.10

# 定義群組
[web]
web01 ansible_host=192.168.1.11
web02 ansible_host=192.168.1.12

[db]
db01 ansible_host=192.168.1.20

# 群組的群組
[app:children]
web
db
```

**常用的 inventory 變數：**

| 變數 | 說明 |
|-----|------|
| `ansible_host` | 實際連線的 IP 或 hostname |
| `ansible_port` | SSH port（預設 22） |
| `ansible_user` | SSH 使用者 |
| `ansible_ssh_private_key_file` | SSH 私鑰路徑 |
| `ansible_become` | 是否使用 sudo |
| `ansible_python_interpreter` | Python 路徑 |

### YAML 格式

同樣的 inventory 也可以用 YAML 格式：

```yaml
# inventory/dev/hosts.yml
all:
  children:
    web:
      hosts:
        web01:
          ansible_host: 192.168.1.11
        web02:
          ansible_host: 192.168.1.12
    db:
      hosts:
        db01:
          ansible_host: 192.168.1.20
    app:
      children:
        web:
        db:
```

**INI vs YAML**：兩者功能相同，選擇看團隊習慣。YAML 格式在處理複雜巢狀結構時較清晰，INI 格式在簡單場景下較簡潔。

### 特殊群組

Ansible 有兩個內建的特殊群組：

| 群組 | 說明 |
|-----|------|
| `all` | 包含所有主機 |
| `ungrouped` | 不屬於任何群組的主機 |

```ini
# 這台主機屬於 ungrouped
192.168.1.100

[web]
web01
```

## 多環境 Inventory

在實務上，我們通常有多個環境（dev、staging、production）。每個環境有不同的主機和設定。

### 目錄結構

```
inventory/
├── dev/
│   ├── hosts
│   └── group_vars/
│       ├── all.yml
│       ├── web.yml
│       └── db.yml
│
├── staging/
│   ├── hosts
│   └── group_vars/
│       └── ...
│
└── production/
    ├── hosts
    └── group_vars/
        └── ...
```

### 執行時指定環境

```bash
# 部署到 dev 環境
ansible-playbook -i inventory/dev site.yml

# 部署到 production 環境
ansible-playbook -i inventory/production site.yml
```

### 我們專案的 Inventory

讓我們為 Flask 專案建立 dev 環境的 inventory：

```ini
# inventory/dev/hosts

[web]
web01 ansible_host=192.168.56.11

[db]
db01 ansible_host=192.168.56.20

[flask:children]
web
db
```

這個 inventory 定義了：
- `web` 群組：包含 Flask 應用和 Nginx 的主機
- `db` 群組：包含 PostgreSQL 的主機
- `flask` 群組：包含所有相關主機（方便一次操作）

## group_vars 與 host_vars

Inventory 檔案只適合放少量變數。當變數變多時，應該使用 `group_vars/` 和 `host_vars/` 目錄。

### group_vars

`group_vars/` 目錄下的檔案會套用到對應群組的所有主機：

```
inventory/dev/group_vars/
├── all.yml      # 套用到所有主機
├── web.yml      # 套用到 web 群組
└── db.yml       # 套用到 db 群組
```

```yaml
# inventory/dev/group_vars/all.yml
# 所有主機共用的變數
ansible_user: deploy
ansible_become: true
timezone: Asia/Taipei

# 應用相關
app_name: flask-demo
app_env: development
```

```yaml
# inventory/dev/group_vars/web.yml
# Web 群組專用變數
nginx_worker_processes: 2
flask_app_port: 5000
flask_workers: 2
```

```yaml
# inventory/dev/group_vars/db.yml
# DB 群組專用變數
postgresql_version: 15
postgresql_port: 5432
postgresql_max_connections: 100

# 資料庫設定
postgresql_databases:
  - name: flask_demo
    encoding: UTF8

postgresql_users:
  - name: flask_app
    password: "{{ vault_postgresql_flask_app_password }}"
    role_attr_flags: LOGIN
```

### host_vars

當某台主機需要特殊設定時，使用 `host_vars/`：

```
inventory/dev/host_vars/
└── web01.yml    # 只套用到 web01
```

```yaml
# inventory/dev/host_vars/web01.yml
# web01 的特殊設定
nginx_worker_processes: 4  # 這台機器規格較好，給多一點
```

### 目錄 vs 檔案

`group_vars/` 和 `host_vars/` 也支援用**目錄**來組織變數：

```
inventory/dev/group_vars/
├── all.yml           # 單一檔案
└── db/               # 或用目錄
    ├── main.yml
    └── vault.yml     # 加密的變數放這裡
```

當 Ansible 讀取 `group_vars/db` 時，會自動載入目錄下的所有 `.yml` 檔案。這在使用 Ansible Vault 加密部分變數時特別有用。

## 變數優先順序

Ansible 有很多地方可以定義變數，當同名變數在多處定義時，哪個會生效？

### 完整的優先順序（由低到高）

1. command line values (e.g. `-u user`)
2. role defaults (`roles/x/defaults/main.yml`)
3. inventory file or script group vars
4. inventory `group_vars/all`
5. playbook `group_vars/all`
6. inventory `group_vars/*`
7. playbook `group_vars/*`
8. inventory file or script host vars
9. inventory `host_vars/*`
10. playbook `host_vars/*`
11. host facts / cached `set_facts`
12. play vars
13. play `vars_prompt`
14. play `vars_files`
15. role vars (`roles/x/vars/main.yml`)
16. block vars (only for tasks in block)
17. task vars (only for the task)
18. `include_vars`
19. `set_facts` / registered vars
20. role (and `include_role`) params
21. `include` params
22. extra vars (`-e "key=value"`)

### 實務上常用的簡化版

記住這個簡化版就夠應付大多數情況：

```
低 ← ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ → 高

role defaults → inventory group_vars/all → inventory group_vars/*
→ inventory host_vars/* → role vars → extra vars (-e)
```

**經驗法則：**

| 變數定義位置 | 用途 |
|------------|------|
| `roles/*/defaults/` | Role 的預設值，使用者應該覆寫 |
| `group_vars/all` | 環境共用的基礎設定 |
| `group_vars/<group>` | 特定群組的設定 |
| `host_vars/<host>` | 特定主機的設定 |
| `roles/*/vars/` | Role 內部使用，不該被覆寫 |
| `-e` extra vars | 臨時覆寫，CI/CD 中常用 |

### 實例說明

假設我們有以下變數定義：

```yaml
# roles/nginx/defaults/main.yml
nginx_worker_processes: auto

# inventory/dev/group_vars/all.yml
nginx_worker_processes: 2

# inventory/dev/group_vars/web.yml
nginx_worker_processes: 4

# inventory/dev/host_vars/web01.yml
nginx_worker_processes: 8
```

當在 `web01` 上執行時，`nginx_worker_processes` 的值是 **8**（host_vars 優先）。

當在 `web02` 上執行時，`nginx_worker_processes` 的值是 **4**（group_vars/web 生效）。

### 思考題

<details>
<summary>Q1：如果我想讓某個變數「絕對不會被覆寫」，應該放在哪裡？</summary>

**放在 `roles/*/vars/main.yml`**，因為它的優先順序很高。

但更好的做法是：**不要阻止覆寫**。如果某個值真的不該被改，應該是在程式碼邏輯中處理，而不是靠變數優先順序。

唯一例外是像檔案路徑這種「role 實作細節」的變數，這類變數放 `vars/` 是合理的。

</details>

<details>
<summary>Q2：為什麼 extra vars (-e) 的優先順序最高？這有什麼用？</summary>

**用途**：

1. **臨時覆寫**：部署時臨時指定版本
   ```bash
   ansible-playbook site.yml -e "app_version=1.2.3"
   ```

2. **CI/CD 整合**：從 CI/CD pipeline 傳入變數
   ```bash
   ansible-playbook site.yml -e "image_tag=${CI_COMMIT_SHA}"
   ```

3. **Debug**：臨時改變行為而不修改檔案
   ```bash
   ansible-playbook site.yml -e "debug_mode=true"
   ```

**風險**：

因為 `-e` 會覆寫一切，所以要小心使用。特別是在 production 環境，應該限制誰可以使用 extra vars。

</details>

<details>
<summary>Q3：group_vars/all 和 group_vars/web 都定義了同一個變數，在 web 群組的主機上哪個生效？</summary>

**`group_vars/web` 生效**。

Ansible 的規則是：**更具體的定義優先**。`group_vars/web` 比 `group_vars/all` 更具體，所以優先。

同理，`host_vars/web01` 又比 `group_vars/web` 更具體。

這個設計很直覺：你可以在 `all` 設定預設值，然後在特定群組或主機覆寫。

</details>

## 實作：建立完整的 Inventory

讓我們為 Flask 專案建立完整的 inventory 結構。

### 目錄結構

```
inventory/
└── dev/
    ├── hosts
    ├── group_vars/
    │   ├── all.yml
    │   ├── web.yml
    │   └── db.yml
    └── host_vars/
        └── (暫時不需要)
```

### hosts 檔案

```ini
# inventory/dev/hosts

[web]
web01 ansible_host=192.168.56.11

[db]
db01 ansible_host=192.168.56.20

[flask:children]
web
db
```

### group_vars/all.yml

```yaml
# inventory/dev/group_vars/all.yml
---
# 連線設定
ansible_user: vagrant
ansible_become: true
ansible_python_interpreter: /usr/bin/python3

# 環境設定
app_env: development
timezone: Asia/Taipei

# 應用程式資訊
app_name: flask-demo
app_domain: flask-demo.local

# 資料庫連線資訊（Web 需要知道如何連 DB）
db_host: "{{ hostvars['db01']['ansible_host'] }}"
db_port: 5432
db_name: flask_demo
db_user: flask_app
# 密碼會在後面的文章用 Vault 加密
db_password: "changeme_in_production"
```

### group_vars/web.yml

```yaml
# inventory/dev/group_vars/web.yml
---
# Nginx 設定
nginx_worker_processes: auto
nginx_worker_connections: 1024

# Flask 應用設定
flask_app_port: 5000
flask_workers: 2
flask_app_user: flask
flask_app_group: flask
flask_app_path: /opt/flask-demo
flask_venv_path: /opt/flask-demo/venv

# Gunicorn 設定
gunicorn_bind: "127.0.0.1:{{ flask_app_port }}"
gunicorn_workers: "{{ flask_workers }}"
```

### group_vars/db.yml

```yaml
# inventory/dev/group_vars/db.yml
---
# PostgreSQL 設定
postgresql_version: 15
postgresql_port: 5432
postgresql_listen_addresses: "*"
postgresql_max_connections: 100

# 資料庫清單
postgresql_databases:
  - name: "{{ db_name }}"
    encoding: UTF8
    lc_collate: en_US.UTF-8
    lc_ctype: en_US.UTF-8

# 使用者清單
postgresql_users:
  - name: "{{ db_user }}"
    password: "{{ db_password }}"
    role_attr_flags: LOGIN

# pg_hba 設定（允許哪些連線）
postgresql_hba_entries:
  - type: local
    database: all
    user: postgres
    method: peer
  - type: host
    database: "{{ db_name }}"
    user: "{{ db_user }}"
    address: "192.168.56.0/24"
    method: scram-sha-256
```

## 驗證 Inventory

建立好 inventory 後，可以用這些指令驗證：

```bash
# 列出所有主機
ansible-inventory -i inventory/dev --list

# 以樹狀結構顯示
ansible-inventory -i inventory/dev --graph

# 顯示特定主機的變數
ansible-inventory -i inventory/dev --host web01

# 測試連線
ansible -i inventory/dev all -m ping
```

### 範例輸出

```bash
$ ansible-inventory -i inventory/dev --graph
@all:
  |--@db:
  |  |--db01
  |--@flask:
  |  |--@db:
  |  |  |--db01
  |  |--@web:
  |  |  |--web01
  |--@ungrouped:
  |--@web:
  |  |--web01
```

## 總結

在這篇文章中，我們學習了：

1. **Inventory 基礎**
   - INI 和 YAML 兩種格式
   - 如何定義主機和群組
   - 常用的 inventory 變數

2. **多環境 Inventory**
   - 用目錄結構分離環境
   - 執行時指定 inventory

3. **group_vars 與 host_vars**
   - 檔案和目錄兩種組織方式
   - 變數套用的範圍

4. **變數優先順序**
   - 完整的優先順序清單
   - 實務上的使用經驗

5. **實作**
   - 建立 Flask 專案的完整 inventory
   - 驗證 inventory 的指令

## 下一篇預告

在下一篇文章中，我們會開始撰寫第一個 Role——**PostgreSQL**，包括：

- Role 的完整目錄結構
- 使用 `community.postgresql` collection
- Template 與 Jinja2 基礎
- Handlers 的使用

## Reference

- [Ansible Documentation - How to build your inventory](https://docs.ansible.com/ansible/latest/inventory_guide/intro_inventory.html)
- [Ansible Documentation - Variable precedence](https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_variables.html#variable-precedence-where-should-i-put-a-variable)
- [Ansible Documentation - Organizing host and group variables](https://docs.ansible.com/ansible/latest/inventory_guide/intro_inventory.html#organizing-host-and-group-variables)
