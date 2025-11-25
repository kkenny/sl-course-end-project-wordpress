#!/bin/bash

# Script to create an EC2 Key Pair

set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source common functions (go up one directory since we're in utils/)
source "${SCRIPT_DIR}/../_common.sh"

# Initialize variables for command-line arguments
KEY_PAIR_NAME=""
REGION=""

# Parse command-line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -k|--key-pair)
            KEY_PAIR_NAME="$2"
            shift 2
            ;;
        -r|--region)
            REGION="$2"
            shift 2
            ;;
        -h|--help)
            echo "Usage: $0 [-k|--key-pair KEY_PAIR_NAME] [-r|--region REGION]"
            echo ""
            echo "Options:"
            echo "  -k, --key-pair    Set the EC2 Key Pair name (default: wordpress-keypair)"
            echo "  -r, --region      Set the AWS region (default: from AWS_REGION env or us-east-1)"
            echo "  -h, --help        Show this help message"
            echo ""
            echo "Examples:"
            echo "  $0 -k my-keypair -r us-west-2"
            echo "  $0 --key-pair wordpress-keypair --region us-east-1"
            exit 0
            ;;
        *)
            # Support legacy positional argument for backward compatibility
            if [ -z "$KEY_PAIR_NAME" ]; then
                KEY_PAIR_NAME="$1"
            else
                echo -e "${RED}Unknown option: $1${NC}"
                echo "Use -h or --help for usage information"
                exit 1
            fi
            shift
            ;;
    esac
done

# Configuration with defaults
KEY_PAIR_NAME="${KEY_PAIR_NAME:-wordpress-keypair}"
REGION="${REGION:-${AWS_REGION:-us-east-1}}"

echo -e "${BLUE}EC2 Key Pair Creation${NC}"
echo "========================"
echo "Key Pair Name: $KEY_PAIR_NAME"
echo "Region: $REGION"
echo ""

# Check if key pair already exists
if aws ec2 describe-key-pairs \
    --key-names "$KEY_PAIR_NAME" \
    --region "$REGION" \
    --query 'KeyPairs[0].KeyName' \
    --output text \
    >/dev/null 2>&1; then
    echo -e "${YELLOW}Key Pair '$KEY_PAIR_NAME' already exists in region '$REGION'${NC}"
    echo ""
    read -p "Do you want to create a new one with a different name? (y/n): " CREATE_NEW
    if [ "$CREATE_NEW" != "y" ] && [ "$CREATE_NEW" != "Y" ]; then
        echo "Exiting..."
        exit 0
    fi
    read -p "Enter new Key Pair name: " KEY_PAIR_NAME
fi

# Create the key pair
echo -e "${YELLOW}Creating Key Pair...${NC}"
OUTPUT_FILE="${KEY_PAIR_NAME}.pem"

if aws ec2 create-key-pair \
    --key-name "$KEY_PAIR_NAME" \
    --region "$REGION" \
    --query 'KeyMaterial' \
    --output text > "$OUTPUT_FILE" 2>/dev/null; then
    
    # Set proper permissions
    chmod 400 "$OUTPUT_FILE"
    
    echo -e "${GREEN}Key Pair created successfully!${NC}"
    echo ""
    echo -e "${GREEN}Key Pair Details:${NC}"
    echo "  Name: $KEY_PAIR_NAME"
    echo "  Region: $REGION"
    echo "  Private Key File: $OUTPUT_FILE"
    echo ""
    echo -e "${YELLOW}Important:${NC}"
    echo "  - Save the private key file ($OUTPUT_FILE) in a secure location"
    echo "  - This is the only time you can download the private key"
    echo "  - Set proper permissions: chmod 400 $OUTPUT_FILE"
    echo "  - Use this key pair name when deploying: $KEY_PAIR_NAME"
    echo ""
    echo -e "${YELLOW}To use this key pair for SSH access:${NC}"
    echo "  ssh -i $OUTPUT_FILE ec2-user@<instance-ip>"
    echo ""
else
    echo -e "${RED}Failed to create Key Pair${NC}"
    exit 1
fi

