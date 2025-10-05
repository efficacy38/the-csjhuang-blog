---
title: gcloud-009-cloud-setup-dev-environment-cloud-iam
description: gcloud-009-cloud-setup-dev-environment-cloud-iam
slug: gcloud-009-cloud-setup-dev-environment-cloud-iam
pubDate: 2025-10-05
tags:
  - "note"
  - "unclassified"
---

## Setup Environment

```bash
gcloud auth login
gcloud config set project qwiklabs-gcp-04-dfae8402217a
export BUCKET_NAME="hello-qwiklabs-gcp-04-dfae8402217a"

# valiadtion
gcloud auth list
gcloud config list project
```

## Prepare a Cloud Storage bucket for access testing

```bash
# create US multi-region bucket
gsutil mb -l US gs://$BUCKET_NAME
gsutil cp sample.txt gs://$BUCKET_NAME/
```

### Remove permission

1. Select Navigation menu > IAM & Admin > IAM. Then click the pencil icon inline and to the right of Username 2.
2. Remove Project Viewer access for Username 2 by clicking the trashcan icon next to the role name. Then click SAVE.

> Note: It can take up to 80 seconds for such a change to take effect as it propagates. Read more about Google Cloud IAM in the Google Cloud IAMResource Documentation, [Frequently asked questions](https://cloud.google.com/iam/docs/faq).

### Add permission

- Copy Username 2 name from the Lab Connection panel.
- Switch to Username 1 console. Ensure that you are still signed in with Username 1's credentials. If you are signed out, sign in back with the proper credentials.
- In the Console, select Navigation menu > IAM & Admin > IAM.
- Click +GRANT ACCESS button and paste the Username 2 name into the New principals field.
- In the Select a role field, select Cloud Storage > Storage Object Viewer from the drop-down menu.
