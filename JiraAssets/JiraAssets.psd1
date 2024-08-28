#
# Module manifest for module 'JiraAssets'
#
# Generated by: Ryan Bakonis
#
# Generated on: 3/1/2024
#
# Assets API Documentation: https://developer.atlassian.com/cloud/assets/rest/api-group-aql/#api-group-aql

@{
    ModuleVersion = '0.0.1'
    RootModule = 'JiraAssets.psm1'
    GUID = '8cd1c219-024c-4a90-b63d-0327ccd620ca'
    Author = 'Ryan Bakonis'
    Copyright = '(c) Ryan Bakonis. All rights reserved.'
    Description = 'Fetch, create, update, and delete objects in Jira Assets'

    FunctionsToExport = @(
        "Get-JiraObject", 
        "Get-JiraObjectAQL",
        "Get-JiraObjectByNameType",
        "Get-JiraObjectsByType", 
        "Get-JiraObjectSchema", 
        "New-JiraConfig"
        "New-JiraObject", 
        "Set-JiraObject", 
        "Remove-JiraObject",
        "Write-Log"
    )


    CmdletsToExport = @()
    VariablesToExport = '*'
    AliasesToExport = @()
    PrivateData = @{
        PSData = @{
        } 
    } 
}

