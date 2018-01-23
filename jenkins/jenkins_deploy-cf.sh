#!/bin/sh
#
#
set -e

COMMON_SH="`dirname "$0"`/jenkins-common.sh"

if [ ! -f "$COMMON_SH" ]; then
	echo "Unable to find $COMMON_SH"

	exit 1
fi

. "$COMMON_SH"

# 4096M minimum to avoid complaints about insufficient cache
JENKINS_MEMORY="${JENKINS_MEMORY:-4096M}"
# 2048M maximum allow storage
JENKINS_DISK="${JENKINS_DISK:-2048M}"

# Default private key
SSH_PRIVATE_KEY='id_rsa'

# Default to assuming we are running on Linux and x86_64
CF_CLI_URL="${CF_CLI_URL:-https://cli.run.pivotal.io/stable?release=linux64-binary&source=github-rel}"
CF_CLI="$PWD/work/cf"

# Parse options
for i in `seq 1 $#`; do
	[ -z "$1" ] && break

	case "$1" in
		-n|--name)
			JENKINS_APPNAME="$2"
			shift 2
			;;
		-r|--release-type)
			JENKINS_RELEASE_TYPE="$2"
			shift 2
			;;
		-m|--memory)
			JENKINS_MEMORY="$2"
			shift 2
			;;
		-d|--disk-quota)
			JENKINS_DISK="$2"
			shift 2
			;;
		-c|--config-repo)
			JENKINS_CONFIG_NEW_REPO="$2"
			shift 2
			;;
		--deploy-config-repo)
			DEPLOY_JENKINS_CONFIG_NEW_REPO="$2"
			shift 2
			;;
		-C|--config-seed-repo)
			JENKINS_CONFIG_SEED_REPO="$2"
			shift 2
			;;
		--deploy-config-seed-repo)
			DEPLOY_JENKINS_CONFIG_SEED_REPO="$2"
			shift 2
			;;
		-S|--scripts-repo)
			JENKINS_SCRIPTS_REPO="$2"
			shift 2
			;;
		--deploy-scripts-repo)
			DEPLOY_JENKINS_SCRIPTS_REPO="$2"
			shift 2
			;;
		--jenkins-stable-url)
			JENKINS_STABLE_WAR_URL="$2"
			shift 2
			;;
		--jenkins-latest-url)
			JENKINS_LATEST_WAR_URL="$2"
			shift 2
			;;
		-P|--plugins)
			# comma separated list of plugins to preload
			PLUGINS="$2"
			shift 2
			;;
		-X|--disable-csp-security)
			DISABLE_CSP=1
			shift
			;;
		-k|--ssh-private-key)
			[ -f "$SSH_PRIVATE_KEY" ] || INFO "$SSH_PRIVATE_KEY does not exist so we'll generate one"
			SSH_PRIVATE_KEY="$2"
			shift 2
			;;
		-K|--ssh-keyscan-host)
			[ -n "$SSH_KEYSCAN_HOSTS" ] && SSH_KEYSCAN_HOSTS="$SSH_KEYSCAN_HOSTS $2" || SSH_KEYSCAN_HOSTS="$2"
			shift 2
			;;
		-D|--debug)
			DEBUG=1
			shift
			;;
		--cf-cli-url)
			CF_CLI_URL="$2"
			shift 2
			;;
		--cf-api-endpoint)
			CF_API_ENDPOINT="$2"
			shift 2
			;;
		--cf-username)
			CF_USERNAME="$2"
			shift 2
			;;
		--cf-password)
			CF_PASSWORD="$2"
			shift 2
			;;
		--cf-space)
			shift
			for j in $@; do
				case "$j" in
					-*)
						break
						;;
					*)
						[ -n "$CF_SPACE" ] && CF_SPACE="$CF_SPACE $j" || CF_SPACE="$j"
						shift
				esac
			done
			;;
		--cf-organisation)
			shift
			for j in $@; do
				case "$j" in
					-*)
						break
						;;
					*)
						[ -n "$CF_ORG" ] && CF_ORG="$CF_ORG $j" || CF_ORG="$j"
						shift
				esac
			done
			;;
		*)
			FATAL "Unknown option $1"
			;;
	esac
