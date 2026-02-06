# Flask Deploy Demo

這是 [Ansible 實戰：撰寫 Flask App Role](https://blog.csjhuang.net/posts/ansible-004-flask-app-role) 文章的完整範例專案。

## 專案結構

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

## 快速開始

```bash
# 1. 修改 inventory 中的主機 IP
vim inventory/dev/hosts

# 2. 安裝 collection
ansible-galaxy collection install -r requirements.yml

# 3. 測試連線
ansible all -m ping

# 4. 執行部署
ansible-playbook site.yml

# 5. 驗證部署
ansible web -m uri -a "url=http://localhost:5000/health"
```

## 自訂設定

### 修改主機 IP

編輯 `inventory/dev/hosts`：

```ini
[web]
web01 ansible_host=YOUR_WEB_SERVER_IP

[db]
db01 ansible_host=YOUR_DB_SERVER_IP
```

### 修改應用設定

編輯 `inventory/dev/group_vars/web.yml`：

```yaml
flask_app_port: 5000
flask_workers: 4  # 調整 worker 數量
```

### 修改資料庫密碼

編輯 `inventory/dev/group_vars/all.yml`：

```yaml
db_password: "your_secure_password"
```

## 相關文章

- [Ansible 實戰：專案結構與 Convention](https://blog.csjhuang.net/posts/ansible-001-project-structure)
- [Ansible 實戰：Inventory 與變數管理](https://blog.csjhuang.net/posts/ansible-002-inventory-variables)
- [Ansible 實戰：撰寫 PostgreSQL Role](https://blog.csjhuang.net/posts/ansible-003-postgresql-role)
- [Ansible 實戰：撰寫 Flask App Role](https://blog.csjhuang.net/posts/ansible-004-flask-app-role)
- [Ansible 實戰：Nginx Role 與專案整合](https://blog.csjhuang.net/posts/ansible-005-nginx-integration)
- [Ansible 實戰：Vault、進階技巧與測試](https://blog.csjhuang.net/posts/ansible-006-vault-advanced-testing)
