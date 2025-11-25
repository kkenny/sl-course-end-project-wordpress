#!/bin/bash

# Script to troubleshoot WordPress 500 errors

set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source common functions
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

echo -e "${BLUE}WordPress Troubleshooting${NC}"
echo "=========================="
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

# Get stack outputs
echo -e "${YELLOW}Getting stack information...${NC}"
ASG_NAME=$(aws cloudformation describe-stacks \
    --stack-name "$STACK_NAME" \
    --region "$REGION" \
    --query "Stacks[0].Outputs[?OutputKey=='AutoScalingGroupName'].OutputValue" \
    --output text 2>/dev/null || echo "")

if [ -z "$ASG_NAME" ]; then
    echo -e "${RED}Error: Could not find Auto Scaling Group in stack '$STACK_NAME'${NC}"
    exit 1
fi

echo "Auto Scaling Group: $ASG_NAME"

# Get instance ID
INSTANCE_ID=$(aws autoscaling describe-auto-scaling-groups \
    --auto-scaling-group-names "$ASG_NAME" \
    --region "$REGION" \
    --query "AutoScalingGroups[0].Instances[0].InstanceId" \
    --output text 2>/dev/null || echo "")

if [ -z "$INSTANCE_ID" ] || [ "$INSTANCE_ID" == "None" ]; then
    echo -e "${RED}Error: No running instances found in Auto Scaling Group${NC}"
    exit 1
fi

echo "Instance ID: $INSTANCE_ID"

# Check instance state
INSTANCE_STATE=$(aws ec2 describe-instances \
    --instance-ids "$INSTANCE_ID" \
    --region "$REGION" \
    --query "Reservations[0].Instances[0].State.Name" \
    --output text)

echo "Instance State: $INSTANCE_STATE"

if [ "$INSTANCE_STATE" != "running" ]; then
    echo -e "${YELLOW}Warning: Instance is not running. Current state: $INSTANCE_STATE${NC}"
    exit 1
fi

# Get instance public IP
PUBLIC_IP=$(aws ec2 describe-instances \
    --instance-ids "$INSTANCE_ID" \
    --region "$REGION" \
    --query "Reservations[0].Instances[0].PublicIpAddress" \
    --output text)

echo "Public IP: $PUBLIC_IP"
echo ""

# Get Load Balancer DNS
LB_DNS=$(aws cloudformation describe-stacks \
    --stack-name "$STACK_NAME" \
    --region "$REGION" \
    --query "Stacks[0].Outputs[?OutputKey=='LoadBalancerDNS'].OutputValue" \
    --output text 2>/dev/null || echo "")

if [ -n "$LB_DNS" ]; then
    echo -e "${GREEN}Load Balancer DNS: $LB_DNS${NC}"
    echo ""
fi

# Check HTTP service
echo -e "${YELLOW}Checking HTTP service status...${NC}"
echo "You can SSH into the instance and run these commands:"
echo ""
echo "  ssh -i <your-key.pem> ec2-user@$PUBLIC_IP"
echo ""
echo "Once connected, check:"
echo ""
echo "  1. Check if httpd is running:"
echo "     sudo systemctl status httpd"
echo ""
echo "  2. Check httpd error logs:"
echo "     sudo tail -50 /var/log/httpd/error_log"
echo ""
echo "  3. Check PHP errors:"
echo "     sudo tail -50 /var/log/httpd/error_log | grep -i php"
echo ""
echo "  4. Check file permissions:"
echo "     ls -la /var/www/html/"
echo "     sudo chown -R apache:apache /var/www/html"
echo "     sudo chmod -R 755 /var/www/html"
echo ""
echo "  5. Check WordPress configuration:"
echo "     cat /var/www/html/wp-config.php | grep DB_"
echo ""
echo "  6. Test database connection:"
echo "     mysql -h <db-endpoint> -u wordpress -p"
echo ""
echo "  7. Check if WordPress files exist:"
echo "     ls -la /var/www/html/ | head -20"
echo ""
echo "  8. Restart httpd:"
echo "     sudo systemctl restart httpd"
echo ""

# Get database endpoint
DB_ENDPOINT=$(aws cloudformation describe-stacks \
    --stack-name "$STACK_NAME" \
    --region "$REGION" \
    --query "Stacks[0].Outputs[?OutputKey=='DatabaseEndpoint'].OutputValue" \
    --output text 2>/dev/null || echo "")

if [ -n "$DB_ENDPOINT" ]; then
    echo -e "${YELLOW}Database Endpoint: $DB_ENDPOINT${NC}"
    echo ""
fi

# Check CloudWatch Logs (if available)
echo -e "${YELLOW}Checking for CloudWatch Logs...${NC}"
echo "You can also check CloudWatch Logs for the instance:"
echo "  https://console.aws.amazon.com/cloudwatch/home?region=${REGION}#logsV2:log-groups"
echo ""

# Check Load Balancer target health
if [ -n "$LB_DNS" ]; then
    echo -e "${YELLOW}Checking Load Balancer target health...${NC}"
    TG_ARN=$(aws elbv2 describe-target-groups \
        --region "$REGION" \
        --query "TargetGroups[?contains(TargetGroupName, 'WP-TG')].TargetGroupArn" \
        --output text 2>/dev/null | head -1)
    
    if [ -n "$TG_ARN" ]; then
        echo "Target Group ARN: $TG_ARN"
        echo ""
        aws elbv2 describe-target-health \
            --target-group-arn "$TG_ARN" \
            --region "$REGION" \
            --output table 2>/dev/null || echo "Could not retrieve target health"
    fi
fi

echo ""
echo -e "${YELLOW}Common WordPress 500 Error Causes:${NC}"
echo "  1. WordPress files not fully downloaded/extracted"
echo "  2. Incorrect file permissions (should be apache:apache)"
echo "  3. Database connection issues"
echo "  4. PHP errors (check error_log)"
echo "  5. Missing WordPress files or incomplete installation"
echo "  6. wp-config.php misconfiguration"
echo ""
echo -e "${GREEN}Next Steps:${NC}"
echo "  1. SSH into the instance using the commands above"
echo "  2. Check the httpd error log for specific error messages"
echo "  3. Verify WordPress files are present and permissions are correct"
echo "  4. Test database connectivity"
echo "  5. Check if the user data script completed successfully"
echo ""

