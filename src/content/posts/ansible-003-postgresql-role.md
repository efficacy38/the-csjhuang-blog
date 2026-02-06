---
title: Ansible 實戰：撰寫 PostgreSQL Role
description: 從零開始撰寫 PostgreSQL Role，學習 Role 結構、Template/Jinja2、Handlers，以及如何使用 community.postgresql collection
date: 2026-02-02
slug: ansible-003-postgresql-role
series: "ansible"
tags:
    - "ansible"
    - "devops"
    - "note"
---

:::note
**前置閱讀**

本文假設你已經讀過系列的前兩篇文章：
- [Ansible 實戰：專案結構與 Convention](/posts/ansible-001-project-structure)——理解專案目錄結構
- [Ansible 實戰：Inventory 與變數管理](/posts/ansible-002-inventory-variables)——理解 inventory 和變數優先順序

本文會使用 `community.postgresql` collection，請確保已安裝。
:::

在這篇文章中，我們會撰寫系列的第一個 Role——**PostgreSQL**。透過這個實作，你會學到：

- Role 的完整目錄結構與各檔案職責
- 如何使用 `community.postgresql` collection
- Template 與 Jinja2 的基礎用法
- Handlers 的運作機制

## Role 結構回顧

在第一篇文章中，我們介紹過 Role 的目錄結構。現在讓我們建立 `postgresql` role：

```
roles/postgresql/
├── tasks/
│   └── main.yml        # 主要的 tasks
├── handlers/
│   └── main.yml        # handlers（restart/reload service）
├── templates/
│   ├── postgresql.conf.j2
│   └── pg_hba.conf.j2
├── defaults/
│   └── main.yml        # 預設變數（使用者可覆寫）
└── vars/
    └── main.yml        # 內部變數（不該被覆寫）
```

## 安裝 community.postgresql

首先確保已安裝 collection：

```bash
# 檢查是否已安裝
ansible-galaxy collection list | grep postgresql

# 若未安裝
ansible-galaxy collection install community.postgresql
```

這個 collection 提供了許多 PostgreSQL 相關的 module：

| Module | 用途 |
|--------|------|
| `postgresql_db` | 建立/管理資料庫 |
| `postgresql_user` | 建立/管理使用者 |
| `postgresql_privs` | 管理權限 |
| `postgresql_pg_hba` | 管理 pg_hba.conf |
| `postgresql_set` | 設定 runtime 參數 |

## 撰寫 defaults/main.yml

`defaults/` 存放使用者應該覆寫的變數。設計原則是：**提供合理的預設值，但允許使用者依環境調整**。

```yaml
# roles/postgresql/defaults/main.yml
---
# PostgreSQL 版本
postgresql_version: 15

# 基本設定
postgresql_port: 5432
postgresql_listen_addresses: "localhost"
postgresql_max_connections: 100

# 記憶體設定（適合小型環境的預設值）
postgresql_shared_buffers: "128MB"
postgresql_effective_cache_size: "512MB"
postgresql_work_mem: "4MB"

# 資料庫清單
postgresql_databases: []
# 範例：
# - name: mydb
#   encoding: UTF8
#   lc_collate: en_US.UTF-8
#   lc_ctype: en_US.UTF-8

# 使用者清單
postgresql_users: []
# 範例：
# - name: myuser
#   password: "secret"
#   role_attr_flags: LOGIN

# pg_hba 設定
postgresql_hba_entries:
  - type: local
    database: all
    user: postgres
    method: peer
  - type: local
    database: all
    user: all
    method: peer
  - type: host
    database: all
    user: all
    address: "127.0.0.1/32"
    method: scram-sha-256
  - type: host
    database: all
    user: all
    address: "::1/128"
    method: scram-sha-256
```

## 撰寫 vars/main.yml

`vars/` 存放 role 內部使用的變數，使用者通常不該覆寫：

```yaml
# roles/postgresql/vars/main.yml
---
# 套件名稱（依版本變化）
postgresql_packages:
  - "postgresql-{{ postgresql_version }}"
  - "postgresql-contrib-{{ postgresql_version }}"
  - "python3-psycopg2"  # Ansible module 需要

# 路徑設定（這些是 Debian/Ubuntu 的標準路徑）
postgresql_config_path: "/etc/postgresql/{{ postgresql_version }}/main"
postgresql_data_path: "/var/lib/postgresql/{{ postgresql_version }}/main"
postgresql_bin_path: "/usr/lib/postgresql/{{ postgresql_version }}/bin"

# Service 名稱
postgresql_service: "postgresql"
```

