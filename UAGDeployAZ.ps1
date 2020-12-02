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
Function Write_Error_Message {
    
    Param ($message)
	Write-Host $message -foregroundcolor Red -backgroundcolor Black
}

# This function provides the Information strings.  Things like where you are in the process.
Function Write-Info-Message {

    Param ($message)
	Write-Host $message -foregroundcolor Yellow -backgroundcolor Black
}

# This code just checks to make sure that all of the Azure Powershell Modules are on the system.
Function Validate_AzureModules {

    If (-not (Get-InstalledModule -Name "Az")) {
        Write_Error_Message "Module Az Not Installed!"
        Write_Error_Message "Run (Install-Module -Name Az -AllowClobber -Scope AllUsers) as Administrator"
        Write_Error_Message "Then Run (Uninstall-AzureRM) as Administrator, might not do anything but cleans up old method"
    }
}

# Get the settings to run this script from a file called UAGSettings.json
Function Get_Settings {

    #Check if the UAGSettings.json exists
    $scriptFolder = $PSScriptRoot
    $jsonPath = $scriptFolder + "\UAGSettings.json"
    If (-not (Test-Path -Path $jsonPath)) {
        Write_Error_Message "Didn't find UAGSettings.json in path ($jsonPath)"
        Exit
    } Else {
        return $jsonPath
    }
}

# This function makes a connection to your Azure instance using the subscription ID.
Function Connect_To_Azure {

    $jsonPath = Get_Settings
    $settingsContent = Get-Content -Path $jsonPath | Out-String 
    $settings = ConvertFrom-Json -InputObject $settingsContent

    $connected = Get-AzSubscription -SubscriptionId $settings.subscriptionID -WarningVariable $errorConnecting -WarningAction Continue
    If ($errorConnecting) {
        Connect-AzAccount -Subscription $settings.subscriptionID
    }
    $tenantID = (Get-AzContext).Tenant.Id
    Write-Info-Message "Connected to Azure Tenant $tenantID"
}

# Create Azure Security Group for the Virtual Network
Function Create_Network_Security_Group {

    $jsonPath = Get_Settings
    $settingsContent = Get-Content -Path $jsonPath | Out-String 
    $settings = ConvertFrom-Json -InputObject $settingsContent
    $securityGroupName = $settings.securityGroupName
 
    $httpsRule = New-AzNetworkSecurityRuleConfig -Name https-rule -Description "Allow HTTPS" -Access Allow -Protocol Tcp -Direction Inbound `
                  -Priority 100 -SourceAddressPrefix Internet -SourcePortRange * -DestinationAddressPrefix * -DestinationPortRange 443

    $udpRule = New-AzNetworkSecurityRuleConfig -Name udp-rule -Description "Allow UDP 443" -Access Allow -Protocol Udp -Direction Inbound `
                  -Priority 101 -SourceAddressPrefix Internet -SourcePortRange * -DestinationAddressPrefix * -DestinationPortRange 443
 

    $httpRule = New-AzNetworkSecurityRuleConfig -Name http-rule -Description "Allow HTTP" -Access Allow -Protocol Tcp -Direction Inbound `
                  -Priority 102 -SourceAddressPrefix Internet -SourcePortRange * -DestinationAddressPrefix * -DestinationPortRange 80

    $blastHttpRule = New-AzNetworkSecurityRuleConfig -Name http-blast-rule -Description "Allow Blast" -Access Allow -Protocol Tcp -Direction Inbound `
                  -Priority 103 -SourceAddressPrefix Internet -SourcePortRange * -DestinationAddressPrefix * -DestinationPortRange 8443

    $blastUDPRule = New-AzNetworkSecurityRuleConfig -Name udp-blast-rule -Description "Allow Blast" -Access Allow -Protocol Udp -Direction Inbound `
                  -Priority 104 -SourceAddressPrefix Internet -SourcePortRange * -DestinationAddressPrefix * -DestinationPortRange 8443

    $nsg = New-AzNetworkSecurityGroup -ResourceGroupName $settings.resourceGroupName -Location $settings.location -Name $securityGroupName `
                -SecurityRules $httpsRule, $httpRule, $udpRule, $blastHttpRule, $blastUDPRule
}

# Create the Virtual Network.  Need to better understand the implications of the AddressPrefix setting.
Function Create_Virtual_Network {
    
    $jsonPath = Get_Settings
    $settingsContent = Get-Content -Path $jsonPath | Out-String 
    $settings = ConvertFrom-Json -InputObject $settingsContent

    $resourceGroupName = $settings.resourceGroupName
    $location = $settings.location
    $virtualNetworkName = $settings.virtualNetworkName
    $vmName = $settings.uagName
    $publicIPName = $settings.publicIPName
    $subnetName = $settings.subnetName
    $dnsPrefix = $settings.publicDNSPrefix

    $networkSubnet = New-AzVirtualNetworkSubnetConfig -Name $subnetName -AddressPrefix 10.0.2.0/24
    $virtualNetwork = New-AzVirtualNetwork -ResourceGroupName $resourceGroupName -Location $location -Name $virtualNetworkName `
                        -AddressPrefix 10.0.2.0/24 -Subnet $networkSubnet


    $publicIPAddress = New-AzPublicIpAddress -Name $publicIPName -ResourceGroupName $resourceGroupName -Location $location `
                        -AllocationMethod Static -DomainNameLabel $dnsPrefix
}

