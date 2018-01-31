#!/bin/sh

#set +x
set -e

#############################################
FATAL(){
	# We use printf as this will handle the escape sequences
	# echo -ne is a {Linux,Bash}-ish-ism
	printf "%s" $FATAL_COLOUR
	echo "FATAL $@"
	printf "%s" $NONE_COLOUR

	exit 1
}

INFO(){
	printf "%s" "$INFO_COLOUR"
	echo "INFO $@"
	printf "%s" "$NONE_COLOUR"
}

branch_to_name(){
	# Generates a deployment name from a given branch name - effectively, it just takes the actual
	# branch name and returns that as the deployment name
	local branch_name="$1"

	[ -z "$branch_name" ] || FATAL 'No Git branch name provided'

	# sed $SED_OPT -e 's,^.*/([^/]+)$,\1,g' would also have done the job
	local deployment_name="`basename "$branch_name"`"

	[ -n "$deployment_name" ] || FATAL "Unable to determine deployment name from '$branch_name'"
}

#############################################
# Detect the SED variant - this is only really useful when running jenkins/jenkins_deploy.sh
# Some BSD sed variants don't handle -r they use -E for extended regular expression
sed </dev/null 2>&1 | grep -q GNU && SED_OPT='-r' || SED_OPT='-E'

# Configure colour console - if possible
COLOURS="`tput colors`"

if [ 0$COLOURS -ge 8 ]; then
	FATAL_COLOUR='\e[1;31m'
	INFO_COLOUR='\e[1;36m'
	NONE_COLOUR='\e[0m'
fi

if ! git config --global push.default >/dev/null 2>&1; then
	INFO 'Setting default Git push method'
	git config --global push.default simple
fi

if ! git config --global user.email >/dev/null 2>&1; then
	INFO 'Setting default Git user email'
	git config --global user.email "${USER:-jenkins}@${HOSTNAME:-localhost}"
fi

if ! git config --global user.name >/dev/null 2>&1; then
	INFO 'Setting default Git user name'
	git config --global user.name "${USER:-jenkins}"
fi

# Ensure we have a sensible umask
umask 022
