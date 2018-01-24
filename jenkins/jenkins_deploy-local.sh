#!/bin/sh
#
set -e

COMMON_SH="`dirname "$0"`/jenkins-common.sh"

if [ ! -f "$COMMON_SH" ]; then
	echo "Unable to find $COMMON_SH"

	exit 1  
fi

. "$COMMON_SH"

ROOT_USER="${ROOT_USER:-root}"
ROOT_GROUP="${ROOT_USER:-wheel}"

JENKINS_USER="${JENKINS_USER:-jenkins}"
JENKINS_GROUP="${JENKINS_GROUP:-jenkins}"

whoami | grep -Eq "^$ROOT_USER$" || FATAL "This script MUST be run as $ROOT_USER"

LOG_ROTATE_COUNT='10'
LOG_ROTATE_SIZE='10m'
LOG_ROTATE_FREQUENCY='daily'
# Fonts & fontconfig are required for AWT
BASE_PACKAGES='git java-1.8.0-openjdk-headless httpd dejavu-sans-fonts fontconfig unzip'
SSH_KEYSCAN_TIMEOUT='10'

CONFIGURE_SLAVE_CONNECTIVITY=1
FIX_FIREWALL=1
FIX_SELINUX=1

# In seconds
JENKINS_START_DELAY='120'
JENKINS_JNLP_CHECK_DELAY='10'
JENKINS_JNLP_CHECK_ATTEMPTS='100'

# Parse options
for i in `seq 1 $#`; do
	[ -z "$1" ] && break

	case "$1" in
		-n|--name)
			JENKINS_APPNAME="$2"
			shift 2
			;;
		--master-url)
			JENKINS_MASTER_URL="$2"
			shift 2
			;;
		--jenkins-slave-name)
			JENKINS_SLAVE_NAME="$2"
			shift 2
			;;
		--jenkins-slave-secret)
			JENKINS_SLAVE_SECRET="$2"
			shift 2
			;;
		--disable-slave-connectivity)
			unset CONFIGURE_SLAVE_CONNECTIVITY
			shift
			;;
		-r|--release-type)
			JENKINS_RELEASE_TYPE="$2"
			shift 2
			;;
		-c|--config-repo)
			JENKINS_CONFIG_NEW_REPO="$2"
			shift 2
			;;
		-C|--config-seed-repo)
			JENKINS_CONFIG_SEED_REPO="$2"
			shift 2
			;;
		-S|--scripts-repo)
			JENKINS_SCRIPTS_REPO="$2"
			shift 2
			;;
		--no-fix-firewall)
			unset FIX_FIREWALL
			shift
			;;
		--no-selinux)
			unset FIX_SELINUX
			shift
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
			PLUGINS="$DEFAULT_PLUGINS,$2"
			shift 2
			;;
		-K|--ssh-keyscan-host)
			[ -n "$SSH_KEYSCAN_HOSTS" ] && SSH_KEYSCAN_HOSTS="$SSH_KEYSCAN_HOSTS $2" || SSH_KEYSCAN_HOSTS="$2"
			shift 2
			;;
		*)
			FATAL "Unknown option $1"
			;;
	esac
done

INSTALL_BASE_DIR="${INSTALL_BASE_DIR:-/opt}"
DEPLOYMENT_DIR="$INSTALL_BASE_DIR/$JENKINS_APPNAME"

if [ -z "$JENKINS_MASTER_URL" ]; then
	if [ -z "$JENKINS_CONFIG_SEED_REPO" ]; then
		FATAL 'No JENKINS_CONFIG_SEED_REPO provided'
	fi

	if [ -z "$JENKINS_SCRIPTS_REPO" ]; then
		FATAL 'No JENKINS_SCRIPTS_REPO provided'
	fi
fi

[ -d "$DEPLOYMENT_DIR" ] && FATAL "Deployment '$DEPLOYMENT_DIR' already exists, please remove"

