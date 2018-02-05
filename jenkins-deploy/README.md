# Jenkins Deployment Scripts

A collection of scripts that call the actual deployment scripts.  These have been written to extract as much of the scripting out of Jenkins as possible.

Currently, only the deploy\_jenkins-\*.sh scripts have been tested.  The other scripts may cause all sorts of damage...

## Two scripts that allow deployment of Jenkins

- `deploy_jenkins-local.sh`: deploys a local master or slave instance of Jenkins to the local machine
- `deploy_jenkins-cf.sh`: deploys a master Jenkins instance to Cloudfoundry

## Common files

- `common-jenkins-deploy.sh`: common variables and functions that are used by the deploy\_jenkins-\*.sh scripts
