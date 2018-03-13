#!/bin/sh
#
# Backs up a Jenkins configuration to Git
#
#
# Variables:
#	GIT_COMMIT_MESSAGE=Git commit message
#	GIT_ADD_FILES=[Comma seperated list of files to add]
#	GIT_DELETE_FILES=[Comma seperated list of files to delete]
#	GIT_IGNORES=[Comma seperated list of files to ignore]
#	JENKINS_BACKUP_USERNAME=[Jenkins backup username]
#	JENKINS_BACKUP_PASSWORD=[Jenkins backup password]
#	JENKINS_CLI_JAR=[Jenkins CLI Jar location]
#	JENKINS_LOCATION=[hostname:port of Jenkins]
#	PORT=[Jenkins port number]
#	WEBAPP_HOME=[Jenkins webapp home]
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

git_add(){
	git_add_rm add "$@"
}

git_rm(){
	git_add_rm rm "$@"
}


git_add_rm(){
	local action="$1"
	shift
	local files="$@"

	[ x"$action" = x"rm" ] && action="rm -r"

	awk -v commit_msg="$GIT_COMMIT_MESSAGE" -v action="$action" <<EOF '{
		split($0,files,/ ?, ?/)
		for(file in files){
			system("git " action " \"" files[file] "\"")
			system("git commit -m \"" commit_msg "\"")
		}
	}'
$files
EOF
}


git_changes(){
	git status --porcelain | awk '!/^A /{
		print $0
		gsub(/^..? /,"")
	
		files[$0]++
	}END{
		for(file in files){
			printf("New/modified/deleted file/directory: %s\n",file)
	
			i++
		}
	
		exit i ? 1 : 0
	}' || return 1
}

JENKINS_BACKUP_USERNAME="${JENKINS_BACKUP_USERNAME:-backup_user}"
JENKINS_BACKUP_PASSWORD="${JENKINS_BACKUP_PASSWORD:-password}"

if [ -n "$WEBAPP_HOME" ]; then
	# We are running under CF
	JENKINS_CLI_JAR="${JENKINS_CLI_JAR:-$WEBAPP_HOME/WEB-INF/jenkins-cli.jar}"

	# Connecting to 0.0.0.0 should connect us to the Jenkins running locally
	# As we are running under CF, we may not be running on 127.0.0.1
	JENKINS_LOCATION="0.0.0.0:${PORT:-8080}"

elif [ -n "$JENKINS_CLI_JAR" -a -n "$JENKINS_LOCATION" ]; then
	# We are running on a version of CF deployed to a normal machine
	:
else
	# Best guess:
	JENKINS_CLI_JAR="${JENKINS_CLI_JAR:-/usr/share/tomcat/webapps/jenkins/WEB-INF/jenkins-cli.jar}"
	JENKINS_LOCATION="${JENKINS_LOCATION:-localhost:8080/jenkins/}"
fi

[ -f "$JENKINS_CLI_JAR" ] || FATAL "Unable to find $JENKINS_CLI_JAR"
[ -z "$JENKINS_HOME" ] && FATAL '$JENKINS_HOME has not been set'
[ -d "$JENKINS_HOME" ] || FATAL "$JENKINS_HOME does not exist"

# Check we have Java available
if which java >/dev/null 2>&1; then
	JAVA_BIN='java'
elif [ -n "$JAVA_HOME" -a "$JAVA_HOME/bin/java" ]; then
	JAVA_BIN="$JAVA_HOME/bin/java"
else
	FATAL 'Unable to determine Java location'
fi

JENKINS_URL="http://$JENKINS_BACKUP_USERNAME:$JENKINS_BACKUP_PASSWORD@$JENKINS_LOCATION"

cd "$JENKINS_HOME"

[ -d .git -a -f .git/config ] || FATAL 'Are we in a Git repository'

INFO 'Generating, potentially, updated plugin list'
"$JAVA_BIN" -jar "$JENKINS_CLI_JAR" -noKeyAuth -s "$JENKINS_URL" list-plugins | awk '{print $1}' | sort >plugin-list.new

# Check if we have generated a plugin list
diff -q /dev/null plugin-list.new 2>&1 >/dev/null && FATAL "A blank plugin-list has been generated, does the $JENKINS_BACKUP_USERNAME have the correct permissions?"

if [ ! -f plugin-list ]; then
	INFO 'Creating plugin-list'
	mv plugin-list.new plugin-list

elif ! diff -q plugin-list plugin-list.new; then
	INFO 'Plugins have changed'
	diff -u plugin-list plugin-list.new || :

	INFO 'Updating plugin-list'
	mv -f plugin-list.new plugin-list
else
	INFO 'plugin-list has not been updated'
	rm -f plugin-list.new
fi

if [ ! -f .gitignore ]; then
	INFO 'Populating initial .gitignore'

	# This should already exist
	cat >.gitignore <<EOF
.owner
*.bak
*.log
cache/
fingerprints/
jobs/*/builds
jobs/*/promotions/*/last*
jobs/*/promotions/*/next*
jobs/*/promotions/*/builds
logs/
plugins/
tools/
updates/
userContent/readme.txt
workspace/
jobs/*/last*
jobs/*/next*
war/

# We may or may not add this to disable Content Security Policy: https://wiki.jenkins-ci.org/display/JENKINS/Configuring+Content+Security+Policy
init.groovy.d/disableCSP.groovy

# Some of these may not be sensible
hudson.model.UpdateCenter.xml
nodeMonitors.xml
identity.key.enc
plugin-list.new
secrets/*
secret.key
secret.key*
EOF

	git add .gitignore
	git commit -m 'Initial .gitignore' .gitignore

	CHANGES=1
fi

# Check if we need to update our ignores
if [ -n "$GIT_IGNORES" ]; then
	INFO "Adding '$GIT_IGNORES to .gitignore"

	awk '{split($0,ignores,/ ?, ?/); for(ignore in ignores) print ignores[ignore] }' >>.gitignore <<EOF
$GIT_IGNORES
EOF
	git add .gitignore
	git commit -m 'Updated .gitignore' .gitignore

	CHANGES=1
fi

if git_changes && [ -z "$GIT_COMMIT_MESSAGE" ]; then
	FATAL 'Unwilling to commit changes without a Git commit message'
fi

if [ -n "$GIT_ADD_FILES" ]; then
	INFO "Adding '$GIT_ADD_FILES'"
	git_add "$GIT_ADD_FILES"

	CHANGES=1
fi

if [ -n "$GIT_DELETE_FILES" ]; then
	INFO "Deleting '$GIT_DELETE_FILES'"
	git_rm "$GIT_DELETE_FILES"

	CHANGES=1
fi

if ! git_changes; then
	INFO 'Uncommitted changes exist'

	FAIL=1
fi

git push "$DEFAULT_ORIGIN" "$DEFAULT_BRANCH" || FATAL 'Unable to push changes to Git'

if git_changes; then
	INFO 'All changes have been committed'

	FAIL=0
fi

exit "${FAIL:-0}"

