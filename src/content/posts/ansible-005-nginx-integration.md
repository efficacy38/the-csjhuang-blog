---
title: Ansible 實戰：Nginx Role 與專案整合
description: 撰寫 Nginx 反向代理 Role，設計 Tags 策略，並整合所有 Roles 建立完整的 site.yml
date: 2026-02-02
slug: ansible-005-nginx-role-integration
series: "ansible"
tags:
    - "ansible"
    - "devops"
    - "note"
---

:::note
**前置閱讀**

本文假設你已經讀過系列的前四篇文章，特別是：
- [Ansible 實戰：撰寫 Flask App Role](/posts/ansible-004-flask-app-role)——理解應用程式部署的 Role 設計

這是實作系列的倒數第二篇，我們會把所有 Roles 整合起來。
:::

在這篇文章中，我們會：

- 撰寫 **Nginx Role**，設定反向代理到 Flask App
- 設計 **Tags 策略**，讓部署更靈活
- 建立 **site.yml** 主 Playbook，整合所有 Roles
- 設計 **deploy_app.yml**，用於快速部署應用更新

## Nginx Role 結構

```
roles/nginx/
├── tasks/
│   └── main.yml
├── handlers/
│   └── main.yml
├── templates/
│   ├── nginx.conf.j2
│   └── flask-app.conf.j2
├── defaults/
│   └── main.yml
└── vars/
    └── main.yml
```

## 撰寫 defaults/main.yml

```yaml
# roles/nginx/defaults/main.yml
---
# Nginx 基本設定
nginx_worker_processes: auto
nginx_worker_connections: 1024

# 站台設定
nginx_server_name: "{{ app_domain | default('localhost') }}"
nginx_listen_port: 80

# 上游設定（Flask App）
nginx_upstream_name: flask_app
nginx_upstream_server: "127.0.0.1:{{ flask_app_port | default(5000) }}"

# 日誌設定
nginx_access_log: /var/log/nginx/flask-app-access.log
nginx_error_log: /var/log/nginx/flask-app-error.log

# 安全設定
nginx_client_max_body_size: 10M
```

## 撰寫 vars/main.yml

```yaml
# roles/nginx/vars/main.yml
---
# 套件
nginx_packages:
  - nginx

# Service 名稱
nginx_service: nginx

# 路徑
nginx_config_path: /etc/nginx
nginx_sites_available: "{{ nginx_config_path }}/sites-available"
nginx_sites_enabled: "{{ nginx_config_path }}/sites-enabled"
```

## 撰寫 tasks/main.yml

```yaml
# roles/nginx/tasks/main.yml
---
- name: Install Nginx
  ansible.builtin.apt:
    name: "{{ nginx_packages }}"
    state: present
    update_cache: true
  tags:
    - nginx
    - packages

- name: Configure nginx.conf
  ansible.builtin.template:
    src: nginx.conf.j2
    dest: "{{ nginx_config_path }}/nginx.conf"
    owner: root
    group: root
    mode: "0644"
    validate: nginx -t -c %s
  notify: Reload Nginx
  tags:
    - nginx
    - config

- name: Remove default site
  ansible.builtin.file:
    path: "{{ nginx_sites_enabled }}/default"
    state: absent
  notify: Reload Nginx
  tags:
    - nginx
    - config

- name: Configure Flask app site
  ansible.builtin.template:
    src: flask-app.conf.j2
    dest: "{{ nginx_sites_available }}/flask-app.conf"
    owner: root
    group: root
    mode: "0644"
    validate: nginx -t -c {{ nginx_config_path }}/nginx.conf
  notify: Reload Nginx
  tags:
    - nginx
    - config

- name: Enable Flask app site
  ansible.builtin.file:
    src: "{{ nginx_sites_available }}/flask-app.conf"
    dest: "{{ nginx_sites_enabled }}/flask-app.conf"
    state: link
  notify: Reload Nginx
  tags:
    - nginx
    - config

- name: Ensure Nginx is started and enabled
  ansible.builtin.service:
    name: "{{ nginx_service }}"
    state: started
    enabled: true
  tags:
    - nginx
```

### 重點說明

**1. validate 參數**

```yaml
- name: Configure nginx.conf
  ansible.builtin.template:
    ...
    validate: nginx -t -c %s
```

