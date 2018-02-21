#!/bin/sh
#
# Shared functions and variables
#
# Variables:
#	DEFAULT_BRANCH=Default Git branch
#	DEFAULT_ORIGIN=Default Git origin
#	CLOUDFOUNDRY_DEPLOYMENT=Cloudfoundry deployment folder
set -e

#############################################
FATAL(){
	cat >&2 <<EOF
${FATAL_COLOR}FATAL $@$NORMAL_COLOUR
EOF

	exit 1
}

WARN(){
	cat >&2 <<EOF
${WARN_COLOUR}WARN $@$NORMAL_COLOUR
EOF
}

INFO(){
	cat >&2 <<EOF
${INFO_COLOUR}INFO $@$NORMAL_COLOUR
EOF
}

branch_to_name(){
	local branch="$1"

	[ -z "$branch" ] && FATAL 'No branch name provided'

	basename "$branch"
}

#############################################
# Git config
DEFAULT_ORIGIN="${DEFAULT_ORIGIN:-origin}"
DEFAULT_BRANCH="${DEFAULT_BRANCH:-master}"

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
#############################################

#############################################
# Detect the SED variant - this is only really useful when running jenkins/jenkins_deploy.sh
# Some BSD sed variants don't handle -r they use -E for extended regular expression
sed </dev/null 2>&1 | grep -q GNU && SED_OPT='-r' || SED_OPT='-E'

#############################################
# Configure colour console - if possible
COLOURS="`tput colors`"

if [ 0$COLOURS -ge 8 ]; then
	# Red
	FATAL_COLOUR='\e[1;31m'
	# Yellow
	WARN_COLOUR='\e[1;33m'
	# Cyan
	INFO_COLOUR='\e[1;36m'
	# None
	NONE_COLOUR='\e[0m'
fi
#############################################

#############################################
# Ensure we have a sensible umask
umask 022
#############################################

#############################################
if [ -n "$CLOUDFOUNDRY_DEPLOYMENT" -a -d "$CLOUDFOUNDRY_DEPLOYMENT" ]; then
	cd "$CLOUDFOUNDRY_DEPLOYMENT"
fi

