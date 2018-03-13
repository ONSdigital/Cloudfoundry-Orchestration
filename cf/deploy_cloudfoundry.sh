#!/bin/sh
#
# Deploy a Cloudfoundry instance onto already deployed infrastructure
#
# Variables:
#	ADMIN_EMAIL_ADDRESS=[Admin email address]
#	DEPLOYMENT_NAME=[Deployment Name]
#	CLOUDFOUNDRY_DEPLOYMENT_BRANCH=Git branch name
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

. "$CF_PREAMBLE"
###########################################################

#if [ -z "$SKIP_CF_SETUP" -o x"$SKIP_CF_SETUP" != x'true' ] && [ ! -f "deployment/$DEPLOYMENT_NAME/cf-credentials-admin.sh" ] && [ -z "$ADMIN_EMAIL_ADDRESS" ]; then
#        FATAL 'No admin email address provided'
#fi

if [ -z "$GIT_COMMIT_MESSAGE" ]; then
	[ x"$CLOUDFOUNDRY_DEPLOYMENT_BRANCH" = x'origin/master' ] && GIT_COMMIT_MESSAGE="New deployment $DEPLOYMENT_NAME" || GIT_COMMIT_MESSAGE="Updated deployment $DEPLOYMENT_NAME"
fi

INFO 'Creating required directories'
[ -d blobs ] || mkdir -p blobs

# Deploy Cloudfoundry instance
./Scripts/bin/deploy_cloudfoundry.sh "$DEPLOYMENT_NAME" || FAILED=1

if [ -z "$FAILED" ] && [ -z "$SKIP_CF_SETUP" -o x"$SKIP_CF_SETUP" = x"false" ]; then
	./Scripts/bin/setup_cf.sh "$DEPLOYMENT_NAME" || FAILED=1
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
