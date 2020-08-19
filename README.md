# vmware-scripts

## vsphere
All scripts for vSphere/ESXi

### powercli
All scripts here require PowerCLI

* build.ps1: Downloads the latest version of ESXi and builds an ISO and offline bundle.  Combines VIBs from v-front.de to add drivers to support the Gigabyte BRiX.  Edit $versionFilter to retrieve a specific version.  Edit $nminus to download a version older than latest.

* VMDK-orphaned-v2.ps1: Searches all datastores for orphaned VMDK files, which can happen during SDRS actions.