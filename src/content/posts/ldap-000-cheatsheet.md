---
title: LDAP Cheatsheet
description: LDAP 常用指令速查，包含 ldapsearch、ldapadd、ldapmodify、ldapdelete 與 FreeIPA 對照
date: 2026-02-02
slug: ldap-cheatsheet
series: "freeipa"
tags:
    - "ldap"
    - "freeipa"
    - "note"
---

LDAP 操作的快速參考，涵蓋 OpenLDAP 命令列工具與 FreeIPA `ipa` 指令對照。

:::note
**前置閱讀**

本文假設你對 LDAP 目錄結構有基本認識。如果你使用 FreeIPA 並透過 Kerberos 認證，建議先閱讀：
- [Kerberos 入門指南](/posts/kerberos-101)——理解 Kerberos ticket 與 GSSAPI 認證
:::

## 術語速查

| 術語 | 說明 |
|------|------|
| DN | Distinguished Name，物件的唯一識別路徑，如 `uid=john,ou=users,dc=example,dc=com` |
| Base DN | 搜尋的起點，決定從哪個節點開始搜尋 |
| Bind | 認證動作，向 LDAP server 證明身份 |
| LDIF | LDAP Data Interchange Format，用來描述 LDAP 資料的文字格式 |
| SASL | Simple Authentication and Security Layer，支援多種認證機制（如 GSSAPI） |
| GSSAPI | Generic Security Services API，用於 Kerberos 認證 |
| Filter | 搜尋條件，用類似 `(uid=john)` 的語法 |

## 連線與認證

### Simple Bind（帳號密碼）

```bash
# 基本格式
ldapsearch -x -H ldap://ldap.example.com -D "cn=admin,dc=example,dc=com" -W

# 參數說明
# -x: 使用 simple authentication（非 SASL）
# -H: LDAP URI
# -D: Bind DN（用來認證的帳號）
# -W: 互動式輸入密碼
# -w: 直接指定密碼（不建議，會留在 history）
```

### Kerberos (GSSAPI)

```bash
# 先取得 Kerberos ticket
kinit admin

# 使用 GSSAPI 認證
ldapsearch -Y GSSAPI -H ldap://ipa.example.com

# 參數說明
# -Y GSSAPI: 使用 Kerberos 認證
# 不需要 -D 和 -W，身份來自 Kerberos ticket
```

### TLS/STARTTLS

```bash
# STARTTLS（從 ldap:// 升級到加密連線）
ldapsearch -x -ZZ -H ldap://ldap.example.com -D "..." -W

# LDAPS（直接 SSL/TLS 連線）
ldapsearch -x -H ldaps://ldap.example.com -D "..." -W

# 參數說明
# -Z: 嘗試 STARTTLS
# -ZZ: 強制 STARTTLS（失敗則中斷）
# ldaps://: 使用 port 636 的 SSL/TLS

# 如果憑證有問題，可以指定 CA 或跳過驗證
LDAPTLS_CACERT=/path/to/ca.crt ldapsearch ...
LDAPTLS_REQCERT=never ldapsearch ...  # 不建議用於 production
```

## 搜尋範圍 (Scope)

```bash
ldapsearch -s <scope> -b "dc=example,dc=com" "(filter)"
```

| Scope | 說明 | 使用情境 |
|-------|------|---------|
| `base` | 只搜尋 Base DN 本身 | 取得單一物件的屬性 |
| `one` | 只搜尋 Base DN 的直接子項 | 列出某 OU 下的物件 |
| `sub` | 搜尋 Base DN 及所有子樹（預設） | 全域搜尋 |

```bash
# 範例：只看 dc=example,dc=com 這個節點本身
ldapsearch -x -s base -b "dc=example,dc=com" "(objectClass=*)"

# 範例：列出 ou=users 下的直接子項
ldapsearch -x -s one -b "ou=users,dc=example,dc=com" "(objectClass=*)"

# 範例：搜尋整個子樹
ldapsearch -x -s sub -b "dc=example,dc=com" "(uid=john)"
```

## Read: ldapsearch

### 基本語法

```bash
ldapsearch [連線選項] -b "baseDN" "filter" [attributes...]
```

### 常用範例

```bash
# 搜尋所有使用者
ldapsearch -x -b "dc=example,dc=com" "(objectClass=inetOrgPerson)"

# 搜尋特定使用者
ldapsearch -x -b "dc=example,dc=com" "(uid=john)"

# 只取特定屬性
ldapsearch -x -b "dc=example,dc=com" "(uid=john)" cn mail uidNumber

# 搜尋所有群組
ldapsearch -x -b "dc=example,dc=com" "(objectClass=groupOfNames)"

# FreeIPA: 搜尋使用者
ldapsearch -Y GSSAPI -b "cn=users,cn=accounts,dc=example,dc=com" "(uid=john)"
```

### FreeIPA 對照

| LDAP | FreeIPA |
|------|---------|
| `ldapsearch ... "(uid=john)"` | `ipa user-show john` |
| `ldapsearch ... "(objectClass=inetOrgPerson)"` | `ipa user-find` |
| `ldapsearch ... "(cn=developers)"` | `ipa group-show developers` |
| `ldapsearch ... "(objectClass=groupOfNames)"` | `ipa group-find` |

## Filter 語法

### 基本運算子

| 運算子 | 說明 | 範例 |
|--------|------|------|
| `=` | 等於 | `(uid=john)` |
| `=*` | 存在（有這個屬性） | `(mail=*)` |
| `~=` | 近似（phonetic） | `(cn~=john)` |
| `>=` | 大於等於 | `(uidNumber>=1000)` |
| `<=` | 小於等於 | `(uidNumber<=2000)` |

### Wildcard

