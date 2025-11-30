[![Integration Tests](https://img.shields.io/badge/integration%20tests-passing-brightgreen)](tests/integration)
[![Unit Tests](https://img.shields.io/badge/unit%20tests-passing-brightgreen)](tests/unit)
[![Performance Tests](https://img.shields.io/badge/performance%20tests-passing-brightgreen)](tests/performance)
<!-- Tests last run: 2025-11-29 20:16:34 UTC -->

# SimpliLearn Course End Project: Set Up and Monitor a WordPress Instance

## Objectives
To set up and monitor a WordPress instance for your organization is to establish a reliable and secure online presence that supports your business or organizational goals.

## Relevance
In this project, several skills and tools are utilized, each serving a specific purpose within the industry:
AWS console – The AWS Management Console is a web application that includes and references several service consoles for managing AWS services.
- AWS CloudFormation – It is a service that aids users in modeling and configuring their AWS resources so they can focus more on their AWS-based apps and spend less time maintaining those resources.
- EC2 Instance - Amazon EC2 provides a large set of instance types that are customized to certain use cases.

## Problem Statement
You are given a project to be able to configure a WordPress instance using AWS CloudFormation and monitor the instance

### Real-World Scenario
Your organization publishes blogs and provides documentation services for other businesses and technologies. You have been asked to:
- Set up a **live WordPress instance** to publish blogs
- Set up a WordPress instance that can be used for **development and testing purposes** so that any work done on this instance will not impact the live blog
- Configure the WordPress instance for development and testing purposes, which will be available only **during the business hours** (9AM–6 PM)

## Acceptance Criteria
1. Create a CloudFormation stack
2. Create an AMI of the WordPress instance
3. Configure Auto Scaling to launch a new WordPress instance
4. Configure the new WordPress instance to shut down automatically

## Solution Implementation
This repository contains a complete solution for deploying and managing **two separate WordPress environments** on AWS.
1. **Production Environment** - Runs 24/7 for live blog publishing
2. **Development Environment** - Auto-shuts down outside business hours for cost optimization

## Key Features:
### Components
1. **CloudFormation Template** (`wordpress-stack.yaml`)
   - Complete infrastructure setup including VPC, subnets, security groups
   - EC2 instances with WordPress installation
   - RDS MySQL database for WordPress
   - Auto Scaling Group configuration
   - Application Load Balancer
   - **Conditional Lambda function** for automatic shutdown/startup (Development only)
   - **Conditional EventBridge rule** for scheduled checks (Development only)
   - **CloudWatch Alarms** for monitoring EC2, RDS, ALB, and Auto Scaling metrics
   - **CloudWatch Dashboard** with comprehensive monitoring widgets
   - **SNS Topic** for alarm notifications (optional, email-based)
   - Environment-aware resource naming and tagging

2. **Production Deployment Script** (`deploy-prod.sh`)
   - Deploys production environment (24/7)
   - Interactive parameter collection
   - Automatic AMI discovery for the region
   - Optional CloudWatch alarm email notifications (`--alarm-email`)
   - No auto-shutdown configuration

3. **Development Deployment Script** (`deploy-dev.sh`)
   - Deploys development environment with auto-shutdown
   - Interactive parameter collection including business hours
   - Automatic AMI discovery for the region
   - Optional CloudWatch alarm email notifications (`--alarm-email`)
   - Configures Lambda and EventBridge for scheduled shutdown

4. **AMI Creation Script** (`create-ami.sh`)
   - Creates an AMI from the running WordPress instance
   - Automatically detects environment (prod/dev) from stack name
   - Automatically finds the instance from the Auto Scaling Group
   - Saves AMI ID for later use

5. **Launch Template Update Script** (`update-launch-template-with-ami.sh`)
   - Updates the Launch Template with a new AMI ID
   - Ensures new instances use the latest AMI

6. **Utility Scripts** (`utils/`)
   - **`check-stack-status.sh`** - Check CloudFormation stack status and recent events
   - **`get-stack-info.sh`** - Get detailed information about stack resources, outputs, parameters, and instances
   - **`create-key-pair.sh`** - Create EC2 key pairs for SSH access
   - **`troubleshoot-wordpress.sh`** - Troubleshooting guide and diagnostic commands for WordPress issues

## Prerequisites
1. **AWS Account** with appropriate permissions
   - Your IAM user/role needs the following permissions:
     - `ec2:*` (or at minimum: `ec2:CreateLaunchTemplate`, `ec2:RunInstances`, `ec2:Describe*`, `ec2:CreateTags`)
     - `autoscaling:*` (or at minimum: `autoscaling:CreateAutoScalingGroup`, `autoscaling:UpdateAutoScalingGroup`, `autoscaling:Describe*`)
     - `rds:*` (or at minimum: `rds:CreateDBInstance`, `rds:DescribeDBInstances`)
     - `elasticloadbalancing:*` (or at minimum: `elasticloadbalancing:CreateLoadBalancer`, `elasticloadbalancing:CreateTargetGroup`, `elasticloadbalancing:Describe*`)
     - `lambda:*` (or at minimum: `lambda:CreateFunction`, `lambda:InvokeFunction`)
     - `events:*` (or at minimum: `events:PutRule`, `events:PutTargets`)
     - `iam:*` (or at minimum: `iam:CreateRole`, `iam:AttachRolePolicy`, `iam:CreateInstanceProfile`)
     - `cloudformation:*` (or at minimum: `cloudformation:CreateStack`, `cloudformation:DescribeStacks`)
   - **Important:** For launch templates, you need `ec2:RunInstances` permission that includes the launch template resource ARN
2. **AWS CLI** installed and configured
   ```bash
   aws configure
   ```
3. **Configure AWS Profile** (optional but recommended):
   ```bash
   cp _set_profile_example.sh _set_profile.sh
   # Edit _set_profile.sh and add your AWS credentials and region
   ```
   The `_set_profile.sh` file will be automatically sourced by deployment scripts to set your AWS credentials.
4. **EC2 Key Pair** created in your AWS region
    - If needed, you can create a new keypair with `utils/create-key-pair.sh`
    ```bash
    utils/create-key-pair.sh -k wordpress-project
    ```
    - This will create the key-pair and store the newly generated private key to `./wordpress-project.pem`
    - You can use this keypair to ssh to EC2 instances: `ssh -i wordpress-project.pem ec2-user@ip`
5. **Basic knowledge** of AWS services (EC2, CloudFormation, Auto Scaling)

## Quick Start Guide
For detailed step-by-step deployment instructions, please refer to [QUICK_START.md](QUICK_START.md).

The Quick Start Guide includes:
- Prerequisites checklist
- Step-by-step deployment instructions for both production and development environments
- AMI creation and Launch Template updates
- Verification steps
- Troubleshooting tips

## Task Completion
### ✅ Task 1: Create a CloudFormation Stack
**Completed** - The `wordpress-stack.yaml` template creates a complete stack with:
- VPC with public subnets
- Security groups
- RDS MySQL database
- EC2 instances with WordPress
- Auto Scaling Group
- Load Balancer
- Lambda function for automation (Development only)
- CloudWatch Alarms and Dashboard for comprehensive monitoring
- SNS Topic for alarm notifications (optional)

**Usage:** 
- Run `./deploy-prod.sh` to deploy the production environment (24/7)
- Run `./deploy-dev.sh` to deploy the development environment (auto-shutdown)

### ✅ Task 2: Create an AMI of the WordPress Instance
**Completed** - The `create-ami.sh` script:
- Automatically finds the WordPress instance
- Creates an AMI with a timestamped name
- Waits for AMI to be available
- Saves AMI ID for reference

**Usage:** Run `./create-ami.sh` after configuring WordPress.

### ✅ Task 3: Configure Auto Scaling to Launch a New WordPress Instance
**Completed** - The CloudFormation template includes:
- Launch Template with WordPress configuration
- Auto Scaling Group (min: 1, max: 3, desired: 1)
- Target Group and Load Balancer integration
- Health checks configured

**Configuration:** Auto Scaling is automatically configured during stack deployment.

### ✅ Task 4: Configure the New WordPress Instance to Shut Down Automatically
**Completed** - The solution includes:
- **Production Environment:** Runs 24/7 (no auto-shutdown)
- **Development Environment:** 
  - Lambda function (`Development-WordPressAutoShutdown`) that checks business hours
  - EventBridge rule that triggers every hour
  - Automatic shutdown of instances outside business hours (9 AM - 6 PM UTC, configurable)
  - Automatic startup of instances during business hours

**Configuration:** 
- Production: Always running, no shutdown
- Development: Business hours configurable via CloudFormation parameters (default: 09:00-18:00 UTC)

## Architecture Overview
### Development Environment (Auto-Shutdown)
```
┌─────────────────────────────────────────────────────────┐
│                    Internet Gateway                      │
└────────────────────┬────────────────────────────────────┘
                     │
┌────────────────────▼────────────────────────────────────┐
│      Development Application Load Balancer                │
└────────────────────┬────────────────────────────────────┘
                     │
         ┌───────────┴───────────┐
         │                       │
┌────────▼────────┐    ┌─────────▼─────────┐
│  Auto Scaling   │    │  Auto Scaling     │
│  Group Instance │    │  Group Instance   │
│  (WordPress)    │    │  (WordPress)      │
│  Development    │    │  Development      │
└────────┬────────┘    └─────────┬─────────┘
         │                       │
         └───────────┬───────────┘
                     │
         ┌───────────▼───────────┐
         │   RDS MySQL Database  │
         │     (Development)     │
         └───────────────────────┘

┌─────────────────────────────────────────────────────────┐
│     Lambda Function (Auto Shutdown - Dev Only)          │
│  Triggered by EventBridge every hour                    │
│  Checks business hours and starts/stops instances      │
│  Only active for Development environment                │
└─────────────────────────────────────────────────────────┘
```

### Production Environment (24/7)
```
┌─────────────────────────────────────────────────────────┐
│                    Internet Gateway                      │
└────────────────────┬────────────────────────────────────┘
                     │
┌────────────────────▼────────────────────────────────────┐
│        Production Application Load Balancer              │
└────────────────────┬────────────────────────────────────┘
                     │
         ┌───────────┴───────────┐
         │                       │
┌────────▼────────┐    ┌─────────▼─────────┐
│  Auto Scaling   │    │  Auto Scaling     │
│  Group Instance │    │  Group Instance   │
│  (WordPress)    │    │  (WordPress)      │
│  Production     │    │  Production       │
└────────┬────────┘    └─────────┬─────────┘
         │                       │
         └───────────┬───────────┘
                     │
         ┌───────────▼───────────┐
         │   RDS MySQL Database  │
         │      (Production)      │
         └───────────────────────┘
```

**Key Differences:**
- **Production:** Always running, no Lambda/EventBridge, Availability groups target 3 instances, max of 8
- **Development:** Lambda function monitors and shuts down instances outside business hours, Availability groups target 1 instance, max of 3

## Configuration Details
### Environment Configuration
**Production Environment:**
- Runs 24/7 with no auto-shutdown
- Suitable for live blog publishing
- High availability with Auto Scaling
- No Lambda function or EventBridge rules

**Development Environment:**
- Lambda function automatically manages instance lifecycle based on business hours:
  - **During business hours:** Instances are started if stopped
  - **Outside business hours:** Instances are stopped if running
- Default business hours: 9:00 AM - 6:00 PM UTC (configurable via parameters)
- Cost-optimized for development/testing workloads

### Auto Scaling Configuration
- **Minimum Size:** 1 instance
- **Maximum Size:** 3 instances
- **Desired Capacity:** 1 instance
- **Health Check:** ELB health checks every 30 seconds

### Security
- Security groups configured for:
  - HTTP (port 80) - public access
  - HTTPS (port 443) - public access
  - SSH (port 22) - public access (restrict in production)
- RDS database only accessible from WordPress security group
- IAM roles with least privilege access

## Monitoring and Management
### CloudWatch Monitoring
The stack includes comprehensive CloudWatch monitoring:

- **CloudWatch Dashboard**: A comprehensive dashboard with 10 widgets monitoring:
  - EC2 metrics (CPU, Network)
  - RDS database metrics (CPU, Connections, Storage, Network)
  - Application Load Balancer metrics (Request Count, Response Time, HTTP Status Codes)
  - Auto Scaling Group capacity
  - Target health status
  - SNS delivery metrics (if email notifications are enabled)

- **CloudWatch Alarms**: Pre-configured alarms for:
  - EC2 CPU utilization (threshold: 80%)
  - RDS CPU utilization (threshold: 80%)
  - RDS database connections (threshold: 80)
  - RDS free storage space (threshold: 2GB)
  - ALB unhealthy target count (threshold: 2)
  - ALB response time (threshold: 5 seconds)
  - ALB 5xx error count (threshold: 10)
  - Auto Scaling Group capacity issues

- **Email Notifications**: Optional email notifications via SNS when alarms trigger
  - Configure during deployment with `--alarm-email` option
  - Alarms will send notifications to the specified email address

**Access the Dashboard:**
```bash
# Get dashboard URL from stack outputs
aws cloudformation describe-stacks \
  --stack-name wordpress-stack \
  --query "Stacks[0].Outputs[?OutputKey=='CloudWatchDashboard'].OutputValue" \
  --output text
```

Or view it in the AWS Console under CloudWatch > Dashboards.

### View Stack Outputs
```bash
aws cloudformation describe-stacks \
  --stack-name wordpress-stack \
  --query "Stacks[0].Outputs" \
  --output table
```

### Check Auto Scaling Group Status
```bash
aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names WordPressAutoScalingGroup
```

### View Lambda Function Logs
```bash
aws logs tail /aws/lambda/WordPressAutoShutdown --follow
```

### Manual Instance Management
Start an instance:
```bash
aws ec2 start-instances --instance-ids <instance-id>
```

Stop an instance:
```bash
aws ec2 stop-instances --instance-ids <instance-id>
```

## Troubleshooting
### Stack Creation Fails
1. Check CloudFormation events in AWS Console
2. Verify IAM permissions (requires EC2, RDS, Lambda, Auto Scaling permissions)
   - **Common issue:** "You are not authorized to use launch template" error
     - Ensure your IAM user/role has `ec2:RunInstances` permission
     - The permission should allow using launch templates: `"Resource": "arn:aws:ec2:*:*:launch-template/*"`
     - Example policy:
       ```json
       {
         "Version": "2012-10-17",
         "Statement": [
           {
             "Effect": "Allow",
             "Action": "ec2:RunInstances",
             "Resource": [
               "arn:aws:ec2:*:*:instance/*",
               "arn:aws:ec2:*:*:launch-template/*"
             ]
           }
         ]
       }
       ```
3. Ensure Key Pair exists in the region
4. Check if default VPC limits are not exceeded

### WordPress Not Accessible
1. Wait 5-10 minutes after stack creation for WordPress installation
2. Check security group rules
3. Verify instance is running
4. Check Load Balancer health checks

### AMI Creation Fails
1. Ensure at least one instance is running in the Auto Scaling Group
2. Check instance state (should be "running")
3. Verify IAM permissions for EC2

### Auto Shutdown Not Working
1. Check Lambda function logs
2. Verify EventBridge rule is enabled
3. Check Lambda execution role permissions
4. Verify business hours are set correctly (UTC timezone)

## Cleanup
To delete all resources and avoid charges, use the `destroy-stack.sh` script:

```bash
# Destroy development stack
./destroy-stack.sh -s wordpress-dev

# Destroy production stack
./destroy-stack.sh -s wordpress-prod

# Specify a different region
./destroy-stack.sh -s wordpress-dev -r us-west-2
```

**Options:**
- `-s, --stack-name`: CloudFormation stack name (required)
- `-r, --region`: AWS region (default: from AWS_REGION env or us-east-1)
- `-h, --help`: Show help message

The script will:
- Verify AWS credentials
- Check if the stack exists
- Delete the stack and wait for completion
- Display stack status and events if deletion fails

**Note:** This will delete all resources including the database. Ensure you have backups if needed.

## Cost Optimization
- RDS instance uses `db.t3.micro` (eligible for free tier)
- EC2 instances can use `t3.micro` for testing (free tier eligible)
- Auto-shutdown feature reduces costs by stopping instances outside business hours
- Consider using Reserved Instances for production workloads

## Additional Notes
- All times are in UTC - adjust business hours accordingly
- The AMI ID in the template may need to be updated for your specific region
- **CloudWatch Monitoring**: The stack includes comprehensive monitoring by default. Configure email notifications during deployment for alarm alerts.
- **WordPress Customization**: The stack automatically downloads custom files:
  - `hostname.php` - Displays instance hostname
  - `footer.php` - Custom footer pattern for WordPress themes
- For production use, consider:
  - Using HTTPS with SSL certificates
  - Restricting SSH access to specific IPs
  - Reviewing and adjusting CloudWatch alarm thresholds based on your traffic patterns
  - Setting up automated backups
  - Using Multi-AZ RDS for high availability
  - Configuring CloudWatch alarm email notifications for critical alerts

## Utility Scripts
The `utils/` folder contains helpful utility scripts for managing and troubleshooting your WordPress stack:

### `check-stack-status.sh`
Quickly check the status of your CloudFormation stack and view recent events.

**Usage:**
```bash
utils/check-stack-status.sh -s wordpress-dev
utils/check-stack-status.sh -s wordpress-prod -r us-west-2
```

**Options:**
- `-s, --stack-name`: CloudFormation stack name (default: wordpress-dev)
- `-r, --region`: AWS region (default: from AWS_REGION env or us-east-1)
- `-h, --help`: Show help message

### `get-stack-info.sh`
Get comprehensive information about your stack including resources, outputs, parameters, instances, and database details.

**Usage:**
```bash
# Show all information
utils/get-stack-info.sh -s wordpress-dev -a

# Show specific information
utils/get-stack-info.sh -s wordpress-dev -e -i -d  # Events, instances, database
utils/get-stack-info.sh -s wordpress-prod -R -o    # Resources and outputs
```

**Options:**
- `-s, --stack-name`: CloudFormation stack name (required)
- `-r, --region`: AWS region (default: from AWS_REGION env or us-east-1)
- `-e, --events`: Show recent stack events
- `-R, --resources`: Show stack resources
- `-o, --outputs`: Show stack outputs (default: enabled)
- `-p, --parameters`: Show stack parameters
- `-i, --instances`: Show EC2 instance information
- `-d, --database`: Show RDS database information
- `-a, --all`: Show all information
- `-h, --help`: Show help message

### `create-key-pair.sh`
Create EC2 key pairs for SSH access to your instances.

**Usage:**
```bash
utils/create-key-pair.sh -k wordpress-keypair -r us-east-1
```

**Options:**
- `-k, --key-pair`: EC2 Key Pair name (default: wordpress-keypair)
- `-r, --region`: AWS region (default: from AWS_REGION env or us-east-1)
- `-h, --help`: Show help message

**Note:** The script will save the private key to `./<key-pair-name>.pem` in the current directory. Keep this file secure!

### `troubleshoot-wordpress.sh`
Get troubleshooting guidance and diagnostic commands for WordPress issues.

**Usage:**
```bash
utils/troubleshoot-wordpress.sh -s wordpress-dev
utils/troubleshoot-wordpress.sh -s wordpress-prod -r us-west-2
```

**Options:**
- `-s, --stack-name`: CloudFormation stack name (default: wordpress-dev)
- `-r, --region`: AWS region (default: from AWS_REGION env or us-east-1)
- `-h, --help`: Show help message

The script provides:
- Stack status and health checks
- Instance information and SSH commands
- Load balancer DNS and health check status
- Database endpoint information
- Troubleshooting commands for common issues

## Testing
This repository includes a comprehensive test suite using [bats-core](https://github.com/bats-core/bats-core) for testing bash scripts.

### Quick Start
1. **Install testing dependencies:**
   ```bash
   ./setup-bats.sh
   ```

2. **Run tests:**
   ```bash
   # Run all tests
   ./run-tests.sh --all
   
   # Run specific test categories
   ./run-tests.sh --unit
   ./run-tests.sh --integration
   ./run-tests.sh --performance
   ```

### Test Coverage
The test suite includes three categories:

1. **Unit Tests** (`tests/unit/`)
   - Core functions in `_common.sh` (password generation, AWS operations, validation)
   - Script argument parsing for all deployment and utility scripts
   - AWS CLI mocking for testing without real AWS credentials
   - Error handling and edge cases

2. **Integration Tests** (`tests/integration/`)
   - End-to-end deployment validation
   - Stack creation and resource verification
   - WordPress accessibility and functionality
   - Database connectivity
   - Load balancer configuration

3. **Performance Tests** (`tests/performance/`)
   - Response time validation
   - Load testing with Apache Bench (ab)
   - Auto-scaling trigger validation
   - Sustained load testing
   - Recovery testing after load

**Test Status Badges:**
The README automatically displays test status badges that are updated after each test run. The badges show the pass/fail status for each test category.

For detailed testing documentation, see [TESTING.md](TESTING.md).

## Support
For issues or questions:
1. Check AWS CloudFormation console for stack events
2. Review CloudWatch logs for Lambda function
3. Verify all prerequisites are met
4. Check AWS service limits in your account
