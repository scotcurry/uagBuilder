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
	Write-Host $message -ForegroundColor White -backgroundcolor DarkRed
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
    Write-Info-Message ("*** Checking Azure Powershell Modules ***")
    If (-not (Get-InstalledModule -Name "Az")) {
        Write-Error-Message "Module Az Not Installed!"
        Write-Error-Message "Run (Install-Module -Name Az -AllowClobber -Scope AllUsers) as Administrator"
        Write-Error-Message "Then Run (Uninstall-AzureRM) as Administrator, might not do anything but cleans up old method"
        Exit
    }
}

# Get the settings to run this script from a file called UAGSettings.json
Function Get-Settings {

    Write-Info-Message ("Getting Settings")
    #Check if the UAGSettings.json exists
    $scriptFolder = $PSScriptRoot
    $jsonPath = $scriptFolder + "\BuildUAGSettings.json"
    If (-not (Test-Path -Path $jsonPath)) {
        Write_Error_Message "Didn't find UAGSettings.json in path ($jsonPath)"
        Exit
    } Else {
        $settingsContent = Get-Content -Path $jsonPath | Out-String
        $settings = ConvertFrom-Json -InputObject $settingsContent
        return $settings
    }
}

# This function makes a connection to your Azure instance using the subscription ID.
Function Connect-To-Azure {

    param ($settings)

    Write-Info-Message("*** Connecting To Azure ***")
    Write-Info-Message("*** SubscriptionID: " + $settings.subscriptionID)

    $connected = Get-AzSubscription -SubscriptionId $settings.subscriptionID -WarningVariable $errorConnecting -WarningAction Continue
    If ($null -eq $connected) {
        $connected = Connect-AzAccount -Subscription $settings.subscriptionID
    }
    if ($null -eq $connected) {
        Write-Error-Message ("Failure Connecting to Azure with ID : " + $settings.subscriptionID)
    }
    $tenantID = (Get-AzContext).Tenant.Id
    Write-Info-Message "Connected to Azure Tenant $tenantID"
}


