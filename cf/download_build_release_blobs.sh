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

INFO 'Finding releases'
cd "$subdir"
for _d in `find . -mindepth 1 -maxdepth 1 -type d -name \*release`; do
	if [ -x "$_d/bin/${ACTION}_blobs.sh" ]; then
		INFO ". executing $_d/bin/${ACTION}_blobs.sh"
		"$_d/bin/${ACTION}_blobs.sh"
	fi
done
