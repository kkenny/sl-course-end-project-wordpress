#!/bin/bash

# Deployment script for WordPress Development Environment (auto-shutdown)

set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source common functions
source "${SCRIPT_DIR}/_common.sh"

# Initialize variables for command-line arguments
WP_USER=""
WP_EMAIL=""
PROMPT_PASSWORD=false
KEY_PAIR_NAME=""
REGION=""
BUSINESS_START="17:00"
BUSINESS_END="06:00"
INSTANCE_TYPE="t3.micro"
AMI_ID=""
ALARM_EMAIL=""

# Parse command-line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -s|--stack-name)
            STACK_NAME="$2"
            shift 2
            ;;
        -u|--username)
            WP_USER="$2"
            shift 2
            ;;
        -e|--email)
            WP_EMAIL="$2"
            shift 2
            ;;
        -p|--prompt-password)
            PROMPT_PASSWORD=true
            shift
            ;;
        -k|--key-pair)
            KEY_PAIR_NAME="$2"
            shift 2
            ;;
        -r|--region)
            REGION="$2"
            shift 2
            ;;
        --business-start)
            BUSINESS_START="$2"
            shift 2
            ;;
        --business-end)
            BUSINESS_END="$2"
            shift 2
            ;;
        -t|--instance-type)
            INSTANCE_TYPE="$2"
            shift 2
            ;;
        -a|--ami-id)
            AMI_ID="$2"
            shift 2
            ;;
        --alarm-email)
            ALARM_EMAIL="$2"
            shift 2
            ;;
        -h|--help)
            echo "Usage: $0 [-s|--stack-name STACK_NAME] [-u|--username USERNAME] [-e|--email EMAIL] [-k|--key-pair KEY_PAIR] [-r|--region REGION] [-t|--instance-type TYPE] [-a|--ami-id AMI_ID] [--alarm-email EMAIL] [--business-start HH:MM] [--business-end HH:MM] [-p|--prompt-password]"
            echo ""
            echo "Options:"
            echo "  -s, --stack-name       Set the CloudFormation stack name (default: wordpress-dev)"
            echo "  -u, --username         Set the WordPress admin username (default: admin)"
            echo "  -e, --email            Set the WordPress admin email address"
            echo "  -k, --key-pair         Set the EC2 Key Pair name"
            echo "  -r, --region           Set the AWS region (default: from AWS_REGION env or us-east-1)"
            echo "  -t, --instance-type    Set the EC2 instance type (default: $INSTANCE_TYPE)"
            echo "  -a, --ami-id           Set the AMI ID to use (default: query AWS for latest)"
            echo "  --alarm-email          Set email address for CloudWatch alarm notifications (optional)"
            echo "  --business-start       Business hours start time in UTC (HH:MM format, default: $BUSINESS_START)"
            echo "  --business-end         Business hours end time in UTC (HH:MM format, default: $BUSINESS_END)"
            echo "  -p, --prompt-password  Prompt for password (default: auto-generate and save to .creds-\${STACK_NAME})"
            echo "  -h, --help             Show this help message"
            echo ""
            echo "Examples:"
            echo "  $0 -s wordpress-dev"
            echo "  $0 -s wordpress-dev --business-start 09:00 --business-end 18:00"
            echo "  $0 -s wordpress-dev -t t3.small"
            echo "  $0 -s wordpress-dev -a ami-12345678"
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
TEMPLATE_FILE="${TEMPLATE_FILE:-wordpress-stack.yaml}"
REGION="${REGION:-${AWS_REGION:-us-east-1}}"
ENVIRONMENT="Development"

echo -e "${BLUE}WordPress Development Environment Deployment${NC}"
echo "=============================================="
echo -e "${GREEN}Environment: Development (auto-shutdown outside business hours)${NC}"
echo ""

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    echo -e "${RED}Error: AWS CLI is not installed. Please install it first.${NC}"
    exit 1
fi

# Check if template file exists
if [ ! -f "$TEMPLATE_FILE" ]; then
    echo -e "${RED}Error: Template file '$TEMPLATE_FILE' not found.${NC}"
    exit 1
