#!/usr/bin/env bash
#replace the AWS account numbers and profiles below to match your own accounts and profiles
AWSAccount=295744685835
AWSAccountProfile=default
KeyPair=ethaaa-keypair

#select a region
region=us-west-2

#select a unique bucket name - this bucket will be created for you
S3TmpBucketName=mcdg-ethaaa-s3bucket

#create the temporary s3 bucket, used to store the SAM templates
echo -e "creating s3 bucket $S3TmpBucketName"
if [[ "$region" == "us-east-1" ]];
then
    aws s3api create-bucket --bucket $S3TmpBucketName --profile $AWSAccountProfile --region $region
else
    aws s3api create-bucket --bucket $S3TmpBucketName --profile $AWSAccountProfile --region $region --create-bucket-configuration LocationConstraint=$region
fi
cp s3-bucket-policy-template.json s3-bucket-policy.json
sed -i -e "s/<bucketname>/$S3TmpBucketName/g" s3-bucket-policy.json
sed -i -e "s/<AWSAccount>/$AWSAccount/g" s3-bucket-policy.json
#aws s3api put-bucket-policy --bucket $S3TmpBucketName --policy file://s3-bucket-policy.json

#creating vpc-network stack
echo -e "creating vpc-network stack"
aws cloudformation deploy --stack-name ethaaa-vpc-network --template-file vpc-network.template --capabilities CAPABILITY_NAMED_IAM --profile $AWSAccountProfile --region $region
VPCID=$(aws cloudformation describe-stacks --stack-name ethaaa-vpc-network --profile $AWSAccountProfile --region $region --query 'Stacks[0].Outputs[?OutputKey==`VPCID`].OutputValue' --output text)
Subnets=$(aws cloudformation describe-stacks --stack-name ethaaa-vpc-network --profile $AWSAccountProfile --region $region --query 'Stacks[0].Outputs[?OutputKey==`Subnets`].OutputValue' --output text)
SubnetPublic=$(aws cloudformation describe-stacks --stack-name ethaaa-vpc-network --profile $AWSAccountProfile --region $region --query 'Stacks[0].Outputs[?OutputKey==`SubnetPublic`].OutputValue' --output text)
SubnetPrivate=$(aws cloudformation describe-stacks --stack-name ethaaa-vpc-network --profile $AWSAccountProfile --region $region --query 'Stacks[0].Outputs[?OutputKey==`SubnetPrivate`].OutputValue' --output text)
SecurityGroup=$(aws cloudformation describe-stacks --stack-name ethaaa-vpc-network --profile $AWSAccountProfile --region $region --query 'Stacks[0].Outputs[?OutputKey==`SecurityGroup`].OutputValue' --output text)
IamRoleECS=$(aws cloudformation describe-stacks --stack-name ethaaa-vpc-network --profile $AWSAccountProfile --region $region --query 'Stacks[0].Outputs[?OutputKey==`IamRoleECS`].OutputValue' --output text)
IamRoleEC2InstanceProfile=$(aws cloudformation describe-stacks --stack-name ethaaa-vpc-network --profile $AWSAccountProfile --region $region --query 'Stacks[0].Outputs[?OutputKey==`IamRoleEC2InstanceProfile`].OutputValue' --output text)
echo -e "VPCID: $VPCID"
echo -e "Subnets: $Subnets"
echo -e "SubnetPublic: $SubnetPublic"
echo -e "SubnetPrivate: $SubnetPrivate"
echo -e "SecurityGroup: $SecurityGroup"
echo -e "IamRoleECS: $IamRoleECS"
echo -e "IamRoleEC2InstanceProfile: $IamRoleEC2InstanceProfile"

#creating ethereum stack into VPC created in the step above
echo -e "creating ethereum stack"
#copy the ethereum nested stack templates to S3
aws s3api put-object --bucket $S3TmpBucketName --key ethereum-templates/ethereum-common.template --body ethereum-common.template
aws s3api put-object --bucket $S3TmpBucketName --key ethereum-templates/ethereum-docker-local.template --body ethereum-docker-local.template
aws s3api put-object --bucket $S3TmpBucketName --key ethereum-templates/ethereum-autoscalegroup.template --body ethereum-autoscalegroup.template
aws s3api put-object --bucket $S3TmpBucketName --key ethereum-templates/ethereum-ecs.template --body ethereum-ecs.template
EthereumTemplateURL="https://s3.us-west-2.amazonaws.com/$S3TmpBucketName/ethereum-templates/"
echo -e "EthereumTemplateURL: $EthereumTemplateURL"