done

for m in CF_API_ENDPOINT CF_USERNAME CF_PASSWORD CF_SPACE CF_ORG; do
	eval v="\$$m"

	[ -z "$v" ] && FATAL "$m has not been set"

	unset v
done

if [ -z "$CF_URL_SET" ] && ! uname -s | grep -q 'Linux'; then
	FATAL "You must set -b|--cf-download-url to point to th location of the CF download for your machine"
fi

for _b in git unzip; do
	if ! which $_b >/dev/null 2>&1; then
		whoami | grep -Eq '^root$' || FATAL "You must be root to install $_b. Or you can install $_b and re-run this script"
		yum install -y "$_b"
	fi
done

# Ensure we are clean
[ -d deployment ] && rm -rf deployment
[ -d work ] || rm -rf work

mkdir -p deployment work

INFO 'Installing CF CLI'
if ! curl -Lo work/cf.tar.gz "$CF_CLI_URL"; then
	rm -f work/cf.tar.gz

	FATAL "Downloading CF CLI from '$CF_CLI_URL' failed"
fi

tar -zxvf work/cf.tar.gz -C work cf

cd deployment

configure_git_repo jenkins_home "$JENKINS_CONFIG_SEED_REPO" "${JENKINS_CONFIG_NEW_REPO:-NONE}" "${DEPLOY_JENKINS_CONFIG_SEED_REPO:-NONE}" "${DEPLOY_JENKINS_CONFIG_NEW_REPO:-NONE}"

git_push_repo_cleanup jenkins_home

# Disable initial config.xml - it'll get renamed by init.groovy
mv jenkins_home/config.xml jenkins_home/_config.xml

INFO 'Installing initial plugin(s)'
[ -d jenkins_home/plugins ] || mkdir -p jenkins_home/plugins

cd jenkins_home/plugins

download_plugins ${PLUGINS:-$DEFAULT_PLUGINS}

cd ../..

configure_git_repo jenkins_scripts "$JENKINS_SCRIPTS_REPO" "${DEPLOY_JENKINS_SCRIPTS_REPO:-NONE}"

# Cloudfoundry nobbles the .git or if its renamed it nobbles .git*/{branchs,objects,refs} - so we have to jump through a few hoops
tar -zcf jenkins_home_scripts.tgz jenkins_home jenkins_scripts

rm -rf jenkins_home jenkins_scripts

cd ../

download_jenkins_war "$JENKINS_RELEASE_TYPE"

cd deployment

# Explode the jar file
unzip ../jenkins-$JENKINS_RELEASE_TYPE.war

# We need to remove the manifest.mf, otherwise Cloudfoundry tries to be intelligent and run Main.class rather
# rather than deploying to Tomcat
# Sometimes we get MANIFEST.MF and sometimes we get manifest.mf
find META-INF -iname MANIFEST.MF -delete

# Allow disabling of CSP
if [ -n "$DISABLE_CSP" -a x"$DISABLE_CSP" != x"false" ]; then
	# Sanity check...
	[ -f WEB-INF/init.groovy ] && FATAL deployment/WEB-INF/init.groovy already exists

	cat >WEB-INF/init.groovy <<EOF
import hudson.model.*

println('Setting hudson.model.DirectoryBrowserSupport.CSP==""\n')
System.setProperty("hudson.model.DirectoryBrowserSupport.CSP", "")
EOF
fi

# Generate our manifest
cat >manifest.yml <<EOF
applications:
- name: $JENKINS_APPNAME
  memory: $JENKINS_MEMORY
  disk_quota: $JENKINS_DISK
  health-check-type: none
  instances: 1
  env:
    JBP_CONFIG_SPRING_AUTO_RECONFIGURATION: '{enabled: false}'
