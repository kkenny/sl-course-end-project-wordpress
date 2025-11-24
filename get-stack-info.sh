#!/bin/bash

# Script to get detailed information about a CloudFormation stack

set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source common functions
source "${SCRIPT_DIR}/_common.sh"

# Initialize variables
STACK_NAME=""
REGION=""
SHOW_EVENTS=false
SHOW_RESOURCES=false
SHOW_OUTPUTS=true
SHOW_PARAMETERS=false
SHOW_INSTANCES=false
SHOW_DATABASE=false

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
        -e|--events)
            SHOW_EVENTS=true
            shift
            ;;
        -R|--resources)
            SHOW_RESOURCES=true
            shift
            ;;
        -o|--outputs)
            SHOW_OUTPUTS=true
            shift
            ;;
        -p|--parameters)
            SHOW_PARAMETERS=true
            shift
            ;;
        -i|--instances)
            SHOW_INSTANCES=true
            shift
            ;;
        -d|--database)
            SHOW_DATABASE=true
            shift
            ;;
        -a|--all)
            SHOW_EVENTS=true
            SHOW_RESOURCES=true
            SHOW_OUTPUTS=true
            SHOW_PARAMETERS=true
            SHOW_INSTANCES=true
            SHOW_DATABASE=true
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [-s|--stack-name STACK_NAME] [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  -s, --stack-name    CloudFormation stack name (required)"
            echo "  -r, --region        AWS region (default: from AWS_REGION env or us-east-1)"
            echo "  -e, --events        Show recent stack events"
            echo "  -R, --resources     Show stack resources"
            echo "  -o, --outputs       Show stack outputs (default: enabled)"
            echo "  -p, --parameters    Show stack parameters"
            echo "  -i, --instances     Show EC2 instance information"
            echo "  -d, --database      Show RDS database information"
            echo "  -a, --all           Show all information"
            echo "  -h, --help          Show this help message"
            echo ""
            echo "Examples:"
            echo "  $0 -s wordpress-dev"
            echo "  $0 -s wordpress-prod -a"
            echo "  $0 -s wordpress-dev -e -i -d"
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
REGION="${REGION:-${AWS_REGION:-us-east-1}}"

# Check if stack name is provided
if [ -z "$STACK_NAME" ]; then
    echo -e "${RED}Error: Stack name is required${NC}"
    echo "Use -s or --stack-name to specify the stack name"
    echo "Use -h or --help for usage information"
    exit 1
fi

# Check AWS credentials
if ! aws sts get-caller-identity &> /dev/null; then
    echo -e "${RED}Error: AWS credentials not configured${NC}"
    exit 1
fi

echo -e "${BLUE}CloudFormation Stack Information${NC}"
echo "=================================="
echo "Stack Name: $STACK_NAME"
echo "Region: $REGION"
echo ""

# Check if stack exists
if ! aws cloudformation describe-stacks --stack-name "$STACK_NAME" --region "$REGION" &> /dev/null; then
    echo -e "${RED}Error: Stack '$STACK_NAME' not found in region '$REGION'${NC}"
    exit 1
fi

# Get basic stack information
STACK_INFO=$(aws cloudformation describe-stacks --stack-name "$STACK_NAME" --region "$REGION" --query 'Stacks[0]' --output json)
STACK_STATUS=$(echo "$STACK_INFO" | jq -r '.StackStatus')
STACK_CREATION_TIME=$(echo "$STACK_INFO" | jq -r '.CreationTime')
STACK_LAST_UPDATE=$(echo "$STACK_INFO" | jq -r '.LastUpdatedTime // "N/A"')

echo -e "${YELLOW}Stack Status:${NC} $STACK_STATUS"
echo "Creation Time: $STACK_CREATION_TIME"
if [ "$STACK_LAST_UPDATE" != "null" ] && [ "$STACK_LAST_UPDATE" != "N/A" ]; then
    echo "Last Updated: $STACK_LAST_UPDATE"
fi
echo ""

# Show stack outputs
if [ "$SHOW_OUTPUTS" = true ]; then
    echo -e "${YELLOW}Stack Outputs:${NC}"
    OUTPUTS=$(echo "$STACK_INFO" | jq -r '.Outputs // []')
    if [ "$OUTPUTS" != "[]" ] && [ "$OUTPUTS" != "null" ]; then
        echo "$OUTPUTS" | jq -r '.[] | "  \(.OutputKey): \(.OutputValue)"'
    else
        echo "  No outputs defined"
    fi
    echo ""
fi

# Show stack parameters
if [ "$SHOW_PARAMETERS" = true ]; then
    echo -e "${YELLOW}Stack Parameters:${NC}"
    PARAMS=$(echo "$STACK_INFO" | jq -r '.Parameters // []')
    if [ "$PARAMS" != "[]" ] && [ "$PARAMS" != "null" ]; then
        echo "$PARAMS" | jq -r '.[] | "  \(.ParameterKey): \(.ParameterValue)"' | sed 's/\(Password\|Secret\|Key\):.*/\1: ********/'
    else
        echo "  No parameters"
    fi
    echo ""
fi

# Show stack resources
if [ "$SHOW_RESOURCES" = true ]; then
    echo -e "${YELLOW}Stack Resources:${NC}"
    RESOURCES=$(aws cloudformation describe-stack-resources --stack-name "$STACK_NAME" --region "$REGION" --query 'StackResources[*].[LogicalResourceId,ResourceType,ResourceStatus]' --output table)
    if [ -n "$RESOURCES" ]; then
        echo "$RESOURCES"
    else
        echo "  No resources found"
    fi
    echo ""
fi

# Show recent stack events
if [ "$SHOW_EVENTS" = true ]; then
    echo -e "${YELLOW}Recent Stack Events (last 10):${NC}"
    EVENTS=$(aws cloudformation describe-stack-events --stack-name "$STACK_NAME" --region "$REGION" --max-items 10 --query 'StackEvents[*].[Timestamp,ResourceStatus,LogicalResourceId,ResourceStatusReason]' --output table)
    if [ -n "$EVENTS" ]; then
        echo "$EVENTS"
    else
        echo "  No events found"
    fi
    echo ""
fi

# Show EC2 instance information
if [ "$SHOW_INSTANCES" = true ]; then
    echo -e "${YELLOW}EC2 Instances:${NC}"
    
    # Get Auto Scaling Group name
    ASG_NAME=$(aws cloudformation describe-stack-resources --stack-name "$STACK_NAME" --region "$REGION" \
        --query 'StackResources[?ResourceType==`AWS::AutoScaling::AutoScalingGroup`].PhysicalResourceId' \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$ASG_NAME" ] && [ "$ASG_NAME" != "None" ]; then
        echo "Auto Scaling Group: $ASG_NAME"
        
        # Get instances in the ASG
        INSTANCES=$(aws autoscaling describe-auto-scaling-groups \
            --auto-scaling-group-names "$ASG_NAME" \
            --region "$REGION" \
            --query 'AutoScalingGroups[0].Instances[*].[InstanceId,LifecycleState,HealthStatus]' \
            --output table 2>/dev/null || echo "")
        
        if [ -n "$INSTANCES" ] && [ "$INSTANCES" != "None" ]; then
            echo "$INSTANCES"
            
            # Get instance details
            INSTANCE_IDS=$(aws autoscaling describe-auto-scaling-groups \
                --auto-scaling-group-names "$ASG_NAME" \
                --region "$REGION" \
                --query 'AutoScalingGroups[0].Instances[*].InstanceId' \
                --output text 2>/dev/null || echo "")
            
            if [ -n "$INSTANCE_IDS" ] && [ "$INSTANCE_IDS" != "None" ]; then
                echo ""
                echo "Instance Details:"
                for INSTANCE_ID in $INSTANCE_IDS; do
                    INSTANCE_INFO=$(aws ec2 describe-instances \
                        --instance-ids "$INSTANCE_ID" \
                        --region "$REGION" \
                        --query 'Reservations[0].Instances[0].[InstanceId,State.Name,PublicIpAddress,PrivateIpAddress,InstanceType]' \
                        --output text 2>/dev/null || echo "")
                    
                    if [ -n "$INSTANCE_INFO" ] && [ "$INSTANCE_INFO" != "None" ]; then
                        echo "  Instance ID: $(echo $INSTANCE_INFO | awk '{print $1}')"
                        echo "    State: $(echo $INSTANCE_INFO | awk '{print $2}')"
                        echo "    Public IP: $(echo $INSTANCE_INFO | awk '{print $3}')"
                        echo "    Private IP: $(echo $INSTANCE_INFO | awk '{print $4}')"
                        echo "    Type: $(echo $INSTANCE_INFO | awk '{print $5}')"
                    fi
                done
            fi
        else
            echo "  No instances found in Auto Scaling Group"
        fi
    else
        echo "  No Auto Scaling Group found"
    fi
    echo ""
fi

# Show RDS database information
if [ "$SHOW_DATABASE" = true ]; then
    echo -e "${YELLOW}RDS Database:${NC}"
    
    # Get database instance identifier
    DB_INSTANCE=$(aws cloudformation describe-stack-resources --stack-name "$STACK_NAME" --region "$REGION" \
        --query 'StackResources[?ResourceType==`AWS::RDS::DBInstance`].PhysicalResourceId' \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$DB_INSTANCE" ] && [ "$DB_INSTANCE" != "None" ]; then
        DB_INFO=$(aws rds describe-db-instances \
            --db-instance-identifier "$DB_INSTANCE" \
            --region "$REGION" \
            --query 'DBInstances[0].[DBInstanceStatus,Engine,EngineVersion,DBInstanceClass,Endpoint.Address,Endpoint.Port]' \
            --output text 2>/dev/null || echo "")
        
        if [ -n "$DB_INFO" ] && [ "$DB_INFO" != "None" ]; then
            echo "  Instance ID: $DB_INSTANCE"
            echo "  Status: $(echo $DB_INFO | awk '{print $1}')"
            echo "  Engine: $(echo $DB_INFO | awk '{print $2}')"
            echo "  Version: $(echo $DB_INFO | awk '{print $3}')"
            echo "  Class: $(echo $DB_INFO | awk '{print $4}')"
            echo "  Endpoint: $(echo $DB_INFO | awk '{print $5}')"
            echo "  Port: $(echo $DB_INFO | awk '{print $6}')"
        else
            echo "  Database instance found but details unavailable"
        fi
    else
        echo "  No RDS database found"
    fi
    echo ""
fi

# Show Load Balancer URL if available
echo -e "${YELLOW}Access Information:${NC}"
LOAD_BALANCER_DNS=$(aws cloudformation describe-stack-resources --stack-name "$STACK_NAME" --region "$REGION" \
    --query 'StackResources[?ResourceType==`AWS::ElasticLoadBalancingV2::LoadBalancer`].PhysicalResourceId' \
    --output text 2>/dev/null || echo "")

if [ -n "$LOAD_BALANCER_DNS" ] && [ "$LOAD_BALANCER_DNS" != "None" ]; then
    LB_DNS=$(aws elbv2 describe-load-balancers \
        --load-balancer-arns "$LOAD_BALANCER_DNS" \
        --region "$REGION" \
        --query 'LoadBalancers[0].DNSName' \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$LB_DNS" ] && [ "$LB_DNS" != "None" ]; then
        echo -e "${GREEN}WordPress URL: http://$LB_DNS${NC}"
        echo ""
    fi
fi

# Show credentials file if it exists
CREDS_FILE=".creds-${STACK_NAME}"
if [ -f "$CREDS_FILE" ]; then
    echo -e "${YELLOW}Credentials File Found:${NC}"
    echo "  File: $CREDS_FILE"
    echo "  (Contains auto-generated WordPress admin credentials)"
    echo ""
fi

echo -e "${GREEN}Stack information retrieved successfully${NC}"

