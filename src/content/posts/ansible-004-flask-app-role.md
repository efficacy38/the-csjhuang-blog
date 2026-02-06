---
title: Ansible 實戰：撰寫 Flask App Role
description: 撰寫 Flask 應用部署 Role，學習 virtualenv 管理、systemd service 模板，以及條件執行與迴圈的進階用法
date: 2026-02-02
slug: ansible-004-flask-app-role
series: "ansible"
tags:
    - "ansible"
    - "devops"
    - "note"
---

:::note
**前置閱讀**

本文假設你已經讀過系列的前三篇文章，特別是：
- [Ansible 實戰：撰寫 PostgreSQL Role](/posts/ansible-003-postgresql-role)——理解 Role 結構、Template、Handlers

本文會建立一個簡單的 Flask 應用，並用 Gunicorn 作為 WSGI server。
:::

在這篇文章中，我們會撰寫 **Flask App Role**，這是部署三層架構的中間層。你會學到：

- 建立系統使用者和目錄結構
- Python virtualenv 的管理
- 用 Template 產生 systemd service unit
- 條件執行（when）、changed_when、failed_when 的使用
- 迴圈（loop）的進階用法

## 範例 Flask 應用

首先，讓我們定義要部署的 Flask 應用。這是一個簡單的 API，可以讀寫 PostgreSQL：

```python
# app.py
from flask import Flask, jsonify, request
import psycopg2
import os

app = Flask(__name__)

def get_db_connection():
    return psycopg2.connect(
        host=os.environ.get('DB_HOST', 'localhost'),
        port=os.environ.get('DB_PORT', '5432'),
        database=os.environ.get('DB_NAME', 'flask_demo'),
        user=os.environ.get('DB_USER', 'flask_app'),
        password=os.environ.get('DB_PASSWORD', '')
    )

@app.route('/health')
def health():
    return jsonify({"status": "ok"})

@app.route('/db-health')
def db_health():
    try:
        conn = get_db_connection()
        cur = conn.cursor()
        cur.execute('SELECT 1')
        cur.close()
        conn.close()
        return jsonify({"status": "ok", "database": "connected"})
    except Exception as e:
        return jsonify({"status": "error", "message": str(e)}), 500

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
```

```
# requirements.txt
flask==3.0.0
gunicorn==21.2.0
psycopg2-binary==2.9.9
```

## Role 結構

```
roles/flask_app/
├── tasks/
│   └── main.yml
├── handlers/
│   └── main.yml
├── templates/
│   ├── flask-app.service.j2
│   ├── config.py.j2
│   └── gunicorn.conf.py.j2
├── files/
│   ├── app.py
│   └── requirements.txt
├── defaults/
│   └── main.yml
└── vars/
    └── main.yml
```

## 撰寫 defaults/main.yml

```yaml
# roles/flask_app/defaults/main.yml
---
# 應用程式設定
flask_app_name: flask-demo
flask_app_port: 5000
flask_workers: 2

# 使用者設定
flask_app_user: flask
flask_app_group: flask

# 路徑設定
flask_app_path: /opt/flask-demo
flask_venv_path: "{{ flask_app_path }}/venv"
flask_app_log_path: /var/log/flask-demo

# 資料庫連線（這些會從 group_vars/all.yml 傳入）
flask_db_host: "{{ db_host | default('localhost') }}"
flask_db_port: "{{ db_port | default(5432) }}"
flask_db_name: "{{ db_name | default('flask_demo') }}"
flask_db_user: "{{ db_user | default('flask_app') }}"
flask_db_password: "{{ db_password | default('') }}"

# Gunicorn 設定
gunicorn_bind: "127.0.0.1:{{ flask_app_port }}"
gunicorn_workers: "{{ flask_workers }}"
gunicorn_timeout: 30
gunicorn_keepalive: 2
```

## 撰寫 vars/main.yml

```yaml
# roles/flask_app/vars/main.yml
---
# 套件依賴
flask_system_packages:
  - python3
  - python3-pip
  - python3-venv

# Service 名稱
flask_service_name: "{{ flask_app_name }}"

# 檔案路徑
flask_app_file: "{{ flask_app_path }}/app.py"
flask_requirements_file: "{{ flask_app_path }}/requirements.txt"
flask_config_file: "{{ flask_app_path }}/config.py"
flask_gunicorn_config: "{{ flask_app_path }}/gunicorn.conf.py"
```

## 撰寫 tasks/main.yml