Function Get-Current-Environment-Info {

    param ($settings)

    # These are all the checks that are going to be made to see what needs to be added.
    $components = @{}

    Write-Info-Message ("*** Checking Resource Group ***")
    $location = $settings.location
    $resourceGroupName = $settings.resourceGroupName
    $resourceGroup = Get-AzResourceGroup -Name $resourceGroupName -Location $location
    If ($null -eq $resourceGroup) {
        Write-Warning-Message ("Resource Group Needs to be Built: " + $resourceGroupName)
        $components.Add("resourceGroupExists", $false)
    } else {
        Write-Info-Message "Resource Group $resourceGroupName Exists!"
        $components.Add("resourceGroupExists", $true)
    }

    Write-Info-Message ("*** Checking Storage Account ***")
    $storageAccount = Get-AzStorageAccount -Name $settings.storageAccountName -ResourceGroupName $resourceGroupName
    if ($null -eq $storageAccount) {
        Write-Warning-Message("Storage Account Needs to be Built")
        $components.Add("storageAccountExists", $false)
    } else {
        $components.Add("storageAccountExists", $true)
        Write-Info-Message ("Storage Account $storageAccountName Exists")
        $storageContext = $storageAccount.Context
    }

    Write-Info-Message ("*** Checking Storage Container ***")
    if ($null -eq $storageContext) {
        Write-Warning-Message ("Storage Container Needs to be Built - No Context")
    } else {
        $storageContainer = Get-AzStorageContainer -Name $settings.storageContainerName -Context $storageContext
        if ($null -eq $storageContainer) {
            $components.Add("storageContainerExists", $false)
            Write-Warning-Message ("Storage Container Needs to be Built - No Container")
        } else {
            Write-Info-Message ("Storage Container Exists")
            $components.Add("storageContainerExists", $true)
        }
    }

    Write-Info-Message ("*** Checking Storage Blob ***")
    $vhdBlob = Get-AzStorageBlob -Context $storageContext -Container $storageContainer.Name -Blob $settings.vhdFileName
    if ($null -eq $vhdBlob) {
        $components.Add("storageBlobExists", $false)
        Write-Warning-Message ("Storage Blob Doesn't Exist - Needs to be Uploaded")
    } else {
        $components.Add("storageBlobExists", $true)
        Write-Info-Message ("Storage Blob Exists")
    }

    Write-Info-Message ("*** Checking Security Group ***")
    $networkSecurityGroupName = $settings.networkSecurityGroupName
    $securityGroupExists = Get-AzNetworkSecurityGroup -Name $networkSecurityGroupName -ErrorVariable $noSecurityGroup -ErrorAction Continue
    if ($null -eq $securityGroupExists) {
        $components.Add("networkSecurityGroupExists", $false)
        Write-Warning-Message ("Security Group Doesn't Exist")
    } else {
        $components.Add("networkSecurityGroupExists", $true)
        Write-Info-Message ("Security Group Exists")
    }

    Write-Info-Message ("*** Checking Virtual Network ***")
    $virtualNetworkName = $settings.virtualNetworkName
    $virtualNetwork = Get-AzVirtualNetwork -Name $virtualNetworkName
    if ($null -eq $virtualNetwork) {
        $components.Add("virtualNetworkExists", $false)
        Write-Warning-Message ("Virtual Network Doesn't Exits")
    } else {
        $components.Add("virtualNetworkExists", $true)
        Write-Info-Message ("Virtual Network Exists")
    }

    Write-Info-Message ("*** Checking Subnet ***")
    if ($null -eq $virtualNetwork) {
        $components.Add("virtualSubnetExists", $false)
        Write-Warning-Message ("Virtual Subnet Doens't Exit")
    } else {
        $virtualSubnet = Get-AzVirtualNetworkSubnetConfig -Name $settings.subnetName -VirtualNetwork $virtualNetwork
        if ($null -eq $virtualSubnet) {
            $components.Add("virtualSubnetExists", $false)
            Write-Warning-Message ("Virtual Subnet Doens't Exit")
        } else {
            Write-Info-Message ("Virtual Subnet Exists")
            $components.Add("virtualSubnetExists", $true)
        }
    }

    Write-Info-Message ("*** Checking Public IP Address ***")
    $publicIPAddress = Get-AzPublicIpAddress -Name $settings.publicIPAddressName -ResourceGroupName $resourceGroupName
    if ($null -eq $publicIPAddress) {
        $components.Add("publicIPAddressExists", $false)
        Write-Warning-Message ("Public IP Address Doesn't Exist")
    } else {
        Write-Info-Message ("Public IP Address Exists")
        $components.Add("publicIPAddressExists", $true)
    }

    Write-Info-Message ("*** Checking UAG Nic Card ***")
    $nicCard = Get-AzNetworkInterface -ResourceGroupName $resourceGroupName -Name $settings.uagNICName -ErrorAction Continue
    if ($null -eq $nicCard) {
        $components.Add("nicCardExists", $false)
        Write-Warning-Message ("UAG NIC Card Doesn't Exist")
    } else {
        $components.Add("nicCardExists", $true)
        Write-Info-Message("UAG NIC Card Exists")
    }

    Write-Info-Message ("*** Checking if UAG VM Exists ***")
    $virtualMachine = Get-AzVM -ResourceGroupName $resourceGroupName -Name $settings.virtualMachineName -ErrorAction SilentlyContinue `
        -ErrorVariable $noVirtualMachine
    if ($null -eq $virtualMachine) {
        $components.Add("virtualMachineExists", $false)
        Write-Warning-Message ("Virtual Machine Doesn't Exist")
    } else {
        Write-Info-Message ("Virtual Machine Exists")
        $components.Add("virtualMachineExists", $true)
    }

    return $components
}

# Main() - This is where everything starts.  Read the JSON file for the settings, make sure the right Azure
# modules are installed and then check to see what already exists in Azure.
$settings = Get-Settings
Find-AzureModules
Connect-To-Azure($settings)

# Once we have what is installed, build out everything else.
$components = Get-Current-Environment-Info($settings)

$resourceGroup = $components.resourceGroupExists
Write-Error-Message ("Resource Group Exists: $resourceGroup")
if ($false -eq $components.resourceGroupExists) {
    $resourceGroup = New-AzResourceGroup -Location $settings.location -Name $settings.resourceGroupName
}

if ($false -eq $components.storageAccountExists) {
    $storageAccount = New-AzStorageAccount -ResourceGroupName $settings.resourceGroupName -Location $settings.location `
            -SkuName Standard_LRS -Kind StorageV2 -Name $settings.storageAccountName
    $storageContext = $storageAccount.Context
} else {
    $storageAccount = Get-AzStorageAccount -Name $settings.storageAccountName -ResourceGroupName $settings.resourceGroupName
    $storageContext = $storageAccount.Context
}

