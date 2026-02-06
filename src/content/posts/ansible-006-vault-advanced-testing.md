---
title: Ansible 實戰：Vault、進階技巧與測試
description: 使用 Ansible Vault 加密敏感資訊、Rolling Update 策略、錯誤處理，以及 Ansible Lint 測試
date: 2026-02-02
slug: ansible-006-vault-advanced-testing
series: "ansible"
tags:
    - "ansible"
    - "devops"
    - "note"
---

:::note
**前置閱讀**

本文是 Ansible 實戰系列的最後一篇。假設你已經讀過前五篇文章，並完成了 Flask + Nginx + PostgreSQL 的部署專案。
:::

在這篇文章中，我們會介紹：

- **Ansible Vault**：加密敏感資訊（密碼、API key）
- **進階技巧**：Rolling update、錯誤處理、block/rescue
- **測試與驗證**：Ansible Lint、--check mode、--diff

## Ansible Vault

Ansible Vault 可以加密 Ansible 的變數檔案或單一變數，讓你可以安全地把敏感資訊存進 Git。

### 基本操作

```bash
# 建立加密檔案
ansible-vault create secrets.yml

# 編輯加密檔案
ansible-vault edit secrets.yml

# 加密現有檔案
ansible-vault encrypt group_vars/all/vault.yml

# 解密檔案
ansible-vault decrypt secrets.yml

# 查看加密檔案內容（不解密）
ansible-vault view secrets.yml

# 更換密碼
ansible-vault rekey secrets.yml
```

### 在我們的專案中使用 Vault

讓我們把資料庫密碼加密。首先，調整目錄結構：

```
inventory/dev/group_vars/
├── all/                    # 改用目錄
│   ├── main.yml           # 一般變數
│   └── vault.yml          # 加密變數
├── web.yml
└── db.yml
```

建立加密的變數檔：

```bash
ansible-vault create inventory/dev/group_vars/all/vault.yml
```

輸入內容：

```yaml
# inventory/dev/group_vars/all/vault.yml (已加密)
---
vault_db_password: "super_secret_password_123"
vault_flask_secret_key: "another_secret_key_456"
```

在 `main.yml` 中引用：

```yaml
# inventory/dev/group_vars/all/main.yml
---
# ... 其他設定 ...

# 引用 Vault 中的變數
db_password: "{{ vault_db_password }}"
flask_secret_key: "{{ vault_flask_secret_key }}"
```

### 執行時提供密碼

```bash
# 互動式輸入密碼
ansible-playbook -i inventory/dev site.yml --ask-vault-pass

# 從檔案讀取密碼
echo "my_vault_password" > .vault_password
chmod 600 .vault_password
ansible-playbook -i inventory/dev site.yml --vault-password-file .vault_password

# 在 ansible.cfg 中設定（方便但要小心不要 commit）
# [defaults]
# vault_password_file = .vault_password
```

:::warning
**安全提醒**

- `.vault_password` 檔案**不要**加入 Git（加到 `.gitignore`）
- CI/CD 中，用環境變數或 secret manager 傳入密碼
- 不同環境可以用不同的 vault 密碼
:::

### 加密單一變數

如果只想加密單一變數而非整個檔案：

```bash
# 加密單一字串
ansible-vault encrypt_string 'super_secret_password' --name 'vault_db_password'

# 輸出：
# vault_db_password: !vault |
#           $ANSIBLE_VAULT;1.1;AES256
#           61626364656667...
```

把輸出貼到 YAML 檔案中即可。

### Vault 的替代方案

Ansible Vault 雖然方便，但也有一些缺點：

- 編輯體驗不佳（需要用 `ansible-vault edit`）
- 密碼管理麻煩（尤其是多人協作）
- Diff 不友善（加密內容無法 code review）

根據你的使用場景，以下是一些替代方案：

#### 方案一：Extra Vars 傳入（推薦用於 CI/CD）

最簡單的做法是**不儲存** credential，而是執行時透過 `--extra-vars` 傳入：

