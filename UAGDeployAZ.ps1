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
Function Write-Warning-Message {

    Param ($message)
	Write-Host $message -foregroundcolor Yellow -backgroundcolor Black
}

Function Write-Info-Message {
    
    Param($message)
    Write-Host $message -ForegroundColor Green -BackgroundColor Black
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

Function Upload-VHD {

    $jsonPath = Get_Settings
    $settingsContent = Get-Content -Path $jsonPath | Out-String 
    $settings = ConvertFrom-Json -InputObject $settingsContent

    $sourceFile = $settings.uagLocalFile
    $destinationFile = $settings.imageURI
    $resourceGroup = $settings.resourceGroupName

    $fileUpload = Add-AzVhd -ResourceGroupName $resourceGroup -Destination $destinationFile -LocalFilePath $sourceFile
}

# Create Azure Security Group for the Virtual Network
Function Create_Network_Security_Group {

    $jsonPath = Get_Settings
    $settingsContent = Get-Content -Path $jsonPath | Out-String 
    $settings = ConvertFrom-Json -InputObject $settingsContent
    $securityGroupName = $settings.securityGroupName
 
    $securityGroupExists = Get-AzNetworkSecurityGroup -Name $securityGroupName -ErrorVariable $noSecurityGroup -ErrorAction Continue
    If ($securityGroupExists -eq $null) {
        $httpsRule = New-AzNetworkSecurityRuleConfig -Name https-rule -Description "Allow HTTPS" -Access Allow -Protocol Tcp -Direction Inbound `
                      -Priority 100 -SourceAddressPrefix * -SourcePortRange * -DestinationAddressPrefix * -DestinationPortRange 443

        $udpRule = New-AzNetworkSecurityRuleConfig -Name udp-rule -Description "Allow UDP 443" -Access Allow -Protocol Udp -Direction Inbound `
                      -Priority 101 -SourceAddressPrefix * -SourcePortRange * -DestinationAddressPrefix * -DestinationPortRange 443
 

        $httpRule = New-AzNetworkSecurityRuleConfig -Name http-rule -Description "Allow HTTP" -Access Allow -Protocol Tcp -Direction Inbound `
                      -Priority 102 -SourceAddressPrefix * -SourcePortRange * -DestinationAddressPrefix * -DestinationPortRange 80

        $blastHttpRule = New-AzNetworkSecurityRuleConfig -Name http-blast-rule -Description "Allow Blast" -Access Allow -Protocol Tcp -Direction Inbound `
                      -Priority 103 -SourceAddressPrefix * -SourcePortRange * -DestinationAddressPrefix * -DestinationPortRange 8443

        $blastUDPRule = New-AzNetworkSecurityRuleConfig -Name udp-blast-rule -Description "Allow Blast" -Access Allow -Protocol Udp -Direction Inbound `
                      -Priority 104 -SourceAddressPrefix * -SourcePortRange * -DestinationAddressPrefix * -DestinationPortRange 8443

        $uagAdminRule = New-AzNetworkSecurityRuleConfig -Name uag-admin-rule -Description "UAG Admin" -Access Allow -Protocol Tcp -Direction Inbound `
                      -Priority 105 -SourceAddressPrefix * -SourcePortRange * -DestinationAddressPrefix * -DestinationPortRange 9443

        $nsg = New-AzNetworkSecurityGroup -ResourceGroupName $settings.resourceGroupName -Location $settings.location -Name $securityGroupName `
                    -SecurityRules $httpsRule, $httpRule, $udpRule, $blastHttpRule, $blastUDPRule, $uagAdminRule
    } Else {
        Write-Info-Message "Security Group {$securityGroupName} Exists"
    }
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

    $virtualNetworkExists = Get-AzVirtualNetwork -Name $virtualNetworkName -ErrorVariable $noVirtualNetwork -ErrorAction Continue
    If ($virtualNetworkExists -eq $null) {
        $networkSubnet = New-AzVirtualNetworkSubnetConfig -Name $subnetName -AddressPrefix 10.0.2.0/24
        $virtualNetwork = New-AzVirtualNetwork -ResourceGroupName $resourceGroupName -Location $location -Name $virtualNetworkName `
                            -AddressPrefix 10.0.2.0/24 -Subnet $networkSubnet


        $publicIPAddress = New-AzPublicIpAddress -Name $publicIPName -ResourceGroupName $resourceGroupName -Location $location `
                            -AllocationMethod Static -DomainNameLabel $dnsPrefix
    } Else {
        Write-Info-Message "Virtual Network $virtualNetworkName Exists!"
    }
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
    $publicIPName = $settings.publicIPName

    $nicExists = Get-AzNetworkInterface -Name "eth0" -ErrorVariable $noVirtualNetwork -ErrorAction Continue
    If ($nicExists -eq $null) {
        $virtualNetwork = Get-AzVirtualNetwork -Name $virtualNetworkName
        $securityGroup = Get-AzNetworkSecurityGroup -Name $securityGroupName
        $uagSubnet = Get-AzVirtualNetworkSubnetConfig -Name $subnetName -VirtualNetwork $virtualNetwork
        $publicIPAddress = Get-AzPublicIpAddress -Name $publicIPName

        $interfaceConfig = New-AzNetworkInterfaceIpConfig -Name "InterfaceConfig" -PublicIpAddress $publicIPAddress -Subnet $uagSubnet
        $nicCard = New-AzNetworkInterface -Name "eth0" -ResourceGroupName $resourceGroupName -Location $location -IpConfiguration $interfaceConfig `
                    -NetworkSecurityGroupId $securityGroup.Id
    } Else {
        Write-Info-Message "NIC Card eth0 Exists"
    }
}
    

Function Get-VHD-Uri {

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


# This is information that needs to be passed to the OS build process.  Need better documentation on exactly what this is.
Function Get-Custom-Data {

    $jsonPath = Get_Settings
    $settingsContent = Get-Content -Path $jsonPath | Out-String 
    $settings = ConvertFrom-Json -InputObject $settingsContent

    $customDataFilePath = $settings.customDataFile
    $customDataContent = Get-Content -Path $customDataFilePath
    $64bitCustomData = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes($customDataContent))
    
    return $64bitCustomData.toString()
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
    $publicIPAddress = Get-AzPublicIpAddress -Name $publicIPName
    $nicCard = Get-AzNetworkInterface -Name "eth0"

    $diskGUID = New-Guid
    $sourceDisk = Get-VHD-Uri
    $sourceDiskUri = $sourceDisk.AbsoluteUri
    Write-Output $sourceDiskURI
    $customData = Get-Custom-Data
    Write-Output $customData.GetType().FullName
    $diskName = "OSDisk-" + $diskGUID
    $destinationURI = $sourceDiskURI.Substring(0, $sourceDiskURI.LastIndexOf("/")) + "/osDisk.vhd"
    Write-Output $destinationURI
    $virtualMachineConfig = New-AzVMConfig -VMName $vmName -VMSize $vmSize
    $virtualMachineConfig = Set-AzVMOSDisk -VM $virtualMachineConfig -VhdUri $destinationURI -SourceImageUri $sourceDiskURI `
                                -Linux -CreateOption FromImage -Name $diskName
    $virtualMachineConfig = Set-AzVMOperatingSystem -VM $virtualMachineConfig -Linux -ComputerName $vmName -Credential $credentials `
                            -CustomData $customData
    $virtualMachineConfig = Add-AzVMNetworkInterface -VM $virtualMachineConfig -Id $nicCard.Id

    $virualMachine = New-AzVM -VM $virtualMachineConfig -ResourceGroupName $resourceGroupName -Location $location -Verbose
                        
}

# Main() - This is where the code actually starts.  It calls all of the functions above, with the exception of
# Write_Error_Message which gets called from the individual functions.
Write-Warning-Message "Validating Installed Modules"
Validate_AzureModules

# All settings are in a JSON file.  This call retrieves them.
Write-Warning-Message "Getting Settings"
Get_Settings

Write-Warning-Message "Connecting to Azure"
Connect_To_Azure

Write-Warning-Message "Uploading VHD"
# Upload-VHD

Write-Warning-Message "Creating Security Group"
Create_Network_Security_Group

Write-Warning-Message "Creating Virtual Network"
Create_Virtual_Network

Write-Warning-Message "Creating NIC(s)"
Create-NIC

Write-Warning-Message "Getting VHD URI"
Get-VHD-Uri

Write-Warning-Message "Getting Custom Data"
Get-Custom-Data

Write-Warning-Message "Create Virtual Machine"
Create-Virtual-Machine