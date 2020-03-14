#!/bin/bash
cd ../aws-devops-installer/
docker build -t aws-devops-installer .
docker run --rm \
    --name aws-devops-installer \
    --env ACTION=install \
    --env ACCOUNT_ID=${ Your AWS Account Id (e.g. 123456789012) } \
    --env REGION_NAME=${ The region were the project will be installed (e.g. us-east-2) } \
    --env PROJECT_NAME=${ The name of your new project (e.g. my-new-project) } \
    --env JENKINS_ADMIN_PASSWORD=${ The password for the new Jenkins admin user (e.g. password) } \
    --env AWS_ACCESS_KEY_ID=${ Your AWS Access Key Id (e.g. ABCDEFGHIJKLMNOPQRST) } \
    --env AWS_SECRET_ACCESS_KEY=${ Your AWS Secret Access Key (e.g. abcDEFghiJKLmnoPQRstuVWXyzaBCDefgHIJklmN) } \
    aws-devops-installer