```bash
# 從環境變數傳入
ansible-playbook -i inventory/dev site.yml \
  -e "db_password=${DB_PASSWORD}" \
  -e "flask_secret_key=${FLASK_SECRET_KEY}"

# 從檔案傳入（檔案不進 Git）
ansible-playbook -i inventory/dev site.yml \
  -e "@secrets.yml"
```

**優點**：
- Credential 完全不進 Git
- CI/CD 整合簡單（用 GitLab CI Variables、GitHub Secrets 等）
- 不需要管理 vault 密碼

**缺點**：
- 本地開發時需要手動設定環境變數
- 需要另外記錄有哪些 credential 要傳

#### 方案二：外部 Secret Manager

整合 HashiCorp Vault、AWS Secrets Manager、Azure Key Vault 等：

```yaml
# 使用 community.hashi_vault collection
- name: Get secret from HashiCorp Vault
  ansible.builtin.set_fact:
    db_password: "{{ lookup('community.hashi_vault.hashi_vault', 'secret/data/myapp:db_password') }}"
```

```yaml
# 使用 AWS Secrets Manager
- name: Get secret from AWS
  ansible.builtin.set_fact:
    db_password: "{{ lookup('amazon.aws.aws_secret', 'myapp/db_password') }}"
```

**優點**：
- 集中管理 secrets
- 有完整的 audit log
- 支援 secret rotation

**缺點**：
- 需要額外的基礎設施
- 增加複雜度

#### 方案三：混合使用

實務上常見的做法是**混合使用**：

| 環境 | 做法 |
|------|------|
| 開發環境 | 使用 Ansible Vault（密碼簡單，方便本地開發） |
| CI/CD | 使用 extra-vars + CI 的 secret 功能 |
| 生產環境 | 使用外部 Secret Manager |

```yaml
# group_vars/all/main.yml
---
# 開發環境有預設值，CI/CD 會覆蓋
db_password: "{{ vault_db_password | default(lookup('env', 'DB_PASSWORD')) }}"
```

這樣開發時用 Vault，CI/CD 時用環境變數。

### Lookup Plugins 介紹

在上面的範例中，我們用了 `lookup('env', 'DB_PASSWORD')` 來讀取環境變數。Lookup plugins 是 Ansible 用來從外部來源取得資料的機制。

#### 查看可用的 Lookup Plugins

```bash
# 列出所有可用的 lookup plugins
ansible-doc -t lookup -l

# 查看特定 lookup 的用法
ansible-doc -t lookup file
ansible-doc -t lookup env
ansible-doc -t lookup pipe
```

#### 常用的 Lookup Plugins

| Plugin | 用途 | 範例 |
|--------|------|------|
| `file` | 讀取檔案內容 | `lookup('file', '/path/to/file')` |
| `env` | 讀取環境變數 | `lookup('env', 'HOME')` |
| `pipe` | 執行 shell 指令 | `lookup('pipe', 'date +%Y%m%d')` |
| `password` | 產生或讀取密碼 | `lookup('password', '/tmp/pass length=16')` |
| `template` | 渲染 Jinja2 模板 | `lookup('template', 'my.j2')` |
| `url` | 取得 URL 內容 | `lookup('url', 'https://api.example.com')` |
| `csvfile` | 讀取 CSV 檔案 | `lookup('csvfile', 'key file=data.csv')` |
| `ini` | 讀取 INI 檔案 | `lookup('ini', 'key section=section file=config.ini')` |

#### 實用範例

```yaml
# 讀取 SSH public key
- name: Add SSH key
  ansible.builtin.authorized_key:
    user: deploy
    key: "{{ lookup('file', '~/.ssh/id_rsa.pub') }}"

# 從環境變數取得 API key（有預設值）
- name: Set API key
  ansible.builtin.set_fact:
    api_key: "{{ lookup('env', 'API_KEY') | default('dev-key', true) }}"

# 執行本地指令取得 git commit hash
- name: Get current commit
  ansible.builtin.set_fact:
    git_commit: "{{ lookup('pipe', 'git rev-parse --short HEAD') }}"

# 產生隨機密碼並存檔（只產生一次）
- name: Generate DB password
  ansible.builtin.set_fact:
    generated_password: "{{ lookup('password', 'credentials/db_password length=32 chars=ascii_letters,digits') }}"

# 讀取 JSON 檔案
- name: Load config
  ansible.builtin.set_fact:
    app_config: "{{ lookup('file', 'config.json') | from_json }}"

# 使用 community collection 的 lookup
# HashiCorp Vault
- name: Get secret from Vault
  ansible.builtin.set_fact:
    secret: "{{ lookup('community.hashi_vault.hashi_vault', 'secret/data/myapp:password') }}"

# AWS Secrets Manager
- name: Get AWS secret
  ansible.builtin.set_fact:
    aws_secret: "{{ lookup('amazon.aws.aws_secret', 'myapp/api_key') }}"
```

