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
	SCRIPT=Scripts/bin/install_deps.sh

elif [ -f vendor/Scripts/bin/install_deps.sh ]; then
	SCRIPT=vendor/Scripts/bin/install_deps.sh

else
	FATAL 'Unable to find install_deps.sh'
fi

$SCRIPT
