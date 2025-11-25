#!/bin/bash

# Script to update the Launch Template with a new AMI ID
# This should be run after creating an AMI using create-ami.sh

set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source common functions
source "${SCRIPT_DIR}/_common.sh"

# Initialize variables for command-line arguments
STACK_NAME=""
REGION=""
AMI_ID=""
AMI_ID_FILE=""

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
        -a|--ami-id)
            AMI_ID="$2"
            shift 2
            ;;
        -f|--ami-file)
            AMI_ID_FILE="$2"
            shift 2
            ;;
        -h|--help)
            echo "Usage: $0 [-s|--stack-name STACK_NAME] [-r|--region REGION] [-a|--ami-id AMI_ID] [-f|--ami-file FILE]"
            echo ""
            echo "Options:"
            echo "  -s, --stack-name      CloudFormation stack name (default: wordpress-dev)"
            echo "  -r, --region          AWS region (default: from AWS_REGION env or us-east-1)"
            echo "  -a, --ami-id          AMI ID to use (if not provided, will read from file or prompt)"
            echo "  -f, --ami-file        File containing AMI ID (default: .ami-id.txt)"
            echo "  -h, --help            Show this help message"
            echo ""
            echo "Examples:"
            echo "  $0 -s wordpress-dev"
            echo "  $0 -s wordpress-prod -a ami-12345678"
            echo "  $0 -s wordpress-dev -f custom-ami-id.txt"
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
AMI_ID_FILE="${AMI_ID_FILE:-.ami-id.txt}"

echo -e "${BLUE}Update Launch Template with AMI${NC}"
echo "================================"
echo -e "${YELLOW}Stack: $STACK_NAME${NC}"
echo -e "${YELLOW}Region: $REGION${NC}"
echo ""

# Check AWS credentials
echo -e "${YELLOW}Checking AWS credentials...${NC}"
if ! check_aws_credentials; then
    exit 1
fi

get_aws_account
echo ""

# Get AMI ID
if [ -z "$AMI_ID" ]; then
    if [ -f "$AMI_ID_FILE" ]; then
        AMI_ID=$(cat "$AMI_ID_FILE")
        echo -e "${GREEN}Found AMI ID from file ($AMI_ID_FILE): $AMI_ID${NC}"
    else
        echo -e "${YELLOW}AMI ID file not found: $AMI_ID_FILE${NC}"
        read -p "Enter AMI ID: " AMI_ID
    fi
else
    echo -e "${GREEN}Using AMI ID from command line: $AMI_ID${NC}"
fi

if [ -z "$AMI_ID" ]; then
    echo -e "${RED}Error: AMI ID is required${NC}"
    exit 1
fi

# Verify AMI exists
echo -e "${YELLOW}Verifying AMI exists...${NC}"
AMI_STATE=$(aws ec2 describe-images \
    --image-ids "$AMI_ID" \
    --region "$REGION" \
    --query "Images[0].State" \
    --output text 2>/dev/null || echo "invalid")

if [ "$AMI_STATE" != "available" ]; then
    echo -e "${RED}Error: AMI '$AMI_ID' is not available (state: ${AMI_STATE:-not found})${NC}"
    echo -e "${YELLOW}Make sure the AMI ID is correct and exists in region '$REGION'${NC}"
    exit 1
fi

echo -e "${GREEN}AMI is available${NC}"
echo ""

# Get Launch Template ID from CloudFormation stack
echo -e "${YELLOW}Finding Launch Template...${NC}"
LAUNCH_TEMPLATE_ID=$(aws cloudformation describe-stack-resources \
    --stack-name "$STACK_NAME" \
    --region "$REGION" \
    --logical-resource-id WordPressLaunchTemplate \
    --query "StackResources[0].PhysicalResourceId" \
    --output text 2>/dev/null || echo "")

if [ -z "$LAUNCH_TEMPLATE_ID" ] || [ "$LAUNCH_TEMPLATE_ID" == "None" ]; then
    echo -e "${RED}Error: Could not find Launch Template in stack '$STACK_NAME'${NC}"
    echo -e "${YELLOW}Make sure the stack exists and contains a Launch Template resource.${NC}"
    exit 1
fi

echo -e "${GREEN}Launch Template ID: $LAUNCH_TEMPLATE_ID${NC}"

# Get current launch template data
echo -e "${YELLOW}Getting current Launch Template configuration...${NC}"
CURRENT_VERSION=$(aws ec2 describe-launch-template-versions \
    --launch-template-id "$LAUNCH_TEMPLATE_ID" \
    --region "$REGION" \
    --query "LaunchTemplateVersions[0].VersionNumber" \
    --output text)

echo -e "${GREEN}Current version: $CURRENT_VERSION${NC}"

# Update the ImageId in the launch template data
echo -e "${YELLOW}Creating new Launch Template version with AMI: $AMI_ID${NC}"

# Create a new version with updated AMI
if ! aws ec2 create-launch-template-version \
    --launch-template-id "$LAUNCH_TEMPLATE_ID" \
    --region "$REGION" \
    --source-version "$CURRENT_VERSION" \
    --launch-template-data "{\"ImageId\":\"$AMI_ID\"}" \
    > /dev/null 2>&1; then
    echo -e "${RED}Error: Failed to create new Launch Template version${NC}"
    exit 1
fi

# Get the new version number
NEW_VERSION=$(aws ec2 describe-launch-template-versions \
    --launch-template-id "$LAUNCH_TEMPLATE_ID" \
    --region "$REGION" \
    --query "LaunchTemplateVersions[0].VersionNumber" \
    --output text)

echo -e "${GREEN}New Launch Template version created: $NEW_VERSION${NC}"

# Set as default version
echo -e "${YELLOW}Setting new version as default...${NC}"
if ! aws ec2 modify-launch-template \
    --launch-template-id "$LAUNCH_TEMPLATE_ID" \
    --region "$REGION" \
    --default-version "$NEW_VERSION" \
    > /dev/null 2>&1; then
    echo -e "${RED}Error: Failed to set new version as default${NC}"
    exit 1
fi

echo -e "${GREEN}Launch Template updated successfully!${NC}"
echo ""
echo "The Auto Scaling Group will use the new AMI for any new instances."
echo "Existing instances will continue running with the old AMI."
echo ""
echo "To force new instances to use the new AMI, you can:"
echo "  1. Update the Auto Scaling Group desired capacity"
echo "  2. Or terminate existing instances (they will be replaced with new ones)"

