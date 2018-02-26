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
# Configure colour console - if possible
#
# Check if we support colours
[ -n "$TERM" ] && COLOURS="`tput colors`"

if [ 0$COLOURS -ge 8 ]; then
	FATAL_COLOUR="`tput setaf 1`"
	INFO_COLOUR="`tput setaf 2`"
	WARN_COLOUR="`tput setaf 3`"
	DEBUG_COLOR="`tput setaf 4`"
	# Jenkins/ansi-color adds '(B' when highlighting - this may now be fixed
	# https://issues.jenkins-ci.org/browse/JENKINS-24387
	#NORMAL_COLOUR="\e[0m"
	NORMAL_COLOUR="`tput sgr0`"
fi
#############################################

#############################################
# Ensure we have a sensible umask
umask 022
#############################################


