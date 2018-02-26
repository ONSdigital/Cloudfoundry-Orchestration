#!/bin/sh
#
# Delete a Cloudfoundry instance
#
# Variables:
#	CLOUDFOUNDRY_DEPLOYMENT_BRANCH=Git branch

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

[ -f bin/protected_branch.sh -a -x bin/protected_branch.sh ] && ./bin/protected_branch.sh

"$CF_SCRIPTS_DIR/bin/delete_cloudfoundry.sh" "$DEPLOYMENT_NAME"

# Commit all of our changes
git commit -am "Deleted deployment" || WARN 'No changes'

# ... and push
git push --all || WARN 'Nothing to push'

INFO "$DEPLOYMENT_NAME deleted"
