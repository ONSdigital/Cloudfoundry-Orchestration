#!/bin/sh
#
# Deploy a Jenkins master or slave to the local server
#
# Variables:
#	ROOT_USER=[Root user]
#	ROOT_GROUP=[Root user's group]
#	LOG_ROTATE_COUNT=[Number of rotated logs to keep'
#	LOG_ROTATE_SIZE=[Rotate logs at this size]
#	LOG_ROTATE_FREQUENCY=[Rotate logs this frequently]
#	SSH_KEYSCAN_TIMEOUT=[SSH keyscan timeout]
#	JENKINS_JNLP_CHECK_DELAY==[Delay, in seconds, between Jenkins availability check]
#	JENKINS_JNLP_CHECK_ATTEMPTS=[Number of checks for Jenkins availability before giving up]
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


install_packages(){
	for _i in $@; do
		if ! rpm --quiet -q "$_i"; then
			INFO ". installing $_i"
			yum install -q -y "$_i"
		fi
	done
}

###########################################################
#
# Local install specific default values
#
ROOT_USER="${ROOT_USER:-root}"
ROOT_GROUP="${ROOT_GROUP:-wheel}"
#
JENKINS_USER="${JENKINS_USER:-jenkins}"
JENKINS_GROUP="${JENKINS_GROUP:-jenkins}"
#
#
INSTALL_BASE_DIR="${INSTALL_BASE_DIR:-/opt}"
LOG_ROTATE_COUNT="${LOG_ROTATE_COUNT:-10}"
LOG_ROTATE_SIZE="${LOG_ROTATE_SIZE:-10m}"
LOG_ROTATE_FREQUENCY="${LOG_ROTATE_FREQUENCY:-daily}"
# Fonts & fontconfig are required for Java/AWT
BASE_PACKAGES='git java-1.8.0-openjdk-headless dejavu-sans-fonts fontconfig unzip'
MASTER_PACKAGES='httpd mod_ssl'
SSH_KEYSCAN_TIMEOUT="${SSH_KEYSCAN_TIMEOUT:-10}"
#
CONFIGURE_SLAVE_CONNECTIVITY=1
FIX_FIREWALL=1
FIX_SELINUX=1

# In seconds
JENKINS_JNLP_CHECK_DELAY="${JENKINS_JNLP_CHECK_DELAY:-5}"
JENKINS_JNLP_CHECK_ATTEMPTS="${JENKINS_JNLP_CHECK_ATTEMPTS:-100}"
###########################################################

whoami | grep -Eq "^$ROOT_USER$" || FATAL "This script MUST be run as $ROOT_USER"

###########################################################
#
# Parse options
for i in `seq 1 $#`; do
	[ -z "$1" ] && break

	case "$1" in
		-n|--name)
			# Jenkins application name, Jenkins will be install under
			JENKINS_APPNAME="$2"
			shift 2
			;;
		--master-url)
			# The URL the Jenkins application run on (eg http://192.168.6.66:8080) - required if deploying a slave
			JENKINS_MASTER_URL="$2"
			shift 2
			;;
		--jenkins-slave-name)
			# The name of the Jenkins slave - required if deploying a slave
			JENKINS_SLAVE_NAME="$2"
			shift 2
			;;
		--jenkins-slave-secret)
			# Jenkins slave secret - required if deploying a slave
			JENKINS_SLAVE_SECRET="$2"
			shift 2
			;;
		--disable-slave-connectivity)
			# Do not configure the master to handle a slave (eg do not allow JNLP through the local firewall)
			unset CONFIGURE_SLAVE_CONNECTIVITY
			shift
			;;
		-r|--release-type)
			# Jenkins release type 'stable' or 'latest'
			JENKINS_RELEASE_TYPE="$2"
			shift 2
			;;
		-c|--config-repo)
			# Git repository to hold configuration post-deployment
			JENKINS_CONFIG_NEW_REPO="$2"
			shift 2
			;;
		-C|--config-seed-repo)
			# Git repository that holds the existing or seed configuration
			JENKINS_CONFIG_SEED_REPO="$2"
			shift 2
			;;
		-S|--scripts-repo)
			# Git repository that contains the Jenkins scripts
			JENKINS_SCRIPTS_REPO="$2"
			shift 2
			;;
		--no-auto-plugin-install)
			# Do not automatically install any plugins - use the --plugins option to add plugins, or add the plugins
			# manually post-install
			NO_PLUGIN_INSTALL=1
			;;
		--no-fix-firewall)
			# Do not configure the firewall
			unset FIX_FIREWALL
			shift
			;;
		--no-fix-selinux)
			# Do not configure SELinux
			unset FIX_SELINUX
			shift
			;;
		--jenkins-base-install-dir)
			# Base directory where we create the directory to hold Jenkins 
			INSTALL_BASE_DIR="$2"
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
		-K|--ssh-keyscan-host)
			# Additional SSH hosts to scan and add to ~/.ssh/known_hosts
			[ -n "$SSH_KEYSCAN_HOSTS" ] && SSH_KEYSCAN_HOSTS="$SSH_KEYSCAN_HOSTS $2" || SSH_KEYSCAN_HOSTS="$2"
			shift 2
			;;
		*)
			FATAL "Unknown option $1"
			;;
	esac