EOF



# Suck in the SSH keys for our Git repos
for i in $JENKINS_CONFIG_REPO $JENKINS_CONFIG_SEED_REPO $JENKINS_SCRIPTS_REPO; do
	# We only want to scan a host if we are connecting via SSH
	echo $i | grep -Eq '^((https?|file|git)://|~?/)' && continue

	echo $i | sed $SED_OPT -e 's,^[a-z]+://([^@]+@)([a-z0-9\.-]+)([:/].*)?$,\2,g' | xargs ssh-keyscan -T $SSH_KEYSCAN_TIMEOUT >>known_hosts
done

# ... and any extra keys
for i in $SSH_KEYSCAN_HOSTS; do
	ssh-keyscan -T $SSH_KEYSCAN_TIMEOUT $i
done | sort -u >>known_hosts

if [ ! -f "$ORIGINAL_DIR/$SSH_PRIVATE_KEY" ]; then
	# Ensure we have a key
	ssh-keygen -t rsa -f "id_rsa" -N '' -C "$JENKINS_APPNAME"

	INFO "You will need to add the following public key to the correct repositories to allow access"
	INFO "We'll print this again at the end in case you miss this time"
	cat id_rsa.pub
else
	grep -q 'BEGIN DSA PRIVATE KEY' "$ORIGINAL_DIR/$SSH_PRIVATE_KEY" && KEY_NAME="id_dsa"
	grep -q 'BEGIN RSA PRIVATE KEY' "$ORIGINAL_DIR/$SSH_PRIVATE_KEY" && KEY_NAME="id_rsa"

	[ -z "$KEY_NAME" ] && FATAL Unable to determine ssh key type

	cp "$ORIGINAL_DIR/$SSH_PRIVATE_KEY" $KEY_NAME


	# Ensure our key has the correct permissions, otherwise ssh-keygen fails
	chmod 0600 $KEY_NAME

	INFO Calculating SSH public key from "$SSH_PRIVATE_KEY"
	ssh-keygen -f $KEY_NAME -y >$KEY_NAME.pub
fi

mkdir -p .profile.d

# Preconfigure our environment
cat >.profile.d/00_jenkins_preconfig.sh <<'EOF_OUTER'
set -e

# We use WEBAPP_HOME to find the jenkins-cli.jar
export WEBAPP_HOME="$PWD"

export JENKINS_HOME="$WEBAPP_HOME/jenkins_home"
export SCRIPTS_DIR="$WEBAPP_HOME/jenkins_scripts"

# Cloudfoundry resets HOME as /home/$USER/app
# https://docs.run.pivotal.io/devguide/deploy-apps/environment-variable.html#HOME
# https://github.com/cloudfoundry/java-buildpack/issues/300
export REAL_HOME="/home/$USER"

tar -zxf jenkins_home_scripts.tgz

cd "$JENKINS_HOME"

[ -f _init.groovy ] && cp _init.groovy init.groovy

cd -

# Create ~/.ssh in the correct place. CF incorrectly sets HOME=/home/$USER/app despite it pointing to
# /home/$USER in /etc/passwd
[ -d "$REAL_HOME/.ssh" ] || mkdir -m 0700 -p $REAL_HOME/.ssh

# Configure SSH
for i in dsa rsa; do
	[ -f "id_$i" -a -f "id_$i.pub" ] || continue

	mv id_$i id_$i.pub $REAL_HOME/.ssh/
done

cat known_hosts >>$REAL_HOME/.ssh/known_hosts

# Remove our temporary files
rm -f known_hosts id_rsa id_rsa.pub
rm -f jenkins_home_scripts.tgz