`validate` 會在套用設定前驗證語法。`%s` 會被替換成暫存檔的路徑。如果驗證失敗，Ansible 不會覆蓋原本的設定檔。

**2. 移除預設站台**

Nginx 安裝後會有一個 default site，我們需要移除它：

```yaml
- name: Remove default site
  ansible.builtin.file:
    path: "{{ nginx_sites_enabled }}/default"
    state: absent
```

## 撰寫 handlers/main.yml

```yaml
# roles/nginx/handlers/main.yml
---
- name: Reload Nginx
  ansible.builtin.service:
    name: "{{ nginx_service }}"
    state: reloaded
  listen: Reload Nginx

- name: Restart Nginx
  ansible.builtin.service:
    name: "{{ nginx_service }}"
    state: restarted
  listen: Restart Nginx
```

## 撰寫 Templates

### nginx.conf.j2

```jinja2
# {{ ansible_managed }}
user www-data;
worker_processes {{ nginx_worker_processes }};
pid /run/nginx.pid;
include /etc/nginx/modules-enabled/*.conf;

events {
    worker_connections {{ nginx_worker_connections }};
    multi_accept on;
    use epoll;
}

http {
    # Basic Settings
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    types_hash_max_size 2048;
    server_tokens off;

    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    # Logging Settings
    access_log /var/log/nginx/access.log;
    error_log /var/log/nginx/error.log;

    # Gzip Settings
    gzip on;
    gzip_vary on;
    gzip_proxied any;
    gzip_comp_level 6;
    gzip_types text/plain text/css text/xml application/json application/javascript application/rss+xml application/atom+xml image/svg+xml;

    # Virtual Host Configs
    include /etc/nginx/conf.d/*.conf;
    include /etc/nginx/sites-enabled/*;
}
```

### flask-app.conf.j2

```jinja2
# {{ ansible_managed }}
upstream {{ nginx_upstream_name }} {
    server {{ nginx_upstream_server }};
    keepalive 32;
}

server {
    listen {{ nginx_listen_port }};
    server_name {{ nginx_server_name }};

    access_log {{ nginx_access_log }};
    error_log {{ nginx_error_log }};

    client_max_body_size {{ nginx_client_max_body_size }};

    location / {
        proxy_pass http://{{ nginx_upstream_name }};
        proxy_http_version 1.1;

        # Headers
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        # Timeouts
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;

        # Connection reuse
        proxy_set_header Connection "";
    }

    # Health check endpoint
    location /health {
        proxy_pass http://{{ nginx_upstream_name }}/health;
        access_log off;
    }
}
```

## Tags 策略設計

Tags 讓你可以只執行 Playbook 的一部分。好的 Tags 設計可以大幅提升部署效率。

### 我們的 Tags 設計

| Tag | 說明 | 使用場景 |
|-----|------|---------|
| `packages` | 套件安裝 | 初次部署、版本升級 |
| `config` | 設定檔更新 | 調整設定 |
| `deploy` | 應用程式部署 | 更新程式碼 |
| `postgresql` | PostgreSQL 相關 | 只操作 DB |
| `flask_app` | Flask App 相關 | 只操作 App |
| `nginx` | Nginx 相關 | 只操作 Web Server |

### 使用範例

```bash
# 完整部署
ansible-playbook -i inventory/dev site.yml

# 只更新設定檔
ansible-playbook -i inventory/dev site.yml --tags config

# 只部署 Flask App
ansible-playbook -i inventory/dev site.yml --tags flask_app

# 排除套件安裝（加速部署）
ansible-playbook -i inventory/dev site.yml --skip-tags packages
```

## 建立主 Playbook：site.yml

現在我們把所有 Roles 整合起來：

