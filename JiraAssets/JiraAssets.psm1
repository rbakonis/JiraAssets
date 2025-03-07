

if (-not (Get-Module -Name "SATLogger")) {
    function New-LogMessage (){  
        <#
        .SYNOPSIS
            Writes a formatted log message to a file with optional terminal output

        .DESCRIPTION
            New-LogMessage is a function that outputs log messages with timestamps and sev-
            erity to a file and, optionally, to the terminal. Log messages can be filtered 
            based on a global $log_level variable with a value set to 0 (DEBUG), 1 (INFO), 
            2 (WARN), 3 (ERROR), or 4 (CRITICAL). Setting $log_level = 0 will result in the
            most verbose logs, while $log_level = 4 will only output critical exceptions.

        .PARAMETER message
            The message you would like to output to the log file. Type: String

        .PARAMETER severity
            The severity of the logged action. Type: Integer [0-4]. 0 = DEBUG,
            1 = INFO, 2 = WARN, 3 = ERROR, 4 = CRITICAL

        .EXAMPLE
            Write-Log -message "Reboot required" -severity 2

        .INPUTS
            String, Integer

        .OUTPUTS
            Null

        #>
        [CmdletBinding()]
        param (
            [Parameter(Mandatory=$true)]
            [string]$message,

            [ValidateNotNullOrEmpty()]
            [int]$severity = 1
        )
        $type = $null
        switch ($severity){
            0 { $type = "[DEBUG]" }
            1 { $type = "[INFO]" }
            2 { $type = "[WARN]"  }
            3 { $type = "[ERROR]" }
            default {$type = "[INFO]" }
        }
        $date = get-date -Format "yyyy-MM-dd hh:mm:ss"
        $log_message = $date + "`t" + $type + "`t" + $message
        if($severity -ge $jira_config.log_level){
            Write-Host $log_message
            $log_message | Out-File $jira_config.log_file -Append
        }
    }
}

