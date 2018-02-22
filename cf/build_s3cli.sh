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

export GOPATH="$PWD/go"

mkdir -p "$GOPATH"

cd go/src/github.com/cloudfoundry/bosh-s3cli

pwd

go build

cd -

cp go/src/github.com/cloudfoundry/bosh-s3cli/bosh-s3cli .