```yaml
# roles/flask_app/tasks/main.yml
---
# =============================================================================
# 系統準備
# =============================================================================

- name: Install system packages
  ansible.builtin.apt:
    name: "{{ flask_system_packages }}"
    state: present
    update_cache: true
  tags:
    - flask_app
    - packages

- name: Create application group
  ansible.builtin.group:
    name: "{{ flask_app_group }}"
    state: present
  tags:
    - flask_app
    - user

- name: Create application user
  ansible.builtin.user:
    name: "{{ flask_app_user }}"
    group: "{{ flask_app_group }}"
    system: true
    shell: /usr/sbin/nologin
    home: "{{ flask_app_path }}"
    create_home: false
  tags:
    - flask_app
    - user

# =============================================================================
# 目錄結構
# =============================================================================

- name: Create application directories
  ansible.builtin.file:
    path: "{{ item }}"
    state: directory
    owner: "{{ flask_app_user }}"
    group: "{{ flask_app_group }}"
    mode: "0755"
  loop:
    - "{{ flask_app_path }}"
    - "{{ flask_app_log_path }}"
  tags:
    - flask_app
    - directories

# =============================================================================
# 應用程式部署
# =============================================================================

- name: Copy application files
  ansible.builtin.copy:
    src: "{{ item.src }}"
    dest: "{{ item.dest }}"
    owner: "{{ flask_app_user }}"
    group: "{{ flask_app_group }}"
    mode: "0644"
  loop:
    - { src: "app.py", dest: "{{ flask_app_file }}" }
    - { src: "requirements.txt", dest: "{{ flask_requirements_file }}" }
  notify: Restart Flask App
  tags:
    - flask_app
    - deploy

- name: Create application config
  ansible.builtin.template:
    src: config.py.j2
    dest: "{{ flask_config_file }}"
    owner: "{{ flask_app_user }}"
    group: "{{ flask_app_group }}"
    mode: "0640"
  notify: Restart Flask App
  tags:
    - flask_app
    - config

- name: Create Gunicorn config
  ansible.builtin.template:
    src: gunicorn.conf.py.j2
    dest: "{{ flask_gunicorn_config }}"
    owner: "{{ flask_app_user }}"
    group: "{{ flask_app_group }}"
    mode: "0644"
  notify: Restart Flask App
  tags:
    - flask_app
    - config

# =============================================================================
# Python 虛擬環境
# =============================================================================

- name: Create virtualenv
  ansible.builtin.command:
    cmd: python3 -m venv {{ flask_venv_path }}
    creates: "{{ flask_venv_path }}/bin/activate"
  become: true
  become_user: "{{ flask_app_user }}"
  tags:
    - flask_app
    - venv

- name: Install Python dependencies
  ansible.builtin.pip:
    requirements: "{{ flask_requirements_file }}"
    virtualenv: "{{ flask_venv_path }}"
    state: present
  become: true
  become_user: "{{ flask_app_user }}"
  notify: Restart Flask App
  tags:
    - flask_app
    - venv
    - dependencies

# =============================================================================
# Systemd Service
# =============================================================================

- name: Create systemd service
  ansible.builtin.template:
    src: flask-app.service.j2
    dest: "/etc/systemd/system/{{ flask_service_name }}.service"
    owner: root
    group: root
    mode: "0644"
  notify:
    - Reload systemd
    - Restart Flask App
  tags:
    - flask_app
    - service

- name: Ensure Flask app is started and enabled
  ansible.builtin.service:
    name: "{{ flask_service_name }}"
    state: started
    enabled: true
  tags:
    - flask_app
    - service
```

### 重點說明

**1. creates 參數**

```yaml
- name: Create virtualenv
  ansible.builtin.command:
    cmd: python3 -m venv {{ flask_venv_path }}
    creates: "{{ flask_venv_path }}/bin/activate"
```

`creates` 參數讓 Ansible 變成 idempotent：如果指定的檔案已存在，就跳過這個 task。這對 `command` 和 `shell` module 特別有用。

**2. loop 搭配字典**

```yaml
- name: Copy application files
  ansible.builtin.copy:
    src: "{{ item.src }}"
    dest: "{{ item.dest }}"
  loop:
    - { src: "app.py", dest: "{{ flask_app_file }}" }
    - { src: "requirements.txt", dest: "{{ flask_requirements_file }}" }
```

當 loop 的每個 item 需要多個屬性時，使用字典格式。

**3. 多個 notify**

```yaml
notify:
  - Reload systemd
  - Restart Flask App
```

一個 task 可以觸發多個 handlers，它們會依序執行。

## 撰寫 handlers/main.yml

```yaml
# roles/flask_app/handlers/main.yml
---
- name: Reload systemd
  ansible.builtin.systemd:
    daemon_reload: true
  listen: Reload systemd

- name: Restart Flask App
  ansible.builtin.service:
    name: "{{ flask_service_name }}"
    state: restarted
  listen: Restart Flask App
```

