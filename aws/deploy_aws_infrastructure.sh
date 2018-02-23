#!/bin/sh
#
# Assumes current working directory contains an checkout of a the master/non-deployed branch of a Cloudfoundry-Deployment repo
#
# Paramters:
#	[Deployment Name]
#
# Variables:
#	CREATE_DEPLOYMENT=true|false
#	DELETE_GIT_BRANCH=[true|false]
#	DEPLOYMENT_COMMIT_MESSAGE=[Git commit deployment message]
#	DEPLOYMENT_NAME=[Deployment Name]
#	GIT_BRANCH=Git branch name

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


###########################################################

CF_SCRIPTS_DIR='Scripts'

DEPLOYMENT_NAME="${1:-$DEPLOYMENT_NAME}"

[ -f bin/protected_branch.sh -a -x bin/protected_branch.sh ] && ./bin/protected_branch.sh

if [ x"$GIT_BRANCH" = x'origin/master' -a -z "$DEPLOYMENT_NAME" ]; then
	FATAL 'You have not provided a deployment name or selected a deployment branch'

elif [ -n "$DEPLOYMENT_NAME" ]; then
	# Force alnumeric deployment name in lowercase (upper case parts confuse the UAA URL registration)
	INFO 'Forcing deployment name to lowercase and stripping non-alphanumeric characters'
	NEW_DEPLOYMENT_NAME="`echo \"$DEPLOYMENT_NAME\" | tr '[:upper:]' '[:lower:]' | tr -dc '[:alnum:]-'`"

	if [ x"$DEPLOYMENT_NAME" != x"$NEW_DEPLOYMENT_NAME" ]; then
		WARN "Deployment name changed from '$DEPLOYMENT_NAME' to '$NEW_DEPLOYMENT_NAME'"
		DEPLOYMENT_NAME="$NEW_DEPLOYMENT_NAME"
	fi

elif [ -n "$GIT_BRANCH" ]; then
	DEPLOYMENT_NAME="`branch_to_name "$GIT_BRANCH"`"
else
	FATAL 'DEPLOYMENT_NAME and GIT_BRANCH have not been set'
fi

if [ x"$CREATE_DEPLOYMENT" = x'false' -a -d deployment ]; then
	[ -z "$DEPLOYMENT_COMMIT_MESSAGE" ] && DEPLOYMENT_COMMIT_MESSAGE='Updated deployment'

	# Update an existing AWS infrastructure
	"$CF_SCRIPTS_DIR/bin/update_aws_cloudformation.sh" "$DEPLOYMENT_NAME" || FAILED='true'

	ACTION='Updating'
else
	[ -z "$DEPLOYMENT_COMMIT_MESSAGE" ] && DEPLOYMENT_COMMIT_MESSAGE='Initial deployment'

	INFO 'Checking for existing Git branch'

	if git branch -r | grep -qE "\*? +[^/]+/$DEPLOYMENT_NAME$"; then
		WARN 'Existing Git branch exists'
		git branch | grep -qE "\* +$DEPLOYMENT_NAME$" || FATAL "$DEPLOYMENT_NAME already exists remotely, but has not been checked out locally"
	else
		INFO 'Creating new Git branch'
		git checkout -b "$DEPLOYMENT_NAME"

		INFO 'Installing vendored repositories'
		for _r in `ls vendor/`; do
			if [ ! -d "$_r" ]; then
				echo "$_r" | grep -Eq -- '-release' && dst="releases/$_r" || dst="./$_r"
				INFO ". installing $_r to $dst"

				[ -d "$_r" ] || mkdir -p "$dst"

				tar --exclude .git -cf - -C "vendor/$_r" . | tar -xf - -C "$dst"
			fi
		done

		[ -d bin ] || mkdir -p bin

		INFO 'Installing scripts'
		for _s in vendor_update.sh protected_branch.sh; do
			INFO ". installing $_s"
			cp "Scripts/bin/$_s" bin
		done
	fi

	# Create the AWS infrastructure
	#"$CF_SCRIPTS_DIR/bin/create_aws_cloudformation.sh" "$DEPLOYMENT_NAME" || FAILED='true'

	ACTION='Creating'
fi

pwd

INFO 'Adding all new files/directories to Git'
git add --all

INFO 'Updating Git repository'
git commit -am "$DEPLOYMENT_COMMIT_MESSAGE" --allow-empty

INFO 'Pushing Git repository'
git push --all

if [ x"$FAILED" = x"true" ]; then
	WARN 'There was a problem with AWS Cloudformation'
	WARN 'Check the failure within the AWS Cloudformation console.'
	WARN 'If there is a stack in a "FAILED" state please remove this stack and re-run the create after fixing'
	WARN 'the underlying Cloudformation template(s) and re-run the job'
	WARN 'If the error ocurred during an update then Cloudformation should have rolled back the change. Again,'
	WARN 'fix the underlying template(s) and re-run the job'

	FATAL "$ACTION AWS infrastructure failed"
fi
