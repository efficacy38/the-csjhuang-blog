---
title: Google Cloud：使用 Compute Engine 架設 Web 應用
description: 透過 Compute Engine 部署 Web 應用程式，涵蓋 Instance Template、MIG 與 Load Balancer
slug: gcloud-002-cloud-compute-host-web-app
pubDate: 2025-10-05
tags:
  - "gcloud"
  - "google cloud AI study jam 2025"
  - "The Basics of Google Cloud Compute"
---

## What you'll learn

In this lab, you learn how to perform the following tasks:

- Create [Compute Engine instances](https://cloud.google.com/compute/docs/instances/)
- Create [instance templates](https://cloud.google.com/compute/docs/instance-templates/) from source instances
- Create [managed instance groups](https://cloud.google.com/compute/docs/instance-groups/)
- Create and test [managed instance group health checks](https://cloud.google.com/compute/docs/instance-groups/autohealing-instances-in-migs)
- Create HTTP(S) [Load Balancers](https://cloud.google.com/load-balancing/)
- Create [load balancer health checks](https://cloud.google.com/load-balancing/docs/health-checks)
- Use a [Content Delivery Network (CDN)](https://cloud.google.com/cdn/) for caching

## Tasks

### Task 1. Enable the compute engine API

```bash
gcloud services enable compute.googleapis.com
```

### Task 2. Create a Cloud Storage bucket

```bash
gsutil mb gs://fancy-store-qwiklabs-gcp-01-3ec5456dfa67
```

### deploy with startup shell

```bash
# create gcloud instance with cloud-init startup script
gcloud compute instances create backend \
    --zone=us-east4-c \
    --machine-type=e2-standard-2 \
    --tags=backend \
   --metadata=startup-script-url=https://storage.googleapis.com/fancy-store-qwiklabs-gcp-01-3ec5456dfa67/startup-script.sh

gcloud compute instances create frontend \
    --zone=us-east4-c \
    --machine-type=e2-standard-2 \
    --tags=frontend \
    --metadata=startup-script-url=https://storage.googleapis.com/fancy-store-qwiklabs-gcp-01-3ec5456dfa67/startup-script.sh

# check machine status
gcloud compute instances list
```

### create firewall rules

```bash
gcloud compute firewall-rules create fw-fe \
    --allow tcp:8080 \
    --target-tags=frontend

gcloud compute firewall-rules create fw-be \
    --allow tcp:8081-8082 \
    --target-tags=backend
```

## Scale up(create managed instance group)

To allow the application to scale, managed instance groups are created and use the frontend and backend instances as Instance Templates.

A managed instance group (MIG) contains identical instances that you can manage as a single entity in a single zone. Managed instance groups maintain high availability of your apps by proactively keeping your instances available, that is, in the RUNNING state. You intend using managed instance groups for your frontend and backend instances to provide autohealing, load balancing, autoscaling, and rolling updates.

### Create an instance template from a source instance

Before you can create a managed instance group, you have to first create an instance template to be the foundation for the group. Instance templates allow you to define the machine type, boot disk image or container image, network, and other instance properties to use when creating new VM instances. You can use instance templates to create instances in a managed instance group or even to create individual instances.

```bash
# first stop all instance
gcloud compute instances stop frontend --zone=us-east4-c
gcloud compute instances stop backend --zone=us-east4-c

# create instance group template from previous instance
gcloud compute instance-templates create fancy-fe \
    --source-instance-zone=us-east4-c \
    --source-instance=frontend

gcloud compute instance-templates create fancy-be \
    --source-instance-zone=us-east4-c \
    --source-instance=backend

# check current instance template
gcloud compute instance-templates list

# remove template vm
gcloud compute instances delete backend --zone=us-east4-c
```

### Create managed instance groups

```bash
# create both managed instance group for scaling
gcloud compute instance-groups managed create fancy-fe-mig \
    --zone=us-east4-c \
    --base-instance-name fancy-fe \
    --size 2 \
    --template fancy-fe

gcloud compute instance-groups managed create fancy-be-mig \
    --zone=us-east4-c \
    --base-instance-name fancy-be \
    --size 2 \
    --template fancy-be
```

instance group use

- the instance template and configure for 2 instance each within each group to start
- instance are automatically named base on `base-instance-name`

```bash
# add named port
#   - because 8080, 8081 is not standard port
#   - named port can assign to "instance-group" indicate port is all "available" accross the group
gcloud compute instance-groups set-named-ports fancy-fe-mig \
    --zone=us-east4-c \
    --named-ports frontend:8080

gcloud compute instance-groups set-named-ports fancy-be-mig \
    --zone=us-east4-c \
    --named-ports orders:8081,products:8082
```

### Configure autohealing

An autohealing policy relies on an application-based health check to verify that an app is responding as expected.
Checking that an app responds is more precise than simply verifying that an instance is in a "RUNNING" state, which is the default behavior.

```bash
# different between autohealing and load-balancing healthy check
# FIXME: use callout instead
Note: Separate health checks are used for load balancing and for autohealing. Health checks for load balancing can and should be more aggressive because these health checks determine whether an instance receives user traffic. You want to catch non-responsive instances quickly so you can redirect traffic if necessary. In contrast, health checking for autohealing causes Compute Engine to proactively replace failing instances, so this health check should be more conservative than a load balancing health check.
```

```
gcloud compute health-checks create http fancy-fe-hc \
    --port 8080 \
    --check-interval 30s \
    --healthy-threshold 1 \
    --timeout 10s \
    --unhealthy-threshold 3

gcloud compute health-checks create http fancy-be-hc \
    --port 8081 \
    --request-path=/api/orders \
    --check-interval 30s \
    --healthy-threshold 1 \
    --timeout 10s \
    --unhealthy-threshold 3

# add firewall
gcloud compute firewall-rules create allow-health-check \
    --allow tcp:8080-8081 \
    --source-ranges 130.211.0.0/22,35.191.0.0/16 \
    --network default

# attach health check to mig
gcloud compute instance-groups managed update fancy-fe-mig \
    --zone=us-east4-c \
    --health-check fancy-fe-hc \
    --initial-delay 300

gcloud compute instance-groups managed update fancy-be-mig \
    --zone=us-east4-c \
    --health-check fancy-be-hc \
    --initial-delay 300
```

## Create loadbalancer

```bash
# create healthy check
gcloud compute http-health-checks create fancy-fe-frontend-hc \
  --request-path / \
  --port 8080

gcloud compute http-health-checks create fancy-be-orders-hc \
  --request-path /api/orders \
  --port 8081

gcloud compute http-health-checks create fancy-be-products-hc \
  --request-path /api/products \
  --port 8082

# create backend-service(would connect to loadbalancer)
gcloud compute backend-services create fancy-fe-frontend \
  --http-health-checks fancy-fe-frontend-hc \
  --port-name frontend \
  --global

gcloud compute backend-services create fancy-be-orders \
  --http-health-checks fancy-be-orders-hc \
  --port-name orders \
  --global

gcloud compute backend-services create fancy-be-products \
  --http-health-checks fancy-be-products-hc \
  --port-name products \
  --global

# attach previous backend service to loadbalancer's backend services
gcloud compute backend-services add-backend fancy-fe-frontend \
  --instance-group-zone=us-east4-c \
  --instance-group fancy-fe-mig \
  --global

gcloud compute backend-services add-backend fancy-be-orders \
  --instance-group-zone=us-east4-c \
  --instance-group fancy-be-mig \
  --global

gcloud compute backend-services add-backend fancy-be-products \
  --instance-group-zone=us-east4-c \
  --instance-group fancy-be-mig \
  --global

# Run the following command to create a URL map that defines which URLs are directed to which backend services:
gcloud compute url-maps create fancy-map \
  --default-service fancy-fe-frontend

gcloud compute url-maps add-path-matcher fancy-map \
   --default-service fancy-fe-frontend \
   --path-matcher-name orders \
   --path-rules "/api/orders=fancy-be-orders,/api/products=fancy-be-products"

gcloud compute target-http-proxies create fancy-proxy \
  --url-map fancy-map

# open loadbalancer's fw rule
gcloud compute forwarding-rules create fancy-http-rule \
  --global \
  --target-http-proxy fancy-proxy \
  --ports 80

# check current loadbalancer's IP
gcloud compute forwarding-rules list --global
```

### Update the frontend instance group

```bash
gcloud compute instance-groups managed rolling-action replace fancy-fe-mig \
    --zone=us-east4-c \
    --max-unavailable 100%
```

## Scale Compute Engine

### Automatically resize by utilization

These commands create an autoscaler on the managed instance groups that automatically adds instances when utilization is above 60% utilization, and removes instances when the load balancer is below 60% utilization.

```bash
gcloud compute instance-groups managed set-autoscaling \
  fancy-fe-mig \
  --zone=us-east4-c \
  --max-num-replicas 2 \
  --target-load-balancing-utilization 0.60

gcloud compute instance-groups managed set-autoscaling \
  fancy-be-mig \
  --zone=us-east4-c \
  --max-num-replicas 2 \
  --target-load-balancing-utilization 0.60
```

## Enable the content delivery network

When a user requests content from the HTTP(S) load balancer, the request arrives at a Google Front End (GFE), which first looks in the Cloud CDN cache for a response to the user's request. If the GFE finds a cached response, the GFE sends the cached response to the user. This is called a cache hit.

If the GFE can't find a cached response for the request, the GFE makes a request directly to the backend. If the response to this request is cacheable, the GFE stores the response in the Cloud CDN cache so that the cache can be used for subsequent requests.

```bash
gcloud compute backend-services update fancy-fe-frontend \
    --enable-cdn --global
```

## Update the instance template

- instance template are not editable

```bash
# edit our template machine
gcloud compute instances set-machine-type frontend \
  --zone=us-east4-c \
  --machine-type e2-small

# create new instance template
gcloud compute instance-templates create fancy-fe-new \
    --region=$REGION \
    --source-instance=frontend \
    --source-instance-zone=us-east4-c

# chagne mig's instance template to `fancy-fe-new`
gcloud compute instance-groups managed rolling-action start-update fancy-fe-mig \
  --zone=us-east4-c \
  --version template=fancy-fe-new

# check service is available
watch -n 2 gcloud compute instance-groups managed list-instances fancy-fe-mig \
  --zone=us-east4-c
```
