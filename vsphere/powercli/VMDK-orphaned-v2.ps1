#Copyright (C) 2016 John Hossbach
#See LICENSE file for full details

#Originally from http://virtuallyjason.blogspot.com/2013/08/orphaned-vmdk-files.html
#Modified by John Hossbach

$activity = 'Initializing'
Write-Progress -Activity $activity -Status 'Gathering environment information' -CurrentOperation 'Getting list of all datastores' -percentComplete 0
#$arrDS = Get-Datastore | Sort-Object -property Name
$arrDS = Get-Datastore | Where-Object { $_.ExtensionData.Summary.MultipleHostAccess -eq $True } | Sort-Object -property Name

$activity = 'Finding orphaned VMX/VMTX files'
Write-Progress -Activity $activity -Status 'Gathering environment information' -CurrentOperation 'Getting list of all known VMXs/VMTXs' -percentComplete 0
$arrVMPaths = Get-View -ViewType VirtualMachine | ForEach-Object {$_.Config} | ForEach-Object {$_.Files} | ForEach-Object {$_.VmPathName}

Write-Progress -Activity $activity -Status "Searching datastores for VMX/VMTX files (0 of $($arrDS.Length))" -percentComplete 0
$begin = Get-Date
$i=0
foreach ($ds in $arrDS) {
	$discoveredFolder = $null
	$dsVMHost = $null
	if ($i -eq 0) {
		Write-Progress -Activity $activity -Status "Searching datastores for VMX/VMTX files ($i of $($arrDS.Length))" -CurrentOperation $ds.Name -percentComplete 0
	} else {
		Write-Progress -Activity $activity -Status "Searching datastores for VMX/VMTX files ($i of $($arrDS.Length))" -CurrentOperation $ds.Name -percentComplete ($i*100/($arrDS.Length)) -SecondsRemaining (((Get-Date) - $begin).TotalSeconds / $i * ($arrDS.Length - $i))
	}
	#Write-Host $ds.Name
	#$ds_extdata = Get-Datastore -Name $ds.Name | ForEach-Object {Get-View $_.Id}
	$fileQueryFlags = New-Object VMware.Vim.FileQueryFlags
	$fileQueryFlags.FileSize = $true
	$fileQueryFlags.FileType = $true
	$fileQueryFlags.Modification = $true
	$searchSpec = New-Object VMware.Vim.HostDatastoreBrowserSearchSpec
	$searchSpec.details = $fileQueryFlags
	$searchSpec.matchPattern = '*.vmx','*.vmtx'
	$searchSpec.sortFoldersFirst = $true
	$dsBrowser = Get-View $ds.ExtensionData.browser
	$rootPath = '[' + $ds.ExtensionData.Name + ']'
	$searchResult = $dsBrowser.SearchDatastoreSubFolders($rootPath, $searchSpec)

	if ($i -eq 0) {
		Write-Progress -Activity $activity -Status "Searching datastores for VMX/VMTX files ($i of $($arrDS.Length)) - Parsing results" -CurrentOperation $ds.Name -percentComplete 0
	} else {
		Write-Progress -Activity $activity -Status "Searching datastores for VMX/VMTX files ($i of $($arrDS.Length)) - Parsing results" -CurrentOperation $ds.Name -percentComplete ($i*100/($arrDS.Length)) -SecondsRemaining (((Get-Date) - $begin).TotalSeconds / $i * ($arrDS.Length - $i))
	}

	foreach ($folder in $searchResult)
	{
		foreach ($fileResult in $folder.File)
		{
			if ($fileResult.Path)
			{
				$FilePath = ($folder.FolderPath + $fileResult.Path)
				if (-not ($arrVMPaths -contains $FilePath)){
					if ($discoveredFolder -eq $null) {
						$topVMFolder = Get-Folder -Location $ds.Datacenter | Where-Object { $_.Type -eq 'VM' } | Select-Object -First 1
						$discoveredFolder = Get-Folder -Location $topVMFolder -Name 'Discovered virtual machine' -ErrorAction SilentlyContinue
						if ($discoveredFolder -eq $null) {
							$discoveredfolder = New-Folder -Name 'Discovered virtual machine' -Location $topVMFolder
						}
					}
					if ($dsVMHost -eq $null) {
						$dsVMHost = Get-VMHost -Id $ds.ExtensionData.Host[0].Key
					}
					"Registering orphaned VM to $($dsVMHost.Name): $FilePath" | Out-Host
					switch -regex ($fileResult.Path)
					{
						'.*?\.vmx' { New-VM -VMFilePath $FilePath -VMHost $dsVMHost -Location $discoveredFolder | Out-String | Out-Host }
						'.*?\.vmtx' { New-Template -TemplateFilePath $FilePath -VMHost $dsVMHost -Location $discoveredFolder | Out-String | Out-Host }
						default { Write-Error "Unknown file type attempting to register: $FilePath" }
					}
				}
			}
		}
	}
	$i++
}
"VMX scan execution time: {0:c}" -f ((Get-Date) - $begin) | Out-Host