done
###########################################################

DEPLOYMENT_DIR="$INSTALL_BASE_DIR/$JENKINS_APPNAME"

if [ -z "$JENKINS_MASTER_URL" ]; then
	# If we are not being deployed as a slave ensure we have the required repositories

	if [ -z "$JENKINS_CONFIG_SEED_REPO" ]; then
		FATAL 'No JENKINS_CONFIG_SEED_REPO provided'
	fi

	if [ -z "$JENKINS_SCRIPTS_REPO" ]; then
		FATAL 'No JENKINS_SCRIPTS_REPO provided'
	fi
elif [ -z "$JENKINS_SLAVE_SECRET" ]; then
	FATAL "No Jenkins secret provided. Cannot connect to Jenkins master. The secret will be available from $JENKINS_MASTER_URL/computer/$JENKINS_SLAVE_NAME/ - assuming the slave name is correct"
fi

# Is there already a Jenkins deployed?
[ -d "$DEPLOYMENT_DIR" ] && FATAL "Deployment '$DEPLOYMENT_DIR' already exists, please remove"

INFO "Creating $DEPLOYMENT_DIR layout"
mkdir -p "$DEPLOYMENT_DIR"/{bin,config,.ssh}

INFO 'Checking if all required packages are installed - this may take a while'
install_packages $BASE_PACKAGES

if [ -n "$FIX_SELINUX" ]; then
	# Check if we have SELinux enabled
	INFO 'Determining SELinux status'
	sestatus 2>&1 >/dev/null && SELINUX_ENABLED=true
fi

INFO "Checking if we need to add the '$JENKINS_USER' user"
if ! id $JENKINS_USER 2>&1 >/dev/null; then
	INFO "Adding $JENKINS_USER"
	useradd -d "$DEPLOYMENT_DIR" -r -s /sbin/nologin "$JENKINS_USER"
fi

cd "$DEPLOYMENT_DIR"

if [ -n "$JENKINS_MASTER_URL" ]; then
	INFO 'Deploying Jenkins slave'
	JENKINS_APPNAME="$JENKINS_APPNAME-${JENKINS_SLAVE_NAME:-slave}"
	JENKINS_AGENT_JAR="$DEPLOYMENT_DIR/bin/agent.jar"
	
	mkdir "$DEPLOYMENT_DIR/slave"

	INFO 'Determining JNLP port'
	JENKINS_JNLP_PORT="`curl -fi "$JENKINS_MASTER_URL/tcpSlaveAgentListener/" | awk '/^X-Jenkins-JNLP-Port:/{print $NF}'`"

	[ -z "$JENKINS_JNLP_PORT" ] && FATAL 'Unable to determine Jenkins JNLP port'
