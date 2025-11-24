#!/bin/bash

# Script to destroy a CloudFormation stack

set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source common functions
source "${SCRIPT_DIR}/_common.sh"

# Initialize variables for command-line arguments
STACK_NAME=""
REGION=""

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
        -h|--help)
            echo "Usage: $0 [-s|--stack-name STACK_NAME] [-r|--region REGION]"
            echo ""
            echo "Options:"
            echo "  -s, --stack-name    CloudFormation stack name (required)"
            echo "  -r, --region        AWS region (default: from AWS_REGION env or us-east-1)"
            echo "  -h, --help           Show this help message"
            echo ""
            echo "Examples:"
            echo "  $0 -s wordpress-dev"
            echo "  $0 -s wordpress-prod -r us-west-2"
            exit 0
            ;;
        *)
            # Support legacy positional argument for backward compatibility
            if [ -z "$STACK_NAME" ]; then
                STACK_NAME="$1"
            else
                echo -e "${RED}Unknown option: $1${NC}"
                echo "Use -h or --help for usage information"
                exit 1
            fi
            shift
            ;;
    esac
done

# Configuration
STACK_NAME="${STACK_NAME:-wordpress-dev}"
REGION="${REGION:-${AWS_REGION:-us-east-1}}"

echo -e "${BLUE}CloudFormation Stack Destruction${NC}"
echo "===================================="
echo -e "${YELLOW}Stack Name: $STACK_NAME${NC}"
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

# Check if stack exists
STACK_EXISTS=$(aws cloudformation describe-stacks \
    --stack-name "$STACK_NAME" \
    --region "$REGION" \
    2>/dev/null || echo "")

if [ -z "$STACK_EXISTS" ]; then
    echo -e "${RED}Stack '$STACK_NAME' not found in region '$REGION'${NC}"
    exit 1
fi

# Destroy the stack
echo ""
echo -e "${BLUE}Destroying CloudFormation stack...${NC}"
aws cloudformation delete-stack --stack-name "$STACK_NAME" --region "$REGION"

echo ""
echo -e "${YELLOW}Waiting for stack to be deleted...${NC}"
if aws cloudformation wait stack-delete-complete --stack-name "$STACK_NAME" --region "$REGION" 2>&1; then
    echo ""
    echo -e "${GREEN}Stack deleted successfully!${NC}"
else
    echo ""
    echo -e "${RED}Failed to delete stack!${NC}"
    echo ""
    echo -e "${YELLOW}Stack Status:${NC}"
    aws cloudformation describe-stacks --stack-name "$STACK_NAME" --region "$REGION" --query "Stacks[0].StackStatus" --output text 2>/dev/null || echo "Stack not found"

    echo ""
    echo -e "${YELLOW}Recent Stack Events (showing failures):${NC}"
    aws cloudformation describe-stack-events --stack-name "$STACK_NAME" --region "$REGION" --query "StackEvents[?ResourceStatus=='CREATE_FAILED' || ResourceStatus=='UPDATE_FAILED' || ResourceStatus=='DELETE_FAILED'].{Time:Timestamp,Resource:LogicalResourceId,Status:ResourceStatus,Reason:ResourceStatusReason}" --output table --max-items 10 2>/dev/null || echo "Could not retrieve events"

    echo ""
    echo -e "${YELLOW}All Recent Events:${NC}"
    aws cloudformation describe-stack-events --stack-name "$STACK_NAME" --region "$REGION" --query "StackEvents[:10].{Time:Timestamp,Resource:LogicalResourceId,Status:ResourceStatus,Reason:ResourceStatusReason}" --output table 2>/dev/null || echo "Could not retrieve events"

    echo ""
    echo -e "${RED}Check the CloudFormation console for more details:${NC}"
    echo "  https://console.aws.amazon.com/cloudformation/home?region=${REGION}#/stacks"
    echo ""
    exit 1
fi

