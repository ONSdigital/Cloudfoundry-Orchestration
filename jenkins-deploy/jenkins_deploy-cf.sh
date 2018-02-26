#!/bin/sh
#
# Deploy Jenkins to CF
#
# Variables:
#	CF_CLI_URL=[Location of Cloudfoundry CLI]
#	... other variables are used, but these can be seen under the 'Parse options' section

set -e


###########################################################
#
# Functionality shared between all of the Jenkins deployment scripts
BASE_DIR="`dirname $0`"
COMMON_JENKINS_DEPLOY_SH="$BASE_DIR/common-jenkins-deploy.sh"

if [ ! -f "$COMMON_JENKINS_DEPLOY_SH" ]; then
	echo "Unable to find $COMMON_JENKINS_DEPLOY_SH"

	exit 1
fi

. "$COMMON_JENKINS_DEPLOY_SH"
###########################################################

###########################################################
#
# Cloudfoundry specific default values
#
# 4096M minimum to avoid complaints about insufficient cache
JENKINS_MEMORY="${JENKINS_MEMORY:-4096M}"
# 2048M maximum allow storage
JENKINS_DISK="${JENKINS_DISK:-2048M}"

# Default to assuming we are running on Linux and x86_64
CF_CLI_URL="${CF_CLI_URL:-https://cli.run.pivotal.io/stable?release=linux64-binary&source=github-rel}"
CF_CLI="$PWD/work/cf"
###########################################################

###########################################################
#
# Parse options
#
for i in `seq 1 $#`; do
	[ -z "$1" ] && break

	case "$1" in
		-n|--name)
			# Cloudfoundry application name
			JENKINS_APPNAME="$2"
			shift 2
			;;
		-r|--release-type)
			# Jenkins release type 'stable' or 'latest'
			JENKINS_RELEASE_TYPE="$2"
			shift 2
			;;
		-m|--memory)
			# Cloudfoundry application memory
			JENKINS_MEMORY="$2"
			shift 2
			;;
		-d|--disk-quota)
			# Cloudfoundry disk quota
			JENKINS_DISK="$2"
			shift 2
			;;
		-c|--config-repo)
			# Git repository to hold configuration post-deployment
			JENKINS_CONFIG_NEW_REPO="$2"
			shift 2
			;;
		--deploy-config-repo)
			# ... as above, but for use during the deployment phase if the URLs are different
			DEPLOY_JENKINS_CONFIG_NEW_REPO="$2"
			shift 2
			;;
		-C|--config-seed-repo)
			# Git repository that holds the existing or seed configuration
			JENKINS_CONFIG_SEED_REPO="$2"
			shift 2
			;;
		--deploy-config-seed-repo)
			# ... as above, but for use during the deployment phase if the URLs are different
			DEPLOY_JENKINS_CONFIG_SEED_REPO="$2"
			shift 2
			;;
		-S|--scripts-repo)
			# Git repository that contains the Jenkins scripts
			JENKINS_SCRIPTS_REPO="$2"
			shift 2
			;;
		--ssh-key)
			# SSH private key
			SSH_PRIVATE_KEY="$2"

			[ -n "$SSH_PRIVATE_KEY" -a ! -f "$SSH_PRIVATE_KEY" ] && FATAL "Unable to find $SSH_PRIVATE_KEY"

			SSH_PRIVATE_KEY_FILENAME="`basename "$SSH_PRIVATE_KEY"`"

			shift 2
			;;
		--ssh-user-config)
			# Used to configure ~/.ssh/config to use a specific SSH username to access the host
			SSH_USER_CONFIG="$2"
			shift 2
			;;
		--no-auto-plugin-install)
			# Do not automatically install any plugins - use the --plugins option to add plugins, or add the plugins
			# manually post-install
			NO_PLUGIN_INSTALL=1
			;;
		--no-auto-plugin-install)
			# Do not automatically install any plugins - use the --plugins option to add plugins, or add the plugins
			# manually post-install
			NO_PLUGIN_INSTALL=1
			;;
		--deploy-scripts-repo)
			# ... as above, but for use during the deployment phase if the URLs are different
			DEPLOY_JENKINS_SCRIPTS_REPO="$2"
			shift 2
			;;
		--jenkins-stable-url)
			# URL of the stable Jenkins WAR file
			JENKINS_STABLE_WAR_URL="$2"
			shift 2
			;;
		--jenkins-latest-url)
			# URL of the latest Jenkins WAR file
			JENKINS_LATEST_WAR_URL="$2"
			shift 2
			;;
		-P|--plugins)
			# Comma separated list of URLs that contain the plugins to install
			[ -z "$PLUGINS" ] && PLUGINS="$2" || PLUGINS="$PLUGINS,$2"
			shift 2
			;;
		-X|--disable-csp-security)
			# Disable cross site scripting security
			DISABLE_CSP=1
			shift
			;;
		-K|--ssh-keyscan-host)
			# Additional SSH hosts to scan and add to ~/.ssh/known_hosts
			[ -n "$SSH_KEYSCAN_HOSTS" ] && SSH_KEYSCAN_HOSTS="$SSH_KEYSCAN_HOSTS $2" || SSH_KEYSCAN_HOSTS="$2"
			shift 2
			;;
		-D|--debug)
			# Run the script with 'set -x' set
			set -x
			shift
			;;
		--cf-cli-url)
			# URL that contains a tar.gz file of the Cloudfoundry CLI
			CF_CLI_URL="$2"
			shift 2
			;;
		--cf-api-endpoint)
			# Cloudfoundry API endpoint
			CF_API_ENDPOINT="$2"
			shift 2
			;;
		--cf-username)
			# Cloudfoundry Username
			CF_USERNAME="$2"
			shift 2
			;;
		--cf-password)
			# Cloudfoundry Password
			CF_PASSWORD="$2"
			shift 2
			;;
		--cf-space)
			# Cloudfoundry Space - may contain spaces, but may not contain leading hypens
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
			# Cloudfoundry Organisation - may contain spaces, but may not contain leading hypens
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
###########################################################