else
	INFO 'Checking if further packages are installed - this may take a while'
	install_packages $MASTER_PACKAGES

	INFO 'Deploying Jenkins master'

	# We have to jump through a few hoops as the Git repository URL(s) used during deployment may not be the same as the ones that will be used once we are deployed
	configure_git_repo jenkins_home "$JENKINS_CONFIG_SEED_REPO" "${JENKINS_CONFIG_NEW_REPO:-NONE}"

	# Fix the Git repository source names and push
	git_push_repo_cleanup jenkins_home

	INFO 'Setting up Jenkins configuration'
	cd "$DEPLOYMENT_DIR/jenkins_home"

	if [ -n "$NO_PLUGIN_INSTALL" ]; then
		INFO 'Not enabling Groovy plugin install script'
	else
		INFO 'Enabling Groovy plugin install script'
		# Rename our Groovy init script so that Jenkins runs it when it starts.  Once run, the script will
		# delete itself. We do it this way to avoid confusing Git
		cp _init.groovy init.groovy
	fi

	# Disable initial config.xml - it'll get renamed by init.groovy
	mv config.xml _config.xml

	cd ..

	# ... again the Git repository URL we use to deploy from may not be the same as the one we use when we are deployed
	configure_git_repo jenkins_scripts "$JENKINS_SCRIPTS_REPO"

	cd "$DEPLOYMENT_DIR"

	INFO 'Installing initial plugin(s)'
	[ -d jenkins_home/plugins ] || mkdir -p jenkins_home/plugins

	cd "$DEPLOYMENT_DIR/jenkins_home/plugins"

	# Download and install any required Jenkins plugins
	download_plugins $PLUGINS

	cd "$DEPLOYMENT_DIR"

	# Download the correct Jenkins war file
	download_jenkins_war "$JENKINS_RELEASE_TYPE"

	cd bin

	INFO 'Extracting Jenkins CLI'
	unzip -qqj "$DEPLOYMENT_DIR/jenkins-$JENKINS_RELEASE_TYPE.war" WEB-INF/jenkins-cli.jar

	cd - 2>&1 >/dev/null

	INFO 'Creating httpd reverse proxy setup'
	cat >"/etc/httpd/conf.d/$JENKINS_APPNAME-proxy.conf" <<EOF
	ProxyPass         "/" "http://127.0.0.1:8080/"
	ProxyPassReverse  "/" "http://127.0.0.1:8080/"
EOF

	if [ -n "$FIX_FIREWALL" ]; then
		INFO 'Permitting access to HTTP'
		firewall-cmd -q --permanent --add-service=http

		INFO 'Reloading firewall'
		firewall-cmd -q --reload
	fi

	# Generate the Jenkins user's ~/.ssh/known_hosts
	scan_ssh_hosts $JENKINS_CONFIG_REPO $JENKINS_CONFIG_SEED_REPO $JENKINS_SCRIPTS_REPO $SSH_KEYSCAN_HOSTS >"$DEPLOYMENT_DIR/.ssh/known_hosts"

	INFO 'Enabling and starting httpd'
	systemctl start httpd
	systemctl enable httpd

fi

if [ -d "/var/log/$JENKINS_APPNAME" ]; then
	INFO 'Clearing existing log directory'

	rm -rf "/var/log/$JENKINS_APPNAME"
fi

INFO 'Creating Jenkins log directory'
mkdir -p "/var/log/$JENKINS_APPNAME"

INFO "Creating $JENKINS_APPNAME configuration"
cat >"$DEPLOYMENT_DIR/config/$JENKINS_APPNAME.config" <<EOF
export JENKINS_HOME='$DEPLOYMENT_DIR/jenkins_home'
export SCRIPTS_DIR='$DEPLOYMENT_DIR/jenkins_scripts'
export JENKINS_CLI_JAR='$DEPLOYMENT_DIR/bin/jenkins-cli.jar'
export JENKINS_LOCATION='localhost:8080'
EOF

INFO 'Creating update script'
cat >"$DEPLOYMENT_DIR/bin/update.sh" <<EOF
#!/bin/sh
#
# Update script
#
# Original invocation: $INVOCATION_ORIGINAL
#
if [ -z "$1" -o x"$1" != x'safe' ]; then
	echo Warning...
	echo ... this script was automatically generated during the installation process
	echo ... it may have lost any quoting and escaping, so please check the script
	echo ... before running it
	echo
	echo To run the script after you have confirmed it will work, or after changes
	echo have been made to make it work please run it with the 'safe' option, eg
	echo
	echo $0 safe

	exit 1
