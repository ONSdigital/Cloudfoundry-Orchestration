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

if [ -f Scripts/bin/install_deps.sh ]; then
	# Do nothing, things are in the right place
	:

elif [ ! -d Scripts ]; then
	# We are being run from a branch that hasn't been deployed, so we need to simulate some of the
	# layout
	cp -rp vendor/Scripts .

elif [ -d Scripts ]; then
	FATAL 'Existing Scripts directory exists, but does not contain install_deps.sh'

else
	FATAL 'Unable to find install_dep.sh'
fi

Scripts/bin/install_deps.sh
