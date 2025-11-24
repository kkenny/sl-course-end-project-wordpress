#!/bin/bash

# Deployment script for WordPress Production Environment (24/7)

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
INSTANCE_TYPE="t3.medium"

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
        -t|--instance-type)
            INSTANCE_TYPE="$2"
            shift 2
            ;;
        -h|--help)
            echo "Usage: $0 [-s|--stack-name STACK_NAME] [-u|--username USERNAME] [-e|--email EMAIL] [-k|--key-pair KEY_PAIR] [-r|--region REGION] [-t|--instance-type TYPE] [-p|--prompt-password]"
            echo ""
            echo "Options:"
            echo "  -s, --stack-name       Set the CloudFormation stack name (default: wordpress-prod)"
            echo "  -u, --username         Set the WordPress admin username (default: admin)"
            echo "  -e, --email            Set the WordPress admin email address"
            echo "  -k, --key-pair         Set the EC2 Key Pair name"
            echo "  -r, --region           Set the AWS region (default: from AWS_REGION env or us-east-1)"
            echo "  -t, --instance-type    Set the EC2 instance type (default: $INSTANCE_TYPE)"
            echo "  -p, --prompt-password  Prompt for password (default: auto-generate and save to .creds-\${STACK_NAME})"
            echo "  -h, --help             Show this help message"
            echo ""
            echo "Examples:"
            echo "  $0 -s wordpress-prod"
            echo "  $0 -s wordpress-prod -t t3.large"
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
STACK_NAME="${STACK_NAME:-wordpress-prod}"
TEMPLATE_FILE="${TEMPLATE_FILE:-wordpress-stack.yaml}"
REGION="${REGION:-${AWS_REGION:-us-east-1}}"
ENVIRONMENT="Production"

echo -e "${BLUE}WordPress Production Environment Deployment${NC}"
echo "=============================================="
echo -e "${GREEN}Environment: Production (24/7)${NC}"
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
if ! aws sts get-caller-identity &> /dev/null; then
    echo -e "${RED}Error: AWS credentials not configured. Please run 'aws configure'${NC}"
    exit 1
fi

AWS_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
echo -e "${GREEN}AWS Account: $AWS_ACCOUNT${NC}"
echo -e "${GREEN}Region: $REGION${NC}"

# Get required parameters
echo ""
echo -e "${YELLOW}Please provide the following information:${NC}"

# Key Pair
if [ -z "$KEY_PAIR_NAME" ]; then
    echo -e "${BLUE}Checking available Key Pairs in region '$REGION'...${NC}"
    
    # Get list of key pairs
    KEY_PAIRS=$(aws ec2 describe-key-pairs --region "$REGION" --query 'KeyPairs[*].KeyName' --output text 2>/dev/null || echo "")
    
    if [ -z "$KEY_PAIRS" ]; then
        echo -e "${RED}Error: No Key Pairs found in region '$REGION'${NC}"
        echo -e "${YELLOW}Please create a Key Pair first using:${NC}"
        echo "  ./create-key-pair.sh -k <key-name> -r $REGION"
        exit 1
    fi
    
    # Count key pairs (handle case where there's only one)
    KEY_PAIR_COUNT=$(echo "$KEY_PAIRS" | wc -w | tr -d ' ')
    
    if [ "$KEY_PAIR_COUNT" -eq 1 ]; then
        # Only one key pair - use it automatically
        KEY_PAIR_NAME="$KEY_PAIRS"
        echo -e "${GREEN}Found one Key Pair: $KEY_PAIR_NAME${NC}"
        echo -e "${GREEN}Using Key Pair: $KEY_PAIR_NAME${NC}"
    else
        # Multiple key pairs - present options
        echo -e "${BLUE}Available Key Pairs:${NC}"
        echo ""
        KEY_PAIR_ARRAY=($KEY_PAIRS)
        for i in "${!KEY_PAIR_ARRAY[@]}"; do
            echo "  $((i+1)). ${KEY_PAIR_ARRAY[$i]}"
        done
        echo ""
        
        while true; do
            read -p "Select Key Pair (1-$KEY_PAIR_COUNT) or enter name: " SELECTION
            
            # Check if it's a number
            if [[ "$SELECTION" =~ ^[0-9]+$ ]]; then
                if [ "$SELECTION" -ge 1 ] && [ "$SELECTION" -le "$KEY_PAIR_COUNT" ]; then
                    KEY_PAIR_NAME="${KEY_PAIR_ARRAY[$((SELECTION-1))]}"
                    echo -e "${GREEN}Selected Key Pair: $KEY_PAIR_NAME${NC}"
                    break
                else
                    echo -e "${RED}Invalid selection. Please enter a number between 1 and $KEY_PAIR_COUNT${NC}"
                fi
            else
                # User entered a name directly - validate it exists
                if echo "$KEY_PAIRS" | grep -q "^$SELECTION$"; then
                    KEY_PAIR_NAME="$SELECTION"
                    echo -e "${GREEN}Selected Key Pair: $KEY_PAIR_NAME${NC}"
                    break
                else
                    echo -e "${RED}Key Pair '$SELECTION' not found. Please try again.${NC}"
                fi
            fi
        done
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

