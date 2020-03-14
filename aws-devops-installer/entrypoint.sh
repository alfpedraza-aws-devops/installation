#!/bin/bash

# Executes the specified $ACTION.sh (either install or uninstall).
./$ACTION.sh \
    $ACCOUNT_ID \
    $REGION_NAME \
    $PROJECT_NAME \
    $JENKINS_ADMIN_PASSWORD \
    $AWS_ACCESS_KEY_ID \
    $AWS_SECRET_ACCESS_KEY