fi

# Check AWS credentials
echo -e "${YELLOW}Checking AWS credentials...${NC}"
if ! check_aws_credentials; then
    exit 1
fi

get_aws_account
echo -e "${GREEN}Region: $REGION${NC}"

# Get required parameters
echo ""
echo -e "${YELLOW}Please provide the following information:${NC}"

# Key Pair
if [ -z "$KEY_PAIR_NAME" ]; then
    echo -e "${BLUE}Checking available Key Pairs in region '$REGION'...${NC}"
    KEY_PAIR_NAME=$(auto_select_key_pair "$REGION")
    if [ $? -ne 0 ] || [ -z "$KEY_PAIR_NAME" ]; then
        exit 1
    fi
else
    echo -e "${GREEN}EC2 Key Pair Name: $KEY_PAIR_NAME (from command line)${NC}"
fi

# Validate Key Pair exists
echo -e "${YELLOW}Validating Key Pair...${NC}"
if ! validate_key_pair "$KEY_PAIR_NAME" "$REGION"; then
    exit 1
fi
echo -e "${GREEN}Key Pair validated successfully${NC}"
echo ""

# WordPress Admin Email
if [ -z "$WP_EMAIL" ]; then
    read -p "WordPress Admin Email [admin@example.com]: " WP_EMAIL
    WP_EMAIL=${WP_EMAIL:-admin@example.com}
else
    echo -e "${GREEN}WordPress Admin Email: $WP_EMAIL (from command line)${NC}"
fi

# WordPress Admin User
if [ -z "$WP_USER" ]; then
    read -p "WordPress Admin Username [admin]: " WP_USER
    WP_USER=${WP_USER:-admin}
else
    echo -e "${GREEN}WordPress Admin Username: $WP_USER (from command line)${NC}"
fi

# CloudWatch Alarm Email (optional)
if [ -z "$ALARM_EMAIL" ]; then
    read -p "CloudWatch Alarm Email (optional, press Enter to skip): " ALARM_EMAIL
    ALARM_EMAIL=${ALARM_EMAIL:-}
    if [ -n "$ALARM_EMAIL" ]; then
        echo -e "${GREEN}CloudWatch Alarm Email: $ALARM_EMAIL${NC}"
    else
        echo -e "${YELLOW}CloudWatch alarms will be created but no email notifications will be sent${NC}"
    fi
else
    echo -e "${GREEN}CloudWatch Alarm Email: $ALARM_EMAIL (from command line)${NC}"
fi