# Instance Type - Use default if not provided via command line
echo ""
echo -e "${YELLOW}Instance Configuration:${NC}"
echo -e "${GREEN}Instance Type: $INSTANCE_TYPE${NC}"
echo -e "${BLUE}(Use -t or --instance-type to override)${NC}"

# Get the latest Amazon Linux 2 AMI ID for the region
echo ""
echo -e "${YELLOW}Finding latest Amazon Linux 2 AMI...${NC}"
AMI_ID=$(aws ec2 describe-images \
    --owners amazon \
    --filters "Name=name,Values=amzn2-ami-hvm-*-x86_64-gp2" \
              "Name=state,Values=available" \
    --query "Images | sort_by(@, &CreationDate) | [-1].ImageId" \
    --output text \
    --region "$REGION")

if [ -z "$AMI_ID" ] || [ "$AMI_ID" == "None" ]; then
    echo -e "${YELLOW}Warning: Could not find Amazon Linux 2 AMI. Using default.${NC}"
    echo -e "${YELLOW}You may need to update the ImageId in the template manually.${NC}"
    AMI_ID="ami-0c55b159cbfafe1f0"  # Default (may need region-specific update)
else
    echo -e "${GREEN}Found AMI: $AMI_ID${NC}"
fi

# Update template with AMI ID
echo -e "${YELLOW}Updating template with region-specific AMI ID...${NC}"
# Find any AMI ID pattern in the template and replace it
if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS - replace any ami-xxxxxxxxxxxxxxxxx pattern
    sed -i '' "s/ami-[0-9a-f]\{17\}/$AMI_ID/g" "$TEMPLATE_FILE"
else
    # Linux - replace any ami-xxxxxxxxxxxxxxxxx pattern
    sed -i "s/ami-[0-9a-f]\{17\}/$AMI_ID/g" "$TEMPLATE_FILE"
fi
echo -e "${GREEN}Template updated with AMI: $AMI_ID${NC}"

# Check if stack exists
STACK_EXISTS=$(aws cloudformation describe-stacks \
    --stack-name "$STACK_NAME" \
    --region "$REGION" \
    2>/dev/null || echo "")

if [ -n "$STACK_EXISTS" ]; then
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
echo -e "${BLUE}Deploying CloudFormation stack for Production environment...${NC}"
echo "This may take 15-20 minutes..."
echo -e "${GREEN}Note: Production environment runs 24/7 (no auto-shutdown)${NC}"

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
  }
]
EOF

aws cloudformation ${OPERATION}-stack \
    --stack-name "$STACK_NAME" \
    --template-body file://"$TEMPLATE_FILE" \
    --parameters file://"$PARAMS_FILE" \
    --capabilities CAPABILITY_NAMED_IAM \
    --region "$REGION" \
    --tags Key=Project,Value=WordPress Key=Environment,Value=Production

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
    echo -e "${GREEN}WordPress Production URL:${NC}"
    WORDPRESS_URL=$(aws cloudformation describe-stacks \
        --stack-name "$STACK_NAME" \
        --region "$REGION" \
        --query "Stacks[0].Outputs[?OutputKey=='WordPressURL'].OutputValue" \
        --output text)
    
    echo "  $WORDPRESS_URL"
    echo ""
    echo -e "${GREEN}Production Environment Details:${NC}"
    echo "  - Runs 24/7 (no auto-shutdown)"
    echo "  - Suitable for live blog publishing"
    echo "  - High availability with Auto Scaling"
    echo ""
    echo -e "${GREEN}Next Steps:${NC}"
    echo "  1. Wait a few minutes for WordPress to finish installing"
    echo "  2. Access the WordPress URL above to complete the setup"
    echo "  3. Configure WordPress for your production blog"
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

