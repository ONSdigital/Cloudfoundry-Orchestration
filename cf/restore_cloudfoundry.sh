#!/bin/sh
#
# Restore a CF from S3
#
# Variables:
#	DEPLOYMENT_NAME=[Deployment Name]
#	S3_BACKUP_BUCKET=S3 Bucket Name

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

install_scripts

[ -z "$S3_BACKUP_BUCKET" ] && FATAL 'No S3 bucket name provided'

./Scripts/bin/backup_cloudfoundry-s3.sh "$DEPLOYMENT_NAME" restore "s3://$S3_BACKUP_BUCKET/$DEPLOYMENT_NAME/s3_backups"
