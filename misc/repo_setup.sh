#!/bin/sh
#
#
# Variables:
#
set -e


###########################################################
#
# Functionality shared between all of the Jenkins deployment scripts
BASE_DIR="`dirname $0`"
COMMON_SH="$BASE_DIR/../common/common.sh"

if [ ! -f "$COMMON_SH" ]; then
	echo "Unable to find $COMMON_SH"

	exit 1
fi

. "$COMMON_SH"
###########################################################

DEFAULT_LOCAL_DIR='Cloudfoundry-Deployment'
DEFAULT_GIT_BASE_URL='https://github.com/ONSdigital'
DEFAULT_REPOS='AWS-Cloudformation Bosh-Manifests Scripts postgresql-databases-release'

# Remote repository to push the newly created repo to - must be an empty, or use 'fake' to create a fake local repo
REMOTE_REPO="${1:-$REMOTE_REPO}"
# Local Git repository dir name
LOCAL_DIR="${2:-${LOCAL_DIR:-$DEFAULT_LOCAL_DIR}}"
# Base URL that we add $REPOS_NAMES to
GIT_BASE_URL="${3:-${GIT_BASE_URL:-$DEFAULT_GIT_BASE_URL}}"

if [ -n "$4" ]; then
	shift 3
	#
	REPO_NAMES="$@"
else
	REPO_NAMES="$DEFAULT_REPOS"
fi

[ -z "$REMOTE_REPO" ] && FATAL 'No remote repository provided'
[ -d "$LOCAL_DIR" ] && FATAL "Existing '$LOCAL_DIR' folder exists"

if [ x"$REMOTE_REPO" = x'fake' ]; then
	INFO 'Creating fake local repository'

	mkdir -p "$LOCAL_DIR-local"

	cd "$LOCAL_DIR-local"

	REMOTE_REPO="file:///$PWD"

	git init --bare

	cd -
fi

INFO "Creating $LOCAL_DIR"
mkdir -p "$LOCAL_DIR"

cd "$LOCAL_DIR"

git init

git checkout -b master

git remote add origin "$REMOTE_REPO"

mkdir -p vendor releases

for _r in $REPO_NAMES; do
	INFO "Adding $_r repository"

	if echo "$_r" | grep -Eq -- '-release'; then
		git submodule add "$GIT_BASE_URL/$_r" "vendor/$_r"
	else
		# We strip off the Cloudfoundry- prefix
		git submodule add "$GIT_BASE_URL/Cloudfoundry-$_r" "vendor/$_r"
	fi
done

INFO "Pushing changes to $REMOTE_REPO"
git commit -m 'Initial repository setup'
git push --all

INFO "Local checkout of $REMOTE_REPO is available: $LOCAL_DIR"
