<#
    This is a set of functions -- Search for Main() to see where the code actually starts.
#>

<#
    .SYNOPSIS
     Sample Powershell script to deploy a VMware UAG virtual appliance to Microsoft Azure.
    .EXAMPLE
     .\uagdeployeaz.ps1 UAGSettings.json 
#>

# If there is an error, this is the function that formats the string with the appropriate coloring.
Function Write-Error-Message {
    
    Param ($message)
	Write-Host $message -foregroundcolor Red -backgroundcolor Black
}

# This function provides the Information strings.  Things like where you are in the process.
Function Write-Warning-Message {

    Param ($message)
	Write-Host $message -foregroundcolor Yellow -backgroundcolor Black
}

Function Write-Info-Message {
    
    Param($message)
    Write-Host $message -ForegroundColor Green -BackgroundColor Black
}

# This code just checks to make sure that all of the Azure Powershell Modules are on the system.
Function Validate-AzureModules {

    If (-not (Get-InstalledModule -Name "Az")) {
        Write_Error_Message "Module Az Not Installed!"
        Write_Error_Message "Run (Install-Module -Name Az -AllowClobber -Scope AllUsers) as Administrator"
        Write_Error_Message "Then Run (Uninstall-AzureRM) as Administrator, might not do anything but cleans up old method"
    }
}

Function Get-Settings {

    #Check if the UAGSettings.json exists
    $scriptFolder = $PSScriptRoot
    $jsonPath = $scriptFolder + "\VMSettings.json"
    If (-not (Test-Path -Path $jsonPath)) {
        Write_Error_Message "Didn't find UAGSettings.json in path ($jsonPath)"
        Exit
    } Else {
        return $jsonPath
    }
}

# This function makes a connection to your Azure instance using the subscription ID.
Function Connect-To-Azure {

    $jsonPath = Get-Settings
    $settingsContent = Get-Content -Path $jsonPath | Out-String 
    $settings = ConvertFrom-Json -InputObject $settingsContent

    $connected = Get-AzSubscription -SubscriptionId $settings.subscriptionID -WarningVariable $errorConnecting -WarningAction Continue
    If ($null -eq $connected) {
        Connect-AzAccount -Subscription $settings.subscriptionID
    }
    $tenantID = (Get-AzContext).Tenant.Id
    Write-Info-Message "Connected to Azure Tenant $tenantID"
}
Function Create-Resource-Group {
    
    $jsonPath = Get-Settings
    $settingsContent = Get-Content -Path $jsonPath | Out-String 
    $settings = ConvertFrom-Json -InputObject $settingsContent

    $resourceGroupName = $settings.resourceGroupName
    $location = $settings.location
    $resourceGroup = Get-AzResourceGroup -Name $resourceGroupName -Location $location
    If ($null -eq $resourceGroup) {
        $resourceGroup = New-AzResourceGroup -Location $location -Name $resourceGroupName
    } else {
        Write-Info-Message "Resource Group $resourceGroupName Exists!"
    }

}


Function Create-Network-Security-Group {

    $jsonPath = Get-Settings
    $settingsContent = Get-Content -Path $jsonPath | Out-String 
    $settings = ConvertFrom-Json -InputObject $settingsContent
    $securityGroupName = $settings.securityGroupName
 
    $securityGroupExists = Get-AzNetworkSecurityGroup -Name $securityGroupName -ErrorVariable $noSecurityGroup -ErrorAction Continue
    If ($null -eq $securityGroupExists) {
        $rdpRule = New-AzNetworkSecurityRuleConfig -Name rdp-rule -Description "Allow RDS" -Access Allow -Protocol Tcp -Direction Inbound `
                      -Priority 100 -SourceAddressPrefix "68.43.210.2" -SourcePortRange * -DestinationAddressPrefix * -DestinationPortRange 3389

        $nsg = New-AzNetworkSecurityGroup -ResourceGroupName $settings.resourceGroupName -Location $settings.location -Name $securityGroupName `
                    -SecurityRules $rdpRule
    } Else {
        Write-Info-Message "Security Group {$securityGroupName} Exists"
    }
}

# Main() - This is where the code actually starts.  It calls all of the functions above, with the exception of
Write-Warning-Message "Validating Installed Modules"
Validate-AzureModules

# All settings are in a JSON file.  This call retrieves them.
Write-Warning-Message "Getting Settings"
Get-Settings

Write-Warning-Message "Connecting to Azure"
Connect-To-Azure

Write-Warning-Message "Creating Resource Group"
Create-Resource-Group

Write-Warning-Message "Creating Security Group"
Create-Network-Security-Group