# Cloudfoundry CLI Helper Scripts

Collection of scripts to perform various CF CLI commands.  Having helper scripts ensures things default to being done in a consistent way.

## Creation scripts

- `create-orgs-roles.sh`
	- Creates an organisation and assigns OrgManager roles to the listed users

- `create-quota.sh`
	- Creates a quota, by default it creates a 'default' quota

- `create-users.sh`
	- Creates the listed users.
	- This script is to be used if ActiveDirectory is not available and UAA doesn't have its signup feature enabled
