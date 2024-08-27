#!/bin/bash

PROFILEFILE="$HOME.steampipe/config/aws.spc"

if [ $# -lt 1 ];
then
    echo "Syntax: $0 <region> [<profile_file>]"
    exit 1 
fi

if [ $# -eq 2 ];
then
    profilefile=$2
else
    profilefile=$PROFILEFILE
fi

awsregion="$1"

declare -a created_profiles

echo "" >> "$profilefile"
echo "###" >> "$profilefile"
echo "### The section below added by steampipe2.sh" >> "$profilefile"
echo "###" >> "$profilefile"

# Read in accounts

for profilename in $( cat ~/.aws/config | grep '\[profile' | awk -F" " '{print substr($2, 1, length($2)-1)}');
do
    echo "Adding roles for account $profilename ..."
    if [ $(grep -ce "^\s*connection\s\s*\"$profilename\"" "$profilefile") -eq 0 ]; then
        echo -n "Creating $profilename... "
        echo "" >> "$profilefile"
        echo "connection \"$profilename\" {" >> "$profilefile"
        echo "  plugin         = \"aws\"" >> "$profilefile"
        echo "  regions        = [\"*\"]" >> "$profilefile"
        echo "  profile        = \"$profilename\"" >> "$profilefile"
        echo "  default_region = \"$awsregion\"" >> "$profilefile"
        echo "  ignore_error_codes = [\"AccessDenied\", \"AccessDeniedException\", \"NotAuthorized\", \"UnauthorizedOperation\", \"UnrecognizedClientException\", \"AuthorizationError\"]" >> "$profilefile"
        echo "}" >> "$profilefile"
        echo "Succeeded"
        created_profiles+=("$profilename")

        echo
        echo "Done adding roles for AWS account $profilename"
    else
		echo "Profile name already exists!"
    fi

done

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