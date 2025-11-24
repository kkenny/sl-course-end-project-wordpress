# Quick Start Guide

## Prerequisites Checklist

- [ ] AWS Account with admin/appropriate permissions
- [ ] AWS CLI installed (`aws --version`)
- [ ] AWS CLI configured (`aws configure`)
- [ ] **Configure AWS Profile** (optional but recommended):
  ```bash
  cp _set_profile_example.sh _set_profile.sh
  # Edit _set_profile.sh and add your AWS credentials and region
  ```
  The `_set_profile.sh` file will be automatically sourced by deployment scripts.
- [ ] EC2 Key Pair created in your target region
- [ ] Sufficient AWS service limits (VPCs, EC2 instances, RDS instances)

## Step-by-Step Deployment

### 1. Clone and Navigate
```bash
cd sl-course-end-project-wordpress
```

### 2. Configure AWS Profile (Optional but Recommended)
```bash
# Copy the example profile file
cp _set_profile_example.sh _set_profile.sh

# Edit _set_profile.sh and add your AWS credentials:
# - AWS_ACCESS_KEY_ID: Your AWS access key
# - AWS_SECRET_ACCESS_KEY: Your AWS secret key
# - AWS_DEFAULT_REGION: Your target AWS region (e.g., us-east-1, us-east-2)
```

**Note:** The `_set_profile.sh` file is automatically sourced by all deployment scripts. If you prefer to use `aws configure` instead, you can skip this step.

### 3. Make Scripts Executable (if needed)
```bash
chmod +x *.sh
```

### 4. Deploy Production Environment (24/7)
```bash
./deploy-prod.sh
```

**What to expect:**
- Script will prompt for:
  - EC2 Key Pair Name (must exist in your region)
  - WordPress Admin Password (min 8 characters)
  - WordPress Admin Email
  - WordPress Admin Username (default: admin)
  - Instance Type (default: t3.medium)
- Deployment takes 15-20 minutes
- Production environment runs 24/7 (no auto-shutdown)
- You'll see stack outputs including WordPress URL

### 4b. Deploy Development Environment (Auto-Shutdown)
```bash
./deploy-dev.sh
```

**What to expect:**
- Script will prompt for:
  - EC2 Key Pair Name (must exist in your region)
  - WordPress Admin Password (min 8 characters)
  - WordPress Admin Email
  - WordPress Admin Username (default: admin)
  - Instance Type (default: t3.micro)
  - Business Hours Start (default: 09:00 UTC)
  - Business Hours End (default: 18:00 UTC)
- Deployment takes 15-20 minutes
- Development environment auto-shuts down outside business hours
- You'll see stack outputs including WordPress URL

### 5. Wait for WordPress Installation
After deployment completes, wait 3-5 minutes for WordPress to finish installing.

### 6. Access WordPress
1. Get the WordPress URL from stack outputs
2. Open in browser
3. Complete WordPress setup wizard

### 7. Create AMI (Task 2)
Once WordPress is configured:

**For Production:**
```bash
STACK_NAME=wordpress-prod ./create-ami.sh
```

**For Development:**
```bash
STACK_NAME=wordpress-dev ./create-ami.sh
```

Or use default (development):
```bash
./create-ami.sh
```
- Takes 10-15 minutes
- AMI ID saved to `.ami-id.txt`

### 8. Update Launch Template (Optional)
To use the new AMI for future instances:
```bash
./update-launch-template-with-ami.sh
```

## Verification

### Check Stack Status
**Production:**
```bash
aws cloudformation describe-stacks --stack-name wordpress-prod
```

**Development:**
```bash
aws cloudformation describe-stacks --stack-name wordpress-dev
```

### Check Auto Scaling Group
**Production:**
```bash
aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names Production-WordPressAutoScalingGroup
```

**Development:**
```bash
aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names Development-WordPressAutoScalingGroup
```

### Check Lambda Function (Development only)
```bash
aws lambda get-function --function-name Development-WordPressAutoShutdown
```

### View Lambda Logs (Development only)
```bash
aws logs tail /aws/lambda/Development-WordPressAutoShutdown --follow
```

## Task Verification

### ✅ Task 1: CloudFormation Stack
- **Production Stack:** Deployed successfully (24/7)
- **Development Stack:** Deployed successfully (auto-shutdown)
- All resources created
- Check: `aws cloudformation describe-stacks --stack-name wordpress-prod` or `wordpress-dev`

### ✅ Task 2: AMI Creation
- AMI created from WordPress instance
- Works for both production and development environments
- Check: `aws ec2 describe-images --image-ids $(cat .ami-id.txt)`

### ✅ Task 3: Auto Scaling
- Auto Scaling Group configured for both environments
- Launch Template created
- Check: `aws autoscaling describe-auto-scaling-groups`

### ✅ Task 4: Auto Shutdown
- **Production:** No auto-shutdown (runs 24/7)
- **Development:** Lambda function created
- **Development:** EventBridge rule scheduled (every hour)
- Check: `aws events describe-rule --name Development-WordPressAutoShutdownSchedule`

## Troubleshooting

### Stack Creation Fails
1. Check CloudFormation events in AWS Console
2. Verify IAM permissions
3. Check service limits
4. Ensure Key Pair exists

### Can't Access WordPress
1. Wait 5-10 minutes after stack creation
2. Check security group allows HTTP (port 80)
3. Verify instance is running
4. Check Load Balancer health

### AMI Creation Fails
1. Ensure instance is running
2. Check IAM permissions for EC2
3. Verify instance is in Auto Scaling Group

## Cleanup

To delete production environment:
```bash
aws cloudformation delete-stack --stack-name wordpress-prod
aws cloudformation wait stack-delete-complete --stack-name wordpress-prod
```

To delete development environment:
```bash
aws cloudformation delete-stack --stack-name wordpress-dev
aws cloudformation wait stack-delete-complete --stack-name wordpress-dev
```

## Cost Estimate

**Free Tier Eligible:**
- t3.micro EC2 instance
- db.t3.micro RDS instance
- Lambda (1M requests/month free)

**Estimated Monthly Cost (outside free tier):**
- t3.medium EC2: ~$30/month
- db.t3.micro RDS: ~$15/month
- Load Balancer: ~$16/month
- Data transfer: varies
- **Total: ~$60-80/month** (with auto-shutdown reducing costs)

**Cost Savings:**
- Auto-shutdown feature stops instances outside business hours
- Reduces EC2 costs by ~50% if only running 9 hours/day

