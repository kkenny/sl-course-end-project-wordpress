# SimpliLearn Course End Project: Set Up and Monitor a WordPress Instance

## Objectives
To set up and monitoring a WordPress instance for your organization is to establish a reliable and secure online presence that supports your business or organizational goals.

## Relevance
In this project, several skills and tools are utilized, each serving a specific purpose within the industry:
AWS console – The AWS Management Console is a web application that includes and references several service consoles for managing AWS services.
- AWS CloudFormation – It is a service that aids users in modeling and configuring their AWS resources so they can focus more on their AWS-based apps and spend less time maintaining those resources.
- EC2 Instance - Amazon EC2 provides a large set of instance types that are customized to certain use cases.

## Problem Statement
You are given a project. You should be able to configure a WordPress instance using AWS CloudFormation and monitor the instance

### Real-World Scenario
Your organization publishes blogs and provides documentation services for other businesses and technologies. You have been asked to:
- Set up a **live production WordPress instance** to publish blogs (runs 24/7)
- Set up a **separate development WordPress instance** for development and testing purposes so that any work done on this instance will not impact the live blog
- Configure the **development WordPress instance** to be available only during business hours (9 AM–6 PM) with automatic shutdown outside these hours

## Tasks
1. Create a CloudFormation stack
2. Create an AMI of the WordPress instance
3. Configure Auto Scaling to launch a new WordPress instance
4. Configure the new WordPress instance to shut down automatically

## Solution Implementation

This repository contains a complete solution for deploying and managing **two separate WordPress environments** on AWS:

1. **Production Environment** - Runs 24/7 for live blog publishing
2. **Development Environment** - Auto-shuts down outside business hours for cost optimization

### Key Features:

### Components

1. **CloudFormation Template** (`wordpress-stack.yaml`)
   - Complete infrastructure setup including VPC, subnets, security groups
   - EC2 instances with WordPress installation
   - RDS MySQL database for WordPress
   - Auto Scaling Group configuration
   - Application Load Balancer
   - **Conditional Lambda function** for automatic shutdown/startup (Development only)
   - **Conditional EventBridge rule** for scheduled checks (Development only)
   - Environment-aware resource naming and tagging

2. **Production Deployment Script** (`deploy-prod.sh`)
   - Deploys production environment (24/7)
   - Interactive parameter collection
   - Automatic AMI discovery for the region
   - No auto-shutdown configuration

3. **Development Deployment Script** (`deploy-dev.sh`)
   - Deploys development environment with auto-shutdown
   - Interactive parameter collection including business hours
   - Automatic AMI discovery for the region
   - Configures Lambda and EventBridge for scheduled shutdown

4. **AMI Creation Script** (`create-ami.sh`)
   - Creates an AMI from the running WordPress instance
   - Automatically detects environment (prod/dev) from stack name
   - Automatically finds the instance from the Auto Scaling Group
   - Saves AMI ID for later use

5. **Launch Template Update Script** (`update-launch-template-with-ami.sh`)
   - Updates the Launch Template with a new AMI ID
   - Ensures new instances use the latest AMI

## Prerequisites

1. **AWS Account** with appropriate permissions
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
5. **Basic knowledge** of AWS services (EC2, CloudFormation, Auto Scaling)

## Quick Start Guide

### Step 1: Deploy the Production Environment (24/7)

Deploy the production environment for your live blog:

```bash
./deploy-prod.sh
```

The script will:
- Check AWS credentials
- Find the latest Amazon Linux 2 AMI for your region
- Prompt for required parameters:
  - EC2 Key Pair Name
  - WordPress Admin Password (min 8 characters)
  - WordPress Admin Email
  - WordPress Admin Username
  - Instance Type (default: t3.medium)

**Note:** Production environment runs 24/7 with no auto-shutdown.

### Step 2: Deploy the Development Environment (Auto-Shutdown)

Deploy the development environment for testing:

```bash
./deploy-dev.sh
```

The script will:
- Check AWS credentials
- Find the latest Amazon Linux 2 AMI for your region
- Prompt for required parameters:
  - EC2 Key Pair Name
  - WordPress Admin Password (min 8 characters)
  - WordPress Admin Email
  - WordPress Admin Username
  - Instance Type (default: t3.micro)
  - Business Hours Start (default: 09:00 UTC)
  - Business Hours End (default: 18:00 UTC)

**Note:** Development environment automatically shuts down outside business hours.

**Deployment takes approximately 15-20 minutes per environment.**

### Step 3: Access WordPress

After deployment completes for each environment:
1. Wait 2-3 minutes for WordPress installation to finish
2. Access the WordPress URL from the stack outputs
3. Complete the WordPress setup wizard

**Production URL:** Available 24/7  
**Development URL:** Available during business hours only (auto-starts/stops)

### Step 4: Create an AMI of the WordPress Instance

Once your WordPress instance is configured and ready, create an AMI:

**For Production:**
```bash
STACK_NAME=wordpress-prod ./create-ami.sh
```

**For Development:**
```bash
STACK_NAME=wordpress-dev ./create-ami.sh
```

Or use the default (development):
```bash
./create-ami.sh
```

This script will:
- Automatically detect the environment from stack name
- Find the WordPress instance from the Auto Scaling Group
- Create an AMI (takes 10-15 minutes)
- Save the AMI ID to `.ami-id.txt` for reference

### Step 5: Update Launch Template with AMI

After the AMI is created, update the Launch Template to use it:

```bash
./update-launch-template-with-ami.sh
```

This ensures that any new instances launched by Auto Scaling will use your custom AMI.

## Task Completion

### ✅ Task 1: Create a CloudFormation Stack
**Completed** - The `wordpress-stack.yaml` template creates a complete stack with:
- VPC with public subnets
- Security groups
- RDS MySQL database
- EC2 instances with WordPress
- Auto Scaling Group
- Load Balancer
- Lambda function for automation

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

**Key Differences:**
- **Production:** Always running, no Lambda/EventBridge
- **Development:** Lambda function monitors and shuts down instances outside business hours

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

To delete all resources and avoid charges:

```bash
aws cloudformation delete-stack --stack-name wordpress-stack
```

**Note:** This will delete all resources including the database. Ensure you have backups if needed.

## Cost Optimization

- RDS instance uses `db.t3.micro` (eligible for free tier)
- EC2 instances can use `t3.micro` for testing (free tier eligible)
- Auto-shutdown feature reduces costs by stopping instances outside business hours
- Consider using Reserved Instances for production workloads

## Additional Notes

- All times are in UTC - adjust business hours accordingly
- The AMI ID in the template may need to be updated for your specific region
- For production use, consider:
  - Using HTTPS with SSL certificates
  - Restricting SSH access to specific IPs
  - Enabling CloudWatch alarms
  - Setting up automated backups
  - Using Multi-AZ RDS for high availability

## Support

For issues or questions:
1. Check AWS CloudFormation console for stack events
2. Review CloudWatch logs for Lambda function
3. Verify all prerequisites are met
4. Check AWS service limits in your account