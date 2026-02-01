---
title: 擴充 Filesystem 容量
description: 這篇文章紀錄了在 Linux/FreeBSD 上如何擴充硬碟以及檔案系統的筆記
date: 2025-09-30
slug: filesystem-101
tags:
    - "filesystem"
    - "linux"
    - "freebsd"
    - "cheatsheet"
---

在管理伺服器時，很常會遇到硬碟空間不足需要擴充的場景。
這篇文章記錄了在 Linux 以及 FreeBSD 上，從最底層的硬碟分割區 (Partition) 到邏輯磁區 (LVM)，再到最上層的檔案系統 (Filesystem) 的擴充指令。

整個流程大致可以分成兩層：

1.  **Disk Level**: 針對硬碟分割區或是 LVM 進行擴充，讓作業系統知道有更多的空間可以使用。
2.  **Filesystem Level**: 針對檔案系統進行擴充，讓檔案系統可以使用到剛剛擴充出來的空間。

---

## Disk Level

在 Disk Level 的擴充，主要會根據你的硬碟分割區格式以及是否有使用 LVM 而有不同的指令。

### GPT (GUID Partition Table)

GPT 是目前主流的硬碟分割區格式，相較於舊的 MBR (Master Boot Record) 格式，可以支援更大的硬碟容量以及更多的分割區。
在 Linux 上我們可以使用 `parted`，而在 FreeBSD 上則是使用 `gpart` 來管理 GPT 分割區。

#### parted (Linux)

`parted` 是 Linux 上一個強大的分割區編輯器。

```bash
# 假設要擴充的硬碟是 /dev/sda
DISK="/dev/sda"

# 首先，印出目前的分割區表，確認要擴充的分割區
parted "$DISK" print

# 接著，使用 resizepart 來擴充分割區。
# 這邊的 3 是分割區的編號，通常資料碟會是 3 號。
# 100% 代表將這個分割區擴充到硬碟的結尾。
parted "$DISK" resizepart 3 100%
```

#### gpart (FreeBSD)

`gpart` 是 FreeBSD 內建用來管理分割區的工具。

```bash
# 假設要擴充的硬碟是 /dev/sda
DISK="/dev/sda"

# 首先，印出目前的分割區表，確認要擴充的分割區
gpart show "$DISK"

# 接著，使用 resize 來擴充分割區。
# -i 3 代表要擴充的是 index 為 3 的分割區。
gpart resize -i 3 "$DISK"
```

### LVM (Logical Volume Manager)

LVM 是 Linux 上一個很好用的邏輯磁區管理工具，他可以把多個實體硬碟/分割區合併成一個邏輯上的 Volume Group (VG)，然後再從這個 VG 切出 Logical Volume (LV) 來使用。
當底層的實體硬碟空間擴充後，我們需要依序擴充 PV -> VG -> LV。

```bash
# 假設要擴充的硬碟分割區是 /dev/sda3
DISKPART="/dev/sda3"

# 首先，讓 LVM 知道底層的實體分割區變大了
# -t 是 test mode，可以先看看結果
pvresize -t "$DISKPART" 
# 確認沒問題後，正式執行
pvresize "$DISKPART"

# 檢查 PV (Physical Volume) 的大小是否已經變大
pvs

# 檢查 VG (Volume Group) 的大小是否也跟著變大
vgs

# 最後，擴充 LV (Logical Volume) 來使用所有 VG 的空間
# -l 100%VG 代表使用 VG 中所有剩餘的空間
lvextend -l 100%VG /dev/volgrp/root
```

---

## Filesystem Level

當底層的 Disk Level 擴充完畢後，最後一步就是通知檔案系統可以使用這塊新的空間了。
這個步驟會根據你使用的檔案系統而有不同的指令。

### XFS

XFS 是個高效能的日誌檔案系統，常用於 RHEL/CentOS 等發行版。

```bash
# 擴充前，先用 df 確認目前的檔案系統大小
df -h

# 使用 xfs_growfs 來擴充檔案系統
# 後面接的是檔案系統的掛載點或是裝置路徑
xfs_growfs /dev/volgrp/root

# 擴充後，再次用 df 確認大小
df -h
```

### EXT4

EXT4 是目前 Linux 上最普及的檔案系統，是 ext3 的後繼者。

```bash
# 擴充前，先用 df 確認目前的檔案系統大小
df -h

# 使用 resize2fs 來擴充檔案系統
# -f 是強制執行，可以避免一些不必要的檢查
resize2fs -f /dev/volgrp/root

# 擴充後，再次用 df 確認大小
df -h
```

### ZFS

ZFS 是一個集檔案系統與邏輯磁區管理於一身的強大工具，常見於 FreeBSD/Solaris，現在 Linux 上的支援也越來越好。
擴充 ZFS 的儲存池 (zpool) 相對單純。

```bash
# 檢查 zpool 的狀態
zpool status

# 檢查 zpool 的大小
zpool list

# 檢查目前可用的硬碟空間
zfs get available zroot
df -h

# 使用 zpool online -e 來讓 zpool 使用底層分割區擴充出來的空間
# 假設 zpool 名稱為 zroot，而擴充的分割區是 da0p4
zpool online -e zroot da0p4

# 擴充後，再次檢查 zpool 大小
zpool list

# 再次檢查可用的硬碟空間
zfs get available zroot
df -h
```

## Summary

這篇文章我們介紹了：

1.  擴充硬碟的兩個主要步驟：Disk Level 與 Filesystem Level。
2.  在 Disk Level 如何使用 `parted` (Linux), `gpart` (FreeBSD) 來擴充 GPT 分割區。
3.  如何擴充 LVM 的 PV, VG, LV。
4.  在 Filesystem Level 如何擴充 XFS, EXT4, ZFS。

希望這份筆記能幫助到需要擴充硬碟空間的人。

## REFERENCE

- [How to resize and growing disks in FreeBSD](https://unixcop.com/how-to-resize-and-growing-disks-in-freebsd/)
- [Expanding FreeBSD root filesystem (UFS)](https://fluca1978.github.io/2021/02/11/FreeBSDExpandingRootFilesystem.html)
- [再谈Linux磁盘扩容（pvresize直接扩容PV）_血灰的博客-CSDN博客](https://blog.csdn.net/weixin_43939767/article/details/124660694)
- [Linux command – parted / (resize , resizepart) + resize2fs](https://benjr.tw/94843)
