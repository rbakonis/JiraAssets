# Jira Assets
PowerShell Module for Interacting with the Jira Assets API

# Installation
1. Download the JiraAssets.zip file
2. Extract the Zip file into one of the following folders:
  - **System-Wide**: `$env:ProgramFiles\WindowsPowerShell\Modules`
  - **User-Specific**: `$HOME\Documents\WindowsPowerShell\Modules`
3. Import the module:
  - `Import-Module JiraAssets

# Configuration
The module requires a configuration file to be stored in a `.jira_assets` file in the current user's home directory. If this file is not present, the module will guide you through creating the configuration file upon import as shown below.

![screenshot of first-time module import](/images/first_time_config.png)

A sample config file is provided below. Replace the `jira_auth_string` and `jira_workspace_id` parameters with values from your tenant. 

```json
{
    "log_file": "c:\\path\\to\\jira_assets.log",
    "auth_string": "jira_auth_string",
    "log_level": 0,
    "workspace_id": "jira_workspace_id"
}
```

# Using the Module
Refer to the examples below when using the module.

## Available Cmdlets
### Get-JiraObjectSchema
Returns a schema definition
```PowerShell
$schema = Get-JiraObjectSchema -object_type_id 10

> $schema.name
Key
Name
Created
Updated
PO Number
Primary User
Department
Building
...
```

### Get-JiraObjectsByType
Returns a list of objects for a given `object_type` or `object_type_id`
```PowerShell
$objects = Get-JiraObjectsByType -object_type "Servers"

> $objects[0] | select id, label, created

id    label  created
--    -----  -------
14994 19hcrb 2023-12-06T00:36:40.498Z

```

### Get-JiraObject
Returns a single Jira Object matching a given `object_id`

```PowerShell
$object = Get-JiraObject -object_id 14491

> $object | select label, created

label           created
-----           -------
10.0.22621.1485 2023-11-08T21:48:59.655Z
```

### Get-JiraObjectAQL
Returns a list of objects matching an AQL query.

```PowerShell
$email = "someone@somedomain.com"

> $object = Get-JiraObjectAQL -query "objectTypeId = 2 AND Email = $email"

$object | select id

id
--
6852
```

### Remove-JiraObject
Removes an object from Jira Assets. Returns `True` if successful, `False` otherwise. 

```PowerShell
Remove-JiraObject -object_id 14491
```

### New-JiraObject
Creates an object in Jira with a PSCustomObject. For reference attributes, provide the value that matches the label of the reference object. The module will attempt to resolve the reference object to it's Jira key. The `create_references` parameter can be used to create stub reference objects if they don't yet exist in Assets. These stub references can be populated later using the `Set-JiraObject` cmdlet. 

```PowerShell
$object = [PSCustomObject]@{
    "Label" = "ZYX"
    "Display Name" = "DPTEST"
    "Description" = "Test workloads"
    "Operating System" = "RHEL 9"
    "Manufacturer" = "Dell"
    "Warranty Expiration Date" = "3/29/2027"
}

$object = New-JiraObject -object_type_id 21 -object $object

$object | select id, label

id       label
--       -----
14491    ZYX
```

### Set-JiraObject
Updates an object in Jira Assets using

```PowerShell
$jira_object = Get-JiraObject -object_id 14491

$updated_object = [PSCustomObject]@{
    "Label" = "XYZ"
    "Display Name" = "DPPROD"
    "Description" = "Prod workloads"
    "Operating System" = "RHEL 9"
    "Manufacturer" = "Dell"
    "Warranty Expiration Date" = "3/29/2027"
}

$object = Set-JiraObject -reference_object $jira_object -updated_object $updated_object


$object | select id, label

id       label
--       -----
14491    XYZ
```

## Supporting Cmdlets

### Write-Log
Outputs message to the log file in the configuration

### New-JiraConfig
Replaces or creates a new Jira Config file in the user's home directory. 