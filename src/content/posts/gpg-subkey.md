---
title: GPG subkey usage
description: 如何使用 gpg subkey
pubDate: 2025-01-28
slug: gpg-subkey-usage
tags:
    - "cryptography"
    - "gpg"
---

在前一篇 blog 中已經先介紹 gpg 的簡單用法，這篇 blog 主要面對的是 gpg 的進階用法 - gpg subkey

## Intro

// TODO: add some intro

## 環境安裝

詳情請看[上一篇 blog](/posts/gpg-101#環境安裝) 的介紹。

## 產生 sub-key

要產生 gpg key 之前需要知道 master key 的 keyid，可以用 `gpg --list-secret-keys`
檢查目前的 keyid，這裡以 <efficacy38-batch@justforfun.com> 這個 key 爲例。
下圖的 keyid 就是 `8ACA9219A777D7759B1E7F9D61AFE1BB75188735`

```bash
❯ gpg --list-secret-keys

[keyboxd]
---------
sec   rsa4096 2025-01-28 [SCEAR] [expires: 2035-01-26]
      8ACA9219A777D7759B1E7F9D61AFE1BB75188735
uid           [ultimate] "Cai-Sian Jhuang(batch)" <"efficacy38-batch@justforfun.com">
ssb   rsa4096 2025-01-28 [S] [expires: 2035-01-26]

sec   ed25519 2025-01-28 [SC] [expires: 2028-01-28]
      CE335FC172D80BF14AB4A54FAA8C96C05B158FBE
uid           [ultimate] Cai-Sian Jhuang <efficacy38@justforfun.com>
ssb   cv25519 2025-01-28 [E] [expires: 2028-01-28]
```

這裏可以看到當初 gen 這個 key 的時候已經有生成一個 Encrypt subkey 了，所以我們
在下面的範例就生成一個 Sign only 的 key。

### Interactive CLI

```bash
❯ gpg --edit-key 8ACA9219A777D7759B1E7F9D61AFE1BB75188735
gpg (GnuPG) 2.4.5; Copyright (C) 2024 g10 Code GmbH
This is free software: you are free to change and redistribute it.
There is NO WARRANTY, to the extent permitted by law.

Secret key is available.

sec  rsa4096/61AFE1BB75188735
     created: 2025-01-28  expires: 2035-01-26  usage: SCEAR
     trust: ultimate      validity: ultimate
ssb  rsa4096/2B5BFC7FFA617988
     created: 2025-01-28  expires: 2035-01-26  usage: S
[ultimate] (1). "Cai-Sian Jhuang(batch)" <"efficacy38-batch@justforfun.com">

gpg> addkey
Please select what kind of key you want:
   (3) DSA (sign only)
   (4) RSA (sign only)
   (5) Elgamal (encrypt only)
   (6) RSA (encrypt only)
  (10) ECC (sign only)
  (12) ECC (encrypt only)
  (14) Existing key from card
Your selection? 12
Please select which elliptic curve you want:
   (1) Curve 25519 *default*
   (4) NIST P-384
   (6) Brainpool P-256
Your selection?
Please specify how long the key should be valid.
         0 = key does not expire
      <n>  = key expires in n days
      <n>w = key expires in n weeks
      <n>m = key expires in n months
      <n>y = key expires in n years
Key is valid for? (0) 365
Key expires at 西元2026年01月29日 (週四) 09時23分30秒 CST
Is this correct? (y/N) y
Really create? (y/N) y
We need to generate a lot of random bytes. It is a good idea to perform
some other action (type on the keyboard, move the mouse, utilize the
disks) during the prime generation; this gives the random number
generator a better chance to gain enough entropy.

sec  rsa4096/61AFE1BB75188735
     created: 2025-01-28  expires: 2035-01-26  usage: SCEAR
     trust: ultimate      validity: ultimate
ssb  rsa4096/2B5BFC7FFA617988
     created: 2025-01-28  expires: 2035-01-26  usage: S
ssb  cv25519/F3DA9D769ADF6B77
     created: 2025-01-29  expires: 2026-01-29  usage: E
[ultimate] (1). "Cai-Sian Jhuang(batch)" <"efficacy38-batch@justforfun.com">

gpg> save
```

### Declactive CLI

```bash
MASTER_KEYID=8ACA9219A777D7759B1E7F9D61AFE1BB75188735
gpg --batch --passphrase '' --quick-add-key "$MASTER_KEYID" RSA4096 sign 1y
```

### 查看目前的 subkey(以及 fingerprint)

subkey fingerprint 就會在以下的 subkey 底下顯示出來:

- `73A133231D793AE3874F2E182B5BFC7FFA617988`
- `C75657A9616AB5132B2A91B6F3DA9D769ADF6B77`
- `A21A351669D987765EEAFA678226374E1F6DCAA0`

```bash
❯ gpg --list-key --with-subkey-fingerprint efficacy38-batch
pub   rsa4096 2025-01-28 [SCEAR] [expires: 2035-01-26]
      8ACA9219A777D7759B1E7F9D61AFE1BB75188735
uid           [ultimate] "Cai-Sian Jhuang(batch)" <"efficacy38-batch@justforfun.com">
sub   rsa4096 2025-01-28 [S] [expires: 2035-01-26]
      73A133231D793AE3874F2E182B5BFC7FFA617988
sub   cv25519 2025-01-29 [E] [expires: 2026-01-29]
      C75657A9616AB5132B2A91B6F3DA9D769ADF6B77
sub   rsa4096 2025-01-29 [S] [expires: 2026-01-29]
      A21A351669D987765EEAFA678226374E1F6DCAA0
```

## 匯出 subkey

### 匯出含有 masterkey 的 key

就跟前一篇提到的 export 方式相同，但較不符合 gpg 的使用方式。
確認是否有 3 把 gpg sub key，下圖分別爲 3 把不同的 subkey

```bash
❯ gpg --output secret-subkeys --export-secret-subkeys
pub   rsa4096 2025-01-28 [SCEAR] [expires: 2035-01-26]
      8ACA9219A777D7759B1E7F9D61AFE1BB75188735
uid           [ultimate] "Cai-Sian Jhuang(batch)" <"efficacy38-batch@justforfun.com">
sub   rsa4096 2025-01-28 [S] [expires: 2035-01-26]
      73A133231D793AE3874F2E182B5BFC7FFA617988
sub   cv25519 2025-01-29 [E] [expires: 2026-01-29]
      C75657A9616AB5132B2A91B6F3DA9D769ADF6B77
sub   rsa4096 2025-01-29 [S] [expires: 2026-01-29]
      A21A351669D987765EEAFA678226374E1F6DCAA0
```

確認目前的要 export 的 subkey fingerprint(`A21A351669D987765EEAFA678226374E1F6DCAA0`)，
並使用以下的語法將 subkey export 出來。

```bash
# export master key(with secret key)
MASTER_KEYID=8ACA9219A777D7759B1E7F9D61AFE1BB75188735
SUBKEY_FINGERPRINT=A21A351669D987765EEAFA678226374E1F6DCAA0
gpg --armor --output mastersubkey.asc --export-secret-keys $MASTER_KEYID ${SUBKEY_FINGERPRINT}!
```

:::warning
注意 export key 的時候，subkey fingerprint 後面要加 `!`
:::

### 測試 subkey 是否正確 import

以下將 gpg 存放的資料放到 tmp 裡，以模擬在另一機器 import 的情況。

```bash
❯ TMP_GPG_HOME=$(mktemp -d)
❯ gpg --homedir=$TMP_GPG_HOME --list-keys
gpg: keybox '/tmp/nix-shell.CmQEIF/tmp.wfVS6eJ2Pq/pubring.kbx' created
gpg: /tmp/nix-shell.CmQEIF/tmp.wfVS6eJ2Pq/trustdb.gpg: trustdb created
❯ gpg --homedir=$TMP_GPG_HOME --import mastersubkey.asc
gpg: key 61AFE1BB75188735: public key ""Cai-Sian Jhuang(batch)" <"efficacy38-batch@justforfun.com">" imported
gpg: key 61AFE1BB75188735: secret key imported
gpg: Total number processed: 1
gpg:               imported: 1
gpg:       secret keys read: 1
gpg:   secret keys imported: 1
❯ gpg --homedir=$TMP_GPG_HOME --list-keys

/tmp/nix-shell.CmQEIF/tmp.wfVS6eJ2Pq/pubring.kbx
------------------------------------------------
pub   rsa4096 2025-01-28 [SCEAR] [expires: 2035-01-26]
      8ACA9219A777D7759B1E7F9D61AFE1BB75188735
uid           [ unknown] "Cai-Sian Jhuang(batch)" <"efficacy38-batch@justforfun.com">
sub   rsa4096 2025-01-29 [S] [expires: 2026-01-29]
```

:::info
這時的 primary key 旁邊還沒有 * 字號(代表已經刪除)
:::

### 匯出不含 master key 的 gpg subkey

1. 重複上面的操作
2. 我們需要知道 masterekey 的 keygroup id，下面的例子爲 `B430506D189CE886832787F2C88BA23453EBBE18`

    ```bash
    MASTER_KEYID=8ACA9219A777D7759B1E7F9D61AFE1BB75188735
    ❯ gpg --homedir=$TMP_GPG_HOME --with-keygrip --list-key $MASTER_KEYID

    pub   rsa4096 2025-01-28 [SCEAR] [expires: 2035-01-26]
        8ACA9219A777D7759B1E7F9D61AFE1BB75188735
        Keygrip = B430506D189CE886832787F2C88BA23453EBBE18
    uid           [ultimate] "Cai-Sian Jhuang(batch)" <"efficacy38-batch@justforfun.com">
    sub   rsa4096 2025-01-28 [S] [expires: 2035-01-26]
        Keygrip = 4EEA168C560DEB98339168DF1113AAB57EA8BCC9
    sub   cv25519 2025-01-29 [E] [expires: 2026-01-29]
        Keygrip = D6F61329BD771E4489C071F074EC03EE7259EE5F
    sub   rsa4096 2025-01-29 [S] [expires: 2026-01-29]
        Keygrip = CB7AF1587061E75CE8866D20E4E318E1BEA6BCC0
    ```

3. 到存放 gpg key 的位置(通常爲 `~/.gnupg/`)把 masterkey 的 private key 刪除

    ```bash
    PRIMARY_KEYGROUP_ID=B430506D189CE886832787F2C88BA23453EBBE18
    rm $TMP_GPG_HOME/private-keys-v1.d/$PRIMARY_KEYGROUP_ID.key
    ```

4. 確認 primary key 是否已經刪除，有 `#` 在 masterkey 旁就代表成功把 masterkey 的
   private key 刪除了

    ```bash
    ❯ gpg --homedir=$TMP_GPG_HOME --list-secret-keys

    /tmp/nix-shell.CmQEIF/tmp.wfVS6eJ2Pq/pubring.kbx
    ------------------------------------------------
    sec#  rsa4096 2025-01-28 [SCEAR] [expires: 2035-01-26]
        8ACA9219A777D7759B1E7F9D61AFE1BB75188735
    uid           [ unknown] "Cai-Sian Jhuang(batch)" <"efficacy38-batch@justforfun.com">
    ssb   rsa4096 2025-01-29 [S] [expires: 2026-01-29]
    ```

## How to sign with subkey

在以下的範例用 `A21A351669D987765EEAFA678226374E1F6DCAA0` 這個 subkey 進行簽章
對以下的檔案進行簽章。

```text
// secret.txt
傳位十四子
```

```bash
SUBKEY_FINGERPRINT=A21A351669D987765EEAFA678226374E1F6DCAA0
gpg -u ${SUBKEY_FINGERPRINT}! --clear-sign -o secret.txt.asc secret.txt

❯ cat secret.txt.asc
-----BEGIN PGP SIGNED MESSAGE-----
Hash: SHA256

// secret.txt
傳位十四子
-----BEGIN PGP SIGNATURE-----

iQIzBAEBCAAdFiEEoho1FmnZh3Ze6vpngiY3Th9tyqAFAmeZjZQACgkQgiY3Th9t
yqBWhg//a9XIuHRj1QiVJXQWWTPiR0VlXcSkom14yTDhRwaL36MhIe5JDqTpdsCg
cjbe3bVmMQkw2dJK2EvLIdCrpHnio+5Or8V2luzQA2CFx0U/X2yj4crPGT9yYqp5
KdNMY6xDEyZZVGMC3G/ZdpxfbkfvzcfXQoikp/vnd5zuVvyFjcBuFghR3y0UFQwW
bPK2r8CRgGlWtaAR1jL9hXLR4M25czqn+LjFdd6wON7VDKfle+/HZpXKMPMNSaZ8
s1ytObR45U857LFxAFNdEhACTVLalnyrZFVWrHgW1mpjj/j/epoH27NPgXZpehu1
m0ED80ci0FjqDtnbJqpqzpeUDzXfXJnjLoNhRYvEOJJUlzrKj4YAtk0mszsBfdPB
Y3u2nQI4nPfhufRqZQYR12FINNRlPlKo8jMDo9juDX6dXa5Qpi0n+g875D+YsARX
51BOOocBGNFl7RgXBrCoQ+i8LBhakfJn0Dpnisv6udC/w91iv5le0FgnQ3W5g4el
Cp+lB2U+IWtqgoPKQ8daaUuG6WNTyNjZvhi51iHWsXw5fey6hTQ8BbyVhj8jHHdk
tCZRrHlAc5fuRclPJU/CW2y2kXXsWnnN2MjGvv1cVlnvuHv6b5qgWycLFQ9yOUnR
mKBfh3HKd7UZsbUx48rV87V7WwLs75YKo/pHLXB3BcQQzIG7pT8=
=++w7
-----END PGP SIGNATURE-----
```

使用 gpg subkey 進行驗證，可以發現驗證成功了

```bash
❯ gpg --homedir $TMP_GPG_HOME --verify secret.txt.asc                                                                                                            with efficacy38@phoenixton
gpg: Signature made 西元2025年01月29日 (週三) 10時08分20秒 CST
gpg:                using RSA key A21A351669D987765EEAFA678226374E1F6DCAA0
gpg: Good signature from ""Cai-Sian Jhuang(batch)" <"efficacy38-batch@justforfun.com">" [unknown]
gpg: WARNING: This key is not certified with a trusted signature!
gpg:          There is no indication that the signature belongs to the owner.
Primary key fingerprint: 8ACA 9219 A777 D775 9B1E  7F9D 61AF E1BB 7518 8735
     Subkey fingerprint: A21A 3516 69D9 8776 5EEA  FA67 8226 374E 1F6D CAA0
gpg: WARNING: not a detached signature; file 'secret.txt' was NOT verified!
```

## Summary

在這篇文章介紹了以下幾個概念:

1. 如何建立/刪除/import/export gpg subkey
2. 如何將 subkey 的 masterkey 刪除
3. 透過 `--homedir` 可以讓 gpg 不要吃到當前 GPG_HOME 的值，可以更方便的測試

## Reference

- [APNIC Lab Training: Securing Email with PGP](https://wiki.apnictraining.net/_media/netsec2017-idopm/1-pgp.pdf)
- [Debian Subkey Tutorial](https://wiki.debian.org/Subkeys)
