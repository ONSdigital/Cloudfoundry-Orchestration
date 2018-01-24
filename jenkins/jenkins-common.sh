#!/bin/sh

#set +x
set -e

#############################################
JENKINS_APPNAME="${JENKINS_APPNAME:-jenkins}"
JENKINS_RELEASE_TYPE="${JENKINS_RELEASE_TYPE:-STABLE}"

# Jenkins WAR file URLs
JENKINS_STABLE_WAR_URL="${JENKINS_STABLE_WAR_URL:-http://mirrors.jenkins-ci.org/war-stable/latest/jenkins.war}"
JENKINS_LATEST_WAR_URL="${JENKINS_LATEST_WAR_URL:-http://mirrors.jenkins-ci.org/war/latest/jenkins.war}"

# Jenkins will not start without this plugin
DEFAULT_PLUGINS="https://updates.jenkins-ci.org/latest/matrix-auth.hpi"
#############################################

INVOCATION_ORIGINAL="$0 $@"

#############################################
FATAL(){
	# echo -ne is a {Linux,Bash}-ish-ism
	echo -ne $FATAL_COLOUR
	echo "FATAL $@"
	echo -ne $NONE_COLOUR

	exit 1
}

INFO(){
	echo -ne $INFO_COLOUR
	echo "INFO $@"
	echo -ne $NONE_COLOUR
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

	if ! curl --progress-bar -L -o jenkins-$release_type.war "$jenkins_war_url"; then
		[ -f "jenkins-$release_type.war" ] && rm -f jenkins-$release_type.war

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

	local final_repo repo_name

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
		if [ -z "$repo_url" -o x"$repo_url" = x'NONE' ]; then
			[ x"$repo_url" = x'NONE' ] && unset "git_${_r}_repo"

			continue
		fi

		# Final/deployed repo
		[ x"$_r" = x'seed' -o x"$_r" = x'new' ] && git_remote_update origin "$repo_url"

		if [ x"$_r" = x'seed' -o x"$_r" = x'deploy_seed' ]; then
			# Predeployment seed repo
			repo_name='predeploy_seed'
		elif [ x"$_r" = x'new' -o x"$_r" = x'deploy_new' ]; then
			# Predeployment new repo
			repo_name='predeploy_new'
		else
			# Should never happen
			FATAL "Unknown repo name: $_r"
		fi

		git_remote_update "$repo_name" "$repo_url"

	done

	git pull predeploy_seed master;

	cd -
}

git_push_repo_cleanup(){
	local repo_dir="$1"

	# Basic sanity checking
	[ -z "$repo_dir" ] && FATAL 'Not enough parameters'
	[ -d "$repo_dir" ] || FATAL "Repository does not exist: $repo_dir"

	cd "$repo_dir"

	if git remote | grep -Eq '^predeploy_new$'; then
		git push --set-upstream predeploy_new master

	elif git remote | grep -Eq '^origin$'; then
		git push --set-upstream origin master
	else
		# Should never happen
		FATAL 'No repository to push to'
	fi

	INFO 'Potentially, removing deployment repositories'
	for _r in `git remote`; do
		[ x"$_r" = x'origin' ] && continue

		git remote remove "$_r"
	done

	cd -
}

git_remote_update(){
	local remote="$1"
	local url="$2"

	[ -z "$url" ] && FATAL 'Not enough parameters'

	# Do we have an existing remote we need to remote?
	git remote | grep -Eq "^$remote$" && git remote remove "$remote"

	git remote add "$remote" "$url"
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

scan_ssh_hosts(){
	[ -z "$1" ] && FATAL 'No hosts to scan'

	INFO 'Checking if we need to save any SSH host keys'
	for _h in $@; do
                # We only want to scan a host if we are connecting via SSH
                echo $_h | grep -Eq '^((https?|file|git)://|~?/)' && continue

                # Silence ssh-keyscan
                echo $_h | sed $SED_OPT -e 's,^[a-z]+://([^@]+@)([a-z0-9\.-]+)([:/].*)?$,\2,g' | xargs ssh-keyscan -T "$SSH_KEYSCAN_TIMEOUT"
        done
}

#############################################


#############################################
# Detect the SED variant - this is only really useful when running jenkins/jenkins_deploy.sh
# Some BSD sed variants don't handle -r they use -E for extended regular expression
sed </dev/null 2>&1 | grep -q GNU && SED_OPT='-r' || SED_OPT='-E'

# Configure colour console - if possible
COLOURS="`tput colors`"

if [ 0$COLOURS -ge 8 ]; then
	FATAL_COLOUR='\e[1;31m'
	INFO_COLOUR='\e[1;36m'
	NONE_COLOUR='\e[0m'
fi

INFO 'Performing initial git setup'
git config --global push.default || git config --global push.default simple

# Ensure we have a sensible umask
umask 022