$report = @()
$activity = 'Finding orphaned VMDK files'
Write-Progress -Activity $activity -Status 'Gathering environment information' -CurrentOperation 'Getting list of all known VMDKs' -percentComplete 0
$arrUsedDisks = Get-View -ViewType VirtualMachine | ForEach-Object {$_.Layout} | ForEach-Object {$_.Disk} | ForEach-Object {$_.DiskFile}
#$arrDS = Get-Datastore | Sort-Object -property Name
Write-Progress -Activity $activity -Status "Searching datastores for VMDK files (0 of $($arrDS.Length))" -percentComplete 0
$begin2 = Get-Date
$i=0
foreach ($ds in $arrDS) {
	if ($i -eq 0) {
		Write-Progress -Activity $activity -Status "Searching datastores for VMDK files ($i of $($arrDS.Length))" -CurrentOperation $ds.Name -percentComplete 0
	} else {
		Write-Progress -Activity $activity -Status "Searching datastores for VMDK files ($i of $($arrDS.Length))" -CurrentOperation $ds.Name -percentComplete ($i*100/($arrDS.Length)) -SecondsRemaining (((Get-Date) - $begin).TotalSeconds / $i * ($arrDS.Length - $i))
	}
	#Write-Host $ds.Name
	#$ds_extdata = Get-Datastore -Name $ds.Name | ForEach-Object {Get-View $_.Id}
	$fileQueryFlags = New-Object VMware.Vim.FileQueryFlags
	$fileQueryFlags.FileSize = $true
	$fileQueryFlags.FileType = $true
	$fileQueryFlags.Modification = $true
	$searchSpec = New-Object VMware.Vim.HostDatastoreBrowserSearchSpec
	$searchSpec.details = $fileQueryFlags
	$searchSpec.matchPattern = '*.vmdk'
	$searchSpec.sortFoldersFirst = $true
	$dsBrowser = Get-View $ds.ExtensionData.browser
	$rootPath = '[' + $ds.ExtensionData.Name + ']'
	$searchResult = $dsBrowser.SearchDatastoreSubFolders($rootPath, $searchSpec)

	foreach ($folder in $searchResult)
	{
		foreach ($fileResult in $folder.File)
		{
			if ($fileResult.Path)
			{
                switch -regex ($fileResult.Path)
				{
					'.*-ctk\.vmdk$' { <# Remove Change Tracking Files #> }
					default {
						if (-not ($arrUsedDisks -contains ($folder.FolderPath.trim('/') + '/' + $fileResult.Path))){
							$row = '' | Select-Object DS, Path, File, Size, ModDate
							$row.DS = $ds.Name
							$row.Path = $folder.FolderPath
							$row.File = $fileResult.Path
							$row.Size = $fileResult.FileSize
							$row.ModDate = $fileResult.Modification
							$report += $row
						}
					}
				}
			}
		}
	}
	$i++
}
Write-Progress -Activity $activity -Status "Outputting results" -Completed
Write-Host "Results:"
$report
"VMDK scan time: {0:c}" -f ((Get-Date) - $begin2) | Out-Host
"Script execution time: {0:c}" -f ((Get-Date) - $begin) | Out-Host
