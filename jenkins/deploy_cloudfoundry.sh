#!/bin/sh
#
#
# Variables:
#	DEPLOYMENT_NAME=[Deployment Name]
#	EXISTING_DEPLOYMENT=[true|false]
#	GIT_COMMIT_MESSAGE=Git commit message
#	RESTORE_FROM_BACKUP=[true|false]

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

export DEPLOYMENT_DIR='deployment'

if [ -z "$GIT_COMMIT_MESSAGE" ]; then
	[ x"$RESTORE_FROM_BACKUP" = x"true" ] && COMMIT_PREFIX="Restored" || COMMIT_PREFIX="Updated"
    
	[ -n "$EXISTING_DEPLOYMENT" ] && GIT_COMMIT_MESSAGE="New deployment $DEPLOYMENT_NAME" || GIT_COMMIT_MESSAGE="$COMMIT_PREFIX deployment $DEPLOYMENT_NAME"
fi


# Deploy Cloudfoundry instance
./Scripts/bin/deploy_cloudfoundry.sh "$DEPLOYMENT_NAME" || FAILED=1

# Generate admin credentials if we don't already have some
if [ x"$RESTORE_FROM_BACKUP" != x"true" -a -z "$FAILED" -a -n "$ADMIN_EMAIL_ADDRESS" -a -n "$SKIP_CF_SETUP" -a x"$SKIP_CF_SETUP" != x"true" ]; then
	./Scripts/bin/setup_cf.sh "$DEPLOYMENT_NAME" "${ADMIN_EMAIL_ADDRESS:-NONE}" || FAILED=1

	[ -f "$DEPLOYMENT_DIR/$DEPLOYMENT_NAME/cf-credentials-admin.sh" ] && git add "$DEPLOYMENT_DIR/$DEPLOYMENT_NAME/cf-credentials-admin.sh" 
fi

git add --all .

# Commit all of our changes
git commit -am "$GIT_COMMIT_MESSAGE" || echo 'No changes'

# ... and push
git push --all || echo 'Nothing to push'


if [ -n "$FAILED" ]; then
	echo 'The deployment failed - please see above for the reason'
    echo 'You may be able to restart the build after fixing the problem(s)'
    echo 'but be sure to select the correct SKIP_* options'
    
	exit 1
fi