# Ensure we have all of the required Cloudfoundry options/variables
for m in CF_API_ENDPOINT CF_USERNAME CF_PASSWORD CF_SPACE CF_ORG; do
	eval v="\$$m"

	[ -z "$v" ] && FATAL "$m has not been set"

	unset v
done

# Check that an alternative CF_URL has been set if we are not running on Linux
if [ -z "$CF_URL_SET" ] && ! uname -s | grep -q 'Linux'; then
	FATAL 'You must set --cf-download-url to point to the location of the CF download for your machine'
fi

# Ensure we have the basic tools installed for us to perform a deployment
for _b in git unzip; do
	if ! which $_b >/dev/null 2>&1; then
		whoami | grep -Eq '^root$' || FATAL "You must be root to install $_b. Or you can install $_b and re-run this script"
		yum install -y "$_b"
	fi
done

# Ensure we are clean
[ -d deployment ] && rm -rf deployment
[ -d work ] || rm -rf work

# Ensure we have the required directories
mkdir -p deployment work

INFO 'Installing CF CLI'
if ! curl -Lo work/cf.tar.gz "$CF_CLI_URL"; then
	rm -f work/cf.tar.gz

	FATAL "Downloading CF CLI from '$CF_CLI_URL' failed"
fi

# Extract the CF CLI
tar -zxvf work/cf.tar.gz -C work cf

cd deployment

# We have to jump through a few hoops as the Git repository URL(s) used during deployment may not be the same as the ones that will be used once we are deployed
configure_git_repo jenkins_home "$JENKINS_CONFIG_SEED_REPO" "${JENKINS_CONFIG_NEW_REPO:-NONE}" "${DEPLOY_JENKINS_CONFIG_SEED_REPO:-NONE}" "${DEPLOY_JENKINS_CONFIG_NEW_REPO:-NONE}"

# Fix the Git repository source names and push
git_push_repo_cleanup jenkins_home

# Disable initial config.xml - it'll get renamed by init.groovy
mv jenkins_home/config.xml jenkins_home/_config.xml

INFO 'Installing initial plugin(s)'
[ -d jenkins_home/plugins ] || mkdir -p jenkins_home/plugins

cd jenkins_home/plugins

# Download and install any required Jenkins plugins
download_plugins $PLUGINS

cd ../..

# ... again the Git repository URL we use to deploy from may not be the same as the one we use when we are deployed
configure_git_repo jenkins_scripts "$JENKINS_SCRIPTS_REPO" "${DEPLOY_JENKINS_SCRIPTS_REPO:-NONE}"

# Cloudfoundry nobbles the .git or if its renamed it nobbles .git*/{branchs,objects,refs} - so we have to jump through a few hoops
tar -zcf jenkins_home_scripts.tgz jenkins_home jenkins_scripts