#### Lookup vs Module

Lookup 和 Module 的差別：

| 特性 | Lookup | Module |
|------|--------|--------|
| 執行位置 | **Control node**（本地） | **Managed node**（遠端） |
| 用途 | 取得資料供模板或變數使用 | 在遠端執行操作 |
| 傳回值 | 字串或 list | 結構化的結果 |

```yaml
# Lookup: 在本地讀取檔案，傳送內容到遠端
- name: Copy SSH key (lookup)
  ansible.builtin.copy:
    content: "{{ lookup('file', '~/.ssh/id_rsa.pub') }}"
    dest: /home/deploy/.ssh/authorized_keys

# Module: 在遠端讀取檔案
- name: Read remote file (module)
  ansible.builtin.slurp:
    src: /etc/hostname
  register: hostname_content
```

### 思考題

<details>
<summary>Q1：為什麼要用 vault_ prefix 命名加密變數？</summary>

**清晰度和安全性**：

1. **一眼辨識**：看到 `vault_` 開頭的變數，馬上知道它是加密的
2. **避免意外覆寫**：加密變數和一般變數分開，不會不小心用明文覆蓋
3. **方便搜尋**：`grep vault_` 可以快速找出所有敏感變數

**常見的命名慣例**：

```yaml
# vault.yml (加密)
vault_db_password: "..."
vault_api_key: "..."

# main.yml (明文)
db_password: "{{ vault_db_password }}"
api_key: "{{ vault_api_key }}"
```

</details>

<details>
<summary>Q2：多人協作時，Vault 密碼怎麼管理？</summary>

**常見做法**：

| 方式 | 適用場景 | 風險 |
|-----|---------|------|
| 共用密碼 | 小型團隊 | 人員離職需要換密碼 |
| 密碼管理器（1Password、Vault） | 中大型團隊 | 依賴外部服務 |
| 不同環境不同密碼 | 所有團隊 | 推薦做法 |

**最佳實踐**：

1. Dev/Staging 用較簡單的密碼，Production 用強密碼
2. Production 密碼只有少數人知道
3. CI/CD 中用環境變數注入密碼
4. 定期輪換密碼（`ansible-vault rekey`）

</details>

## 進階技巧

### Rolling Update

當你有多台 Web Server 時，不應該同時重啟全部——這會導致服務中斷。Rolling update 是一次更新一部分主機。

```yaml
# rolling_restart.yml
---
- name: Rolling restart Flask App
  hosts: web
  serial: 1                           # 一次只處理 1 台
  # serial: "30%"                     # 或每次處理 30% 的主機
  max_fail_percentage: 0              # 任何一台失敗就停止

  tasks:
    - name: Restart Flask App
      ansible.builtin.service:
        name: flask-demo
        state: restarted

    - name: Wait for app to be ready
      ansible.builtin.uri:
        url: "http://localhost:5000/health"
        status_code: 200
      register: health_check
      until: health_check.status == 200
      retries: 10
      delay: 3

    - name: Verify through load balancer
      ansible.builtin.uri:
        url: "http://{{ inventory_hostname }}/health"
        status_code: 200
      delegate_to: localhost           # 從控制機執行
```

**關鍵參數**：

| 參數 | 說明 |
|------|------|
| `serial` | 每批次處理的主機數量 |
| `max_fail_percentage` | 允許失敗的百分比，超過就停止 |
| `delegate_to` | 把 task 委託給其他主機執行 |

### 錯誤處理：block/rescue/always

