#!/bin/sh
#
# Shared functions and variables
#
set -e

# Load the common bits
. "$BASE_DIR/../common/common.sh"

#############################################
# Git config

DEFAULT_ORIGIN="${DEFAULT_ORIGIN:-origin}"
DEFAULT_BRANCH="${DEFAULT_BRANCH:-master}"

if ! git config --global push.default >/dev/null 2>&1; then
	INFO 'Setting default Git push method'
	git config --global push.default simple
fi

if ! git config --global user.email >/dev/null 2>&1; then
	INFO 'Setting default Git user email'
	git config --global user.email "${USER:-jenkins}@${HOSTNAME:-localhost}"
fi

if ! git config --global user.name >/dev/null 2>&1; then
	INFO 'Setting default Git user name'
	git config --global user.name "${USER:-jenkins}"
fi
#############################################
