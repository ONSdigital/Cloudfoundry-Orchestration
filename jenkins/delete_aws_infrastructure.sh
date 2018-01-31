#!/bin/sh
#
# Assumes current working directory contains an existing deployment of AWS infrastructure:
#
# Variables:
#	GIT_BRANCH=Git branch name
#	DELETE_GIT_BRANCH=[true|false]
#

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


###########################################################
DEPLOYMENT_NAME="`branch_to_name "$GIT_BRANCH"`"

[ -f bin/protected_branch.sh -a -x bin/protected_branch.sh ] && ./bin/protected_branch.sh

[ x"$DEPLOYMENT_NAME" = x'master' ] && FATAL 'Foot shooting protection activated, refusing to delete master branch'

./Scripts/bin/delete_aws_cloudformation.sh "$DEPLOYMENT_NAME"

if [ x"$DELETE_GIT_BRANCH" = x'true' ]; then
	INFO 'Deleting Git branch'
	git checkout master
	git branch -D "$DEPLOYMENT_NAME"
	git push origin ":$DEPLOYMENT_NAME"
fi