# Clean up the old folders now we have archives of the folders
rm -rf jenkins_home jenkins_scripts

cd ../

# Download the correct Jenkins war file
download_jenkins_war "$JENKINS_RELEASE_TYPE"

cd deployment

# Explode the jar file
unzip ../jenkins-$JENKINS_RELEASE_TYPE.war

# We need to remove the manifest.mf, otherwise Cloudfoundry tries to be intelligent and run Main.class rather
# rather than deploying to Tomcat
# Sometimes we get MANIFEST.MF and sometimes we get manifest.mf - we can probably blame Windows and/or OSX for this
find META-INF -iname MANIFEST.MF -delete

# Allow disabling of CSP
if [ -n "$DISABLE_CSP" -a x"$DISABLE_CSP" != x"false" ]; then
	# Sanity check...
	[ -f WEB-INF/init.groovy ] && FATAL 'deployment/WEB-INF/init.groovy already exists'

	INFO 'Disabling cross site scripting protection'
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

# Generate known_hosts that will eventually become ~/.ssh/known_hosts
scan_ssh_hosts $JENKINS_CONFIG_REPO $JENKINS_CONFIG_SEED_REPO $JENKINS_SCRIPTS_REPO $SSH_KEYSCAN_HOSTS >known_hosts


if [ -n "$SSH_PRIVATE_KEY" ]; then
	# If we have one in the correct location we copy it to the location we need
	cp "$SSH_PRIVATE_KEY" "$SSH_PRIVATE_KEY_FILENAME"

	# Ensure our key has the correct permissions, otherwise ssh-keygen fails
	chmod 0600 "$SSH_PRIVATE_KEY_FILENAME"

	INFO "Calculating SSH public key from 'id_rsa'"
	ssh-keygen -f "$SSH_PRIVATE_KEY_FILENAME" -y >"$SSH_PRIVATE_KEY_FILENAME.pub"
else
	# If we don't have an SSH key we generate one
	ssh-keygen -t rsa -f id_rsa -N '' -C "$JENKINS_APPNAME"

	INFO 'You will need to add the following public key to the correct repositories to allow access'
	INFO "We'll print this again at the end in case you miss this time"
	cat id_rsa.pub
fi

# Directory to hold our pre-run scripts - these scripts are executed prior to starting Jenkins
mkdir -p .profile.d

# Preconfigure our environment
cat >.profile.d/00_jenkins_preconfig.sh <<'EOF_OUTER'
set -e

# We use WEBAPP_HOME to find the jenkins-cli.jar
export WEBAPP_HOME="$PWD"

# Set some vars that we use later
export JENKINS_HOME="$WEBAPP_HOME/jenkins_home"
export SCRIPTS_DIR="$WEBAPP_HOME/jenkins_scripts"

# Cloudfoundry resets HOME as /home/$USER/app
# https://docs.run.pivotal.io/devguide/deploy-apps/environment-variable.html#HOME
# https://github.com/cloudfoundry/java-buildpack/issues/300
export REAL_HOME="/home/$USER"

# Extract our archived scripts and Jenkins configuration - this ensures we retain the .git dir
tar -zxf jenkins_home_scripts.tgz

cd "$JENKINS_HOME"
EOF_OUTER

if [ -n "$NO_PLUGIN_INSTALL" ]; then
	INFO 'Not enabling Groovy plugin install script'
else
	INFO 'Enabling Groovy plugin install script'
	cat >>.profile.d/00_jenkins_preconfig.sh <<'EOF_OUTER'
# Rename our Groovy init script so that Jenkins runs it when it starts.  Once run, the script will
# delete itself. We do it this way to avoid confusing Git
cp _init.groovy init.groovy
EOF_OUTER
fi

cat >>.profile.d/00_jenkins_preconfig.sh <<'EOF_OUTER'
# Rename our Groovy init script so that Jenkins runs it when it starts.  Once run, the script will
# delete itself. We do it this way to avoid confusing Git
[ -f _init.groovy ] && cp _init.groovy init.groovy

cd -

# Create ~/.ssh in the correct place. CF incorrectly sets HOME=/home/$USER/app despite it pointing to
# /home/$USER in /etc/passwd
[ -d "$REAL_HOME/.ssh" ] || mkdir -m 0700 -p $REAL_HOME/.ssh

# Configure SSH
mv id_rsa id_rsa.pub $REAL_HOME/.ssh/
EOF_OUTER


