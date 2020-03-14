#!/bin/bash
set -exuo pipefail
echo "Uninstallation started at $(date)"

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
# Destroy resorces not tracked by any of the terraform configurations.        #                                       #
#-----------------------------------------------------------------------------#

# Delete the Kubernetes buckets that stored the cluster join information. 
aws s3 rb s3://$ACCOUNT_ID-$PROJECT_NAME-private-dev-master --force || true
aws s3 rb s3://$ACCOUNT_ID-$PROJECT_NAME-private-prod-master --force || true
aws s3 rb s3://$ACCOUNT_ID-$PROJECT_NAME-jenkins-secrets --force || true

# Delete the Elastic Load Balancers created for the web-ui and kubernetes-api.
ELB_LIST=$(aws elb describe-load-balancers \
    --region $REGION_NAME \
    --query 'LoadBalancerDescriptions[*].{Name:LoadBalancerName}' \
    --output text)
for elb_name in $ELB_LIST; do
    aws elb delete-load-balancer \
        --load-balancer-name $elb_name \
        --region $REGION_NAME || true;
done

# Delete the security groups created for the load balancers above.
KUBERNETES_GROUP_LIST=$(aws ec2 describe-security-groups \
    --region $REGION_NAME \
    --filters "Name=tag:kubernetes.io/cluster/$PROJECT_NAME,Values=owned" \
    --query "SecurityGroups[].GroupId" \
    --output text)
for kubernetes_group_id in $KUBERNETES_GROUP_LIST; do
    for environment in dev prod; do
        set +exuo pipefail
        IS_GROUP_USED=$(aws ec2 describe-security-groups \
            --region $REGION_NAME \
            --filters "Name=tag:Name,Values=$PROJECT_NAME-private-$environment-node" \
            | grep $kubernetes_group_id)
        set -exuo pipefail
        if [ ! -z "$IS_GROUP_USED" ]; then
            GROUP_ID=$(aws ec2 describe-security-groups \
                --region $REGION_NAME \
                --filters "Name=tag:Name,Values=$PROJECT_NAME-private-$environment-node" \
                --query "SecurityGroups[].GroupId" \
                --output text)
            aws ec2 revoke-security-group-ingress \
                --region $REGION_NAME \
                --group-id $GROUP_ID \
                --protocol all \
                --port -1 \
                --source-group $kubernetes_group_id || true
        fi
    done
    set +exuo pipefail;
    for i in {1..50}; do
        aws ec2 delete-security-group \
            --region $REGION_NAME \
            --group-id $kubernetes_group_id
        if [ $? -eq 0 ]; then break; fi;
        sleep 6
    done
    set -exuo pipefail;
done

#-----------------------------------------------------------------------------#
# Destroy the terraform configurations.                                       #
#-----------------------------------------------------------------------------#

# Download the terraform configurations from the git repository.
mkdir /aws-devops
cd /aws-devops
git clone --depth 1 "https://github.com/alfpedraza-aws-devops/infrastructure.git"
PROJECT_PATH=/aws-devops/infrastructure
BUCKET_NAME="$ACCOUNT_ID-$PROJECT_NAME-jenkins-secrets"

# Destroy the specified terraform configuration.
for configuration in prod dev jenkins vpc
do
    cd $PROJECT_PATH/$configuration/
    terraform init -input=false \
        -backend-config="bucket=$ACCOUNT_ID-$PROJECT_NAME-$configuration-terraform-state" \
        -backend-config="key=terraform.tfstate" \
        -backend-config="region=$REGION_NAME" \
        -backend-config="dynamodb_table=$ACCOUNT_ID-$PROJECT_NAME-$configuration-terraform-lock" \
        -backend-config="encrypt=true" || true
    terraform destroy -input=false -lock=true -auto-approve \
        -var "account_id=$ACCOUNT_ID" \
        -var "region_name=$REGION_NAME" \
        -var "project_name=$PROJECT_NAME" \
        `if [ $configuration = jenkins ]; then echo "-var bucket_name=$BUCKET_NAME"; fi` \
        || true
done

#-----------------------------------------------------------------------------#
# Destroy the state buckets and table locks for the terraform configurations. #
#-----------------------------------------------------------------------------#

for configuration in prod dev jenkins vpc
do
    BUCKET_NAME=$ACCOUNT_ID-$PROJECT_NAME-$configuration-terraform-state
    TABLE_NAME=$ACCOUNT_ID-$PROJECT_NAME-$configuration-terraform-lock 
    aws s3api delete-objects \
        --bucket $BUCKET_NAME \
        --delete "$(aws s3api list-object-versions \
            --bucket "$BUCKET_NAME" \
            --output=json \
            --query='{Objects: Versions[].{Key:Key,VersionId:VersionId}}')" || true
    sleep 2
    aws s3 rb s3://$BUCKET_NAME --force || true
    aws dynamodb delete-table \
        --table-name $TABLE_NAME \
        --region $REGION_NAME || true
done

#-----------------------------------------------------------------------------#
# End of the script.                                                          #
#-----------------------------------------------------------------------------#
echo "Uninstallation finished successfully at $(date)"