#!/bin/sh
#
#
# Parameters:
#	[Organisation]
#	[Quota Name]
#	[OrgManager1 ... OrgManagerN]
#
# Variables:
#	[ORGANISATION]
#	[QUOTA_NAME]
#	[ORG_MANANGERS]
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

ORGANISATION="${1:-$ORGANISATION}"
QUOTA_NAME="${2:-$QUOTA_NAME}"

[ -n "$1" ] || FATAL 'No organisation provided'
[ -n "$2" ] || FATAL 'No quota name provided'

shift 2

ORG_MANAGERS="${ORG_MANAGERS:-$@}"

[ -z "$ORG_MANAGERS" ] && FATAL 'No OrgManagers provided'

"$CF" create-org "$ORGANISATION" -q "$QUOTA_NAME"

for _u in $ORG_MANAGERS; do
	"$CF" set-org-role "$_u" "$ORGANISATION" OrgManager || FATAL "Failed to allocate OrgManager to '$_u' - does the user exist?"
done
