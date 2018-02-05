# Cloudfoundry Deployment Scripts

A collection of scripts that call the actual deployment scripts.  These have been written to extract as much of the scripting out of Jenkins as possible.

## Common files

- `cloudfoundry-preamble.sh`: Cloudfoundry specific preamble to check various variables

## Cloudfoundry specific scripts

- `backup_cloudfoundry.sh`: backup Cloudfoundry
- `delete_cloudfoundry.sh`: delete Cloudfoundry
- `deploy_cloudfoundry.sh`: deploy Cloudfoundry onto existing infrastructure
- `restore_cloudfoundry.sh`: restore Cloudfoundry from an S3 backup
