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
COMMON_SH="$BASE_DIR/../common/common.sh"

if [ ! -f "$COMMON_SH" ]; then
	echo "Unable to find $COMMON_SH"

	exit 1
fi

. "$COMMON_SH"
###########################################################

BUILDPACK_NAME="$1"
BUILDPACK_DIR="$2"

pwd
find .

# Error checking is done in the underlying script
./Scripts/bin/build_offline_buildpack.sh "$BUILDPACK_NAME" "$BUILDPACK_DIR"