# WordPress Admin Password
if [ "$PROMPT_PASSWORD" = true ]; then
    # Prompt for password if flag is set
    read -sp "WordPress Admin Password (min 8 characters, press Enter to auto-generate): " WP_PASSWORD
    echo ""
    
    if [ -z "$WP_PASSWORD" ]; then
        echo -e "${YELLOW}Auto-generating secure password...${NC}"
        WP_PASSWORD=$(generate_password)
        echo -e "${GREEN}Generated Password: $WP_PASSWORD${NC}"
        echo -e "${YELLOW}Please save this password securely!${NC}"
        echo ""
    elif [ ${#WP_PASSWORD} -lt 8 ]; then
        echo -e "${RED}Error: Password must be at least 8 characters${NC}"
        exit 1
    fi
else
    # Auto-generate password without prompting
    echo -e "${YELLOW}Auto-generating secure password...${NC}"
    WP_PASSWORD=$(generate_password)
    echo -e "${GREEN}Generated Password: $WP_PASSWORD${NC}"
    echo ""
fi

# Save credentials to file
CREDS_FILE=".creds-${STACK_NAME}"
echo "Saving credentials to $CREDS_FILE..."
cat > "$CREDS_FILE" <<EOF
# WordPress Credentials for Stack: $STACK_NAME
# Generated: $(date)
STACK_NAME=$STACK_NAME
WORDPRESS_ADMIN_USER=$WP_USER
WORDPRESS_ADMIN_EMAIL=$WP_EMAIL
WORDPRESS_ADMIN_PASSWORD=$WP_PASSWORD
EOF
chmod 600 "$CREDS_FILE"
echo -e "${GREEN}Credentials saved to $CREDS_FILE${NC}"
echo -e "${YELLOW}Keep this file secure! It contains sensitive information.${NC}"
echo ""


# Instance Type - Use default if not provided via command line
echo ""
echo -e "${YELLOW}Instance Configuration:${NC}"
echo -e "${GREEN}Instance Type: $INSTANCE_TYPE${NC}"
echo -e "${BLUE}(Use -t or --instance-type to override)${NC}"

# Business Hours (in UTC) - Set defaults if not provided via command line
BUSINESS_START="${BUSINESS_START}"
BUSINESS_END="${BUSINESS_END}"

echo ""
echo -e "${YELLOW}Business Hours (in UTC) - Instances will auto-shutdown outside these hours:${NC}"
echo -e "${GREEN}Start Time: $BUSINESS_START${NC}"
echo -e "${GREEN}End Time: $BUSINESS_END${NC}"
echo -e "${BLUE}(Use --business-start and --business-end to override)${NC}"

# Get AMI ID - priority: command line > query AWS
echo ""
if [ -n "$AMI_ID" ]; then
    echo -e "${GREEN}Using AMI ID from command line: $AMI_ID${NC}"
else
    # Query AWS for latest Amazon Linux 2 AMI
    echo -e "${YELLOW}Finding latest Amazon Linux 2 AMI...${NC}"
    AMI_ID=$(get_latest_ami "$REGION")
    if [ -n "$AMI_ID" ]; then
        echo -e "${GREEN}Found AMI: $AMI_ID${NC}"
    fi
fi

# Update template with AMI ID
echo -e "${YELLOW}Updating template with region-specific AMI ID...${NC}"
if update_template_ami "$TEMPLATE_FILE" "$AMI_ID"; then
    echo -e "${GREEN}Template updated with AMI: $AMI_ID${NC}"
else
    echo -e "${RED}Failed to update template with AMI ID${NC}"
    exit 1
fi

# Check if stack exists
if check_stack_exists "$STACK_NAME" "$REGION"; then
    echo ""
    echo -e "${YELLOW}Stack '$STACK_NAME' already exists. Updating...${NC}"
    OPERATION="update"
else
    echo ""
    echo -e "${YELLOW}Creating new stack '$STACK_NAME'...${NC}"
    OPERATION="create"
fi

# Deploy the stack
echo ""
echo -e "${BLUE}Deploying CloudFormation stack for Development environment...${NC}"
echo "This may take 15-20 minutes..."
echo -e "${GREEN}Note: Development environment will auto-shutdown outside business hours${NC}"
echo -e "${GREEN}Business Hours: $BUSINESS_START - $BUSINESS_END UTC${NC}"

# Build parameters using a JSON file to handle special characters properly
PARAMS_FILE=$(mktemp)
cat > "$PARAMS_FILE" << EOF
[
  {
    "ParameterKey": "Environment",
    "ParameterValue": "${ENVIRONMENT}"
  },
  {
    "ParameterKey": "KeyPairName",
    "ParameterValue": "${KEY_PAIR_NAME}"
  },
  {
    "ParameterKey": "WordPressAdminPassword",
    "ParameterValue": "${WP_PASSWORD}"
  },
  {
    "ParameterKey": "WordPressAdminEmail",
    "ParameterValue": "${WP_EMAIL}"
  },
  {
    "ParameterKey": "WordPressAdminUser",
    "ParameterValue": "${WP_USER}"
  },
  {
    "ParameterKey": "InstanceType",
    "ParameterValue": "${INSTANCE_TYPE}"
  },
  {
    "ParameterKey": "BusinessHoursStart",
    "ParameterValue": "${BUSINESS_START}"
  },
  {
    "ParameterKey": "BusinessHoursEnd",
    "ParameterValue": "${BUSINESS_END}"
  },
  {
    "ParameterKey": "AlarmEmail",
    "ParameterValue": "${ALARM_EMAIL}"
  }
]
EOF

aws cloudformation ${OPERATION}-stack \
    --stack-name "$STACK_NAME" \
    --template-body file://"$TEMPLATE_FILE" \
    --parameters file://"$PARAMS_FILE" \
    --capabilities CAPABILITY_NAMED_IAM \
    --region "$REGION" \
    --tags Key=Project,Value=WordPress Key=Environment,Value=Development

# Clean up temporary parameters file
rm -f "$PARAMS_FILE"

echo ""
echo -e "${YELLOW}Waiting for stack ${OPERATION} to complete...${NC}"
if aws cloudformation wait stack-${OPERATION}-complete \
    --stack-name "$STACK_NAME" \
    --region "$REGION" 2>&1; then
    echo ""
    echo -e "${GREEN}Stack ${OPERATION} completed successfully!${NC}"
    echo ""
    
    # Get stack outputs
    echo -e "${BLUE}Stack Outputs:${NC}"
    aws cloudformation describe-stacks \
        --stack-name "$STACK_NAME" \
        --region "$REGION" \
        --query "Stacks[0].Outputs" \
        --output table
    
    echo ""
    echo -e "${GREEN}WordPress Development URL:${NC}"
    WORDPRESS_URL=$(aws cloudformation describe-stacks \
        --stack-name "$STACK_NAME" \
        --region "$REGION" \
        --query "Stacks[0].Outputs[?OutputKey=='WordPressURL'].OutputValue" \
        --output text)
    
    echo "  $WORDPRESS_URL"
    echo ""
    echo -e "${GREEN}Development Environment Details:${NC}"
    echo "  - Auto-shutdown outside business hours ($BUSINESS_START - $BUSINESS_END UTC)"
    echo "  - Suitable for development and testing"
    echo "  - Cost-optimized (instances stop when not in use)"
    echo ""
    echo -e "${GREEN}Next Steps:${NC}"
    echo "  1. Wait a few minutes for WordPress to finish installing"
    echo "  2. Access the WordPress URL above to complete the setup"
    echo "  3. Configure WordPress for development/testing"
    echo "  4. Run './create-ami.sh' to create an AMI after configuration"
    echo ""
else
    echo ""
    echo -e "${RED}Stack ${OPERATION} failed!${NC}"
    echo ""
    echo -e "${YELLOW}Stack Status:${NC}"
    aws cloudformation describe-stacks \
        --stack-name "$STACK_NAME" \
        --region "$REGION" \
        --query "Stacks[0].StackStatus" \
        --output text 2>/dev/null || echo "Stack not found"
    
    echo ""
    echo -e "${YELLOW}Recent Stack Events (showing failures):${NC}"
    aws cloudformation describe-stack-events \
        --stack-name "$STACK_NAME" \
        --region "$REGION" \
        --query "StackEvents[?ResourceStatus=='CREATE_FAILED' || ResourceStatus=='UPDATE_FAILED' || ResourceStatus=='DELETE_FAILED'].{Time:Timestamp,Resource:LogicalResourceId,Status:ResourceStatus,Reason:ResourceStatusReason}" \
        --output table \
        --max-items 10 2>/dev/null || echo "Could not retrieve events"
    
    echo ""
    echo -e "${YELLOW}All Recent Events:${NC}"
    aws cloudformation describe-stack-events \
        --stack-name "$STACK_NAME" \
        --region "$REGION" \
        --query "StackEvents[:10].{Time:Timestamp,Resource:LogicalResourceId,Status:ResourceStatus,Reason:ResourceStatusReason}" \
        --output table 2>/dev/null || echo "Could not retrieve events"
    
    echo ""
    echo -e "${RED}Check the CloudFormation console for more details:${NC}"
    echo "  https://console.aws.amazon.com/cloudformation/home?region=${REGION}#/stacks"
    echo ""
    exit 1
fi

