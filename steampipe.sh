#!/bin/bash
#
# Copyright 2020 Amazon.com, Inc. or its affiliates. All Rights Reserved.
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.

#
# Syntax:
#
# steampipe.sh <region> <start_url> [<steampipe_file>]
#
# <region> is the region where AWS SSO is configured (e.g., us-east-1)
# <start_url> is the AWS SSO start URL
# <profile_file> is the file where the profiles will be written (default is
#    ~/.steampipe/config/aws.spc)

find_aws_profile() {                                                            
    account=$1

	profile_name=$(tail -r ~/.aws/config | grep -A 10 " = ${account}" | grep -m1 "\[profile" | cut -d" " -f2 | cut -d "]" -f1)
	if [ -n "$profile_name" ]; then
		echo ${profile_name}
	fi
}

ACCOUNTPAGESIZE=10
ROLEPAGESIZE=10
PROFILEFILE="$HOME.steampipe/config/aws.spc"

if [ $# -lt 2 ];
then
    echo "Syntax: $0 <region> <start_url> [<profile_file>]"
    exit 1 
fi

if [ $# -eq 3 ];
then
    profilefile=$3
else
    profilefile=$PROFILEFILE
fi

if [[ $(aws --version) == aws-cli/1* ]]
then
    echo "ERROR: $0 requires AWS CLI v2 or higher"
    exit 1
fi

# Get secret and client ID to begin authentication session

echo
echo -n "Registering client... "

out=$(aws sso-oidc register-client --client-name 'profiletool' --client-type 'public' --region "$1" --output text)

if [ $? -ne 0 ];
then
    echo "Failed"
    exit 1
else
    echo "Succeeded"
fi

secret=$(awk -F ' ' '{print $3}' <<< "$out")
clientid=$(awk -F ' ' '{print $1}' <<< "$out")

# Start the authentication process

echo -n "Starting device authorization... "

out=$(aws sso-oidc start-device-authorization --client-id "$clientid" --client-secret "$secret" --start-url "$2" --region "$1" --output text)

if [ $? -ne 0 ];
then
    echo "Failed"
    exit 1
else
    echo "Succeeded"
fi

regurl=$(awk -F ' ' '{print $6}' <<< "$out")
devicecode=$(awk -F ' ' '{print $1}' <<< "$out")

echo
echo "Open the following URL in your browser and sign in, then click the Allow button:"
echo
echo "$regurl"
echo
echo "Press <ENTER> after you have signed in to continue..."

read continue

# Get the access token for use in the remaining API calls

echo -n "Getting access token... "

out=$(aws sso-oidc create-token --client-id "$clientid" --client-secret "$secret" --grant-type 'urn:ietf:params:oauth:grant-type:device_code' --device-code "$devicecode" --region "$1" --output text)

if [ $? -ne 0 ];
then
    echo "Failed"
    exit 1
else
    echo "Succeeded"
fi

token=$(awk -F ' ' '{print $1}' <<< "$out")

# Set defaults for profiles

defregion="$1"
defoutput="json"

# Batch or interactive

echo
echo "$0 can create all profiles with default values"
echo "or it can prompt you regarding each profile before it gets created."
echo
echo -n  "Would you like to be prompted for each profile? (Y/n): "
read resp < /dev/tty
if [ -z "$resp" ];
then
    interactive=true
elif [ "$resp" == 'n' ] || [ "$resp" == 'N' ];
then
    interactive=false
    awsregion=$defregion
    output=$defoutput
else
    interactive=true
fi

# Retrieve accounts first

echo
echo -n "Retrieving accounts... "

acctsfile="$(mktemp ./sso.accts.XXXXXX)"

# Set up trap to clean up temp file
trap '{ rm -f "$acctsfile"; echo; exit 255; }' SIGINT SIGTERM
    
aws sso list-accounts --access-token "$token" --page-size $ACCOUNTPAGESIZE --region "$1" --output text > "$acctsfile"

if [ $? -ne 0 ];
then
    echo "Failed"
    exit 1
else
    echo "Succeeded"
fi

declare -a created_profiles

echo "" >> "$profilefile"
echo "###" >> "$profilefile"
echo "### The section below added by awsssoprofiletool.sh" >> "$profilefile"
echo "###" >> "$profilefile"

# Read in accounts

while IFS=$'\t' read skip acctnum acctname acctowner;
do
    echo
    echo "Adding roles for account $acctnum ($acctname)..."
    rolesfile="$(mktemp ./sso.roles.XXXXXX)"

    # Set up trap to clean up both temp files
    trap '{ rm -f "$rolesfile" "$acctsfile"; echo; exit 255; }' SIGINT SIGTERM

	profileacctname=$(find_aws_profile "$acctnum")
	echo -n "Creating $profilename... "
	echo "" >> "$profilefile"
	echo "connection \"$profileacctname\" {" >> "$profilefile"
	echo "  plugin         = \"aws\"" >> "$profilefile"
	echo "  regions        = [\"*\"]" >> "$profilefile"
	echo "  profile        = \"$profileacctname\"" >> "$profilefile"
	echo "  default_region = \"$awsregion\"" >> "$profilefile"
	echo "  ignore_error_codes = [\"AccessDenied\", \"AccessDeniedException\", \"NotAuthorized\", \"UnauthorizedOperation\", \"UnrecognizedClientException\", \"AuthorizationError\"]" >> "$profilefile"
	echo "}" >> "$profilefile"
	echo "Succeeded"	
	created_profiles+=("$profilename")

    echo
    echo "Done adding roles for AWS account $acctnum ($acctname)"

done < "$acctsfile"
rm "$acctsfile"

echo >> "$profilefile"
echo "###" >> "$profilefile"
echo "### The section above added by awsssoprofiletool.sh" >> "$profilefile"
echo "###" >> "$profilefile"

echo
echo "Processing complete."
echo
echo "Added the following profiles to $profilefile:"
echo

for i in "${created_profiles[@]}"
do
    echo "$i"
done
echo
exit 0
