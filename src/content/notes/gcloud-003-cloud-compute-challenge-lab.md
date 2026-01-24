---
title: Google Cloud：Compute Engine 挑戰實驗室
description: Compute Engine 基礎挑戰實驗：設置簡單的 Nginx 伺服器
pubDate: 2025-10-05
slug: gcloud-003-cloud-compute-challenge-lab
tags:
  - "gcloud"
  - "google cloud AI study jam 2025"
  - "The Basics of Google Cloud Compute"
---

# prerequest

```bash
gcloud auth login
gcloud config set project <YOUR project>
gcloud auth list


# set the variables for next use
export REGION=us-west1
export ZONE=us-west1-c
gcloud config set compute/zone "$REGION"
gcloud config set compute/region "$ZONE"

# check zone is good
gcloud config get compute/zone
gcloud config get compute/region
```

## create a cloud storage bucket

```bash
gsutil mb gs://qwiklabs-gcp-02-5616d8aa0f54-bucket

gcloud compute instances create my-instance \
  --zone="$ZONE" \
  --machine-type=e2-medium \
  --image-family=debian-12 \
  --image-project=debian-cloud \
  --boot-disk-type=pd-balanced \
  --boot-disk-size=10GB \
  --tags=http-server
```
