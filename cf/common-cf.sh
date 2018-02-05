#!/bin/sh
#
# Shared functions and variables
#
set -e

# Load the common bits
. "$BASE_DIR/../common/common.sh"

#############################################
# CF config

if [ -z "$CF" ]; then
	if which cf >/dev/null 2>&1; then
		CF='cf'
	elif [ -e 'work/bin/cf' ]; then
		CF="$PWD/work/bin/cf"

	else
		FATAL 'No CF CLI available'
	fi
fi
#############################################
