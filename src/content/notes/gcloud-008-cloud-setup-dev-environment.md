---
title: Google Cloud：設置開發環境與 Cloud Storage
description: 學習如何配置 Google Cloud 開發環境並使用 Cloud Storage 儲存服務
pubDate: 2025-10-05
slug: gcloud-008-cloud-setup-dev-environment-cloud-storage
tags:
  - "gcloud"
---

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

### What we would do

- Create a storage bucket
- Upload objects to the bucket
- Create folders and subfolders in the bucket
- Make objects in a storage bucket publicly accessible

### Naming ruels

- Do not include sensitive information in the bucket name, because the bucket namespace is global and publicly visible.
- Bucket names must contain only lowercase letters, numbers, dashes (-), underscores (\_), and dots (.). Names containing dots require verification.
- Bucket names must start and end with a number or letter.
- Bucket names must contain 3 to 63 characters. Names containing dots can contain up to 222 characters, but each dot-separated component can be no longer than 63 characters.
- Bucket names cannot be represented as an IP address in dotted-decimal notation (for example, 192.168.5.4).
- Bucket names cannot begin with the "goog" prefix.
- Bucket names cannot contain "google" or close misspellings of "google".
- Also, for DNS compliance and future compatibility, you should not use underscores (\_) or have a period adjacent to another period or dash. For example, ".." or "-." or ".-" are not valid in DNS names.

```bash
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

## Cloud Monitoring: Qwik Start

### Setup

```bash
gcloud auth login
gcloud config set project qwiklabs-gcp-02-74ffc5488ff1

gcloud config set compute/zone "europe-west1-c"
export ZONE=$(gcloud config get compute/zone)

gcloud config set compute/region "europe-west1"
export REGION=$(gcloud config get compute/region)
```

### Create compute engines

```bash
gcloud compute instances create lamp-1-vm \
--zone="$ZONE" \
--tags=network-lb-tag \
--machine-type=e2-medium \
--image-family=debian-12 \
--image-project=debian-cloud \
--metadata=startup-script='#!/bin/bash
  apt-get update
  apt-get install apache2 -y
  service apache2 restart
'

gcloud compute firewall-rules create www-firewall-network-lb \
    --target-tags network-lb-tag --allow tcp:80
```

TBD...

## Cloud Run Functions: Qwik Start - Command Line

### What we'll do

- Create a Cloud Run function
- Deploy and test the Cloud Run function
- View logs

### Task 1: Create a function

```bash
gcloud config set run/region europe-west1
mkdir gcf_hello_world && cd $_
```

create cloud function application, `index.js`

```js
const functions = require("@google-cloud/functions-framework");

// Register a CloudEvent callback with the Functions Framework that will
// be executed when the Pub/Sub trigger topic receives a message.
functions.cloudEvent("helloPubSub", (cloudEvent) => {
  // The Pub/Sub message is passed as the CloudEvent's data payload.
  const base64name = cloudEvent.data.message.data;

  const name = base64name
    ? Buffer.from(base64name, "base64").toString()
    : "World";

  console.log(`Hello, ${name}!`);
});
```

package.json

```json
{
  "name": "gcf_hello_world",
  "version": "1.0.0",
  "main": "index.js",
  "scripts": {
    "start": "node index.js",
    "test": "echo \"Error: no test specified\" && exit 1"
  },
  "dependencies": {
    "@google-cloud/functions-framework": "^3.0.0"
  }
}
```

### Deploy our function

- For this lab, you'll set the --trigger-topic as cf_demo.
- cloud run functions are event driven, there are multiple trigger event
  - `--trigger-topic`, `--trigger-bucket`, `--trigger-http`
  - when deploy updated, the function keeps the existing trigger unless otherwise specified

```bash
# deploy this cloud run function
## Note:
## If you get a service account serviceAccountTokenCreator notification select "n".
gcloud functions deploy nodejs-pubsub-function \
  --gen2 \
  --runtime=nodejs20 \
  --region=europe-west1 \
  --source=. \
  --entry-point=helloPubSub \
  --trigger-topic cf-demo \
  --stage-bucket qwiklabs-gcp-01-4b6dfba2e1fd-bucket \
  --service-account cloudfunctionsa@qwiklabs-gcp-01-4b6dfba2e1fd.iam.gserviceaccount.com \
  --allow-unauthenticated

# check this cloud run function
## An ACTIVE status indicates that the function has been deployed.
gcloud functions describe nodejs-pubsub-function \
  --region=europe-west1
```

```bash
# test this function
gcloud pubsub topics publish cf-demo --message="Cloud Function Gen2"

# view the log
gcloud functions logs read nodejs-pubsub-function \
  --region=europe-west1
```

## Pub / Sub: Qwik Start - Command Line

### What you'll learn

In this lab, you will do the following:

- Create, delete, and list Pub/Sub topics and subscriptions
- Publish messages to a topic
- How to use a pull subscriber

### Pub/Sub basics

As stated earlier, Pub/Sub is an asynchronous global messaging service.
There are three terms in Pub/Sub that appear often: topics, publishing, and subscribing.

- A topic is a shared string that allows applications to connect with one another through a common thread.
- Publishers push (or publish) a message to a Cloud Pub/Sub topic.
- Subscribers make a "subscription" to a topic where they will either pull messages from the subscription or configure webhooks for push subscriptions. Every subscriber must acknowledge each message within a configurable window of time.

```bash
# create topics
gcloud pubsub topics create myTopic
gcloud pubsub topics create Test1
gcloud pubsub topics create Test2

