#Requires -Version 5
#Requires -Modules VMware.ImageBuilder

#Copyright (C) 2020 John Hossbach
#See LICENSE file for full details

Param(
	[ValidateScript({[regex]::new($_) -is [regex]})][String]$VersionFilter = ''
	,[Switch] $Custom
	,[ValidateRange(0, [int]::MaxValue - 1)][int]$nminus = 0
)

#$versionfilter = '6.5.0-*'
#$versionfilter = '6.5.0-4564106-*'
#$versionfilter = '6.5.0-20191204001*'
#$versionfilter = '6.7.0-201908*'
#Set nminus to 0 for latest version

function Get-KeyPress{
	# https://stackoverflow.com/questions/150161/waiting-for-user-input-with-a-timeout
	Param(
		[ValidateScript({[regex]::new("[$_]") -is [regex]})][String]$Options = 'ynq',
		[string]$Message = $null,
		[int]$timeOutSeconds = 0
	)

	# Initialize
	$regexPattern = [regex]::new("[$Options]")
	$checkInterval = 250
	$key = $null
	try {
	$Host.UI.RawUI.FlushInputBuffer()
	}
	catch {
		Write-Host 'Failed to FlushInputBuffer'
	}

	# Prompt user
	if (![string]::IsNullOrEmpty($Message))
	{
		Write-Host -NoNewLine $Message
	}

	# Get key press
	$counter = $timeOutSeconds * 1000 / $checkInterval
	while($null -eq $key -and ($timeOutSeconds -eq 0 -or $counter-- -gt 0))
	{
		if (($timeOutSeconds -eq 0) -or $Host.UI.RawUI.KeyAvailable)
		{
			$key_ = $host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown,IncludeKeyUp')
			if ($key_.KeyDown -and $key_.Character -match $regexPattern)
			{
				$key = $key_
			}
		}
		else
		{
			Start-Sleep -m $checkInterval  # Milliseconds
		}
	}

	if (-not ($null -eq $key))
	{
		Write-Host -NoNewLine "$($key.Character)"
	}

	if (![string]::IsNullOrEmpty($Message))
	{
		Write-Host '' # newline
	}

	return $(if ($null -eq $key) {$null} else {$key.Character})
}

#Import online software depot
'Connecting to the VMware online software depot...'
Add-EsxSoftwareDepot https://hostupdate.vmware.com/software/VUM/PRODUCTION/main/vmw-depot-index.xml

#Get latest image profile
'Getting image profile list...'
$ips_std_all = Get-EsxImageProfile -Name '*-standard' # | Where-Object { $_.Name -match '^ESXi-(?<FullVer>(?<BaseVer>(?:\d+\.)+(?:U\d+)?)\w*)-(?:\d+s?)-standard$' }
$ips_std = $ips_std_all | Where-Object { ($_.VibList | Where-Object { $_.Name -eq 'esx-base' }).Version -like $(if ([String]::IsNullOrEmpty($VersionFilter)) { '*' } else { $VersionFilter }) }
$latest_ip = $ips_std | Sort-Object @{E={[version] (($_.VibList | Where-Object { $_.Name -eq 'esx-base' }).Version -split '-')[0] }},@{E={[version] (($_.VibList | Where-Object { $_.Name -eq 'esx-base' }).Version -split '-')[1] }} | Select-Object -Last (1 + $nminus) | Select-Object -First 1
$shortver = (($latest_ip.VibList | Where-Object { $_.Name -eq 'esx-base' }).Version -split '-')[0]

if ($null -eq $latest_ip) {
	'Failed to find an image profile.'
	exit
} else {
	'Chose image profile: ' + $latest_ip.Name
	'esx-base version: ' + ($latest_ip.VibList | Where-Object { $_.Name -eq 'esx-base' }).Version
}


if ($custom) {
	$folder = 'Custom'
	#Import third-party online software depots
	'Connecting to third-party online software depots...'
	Add-EsxSoftwareDepot http://vibsdepot.v-front.de
	#HPE: http://vibsdepot.hpe.com/index.xml
	#Dell: No online depot, download latest offline bundle. https://www.dell.com/support/article/gy/en/gybsdt1/sln288152/how-to-download-the-dell-customized-esxi-embedded-iso-image?lang=en
	#Dell (for Update Manager): http://vmwaredepot.dell.com/index.xml


	#Import local software depots
	#Add-EsxSoftwareDepot !Bundles\net55-r8168-8.045a-napi-offline_bundle.zip
	#Add-EsxSoftwareDepot !Bundles\sata-xahci-1.40-1-offline_bundle.zip


	#Set image profile information
	$orig_profile = $latest_ip.Name
	$new_profile = $orig_profile -replace '-standard','-BRiX'


	#Build image profile
	'Creating new profile...'
	New-EsxImageProfile -CloneProfile $orig_profile -name $new_profile -Vendor 'Hossy' -AcceptanceLevel 'CommunitySupported'
	Add-EsxSoftwarePackage -ImageProfile $new_profile -SoftwarePackage 'sata-ahci'
	Add-EsxSoftwarePackage -ImageProfile $new_profile -SoftwarePackage 'sata-xahci'
	#Add-EsxSoftwarePackage -ImageProfile $new_profile -SoftwarePackage 'net-r8168'
	Add-EsxSoftwarePackage -ImageProfile $new_profile -SoftwarePackage 'net55-r8168'
} else {
	$folder = $shortver
	$new_profile = $latest_ip.Name
}

#Export image profile
$targetpath = "$PSScriptRoot\$folder"
if (-not (Test-Path -PathType Container -Path $targetpath)) {
	"Creating directory: $targetpath"
	New-Item -ItemType Directory -Path $targetpath | Out-Null
}
$prefix = "$targetpath\$new_profile"
$isofile = "$prefix.iso"
$bundlefile = "$prefix.zip"
$retry = $false
$retrycount = 0
do {
	if (-not $retry -or -not (Test-Path $isofile)) {
		"Exporting ISO to $prefix.iso..."
		Export-ESXImageProfile -ImageProfile $new_profile -ExportToISO -filepath $isofile
	}
	if (-not $retry -or -not (Test-Path $bundlefile)) {
		"Exporting Offline bundle to $prefix.zip..."
		Export-ESXImageProfile -ImageProfile $new_profile -ExportToBundle -filepath $bundlefile
	}
	if ($retrycount++ -ge 10) { break }
	if (-not (Test-Path $isofile) -or -not (Test-Path $bundlefile)) {
		$r = Get-KeyPress -Options 'yn' -Message 'Retry export [yn]?' -timeOutSeconds 10
		if ($null -eq $r -or ($r -is [Char] -and $r.ToString().ToLower() -eq 'y')) { $retry = $true }
		else { $retry = $false }
	}
} while ($retry)

#esxcli software profile update -d /vmfs/volumes/local-hossy-vmware/ESXi-6.7.0-20210304001-BRiX.zip -p ESXi-6.7.0-20210304001-BRiX --dry-run
#esxcli software profile update -d /vmfs/volumes/local-hossy-vmware/ESXi-6.7.0-20210304001-BRiX.zip -p ESXi-6.7.0-20210304001-BRiX
#esxcli software profile update -d https://hostupdate.vmware.com/software/VUM/PRODUCTION/main/vmw-depot-index.xml -p ESXi-6.7.0-20210304001-standard --dry-run