## 撰寫 Templates

### flask-app.service.j2

```jinja2
# {{ ansible_managed }}
[Unit]
Description={{ flask_app_name }} Flask Application
After=network.target

[Service]
Type=notify
User={{ flask_app_user }}
Group={{ flask_app_group }}
WorkingDirectory={{ flask_app_path }}

# 環境變數
Environment="PATH={{ flask_venv_path }}/bin:/usr/bin"
Environment="DB_HOST={{ flask_db_host }}"
Environment="DB_PORT={{ flask_db_port }}"
Environment="DB_NAME={{ flask_db_name }}"
Environment="DB_USER={{ flask_db_user }}"
Environment="DB_PASSWORD={{ flask_db_password }}"

# Gunicorn 啟動指令
ExecStart={{ flask_venv_path }}/bin/gunicorn \
    --config {{ flask_gunicorn_config }} \
    app:app

# 重啟設定
Restart=always
RestartSec=5

# 安全設定
NoNewPrivileges=true
PrivateTmp=true

[Install]
WantedBy=multi-user.target
```

### gunicorn.conf.py.j2

```jinja2
# {{ ansible_managed }}
# Gunicorn configuration file

# Server socket
bind = "{{ gunicorn_bind }}"
backlog = 2048

# Worker processes
workers = {{ gunicorn_workers }}
worker_class = "sync"
worker_connections = 1000
timeout = {{ gunicorn_timeout }}
keepalive = {{ gunicorn_keepalive }}

# Logging
accesslog = "{{ flask_app_log_path }}/access.log"
errorlog = "{{ flask_app_log_path }}/error.log"
loglevel = "info"
access_log_format = '%(h)s %(l)s %(u)s %(t)s "%(r)s" %(s)s %(b)s "%(f)s" "%(a)s"'

# Process naming
proc_name = "{{ flask_app_name }}"

# Server mechanics
daemon = False
pidfile = None
umask = 0
user = None
group = None
tmp_upload_dir = None
```

### config.py.j2

```jinja2
# {{ ansible_managed }}
# Flask application configuration

import os

# Database
DB_HOST = os.environ.get('DB_HOST', '{{ flask_db_host }}')
DB_PORT = os.environ.get('DB_PORT', '{{ flask_db_port }}')
DB_NAME = os.environ.get('DB_NAME', '{{ flask_db_name }}')
DB_USER = os.environ.get('DB_USER', '{{ flask_db_user }}')
DB_PASSWORD = os.environ.get('DB_PASSWORD', '{{ flask_db_password }}')

# Application
DEBUG = {{ 'True' if app_env == 'development' else 'False' }}
```

## 進階技巧：條件執行

### when 的使用

```yaml
- name: Install development tools
  ansible.builtin.apt:
    name:
      - vim
      - htop
    state: present
  when: app_env == 'development'
```

### 多條件

```yaml
- name: Do something
  ansible.builtin.debug:
    msg: "Both conditions met"
  when:
    - ansible_os_family == 'Debian'
    - flask_workers > 1
```

### changed_when 與 failed_when

有時候 `command` module 的結果需要自訂判斷：

```yaml
- name: Check if virtualenv exists
  ansible.builtin.stat:
    path: "{{ flask_venv_path }}/bin/activate"
  register: venv_stat

- name: Create virtualenv if not exists
  ansible.builtin.command:
    cmd: python3 -m venv {{ flask_venv_path }}
  when: not venv_stat.stat.exists
  changed_when: true  # 這個 command 執行了就算 changed

- name: Check application version
  ansible.builtin.command:
    cmd: "{{ flask_venv_path }}/bin/python -c 'import flask; print(flask.__version__)'"
  register: flask_version
  changed_when: false  # 這個 command 只是查詢，不算 changed
  failed_when: flask_version.rc != 0  # 自訂失敗條件
```

### 思考題

<details>
<summary>Q1：為什麼 systemd service 要設定 NoNewPrivileges=true 和 PrivateTmp=true？</summary>

**安全加固**：

| 設定 | 效果 |
|------|------|
| `NoNewPrivileges=true` | 禁止 process 透過 setuid/setgid 取得更多權限 |
| `PrivateTmp=true` | 給 service 一個獨立的 /tmp，其他 process 看不到 |

這是 systemd 的安全功能，可以限制被入侵的 service 能做的事。其他常見的安全設定還有：

```ini
ProtectSystem=strict      # 將 /boot, /usr, /etc 設為唯讀
ProtectHome=true          # 禁止存取使用者家目錄
ReadOnlyPaths=/etc        # 特定路徑唯讀
```

