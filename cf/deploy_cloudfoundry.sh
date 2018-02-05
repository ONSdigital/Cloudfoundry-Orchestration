#!/bin/sh
#
# Deploy a Cloudfoundry instance onto already deployed infrastructure
#
# Variables:
#	ADMIN_EMAIL_ADDRESS=[Admin email address]
#	DEPLOYMENT_NAME=[Deployment Name]
#	GIT_BRANCH=Git branch name
#	GIT_COMMIT_MESSAGE=Git commit message
#	SKIP_CF_SETUP=[true|false]

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

if [ -z "$GIT_COMMIT_MESSAGE" ]; then
	[ x"$GIT_BRANCH" = x'origin/master' ] && GIT_COMMIT_MESSAGE="New deployment $DEPLOYMENT_NAME" || GIT_COMMIT_MESSAGE="Updated deployment $DEPLOYMENT_NAME"
fi

# Deploy Cloudfoundry instance
./Scripts/bin/deploy_cloudfoundry.sh "$DEPLOYMENT_NAME" || FAILED=1

# Generate admin credentials if we don't already have some
if [ -z "$FAILED" -a -n "$ADMIN_EMAIL_ADDRESS" -a -n "$SKIP_CF_SETUP" -a x"$SKIP_CF_SETUP" != x"true" ]; then
	./Scripts/bin/setup_cf.sh "$DEPLOYMENT_NAME" "${ADMIN_EMAIL_ADDRESS:-NONE}" || FAILED=1

	[ -f "deployment/$DEPLOYMENT_NAME/cf-credentials-admin.sh" ] && git add "deployment/$DEPLOYMENT_NAME/cf-credentials-admin.sh" 
fi

git add --all .

# Commit all of our changes
git commit -am "$GIT_COMMIT_MESSAGE" || WARN 'No changes'

# ... and push
git push --all || WARN 'Nothing to push'

if [ -n "$FAILED" ]; then
	WARN 'The deployment failed - please see above for the reason'
	WARN 'You may be able to restart the build after fixing the problem(s)'

	FATAL 'Cloudfoundry deployment failed'
fi