function Get-JiraObjectsByType(){
    <#
    .SYNOPSIS
        Fetches objects from Jira Assets by type name or type ID

    .DESCRIPTION
        Fetches objects from Jira Assets by type name or type ID. Recursive
        API requests are made until the entire set of objects has been 
        retrieved. This can consume large amounts of memory for very large
        object sets, especially if the type has an attribute list with
        multiple reference objects. Only one input parameter is accepted.
        Returns an array of custom objects or $false if not found.

    .PARAMETER object_type
        The name of the object type in Assets (e.g. "Computers"). Type: String

    .PARAMETER object_type_id
        The ID of the object type in Assets. Type: Integer

    .EXAMPLE
        Get-JiraObjectsByType -object_type_id 29

    .EXAMPLE
        Get-JiraObjectsByType -object_type "Computers"

    .INPUTS
        String, Integer

    .OUTPUTS
        [PSCustomObject], $false
    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory=$true,
        ParameterSetName="object_type")]
        [String]$object_type,
    
        [parameter(Mandatory=$true,
        ParameterSetName="object_type_id")]
        [int]$object_type_id
    )

    $url = "https://api.atlassian.com/jsm/assets/workspace/$($workspace_id)/v1/object/aql"

    $headers = @{
        "Accept" = "application/json";
        "Content-Type" = "application/json";
        "Authorization"= "Basic $token"
    }
    if($object_type){
        $search_string = @{
                "qlQuery" = "objectType = `"$object_type`""
        } | ConvertTo-Json -Compress
    }
    elseif($object_type_id){
        $search_string = @{
            "qlQuery" = "objectTypeId = $object_type_id"
        } | ConvertTo-Json -Compress
    }
    
    # Fetch total count:
    $object_count = (Get-JiraAQLResultCount -aql_query $search_string)
    if($object_count -gt 0){
        New-LogMessage -Severity 0 -Message "Total results from query: $($object_count)"
    }
    else{
        New-LogMessage -Severity 1 -Message "Total results from query: 0. Review query if this is unexpected"
        return
    }

    $all_objs = @()
    $start_val = 0
    try{
        $response = Invoke-RestMethod -Uri $url -Headers $headers -Method Post -Body $search_string
        if ($response.total -gt 0){       
            while($all_objs.count -lt $object_count){
                $all_objs += $response.values
                $start_val += 25
                $url_with_params = $url + "?startAt=$start_val"
                $response = Invoke-RestMethod -Uri $url_with_params -Headers $headers -Method Post -Body $search_string
            }
        }
        else{
            New-LogMessage -Message "No results returned from GET request" -severity 2
            New-LogMessage -Message "Request URL: $url" -severity 2
            New-LogMessage -Message "Request Body: $search_string" -severity 2
        }
        New-LogMessage -Message "Fetched $($all_objs.count) objects from asset. Total objects: $($response.total)" -severity 0
        New-LogMessage -Message "Request URL: $url" -severity 0
        New-LogMessage -Message "Request Body: $search_string" -severity 0  
        return $all_objs
    }
    catch{
        New-LogMessage -Message "Failed to query Asset API. Exception: $($_.ErrorDetails.Message)" -severity 3
        New-LogMessage -Message "Request URL: $url" -severity 2
        New-LogMessage -Message "Request Body: $search_string" -severity 2
    }
}

function Get-JiraAQLResultCount(){
    <#
    .SYNOPSIS
        Fetches the total number of results for an AQL query

    .DESCRIPTION
        Fetches the total number of results for an AQL query

    .PARAMETER aql_query
        The ID of the object type in Assets. Type: Integer

    .EXAMPLE
        Get-JiraAQLResultCount -query

    .INPUTS
        string

    .OUTPUTS
        PSCustomObject, $false
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [string]$aql_query
    )
    $url = "https://api.atlassian.com/jsm/assets/workspace/$($workspace_id)/v1/object/aql/totalcount"
    $headers = @{
        "Accept" = "application/json";
        "Content-Type" = "application/json";
        "Authorization"= "Basic $token"
    }

    try{
        if($result = Invoke-RestMethod -Uri $url -headers $headers -Method Post -Body $aql_query){
            New-LogMessage -Message "Fetched total count for query: $($aql_query). Count: $($result.totalCount)" -severity 0
            New-LogMessage -Message "GET URL: $url" -severity 0
            return $result.TotalCount
        }
        else{
            New-LogMessage -Message "Failed to fetch total count for query: $($aql_query)" -severity 0
            New-LogMessage -Message "Failed GET URL: $url" -severity 0
            return $false
        }
    }
    catch{
        New-LogMessage -Message "Failed to fetch total count for query: $($aql_query). Exception: $($_.ErrorDetails.Message)" -severity 2
        New-LogMessage -Message "Failed GET URL: $url" -severity 0
        return $false
    }
}

function Get-JiraObjectSchema(){
    <#
    .SYNOPSIS
        Fetches the schema for a given object type.

    .DESCRIPTION
        Fetches the schema for a given object type. Returns a custom object or
        $false if not found.

    .PARAMETER object_type_id
        The ID of the object type in Assets. Type: Integer

    .EXAMPLE
        Get-JiraObjectsSchema -object_type_id 29

    .INPUTS
        Integer

    .OUTPUTS
        PSCustomObject, $false
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [int]$object_type_id
    )
    $url = "https://api.atlassian.com/jsm/assets/workspace/$($workspace_id)/v1/objecttype/$($object_type_id)/attributes?excludeParentAttributes=true&includeValueExist=true"
    $headers = @{
        "Accept" = "application/json";
        "Content-Type" = "application/json";
        "Authorization"= "Basic $token"
    }
    try{
        if($result = Invoke-RestMethod -Uri $url -headers $headers -Method Get){
            New-LogMessage -Message "Fetched schema for object type: $($object_type_id)" -severity 0
            New-LogMessage -Message "GET URL: $url" -severity 0
            return $result
        }
        else{
            New-LogMessage -Message "Failed to fetch schema for object type: $($object_type_id)" -severity 0
            New-LogMessage -Message "Failed GET URL: $url" -severity 0
            return $false
        }
    }
    catch{
        New-LogMessage -Message "Failed to fetch object schema for object type: $($object_type_id). Exception: $($_.ErrorDetails.Message)" -severity 2
        New-LogMessage -Message "Failed GET URL: $url" -severity 0
        return $false
    }
}

function Get-JiraObject(){
    <#
    .SYNOPSIS
        Fetches an object from Jira Assets by ID.

    .DESCRIPTION
        Fetches an object from Jira Assets by ID. Returns a custom object or 
        $false if not found.

    .PARAMETER $object_id
        The ID of the object in Jira Assets. Type: Integer

    .EXAMPLE
        Get-JiraObject -object_id 14491

    .INPUTS
        Integer

    .OUTPUTS
        PSCustomObject, $false
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [int]$object_id
    )
    $url = "https://api.atlassian.com/jsm/assets/workspace/$($workspace_id)/v1/object/$($object_id)"

    $headers = @{
        "Accept" = "application/json";
        "Content-Type" = "application/json";
        "Authorization"= "Basic $token"
    }

    try{
        $response = Invoke-RestMethod -Uri $url -Headers $headers -Method Get
        if($response.objectKey){
            New-LogMessage -Message "Fetched $($response.objectkey)" -severity 0
            New-LogMessage -Message "GET URL: $url" -severity 0
            return $response
        }
        else{
            New-LogMessage -Message "Failed to fetch object with ID $($object_id). Response: $($response)" -severity 2
            New-LogMessage -Message "Failed GET URL: $url" -severity 2
            return $false
        }
    }
    catch{
        New-LogMessage -Message "Failed to fetch object with ID $($object_id). Exception: $($_.ErrorDetails.Message)" -severity 2
        New-LogMessage -Message "Failed GET URL: $url" -severity 2
        return $false
    }

}

function Get-JiraObjectAQL(){
    <#
    .SYNOPSIS
        Fetches objects matching an AQL query. 

    .DESCRIPTION
        Fetches objects matching an AQL query. See the page below for more information on AQL Syntax:
        https://support.atlassian.com/jira-service-management-cloud/docs/use-assets-query-language-aql/
        Returns an array of custom objects or $false if not found.

    .PARAMETER $query
        The AQL query to return one or more objects.

    .EXAMPLE
        Get-JiraObjectAQL -query "objectTypeId = 2 AND Email = $email"

    .INPUTS
        String

    .OUTPUTS
        [PSCustomObject], $false
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [String]$query
    )
    $url = "https://api.atlassian.com/jsm/assets/workspace/$($workspace_id)/v1/object/aql"

    $headers = @{
        "Accept" = "application/json";
        "Content-Type" = "application/json";
        "Authorization"= "Basic $token"
    }

    $body = @{
        "qlQuery" = $query
    } | convertto-json -compress

    $object_count = (Get-JiraAQLResultCount -aql_query $body)

    $all_objs = @()
    $start_val = 0
    try{
        $response = Invoke-RestMethod -Uri $url -Headers $headers -Method Post -Body $body
        if ($response.total -gt 0){       
            while($all_objs.count -lt $object_count){
                $all_objs += $response.values
                $start_val += 25
                $url_with_params = $url + "?startAt=$start_val"
                $response = Invoke-RestMethod -Uri $url_with_params -Headers $headers -Method Post -Body $body
            }
        }
        else{
            New-LogMessage -Message "No results returned from GET request" -severity 2
            New-LogMessage -Message "Request URL: $url" -severity 2
            New-LogMessage -Message "Request Body: $search_string" -severity 2
        }
        New-LogMessage -Message "Fetched $($all_objs.count) objects from asset. Total objects: $($response.total)" -severity 0
        New-LogMessage -Message "Request URL: $url" -severity 0
        New-LogMessage -Message "Request Body: $search_string" -severity 0  
        return $all_objs
    }
    catch{
        New-LogMessage -Message "Failed to query Asset API. Exception: $($_.ErrorDetails.Message)" -severity 3
        New-LogMessage -Message "Request URL: $url" -severity 2
        New-LogMessage -Message "Request Body: $search_string" -severity 2
    }
}

function Get-JiraObjectByNameType(){
    <#
    .SYNOPSIS
        Fetches an object by name (label) and type

    .DESCRIPTION
        Fetches an object by name (label) and type. Returns a single custom
        object or $false if not found. If more than one result is returned,
        the query is considered ambiguous and $false is also returned. This
        is intended to identify an object for which a name and type is known,
        but which may not yet exist in Jira Assets. The value to be passed
        in the "object_label" parameter should be the attribute that carries
        the "label" assignment in Jira Assets. This is usually "Name," but
        in some cases it differs (e.g. IP Addresses and Tablets use alternate
        attributes for the label assignment).

    .PARAMETER $object_label
        The name (Label) of a device

    .PARAMETER $object_type_id
        The associated object type ID for the device in Jira Assets

    .EXAMPLE
        Get-JiraObjectByNameType -object_label "COMPUTER-001" -object_type_id 24

    .INPUTS
        String

    .OUTPUTS
        PSCustomObject, $false
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [String]$object_label,
        [Parameter(Mandatory=$true)]
        [int]$object_type_id
    )
    $url = "https://api.atlassian.com/jsm/assets/workspace/$($workspace_id)/v1/object/aql"

    $headers = @{
        "Accept" = "application/json";
        "Content-Type" = "application/json";
        "Authorization"= "Basic $token"
    }

    $body = @{
        "qlQuery" = "objectTypeId = $($object_type_id) AND label = `"$($object_label)`""
    } | convertto-json -compress


    try{
        $response = Invoke-RestMethod -Uri $url -Headers $headers -Method Post -Body $body
        if($response.total -eq 1){
            New-LogMessage -Message "Fetched $($object_label) of type $($object_type_id)" -severity 0
            New-LogMessage -Message "POST URL: $url" -severity 0
            New-LogMessage -Message "POST Body: $body" -severity 0
            return $response.values[0]
        }
        elseif($response.total -gt 1){
            New-LogMessage -Message "Ambiguous query. More than one result returned. Total results: $($response.total)" - severity 2
            New-LogMessage -Message "POST URL: $url" -severity 0
            New-LogMessage -Message "POST Body: $body" -severity 0
            return $false
        }
        else{
            New-LogMessage -Message "No results for $($object_label) of type: $($object_type_id). Response: $($response)" -severity 2
            New-LogMessage -Message "POST URL: $url" -severity 2
            New-LogMessage -Message "POST Body: $body" -severity 2
            return $false
        }
    }
    catch{
        New-LogMessage -Message "Failed to fetch object $($object_label) of type: $($object_type_id). Exception: $($_.ErrorDetails.Message.Message)" -severity 2
        New-LogMessage -Message "Failed POST URL: $url" -severity 2
        New-LogMessage -Message "Failed POST Body: $body" -severity 2
        return $false
    }
}

