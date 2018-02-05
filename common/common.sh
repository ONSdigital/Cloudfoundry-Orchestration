#!/bin/sh
#
# Shared functions and variables
#
# Variables:
#	DEFAULT_BRANCH=Default Git branch
#	DEFAULT_ORIGIN=Default Git origin
set -e

#############################################
FATAL(){
	# We use printf as this will handle the escape sequences
	# echo -ne is a {Linux,Bash}-ish-ism
	printf "%s" $FATAL_COLOUR
	cat <<EOF
FATAL $@
EOF
	printf "%s" $NONE_COLOUR

	exit 1
}

WARN(){
	printf "%s" "$WARN_COLOUR"
	cat <<EOF
WARN $@
EOF
	printf "%s" "$NONE_COLOUR"
}

INFO(){
	printf "%s" "$INFO_COLOUR"
	dwicat <<EOF
INFO $@
EOF
	printf "%s" "$NONE_COLOUR"
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