</details>

<details>
<summary>Q2：為什麼要用 become_user 建立 virtualenv，而不是用 root 建立再 chown？</summary>

**檔案權限問題**：

如果用 root 建立 virtualenv，所有檔案的 owner 都是 root。即使之後 chown 給 flask 使用者：

1. pip 安裝套件時可能有權限問題（cache 目錄）
2. 執行 python 時可能遇到 `.pyc` 編譯快取問題
3. 有些套件會在安裝時寫入 metadata，權限會出錯

用 `become_user: flask` 從一開始就用正確的使用者建立，可以避免這些問題。

</details>

<details>
<summary>Q3：changed_when: false 什麼時候該用？</summary>

**適用場景**：

當 task 只是「查詢」而非「變更」時使用。例如：

```yaml
# 查詢版本 - 不該標記為 changed
- name: Get Python version
  command: python3 --version
  register: python_version
  changed_when: false

# 檢查 service 狀態 - 不該標記為 changed
- name: Check if service is running
  command: systemctl is-active myservice
  register: service_status
  changed_when: false
  failed_when: false  # 即使 service 沒跑也不算失敗
```

**為什麼重要**：

1. Ansible 的 `--check` mode 會跳過 changed 的 task
2. 報告會顯示正確的 changed 數量
3. 觸發 handlers 依賴 changed 狀態

</details>

## 測試 Role

```yaml
# test_flask_app.yml
---
- name: Test Flask App Role
  hosts: web
  become: true

  roles:
    - flask_app
```

```bash
# 執行
ansible-playbook -i inventory/dev test_flask_app.yml

# 驗證
ansible -i inventory/dev web -m shell -a "systemctl status flask-demo"
ansible -i inventory/dev web -m uri -a "url=http://localhost:5000/health"
```

## 完整 Demo 專案

:::note
**完整範例專案**

本文的完整範例專案可以在這裡取得：

- **線上瀏覽**：[flask-deploy 專案結構](/demos/flask-deploy/)
- **直接下載**：
  ```bash
  # 下載完整專案
  curl -L https://blog.csjhuang.net/demos/flask-deploy.tar.gz | tar xz
  cd flask-deploy
  ```

專案包含所有檔案：`ansible.cfg`、`inventory/`、`roles/flask_app/`、`site.yml` 等。
:::

### 專案目錄結構

```
flask-deploy/
├── ansible.cfg
├── requirements.yml
├── site.yml
├── inventory/
│   └── dev/
│       ├── hosts
│       └── group_vars/
│           ├── all.yml
│           └── web.yml
└── roles/
    └── flask_app/
        ├── defaults/main.yml
        ├── vars/main.yml
        ├── tasks/main.yml
        ├── handlers/main.yml
        ├── templates/
        │   ├── flask-app.service.j2
        │   └── gunicorn.conf.py.j2
        └── files/
            ├── app.py
            └── requirements.txt
```

### 快速開始

```bash
# 1. 下載專案
curl -L https://blog.csjhuang.net/demos/flask-deploy.tar.gz | tar xz
cd flask-deploy

# 2. 修改 inventory 中的主機 IP
vim inventory/dev/hosts

# 3. 安裝 collection
ansible-galaxy collection install -r requirements.yml

# 4. 測試連線
ansible all -m ping

# 5. 執行部署
ansible-playbook site.yml

# 6. 驗證部署
ansible web -m uri -a "url=http://localhost:5000/health"
```

## 總結

在這篇文章中，我們學習了：

1. **系統準備**
   - 建立系統使用者（system user）
   - 設定適當的檔案權限

2. **Python 虛擬環境**
   - 使用 `creates` 參數實現 idempotent
   - 用正確的使用者建立 virtualenv

3. **Systemd Service**
   - 用 Template 產生 service unit
   - 設定環境變數
   - 安全加固選項

4. **條件執行**
   - when 的單一和多條件用法
   - changed_when 和 failed_when 自訂判斷

## 下一篇預告

在下一篇文章中，我們會撰寫 **Nginx Role** 並整合所有 roles，包括：

- Nginx 反向代理設定
- Tags 的設計與使用
- 主 Playbook（site.yml）的設計
- 完整的部署流程

## Reference

- [Ansible Documentation - ansible.builtin.pip](https://docs.ansible.com/ansible/latest/collections/ansible/builtin/pip_module.html)
- [Ansible Documentation - Conditionals](https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_conditionals.html)
- [Systemd Documentation - Service Security](https://www.freedesktop.org/software/systemd/man/systemd.exec.html#Sandboxing)
- [Gunicorn Documentation - Settings](https://docs.gunicorn.org/en/stable/settings.html)