#create the stack
aws cloudformation deploy --stack-name ethaaa-ethereum-network --template-file ethereum-network.template --capabilities CAPABILITY_NAMED_IAM --parameter-overrides NestedTemplateURL=$EthereumTemplateURL VPCID=$VPCID NetworkSubnetIDs=$SubnetPublic ALBSubnetIDs=$Subnets EC2InstanceProfileArn=$IamRoleEC2InstanceProfile ECSRoleForALB=$IamRoleECS EC2SecurityGroup=$SecurityGroup LoadBalancerSecurityGroup=$SecurityGroup EC2KeyPairName=$KeyPair --profile $AWSAccountProfile --region $region
EthStatsURL=$(aws cloudformation describe-stacks --stack-name ethaaa-ethereum-network --profile $AWSAccountProfile --region $region --query 'Stacks[0].Outputs[?OutputKey==`EthStatsURL`].OutputValue' --output text)
EthExplorerURL=$(aws cloudformation describe-stacks --stack-name ethaaa-ethereum-network --profile $AWSAccountProfile --region $region --query 'Stacks[0].Outputs[?OutputKey==`EthExplorerURL`].OutputValue' --output text)
EthJsonRPCURL=$(aws cloudformation describe-stacks --stack-name ethaaa-ethereum-network --profile $AWSAccountProfile --region $region --query 'Stacks[0].Outputs[?OutputKey==`EthJsonRPCURL`].OutputValue' --output text)


#deploy the ListenForTransactions lambda
echo -e "creating ListenForTransactions lambda"
cd ListenForTransactions
#npm install
#aws cloudformation package --template-file listen-for-transactions.yaml --s3-bucket $S3TmpBucketName --s3-prefix ListenForTransactions --output-template-file output-listen-for-transactions.yaml --profile $AWSAccountProfile --region $region
aws cloudformation deploy --stack-name ListenForTransactions --template-file output-listen-for-transactions.yaml --capabilities CAPABILITY_NAMED_IAM --parameter-overrides LambdaSubnetPublic=$SubnetPublic LambdaSubnetPrivate=$SubnetPrivate LambdaSecurityGroup=$SecurityGroup --profile $AWSAccountProfile --region $region
ListenForTransactionsLambdaArn=$(aws cloudformation describe-stacks --stack-name ListenForTransactions --profile $AWSAccountProfile --region $region --query 'Stacks[0].Outputs[?OutputKey==`ListenForTransactionsLambdaArn`].OutputValue' --output text)
echo -e "ListenForTransactionsLambdaArn: $ListenForTransactionsLambdaArn"
cd ..

#deploy the ExecuteTransactions lambda
echo -e "creating ExecuteTransactions lambda"
cd ExecuteTransactions
#npm install
#aws cloudformation package --template-file execute-transactions.yaml --s3-bucket $S3TmpBucketName --s3-prefix ExecuteTransactions --output-template-file output-execute-transactions.yaml --profile $AWSAccountProfile --region $region
aws cloudformation deploy --stack-name ExecuteTransactions --template-file output-execute-transactions.yaml --capabilities CAPABILITY_NAMED_IAM --parameter-overrides LambdaSubnetPublic=$SubnetPublic LambdaSubnetPrivate=$SubnetPrivate LambdaSecurityGroup=$SecurityGroup --profile $AWSAccountProfile --region $region
ExecuteTransactionsLambdaArn=$(aws cloudformation describe-stacks --stack-name ExecuteTransactions --profile $AWSAccountProfile --region $region --query 'Stacks[0].Outputs[?OutputKey==`ExecuteTransactionsLambdaArn`].OutputValue' --output text)
echo -e "ExecuteTransactionsLambdaArn: $ExecuteTransactionsLambdaArn"
cd ..

#deploy the DeployContract lambda
echo -e "creating DeployContract lambda"
cd DeployContract
#npm install
#aws cloudformation package --template-file deploy-contract.yaml --s3-bucket $S3TmpBucketName --s3-prefix DeployContract --output-template-file output-deploy-contract.yaml --profile $AWSAccountProfile --region $region
aws cloudformation deploy --stack-name DeployContract --template-file output-deploy-contract.yaml --capabilities CAPABILITY_NAMED_IAM --parameter-overrides LambdaSubnetPublic=$SubnetPublic LambdaSubnetPrivate=$SubnetPrivate LambdaSecurityGroup=$SecurityGroup --profile $AWSAccountProfile --region $region
DeployContractLambdaArn=$(aws cloudformation describe-stacks --stack-name DeployContract --profile $AWSAccountProfile --region $region --query 'Stacks[0].Outputs[?OutputKey==`DeployContractLambdaArn`].OutputValue' --output text)
echo -e "DeployContractLambdaArn: $DeployContractLambdaArn"
cd ..

