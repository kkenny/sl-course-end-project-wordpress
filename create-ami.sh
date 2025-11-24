#!/bin/bash

# Script to create an AMI from a WordPress instance
# This script should be run after the WordPress instance is set up and configured

set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source common functions
source "${SCRIPT_DIR}/_common.sh"

# Initialize variables for command-line arguments
STACK_NAME=""
REGION=""
AMI_NAME_PREFIX=""
AMI_DESCRIPTION=""

# Parse command-line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -s|--stack-name)
            STACK_NAME="$2"
            shift 2
            ;;
        -r|--region)
            REGION="$2"
            shift 2
            ;;
        -n|--name-prefix)
            AMI_NAME_PREFIX="$2"
            shift 2
            ;;
        -d|--description)
            AMI_DESCRIPTION="$2"
            shift 2
            ;;
        -h|--help)
            echo "Usage: $0 [-s|--stack-name STACK_NAME] [-r|--region REGION] [-n|--name-prefix PREFIX] [-d|--description DESCRIPTION]"
            echo ""
            echo "Options:"
            echo "  -s, --stack-name      CloudFormation stack name (required)"
            echo "  -r, --region          AWS region (default: from AWS_REGION env or us-east-1)"
            echo "  -n, --name-prefix     AMI name prefix (default: auto-detected from stack name)"
            echo "  -d, --description     AMI description (default: auto-generated)"
            echo "  -h, --help            Show this help message"
            echo ""
            echo "Examples:"
            echo "  $0 -s wordpress-dev"
            echo "  $0 -s wordpress-prod -r us-west-2"
            echo "  $0 -s wordpress-dev -n my-wordpress -d 'Custom AMI description'"
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            echo "Use -h or --help for usage information"
            exit 1
            ;;
    esac
done

# Configuration
STACK_NAME="${STACK_NAME:-wordpress-dev}"
REGION="${REGION:-${AWS_REGION:-us-east-1}}"

# Detect environment from stack name if not set
if [[ "$STACK_NAME" == *"prod"* ]] || [[ "$STACK_NAME" == *"Prod"* ]] || [[ "$STACK_NAME" == *"PROD"* ]]; then
    ENVIRONMENT="Production"
    AMI_NAME_PREFIX="${AMI_NAME_PREFIX:-wordpress-prod-instance}"
    AMI_DESCRIPTION="${AMI_DESCRIPTION:-WordPress Production instance AMI}"
else
    ENVIRONMENT="Development"
    AMI_NAME_PREFIX="${AMI_NAME_PREFIX:-wordpress-dev-instance}"
    AMI_DESCRIPTION="${AMI_DESCRIPTION:-WordPress Development instance AMI}"
fi

echo -e "${BLUE}WordPress AMI Creation Script${NC}"
echo "=================================="
echo -e "${YELLOW}Environment: $ENVIRONMENT${NC}"
echo -e "${YELLOW}Stack: $STACK_NAME${NC}"
echo -e "${YELLOW}Region: $REGION${NC}"
echo ""

# Check AWS credentials
echo -e "${YELLOW}Checking AWS credentials...${NC}"
if ! aws sts get-caller-identity &> /dev/null; then
    echo -e "${RED}Error: AWS credentials not configured. Please run 'aws configure'${NC}"
    exit 1
fi

AWS_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
echo -e "${GREEN}AWS Account: $AWS_ACCOUNT${NC}"
echo ""

# Get the instance ID from the Auto Scaling Group
echo -e "${YELLOW}Finding WordPress instance from Auto Scaling Group...${NC}"
ASG_NAME=$(aws cloudformation describe-stacks \
    --stack-name "$STACK_NAME" \
    --region "$REGION" \
    --query "Stacks[0].Outputs[?OutputKey=='AutoScalingGroupName'].OutputValue" \
    --output text 2>/dev/null || echo "")

if [ -z "$ASG_NAME" ]; then
    echo -e "${RED}Error: Could not find Auto Scaling Group. Is the stack '$STACK_NAME' deployed?${NC}"
    exit 1
fi

echo "Auto Scaling Group: $ASG_NAME"

# Get instance ID from Auto Scaling Group
INSTANCE_ID=$(aws autoscaling describe-auto-scaling-groups \
    --auto-scaling-group-names "$ASG_NAME" \
    --region "$REGION" \
    --query "AutoScalingGroups[0].Instances[0].InstanceId" \
    --output text 2>/dev/null || echo "")

if [ -z "$INSTANCE_ID" ] || [ "$INSTANCE_ID" == "None" ]; then
    echo -e "${RED}Error: No running instances found in Auto Scaling Group.${NC}"
    echo -e "${YELLOW}Note: You may need to ensure at least one instance is running.${NC}"
    exit 1
fi

echo "Instance ID: $INSTANCE_ID"

# Check instance state
INSTANCE_STATE=$(aws ec2 describe-instances \
    --instance-ids "$INSTANCE_ID" \
    --region "$REGION" \
    --query "Reservations[0].Instances[0].State.Name" \
    --output text)

if [ "$INSTANCE_STATE" != "running" ]; then
    echo -e "${YELLOW}Warning: Instance is in '$INSTANCE_STATE' state. Starting instance...${NC}"
    aws ec2 start-instances --instance-ids "$INSTANCE_ID" --region "$REGION"
    
    echo "Waiting for instance to be running..."
    aws ec2 wait instance-running --instance-ids "$INSTANCE_ID" --region "$REGION"
    sleep 30  # Additional wait for instance to be fully ready
fi

# Get current timestamp for AMI name
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
AMI_NAME="${AMI_NAME_PREFIX}-${TIMESTAMP}"

echo -e "${YELLOW}Creating AMI: $AMI_NAME${NC}"
echo "This may take several minutes..."

# Create the AMI
AMI_ID=$(aws ec2 create-image \
    --instance-id "$INSTANCE_ID" \
    --name "$AMI_NAME" \
    --description "$AMI_DESCRIPTION" \
    --region "$REGION" \
    --no-reboot \
    --query 'ImageId' \
    --output text)

if [ -z "$AMI_ID" ]; then
    echo -e "${RED}Error: Failed to create AMI${NC}"
    exit 1
fi

echo -e "${GREEN}AMI creation initiated successfully!${NC}"
echo "AMI ID: $AMI_ID"
echo "AMI Name: $AMI_NAME"

# Wait for AMI to be available
echo -e "${YELLOW}Waiting for AMI to be available (this may take 10-15 minutes)...${NC}"
aws ec2 wait image-available --image-ids "$AMI_ID" --region "$REGION"

echo -e "${GREEN}AMI is now available!${NC}"
echo ""
echo "AMI Details:"
echo "  AMI ID: $AMI_ID"
echo "  AMI Name: $AMI_NAME"
echo "  Region: $REGION"
echo ""
echo "You can now use this AMI ID in your Launch Template: $AMI_ID"
echo ""
echo "To update the Launch Template with this AMI, run:"
echo "  aws ec2 create-launch-template-version \\"
echo "    --launch-template-id <LaunchTemplateId> \\"
echo "    --source-version \$Latest \\"
echo "    --launch-template-data '{\"ImageId\":\"$AMI_ID\"}'"

# Save AMI ID to a file for reference
echo "$AMI_ID" > .ami-id.txt
echo "$AMI_NAME" > .ami-name.txt
echo -e "${GREEN}AMI ID saved to .ami-id.txt${NC}"