```yaml
# site.yml
---
# =============================================================================
# 完整部署 Playbook
# 用法: ansible-playbook -i inventory/dev site.yml
# =============================================================================

- name: Deploy PostgreSQL
  hosts: db
  become: true
  roles:
    - role: postgresql
      tags: [postgresql, database]

- name: Deploy Flask Application
  hosts: web
  become: true
  roles:
    - role: flask_app
      tags: [flask_app, application]
    - role: nginx
      tags: [nginx, webserver]

# =============================================================================
# 部署後驗證
# =============================================================================

- name: Verify deployment
  hosts: web
  become: false
  gather_facts: false
  tasks:
    - name: Wait for Flask app to be ready
      ansible.builtin.uri:
        url: "http://localhost:{{ flask_app_port | default(5000) }}/health"
        status_code: 200
      register: health_check
      until: health_check.status == 200
      retries: 5
      delay: 3
      tags: [verify]

    - name: Wait for Nginx to be ready
      ansible.builtin.uri:
        url: "http://localhost/health"
        status_code: 200
      register: nginx_check
      until: nginx_check.status == 200
      retries: 5
      delay: 3
      tags: [verify]

    - name: Display deployment status
      ansible.builtin.debug:
        msg: "Deployment successful! App is running at http://{{ app_domain | default('localhost') }}"
      tags: [verify]
```

### 重點說明

**1. 多個 Plays**

一個 Playbook 可以有多個 plays，每個 play 針對不同的 hosts：

```yaml
- name: Deploy PostgreSQL
  hosts: db          # 只在 db 群組執行
  roles:
    - postgresql

- name: Deploy Flask Application
  hosts: web         # 只在 web 群組執行
  roles:
    - flask_app
    - nginx
```

**2. 部署後驗證**

```yaml
- name: Wait for Flask app to be ready
  ansible.builtin.uri:
    url: "http://localhost:5000/health"
  register: health_check
  until: health_check.status == 200
  retries: 5
  delay: 3
```

`until`/`retries`/`delay` 實現了 polling 機制：每 3 秒檢查一次，最多重試 5 次。

**3. Role 綁定 Tags**

```yaml
roles:
  - role: postgresql
    tags: [postgresql, database]
```

這樣 `--tags postgresql` 或 `--tags database` 都會執行這個 role。

## 建立快速部署 Playbook：deploy_app.yml

日常更新應用程式時，不需要重跑整個 site.yml。我們建立一個精簡版：

```yaml
# deploy_app.yml
---
# =============================================================================
# 快速部署應用程式（跳過基礎設施設定）
# 用法: ansible-playbook -i inventory/dev deploy_app.yml
# =============================================================================

- name: Deploy Flask Application Update
  hosts: web
  become: true

  tasks:
    - name: Copy application files
      ansible.builtin.copy:
        src: "{{ item.src }}"
        dest: "{{ item.dest }}"
        owner: "{{ flask_app_user }}"
        group: "{{ flask_app_group }}"
        mode: "0644"
      loop:
        - { src: "roles/flask_app/files/app.py", dest: "{{ flask_app_path }}/app.py" }
        - { src: "roles/flask_app/files/requirements.txt", dest: "{{ flask_app_path }}/requirements.txt" }
      notify: Restart Flask App

    - name: Update Python dependencies
      ansible.builtin.pip:
        requirements: "{{ flask_app_path }}/requirements.txt"
        virtualenv: "{{ flask_venv_path }}"
        state: present
      become: true
      become_user: "{{ flask_app_user }}"
      notify: Restart Flask App

  handlers:
    - name: Restart Flask App
      ansible.builtin.service:
        name: "{{ flask_app_name }}"
        state: restarted

- name: Verify deployment
  hosts: web
  become: false
  gather_facts: false
  tasks:
    - name: Health check
      ansible.builtin.uri:
        url: "http://localhost/health"
        status_code: 200
      retries: 5
      delay: 2
```

## 完整專案結構

經過這五篇文章，我們的專案結構如下：

```
flask-deploy/
├── ansible.cfg
├── requirements.yml
│
├── inventory/
│   └── dev/
│       ├── hosts
│       └── group_vars/
│           ├── all.yml
│           ├── web.yml
│           └── db.yml
│
├── roles/
│   ├── postgresql/
│   │   ├── tasks/main.yml
│   │   ├── handlers/main.yml
│   │   ├── templates/
│   │   │   ├── postgresql.conf.j2
│   │   │   └── pg_hba.conf.j2
│   │   ├── defaults/main.yml
│   │   └── vars/main.yml
│   │
│   ├── flask_app/
│   │   ├── tasks/main.yml
│   │   ├── handlers/main.yml
│   │   ├── templates/
│   │   │   ├── flask-app.service.j2
│   │   │   ├── config.py.j2
│   │   │   └── gunicorn.conf.py.j2
│   │   ├── files/
│   │   │   ├── app.py
│   │   │   └── requirements.txt
│   │   ├── defaults/main.yml
│   │   └── vars/main.yml
│   │
│   └── nginx/
│       ├── tasks/main.yml
│       ├── handlers/main.yml
│       ├── templates/
│       │   ├── nginx.conf.j2
│       │   └── flask-app.conf.j2
│       ├── defaults/main.yml
│       └── vars/main.yml
│
├── site.yml              # 完整部署
└── deploy_app.yml        # 快速部署
```