INFO "Creating $DEPLOYMENT_DIR layout"
mkdir -p "$DEPLOYMENT_DIR"/{bin,config,.ssh}

INFO 'Checking if all required packages are installed - this may take a while'
for _i in $BASE_PACKAGES; do
	if ! rpm --quiet -q "$_i"; then
		INFO ". Installing $_i"
		yum install -q -y "$_i"
	fi
done

if [ -n "$FIX_SELINUX" ]; then
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
	[ -z "$JENKINS_SLAVE_NAME" ] && JENKINS_SLAVE_NAME="$JENKINS_APPNAME-slave"

	JENKINS_APPNAME="$JENKINS_SLAVE_NAME"
	JENKINS_AGENT_JAR="$DEPLOYMENT_DIR/bin/agent.jar"
	
	[ -z "$JENKINS_SLAVE_SECRET" ] && FATAL "No Jenkins secret provided. Cannot connect to Jenkins master. The secret will be available from $JENKINS_MASTER_URL/computer/$JENKINS_SLAVE_NAME/ - assuming the slave name is correct"

	INFO 'Downloading Jenkins agent.jar'
	curl -Lo "$JENKINS_AGENT_JAR" "$JENKINS_MASTER_URL/jnlpJars/agent.jar"

	mkdir "$DEPLOYMENT_DIR/slave"

	INFO 'Determining JNLP port'
	JENKINS_JNLP_PORT="`curl -fi "$JENKINS_MASTER_URL/tcpSlaveAgentListener/" | awk '/^X-Jenkins-JNLP-Port:/{print $NF}'`"

	[ -z "$JENKINS_JNLP_PORT" ] && FATAL 'Unable to determine Jenkins JNLP port'
else
	INFO 'Deploying Jenkins master'
	configure_git_repo jenkins_home "$JENKINS_CONFIG_SEED_REPO" "${JENKINS_CONFIG_NEW_REPO:-NONE}"

	git_push_repo_cleanup jenkins_home

	INFO 'Setting up Jenkins to install required plugins'
	cd "$DEPLOYMENT_DIR/jenkins_home"
	cp _init.groovy init.groovy

	# init.groovy will rename this when its run
	mv config.xml _config.xml

	cd ..

	configure_git_repo jenkins_scripts "$JENKINS_SCRIPTS_REPO"

	cd "$DEPLOYMENT_DIR"

	INFO 'Installing initial plugin(s)'
	[ -d jenkins_home/plugins ] || mkdir -p jenkins_home/plugins

	cd "$DEPLOYMENT_DIR/jenkins_home/plugins"

	download_plugins ${PLUGINS:-$DEFAULT_PLUGINS}

	cd "$DEPLOYMENT_DIR"

	download_jenkins_war "$JENKINS_RELEASE_TYPE"

	cd bin

	INFO 'Extracting Jenkins CLI'
	unzip -qqj "$DEPLOYMENT_DIR/jenkins-$JENKINS_RELEASE_TYPE.war" WEB-INF/jenkins-cli.jar

	cd - 2>&1 >/dev/null

	INFO 'Creating httpd reverse proxy setup'
	cat >/etc/httpd/conf.d/$JENKINS_APPNAME-proxy.conf <<EOF
	ProxyPass         "/" "http://127.0.0.1:8080/"
	ProxyPassReverse  "/" "http://127.0.0.1:8080/"
EOF

	if [ -n "$FIX_FIREWALL" ]; then
		INFO 'Permitting access to HTTP'
		firewall-cmd --add-service=http --permanent

		INFO 'Reloading firewall'
		firewall-cmd --reload
	fi

	scan_ssh_hosts $JENKINS_CONFIG_REPO $JENKINS_CONFIG_SEED_REPO $JENKINS_SCRIPTS_REPO $SSH_KEYSCAN_HOSTS >"$DEPLOYMENT_DIR/.ssh/known_hosts"

	INFO 'Enabling and starting httpd'
	systemctl start httpd
	systemctl enable httpd

