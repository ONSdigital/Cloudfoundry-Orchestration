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

install_scripts

ACTION="${1:-build}"

grep -Eq '^(build|download)$' <<EOF || FATAL 'Incorrect action. Valid action: build or download'
$ACTION
EOF

[ -d releases ] && subdir='releases' || subdir='vendor'

for _d in `find $subdir -name \*release`; do
	find $_d -name "${ACTION}_blobs.sh" -exec {} \;
done