fi
EOF

# Adjust our invocation args so that it can be run again to update Jenkins
awk '{
	if($0 ~ / (-C|--config-seed-repo) / && $0 ~ / (-c|--config-repo) /){
		print "YES"
		gsub(" (-C|--config-seed-repo) [^ ]+($| )"," ")
		gsub(" (-c|--config-repo) "," --config-seed-repo ")
	}

	print $0
}' <<EOF >>"$DEPLOYMENT_DIR/bin/update.sh"
$INVOCATION_ORIGINAL
EOF

INFO 'Checking if we need to set a proxy'
if [ -f /etc/wgetrc ] && grep '^http_proxy *= *' /etc/wgetrc; then
	sed -e $SED_OPT 's/^http_proxy *= *(.*) *$/export http_proxy='"'"'\1'"'"'/g' /etc/wgetrc >>"$DEPLOYMENT_DIR/config/$JENKINS_APPNAME.config"
fi

INFO 'Creating startup script'
cat >>"$DEPLOYMENT_DIR/bin/$JENKINS_APPNAME-startup.sh" <<EOF
#!/bin/sh

set -e

# Basic sanity check
if [ x'$JENKINS_USER' != x"\$USER" ]; then
	FATAL 'This startup script MUST be run as $JENKINS_USER'

	exit 1
fi

# Read our global config if it exists
[ -f '/etc/sysconfig/$JENKINS_APPNAME' ] && . '/etc/sysconfig/$JENKINS_APPNAME'

# Rotate our previous log - we read the new log during deployment, so we don't want to confuse ourselves by having old startup data in the log file
if [ -f '/var/log/$JENKINS_APPNAME/$JENKINS_APPNAME.log' ]; then
	mv '/var/log/$JENKINS_APPNAME/$JENKINS_APPNAME.log' '/var/log/$JENKINS_APPNAME/$JENKINS_APPNAME.log.previous'

	[ -f '/var/log/$JENKINS_APPNAME/$JENKINS_APPNAME.log.previous.gz' ] && rm -f '/var/log/$JENKINS_APPNAME/$JENKINS_APPNAME.log.previous.gz'

	gzip '/var/log/$JENKINS_APPNAME/$JENKINS_APPNAME.log.previous'
fi
EOF

# Add our master/slave specific start command 
if [ -z "$JENKINS_MASTER_URL" ]; then
	# We are a master
	cat >>"$DEPLOYMENT_DIR/bin/$JENKINS_APPNAME-startup.sh" <<EOF
# Jenkins master
java -Djava.awt.headless=true -jar '$DEPLOYMENT_DIR/jenkins-$JENKINS_RELEASE_TYPE.war' --httpListenAddress=127.0.0.1 >'/var/log/$JENKINS_APPNAME/$JENKINS_APPNAME.log' 2>&1
EOF
else
	# We are a slave
	cat >>"$DEPLOYMENT_DIR/bin/$JENKINS_APPNAME-startup.sh" <<EOF
# Update the Jenkins agent.jar
curl -Lo "$JENKINS_AGENT_JAR" "$JENKINS_MASTER_URL/jnlpJars/agent.jar"

# Jenkins slave
java -Djava.awt.headless=true -jar '$JENKINS_AGENT_JAR' -workDir '$DEPLOYMENT_DIR/slave' -jnlpUrl '$JENKINS_MASTER_URL/computer/$JENKINS_SLAVE_NAME/slave-agent.jnlp' -secret '$JENKINS_SLAVE_SECRET' >'/var/log/$JENKINS_APPNAME/$JENKINS_APPNAME.log' 2>&1
EOF
fi

INFO "Creating $JENKINS_APPNAME systemd service"
cat >"$DEPLOYMENT_DIR/config/$JENKINS_APPNAME.service" <<EOF
[Unit]
Description=$JENKINS_APPNAME - Jenkins CI

[Service]
Type=simple
GuessMainPID=yes
ExecStart=$DEPLOYMENT_DIR/bin/$JENKINS_APPNAME-startup.sh
User=$JENKINS_USER

[Install]
WantedBy=multi-user.target
EOF