fi

INFO 'Creating Jenkins log directory'
mkdir -p "/var/log/$JENKINS_APPNAME"

INFO "Creating $JENKINS_APPNAME configuration"
cat >"$DEPLOYMENT_DIR/config/$JENKINS_APPNAME.config" <<EOF
export JENKINS_HOME="$DEPLOYMENT_DIR/jenkins_home"
export SCRIPTS_DIR="$DEPLOYMENT_DIR/jenkins_scripts"
export JENKINS_CLI_JAR="$DEPLOYMENT_DIR/bin/jenkins-cli.jar"
export JENKINS_LOCATION="localhost:8080"
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

if [ x"$JENKINS_USER" != x"\$USER" ]; then
	FATAL 'This startup script MUST be run as $JENKINS_USER'

	exit 1
fi

[ -f "/etc/sysconfig/$JENKINS_APPNAME" ] && . /etc/sysconfig/$JENKINS_APPNAME

[ -f "/var/log/$JENKINS_APPNAME/$JENKINS_APPNAME.log" ] && gzip -c "/var/log/$JENKINS_APPNAME/$JENKINS_APPNAME.log" >"/var/log/$JENKINS_APPNAME/$JENKINS_APPNAME.log.previous.gz"
EOF

if [ -z "$JENKINS_MASTER_URL" ]; then
	# We are a master
	cat >>"$DEPLOYMENT_DIR/bin/$JENKINS_APPNAME-startup.sh" <<EOF
java -Djava.awt.headless=true -jar "$DEPLOYMENT_DIR/jenkins-$JENKINS_RELEASE_TYPE.war" --httpListenAddress=127.0.0.1 >"/var/log/$JENKINS_APPNAME/$JENKINS_APPNAME.log" 2>&1
EOF
else
	# We are a slave
	cat >>"$DEPLOYMENT_DIR/bin/$JENKINS_APPNAME-startup.sh" <<EOF
java -Djava.awt.headless=true -jar "$JENKINS_AGENT_JAR" -workDir "$DEPLOYMENT_DIR/slave" -jnlpUrl "$JENKINS_MASTER_URL/computer/$JENKINS_SLAVE_NAME/slave-agent.jnlp" -secret "$JENKINS_SLAVE_SECRET" >"/var/log/$JENKINS_APPNAME/$JENKINS_APPNAME.log" 2>&1
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

