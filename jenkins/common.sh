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

if git config --global push.default >/dev/null 2>&1; then
	INFO 'Performing initial git setup'
	git config --global push.default simple
fi

# Ensure we have a sensible umask
umask 022