cat >.profile.d/00_jenkins_config <<EOF
export WEBAPP_HOME="$WEBAPP_HOME"
export SCRIPTS_DIR="$SCRIPTS_DIR"
export JENKINS_HOME="$JENKINS_HOME"
EOF

# No point in repeating ourselves, so we remove this script and assume things stay static
rm -f .profile.d/00_jenkins_preconfig.sh
EOF_OUTER

# These two profiles are here to workaround Cloudfoundry's lack of persistent storage.  If an application crashes,
# shutdown or moves local storage is lost
#
# Until we add the new SSH key this will fail, this isn't a concern as a fresh deployment should have an identical
# config to that held in Git
cat >.profile.d/01_jenkins_git_update.sh <<'EOF'
cd "$JENKINS_HOME"

echo If the SSH key has not yet been added to the Git repositories you may see errors here
git pull origin master || :

cd -

cd "$SCRIPTS_DIR"

git pull origin master || :

cd -
EOF

"$CF_CLI" login -a "$CF_API_ENDPOINT" -u "$CF_USERNAME" -p "$CF_PASSWORD" -o "$CF_ORG" -s "$CF_SPACE"

"$CF_CLI" push "$JENKINS_APPNAME"

INFO
INFO "Jenkins should be available shortly"
INFO
INFO "Please wait whilst things startup... (this could take a while)"

if [ -n "$DEBUG" ]; then
	INFO "Debug has been enabled"
	INFO "Output Jenkins logs. Please do not interrupt, things should exit once Jenkins has loaded correctly"

	sleep 10
fi

"$CF_CLI" logs "$JENKINS_APPNAME" | tee "$JENKINS_APPNAME-deploy.log" | awk -v debug="$DEBUG" '{
	if($0 ~ /Jenkins is fully up and running/)
		exit 0

	if(debug)
		print $0

	if($0 ~ /(Jenkins stopped|Failed to list up hs_err_pid files)/){
		printf("There was an issue deploying Jenkins, try restarting, otherwise redeploy")
		exit 1
	}
}' && SUCCESS=1 || SUCCESS=0

# We try our best to get things to work properly, but both Jenkins and Cloudfoundry work against us:
# Jenkins, often, doesn't correctly load all of the plugins - so we run the plugin loading 3 times
# Cloudfoundry sometimes performs a port check the very moment Jenkins is restarted resulting in a
# redeploy - so we've disabled the port checking.
INFO
INFO
if [ x"$SUCCESS" = x"1" ]; then
	INFO "Jenkins may still be loading, so hold tight"
	INFO
	INFO "You will need to add the following public key to ${JENKINS_CONFIG_NEW_REPO:-$JENKINS_CONFIG_SEED_REPO}"
	INFO
	cat "$SSH_PRIVATE_KEY"
	INFO
	# If we can find the log line of the failed plugin we could add it to the above AWK section and present a warning to load
	# a given plugin - as we run the plugin load three times, we'd need a little bit of logic there
	INFO "Even though Jenkins may have finished loading, its possible not all of the plugins were loaded. Unfortunately"
	INFO "this is difficult to detect - so run the 'Backup Jenkins' job and ensure the plugin list doesn't have any changes"
	INFO "or at the very least looks sensible"
	# Need to make domain name configurable - env var of domain may be available, or easily set during deployment
	INFO "Check if there is any data under: https://$JENKINS_APPNAME.apps.${CF_INSTANCE_DOMAIN:-CF_DOMAIN}/administrativeMonitor/OldData/manage"
	INFO "if there is, check its sensible, otherwise redeploy"
	INFO
	INFO "Your Jenkins should will shortly be accessible from https://$JENKINS_APPNAME.apps.${CF_INSTANCE_DOMAIN:-CF_DOMAIN}"
else
	tail -n20 "$JENKINS_APPNAME-deploy-deploy.log"

	FATAL "Jenkins failed, please retry. Check $JENKINS_APP_NAME-deploy.log for more details"
fi