## 部署流程

### 首次完整部署

```bash
# 1. 安裝 Collection
ansible-galaxy collection install -r requirements.yml

# 2. 確認 inventory
ansible-inventory -i inventory/dev --graph

# 3. 測試連線
ansible -i inventory/dev all -m ping

# 4. Dry-run
ansible-playbook -i inventory/dev site.yml --check --diff

# 5. 執行部署
ansible-playbook -i inventory/dev site.yml

# 6. 驗證
curl http://your-server/health
curl http://your-server/db-health
```

### 日常更新應用

```bash
# 快速部署（只更新 App）
ansible-playbook -i inventory/dev deploy_app.yml

# 或使用 tags
ansible-playbook -i inventory/dev site.yml --tags deploy
```

### 思考題

<details>
<summary>Q1：為什麼要把 PostgreSQL 和 Flask/Nginx 分成不同的 plays？</summary>

**原因**：

1. **不同的 hosts**：PostgreSQL 在 `db` 群組，Flask/Nginx 在 `web` 群組
2. **執行順序**：確保 DB 先部署完成，App 才能連線
3. **可以獨立執行**：用 `--limit db` 只操作資料庫

**替代方案**：

如果只有一台機器，可以合併成一個 play：

```yaml
- name: Deploy all
  hosts: all
  roles:
    - postgresql
    - flask_app
    - nginx
```

</details>

<details>
<summary>Q2：為什麼 deploy_app.yml 不直接 include flask_app role？</summary>

**原因**：

`flask_app` role 會做很多事：建立使用者、建立目錄、建立 virtualenv、設定 systemd...

日常更新只需要：
1. 複製新的程式碼
2. 更新依賴（如果有變）
3. 重啟服務

直接寫 tasks 比 include role 更精簡、更快。

**取捨**：

| 方式 | 優點 | 缺點 |
|-----|------|------|
| Include role | 邏輯集中、不用重複 | 執行時間長 |
| 獨立 tasks | 快速、精簡 | 邏輯分散、需要同步維護 |

兩種方式都合理，看團隊偏好和部署頻率。

</details>

<details>
<summary>Q3：validate 驗證失敗時會發生什麼？</summary>

**行為**：

1. Ansible 先把 template render 到一個暫存檔
2. 執行 `nginx -t -c /tmp/ansible_xxxxx`
3. 如果回傳非 0，task 會 fail
4. **原本的設定檔不會被覆蓋**

這是一個安全機制：確保不會因為寫錯設定而讓服務 crash。

**注意**：validate 只檢查語法，不保證邏輯正確。例如 upstream 的 IP 打錯，nginx -t 仍會 pass。

</details>

## 總結

在這篇文章中，我們學習了：

1. **Nginx Role**
   - 反向代理設定
   - validate 參數確保設定正確
   - sites-available/sites-enabled 模式

2. **Tags 策略**
   - 設計有意義的 tags
   - 使用 --tags 和 --skip-tags

3. **整合**
   - site.yml 多 plays 設計
   - deploy_app.yml 快速部署
   - 部署後驗證

## 下一篇預告

在系列的最後一篇文章中，我們會介紹：

- **Ansible Vault** 加密敏感資訊
- **進階技巧**：Rolling update、錯誤處理
- **測試**：Ansible Lint、--check mode

## Reference

- [Ansible Documentation - Tags](https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_tags.html)
- [Nginx Documentation - Reverse Proxy](https://docs.nginx.com/nginx/admin-guide/web-server/reverse-proxy/)
- [Ansible Documentation - Validating tasks](https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_error_handling.html#validating-configuration-files)