if [ -n "$SSH_HOST_CONFIG" -a "$SSH_USER_CONFIG" ]; then
	INFO "Setting up SSH to connect to $SSH_HOST_CONFIG as $SSH_USER_CONFIG"
	cat >>.profile.d/00_jenkins_preconfig.sh <<EOF_OUTER

	if [ ! -f $REAL_HOME/.ssh/config ]; then
		cat >$REAL_HOME/.ssh/config <<EOF_INNER
Host $SSH_HOST_CONFIG
	User $SSH_USER_CONFIG
	IdentifyFile ~/.ssh/${SSH_PRIVATE_KEY_FILENAME:-id_rsa}
EOF_INNER
	fi
EOF_OUTER
fi

cat >>.profile.d/00_jenkins_preconfig.sh <<EOF_OUTER
# Set up SSH
chmod 0600 ${SSH_PRIVATE_KEY_FILENAME:-id_rsa}

mv ${SSH_PRIVATE_KEY_FILENAME:-id_rsa} $REAL_HOME/.ssh/

# Create the ~/.ssh/known_hosts
cat known_hosts >>$REAL_HOME/.ssh/known_hosts

# Remove our temporary files
rm -f known_hosts id_rsa id_rsa.pub
rm -f jenkins_home_scripts.tgz

# Now we've configured ourselves we generate a new config file that only contains some vars that Jenkins will use
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

# Ensure we have the latest version of the scripts
git pull origin master || :

cd -
EOF

INFO "Logging into $CF_API_ENDPOINT as $CF_USERNAME under $CF_ORG/$CF_SPACE"
"$CF_CLI" login -a "$CF_API_ENDPOINT" -u "$CF_USERNAME" -p "$CF_PASSWORD" -o "$CF_ORG" -s "$CF_SPACE"

INFO "Pushing Jenkins as $JENKINS_APP_NAME"
"$CF_CLI" push "$JENKINS_APPNAME"

INFO
INFO 'Jenkins should be available shortly'
INFO
INFO 'Please wait whilst things startup... (this could take a while)'

# Tail the Jenkins logs and report when things have started
CF_COLOR=false "$CF_CLI" logs "$JENKINS_APPNAME" | tee "$JENKINS_APPNAME-deploy.log" | awk -v debug="$DEBUG" '{
	if($0 ~ /Jenkins is fully up and running/)
		exit 0

	if(debug)
		print $0

	if($0 ~ /(Jenkins stopped|Failed to list up hs_err_pid files)/){
		printf("There was an issue deploying Jenkins, try restarting, otherwise redeploy")
		exit 1
	}
}' && SUCCESS=1 || SUCCESS=0

# Find the Jenkins URL
JENKINS_URL="`CF_COLOR=false "$CF_CLI" app "$JENKINS_APPNAME" | awk '/^routes:/{printf("https://%s",$NF)}'`"

# We try our best to get things to work properly, but both Jenkins and Cloudfoundry work against us:
# Jenkins, often, doesn't correctly load all of the plugins - so we run the plugin loading 3 times
# Cloudfoundry sometimes performs a port check the very moment Jenkins is restarted resulting in a
# redeploy - so we've disabled the port checking.
INFO
INFO
if [ x"$SUCCESS" = x"1" ]; then
	INFO 'Jenkins may still be loading, so hold tight'
	INFO
	INFO "You will need to add the following public key to ${JENKINS_CONFIG_NEW_REPO:-$JENKINS_CONFIG_SEED_REPO}"
	INFO
	cat id_rsa
	INFO
	# If we can find the log line of the failed plugin we could add it to the above AWK section and present a warning to load
	# a given plugin - as we run the plugin load three times, we'd need a little bit of logic there
	INFO 'Even though Jenkins may have finished loading, its possible not all of the plugins were loaded. Unfortunately'
	INFO "this is difficult to detect - so run the 'Backup Jenkins' job and ensure the plugin list doesn't have any changes"
	INFO 'or at the very least looks sensible'
	# Need to make domain name configurable - env var of domain may be available, or easily set during deployment
	INFO "Check if there is any data under: $JENKINS_URL/administrativeMonitor/OldData/manage"
	INFO 'if there is, check its sensible, otherwise redeploy'
	INFO
	INFO "Your Jenkins should will shortly be accessible from $JENKINS_URL"
else
	tail -n20 "$JENKINS_APPNAME-deploy-deploy.log"

	FATAL "Jenkins failed, please retry. Check $JENKINS_APP_NAME-deploy.log for more details"
fi