## 撰寫 tasks/main.yml

現在來寫主要的 tasks。我們會分成幾個階段：

1. 安裝 PostgreSQL
2. 設定 postgresql.conf
3. 設定 pg_hba.conf
4. 啟動服務
5. 建立資料庫和使用者

```yaml
# roles/postgresql/tasks/main.yml
---
- name: Install PostgreSQL packages
  ansible.builtin.apt:
    name: "{{ postgresql_packages }}"
    state: present
    update_cache: true
  tags:
    - postgresql
    - packages

- name: Configure postgresql.conf
  ansible.builtin.template:
    src: postgresql.conf.j2
    dest: "{{ postgresql_config_path }}/postgresql.conf"
    owner: postgres
    group: postgres
    mode: "0644"
  notify: Restart PostgreSQL
  tags:
    - postgresql
    - config

- name: Configure pg_hba.conf
  ansible.builtin.template:
    src: pg_hba.conf.j2
    dest: "{{ postgresql_config_path }}/pg_hba.conf"
    owner: postgres
    group: postgres
    mode: "0640"
  notify: Reload PostgreSQL
  tags:
    - postgresql
    - config

- name: Ensure PostgreSQL is started and enabled
  ansible.builtin.service:
    name: "{{ postgresql_service }}"
    state: started
    enabled: true
  tags:
    - postgresql

# 強制執行 handlers，確保設定生效後再建立 DB/User
- name: Flush handlers
  ansible.builtin.meta: flush_handlers

- name: Create databases
  community.postgresql.postgresql_db:
    name: "{{ item.name }}"
    encoding: "{{ item.encoding | default('UTF8') }}"
    lc_collate: "{{ item.lc_collate | default('en_US.UTF-8') }}"
    lc_ctype: "{{ item.lc_ctype | default('en_US.UTF-8') }}"
    state: present
  become: true
  become_user: postgres
  loop: "{{ postgresql_databases }}"
  when: postgresql_databases | length > 0
  tags:
    - postgresql
    - databases

- name: Create users
  community.postgresql.postgresql_user:
    name: "{{ item.name }}"
    password: "{{ item.password }}"
    role_attr_flags: "{{ item.role_attr_flags | default('LOGIN') }}"
    state: present
  become: true
  become_user: postgres
  loop: "{{ postgresql_users }}"
  when: postgresql_users | length > 0
  no_log: true  # 避免密碼出現在 log 中
  tags:
    - postgresql
    - users

- name: Grant database privileges to users
  community.postgresql.postgresql_privs:
    database: "{{ item.0.name }}"
    privs: ALL
    type: database
    role: "{{ item.1.name }}"
    state: present
  become: true
  become_user: postgres
  loop: "{{ postgresql_databases | product(postgresql_users) | list }}"
  when:
    - postgresql_databases | length > 0
    - postgresql_users | length > 0
  tags:
    - postgresql
    - privileges
```

### 重點說明

**1. 使用 FQCN（Fully Qualified Collection Name）**

```yaml
# 推薦：使用完整名稱
ansible.builtin.apt:
community.postgresql.postgresql_db:

# 不推薦：省略 collection 名稱
apt:
postgresql_db:
```

使用 FQCN 可以避免 module 名稱衝突，也讓人一眼看出使用的是哪個 collection。

**2. notify 與 handlers**

```yaml
- name: Configure postgresql.conf
  template: ...
  notify: Restart PostgreSQL  # 當檔案變更時，觸發 handler
```

`notify` 不會立即執行 handler，而是在 play 結束時執行。如果需要立即執行，使用 `meta: flush_handlers`。

**3. become_user**

```yaml
- name: Create databases
  community.postgresql.postgresql_db:
    ...
  become: true
  become_user: postgres  # 以 postgres 系統使用者執行
```

PostgreSQL 的 `peer` 認證會檢查系統使用者，所以需要用 `become_user: postgres`。

**4. no_log**

```yaml
- name: Create users
  ...
  no_log: true  # 避免密碼出現在 log 中
```

任何涉及密碼的 task 都應該設定 `no_log: true`。