function Remove-JiraObject(){
    <#
    .SYNOPSIS
        Removes an object from Jira Assets by ID.

    .DESCRIPTION
        Removes an object from Jira Assets by ID. Returns $true if
        the object is deleted, $false if deletion fails.

    .PARAMETER $object_id
        The ID of the object in Jira Assets. Type: Integer

    .EXAMPLE
        Remove-JiraObject -object_id 14491

    .INPUTS
        Integer

    .OUTPUTS
        Boolean
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [int]$object_id
    )
    $url = "https://api.atlassian.com/jsm/assets/workspace/$($workspace_id)/v1/object/$($object_id)"

    $headers = @{
        "Accept" = "application/json";
        "Content-Type" = "application/json";
        "Authorization"= "Basic $token"
    }

    try{
        if(Invoke-RestMethod -Uri $url -Headers $headers -Method Delete){
            New-LogMessage -Message "Deleted $($object_id)" -severity 0
            New-LogMessage -Message "DELETE URL: $url" -severity 0
            return $true
        }
        else{
            New-LogMessage -Message "Failed to fetch object with ID $($object_id). Response: $($response)" -severity 2
            New-LogMessage -Message "Failed DELETE URL: $url" -severity 2
            return $false
        }
    }
    catch{
        New-LogMessage -Message "Failed to fetch object with ID $($object_id). Exception: $($_.ErrorDetails.Message)" -severity 2
        New-LogMessage -Message "Failed DELETE URL: $url" -severity 2
        return $false
    }

}

