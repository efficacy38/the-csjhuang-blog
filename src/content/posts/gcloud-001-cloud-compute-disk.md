---
title: Create a Persistent Disk
description: "The Basics of Google Cloud Compute(Create a Persistent Disk )"
pubDate: 2025-10-05
slug: gcloud-001-cloud-compute-disk
tags:
  - "note"
  - "gcloud"
  - "google cloud AI study jam 2025"
  - "The Basics of Google Cloud Compute"
---

## login

```bash
# login with browser
gcloud auth login

# select the project
gcloud config set project <YOUR-PROJECT>

# check account is enabled
gcloud auth list

# check current project is correct
gcloud config list project
```

## Setup zone and region

```bash
gcloud config set compute/zone europe-west1-b
gcloud config set compute/region europe-west1
```

## Play with cloud shell

```bash
# set the variables for next use
export REGION=europe-west1
export ZONE=europe-west1-b


# create a instance
gcloud compute instances create gcelab --zone $ZONE --machine-type e2-standard-2

# create a persistent disk
gcloud compute disks create mydisk --size=200GB --zone $ZONE

# attach this disk
gcloud compute instances attach-disk gcelab --disk mydisk --zone $ZONE
```

### access this machine

```bash
gcloud compute ssh gcelab --zone $ZONE
```

### check disk is attached

```bash
ls -l /dev/disk/by-id/
lrwxrwxrwx 1 root root  9 Feb 27 02:24 google-persistent-disk-0 -> ../../sda
lrwxrwxrwx 1 root root 10 Feb 27 02:24 google-persistent-disk-0-part1 -> ../../sda1
lrwxrwxrwx 1 root root  9 Feb 27 02:25 google-persistent-disk-1 -> ../../sdb
lrwxrwxrwx 1 root root  9 Feb 27 02:24 scsi-0Google_PersistentDisk_persistent-disk-0 -> ../../sda
lrwxrwxrwx 1 root root 10 Feb 27 02:24 scsi-0Google_PersistentDisk_persistent-disk-0-part1 -> ../../sda1
lrwxrwxrwx 1 root root  9 Feb 27 02:25 scsi-0Google_PersistentDisk_persistent-disk-1 -> ../../sdb
```

```bash
# fixme: use callout insteaded
# if you want different device name rather than `google-persistent-disk-1`, use following command
gcloud compute instances attach-disk gcelab --disk mydisk --device-name <YOUR_DEVICE_NAME> --zone $ZONE
```

```bash
# format this disk
sudo mkfs.ext4 -F -E lazy_itable_init=0,lazy_journal_init=0,discard /dev/disk/by-id/scsi-0Google_PersistentDisk_persistent-disk-1

# mount this disk
sudo mount -o discard,defaults /dev/disk/by-id/scsi-0Google_PersistentDisk_persistent-disk-1 /mnt/mydisk
```

## Some quizs

1. For migrating data from a persistent disk to another region, reorder the
   following steps in which they should be performed:
   1. Unmount file system(s)
   2. Create snapshot
   3. Create disk
   4. Create instance
   5. Attach disk

## Other disk type(local ssd)

Compute Engine can also attach local SSDs. Local SSDs are physically attached to
the server hosting the virtual machine instance to which they are mounted.
This tight coupling offers superior performance, with very high input/output
operations per second (IOPS) and very low latency compared to persistent disks.
Local SSD performance offers:

- Less than 1 ms of latency
- Up to 680,000 read IOPs and 360,000 write IOPs

These performance gains require certain trade-offs in availability, durability,
and flexibility. Because of these trade-offs, local SSD storage is not automatically
replicated and all data can be lost in the event of a host error or a user
configuration error that makes the disk unreachable.
Users must take extra precautions to backup their data.

This lab does not cover local SSDs.

To maximize the local SSD performance, you'll need to use a special Linux image
that supports NVMe. You can learn more about local SSDs in the
[Local SSD documentation](https://cloud.google.com/compute/docs/disks/local-ssd#create_a_local_ssd).