if ($false -eq $components.storageContainerExists) {
    $storageContainer = New-AzStorageContainer -Name $settings.storageContainerName -Context $storageContext
}

if ($false -eq $components.storageBlobExists) {
    $blobContainerBase = $storageContext.BlobEndPoint
    $destinationFile = $blobContainerBase + $settings.storageContainerName + "/" + $settings.vhdFileName
    Add-AzVhd -ResourceGroupName $settings.resourceGroupName -LocalFilePath $settings.uagLocalFile `
            -Destination $destinationFile
}

if ($false -eq $components.networkSecurityGroupExists) {
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

        New-AzNetworkSecurityGroup -ResourceGroupName $settings.resourceGroupName -Location $settings.location `
            -Name $settings.networkSecurityGroupName -SecurityRules $httpsRule, $httpRule, $udpRule, $blastHttpRule, $blastUDPRule, $uagAdminRule
}

if ($false -eq $components.virtualSubnetExists) {
    Write-Warning-Message ("Buildiing Subnet")
    $networkSubnet = New-AzVirtualNetworkSubnetConfig -Name $settings.subnetName -AddressPrefix 10.0.2.0/24
}

if ($false -eq $components.virtualNetworkExists) {
    $virtualNetwork = New-AzVirtualNetwork -ResourceGroupName $settings.resourceGroupName -Location $settings.location `
     -Name $settings.virtualNetworkName -AddressPrefix 10.0.0.0/16 -Subnet $networkSubnet
}

if ($false -eq $components.publicIPAddressExists) {
    $publicIPAddress = New-AzPublicIpAddress -Name $settings.publicIPAddressName -ResourceGroupName $settings.resourceGroupName `
        -Location $settings.location -AllocationMethod Dynamic -DomainNameLabel $settings.publicDNSPrefix
}

if ($false -eq $components.nicCardExists) {
    $virtualNetwork = Get-AzVirtualNetwork -Name $settings.virtualNetworkName
    $securityGroup = Get-AzNetworkSecurityGroup -Name $settings.networkSecurityGroupName
    $uagSubnet = Get-AzVirtualNetworkSubnetConfig -Name $settings.subnetName -VirtualNetwork $virtualNetwork
    $publicIPAddress = Get-AzPublicIpAddress -Name $settings.publicIPAddressName

    $interfaceConfig = New-AzNetworkInterfaceIpConfig -Name "UAGInterfaceConfig" -PublicIpAddress $publicIPAddress -Subnet $uagSubnet
    $nicCard = New-AzNetworkInterface -Name $settings.uagNICName -ResourceGroupName $settings.resourceGroupName -Location `
        $settings.location -IpConfiguration $interfaceConfig -NetworkSecurityGroupId $securityGroup.Id
}

# This function is needed to get all of the seed values for the VM.  This only gets called if the VM needs to be created
Function Get-Custom-Data {

    [OutputType("System.String")]
    $settings = Get-Settings

    $vmSettings = "deploymentOption=" + $settings.deploymentOption + "`r`n"
    $vmSettings = $vmSettings + "rootPassword=" + $settings.rootPassword + "`r`n"
    $vmSettings = $vmSettings + "adminPassword=" + $settings.uagPassword + "`r`n"
    $vmSettings = $vmSettings + "ipMode0=DHCPV4+DHCPV6`r`n"

    $emptyArray = @()
    $kerbKeyTabSettings = [PSCustomObject]@{
        kerberosKeyTabSettings = $emptyArray
    }

    $kerberosRealmSettingsListArray = [PSCustomObject]@{
        kerberosRealmSettingsList = $emptyArray 
    }

    $idPExternalMetadataSettingsListArray = [PSCustomObject]@{
        idPExternalMetadataSettingsList = $emptyArray
    }

    $edgeServiceSettingsListArray = [PSCustomObject]@{
        edgeServiceSettingsList = $emptyArray
    }

    $settingsObject = [PSCustomObject]@{
        locale = "en_US"
        ssl30Enabled = "false"
        tls10Enabled = "false"
        tls11Enabled = "false"
        tls12Enabled = "true"
        tls13Enabled = "true"
        sysLogType = "UDP"
    }

    $authMethodSettingsListArray = [PSCustomObject]@{
        authMethodSettingsList = $emptyArray
    }

    $serviceProviderMetadataListArray = [PSCustomObject]@{
        items = $emptyArray
    }

    $allSettingsJSON = [PSCustomObject]@{
        kerberosKeyTabSettingsList = $kerbKeyTabSettings
        kerberosRealmSettingsList = $kerberosRealmSettingsListArray
        idPExternalMetadataSettingsList = $idPExternalMetadataSettingsListArray
        edgeServiceSettingsList = $edgeServiceSettingsListArray
        systemSettings = $settingsObject
        authMethodSettingsList = $authMethodSettingsListArray
        serviceProviderMetadataList = $serviceProviderMetadataListArray
        identityProviderMetaData = @{}
    }

    $settingsJSONString = ConvertTo-Json -InputObject $allSettingsJSON -Compress
    $jsonForSettings = $settingsJSONString.Replace("`"", "\`"")

    $vmSettings = $vmSettings + "settingsJSON=" + $jsonForSettings + "`r`n"
    $base64Settings = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes($vmSettings))
    return $base64Settings
}

