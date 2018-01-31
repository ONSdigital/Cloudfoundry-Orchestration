# Jenkins Deployment Scripts

A collection of scripts that call the actual deployment scripts.  These have been written to extract as much of the scripting out of Jenkins as possible.

Currently, only the deploy\_jenkins-\*.sh scripts have been tested.  The other scripts may cause all sorts of damage...

## Two scripts that allow deployment of Jenkins

- `deploy_jenkins-local.sh`: deploys a local master or slave instance of Jenkins to the local machine
- `deploy_jenkins-cf.sh`: deploys a master Jenkins instance to Cloudfoundry

## Common files

- `common.sh`: common variables functions shared across all of the scripts
- `common-jenkins-deploy.sh`: common variables and functions that are used by the deploy\_jenkins-\*.sh scripts
- `cloudfoundry-preamble.sh`: Cloudfoundry specific preamble to check various variables

## AWS specific scripts

- `delete\_aws\_infrastructure.sh`: delete AWS infrastructure
- `deploy\_aws\_infrastructure.sh`: deploy AWS infrastructure

## Cloudfoundry specific scripts

- `backup\_cloudfoundry.sh`: backup Cloudfoundry
- `delete\_cloudfoundry.sh`: delete Cloudfoundry
- `deploy\_cloudfoundry.sh`: deploy Cloudfoundry onto existing infrastructure

## More Jenkins specific scripts

- `clean\_local\_environment.sh`: clean directories under the user's home directory
- `jenkins\_backup.sh`: backup a Jenkins instances into Git
- `restore\_cloudfoundry.sh`: restore Cloudfoundry from an S3 backup

## Misc scripts

- `template.sh`: template for future scripts
