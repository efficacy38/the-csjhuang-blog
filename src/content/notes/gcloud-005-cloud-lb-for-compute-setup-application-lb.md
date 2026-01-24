---
title: Google Cloud：設置應用程式負載平衡器
description: 學習如何為 Compute Engine 配置 HTTP(S) 應用程式負載平衡器
slug: gcloud-005-cloud-lb-for-compute-setup-application-lb
pubDate: 2025-10-05
tags:
  - "gcloud"
  - "google cloud AI study jam 2025"
  - "Implementing Cloud Load Balancing for Compute Engine"
---

- [Application Load Balancer](https://cloud.google.com/compute/docs/load-balancing/http/)

## Objectives

In this lab, you learn how to perform the following tasks:

- Configure the default region and zone for your resources.
- Create an Application Load Balancer.
- Test the traffic to your insances.

## Setup Environment

```bash
gcloud auth login
gcloud config set compute/region us-east1
gcloud config set compute/zone us-east1-b
gcloud config set project qwiklabs-gcp-03-f2bce04b6183

# valiadtion
gcloud auth list
gcloud config list project
```

## Setup Environment

```bash
gcloud compute instances create www1 \
    --zone=us-east1-b \
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
    --zone=us-east1-b \
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

gcloud compute instances create www2 \
    --zone=us-east1-b \
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

# fw rule
gcloud compute firewall-rules create www-firewall-network-lb \
    --target-tags network-lb-tag --allow tcp:80
```

## Create ALB

Application Load Balancing is implemented on "Google Front End (GFE)"

- GFEs are distributed globally and operate together using:
  - Google's global network
  - control plane
- Requests are always routed to the "instance group" that is closest to the user
  - If the closest group does not have enough capacity, the request is sent to the closest group that does have capacity.

To set up a load balancer with a Compute Engine backend, your VMs need to be in an instance group.

The managed instance group provides VMs running the backend servers of an external application load balancer. For this lab, backends serve their own hostnames.

```bash
# create loadbalancer template
gcloud compute instance-templates create lb-backend-template \
   --region=us-east1 \
   --network=default \
   --subnet=default \
   --tags=allow-health-check \
   --machine-type=e2-medium \
   --image-family=debian-11 \
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
   --template=lb-backend-template --size=2 --zone=us-east1-b

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
  --instance-group-zone=us-east1-b \
  --global

# create URL map to route incoming request
gcloud compute url-maps create web-map-http \
    --default-service web-backend-service
```

### create target HTTP proxy to route request to URL map

```bash
gcloud compute target-http-proxies create http-lb-proxy \
    --url-map web-map-http

# add global forwarding rule to route incoming request to the proxy
gcloud compute forwarding-rules create http-content-rule \
   --address=lb-ipv4-1\
   --global \
   --target-http-proxy=http-lb-proxy \
   --ports=80
```

Note: A [forwarding rule](https://cloud.google.com/load-balancing/docs/using-forwarding-rules) and its corresponding IP address represent the frontend configuration of a Google Cloud load balancer. Learn more about the general understanding of forwarding rules from the [Forwarding rules overview](https://cloud.google.com/load-balancing/docs/forwarding-rule-concepts) guide.

```bash
# check instance-group is all ready
gcloud compute instance-groups managed list-instances lb-backend-group
```

## other reference

- [Set up a classic Application Load Balancer with a managed instance group backend](https://cloud.google.com/load-balancing/docs/https/ext-https-lb-simple)
- [External Application Load Balancer overview](https://cloud.google.com/load-balancing/docs/https)

Google Cloud provides health checking mechanisms that determine whether backend instances respond properly to traffic.

[Createing healthy checks](https://cloud.google.com/load-balancing/docs/health-checks)