function New-JiraObject(){
    <#
    .SYNOPSIS
        Creates a new object in Jira Assets.

    .DESCRIPTION
        Creates a new object in Jira Assets. The property names must match
        the property names in Assets. If the $create_references parameter is
        set to $true, reference property values which do not exist in 
        Assets will be created. For example, if a Computer object has a 
        reference property for Manufacturer with a value of "Dell," but 
        Assets does not contain "Dell" in the referenced object type, a
        new manufacturer object will be created prior to creating the 
        new computer object. Returns a custom object from Assets or 
        $false if creation fails. Use "Label" as the property name for
        the attribute with the label assigment.

    .PARAMETER $object_type_id
        The ID of the object type

    .PARAMETER $object
        A PSCustomObject with property names that match the schema in Assets.
        Use "Label" as the propert name for the attribute with the label assign-
        ment. 

    .PARAMETER $create_references
        Boolean value to determine if nested reference objects should be created.
        Default value is $false.

    .EXAMPLE
        New-JiraObject -object_type_id 21 -object $object -create_references:$true

    .INPUTS
        String, PSCustomObject, Boolean

    .OUTPUTS
        PSCustomObject, $false
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [int]$object_type_id,

        [Parameter(Mandatory=$true)]
        [PSCustomObject]$object,

        [ValidateNotNullOrEmpty()]
        [bool]$create_references = $false
    )
    # Create POST request for new asset
    $url = "https://api.atlassian.com/jsm/assets/workspace/$($workspace_id)/v1/object/create"

    $headers = @{
        "Accept" = "application/json";
        "Content-Type" = "application/json";
        "Authorization"= "Basic $token"
    }

    # Initialize the Jira request body
    $request_body = @{
        "objectTypeId" = $object_type_id;
        "attributes" = @()
    }

    # Get the schema for the current object type
    if($schema = Get-JiraObjectSchema -object_type_id $object_type_id){
        New-LogMessage -Message "Obtained schema for object type id: $($object_type_id)." -severity 0
    } 
    else{
        New-LogMessage -Message "Failed to obtain schema for object type id: $($object_type_id). Verify that the type id is correct." -severity 2
        return $false
    }


    # Iterate through the object properties to set their values according to the schema
    foreach($property in $object.psobject.properties){

        if($property.value){
            # Initialize list of attribute values to pass into Jira
            $values = @()

            # Some schemas don't use "Name" (e.g. IP Addresses use "Address"), so ensure that the "Name" value on the 
            # reference object maps to the label in Asset
            if($property.name -eq "Label"){
                $schema_property = $schema | where-object {$_.label -eq $true}
                New-LogMessage -Message "Schema property: $($schema_property.name). Value: $($property.value)." -severity 0
            }
            elseif($schema_property = $schema | where-object {$_.name -eq $property.name}){
                New-LogMessage -Message "Schema property: $($schema_property.name). Value: $($property.value)." -severity 0
            }
            else{
                # No matching attribute in schema. This may be expected - especially when calling the function within the 
                # function. Skip
                New-LogMessage -Message "Attribute '$($property.name)' not found in schema for object type $($object_type_id). Check that the name of the object property matches the name in the object schema in Asset." -severity 2
            }
            if($schema_property){
                if($schema_property.referenceObjectTypeId){
                    # Reference object type. Need to confirm a reference object exists
                    New-LogMessage -Message "$($property.name) is a reference object with type id: $($schema_property.referenceObjectTypeId)" -severity 0
                    
                    
                    # If the reference object exists, attach the id to the attribute, otherwise, create a new object of the reference type
                    foreach($value in $property.value){

                        # Select the reference object with matching value
                        New-LogMessage -Message "Fetching property value for $($value | Out-String)" -severity 0
                        if($ref_object = Get-JiraObjectByNameType -object_label $property.value -object_type_id $schema_property.referenceObjectTypeId){
                            # Attach this reference object to the new request
                            $values += @{"value" = $ref_object.id}
                        }
                        else{
                            # We can create a stub type, but we don't necessarily know what the additional attributes are
                            New-LogMessage -Message "No matching reference object found for $($property.value)" -severity 2

                            if($create_references){

                                New-LogMessage -Message "Reference object creation set to 'true', creating reference object for $($property.value)" -severity 1
                                $reference_schema = Get-JiraObjectSchema -object_type_id $schema_property.referenceObjectTypeId

                                $new_reference_object = [PSCustomObject]@{
                                    "Label" = $property.value
                                }

                                # Here's where this gets wonky. We'll append each of the other attributes included in the 
                                # initial object (except for those in the no_carry_over list), and call the function again. 
                                # This could loop a couple of layers - e.g. Server --> DNS --> IP object. 
                                $no_carry_over = @("Label", "Description", "Notes")
                                foreach($attribute in $object.psobject.properties | where-object {$no_carry_over -notcontains $_.name}){
                                    if($reference_schema.name -contains $attribute.name){
                                        $new_reference_object | add-member -notepropertyname $attribute.name -notepropertyvalue $attribute.value
                                    }
                                }
                                # Assuming $true for reference creation. Might need to add an additional create_nested_references switch.
                                if($ref_object = New-JiraObject -object_type_id $schema_property.referenceObjectTypeId -object $new_reference_object -create_references $true){
                                    $values += @{"value" = $ref_object.id}
                                }
                                else{
                                    New-LogMessage -Message "Failed to create $($property.name) object for $($property.value)" -severity 2
                                }
                            }
                            else{
                                New-LogMessage -Message "Reference object creation disabled. Excluding $($property.name) from the object. Create the reference object first" -severity 1
                            }
                        }
                    }
                }
                else{
                    foreach($value in $property.value){
                        $values += @{"value" = $value}
                    }
                }
                # Complete the request object
                $request_body.attributes += @{
                    "objectTypeAttributeId" = $schema_property.id
                    "objectAttributeValues" = $values
                }
            }
        }
    }

    New-LogMessage -Message "Submitting request for new object creation: $($object.label)" -severity 0
    $body = $request_body | ConvertTo-Json -Depth 10 -Compress

    try{
        $response = Invoke-RestMethod -Uri $url -Headers $headers -Method Post -Body $body
        if($response.objectKey){
            New-LogMessage -Message "Created object" -severity 1
            New-LogMessage -Message "POST URL: $url" -severity 1
            New-LogMessage -Message "POST Body: $body" -severity 1
            return $response
        }
        else{
            New-LogMessage -Message "Failed to create object. Response: $($response)" -severity 2
            New-LogMessage -Message "Failed POST URL: $url" -severity 2
            New-LogMessage -Message "Failed POST Body: $body" -severity 2
            return $false
        }
    }
    catch{
        New-LogMessage -Message "Failed to create object. Exception: $($_.ErrorDetails.Message)" -severity 2
        New-LogMessage -Message "Failed POST URL: $url" -severity 2
        New-LogMessage -Message "Failed POST Body: $body" -severity 2
        return $false
    }
}