# This is built to validate that all of the components above exist and builds the VM.
if ($false -eq $components.virtualMachineExists) {

    # Get all of the storage portions ready.
    $resourceGroup = Get-AzResourceGroup -Name $settings.resourceGroupName -Location $settings.location
    Write-Info-Message ("Resource Group Name: " + $resourceGroup.ResourceGroupName)
    $storageAccount = Get-AzStorageAccount -ResourceGroupName $resourceGroup.ResourceGroupName -Name $settings.storageAccountName
    $storageContext = $storageAccount.Context
    $blobEndpoint = $storageAccount.PrimaryEndpoints.Blob
    Write-Info-Message("Storage Blob Endpoint: " + $blobEndpoint)
    $storageContainer = Get-AzStorageContainer -Name $settings.storageContainerName -Context $storageContext
    Write-Info-Message ("Storage Container: " + $storageContainer.Name)
    $storageBlob = Get-AzStorageBlob -Container $settings.storageContainerName -Context $storageAccount.Context `
        -Blob $settings.vhdFileName
    $storageBlobURI = $storageBlob.BlobClient.Uri
    Write-Info-Message ("Storage Blob URI: " + $storageBlobURI)
    $oldDiskExists = Get-AzStorageBlob -Container $settings.storageContainerName -Context $storageContext -Blob "winvmosDisk.vhd" `
        -ErrorAction SilentlyContinue -ErrorVariable $noOldDisk
    if ($null -ne $oldDiskExists) {
        Write-Warning-Message ("Deleting Old OS Disk")
        Remove-AzStorageBlob -Context $storageContext -Container $settings.storageContainerName -Blob "osDisk.vhd"
    }

    # Start building out the VM
    $virtualMachineConfig = New-AzVMConfig -VMName $settings.virtualMachineName -VMSize $settings.vmSize

    # Add the NIC Card
    $nicCard = Get-AzNetworkInterface -ResourceGroupName $resourceGroup.ResourceGroupName -Name $settings.uagNICName
    Write-Info-Message ("Using NIC Card: " + $nicCard.ID)
    $virtualMachineConfig = Add-AzVMNetworkInterface -VM $virtualMachineConfig -Id $nicCard.Id

    # Build out the disk information - hard coding the OS disk for easy cleanup.
    $destinationURI = $blobEndpoint + $storageContainer.Name + "/osDisk.vhd"
    $virtualMachineConfig = Set-AzVMOSDisk -VM $virtualMachineConfig -VhdUri $destinationURI -SourceImageUri $storageBlobURI `
        -Linux -CreateOption FromImage -Name "UAGOSDisk"

    # Set the OS Parameters.  The custom data section is a bit of a black box right now
    $customData = Get-Custom-Data
    $customData = $customData.ToString()
    $securePassword = ConvertTo-SecureString -String $settings.rootPassword -AsPlainText -Force
    $credentials = New-Object -TypeName System.Management.Automation.PSCredential `
        -ArgumentList $settings.rootUserName, $securePassword
    $virtualMachineConfig = Set-AzVMOperatingSystem -VM $virtualMachineConfig -Linux -ComputerName $settings.virtualMachineName `
        -Credential $credentials -CustomData $customData

    # Actually build out the VM
    New-AzVM -VM $virtualMachineConfig -ResourceGroupName $resourceGroup.ResourceGroupName `
        -Location $settings.location -Verbose
}