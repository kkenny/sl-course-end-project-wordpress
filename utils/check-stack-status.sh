#!/bin/bash

# Script to check CloudFormation stack status and events

set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source common functions (go up one directory since we're in utils/)
source "${SCRIPT_DIR}/../_common.sh"

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
            echo "  -s, --stack-name    CloudFormation stack name (default: wordpress-dev)"
            echo "  -r, --region        AWS region (default: from AWS_REGION env or us-east-1)"
            echo "  -h, --help          Show this help message"
            echo ""
            echo "Examples:"
            echo "  $0 -s wordpress-dev"
            echo "  $0 -s wordpress-prod -r us-west-2"
            echo "  $0 wordpress-dev  # Legacy positional argument support"
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

echo -e "${BLUE}CloudFormation Stack Status Check${NC}"
echo "=================================="
echo -e "${YELLOW}Stack Name: $STACK_NAME${NC}"
echo -e "${YELLOW}Region: $REGION${NC}"
echo ""

# Check AWS credentials
echo -e "${YELLOW}Checking AWS credentials...${NC}"
if ! check_aws_credentials; then
    exit 1
fi

get_aws_account
echo ""

# Check if stack exists
if ! check_stack_exists "$STACK_NAME" "$REGION"; then
    echo -e "${RED}Stack '$STACK_NAME' not found in region '$REGION'${NC}"
    exit 1
fi

# Get stack status
echo -e "${YELLOW}Stack Status:${NC}"
STATUS=$(get_stack_status "$STACK_NAME" "$REGION")

if [[ "$STATUS" == *"COMPLETE"* ]] && [[ "$STATUS" != *"ROLLBACK"* ]]; then
    echo -e "${GREEN}$STATUS${NC}"
else
    echo -e "${RED}$STATUS${NC}"
fi

echo ""
echo -e "${YELLOW}Stack Status Reason:${NC}"
REASON=$(aws cloudformation describe-stacks \
    --stack-name "$STACK_NAME" \
    --region "$REGION" \
    --query "Stacks[0].StackStatusReason" \
    --output text 2>/dev/null || echo "None")

if [ -n "$REASON" ] && [ "$REASON" != "None" ]; then
    echo "$REASON"
else
    echo "No reason provided"
fi

echo ""
echo -e "${YELLOW}Failed Resources:${NC}"
aws cloudformation describe-stack-events \
    --stack-name "$STACK_NAME" \
    --region "$REGION" \
    --query "StackEvents[?ResourceStatus=='CREATE_FAILED' || ResourceStatus=='UPDATE_FAILED' || ResourceStatus=='DELETE_FAILED'].{Time:Timestamp,Resource:LogicalResourceId,Status:ResourceStatus,Reason:ResourceStatusReason}" \
    --output table \
    --max-items 20 2>/dev/null || echo "No failed resources found"

echo ""
echo -e "${YELLOW}Recent Stack Events (last 20):${NC}"
aws cloudformation describe-stack-events \
    --stack-name "$STACK_NAME" \
    --region "$REGION" \
    --query "StackEvents[:20].{Time:Timestamp,Resource:LogicalResourceId,Status:ResourceStatus,Reason:ResourceStatusReason}" \
    --output table 2>/dev/null || echo "Could not retrieve events"

echo ""
echo -e "${BLUE}CloudFormation Console:${NC}"
echo "  https://console.aws.amazon.com/cloudformation/home?region=${REGION}#/stacks/stackinfo?stackId=$(aws cloudformation describe-stacks --stack-name "$STACK_NAME" --region "$REGION" --query "Stacks[0].StackId" --output text 2>/dev/null || echo '')"

