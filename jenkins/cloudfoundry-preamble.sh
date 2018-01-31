#!/bin/sh
#
#
# Variables:
#	ADMIN_EMAIL_ADDRESS=[Administrator's email address]
#	DEPLOYMENT_NAME=[Deployment Name]
#	GIT_BRANCH=Git branch name
#	SKIP_CF_SETUP=[true|false]

set -e


###########################################################
#
# Functionality shared between all of the Jenkins deployment scripts
BASE_DIR="`dirname $0`"
COMMON_SH="$BASE_DIR/common.sh"

if [ ! -f "$COMMON_SH" ]; then
	echo "Unable to find $COMMON_SH"

	exit 1
fi

. "$COMMON_SH"
###########################################################

[ -f Scripts/bin/protected_branch.sh -a -x Scripts/bin/protected_branch.sh ] && ./Scripts/bin/protected_branch.sh


[ x"$GIT_BRANCH" = x'origin/master' ] && FATAL 'You have not selected deployment branch'

DEPLOYMENT_NAME="`branch_to_name "$GIT_BRANCH"`"

# For AWS these are generated automatically
# For VMware these are hand crafted
[ ! -d "deployment/$deployment_name/outputs" ] && FATAL 'Deployment outputs do not exist'

if [ x"$SKIP_CF_SETUP" != x'true' -a ! -f "deployment/$DEPLOYMENT_NAME/cf-credentials-admin.sh" ] && [ -z "$ADMIN_EMAIL_ADDRESS" ]; then
	FATAL 'No admin email address provided'
fi
