#!/bin/sh
# 
#
# Parameters:
#	[Quota Name]
#	[Total Memory]
#	[Total Routes]
#	[Total Services]
#
# Variables:
#	[QUOTA_NAME]
#	[TOTAL_MEMORY]
#	[TOTAL_ROUTES]
#	[TOTAL_SERVICES]
#
set -e

###########################################################
#
# Functionality shared between all of the scripts
BASE_DIR="`dirname $0`"
COMMON_SH="$BASE_DIR/common-cf.sh"

if [ ! -f "$COMMON_SH" ]; then
        echo "Unable to find $COMMON_SH"

        exit 1
fi

. "$COMMON_SH"
###########################################################

# Defaults
DEFAULT_QUOTA_NAME='default'
DEFAULT_TOTAL_MEMORY='24G'
DEFAULT_TOTAL_ROUTES='48'
DEFAULT_TOTAL_SERVICES='48'

QUOTA_NAME="${1:-${QUOTA_NAME:-$DEFAULT_QUOTA_NAME}}"

[ -n "$1" ] || WARN "No quota name provided, creating 'default' quota"

TOTAL_MEMORY="${2:-${TOTAL_MEMORY:-$DEFAULT_TOTAL_MEMORY}}"
TOTAL_ROUTES="${3:-${TOTAL_ROUTES:-$DEFAULT_TOTAL_ROUTES}}"
TOTAL_SERVICES="${4:-${TOTAL_SERVICES:-$DEFAULT_TOTAL_SERVICES}}"

if "$CF" quota "$QUOTA_NAME" >/dev/null 2>&1; then
	LOG_MSG='Updating'
	ACTION='update'
else
	LOG_MSG='Creating'
	ACTION='create'
fi

INFO "$LOG_MSG quota '$QUOTA_NAME' with '$TOTAL_MEMORY' total memory, '$TOTAL_ROUTES' total routes and '$TOTAL_SERVICES' total number of services"
"$CF" $ACTION-quota "$QUOTA_NAME" --allow-paid-service-plans -m "$TOTAL_MEMORY" -r "$TOTAL_ROUTES" -s "$TOTAL_SERVICES"
