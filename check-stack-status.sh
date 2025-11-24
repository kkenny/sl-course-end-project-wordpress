#!/bin/bash

# Script to check CloudFormation stack status and events

set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source common functions
source "${SCRIPT_DIR}/_common.sh"

# Configuration
STACK_NAME="${1:-wordpress-dev}"
REGION="${AWS_REGION:-us-east-2}"

echo -e "${BLUE}CloudFormation Stack Status Check${NC}"
echo "=================================="
echo "Stack Name: $STACK_NAME"
echo "Region: $REGION"
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

# Get stack status
echo -e "${YELLOW}Stack Status:${NC}"
STATUS=$(aws cloudformation describe-stacks \
    --stack-name "$STACK_NAME" \
    --region "$REGION" \
    --query "Stacks[0].StackStatus" \
    --output text)

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

