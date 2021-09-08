<#
    This is a set of functions -- Search for Main() to see where the code actually starts.
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
Function Find-AzureModules {

    If (-not (Get-InstalledModule -Name "Az")) {
        Write_Error_Message "Module Az Not Installed!"
        Write_Error_Message "Run (Install-Module -Name Az -AllowClobber -Scope AllUsers) as Administrator"
        Write_Error_Message "Then Run (Uninstall-AzureRM) as Administrator, might not do anything but cleans up old method"
    }
}

# Get the settings to run this script from a file called UAGSettings.json
Function Get-Settings {

    #Check if the UAGSettings.json exists
    $scriptFolder = $PSScriptRoot
    $jsonPath = $scriptFolder + "\AppGatewayDeploy.json"
    If (-not (Test-Path -Path $jsonPath)) {
        Write_Error_Message "Didn't find UAGSettings.json in path ($jsonPath)"
        Exit
    } Else {
        return $jsonPath
    }
}

# This function makes a connection to your Azure instance using the subscription ID.
Function Connect-To-Azure {

    $settings = Get-Settings

    $connected = Get-AzSubscription -SubscriptionId $settings.subscriptionID -WarningVariable $errorConnecting -WarningAction Continue
    If ($null -eq $connected) {
        Connect-AzAccount -Subscription $settings.subscriptionID
    }
    $tenantID = (Get-AzContext).Tenant.Id
    Write-Info-Message "Connected to Azure Tenant $tenantID"
}

# Creates the Resource Group with the name specified in the .json file.
Function New-Resource-Group {
    
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

Function Add-Gateway-VNET {

    Set-Item Env:\SuppressAzurePowerShellBreakingChangeWarnings "true"
    $jsonPath = Get-Settings
    $settingsContent = Get-Content -Path $jsonPath | Out-String 
    $settings = ConvertFrom-Json -InputObject $settingsContent

    Write-Info-Message ("Front End Name: " + $settings.appgatewaySubnetName)
    $accessGatewaySubnetList = New-Object Collections.Generic.List[string]
    $accessGatewaySubnetList.Add(10.1.0.0/24)
    foreach($currentSubnet in $accessGatewaySubnetList) {
        Write-Output $currentSubnet
    }
    Get-Member -InputObject $accessGatewaySubnetList
    $accessGatewaySubnet = New-AzVirtualNetworkSubnetConfig -Name $settings.appgatewaySubnetName -AddressPrefix $accessGatewaySubnetList
    # $backendSubnet = New-AzVirtualNetworkSubnetConfig -Name $settings.backendSubnetName -AddressPrefix "10.1.1.0/24"
    New-AzVirtualNetwork -ResourceGroupName $settings.resourceGroupName -Location $settings.location `
        -Name $settings.virtualNetworkName -Subnet $accessGatewaySubnet #, $backendSubnet
    New-AzPublicIpAddress -ResourceGroupName $settings.resourceGroupName -Location $settings.location -Name $settings.publicIPAddressName `
        -AllocationMethod Static -Sku Standard
}


Function Get-VNetInfo {

    $jsonPath = Get-Settings
    $settingsContent = Get-Content -Path $jsonPath | Out-String 
    $settings = ConvertFrom-Json -InputObject $settingsContent

    $vnet = Get-AzVirtualNetwork -ResourceGroupName $settings.resourceGroupName -Name $settings.virtualNetworkName
    foreach ($currentSubnet in $vnet.Subnets) {
        Get-Member -InputObject $currentSubnet
        Write-Output $currentSubnet.Name
        Write-Output $currentSubnet.AddressPrefix
    }
}

# Main() - This is where the code actually starts.  It calls all of the functions above, with the exception of
Write-Warning-Message "Validating Installed Modules"
Find-AzureModules

# All settings are in a JSON file.  This call retrieves them.
Write-Warning-Message "Getting Settings"
Get-Settings

Write-Warning-Message "Connecting to Azure"
Connect-To-Azure

Write-Warning-Message "Creating Resource Group"
New-Resource-Group

Write-Warning-Message "Creating VNET"
Add-Gateway-VNET

# Get-VNetInfo