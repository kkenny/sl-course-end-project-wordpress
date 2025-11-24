echo -n "Setting profile"
export AWS_ACCESS_KEY_ID=""
export AWS_SECRET_ACCESS_KEY=""
export AWS_DEFAULT_REGION=""
export AWS_REGION=$AWS_DEFAULT_REGION

aws configure list
