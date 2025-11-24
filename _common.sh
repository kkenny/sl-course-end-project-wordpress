#!/bin/bash

# Get the directory where this script is located (if not already set)
if [ -z "$SCRIPT_DIR" ]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi

# Source profile (if _set_profile.sh exists)
if [ -f "${SCRIPT_DIR}/_set_profile.sh" ]; then
    source "${SCRIPT_DIR}/_set_profile.sh"
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