INFO 'Generating logrotate config'
cat >"$DEPLOYMENT_DIR/config/$JENKINS_APPNAME.rotate" <<EOF
# Logrotate for $JENKINS_APPNAME

'/var/log/$JENKINS_APPNAME/$JENKINS_APPNAME.log' {
        missingok
        compress
        copytruncate
        $LOG_ROTATE_FREQUENCY
        $LOG_ROTATE_COUNT
        $LOG_ROTATE_SIZE
}
EOF

# Check if there is an existing service
if [ -f "/usr/lib/systemd/system/$JENKINS_APPNAME.service" ]; then
	# ... and stop it
	INFO "Ensuring any existing $JENKINS_APPNAME.service is not running"
	systemctl -q is-active "$JENKINS_APPNAME.service" && systemctl -q stop "$JENKINS_APPNAME.service"

	# If we have an existing service we need to reload systemd so that it picks up the updated service file
	RELOAD_SYSTEMD=1
fi

INFO 'Generating SSH keys'
ssh-keygen -qt rsa -f "$DEPLOYMENT_DIR/.ssh/id_rsa" -N '' -C "$JENKINS_APPNAME"

INFO 'Installing service'
cp --no-preserve=mode -f "$DEPLOYMENT_DIR/config/$JENKINS_APPNAME.service" "/usr/lib/systemd/system/$JENKINS_APPNAME.service"

if [ -n "$RELOAD_SYSTEMD" ]; then
	INFO "Reloading systemd due to pre-existing $JENKINS_APPNAME.service"
	systemctl -q daemon-reload
fi

INFO 'Installing config'
cp --no-preserve=mode -f "$DEPLOYMENT_DIR/config/$JENKINS_APPNAME.config" "/etc/sysconfig/$JENKINS_APPNAME"

INFO 'Install logrotate config'
cp --no-preserve=mode -f "$DEPLOYMENT_DIR/config/$JENKINS_APPNAME.rotate" /etc/logrotate.d

# Add a note that these configs are not the ones being used by the system
cat >"$DEPLOYMENT_DIR/config/README.1st" <<EOF

Please note

The files in this folder are not the ones that the system uses.  They are located under '/etc/sysconfig/$JENKINS_APPNAME'
and '/etc/logrotate.d/$JENKINS_APPNAME.rotate'

EOF

INFO 'Ensuring we have the correct ownership'
# We don't want to give the Jenkins user permission to write to anything other than the bits it has to be able to write to
chown -R "$ROOT_USER:$ROOT_GROUP" "$DEPLOYMENT_DIR"
chown -R "$JENKINS_USER:$JENKINS_GROUP" "/var/log/$JENKINS_APPNAME"
chown -R "$JENKINS_USER:$JENKINS_GROUP" "$DEPLOYMENT_DIR/.ssh"

if [ -n "$SELINUX_ENABLED" ]; then
	INFO 'Fixing SELinux permissions'
	chcon --reference=/etc/sysconfig/network "/etc/sysconfig/$JENKINS_APPNAME"
	chcon --reference=/usr/lib/systemd/system/system.slice "/usr/lib/systemd/system/$JENKINS_APPNAME.service"

	INFO 'Enabling SELinux reverse proxy permissions'
	setsebool -P httpd_can_network_connect 1
fi


# Give the Jenkins user permission to write to its own directories
INFO 'Fixing directory ownership'
if [ -n "$JENKINS_MASTER_URL" ]; then
	chown -R "$JENKINS_USER:$JENKINS_GROUP" "$DEPLOYMENT_DIR/slave"
else
 	chown -R "$JENKINS_USER:$JENKINS_GROUP" "$DEPLOYMENT_DIR/jenkins_home" "$DEPLOYMENT_DIR/jenkins_scripts"
fi

# SSH will complain/fail without the correct permissions
INFO 'Ensuring installation has the correct permissions'
chmod 0700 "$DEPLOYMENT_DIR/.ssh"
chmod 0600 "$DEPLOYMENT_DIR/.ssh/id_rsa"

if [ -n "$JENKINS_MASTER_URL" ]; then
	INFO 'Enabling and starting Jenkins slave'
