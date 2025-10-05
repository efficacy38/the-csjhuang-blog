---
title: gcloud-008-cloud-setup-dev-environment-cloud-storage
description: gcloud-008-cloud-setup-dev-environment-cloud-storage
pubDate: 2025-10-05
slug: gcloud-008-cloud-setup-dev-environment-cloud-storage
tags:
  - "note"
  - "unclassified"
---

## What we would do

- Create a storage bucket
- Upload objects to the bucket
- Create folders and subfolders in the bucket
- Make objects in a storage bucket publicly accessible

## Setup Environment

```bash
gcloud auth login
gcloud config set project qwiklabs-gcp-02-74ffc5488ff1
export REGION="us-east1"
gcloud config set compute/region $REGION

# valiadtion
gcloud auth list
gcloud config list project
```

## Create bucket

### Naming ruels

- Do not include sensitive information in the bucket name, because the bucket namespace is global and publicly visible.
- Bucket names must contain only lowercase letters, numbers, dashes (-), underscores (\_), and dots (.). Names containing dots require verification.
- Bucket names must start and end with a number or letter.
- Bucket names must contain 3 to 63 characters. Names containing dots can contain up to 222 characters, but each dot-separated component can be no longer than 63 characters.
- Bucket names cannot be represented as an IP address in dotted-decimal notation (for example, 192.168.5.4).
- Bucket names cannot begin with the "goog" prefix.
- Bucket names cannot contain "google" or close misspellings of "google".
- Also, for DNS compliance and future compatibility, you should not use underscores (\_) or have a period adjacent to another period or dash. For example, ".." or "-." or ".-" are not valid in DNS names.

```
# create bucket
BUCKET_NAME="jweklrjwkeljrwklerj"
gcloud storage buckets create gs://$BUCKET_NAME

# download a picture then upload to bucket
curl https://upload.wikimedia.org/wikipedia/commons/thumb/a/a4/Ada_Lovelace_portrait.jpg/800px-Ada_Lovelace_portrait.jpg --output ada.jpg
gcloud storage cp ada.jpg gs://$BUCKET_NAME

rm ada.jpg

# download from storage bucket
gcloud storage cp -r gs://$BUCKET_NAME/ada.jpg .

# copy to bucket directory
gcloud storage cp gs://$BUCKET_NAME/ada.jpg gs://$BUCKET_NAME/image-folder/

# list content of a bucket or folder
gcloud storage ls gs://$BUCKET_NAME

# list detail of bucket
gcloud storage ls -l gs://$BUCKET_NAME
```

### ACL of buckets

```bash
gsutil acl ch -u AllUsers:R gs://$BUCKET_NAME/ada.jpg

# check the bucket content
curl https://storage.googleapis.com/$BUCKET_NAME/ada.jpg

# also can remove public access
gsutil acl ch -d AllUsers gs://$BUCKET_NAME/ada.jpg
```

### Cleanup

```bash
gcloud storage rm gs://$BUCKET_NAME/ada.jpg
```
