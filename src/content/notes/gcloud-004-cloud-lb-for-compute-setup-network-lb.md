---
title: Google Cloud：設置網路負載平衡器（Network LB）
description: 學習如何為 Compute Engine 配置 Layer 4 網路負載平衡器
slug: gcloud-004-cloud-lb-for-compute-setup-network-lb
series: "gcloud"
date: 2025-10-05
tags:
  - "gcloud"
  - "google cloud AI study jam 2025"
  - "Implementing Cloud Load Balancing for Compute Engine"
---

## Overview

In this hands-on lab you learn how to set up a passthrough network load balancer (NLB) running on Compute Engine virtual machines (VMs). A Layer 4 (L4) NLB handles traffic based on network-level information like IP addresses and port numbers, and does not inspect the content of the traffic.
There are several ways you can [load balance on Google Cloud](https://cloud.google.com/load-balancing/docs/load-balancing-overview#a_closer_look_at_cloud_load_balancers). This lab takes you through the setup of the following load balancers([Network Load Balancer](https://cloud.google.com/compute/docs/load-balancing/network/))

## Objectives

- Configure the default region and zone for your resources.
- Create multiple web server instances.
- Configure a load balancing service.
- Configure a forwarding rule to distribute traffic

## Setup Environment

```bash
gcloud config set compute/region europe-west1
gcloud config set compute/zone europe-west1-b
gcloud config set project qwiklabs-gcp-02-9d26be8807de

```

```bash
# create vm
gcloud compute instances create www1 \
  --zone=europe-west1-b \
  --tags=network-lb-tag \
  --machine-type=e2-small \
  --image-family=debian-11 \
  --image-project=debian-cloud \
  --metadata=startup-script='#!/bin/bash
    apt-get update
    apt-get install apache2 -y
    service apache2 restart
    echo "
<h3>Web Server: www1</h3>" | tee /var/www/html/index.html'

gcloud compute instances create www2 \
  --zone=europe-west1-b \
  --tags=network-lb-tag \
  --machine-type=e2-small \
  --image-family=debian-11 \
  --image-project=debian-cloud \
  --metadata=startup-script='#!/bin/bash
    apt-get update
    apt-get install apache2 -y
    service apache2 restart
    echo "
<h3>Web Server: www2</h3>" | tee /var/www/html/index.html'

gcloud compute instances create www3 \
  --zone=europe-west1-b  \
  --tags=network-lb-tag \
  --machine-type=e2-small \
  --image-family=debian-11 \
  --image-project=debian-cloud \
  --metadata=startup-script='#!/bin/bash
    apt-get update
    apt-get install apache2 -y
    service apache2 restart
    echo "
<h3>Web Server: www3</h3>" | tee /var/www/html/index.html'

# create firewall rule
gcloud compute firewall-rules create www-firewall-network-lb \
    --target-tags network-lb-tag --allow tcp:80

# Verify fw rules, check instance's external rule
gcloud compute instances list
curl http://[IP_ADDRESS]
```

## Configure the loadbalancing service

```bash
# create external IP address for lb
gcloud compute addresses create network-lb-ip-1 \
  --region europe-west1

# add healthy check for lb
gcloud compute http-health-checks create basic-check
```

## Create the target pool and forwarding rule

- target pool
  - group of backend instance that receive incoming traffic from NLP
  - all backend must "reside in the same gcp region"

```bash
# create target pool
gcloud compute target-pools create www-pool \
  --region europe-west1 --http-health-check basic-check

# add instances into pool
gcloud compute target-pools add-instances www-pool \
    --instances www1,www2,www3

gcloud compute forwarding-rules create www-rule \
    --region  europe-west1 \
    --ports 80 \
    --address network-lb-ip-1 \
    --target-pool www-pool

# check forwarding rule's IP
gcloud compute forwarding-rules describe www-rule --region europe-west1
```
