---
title: Google Cloud：設置內部應用程式負載平衡器
description: 學習如何配置 Google Cloud 內部應用程式負載平衡器
pubDate: 2025-10-05
slug: gcloud-006-cloud-lb-for-compute-setup-internal-application-lb
tags:
  - "gcloud"
---

## Setup Environment

```bash
gcloud auth login
gcloud config set project qwiklabs-gcp-03-5111c4317b98
gcloud config set compute/region us-central1
gcloud config set compute/zone us-central1-b

# valiadtion
gcloud auth list
gcloud config list project
```

## Create backend service

1. create backend file `backend.sh`

```
sudo chmod -R 777 /usr/local/sbin/
sudo cat << EOF > /usr/local/sbin/serveprimes.py
import http.server

def is_prime(a): return a!=1 and all(a % i for i in range(2,int(a**0.5)+1))

class myHandler(http.server.BaseHTTPRequestHandler):
  def do_GET(s):
    s.send_response(200)
    s.send_header("Content-type", "text/plain")
    s.end_headers()
    s.wfile.write(bytes(str(is_prime(int(s.path[1:]))).encode('utf-8')))

http.server.HTTPServer(("",80),myHandler).serve_forever()
EOF
nohup python3 /usr/local/sbin/serveprimes.py >/dev/null 2>&1 &
```

```bash
# create backend instance-template
gcloud compute instance-templates create primecalc \
--metadata-from-file startup-script=backend.sh \
--no-address --tags backend --machine-type=e2-medium

# open firewall
# FIXME: why this is 10.128.0.0/20, does it mean it is internal address?
gcloud compute firewall-rules create http --network default --allow=tcp:80 \
--source-ranges 10.128.0.0/20 --target-tags backend

# create mig(instance group)
gcloud compute instance-groups managed create backend \
--size 3 \
--template primecalc \
--zone us-central1-b

# check current instance status
gcloud compute instances list
gcloud compute instance-groups managed list-instances backend
```

## Setup internal loadbalancer

- create private internal VIP for insternal loadbalancer
- internal loadbalancer consists 3 main parts:
  - forwarding rule
    - forward traffic from VIP to our backend service
  - backend service
    - how loadbalancer distribute traffic to VM instance, also include the healthy check
  - health check
    - always send traffic to vm that pass health checks

```bash
# create a health check, request-path /2 is append path with `/2`
gcloud compute health-checks create http ilb-health --request-path /2

# create backend service
gcloud compute backend-services create prime-service \
--load-balancing-scheme internal --region=us-central1 \
--protocol tcp --health-checks ilb-health

# add instance group to backend service
gcloud compute backend-services add-backend prime-service \
--instance-group backend --instance-group-zone=us-central1-b \
--region=us-central1

# create firewall rule with internal static IP `10.128.0.10`
gcloud compute forwarding-rules create prime-lb \
--load-balancing-scheme internal \
--ports 80 --network default \
--region=us-central1 --address 10.128.0.10 \
--backend-service prime-service
```

## Test the loadbalancer

- create a new vm to check internal loadbalancer is ok
  - only connected to our vpc
  - can't access via cloud shell

```bash
# create instance
gcloud compute instances create testinstance \
--machine-type=e2-standard-2 --zone us-central1-b

# ssh into this machine
gcloud compute ssh testinstance --zone us-central1-b

# delete this instance
gcloud compute instances delete testinstance --zone=us-central1-b
```

## Create public-facing web service

1. create `~/frontend.sh`

```bash
sudo chmod -R 777 /usr/local/sbin/
sudo cat << EOF > /usr/local/sbin/getprimes.py
import urllib.request
from multiprocessing.dummy import Pool as ThreadPool
import http.server
PREFIX="http://10.128.0.10/" #HTTP Load Balancer
def get_url(number):
    return urllib.request.urlopen(PREFIX+str(number)).read().decode('utf-8')
class myHandler(http.server.BaseHTTPRequestHandler):
  def do_GET(s):
    s.send_response(200)
    s.send_header("Content-type", "text/html")
    s.end_headers()
    i = int(s.path[1:]) if (len(s.path)>1) else 1
    s.wfile.write("<html><body><table>".encode('utf-8'))
    pool = ThreadPool(10)
    results = pool.map(get_url,range(i,i+100))
    for x in range(0,100):
      if not (x % 10): s.wfile.write("<tr>".encode('utf-8'))
      if results[x]=="True":
        s.wfile.write("<td bgcolor='#00ff00'>".encode('utf-8'))
      else:
        s.wfile.write("<td bgcolor='#ff0000'>".encode('utf-8'))
      s.wfile.write(str(x+i).encode('utf-8')+"</td> ".encode('utf-8'))
      if not ((x+1) % 10): s.wfile.write("</tr>".encode('utf-8'))
    s.wfile.write("</table></body></html>".encode('utf-8'))
http.server.HTTPServer(("",80),myHandler).serve_forever()
EOF
nohup python3 /usr/local/sbin/getprimes.py >/dev/null 2>&1 &
```

```
# create frontend instances
gcloud compute instances create frontend --zone=us-central1-b \
--metadata-from-file startup-script=frontend.sh \
--tags frontend --machine-type=e2-standard-2

# firewall
gcloud compute firewall-rules create http2 --network default --allow=tcp:80 \
--source-ranges 0.0.0.0/0 --target-tags frontend

# check EXTERNAL_IP of frontend
gcloud compute instances list

# test frontend is working
curl <EXTERNAL_IP>
```