function Get-AttributeUpdate(){
    <#
    .SYNOPSIS
        Internal function for comparing attribute values stored in a Jira Object's
        property with updated values.

    .DESCRIPTION
        Internal function for comparing attribute values stored in a Jira Object's
        property with updated values. Returns a hash table if an update to the att-
        tribute is required. 

    .PARAMETER $reference_object
        The Jira Assets object to be updated

    .PARAMETER $attribute_value
        The current value retrieved from an attribute source (e.g. InTune, JAMF, VMware)

    .PARAMETER $attribute_id
        The attribute type ID from the Object type. All devices of a given type
        will share this value (e.g. the "Model" property for the "Computer object
        has a type id of ##").

    .PARAMETER $is_reference
        Boolean value to determine if the attribute is a reference type. 

    .EXAMPLE
        Get-AttributeUpdate -reference_object $jira_object -attribute_value $computer.ip_address -attribute_id 237 -is_reference:$true

    .INPUTS
        Int, PSCustomObject, Boolean, Misc.

    .OUTPUTS
        HashTable, $false
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [PSCustomObject]$reference_object,

        [Parameter(Mandatory=$false)]
        [Object]$attribute_value,

        [Parameter(Mandatory=$true)]
        [int]$attribute_id,

        [Parameter(Mandatory=$true)]
        [bool]$is_reference
    )    
    $update = $false
    if($asset_attribute = $reference_object.attributes | Where-Object {$_.objectTypeAttributeId -eq $attribute_id}){
        if($is_reference){
            # Check if any new or extra attribute values are present in the reference object or in Asset
            if(($asset_attribute.objectAttributeValues.referencedobject.id | Where-Object {$attribute_value -notcontains $_}) -or `
                ($attribute_value | Where-Object {$asset_attribute.objectAttributevalues.referencedobject.id -notcontains $_})){
                $update = $true
                New-LogMessage -Message "Updating $($reference_object.label). Attribute ID: $($attribute_id), Attribute value: $($attribute_value -join ","), Old value: $($asset_attribute.objectAttributeValues.referencedobject.id -join ",")" -severity 0
            }
        } elseif($asset_attribute.objectAttributeValues.value -ne $attribute_value){
            New-LogMessage -Message "Updating $($reference_object.label). Attribute ID: $($attribute_id), Attribute value: $($attribute_value), Old value $($asset_attribute.objectAttributeValues.value)" -severity 0
            $update = $true
        }
    } 
    else{
        New-LogMessage -Message "Updating $($reference_object.label). Attribute ID: $($attribute_id), Attribute value: $($attribute_value -join ",")"
        $update = $true
    }

    if($update){
        $updated_values = @()
        foreach($attribute in $attribute_value){
            $updated_values += @{"value" = $attribute}
        }
        return @{
            "objectTypeAttributeId" = $attribute_id
            "objectAttributeValues" = $updated_values
        }
    } 
    else{
        return $false
    }
}

function Set-JiraObject(){
    <#
    .SYNOPSIS
        Udpates an existing object in Jira Assets.

    .DESCRIPTION
        Updates an existing object in Jira Assets. The property names must match
        the property names in Assets. If the $create_references parameter is set 
        to $true, reference property values which do not exist in Assets will be 
        created. For example, if a Computer object has a reference property for 
        Manufacturer with a value of "Dell," but  Assets does not contain "Dell" 
        in the referenced object type, a new manufacturer object will be created 
        prior to creating the new computer object. Returns a custom object from 
        Assets if updates are needed, $true if no updates are needed,  or $false 
        if the update fails. Use "Label" as the property name for the attribute 
        with the label assigment.

    .PARAMETER $reference_object
        The existing Jira Assets object to be checked and updated (if needed)

    .PARAMETER $updated_object
        A PSCustomObject with property names that match the schema in Assets.
        Use "Label" as the property name for the attribute with the label assign-
        ment. 

    .PARAMETER $create_references
        Boolean value to determine if nested reference objects should be created.
        Default value is $false.

    .EXAMPLE
        Set-JiraObject -reference_object $jira_object -updated_object $updated_object -create_references:$true

    .INPUTS
        PSCustomObject, Boolean

    .OUTPUTS
        PSCustomObject, $false, $true
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [PSCustomObject]$reference_object,

        [Parameter(Mandatory=$true)]
        [PSCustomObject]$updated_object,

        [ValidateNotNullOrEmpty()]
        [bool]$create_references = $false
    )
    # We have an existing object, and we need to check if the properties have changed
    $update_attributes = @()

    # Get the schema for the current object type
    if($schema = Get-JiraObjectSchema -object_type_id $reference_object.objectType.id){
        New-LogMessage -Message "Obtained schema for object type id: $($reference_object.objectType.id)." -severity 0
    } else{
        New-LogMessage -Message "Failed to obtain schema for object type id: $($reference_object.objectType.id). Verify that the type id is correct." -severity 2
        return $false
    }

    foreach($property in $updated_object.psobject.properties){

        $reference_property = $null

        if($property.name -eq "Label"){
            $reference_property = $schema | where-object {$_.label -eq $true}
            New-LogMessage -Message "Reference property: $($reference_property.name). Property value: $($property.value)" -severity 0
        }elseif($reference_property = $schema | where-object {$_.name -eq $property.name}){
            New-LogMessage -Message "Reference property: $($reference_property.name). Property value: $($property.value)" -severity 0
        }

        if($reference_property){
            if($reference_property.referenceObjectTypeId){
                # This is a reference attributes. We have work to do
                $is_reference = $true
                New-LogMessage -Message "$($property.name) is a reference object with type id: $($reference_property.referenceObjectTypeId)." -severity 0
                
                # For reference attributes, we need to replace names in the value list with IDs
                $reference_attributes = @()
                foreach($value in $property.value){
                    # Fetch the reference attribute's object
                    New-LogMessage -Message "Fetching property value for $($value | Out-String)" -severity 0
                    if($reference_attribute = Get-JiraObjectByNameType -object_label $property.value -object_type_id $reference_property.referenceObjectTypeId){
                        # It exists in Assets. Append to the pointer_objects list
                        $reference_attributes += $reference_attribute.id
                    }
                    else{
                        # If it doesn't exist in Assets, the reference object needs to be created
                        New-LogMessage -Message "No matching reference object found for $($property.value)." -severity 2
                        
                        if($create_references){
                            New-LogMessage -Message "Reference object creation set to 'true', creating reference object for $($property.value)" -severity 1
                            $reference_schema = Get-JiraObjectSchema -object_type_id $reference_property.referenceObjectTypeId

                            $new_reference_object = [PSCustomObject]@{
                                "Label" = $property.value
                            }

                            # Append attributes that match the reference schema from the source object before creating the new object
                            $no_carry_over = @("Label", "Description", "Notes")
                            foreach($attribute in $updated_object.psobject.properties | where-object {$no_carry_over -notcontains $_.name}){
                                if($reference_schema.name -contains $attribute.name){
                                    $new_reference_object | add-member -notepropertyname $attribute.name -notepropertyvalue $attribute.value
                                }
                            }

                            if($new_reference_attribute = New-JiraObject -object_type_id $reference_property.referenceObjectTypeId -object $new_reference_object -create_references $true){
                                $reference_attributes += $new_reference_attribute.id
                            }
                            else{
                                New-LogMessage -Message "Failed to create $($property.name) object for $($property.value)" -severity 2
                            }
                        }
                        else{
                            New-LogMessage -Message "Reference object creation disabled. Excluding $($property.name) from the object. Create the reference object first" -severity 1
                        }
                    }
                }
                # Replace named values with reference attributes
                $property.value = $reference_attributes
            }
            else{
                $is_reference = $false
            }
            # Reference attribute should be the entire object, not just the attribute
            if($update_attribute = Get-AttributeUpdate -reference_object $reference_object -attribute_value $property.value -attribute_id $reference_property.id  -is_reference $is_reference){
                $update_attributes += $update_attribute
            }
        }
        else{
            New-LogMessage -Message "$($property.name) not found in the properties for object type: $($reference_object.objectType.id). Check that the property name matches the object schema." -severity 2
        }
    }
     
    if($update_attributes){

        New-LogMessage -Message "Putting updates to $($reference_object.label) ($($reference_object.objectKey))" -severity 1

        $url = "https://api.atlassian.com/jsm/assets/workspace/$($workspace_id)/v1/object/$($reference_object.id)"

        $headers = @{
            "Accept" = "application/json";
            "Content-Type" = "application/json";
            "Authorization"= "Basic $token"
        }

        $body = @{
            "attributes" = $update_attributes
            "objectTypeId" = $reference_object.objectType.id

        } | ConvertTo-Json -Depth 10 -Compress

        try{
            $response = Invoke-RestMethod -Uri $url -Headers $headers -Method Put -Body $body
            if($response.objectKey){
                New-LogMessage -Message "PUT URL: $url" -severity 0
                New-LogMessage -Message "PUT Body: $body" -severity 0
                return $response
            }
            else{
                New-LogMessage -Message "Failed to update object for $($upd_dns.label). Response: $($response)" -severity 2
                New-LogMessage -Message "Failed PUT URL: $url" -severity 2
                New-LogMessage -Message "Failed PUT Body: $body" -severity 2
                return $false
            }
        }
        catch{
            New-LogMessage -Message "Failed to update object for $($upd_dns.label). Exception: $($_.ErrorDetails.Message)" -severity 2
            New-LogMessage -Message "Failed PUT URL: $url" -severity 2
            New-LogMessage -Message "Failed PUT Body: $body" -severity 2
            return $false
        }
    }
    else{
        New-LogMessage -Message "No updates needed for $($reference_object.label)" -severity 0
        return $true
    }
    
}

function New-JiraConfig(){
    <#
    .SYNOPSIS
        Creates a new Jira Assets Configuration file in the user's home directory.

    .DESCRIPTION
        Creates a new Jira Assets Configuration file in the user's home directory.
        The default path is ~\.jira_assets
        
    .PARAMETER $log_level
        The desired logging level for the module. Accepts integer values of 0-4.
        0 = DEBUG, 1 = INFO, 2 = WARN, 3 = ERROR, 4 = CRITICAL

    .PARAMETER $log_file
        The path to the log file

    .PARAMETER $workspace_id
        Jira Workspace ID

    .PARAMETER $auth_string
        Jira auth string

    .PARAMETER $auth_string
        The path to write your config file. Default is ~\.jira_assets

    .EXAMPLE
        Get-JiraObjectByNameType -object_label "COMPUTER-001" -object_type_id 24

    .INPUTS
        String, Integer

    .OUTPUTS
        File
    #>
    [CmdletBinding()]
    param (
        [Parameter()]
        [int]$log_level = 5,

        [Parameter()]
        [String]$log_file,

        [Parameter()]
        [String]$workspace_id,

        [Parameter()]
        [String]$auth_string
    )

    while($log_level -notmatch "[0-4]"){
        Write-Host "Set Log Levels" -ForegroundColor Green
        Write-Host " - 0: DEBUG and higher"
        Write-Host " - 1: INFO and higher"
        Write-Host " - 2: WARN and higher"
        Write-Host " - 3: ERROR and higher"
        Write-Host " - 4: Critical and higher"
        $log_level = Read-host "Select an option from the list above"
        write-host ""
    }

    while(!($log_file)){
        Write-Host "Set Log File Path" -ForegroundColor Green
        $log_file = Read-Host "Enter the path to your log file"
    }

    while(!($workspace_id)){
        Write-Host "Set Workspace ID" -ForegroundColor Green
        $workspace_id = Read-Host "Enter your Jira workspace ID"
    }

    while(!($auth_string)){
        Write-Host "Set Auth String" -ForegroundColor Green
        $auth_string = Read-Host "Enter your Jira auth string"
    }
    $config = @{
        "log_level" = $log_level
        "log_file" = $log_file
        "workspace_id" = $workspace_id
        "auth_string" = $auth_string
    }

    $config | ConvertTo-Json | Out-File "~/.jira_assets"

    return $config
}
function Get-Config(){
    if(test-path "~/.jira_assets"){
        $jira_config = Get-Content "~/.jira_assets" | ConvertFrom-Json 
    }
    else{
        Write-Host "Config file not found (~/.jira_assets). Creating a new config file" -ForegroundColor Yellow
        $jira_config = New-JiraConfig
    }
    return $jira_config
}


# LOAD CONFIG
$workspace_id = $null
$auth_str = $null


if($jira_config = Get-Secret -Name "jira_api" -ErrorAction SilentlyContinue){
    if($PSVersionTable.PSversion.Major -gt 5){
        $workspace_id = $jira_config.workspace_id | ConvertFrom-SecureString -AsPlainText
        $auth_str = $jira_config.auth_string | ConvertFrom-SecureString -AsPlainText
        $log_file = $jira_config.log_file | ConvertFrom-SecureString -AsPlainText
        $log_level = $jira_config.log_level | ConvertFrom-SecureString -AsPlainText

    }
    elseif($PSVersionTable.PSversion.Major -le 5){
        $BString = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($jira_config.workspace_id)
        $workspace_id = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BString)

        $BString2 = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($jira_config.auth_string)
        $auth_str = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BString2)    

        $BString3 = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($jira_config.log_file)
        $log_file = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BString3) 

        $BString4 = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($jira_config.log_level)
        $log_level = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BString4) 

    }
    $jira_config = @{
        log_file= $log_file
        auth_string=$auth_str
        log_level=[int]$log_level
        workspace_id=$workspace_id
    }
}
elseif($jira_config = Get-Config){
    $workspace_id = $jira_config.workspace_id 
    $auth_str = $jira_config.auth_string
}

if($workspace_id -and $auth_str){
    $Bytes = [System.Text.Encoding]::UTF8.GetBytes($auth_str) 
    $token = [Convert]::ToBase64String($Bytes) 
}
else{
    New-LogMessage -Severity 3 -Message "Failed to load Jira Config. Ensure config file or 'jira_api' secret values include the workspace_id and auth_string values"
}