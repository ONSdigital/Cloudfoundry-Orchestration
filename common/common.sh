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
# Add ability to debug commands
[ -n "$DEBUG" -a x"$DEBUG" != x"false" ] && set -x
#############################################

#############################################
FATAL(){
	printf '%bFATAL %s%b\n' "$FATAL_COLOUR" "$@" "$NORMAL_COLOUR"

	exit 1
}

WARN(){
	printf '%bWARN %s%b\n' "$WARN_COLOUR" "$@" "$NORMAL_COLOUR"
}

INFO(){
	printf '%bINFO %s%b\n' "$INFO_COLOUR" "$@" "$NORMAL_COLOUR"
}

branch_to_name(){
	local branch="$1"

	[ -z "$branch" ] && FATAL 'No branch name provided'

	basename "$branch"
}

install_scripts(){
	# Install Scripts, if we don't already have things in the right place
	if [ ! -d Scripts ]; then
		# We are being run from a branch that hasn't been deployed, so we need to simulate some of the
		# layout. If we don't do this we get the work/bin/ directory created under vendor/
		cp -rp vendor/Scripts .
	fi
}
#############################################

#############################################
# Configure colour console - if possible
#
# Check if we support colours
if [ -t 1 ]; then
	COLOURS="`tput -T ${TERM:-dumb} colors 2>/dev/null | grep -E '^[0-9]+$' || :`"

	# Colours may be negative
	if [ -n "$COLOURS" ] && [ $COLOURS -ge 8 ]; then
		FATAL_COLOUR="`tput setaf 1`"
		INFO_COLOUR="`tput setaf 2`"
		WARN_COLOUR="`tput setaf 3`"
		DEBUG_COLOUR="`tput setaf 4`"
		NORMAL_COLOUR="`tput sgr0`"
	fi
elif [ -n "$TERM" ] && echo "$TERM" | grep -Eq '^(xterm|rxvt)'; then
	# We aren't running under a proper terminal, but we may be running under something pretending to be a terminal
	FATAL_COLOUR='\e[31;1m'
	INFO_COLOUR='\e[32;1m'
	WARN_COLOUR='\e[33;1m'
	DEBUG_COLOUR='\e[34;1m'
	NORMAL_COLOUR='\e[0m'
else
	INFO 'Not setting any colours as we have neither /dev/tty nor $TERM available'
fi
#############################################

#############################################
# Git config
DEFAULT_ORIGIN="${DEFAULT_ORIGIN:-origin}"
DEFAULT_BRANCH="${DEFAULT_BRANCH:-master}"

if which git >/dev/null 2>&1; then
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
fi
#############################################

#############################################
# Detect the SED variant - this is only really useful when running jenkins/jenkins_deploy.sh
# Some BSD sed variants don't handle -r they use -E for extended regular expression
sed </dev/null 2>&1 | grep -q GNU && SED_OPT='-r' || SED_OPT='-E'


#############################################
# Ensure we have a sensible umask
umask 022
#############################################