```bash
# 前綴匹配
(uid=john*)

# 後綴匹配
(mail=*@example.com)

# 包含
(cn=*admin*)
```

### 邏輯運算（前置表示法）

```bash
# AND: 找 uid=john 且 objectClass=person
(&(uid=john)(objectClass=person))

# OR: 找 uid=john 或 uid=jane
(|(uid=john)(uid=jane))

# NOT: 找不是 disabled 的帳號
(!(accountStatus=disabled))

# 組合: 找所有啟用的管理員
(&(memberOf=cn=admins,ou=groups,dc=example,dc=com)(!(accountStatus=disabled)))
```

## Create: ldapadd

### LDIF 格式

```bash
ldapadd [連線選項] -f file.ldif
# 或從 stdin
ldapadd [連線選項] << EOF
...
EOF
```

### 新增使用者

```ldif
dn: uid=john,ou=users,dc=example,dc=com
objectClass: inetOrgPerson
objectClass: posixAccount
objectClass: shadowAccount
uid: john
cn: John Doe
sn: Doe
givenName: John
mail: john@example.com
uidNumber: 10001
gidNumber: 10001
homeDirectory: /home/john
loginShell: /bin/bash
userPassword: {SSHA}...
```

```bash
# 執行
ldapadd -x -D "cn=admin,dc=example,dc=com" -W -f user.ldif
```

### 新增群組

```ldif
dn: cn=developers,ou=groups,dc=example,dc=com
objectClass: groupOfNames
cn: developers
member: uid=john,ou=users,dc=example,dc=com
```

### FreeIPA 對照

| LDAP | FreeIPA |
|------|---------|
| `ldapadd -f user.ldif` | `ipa user-add john --first=John --last=Doe` |
| `ldapadd -f group.ldif` | `ipa group-add developers` |

## Update: ldapmodify

### LDIF 格式

```bash
ldapmodify [連線選項] -f changes.ldif
```

### 修改操作類型

```ldif
# 新增屬性
dn: uid=john,ou=users,dc=example,dc=com
changetype: modify
add: mail
mail: john.doe@example.com

# 取代屬性（會覆蓋所有同名屬性）
dn: uid=john,ou=users,dc=example,dc=com
changetype: modify
replace: loginShell
loginShell: /bin/zsh

# 刪除屬性
dn: uid=john,ou=users,dc=example,dc=com
changetype: modify
delete: telephoneNumber

# 刪除特定值（多值屬性時）
dn: uid=john,ou=users,dc=example,dc=com
changetype: modify
delete: mail
mail: old@example.com

# 多個操作合併（用 - 分隔）
dn: uid=john,ou=users,dc=example,dc=com
changetype: modify
replace: cn
cn: John D. Doe
-
add: title
title: Senior Engineer
```

### 群組成員操作

```ldif
# 加入成員
dn: cn=developers,ou=groups,dc=example,dc=com
changetype: modify
add: member
member: uid=jane,ou=users,dc=example,dc=com

# 移除成員
dn: cn=developers,ou=groups,dc=example,dc=com
changetype: modify
delete: member
member: uid=john,ou=users,dc=example,dc=com
```

### FreeIPA 對照

| LDAP | FreeIPA |
|------|---------|
| `ldapmodify` (replace mail) | `ipa user-mod john --email=new@example.com` |
| `ldapmodify` (add member) | `ipa group-add-member developers --users=jane` |
| `ldapmodify` (delete member) | `ipa group-remove-member developers --users=john` |

## Delete: ldapdelete

```bash
# 刪除單一物件
ldapdelete [連線選項] "uid=john,ou=users,dc=example,dc=com"

# 從檔案讀取多個 DN
ldapdelete [連線選項] -f dns-to-delete.txt

# 遞迴刪除（危險！）
ldapdelete -r [連線選項] "ou=old-department,dc=example,dc=com"
```

### FreeIPA 對照

| LDAP | FreeIPA |
|------|---------|
| `ldapdelete "uid=john,..."` | `ipa user-del john` |
| `ldapdelete "cn=developers,..."` | `ipa group-del developers` |

## 其他實用指令

### ldapwhoami

```bash
# 確認目前的認證身份
ldapwhoami -x -D "cn=admin,dc=example,dc=com" -W
# 輸出: dn:cn=admin,dc=example,dc=com

ldapwhoami -Y GSSAPI
# 輸出: dn:uid=admin,cn=users,cn=accounts,dc=example,dc=com
```

### ldappasswd

```bash
# 修改自己的密碼
ldappasswd -x -D "uid=john,ou=users,dc=example,dc=com" -W -S

# 管理員修改他人密碼
ldappasswd -x -D "cn=admin,dc=example,dc=com" -W \
    "uid=john,ou=users,dc=example,dc=com" -S

# 參數說明
# -S: 互動式輸入新密碼
# -s: 直接指定新密碼
```

### FreeIPA 對照

| LDAP | FreeIPA |
|------|---------|
| `ldapwhoami` | `ipa whoami` |
| `ldappasswd` | `ipa passwd john` |

## FreeIPA Base DN 參考

```bash
# FreeIPA 的標準 Base DN 結構
dc=example,dc=com
├── cn=accounts
│   ├── cn=users          # 使用者
│   ├── cn=groups         # 群組
│   ├── cn=services       # Service principals
│   └── cn=computers      # 主機
├── cn=sudo               # Sudo rules
├── cn=hbac               # Host-based access control
└── cn=pbac               # Permission-based access control
```

```bash
# 常用搜尋 Base DN
ldapsearch -Y GSSAPI -b "cn=users,cn=accounts,dc=example,dc=com" ...
ldapsearch -Y GSSAPI -b "cn=groups,cn=accounts,dc=example,dc=com" ...
```
