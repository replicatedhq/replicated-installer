#!/bin/python
import json
import os

import boto
from boto.sqs.message import RawMessage


def add_message_to_queue(project, sha):
    # Data required by the API
    data = {"project": project, "sha": sha}

    # Connect to SQS and open the queue
    sqs = boto.connect_sqs(os.environ["AWS_ACCESS_KEY"],
                           os.environ["AWS_SECRET_KEY"])
    q = sqs.create_queue("chatops-deployer-staging")

    # Put the message in the queue
    m = RawMessage()
    m.set_body(json.dumps(data))
    q.write(m)


addMessageToQueue("install-scripts",
                  os.environ["CIRCLE_SHA1"][:7])