類似 try/catch/finally：

```yaml
- name: Deploy with error handling
  hosts: web
  tasks:
    - name: Deployment block
      block:
        - name: Stop application
          ansible.builtin.service:
            name: flask-demo
            state: stopped

        - name: Deploy new code
          ansible.builtin.copy:
            src: new_app.py
            dest: /opt/flask-demo/app.py

        - name: Start application
          ansible.builtin.service:
            name: flask-demo
            state: started

      rescue:
        - name: Rollback - restore old code
          ansible.builtin.copy:
            src: /opt/flask-demo/app.py.bak
            dest: /opt/flask-demo/app.py
            remote_src: true

        - name: Start application with old code
          ansible.builtin.service:
            name: flask-demo
            state: started

        - name: Notify about failure
          ansible.builtin.debug:
            msg: "Deployment failed! Rolled back to previous version."

      always:
        - name: Clean up temp files
          ansible.builtin.file:
            path: /tmp/deploy_temp
            state: absent
```

### ignore_errors 與 failed_when

```yaml
# 忽略錯誤（謹慎使用）
- name: Remove optional file
  ansible.builtin.file:
    path: /tmp/optional_file
    state: absent
  ignore_errors: true

# 自訂失敗條件
- name: Check disk space
  ansible.builtin.shell: df -h / | tail -1 | awk '{print $5}' | sed 's/%//'
  register: disk_usage
  failed_when: disk_usage.stdout | int > 90
  changed_when: false
```

### run_once 與 delegate_to

```yaml
# 只在一台主機執行（例如 DB migration）
- name: Run database migration
  ansible.builtin.command:
    cmd: /opt/flask-demo/venv/bin/python manage.py migrate
  run_once: true

# 委託給其他主機執行
- name: Update DNS record
  community.general.cloudflare_dns:
    zone: example.com
    record: app
    type: A
    value: "{{ ansible_host }}"
  delegate_to: localhost

# 委託給特定群組的第一台
- name: Notify load balancer
  ansible.builtin.uri:
    url: "http://{{ groups['lb'][0] }}/api/update"
    method: POST
  delegate_to: "{{ groups['lb'][0] }}"
```

### 思考題

<details>
<summary>Q1：serial: 1 和 serial: "50%" 的差異是什麼？什麼時候用哪個？</summary>

**差異**：

| 設定 | 10 台主機的行為 |
|------|----------------|
| `serial: 1` | 1 → 1 → 1 → ... 共 10 批 |
| `serial: "50%"` | 5 → 5，共 2 批 |
| `serial: [1, 5, "100%"]` | 1 → 5 → 4，共 3 批 |

**使用時機**：

- `serial: 1`：最安全，但最慢。適合第一次部署新版本時
- `serial: "50%"`：平衡速度和安全。適合有信心的部署
- `serial: [1, 5, "100%"]`：先試一台，沒問題再加速。推薦的生產環境策略

</details>

<details>
<summary>Q2：什麼時候該用 ignore_errors，什麼時候該用 failed_when: false？</summary>

**ignore_errors**：

- 知道可能會失敗，但不在乎
- 結果會標記為 `...ignoring`
- 例如：刪除可能不存在的檔案

**failed_when: false**：

- 永遠不算失敗（即使 return code 非 0）
- 結果會顯示正常
- 例如：shell 指令 return code 非 0 但這是預期的行為

**更好的做法**：明確定義什麼是「成功」：

```yaml
- name: Check if file exists
  ansible.builtin.stat:
    path: /tmp/myfile
  register: myfile

- name: Remove file if exists
  ansible.builtin.file:
    path: /tmp/myfile
    state: absent
  when: myfile.stat.exists
```

</details>

## 測試與驗證

### Ansible Lint

Ansible Lint 是靜態分析工具，可以檢查 Playbook 的品質和最佳實踐。

```bash
# 安裝
pip install ansible-lint

# 執行
ansible-lint site.yml

# 檢查整個專案
ansible-lint
```

常見的規則違規：

