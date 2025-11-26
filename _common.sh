#!/bin/bash

# Get the directory where this script is located (if not already set)
if [ -z "$SCRIPT_DIR" ]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi

# Get the directory where _common.sh is located (always use this for finding _set_profile.sh)
COMMON_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source profile (if _set_profile.sh exists in the same directory as _common.sh)
if [ -f "${COMMON_DIR}/_set_profile.sh" ]; then
    source "${COMMON_DIR}/_set_profile.sh"
fi

# Common Variables
# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Common functions for WordPress deployment scripts
# Function to generate random password
# RDS-compliant: Only printable ASCII except '/', '@', '"', and space
generate_password() {
    # Generate a random password between 12-16 characters
    # Contains: uppercase, lowercase, numbers, and RDS-compliant special characters
    # RDS allows: !#$%&*()_+-=[]{}|;:,.<>?~` (but NOT /, @, ", or space)
    local length=$((RANDOM % 5 + 12))  # Random length between 12-16
    local uppercase="ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    local lowercase="abcdefghijklmnopqrstuvwxyz"
    local numbers="0123456789"
    # RDS-compliant special characters (excluding /, @, ", space, and ^ which can cause issues)
    # Using a safe subset: !#$%&*()_+-=[]{}|;:,.<>?~
    local special="!#$%&*()_+-=[]{}|;:,.<>?~"
    local all_chars="${uppercase}${lowercase}${numbers}${special}"
    local password=""
    
    # Ensure at least one of each required character type
    password+="${uppercase:$((RANDOM % ${#uppercase})):1}"
    password+="${lowercase:$((RANDOM % ${#lowercase})):1}"
    password+="${numbers:$((RANDOM % ${#numbers})):1}"
    password+="${special:$((RANDOM % ${#special})):1}"
    
    # Fill the rest randomly
    while [ ${#password} -lt $length ]; do
        password+="${all_chars:$((RANDOM % ${#all_chars})):1}"
    done
    
    # Shuffle the password to randomize character positions
    if command -v shuf &> /dev/null; then
        # Linux
        echo "$password" | fold -w1 | shuf | tr -d '\n'
    else
        # macOS or other systems - use awk to shuffle
        echo "$password" | awk -v FS="" '{for(i=NF;i>1;i--){j=int(rand()*i+1);t=$i;$i=$j;$j=t}}1' | tr -d '\n'
    fi
}

# Function to validate EC2 Key Pair exists in the region
validate_key_pair() {
    local key_pair_name="$1"
    local region="${2:-us-east-1}"
    
    if [ -z "$key_pair_name" ]; then
        echo -e "${RED}Error: Key Pair Name is required${NC}" >&2
        return 1
    fi
    
    # Check if key pair exists
    if aws ec2 describe-key-pairs \
        --key-names "$key_pair_name" \
        --region "$region" \
        --query 'KeyPairs[0].KeyName' \
        --output text \
        >/dev/null 2>&1; then
        return 0
    else
        echo -e "${RED}Error: Key Pair '$key_pair_name' does not exist in region '$region'${NC}" >&2
        echo -e "${YELLOW}Available Key Pairs in region '$region':${NC}" >&2
        aws ec2 describe-key-pairs \
            --region "$region" \
            --query 'KeyPairs[*].KeyName' \
            --output table 2>/dev/null || echo "  (Could not retrieve key pairs)" >&2
        echo "" >&2
        echo -e "${YELLOW}To create a new Key Pair, run:${NC}" >&2
        echo "  aws ec2 create-key-pair --key-name $key_pair_name --region $region --query 'KeyMaterial' --output text > $key_pair_name.pem" >&2
        echo "  chmod 400 $key_pair_name.pem" >&2
        return 1
    fi
}

# Function to check AWS credentials
check_aws_credentials() {
    if ! aws sts get-caller-identity &> /dev/null; then
        echo -e "${RED}Error: AWS credentials not configured. Please run 'aws configure'${NC}" >&2
        return 1
    fi
    return 0
}

# Function to get and display AWS account
get_aws_account() {
    local aws_account
    aws_account=$(aws sts get-caller-identity --query Account --output text 2>/dev/null)
    if [ -n "$aws_account" ]; then
        echo -e "${GREEN}AWS Account: $aws_account${NC}"
        return 0
    else
        echo -e "${RED}Error: Could not retrieve AWS account${NC}" >&2
        return 1
    fi
}

# Function to check if a CloudFormation stack exists
check_stack_exists() {
    local stack_name="$1"
    local region="${2:-us-east-1}"
    
    if [ -z "$stack_name" ]; then
        echo -e "${RED}Error: Stack name is required${NC}" >&2
        return 1
    fi
    
    local stack_exists
    stack_exists=$(aws cloudformation describe-stacks \
        --stack-name "$stack_name" \
        --region "$region" \
        2>/dev/null || echo "")
    
    if [ -z "$stack_exists" ]; then
        return 1
    else
        return 0
    fi
}

# Function to get CloudFormation stack status
get_stack_status() {
    local stack_name="$1"
    local region="${2:-us-east-1}"
    
    if [ -z "$stack_name" ]; then
        echo -e "${RED}Error: Stack name is required${NC}" >&2
        return 1
    fi
    
    aws cloudformation describe-stacks \
        --stack-name "$stack_name" \
        --region "$region" \
        --query "Stacks[0].StackStatus" \
        --output text 2>/dev/null || echo ""
}

# Function to get latest Amazon Linux 2 AMI for a region
get_latest_ami() {
    local region="${1:-us-east-1}"
    local default_ami="${2:-ami-0c55b159cbfafe1f0}"
    
    local ami_id
    ami_id=$(aws ec2 describe-images \
        --owners amazon \
        --filters "Name=name,Values=amzn2-ami-hvm-*-x86_64-gp2" \
                  "Name=state,Values=available" \
        --query "Images | sort_by(@, &CreationDate) | [-1].ImageId" \
        --output text \
        --region "$region" 2>/dev/null)
    
    if [ -z "$ami_id" ] || [ "$ami_id" == "None" ]; then
        echo -e "${YELLOW}Warning: Could not find Amazon Linux 2 AMI. Using default: $default_ami${NC}" >&2
        echo "$default_ami"
    else
        echo "$ami_id"
    fi
}

# Function to update AMI ID in CloudFormation template
update_template_ami() {
    local template_file="$1"
    local ami_id="$2"
    
    if [ -z "$template_file" ] || [ -z "$ami_id" ]; then
        echo -e "${RED}Error: Template file and AMI ID are required${NC}" >&2
        return 1
    fi
    
    if [ ! -f "$template_file" ]; then
        echo -e "${RED}Error: Template file '$template_file' not found${NC}" >&2
        return 1
    fi
    
    # Replace any AMI ID pattern in the template
    # Match both real AMI IDs (17 hex chars) and placeholder values (like ami-12345678)
    # Use a more flexible pattern that matches ami- followed by 8 or more hex characters
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS - replace any ami- followed by 8+ hex characters
        sed -i '' "s/ami-[0-9a-f]\{8,\}/$ami_id/g" "$template_file"
    else
        # Linux - replace any ami- followed by 8+ hex characters
        sed -i "s/ami-[0-9a-f]\{8,\}/$ami_id/g" "$template_file"
    fi
}

# Function to auto-select or prompt for key pair
auto_select_key_pair() {
    local region="${1:-us-east-1}"
    local key_pair_name=""
    
    # Get list of key pairs
    local key_pairs
    key_pairs=$(aws ec2 describe-key-pairs --region "$region" --query 'KeyPairs[*].KeyName' --output text 2>/dev/null || echo "")
    
    if [ -z "$key_pairs" ]; then
        echo -e "${RED}Error: No Key Pairs found in region '$region'${NC}" >&2
        echo -e "${YELLOW}Please create a Key Pair first using:${NC}" >&2
        echo "  ./utils/create-key-pair.sh -k <key-name> -r $region" >&2
        return 1
    fi
    
    # Count key pairs
    local key_pair_count
    key_pair_count=$(echo "$key_pairs" | wc -w | tr -d ' ')
    
    if [ "$key_pair_count" -eq 1 ]; then
        # Only one key pair - use it automatically
        key_pair_name="$key_pairs"
        echo -e "${GREEN}Found one Key Pair: $key_pair_name${NC}" >&2
        echo -e "${GREEN}Using Key Pair: $key_pair_name${NC}" >&2
    else
        # Multiple key pairs - present options
        echo -e "${BLUE}Available Key Pairs:${NC}" >&2
        echo "" >&2
        local index=1
        local key_pair_array=()
        for key in $key_pairs; do
            echo "  $index) $key" >&2
            key_pair_array+=("$key")
            ((index++))
        done
        echo "" >&2
        
        while true; do
            read -p "Select Key Pair (1-$key_pair_count) or enter name: " selection
            
            # Check if it's a number
            if [[ "$selection" =~ ^[0-9]+$ ]]; then
                if [ "$selection" -ge 1 ] && [ "$selection" -le "$key_pair_count" ]; then
                    key_pair_name="${key_pair_array[$((selection-1))]}"
                    echo -e "${GREEN}Selected Key Pair: $key_pair_name${NC}" >&2
                    break
                else
                    echo -e "${RED}Invalid selection. Please enter a number between 1 and $key_pair_count${NC}" >&2
                fi
            else
                # User entered a name directly - validate it exists
                if echo "$key_pairs" | grep -q "^$selection$"; then
                    key_pair_name="$selection"
                    echo -e "${GREEN}Selected Key Pair: $key_pair_name${NC}" >&2
                    break
                else
                    echo -e "${RED}Key Pair '$selection' not found. Please try again.${NC}" >&2
                fi
            fi
        done
    fi
    
    echo "$key_pair_name"
}

