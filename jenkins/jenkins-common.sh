#!/bin/sh

#set +x
set -e

#############################################
FATAL_COLOUR='\e[1;31m'
INFO_COLOUR='\e[1;36m'
NONE_COLOUR='\e[0m'

JENKINS_APPNAME="${JENKINS_APPNAME:-jenkins}"
JENKINS_RELEASE_TYPE="${JENKINS_RELEASE_TYPE:-STABLE}"

# Jenkins WAR file URLs
JENKINS_STABLE_WAR_URL="${JENKINS_STABLE_WAR_URL:-http://mirrors.jenkins-ci.org/war-stable/latest/jenkins.war}"
JENKINS_LATEST_WAR_URL="${JENKINS_LATEST_WAR_URL:-http://mirrors.jenkins-ci.org/war/latest/jenkins.war}"

# Jenkins will not start without this plugin
DEFAULT_PLUGINS="https://updates.jenkins-ci.org/latest/matrix-auth.hpi"
#############################################

#############################################
FATAL(){
	COLOUR FATAL
	echo "FATAL $@"
	COLOUR NONE

	exit 1
}

INFO(){
	COLOUR INFO
	echo "INFO $@"
	COLOUR NONE
}

COLOUR(){
	echo "$TERM" | grep -qE "^(xterm|rxvt)(-256color)?$" || return 0

	eval colour="\$${1}_COLOUR"

	echo -ne "$colour"
}

download_jenkins_war(){
	local release_type="$1"

	case "$release_type" in
		[Ll][Aa][Tt][Ee][Ss][Tt])
			local jenkins_war_url="$JENKINS_LATEST_WAR_URL"
			;;
		[Ss][Tt][Aa][Bb][Ll][Ee])
			local jenkins_war_url="$JENKINS_STABLE_WAR_URL"
			;;
		*)
			FATAL "Unknown Jenkins type: $JENKINS_RELEASE_TYPE. Valid types: latest or table"
			;;
	esac

	if ! curl --progress-bar -L -o jenkins-$jenkins_release_type.war "$jenkins_war_url"; then
		[ -f "jenkins-$jenkins_release_type.war" ] && rm -f jenkins-$jenkins_release_type.war

		FATAL "Downloading $jenkins_war_url failed"
	fi
}

scan_ssh_keys(){
	# Suck in the SSH keys for our Git repos
	for _k in $@; do
		# We only want to scan a host if we are connecting via SSH
		echo $_k | grep -Eq '^((https?|file|git)://|~?/)' && continue

		echo $_k | sed $SED_OPT -e 's,^[a-z]+://([^@]+@)([a-z0-9\.-]+)([:/].*)?$,\2,g' | xargs ssh-keyscan -T $SSH_KEYSCAN_TIMEOUT
	done | sort -u
}

configure_git_repo(){
	# This is slightly long winded as we use a seed repository for new deployments, but for existing ones we only have a seed
	# AWS then comes along and complicates things by using different usernames for repositories based on the user's SSH key
	# The thing that deploys Jenkins may or may not be the thing that eventually commits updates from the running system
	#
	# eg Jenkins A performs the Jenkins B deployment and then Jenkins B performs its own commits/updates/etc

	local repo_dir="$1"

	local git_seed_repo="$2"
	local git_new_repo="$3"

	# If we use AWS Git repos the embedded username differs
	local git_deploy_seed_repo="$4"
	local git_deploy_new_repo="$5"

	local final_repo

	# Minimal parameter checking
	[ -z "$git_seed_repo" ] && FATAL 'Not enough parameters'

	[ -d "$repo_dir" ] && FATAL "$repo_dir already exists"

	INFO 'Initialising repository'
	mkdir "$repo_dir"
	cd "$repo_dir"

	git init

	# Ordering is important
	for _r in seed new deploy_seed deploy_new; do
		unset repo_url

		eval repo_url="\$git_${_r}_repo"

		# Only act if we have been given a repo
		if [ x"$repo_url" = x'NONE' ]; then
			unset "git_${_r}_repo"

			continue
		fi

		# Final/deployed repo
		[ x"$_r" = x'seed' -o x"$_r" = x'new' ] && git remote add origin "$_r"

		# Predeployment seed repo
		[ x"$_r" = x'seed' -o x"$_r" = x'deploy_seed' ] && git remote add predeploy_seed "$_r"

		# Predeployment new repo
		[ x"$_r" = x'new' -o x"$_r" = x'deploy_new' ] && git remote add predeploy_new "$_r"
	done

	if [ -n "$git_deploy_seed_repo" ]; then
		git pull predeploy_seed;

	elif [ -n "$git_seed_repo" ]; then
		git pull origin

	else
		FATAL 'No remote repository to pull from'
	fi

	cd -
}

download_plugins(){
	local plugins="$1"

	local OLDIFS="$IFS"

	for _p in $plugins; do
		INFO "Downloading $_p"

		curl -O "$_p"
	done

	IFS="$OLDIFS"
}
#############################################


#############################################
# Detect the SED variant - this is only really useful when running jenkins/jenkins_deploy.sh
# Some BSD sed variants don't handle -r they use -E for extended regular expression
sed </dev/null 2>&1 | grep -q GNU && SED_OPT='-r' || SED_OPT='-E'

# Ensure we have a sensible umask
umask 022
