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
COMMON_SH="$BASE_DIR/common.sh"

if [ ! -f "$COMMON_SH" ]; then
	echo "Unable to find $COMMON_SH"

	exit 1
fi

. "$COMMON_SH"
###########################################################

DEFAULT_GIT_REPO='Cloudfoundry-Deployment'
DEFAULT_GIT_BASE_URL='https://github.com/ONSdigital'

REMOTE_REPO="${1:-$REMOTE_REPO}"
GIT_REPO="${2:-${GIT_REPO:-$DEFAULT_GIT_REPO}}"
GIT_BASE_URL="${3:-${GIT_BASE_URL:-$DEFAULT_GIT_BASE_URL}}"

REPOS='AWS-Cloudformation Bosh-Manifests Scripts'
RELEASE_REPOS='postgresql-databases-release'

[ -z "$REMOTE_REPO" ] && FATAL 'No remote repository provided'
[ -d "$GIT_REPO" ] && FATAL "Existing '$GIT_REPO' folder exists"

if [ x"$REMOTE_REPO" = x'fake' ]; then
	INFO 'Creating fake local repository'

	mkdir -p "$GIT_REPO-local"

	cd "$GIT_REPO-local"

	REMOTE_REPO="file:///$PWD"

	git init --bare
fi

mkdir -p "$GIT_REPO"

cd "$GIT_REPO"

git init

git checkout -b master

git remote add origin "$REMOTE_REPO"

mkdir -p vendor

for _r in $REPOS; do
	INFO "Adding $_r repository"
	git submodule add "$GIT_BASE_URL/Cloudfoundry-$_r" "vendor/$_r"
done

for _r in "$RELEASE_REPOS"; do
	INFO "Adding $_r release repository"
	git submodule add "$GIT_BASE_URL/$_r" "vendor/$_r"
done

git commit -m 'Initial repository setup'
git push --all