**5. loop 與 when**

```yaml
loop: "{{ postgresql_databases }}"
when: postgresql_databases | length > 0
```

當 list 可能為空時，加上 `when` 可以避免不必要的 warning。

## 撰寫 handlers/main.yml

Handlers 是特殊的 tasks，只有被 `notify` 觸發時才會執行：

```yaml
# roles/postgresql/handlers/main.yml
---
- name: Restart PostgreSQL
  ansible.builtin.service:
    name: "{{ postgresql_service }}"
    state: restarted
  listen: Restart PostgreSQL

- name: Reload PostgreSQL
  ansible.builtin.service:
    name: "{{ postgresql_service }}"
    state: reloaded
  listen: Reload PostgreSQL
```

**Restart vs Reload**：

| 動作 | 說明 | 使用時機 |
|------|------|---------|
| restart | 停止並重新啟動 | 修改需要重啟才生效的參數（如 shared_buffers） |
| reload | 重新載入設定 | 修改可熱載入的參數（如 pg_hba.conf） |

## Template 與 Jinja2

Template 是 Ansible 最強大的功能之一。讓我們看看如何用 Jinja2 產生 PostgreSQL 設定檔。

### postgresql.conf.j2

```jinja2
# {{ ansible_managed }}
# PostgreSQL configuration file

#------------------------------------------------------------------------------
# CONNECTIONS AND AUTHENTICATION
#------------------------------------------------------------------------------

listen_addresses = '{{ postgresql_listen_addresses }}'
port = {{ postgresql_port }}
max_connections = {{ postgresql_max_connections }}

#------------------------------------------------------------------------------
# RESOURCE USAGE (except WAL)
#------------------------------------------------------------------------------

shared_buffers = {{ postgresql_shared_buffers }}
effective_cache_size = {{ postgresql_effective_cache_size }}
work_mem = {{ postgresql_work_mem }}

#------------------------------------------------------------------------------
# WRITE-AHEAD LOG
#------------------------------------------------------------------------------

wal_level = replica
max_wal_senders = 3

#------------------------------------------------------------------------------
# LOGGING
#------------------------------------------------------------------------------

log_destination = 'stderr'
logging_collector = on
log_directory = 'log'
log_filename = 'postgresql-%Y-%m-%d_%H%M%S.log'
log_rotation_age = 1d
log_rotation_size = 100MB
log_line_prefix = '%m [%p] %q%u@%d '
log_timezone = '{{ timezone | default("UTC") }}'

#------------------------------------------------------------------------------
# CLIENT CONNECTION DEFAULTS
#------------------------------------------------------------------------------

datestyle = 'iso, mdy'
timezone = '{{ timezone | default("UTC") }}'
lc_messages = 'en_US.UTF-8'
lc_monetary = 'en_US.UTF-8'
lc_numeric = 'en_US.UTF-8'
lc_time = 'en_US.UTF-8'
default_text_search_config = 'pg_catalog.english'
```

**Jinja2 重點語法**：

| 語法 | 說明 | 範例 |
|------|------|------|
| `{{ var }}` | 輸出變數值 | `{{ postgresql_port }}` |
| `{{ var \| default('x') }}` | 有預設值的變數 | `{{ timezone \| default('UTC') }}` |
| `{{ ansible_managed }}` | 自動加入「此檔案由 Ansible 管理」的註解 | |

### pg_hba.conf.j2

```jinja2
# {{ ansible_managed }}
# PostgreSQL Client Authentication Configuration File

# TYPE  DATABASE        USER            ADDRESS                 METHOD
{% for entry in postgresql_hba_entries %}
{% if entry.type == 'local' %}
{{ entry.type }}   {{ entry.database }}             {{ entry.user }}                                    {{ entry.method }}
{% else %}
{{ entry.type }}    {{ entry.database }}             {{ entry.user }}            {{ entry.address }}        {{ entry.method }}
{% endif %}
{% endfor %}
```

**Jinja2 控制結構**：

```jinja2
{% for item in list %}     {# 迴圈 #}
{% endfor %}

{% if condition %}         {# 條件判斷 #}
{% elif other_condition %}
{% else %}
{% endif %}
```

### 思考題

<details>
<summary>Q1：為什麼 postgresql.conf 變更要 restart，但 pg_hba.conf 變更只要 reload？</summary>

