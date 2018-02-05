#!/bin/sh
# 
#
# Parameters:
#	[Username1 ... UsernameN]
#
# Variables:
#	[USERS]
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

PASSWORD_LENGTH="${PASSWORD_LENGTH:-16}"
USERS_CSV="${USERS_CSV:-users.csv}":w

USERS="${@:-$USERS}"

[ -f "$USERS_CSV" ] && FATAL 'Existing users.csv exists'

echo 'Username,Password' >"$USERS_CSV"

for _u in $USERS; do
	INFO "Generating password"
	# Ignoring the insecurity of using an environmental variable for a password
	PASSWORD="`head /dev/urandom | base64 | head -c$PASSWORD_LENGTH`"

	INFO "Creating user: $_u"
	cf create-user "$_u" "$PASSWORD" 

	echo "$_u,$PASSWORD" >>"$USERS_CSV"
done

INFO 'Users CSV:'
ls "$USERS_SV"