else
	INFO 'Enabling and starting - Jenkins will install required plugins and restart a few times, so this may take a while'
fi

# Enable and start our Jenkins master/slave service
chmod 0755 "$DEPLOYMENT_DIR/bin/$JENKINS_APPNAME-startup.sh"
systemctl enable "$JENKINS_APPNAME.service"
systemctl start "$JENKINS_APPNAME.service"

INFO 'Jenkins should be available shortly'
INFO
INFO 'Please wait whilst things startup...'
INFO
INFO 'Whilst things are starting up you can add Jenkins public key to the Git repo(s)'
INFO
INFO 'SSH public key:'
cat "$DEPLOYMENT_DIR/.ssh/id_rsa.pub"
INFO

if [ -z "$JENKINS_MASTER_URL" -a -n "$FIX_FIREWALL" -a -n "$CONFIGURE_SLAVE_CONNECTIVITY" ]; then
	# If we are running a Jenkins master node we have to jump through a few more hoops to enable JNLP
	INFO 'Determing JNLP port - this will take a few moments before Jenkins is able to provide this information'

	for _a in `seq 1 $JENKINS_JNLP_CHECK_ATTEMPTS`; do
		echo -n .

		# During initial we perform some basic log rotation, so we need to make sure the Jenkins log exists before we start inspecting it
		if [ ! -f "/var/log/$JENKINS_APPNAME/$JENKINS_APPNAME.log" ]; then
			sleep $JENKINS_JNLP_CHECK_DELAY

			continue
		fi		

		# Our Jenkins setup automatically goes through and installs a number of plugins, once the plugins have been re-installed we restart a few times, so
		# we need to check for the final restart before we start checking if Jenkins is up and running
		if [ -z "$JENKINS_STARTED" ] && tail -f "/var/log/$JENKINS_APPNAME/$JENKINS_APPNAME.log" | awk '{
	if($0 ~ /Performing final restart/){
		print "started";
		s=1
	}else if((s == 1) && ($0 ~ /INFO: Jenkins is fully up and running/)){
		print "running";
		exit 0
	}

	printf(".")
}'; then

			INFO 'Jenkins has partially started now waiting for Jenkins to fully start ... '
			JENKINS_STARTED=1
		fi

		# Now Jenkins has started, we check for a header containing the JNLP port
		JENKINS_JNLP_PORT="`curl --max-time 2 -si "http://127.0.0.1:8080/tcpSlaveAgentListener/" | awk '/^X-Jenkins-JNLP-Port:/{print $NF}'`"

		# Once we have the port we can then configure the firewall
		[ -n "$JENKINS_JNLP_PORT" ] && break

		sleep $JENKINS_JNLP_CHECK_DELAY
	done

	echo fully started
	[ -z "$JENKINS_JNLP_PORT" ] && FATAL 'Unable to determine Jenkins JNLP port, this can be completed later if required'

	INFO 'Jenkins has now fully started'

	# firewall-cmd isn't the most user friendly of tools
	if firewall-cmd --info-service=jenkins-jnlp >/dev/null 2>&1; then
		INFO 'Removing existing, local, firewall definition for Jenkins slave access'
		firewall-cmd -q --permanent --delete-service=jenkins-jnlp

		# If we don't reload the firewall when we come to add the service again it complains it already exists
		firewall-cmd -q --reload
	fi

	INFO 'Adding, local, firewall definition for Jenkins slave access'
	# Add an exception to allow access via the JNLP port
	firewall-cmd -q --permanent --new-service=jenkins-jnlp
	firewall-cmd -q --permanent --service=jenkins-jnlp --add-port="$JENKINS_JNLP_PORT/tcp"
	firewall-cmd -q --permanent --service=jenkins-jnlp --set-short='Jenkins Slave Connectivity'
	firewall-cmd -q --permanent --add-service=jenkins-jnlp

	INFO 'Reloading firewall'
	firewall-cmd -q --reload

	INFO 'Jenkins will be available on the following URL(s):'
	INFO
	ip addr list | awk '/inet / && !/127.0.0.1/{gsub("/24",""); printf("http://%s\n",$2)}'
	INFO
fi
