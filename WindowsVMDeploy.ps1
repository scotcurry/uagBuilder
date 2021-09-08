<# IMPORTANT NOTE: For some reason RDP does seem to work right after the VM is deployed.  Go to 
    RDP troubleshooting and there is an option to rebuild VM which seemed to solve the issue. #>

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
	Write-Host $message -ForegroundColor Red -BackgroundColor Black
}

# This function provides the Information strings.  Things like where you are in the process.
Function Write-Warning-Message {

    Param ($message)
	Write-Host $message -ForegroundColor Yellow -BackgroundColor Black
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

Function Get-Settings {

    Write-Info-Message ("Getting Settings")
    #Check if the UAGSettings.json exists
    $scriptFolder = $PSScriptRoot
    $jsonPath = $scriptFolder + "\WindowsVMSettings.json"
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
        $connected = Connect-AzAccount -Subscription $settings.subscriptionID -TenantId "945c199a-83a2-4e80-9f8c-5a91be5752dd"
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

    Write-Info-Message ("*** Checking WinVM Nic Card ***")
    $nicCard = Get-AzNetworkInterface -ResourceGroupName $resourceGroupName -Name $settings.winVMNICName -ErrorAction Continue
    if ($null -eq $nicCard) {
        $components.Add("nicCardExists", $false)
        Write-Warning-Message ("WinVM NIC Card Doesn't Exist")
    } else {
        $components.Add("nicCardExists", $true)
        Write-Info-Message("WinVM NIC Card Exists")
    }

    Write-Info-Message ("*** Checking if Windows VM Exists ***")
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


# Main() - This is where the code actually starts.  It calls all of the functions above, with the exception of
Write-Info-Message "Validating Installed Modules"
Find-AzureModules

# All settings are in a JSON file.  This call retrieves them.
Write-Info-Message "Getting Settings"
$settings = Get-Settings

Write-Info-Message "Connecting to Azure"
Connect-To-Azure($settings)

$components = Get-Current-Environment-Info($settings)

Write-Info-Message ("ResourceGroupExists $components.resourceGroupExists")
if ($false -eq $components.resourceGroupExists) {
    $resourceGroup = New-AzResourceGroup -Location $settings.location -Name $settings.resourceGroupName
}

if ($false -eq $components.storageAccountExists) {
    $storageAccount = New-AzStorageAccount -ResourceGroupName $settings.resourceGroupName -Location $settings.location `
            -SkuName Standard_LRS -Kind StorageV2 -Name $settings.storageAccountName
    $storageContext = $storageAccount.Context
} else {
    $storageAccount = Get-AzStorageAccount -Name $settings.storageAccountName -ResourceGroupName $settings.resourceGroupName
}

if ($false -eq $components.storageContainerExists) {
    New-AzStorageContainer -Name $settings.storageContainerName -Context $storageContext
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

    $rdpRule = New-AzNetworkSecurityRuleConfig -Name rdp-rul -Description "Allow RDP 3389" -Access Allow -Protocol Tcp -Direction Inbound `
        -Priority 106 -SourceAddressPrefix * -SourcePortRange 3389 -DestinationAddressPrefix * -DestinationPortRange 3389

        New-AzNetworkSecurityGroup -ResourceGroupName $settings.resourceGroupName -Location $settings.location `
            -Name $settings.networkSecurityGroupName -SecurityRules $httpsRule, $httpRule, $udpRule, $blastHttpRule, $blastUDPRule, $uagAdminRule
}

if ($false -eq $components.publicIPAddressExists) {
    $publicIPAddress = New-AzPublicIpAddress -Name $settings.publicIPAddressName -ResourceGroupName $settings.resourceGroupName `
        -Location $settings.location -AllocationMethod Dynamic -DomainNameLabel $settings.publicDNSPrefix
}

if ($false -eq $components.virtualSubnetExists) {
    Write-Warning-Message ("Buildiing Subnet")
    $networkSubnet = New-AzVirtualNetworkSubnetConfig -Name $settings.subnetName -AddressPrefix 10.0.2.0/24
}

if ($false -eq $components.virtualNetworkExists) {
    $virtualNetwork = New-AzVirtualNetwork -ResourceGroupName $settings.resourceGroupName -Location $settings.location `
     -Name $settings.virtualNetworkName -AddressPrefix 10.0.0.0/16 -Subnet $networkSubnet
}

if ($false -eq $components.nicCardExists) {
    $virtualNetwork = Get-AzVirtualNetwork -Name $settings.virtualNetworkName
    $securityGroup = Get-AzNetworkSecurityGroup -Name $settings.networkSecurityGroupName
    $uagSubnet = Get-AzVirtualNetworkSubnetConfig -Name $settings.subnetName -VirtualNetwork $virtualNetwork

    $interfaceConfig = New-AzNetworkInterfaceIpConfig -Name "WinVMInterfaceConfig" -Subnet $uagSubnet `
        -PublicIpAddress $publicIPAddress
    $nicCard = New-AzNetworkInterface -Name $settings.winVMNICName -ResourceGroupName $settings.resourceGroupName -Location `
        $settings.location -IpConfiguration $interfaceConfig -NetworkSecurityGroupId $securityGroup.Id
}

if ($false -eq $components.virtualMachineExists) {

    # Get all of the storage portions ready.
    $resourceGroup = Get-AzResourceGroup -Name $settings.resourceGroupName -Location $settings.location
    Write-Info-Message ("Resource Group Name: " + $resourceGroup.ResourceGroupName)
    $storageAccount = Get-AzStorageAccount -ResourceGroupName $resourceGroup.ResourceGroupName -Name $settings.storageAccountName
    $storageContext = $storageAccount.Context
    $oldDiskExists = Get-AzStorageBlob -Container $settings.storageContainerName -Context $storageContext -Blob "winvmosDisk.vhd" `
        -ErrorAction SilentlyContinue -ErrorVariable $noOldDisk
    if ($null -ne $oldDiskExists) {
        Write-Warning-Message ("Deleting Old OS Disk")
        Remove-AzStorageBlob -Context $storageContext -Container $settings.storageContainerName -Blob "osDisk.vhd"
    }

    # Start building out the VM
    $virtualMachineConfig = New-AzVMConfig -VMName $settings.virtualMachineName -VMSize $settings.winVMSize `

    # Add the NIC Card
    $nicCard = Get-AzNetworkInterface -ResourceGroupName $resourceGroup.ResourceGroupName -Name $settings.winVMNICName
    Write-Info-Message ("Using NIC Card: " + $nicCard.ID)
    $virtualMachineConfig = Add-AzVMNetworkInterface -VM $virtualMachineConfig -Id $nicCard.Id

    # Set the OS Parameters.  The custom data section is a bit of a black box right now
    $securePassword = ConvertTo-SecureString -String $settings.winVMPassword -AsPlainText -Force
    $credentials = New-Object -TypeName System.Management.Automation.PSCredential `
        -ArgumentList $settings.winVMUserName, $securePassword
    $virtualMachineConfig = Set-AzVMOperatingSystem -VM $virtualMachineConfig -Windows -ComputerName $settings.virtualMachineName `
        -Credential $credentials -EnableAutoUpdate
    $storageBlob = Get-AzStorageContainer -Name $settings.storageContainerName -Context $storageAccount.Context
    $storageBlobURI = $storageBlob.Context.BlobEndPoint + $settings.storageAccountName
    Write-Error-Message $storageBlobURI

    # To build out the vm you need a source image, VM operating system
    $virtualMachineConfig = Set-AzVMSourceImage -VM $virtualMachineConfig -PublisherName "MicrosoftWindowsServer" `
        -Offer "WindowsServer" -Skus "2019-Datacenter" -Version "latest"
    $virtualMachineConfig = Set-AzVMOperatingSystem -VM $virtualMachineConfig -Windows -ComputerName $settings.virtualMachineName `
        -Credential $credentials
    $virtualMachineConfig = Set-AzVMOSDisk -VM $virtualMachineConfig -CreateOption "FromImage" -Name "win_osdisk" `
        -StorageAccountType "StandardSSD_LRS"
    # Actually build out the VM
    
    New-AzVM -VM $virtualMachineConfig -ResourceGroupName $resourceGroup.ResourceGroupName `
       -Location $settings.location -Verbose 
}