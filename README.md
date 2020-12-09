# UAGBuilder
Powershell script to build UAG

## Syntax

Windows - `Powershell.exe -File UAGDeployAZ.ps1`

MacOS - `pwsh -File UAGDeployAZ.ps1`

## Notes

**Important** - The script uses a settings file `UAGSettings.json`.  This file must be in the same folder as the script, and it must be that exact name (case sensitive if running on a Mac).  The example is a working config file.  I would suggest keeping the syntax of the Azure components the same as in the example file, meaning don't add spaces or special characters as the script doesn't do a lot of error checking.

**Powershell Az Module** - This script relies on the [Az Module](https://docs.microsoft.com/en-us/powershell/azure/new-azureps-module-az) for cross platform compatibility.  The script does check to make sure that it is installed, but to save time you may want to run _Install-Module -Name Az -Force_ prior to running the script.

**Location** - The item in the settings file that may not be entirely clear is the location field.  To find the name of the location you would like to use run the [Get-AzLocation](https://docs.microsoft.com/en-us/powershell/module/az.resources/get-azlocation) command to find the location to use.