/var/log/$JENKINS_APPNAME/$JENKINS_APPNAME.log {
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
	systemctl -q status $JENKINS_APPNAME.service && systemctl -q stop $JENKINS_APPNAME.service

	RELOAD_SYSTEMD=1
fi

INFO 'Generating SSH keys'
ssh-keygen -qt rsa -f "$DEPLOYMENT_DIR/.ssh/id_rsa" -N '' -C "$JENKINS_APPNAME"

INFO Installing service
cp --no-preserve=mode -f "$DEPLOYMENT_DIR/config/$JENKINS_APPNAME.service" "/usr/lib/systemd/system/$JENKINS_APPNAME.service"

if [ -n "$RELOAD_SYSTEMD" ]; then
	INFO "Reloading systemd due to pre-existing $JENKINS_APPNAME.service"
	systemctl -q daemon-reload
fi

INFO 'Installing config'
cp --no-preserve=mode -f "$DEPLOYMENT_DIR/config/$JENKINS_APPNAME.config" "/etc/sysconfig/$JENKINS_APPNAME"

INFO 'Install logrotate config'
cp --no-preserve=mode -f "$DEPLOYMENT_DIR/config/$JENKINS_APPNAME.rotate" /etc/logrotate.d

INFO 'Ensuring we have the correct ownership'
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


INFO 'Fixing directory ownership'
if [ -n "$JENKINS_MASTER_URL" ]; then
	chown -R "$JENKINS_USER:$JENKINS_GROUP" "$DEPLOYMENT_DIR/.ssh" "$DEPLOYMENT_DIR/slave"
else
 	chown -R "$JENKINS_USER:$JENKINS_GROUP" "$DEPLOYMENT_DIR/.ssh" "$DEPLOYMENT_DIR/jenkins_home" "$DEPLOYMENT_DIR/jenkins_scripts"
fi

INFO 'Ensuring installation has the correct permissions'
chmod 0700 "$DEPLOYMENT_DIR/.ssh"
chmod 0600 "$DEPLOYMENT_DIR/.ssh/id_rsa"

if [ -n "$JENKINS_MASTER_URL" ]; then
	INFO 'Enabling and starting Jenkins slave'
else
	INFO 'Enabling and starting - Jenkins will install required plugins and restart a few times, so this may take a while'
fi
chmod 0755 "$DEPLOYMENT_DIR/bin/$JENKINS_APPNAME-startup.sh"
systemctl enable $JENKINS_APPNAME.service
systemctl start $JENKINS_APPNAME.service

INFO 'Jenkins should be available shortly'
INFO
INFO 'Please wait whilst things startup...'
INFO
INFO 'Whilst things are starting up you can add Jenkins public key to the Git repo(s)'
INFO
INFO 'SSH public key:'
cat "$DEPLOYMENT_DIR/.ssh/id_rsa.pub"
INFO
INFO 'Jenkins will be available on the following URL(s):'
INFO
ip addr list | awk '/inet / && !/127.0.0.1/{gsub("/24",""); printf("http://%s\n",$2)}'
INFO

if [ -z "$JENKINS_MASTER_URL" -a -n "$FIX_FIREWALL" -a -n "$CONFIGURE_SLAVE_CONNECTIVITY" ]; then
	INFO 'Determing JNLP port - this may take a few moments until Jenkins is able to provide this information'

	INFO 'Jenkins starting ...'
	echo -n
	for _a in `seq 1 $JENKINS_JNLP_CHECK_ATTEMPTS`; do
		echo -n .

		if [ -z "$JENKINS_STARTED" ]; then
			if ! grep -Eq 'INFO: Started ServerConnector.*127.0.0.1:8080' "/var/log/$JENKINS_APPNAME/$JENKINS_APPNAME.log"; then
				sleep $JENKINS_JNLP_CHECK_DELAY

				continue
			fi

			echo
			INFO 'Jenkins has partially started now waiting for Jenkins to fuly start ...'
			echo -n
			JENKINS_STARTED=1
		fi

		# Once Jenkins has booted up fully this seems to give a 404, so we may be using something that may brake in the future
		JENKINS_JNLP_PORT="`curl -sSi "http://127.0.0.1:8080/tcpSlaveAgentListener/" | awk '/^X-Jenkins-JNLP-Port:/{print $NF}'`"

		[ -n "$JENKINS_JNLP_PORT" ] && break

		sleep $JENKINS_JNLP_CHECK_DELAY
	done
	echo

	[ -z "$JENKINS_JNLP_PORT" ] && FATAL 'Unable to determine Jenkins JNLP port, this can be completed later if required'

	INFO 'Configuring slave connectivity'
	if firewall-cmd --info-service=jenkins-jnlp 2>&1 >/dev/null; then
		INFO 'Removing existing JNLP configuration'
		firewall-cmd --remove-service=jenkins-jnlp
	fi

	firewall-cmd --new-service=jenkins-jnlp --permanent
	firewall-cmd --service=jenkins-jnlp --add-port="$JENKINS_JNLP_PORT/tcp" --permanent
	firewall-cmd --service=jenkins-jnlp --set-short='Jenkins Slave Connectivity' --permanent
	firewall-cmd --add-service=jenkins-jnlp --permanent

	INFO 'Reloading firewall'
	firewall-cmd --reload
fi
