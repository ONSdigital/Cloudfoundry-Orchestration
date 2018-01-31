#!/bin/sh
#
#
# Variables:
#	DEPLOYMENT_NAME=[Deployment Name]
#	S3_BACKUP=[true|false]

set -e


###########################################################
#
# Functionality shared between all of the Jenkins deployment scripts
BASE_DIR="`dirname $0`"
CF_PREAMBLE="$BASE_DIR/cloudfoundry-preamble.sh"

if [ ! -f "$CF_PREAMBLE" ]; then
	echo "Unable to find $CF_PREAMBLE"

	exit 1
fi

"$CF_PREAMBLE"
###########################################################

