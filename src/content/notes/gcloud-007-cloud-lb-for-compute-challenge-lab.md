---
title: Google Cloud：負載平衡器挑戰實驗室
description: 負載平衡器挑戰實驗：建立多個 Web 伺服器並配置負載平衡
date: 2025-10-05
slug: gcloud-007-cloud-lb-for-compute-challenge-lab
series: "gcloud"
tags:
  - "gcloud"
---

## Setup Environment

```bash
gcloud auth login
gcloud config set project qwiklabs-gcp-02-7a842273f26e
export REGION="us-central1"
export ZONE="us-central1-b"
gcloud config set compute/region us-central1
gcloud config set compute/zone us-central1-b

# valiadtion
gcloud auth list
gcloud config list project
```

## Create multiple web server

```bash
    gcloud compute instances create web1 \
    --zone="$ZONE" \
    --tags=network-lb-tag \
    --machine-type=e2-small \
    --image-family=debian-12 \
    --image-project=debian-cloud \
    --metadata=startup-script='#!/bin/bash
      apt-get update
      apt-get install apache2 -y
      service apache2 restart
      echo "
<h3>Web Server: web1
</h3>" | tee /var/www/html/index.html'

    gcloud compute instances create web2 \
    --zone="$ZONE" \
    --tags=network-lb-tag \
    --machine-type=e2-small \
    --image-family=debian-12 \
    --image-project=debian-cloud \
    --metadata=startup-script='#!/bin/bash
      apt-get update
      apt-get install apache2 -y
      service apache2 restart
      echo "
<h3>Web Server: web2
</h3>" | tee /var/www/html/index.html'

    gcloud compute instances create web3 \
    --zone="$ZONE" \
    --tags=network-lb-tag \
    --machine-type=e2-small \
    --image-family=debian-12 \
    --image-project=debian-cloud \
    --metadata=startup-script='#!/bin/bash
      apt-get update
      apt-get install apache2 -y
      service apache2 restart
      echo "
<h3>Web Server: web3
</h3>" | tee /var/www/html/index.html'

gcloud compute firewall-rules create www-firewall-network-lb \
    --target-tags network-lb-tag --allow tcp:80
```

## Configure the load balancing service

```bash
gcloud compute http-health-checks create basic-check

gcloud compute addresses create network-lb-ip-1 \
  --region "$REGION"

gcloud compute target-pools create www-pool \
  --region "$REGION" --http-health-check basic-check

# add instances into pool
gcloud compute target-pools add-instances www-pool \
    --instances web1,web2,web3

# add forwarding rule
gcloud compute forwarding-rules create www-rule \
    --region  "$REGION" \
    --ports 80 \
    --address network-lb-ip-1 \
    --target-pool www-pool

# check forwarding rule's IP
gcloud compute forwarding-rules describe www-rule --region "$REGION"
```

## Create an HTTP load balancer

```bash
gcloud compute instance-templates create lb-backend-template \
   --region=$REGION \
   --network=default \
   --subnet=default \
   --tags=allow-health-check \
   --machine-type=e2-medium \
   --image-family=debian-12 \
   --image-project=debian-cloud \
   --metadata=startup-script='#!/bin/bash
     apt-get update
     apt-get install apache2 -y
     a2ensite default-ssl
     a2enmod ssl
     vm_hostname="$(curl -H "Metadata-Flavor:Google" \
     http://169.254.169.254/computeMetadata/v1/instance/name)"
     echo "Page served from: $vm_hostname" | \
     tee /var/www/html/index.html
     systemctl restart apache2'

# create MIG(managed instance group)
gcloud compute instance-groups managed create lb-backend-group \
   --template=lb-backend-template --size=2 --zone=$ZONE

# let google cloud frontend healthy check pass
gcloud compute firewall-rules create fw-allow-health-check \
  --network=default \
  --action=allow \
  --direction=ingress \
  --source-ranges=130.211.0.0/22,35.191.0.0/16 \
  --target-tags=allow-health-check \
  --rules=tcp:80

# setup external ip for ALB
gcloud compute addresses create lb-ipv4-1 \
  --ip-version=IPV4 \
  --global

# check lb ip
gcloud compute addresses describe lb-ipv4-1 \
  --format="get(address)" \
  --global

# create healthy check for loadbalancer
gcloud compute health-checks create http http-basic-check \
  --port 80

# create backend service
gcloud compute backend-services create web-backend-service \
  --protocol=HTTP \
  --port-name=http \
  --health-checks=http-basic-check \
  --global

# attach instance group to this backend service
gcloud compute backend-services add-backend web-backend-service \
  --instance-group=lb-backend-group \
  --instance-group-zone=$ZONE \
  --global

# create URL map to route incoming request
gcloud compute url-maps create web-map-http \
    --default-service web-backend-service

gcloud compute target-http-proxies create http-lb-proxy \
    --url-map web-map-http

# add global forwarding rule to route incoming request to the proxy
gcloud compute forwarding-rules create http-content-rule \
   --address=lb-ipv4-1\
   --global \
   --target-http-proxy=http-lb-proxy \
   --ports=80
```
