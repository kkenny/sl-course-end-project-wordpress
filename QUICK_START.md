# Quick Start Guide

## TLDR

**Quick deployment workflow:**
1. Configure AWS credentials (`_set_profile.sh`)
2. Create EC2 Key Pair (`utils/create-key-pair.sh -k wordpress-project`)
3. Deploy dev environment (`./deploy-dev.sh`)
4. Configure WordPress in dev
5. Create AMI from dev (`./create-ami.sh`)
6. Deploy production using the AMI (`./deploy-prod.sh`)

**Key commands:**
- Check stack status: `utils/check-stack-status.sh -s wordpress-dev`
- Troubleshoot WordPress: `utils/troubleshoot-wordpress.sh -s wordpress-dev`
- Delete stack: `./destroy-stack.sh -s wordpress-dev`

**Time estimate:** ~45-60 minutes total (15-20 min per deployment + 10-15 min for AMI creation)

---

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

**Workflow Overview:**
1. Deploy development environment first for testing
2. Configure WordPress in development
3. Create an AMI from the configured development environment
4. Deploy production environment using the AMI from development

This workflow ensures that production uses a tested and configured WordPress instance.

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

**Note:** The `_set_profile.sh` file is automatically sourced by all deployment scripts to make this more portable and not overwrite any other AWS configuration you may already have set. If you prefer to use `aws configure` instead, you can skip this step.

### 3. Make Scripts Executable (if needed)
```bash
chmod +x *.sh
```

### 4. Create EC2 Key Pair (if needed)
If you don't already have an EC2 Key Pair in your target AWS region, create one:

```bash
utils/create-key-pair.sh -k wordpress-project
```

**What to expect:**
- Creates a new EC2 Key Pair named `wordpress-project` in your AWS region
- Saves the private key to `./wordpress-project.pem` in the current directory
- **Important:** Keep the `.pem` file secure and never commit it to version control
- You can use this key to SSH into EC2 instances: `ssh -i wordpress-project.pem ec2-user@<instance-ip>`

**Note:** If you already have a Key Pair in your region, you can skip this step and use your existing Key Pair name when prompted during deployment.

### 5. Deploy Development Environment (Auto-Shutdown)
Deploy the development environment first for testing and AMI creation:

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

### 6. Wait for WordPress Installation
After deployment completes, wait 3-5 minutes for WordPress to finish installing.

### 7. Access and Configure WordPress (Development)
1. Get the WordPress URL from stack outputs
2. Open in browser
3. Complete WordPress setup wizard
4. Configure WordPress as needed (themes, plugins, content, etc.)

**Note:** Make sure WordPress is fully configured before creating the AMI, as the AMI will capture the current state of the instance.

### 8. Create AMI from Development Environment (Task 2)
Once WordPress is configured in the development environment, create an AMI:

```bash
STACK_NAME=wordpress-dev ./create-ami.sh
```

Or use the default (development):
```bash
./create-ami.sh
```

**What to expect:**
- Takes 10-15 minutes
- AMI ID automatically saved to `.ami-id.txt`
- This AMI will be used for the production deployment

### 9. Deploy Production Environment (24/7)
Deploy the production environment using the AMI created from development:

```bash
./deploy-prod.sh
```

**What to expect:**
- Script will automatically use the AMI ID from `.ami-id.txt` (created in step 7)
- Script will prompt for:
  - EC2 Key Pair Name (must exist in your region)
  - WordPress Admin Password (min 8 characters)
  - WordPress Admin Email
  - WordPress Admin Username (default: admin)
  - Instance Type (default: t3.medium)
- Deployment takes 15-20 minutes
- Production environment runs 24/7 (no auto-shutdown)
- You'll see stack outputs including WordPress URL

**Note:** The production environment will use the AMI created from your configured development environment, ensuring consistency between environments.

### 10. Update Launch Template (Optional)
To use the new AMI for future instances in the production Auto Scaling Group:

```bash
STACK_NAME=wordpress-prod ./update-launch-template-with-ami.sh
```

This ensures that any new instances launched by Auto Scaling will use your custom AMI.

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
- **Development Stack:** Deployed successfully (auto-shutdown)
- **Production Stack:** Deployed successfully (24/7) using AMI from development
- All resources created
- Check: `aws cloudformation describe-stacks --stack-name wordpress-dev` or `wordpress-prod`

### ✅ Task 2: AMI Creation
- AMI created from development WordPress instance
- AMI used for production deployment
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
1. Check stack status using the utility script:
   ```bash
   utils/check-stack-status.sh -s wordpress-dev
   # or for production:
   utils/check-stack-status.sh -s wordpress-prod
   ```
   This will show stack status, failed resources, and recent events.
2. Wait 5-10 minutes after stack creation
3. Check security group allows HTTP (port 80)
4. Verify instance is running
5. Check Load Balancer health

### AMI Creation Fails
1. Ensure instance is running
2. Check IAM permissions for EC2
3. Verify instance is in Auto Scaling Group

## Cleanup

To delete stacks, use the `destroy-stack.sh` script:

**To delete production environment:**
```bash
./destroy-stack.sh -s wordpress-prod
```

**To delete development environment:**
```bash
./destroy-stack.sh -s wordpress-dev
```

Or use the default (development):
```bash
./destroy-stack.sh
```

**What to expect:**
- Script checks AWS credentials
- Verifies the stack exists
- Deletes the CloudFormation stack
- Waits for deletion to complete (can take 10-15 minutes)
- Shows stack status and events if deletion fails

**Note:** Stack deletion will remove all resources created by the stack, including EC2 instances, RDS databases, Load Balancers, and other AWS resources. Make sure you have backups of any important data before deleting stacks.


