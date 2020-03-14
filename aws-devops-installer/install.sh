#!/bin/bash
set -exuo pipefail
echo "Installation started at $(date)"

#-----------------------------------------------------------------------------#
# External parameters supplied by the command line.                           #
#-----------------------------------------------------------------------------#

ACCOUNT_ID=$1
REGION_NAME=$2
PROJECT_NAME=$3
JENKINS_ADMIN_PASSWORD=$4
export AWS_ACCESS_KEY_ID=$5
export AWS_SECRET_ACCESS_KEY=$6

#-----------------------------------------------------------------------------#
# Create the AWS S3 buckets to store the terraform state.                     #
#-----------------------------------------------------------------------------#

# Download the terraform configurations from the git repository.
mkdir /aws-devops
cd /aws-devops
git clone --depth 1 "https://github.com/alfpedraza-aws-devops/infrastructure.git"
PROJECT_PATH=/aws-devops/infrastructure

# Create the state bucket and table lock for the specified terraform configuration.
for configuration in vpc jenkins dev prod
do
    cd $PROJECT_PATH/state/$configuration/
    terraform init -input=false
    terraform apply -input=false -lock=true -auto-approve \
        -var "account_id=$ACCOUNT_ID" \
        -var "region_name=$REGION_NAME" \
        -var "project_name=$PROJECT_NAME"
done

#-----------------------------------------------------------------------------#
# Apply the VPC terraform configuration.                                      #
#-----------------------------------------------------------------------------#

cd $PROJECT_PATH/vpc/
terraform init -input=false \
    -backend-config="bucket=$ACCOUNT_ID-$PROJECT_NAME-vpc-terraform-state" \
    -backend-config="key=terraform.tfstate" \
    -backend-config="region=$REGION_NAME" \
    -backend-config="dynamodb_table=$ACCOUNT_ID-$PROJECT_NAME-vpc-terraform-lock" \
    -backend-config="encrypt=true"
terraform apply -input=false -lock=true -auto-approve \
    -var "account_id=$ACCOUNT_ID" \
    -var "region_name=$REGION_NAME" \
    -var "project_name=$PROJECT_NAME"

#-----------------------------------------------------------------------------#
# Create a temporal bucket to store secrets for the Jenkins server.           #
#-----------------------------------------------------------------------------#

BUCKET_NAME="$ACCOUNT_ID-$PROJECT_NAME-jenkins-secrets"
aws s3 rb s3://$BUCKET_NAME --force || true
aws s3api create-bucket \
    --bucket $BUCKET_NAME \
    --region $REGION_NAME \
    --create-bucket-configuration \
        LocationConstraint=$REGION_NAME;
aws s3api wait bucket-exists \
    --bucket $BUCKET_NAME \
    --region $REGION_NAME
aws s3api put-public-access-block \
    --bucket $BUCKET_NAME \
    --region $REGION_NAME \
    --public-access-block-configuration \
        "BlockPublicAcls=true,
        IgnorePublicAcls=true,
        BlockPublicPolicy=true,
        RestrictPublicBuckets=true"
aws s3api put-bucket-encryption \
    --bucket $BUCKET_NAME \
    --region $REGION_NAME \
    --server-side-encryption-configuration \
        '{"Rules":[{"ApplyServerSideEncryptionByDefault":
        {"SSEAlgorithm":"AES256"}}]}'

#-----------------------------------------------------------------------------#
# Upload the secrets to the temporal S3 bucket for the Jenkins server.        #
# Secrets are written to the /dev/shm folder which is a in-memory filesystem  #
# so they never are written to the hard-disk for more security.               #
#-----------------------------------------------------------------------------#

mkdir -p /dev/shm/aws-devops/credentials/
cd /dev/shm/aws-devops/credentials/
echo $JENKINS_ADMIN_PASSWORD > jenkins-admin-password
echo $AWS_ACCESS_KEY_ID      > aws-access-key-id
echo $AWS_SECRET_ACCESS_KEY  > aws-secret-access-key
aws s3 cp jenkins-admin-password s3://$BUCKET_NAME/ --region $REGION_NAME
aws s3 cp aws-access-key-id      s3://$BUCKET_NAME/ --region $REGION_NAME
aws s3 cp aws-secret-access-key  s3://$BUCKET_NAME/ --region $REGION_NAME
rm -r /dev/shm/aws-devops/credentials/

#-----------------------------------------------------------------------------#
# Apply the Jenkins terraform configuration.                                  #
#-----------------------------------------------------------------------------#

# Initializes the terraform configuration.
cd $PROJECT_PATH/jenkins/
terraform init -input=false \
    -backend-config="bucket=$ACCOUNT_ID-$PROJECT_NAME-jenkins-terraform-state" \
    -backend-config="key=terraform.tfstate" \
    -backend-config="region=$REGION_NAME" \
    -backend-config="dynamodb_table=$ACCOUNT_ID-$PROJECT_NAME-jenkins-terraform-lock" \
    -backend-config="encrypt=true"

# Create the Jenkins IAM role
terraform apply -input=false -lock=true -auto-approve \
    -target "aws_iam_role.jenkins" \
    -var "account_id=$ACCOUNT_ID" \
    -var "region_name=$REGION_NAME" \
    -var "project_name=$PROJECT_NAME" \
    -var "bucket_name=$BUCKET_NAME"

# Update the temporal bucket policy to grant access only to the Jenkins server.
# Wait until the IAM role is propagated to apply the bucket policy accordingly.
JENKINS_ROLE=$PROJECT_NAME-$REGION_NAME-jenkins
BUCKET_POLICY="{\"Version\": \"2012-10-17\",\"Id\": \"Policy1583629506118\",\"Statement\": [{\"Sid\": \"Stmt1583629432359\",\"Effect\": \"Allow\",\"Principal\": {\"AWS\": \"arn:aws:iam::$ACCOUNT_ID:role/$JENKINS_ROLE\"},\"Action\": [\"s3:DeleteBucket\",\"s3:DeleteObject\",\"s3:GetObject\",\"s3:ListBucket\"],\"Resource\": [\"arn:aws:s3:::$BUCKET_NAME/*\",\"arn:aws:s3:::$BUCKET_NAME\"]}]}"
aws iam wait role-exists --role-name $JENKINS_ROLE

set +exuo pipefail;
for i in {1..50}; do
    aws s3api put-bucket-policy \
        --bucket $BUCKET_NAME \
        --region $REGION_NAME \
        --policy "$BUCKET_POLICY"
    RESULT=$?
    if [ $RESULT -eq 0 ]; then break; fi;
    sleep 6
done
if [ $RESULT -ne 0 ]; then echo "Couldn't wait for role ready."; exit 1; fi;
set -exuo pipefail;

# Apply the Jenkins terraform configuration.
terraform apply -input=false -lock=true -auto-approve \
    -var "account_id=$ACCOUNT_ID" \
    -var "region_name=$REGION_NAME" \
    -var "project_name=$PROJECT_NAME" \
    -var "bucket_name=$BUCKET_NAME"

#-----------------------------------------------------------------------------#
# End of the script.                                                          #
#-----------------------------------------------------------------------------#
echo "Installation finished successfully at $(date)"