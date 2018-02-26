#!/bin/sh
#
# Cleans various directories under Jenkins' home directory
#
# Variables:
#	CLEANUP_TYPE=[AWS|Bosh|CF|Python|Ruby|Buildpacks|ALL]
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

AWS=.aws
Bosh=.bosh
CF=.cf
Python=.pyenv
Ruby=.rbenv
Buildpacks=.buildpack-packager

#TMP=/home/vcap/tmp

[ x"$CLEANUP_TYPE" = x"ALL" ] && DIRS="AWS Bosh CF Python Ruby Buildpacks Tmp" || DIRS="$CLEANUP_TYPE"
	

for _d in $DIRS; do
	INFO "Cleaning $_d"

	case "$_d" in
		# Need to re-add tmp directory cleanups - the location will differ for local Jenkins and CF Jenkins
		#Tmp)
		#	[ -d "$TMP" ] && find "$TMP" -name buildpack\* -mindepth 1 -maxdepth 1 -exec rm -rf "{}" \;
		#	;;
		AWS|Bosh|CF|Python|Ruby|Buildpacks)
			eval dir="\$$_d"

			[ -d ~/$dir ] && rm -rf ~/$dir
			;;
		*)
	    		FATAL "Unknown cleanup: $_d"
			;;
	esac
done

INFO 'Remaining disk space'
df -h ~ 