# Create the NIC for the VM
Function Create-NIC {

    $jsonPath = Get_Settings
    $settingsContent = Get-Content -Path $jsonPath | Out-String 
    $settings = ConvertFrom-Json -InputObject $settingsContent

    $resourceGroupName = $settings.resourceGroupName
    $location = $settings.location
    $virtualNetworkName = $settings.virtualNetworkName
    $subnetName = $settings.subnetName
    $securityGroupName = $settings.securityGroupName

    $virtualNetwork = Get-AzVirtualNetwork -Name $virtualNetworkName
    $securityGroup = Get-AzNetworkSecurityGroup -Name $securityGroupName
    $uagSubnet = Get-AzVirtualNetworkSubnetConfig -Name $subnetName -VirtualNetwork $virtualNetwork

    $nicCard = New-AzNetworkInterface -Name "eth0" -ResourceGroupName $resourceGroupName -Location $location -SubnetId $uagSubnet.Id `
                -NetworkSecurityGroupId $securityGroup.Id
}

Function Get-Disk-Uri {

    $jsonPath = Get_Settings
    $settingsContent = Get-Content -Path $jsonPath | Out-String 
    $settings = ConvertFrom-Json -InputObject $settingsContent

    $vhdFileName = $settings.uagVHDFileName
    $resourceGroupName = $settings.resourceGroupName
    $storageAccount = Get-AzStorageAccount -ResourceGroupName $resourceGroupName
    $storageBlobEndpoint = $storageAccount.PrimaryEndpoints.Blob.ToString()

    $storageContainer = Get-AzStorageContainer -Name "uagcontainer" -Context $storageAccount.Context
    $storageBlob = Get-AzStorageBlob -Container $storageContainer.Name -Context $storageAccount.Context -Blob $vhdFileName
    $blobUri = $storageBlob.BlobClient.Uri

    return $blobUri
}

Function Create-Virtual-Machine {

    $jsonPath = Get_Settings
    $settingsContent = Get-Content -Path $jsonPath | Out-String 
    $settings = ConvertFrom-Json -InputObject $settingsContent

    $resourceGroupName = $settings.resourceGroupName
    $location = $settings.location
    $virtualNetworkName = $settings.virtualNetworkName
    $securityGroupName = $settings.securityGroupName
    $vmName = $settings.uagName
    $vmSize = $settings.vmSize
    $adminUserName = $settings.adminUserName
    $adminPassword = $settings.adminPassword
    $publicIPName = $settings.publicIPName

    $securePassword = ConvertTo-SecureString -String $adminPassword -AsPlainText -Force
    $credentials = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $adminUserName, $securePassword
    $virtualNetwork = Get-AzVirtualNetwork -Name $virtualNetworkName
    $securityGroup = Get-AzNetworkSecurityGroup -Name $securityGroupName
    $publicIPAddress = Get-AzPublicIpAddress -Name publicIPName
    $nicCard = Get-AzNetworkInterface -Name "eth0"

    $diskGUID = New-Guid
    $diskURI = Get-Disk-Uri
    $diskName = "OSDisk-" + $diskGUID
    $virtualMachineConfig = New-AzVMConfig -VMName $vmName -VMSize $vmSize
    $virtualMachineConfig = Set-AzVMOSDisk -VM $virtualMachineConfig -Name $diskName -VhdUri $diskURI -SourceImageUri $diskURI `
                                -Linux -DiskSizeInGB 40 -CreateOption FromImage

    $virualMachine = New-AzVM -ResourceGroupName $resourceGroupName -Location $location -VirtualNetworkName $virtualNetwork.Name `
                        -SecurityGroupName $securityGroup.Name -Name $vmName -Credential $credentials -PublicIpAddressName $publicIPAddress `
                        
}

# Main() - This is where the code actually starts.  It calls all of the functions above, with the exception of
# Write_Error_Message which gets called from the individual functions.
Write-Info-Message "Validating Installed Modules"
Validate_AzureModules

# All settings are in a JSON file.  This call retrieves them.
Write-Info-Message "Getting Settings"
Get_Settings

Write-Info-Message "Connecting to Azure"
Connect_To_Azure

Write-Info-Message "Creating Security Group"
Create_Network_Security_Group

Write-Info-Message "Creating Virtual Network"
Create_Virtual_Network

Write-Info-Message "Creating NIC(s)"
Create-NIC

Write-Info-Message "Getting VHD URI"
Get-Disk-Uri

Write-Info-Message "Create Virtual Machine"
Create-Virtual-Machine