# check current topics
gcloud pubsub topics list

# remove topics
gcloud pubsub topics delete Test1
gcloud pubsub topics delete Test2
```

### Pub/Sub subscriptions

```bash
# create subscription
gcloud  pubsub subscriptions create --topic myTopic mySubscription

# check current subscription
gcloud pubsub topics list-subscriptions myTopic
```

### Pub/Sub publishing and pulling a single message

```bash
# publish a message
gcloud pubsub topics publish myTopic --message "Hello"
gcloud pubsub topics publish myTopic --message "Publisher's name is <YOUR NAME>"

# pull the topics
gcloud pubsub subscriptions pull mySubscription --auto-ack
```

- Using the pull command without any flags will output only one message, even if you are subscribed to a topic that has more held in it.
- Once an individual message has been outputted from a particular subscription-based pull command, you cannot access that message again with the pull command.

also pull can use `--limit=3` to gather more message

```bash
gcloud pubsub topics publish myTopic --message "Hello"
gcloud pubsub topics publish myTopic --message "Publisher's name is test1"
gcloud pubsub topics publish myTopic --message "Publisher's name is test2"
gcloud pubsub topics publish myTopic --message "Publisher's name is test3"
gcloud pubsub topics publish myTopic --message "Publisher's name is test4"
gcloud pubsub subscriptions pull mySubscription --limit=3
```

## Challenge lab

```bash
export BUCKET_NAME="qwiklabs-gcp-02-b53b6a375416-bucket"
export REGION="europe-west1"
export ZONE="europe-west1-d"
gsutil mb -l $REGION gs://$BUCKET_NAME

# create topics
gcloud pubsub topics create topic-memories-993
```

### Create cloud run function

package.json

```json
{
  "name": "gcf_hello_world",
  "version": "1.0.0",
  "main": "index.js",
  "scripts": {
    "start": "node index.js",
    "test": "echo \"Error: no test specified\" && exit 1"
  },
  "dependencies": {
    "@google-cloud/functions-framework": "^3.0.0"
  }
}
```

index.js

```js
const functions = require("@google-cloud/functions-framework");
const { Storage } = require("@google-cloud/storage");
const { PubSub } = require("@google-cloud/pubsub");
const sharp = require("sharp");

functions.cloudEvent("memories-thumbnail-creator", async (cloudEvent) => {
  const event = cloudEvent.data;

  console.log(`Event: ${JSON.stringify(event)}`);
  console.log(`Hello ${event.bucket}`);

  const fileName = event.name;
  const bucketName = event.bucket;
  const size = "64x64";
  const bucket = new Storage().bucket(bucketName);
  const topicName = "topic-memories-108";
  const pubsub = new PubSub();

  if (fileName.search("64x64_thumbnail") === -1) {
    // doesn't have a thumbnail, get the filename extension
    const filename_split = fileName.split(".");
    const filename_ext =
      filename_split[filename_split.length - 1].toLowerCase();
    const filename_without_ext = fileName.substring(
      0,
      fileName.length - filename_ext.length - 1,
    ); // fix sub string to remove the dot

    if (
      filename_ext === "png" ||
      filename_ext === "jpg" ||
      filename_ext === "jpeg"
    ) {
      // only support png and jpg at this point
      console.log(`Processing Original: gs://${bucketName}/${fileName}`);
      const gcsObject = bucket.file(fileName);
      const newFilename = `${filename_without_ext}_64x64_thumbnail.${filename_ext}`;
      const gcsNewObject = bucket.file(newFilename);

      try {
        const [buffer] = await gcsObject.download();
        const resizedBuffer = await sharp(buffer)
          .resize(64, 64, {
            fit: "inside",
            withoutEnlargement: true,
          })
          .toFormat(filename_ext)
          .toBuffer();

        await gcsNewObject.save(resizedBuffer, {
          metadata: {
            contentType: `image/${filename_ext}`,
          },
        });

        console.log(`Success: ${fileName} → ${newFilename}`);

        await pubsub
          .topic(topicName)
          .publishMessage({ data: Buffer.from(newFilename) });

        console.log(`Message published to ${topicName}`);
      } catch (err) {
        console.error(`Error: ${err}`);
      }
    } else {
      console.log(
        `gs://${bucketName}/${fileName} is not an image I can handle`,
      );
    }
  } else {
    console.log(`gs://${bucketName}/${fileName} already has a thumbnail`);
  }
});
```

```bash
# create cloud run
gcloud functions deploy memories-thumbnail-creator \
  --gen2 \
  --runtime=nodejs22 \
  --region=$REGION \
  --source=. \
  --entry-point=memories-thumbnail-creator \
  --trigger-bucket qwiklabs-gcp-04-29709b01c385-bucket \
  --allow-unauthenticated
```