```yaml
# 1. 沒有 name
- apt: name=nginx state=present          # 錯誤
- name: Install nginx                    # 正確
  apt: name=nginx state=present

# 2. 使用 shell 而非專用 module
- shell: apt-get install nginx           # 錯誤
- apt: name=nginx state=present          # 正確

# 3. 沒有使用 FQCN
- apt: name=nginx                        # 警告
- ansible.builtin.apt: name=nginx        # 正確

# 4. 變數名稱有空格
- debug: msg="{{ my var }}"              # 錯誤
- debug: msg="{{ my_var }}"              # 正確
```

### --check 和 --diff

```bash
# Dry-run：不實際執行，只顯示會做什麼
ansible-playbook site.yml --check

# Diff：顯示檔案會有什麼變化
ansible-playbook site.yml --diff

# 兩者結合：最安全的預覽方式
ansible-playbook site.yml --check --diff
```

**限制**：

- `--check` 無法預測 `command`/`shell` 的結果
- 有些 task 依賴前一個 task 的結果，可能會跳過或失敗
- 建議搭配 `check_mode: false` 強制執行某些 task：

```yaml
- name: Get current version
  ansible.builtin.command: cat /opt/app/version
  register: app_version
  check_mode: false     # 即使在 --check 模式也會執行
  changed_when: false
```

### 驗證 Playbook 語法

```bash
# 語法檢查（不連線到主機）
ansible-playbook site.yml --syntax-check

# 列出會影響的主機
ansible-playbook site.yml --list-hosts

# 列出會執行的 tasks
ansible-playbook site.yml --list-tasks

# 列出會使用的 tags
ansible-playbook site.yml --list-tags
```

### CI/CD 整合範例

```yaml
# .gitlab-ci.yml
stages:
  - lint
  - deploy

ansible-lint:
  stage: lint
  image: python:3.11
  script:
    - pip install ansible ansible-lint
    - ansible-lint
    - ansible-playbook site.yml --syntax-check

deploy-staging:
  stage: deploy
  image: python:3.11
  script:
    - pip install ansible
    - ansible-galaxy collection install -r requirements.yml
    - echo "$VAULT_PASSWORD" > .vault_password
    - ansible-playbook -i inventory/staging site.yml --vault-password-file .vault_password
  environment:
    name: staging
  only:
    - main
```

## 系列總結

經過六篇文章，我們完成了：

### 專案成果

```
flask-deploy/
├── ansible.cfg
├── requirements.yml
├── inventory/
│   └── dev/
│       ├── hosts
│       └── group_vars/
│           ├── all/
│           │   ├── main.yml
│           │   └── vault.yml (加密)
│           ├── web.yml
│           └── db.yml
├── roles/
│   ├── postgresql/
│   ├── flask_app/
│   └── nginx/
├── site.yml
├── deploy_app.yml
└── rolling_restart.yml
```

### 學習重點

| 篇章 | 主題 | 核心技能 |
|-----|------|---------|
| 1 | 專案結構與 Convention | 目錄結構、Role 組織 |
| 2 | Inventory 與變數管理 | group_vars、host_vars、變數優先順序 |
| 3 | PostgreSQL Role | Template、Jinja2、Handlers |
| 4 | Flask App Role | virtualenv、systemd、條件執行 |
| 5 | Nginx Role 與整合 | 反向代理、Tags、多 Plays |
| 6 | Vault 與進階技巧 | 加密、Rolling Update、測試 |

### 下一步

1. **閱讀真實專案**：找一些開源的 Ansible 專案來學習（如 DebOps、Geerlingguy 的 roles）
2. **學習 Molecule**：Role 的單元測試框架
3. **嘗試 AWX/Tower**：Ansible 的 Web UI 和 API
4. **學習 Dynamic Inventory**：從 AWS/GCP/Azure 動態取得主機清單

## Reference

- [Ansible Documentation - Vault](https://docs.ansible.com/ansible/latest/vault_guide/index.html)
- [Ansible Documentation - Error Handling](https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_error_handling.html)
- [Ansible Documentation - Delegation](https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_delegation.html)
- [Ansible Lint Documentation](https://ansible.readthedocs.io/projects/lint/)
- [Ansible Documentation - Check Mode](https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_checkmode.html)