**PostgreSQL 參數分類**：

| 類型 | 說明 | 範例 |
|------|------|------|
| `postmaster` | 需要重啟 | shared_buffers, max_connections |
| `sighup` | 可以 reload | pg_hba.conf 的變更 |
| `user` | 每個 session 可設定 | work_mem |
| `superuser` | superuser 可設定 | log_statement |

`pg_hba.conf` 是 `sighup` 類型，PostgreSQL 收到 SIGHUP 信號後會重新讀取。而 `shared_buffers` 是 `postmaster` 類型，因為它涉及記憶體配置，必須在啟動時設定。

</details>

<details>
<summary>Q2：為什麼要在 template 開頭加 {{ ansible_managed }}？</summary>

**防止人工修改**：

`{{ ansible_managed }}` 會產生類似這樣的註解：

```
# Ansible managed: /path/to/template.j2 modified on 2026-02-02
```

這告訴維運人員：
1. 這個檔案是 Ansible 管理的
2. 人工修改會在下次 Ansible 執行時被覆蓋
3. 如果要改，應該改 inventory 變數或 template

</details>

<details>
<summary>Q3：什麼時候用 restart，什麼時候用 reload？如果搞混了會怎樣？</summary>

**搞混的後果**：

| 實際需要 | 你做了 | 結果 |
|---------|-------|------|
| restart | reload | 設定不生效，服務使用舊設定繼續跑 |
| reload | restart | 設定生效，但服務中斷（所有連線被斷開） |

**安全原則**：

- 如果不確定，用 restart 比較安全（至少設定會生效）
- 但 production 環境應該盡量用 reload，避免服務中斷
- 可以查 PostgreSQL 文件，每個參數都有標註 context

</details>

## 測試 Role

建立一個測試用的 playbook：

```yaml
# test_postgresql.yml
---
- name: Test PostgreSQL Role
  hosts: db
  become: true

  roles:
    - postgresql
```

執行：

```bash
# Dry-run（不實際執行，只顯示會做什麼）
ansible-playbook -i inventory/dev test_postgresql.yml --check --diff

# 實際執行
ansible-playbook -i inventory/dev test_postgresql.yml

# 只執行特定 tag
ansible-playbook -i inventory/dev test_postgresql.yml --tags config
```

### 驗證安裝

```bash
# 連到 db01 確認 PostgreSQL 狀態
ansible -i inventory/dev db -m shell -a "systemctl status postgresql"

# 確認資料庫已建立
ansible -i inventory/dev db -m shell -a "sudo -u postgres psql -c '\l'"

# 確認使用者已建立
ansible -i inventory/dev db -m shell -a "sudo -u postgres psql -c '\du'"
```

## 完整的 Role 結構

最終的 `roles/postgresql/` 結構：

```
roles/postgresql/
├── defaults/
│   └── main.yml
├── handlers/
│   └── main.yml
├── tasks/
│   └── main.yml
├── templates/
│   ├── pg_hba.conf.j2
│   └── postgresql.conf.j2
└── vars/
    └── main.yml
```

## 總結

在這篇文章中，我們學習了：

1. **Role 結構**
   - defaults/ vs vars/ 的差異
   - tasks、handlers、templates 的職責

2. **community.postgresql collection**
   - postgresql_db、postgresql_user 等 module
   - 使用 become_user 執行 PostgreSQL 操作

3. **Template 與 Jinja2**
   - 變數輸出 `{{ }}`
   - 控制結構 `{% %}`
   - default filter 的使用

4. **Handlers**
   - notify 觸發機制
   - restart vs reload 的差異
   - flush_handlers 的使用時機

## 下一篇預告

在下一篇文章中，我們會撰寫 **Flask App Role**，包括：

- 建立系統使用者和目錄結構
- Python virtualenv 管理
- 用 Template 產生 systemd service
- 條件執行（when）和迴圈（loop）的進階用法

## Reference

- [community.postgresql Collection](https://docs.ansible.com/ansible/latest/collections/community/postgresql/index.html)
- [Ansible Documentation - Templating (Jinja2)](https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_templating.html)
- [Ansible Documentation - Handlers](https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_handlers.html)
- [PostgreSQL Documentation - Server Configuration](https://www.postgresql.org/docs/current/runtime-config.html)
