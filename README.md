<!-- ********** DO NOT EDIT THESE LINKS ********** -->
<p align="center">
    <a href="https://www.asbuiltreport.com/">
        <img src="https://raw.githubusercontent.com/AsBuiltReport/.github/main/assets/repo-banners/AsBuiltReport.Microsoft.HyperV.png" alt="AsBuiltReport.Microsoft.HyperV" width="880"></a>
</p>
<p align="center">
    <a href="https://www.powershellgallery.com/packages/AsBuiltReport.Microsoft.HyperV/" alt="PowerShell Gallery Version">
        <img src="https://img.shields.io/powershellgallery/v/AsBuiltReport.Microsoft.HyperV.svg?color=1F5FD0" /></a>
    <a href="https://www.powershellgallery.com/packages/AsBuiltReport.Microsoft.HyperV/" alt="PS Gallery Downloads">
        <img src="https://img.shields.io/powershellgallery/dt/AsBuiltReport.Microsoft.HyperV.svg?color=012456" /></a>
    <a href="https://www.powershellgallery.com/packages/AsBuiltReport.Microsoft.HyperV/" alt="PS Platform">
        <img src="https://img.shields.io/powershellgallery/p/AsBuiltReport.Microsoft.HyperV.svg?color=FFD02B" /></a>
</p>
<p align="center">
    <a href="https://github.com/AsBuiltReport/AsBuiltReport.Microsoft.HyperV/graphs/commit-activity" alt="GitHub Last Commit">
        <img src="https://img.shields.io/github/last-commit/AsBuiltReport/AsBuiltReport.Microsoft.HyperV/master.svg" /></a>
    <a href="https://raw.githubusercontent.com/AsBuiltReport/AsBuiltReport.Microsoft.HyperV/master/LICENSE" alt="GitHub License">
        <img src="https://img.shields.io/github/license/AsBuiltReport/AsBuiltReport.Microsoft.HyperV.svg" /></a>
    <a href="https://github.com/AsBuiltReport/AsBuiltReport.Microsoft.HyperV/graphs/contributors" alt="GitHub Contributors">
        <img src="https://img.shields.io/github/contributors/AsBuiltReport/AsBuiltReport.Microsoft.HyperV.svg?color=012456"/></a>
</p>

<p align="center">
    <a href='https://ko-fi.com/B0B7DDGZ7' target='_blank'><img height='36' style='border:0px;height:36px;' src='https://ko-fi.com/img/githubbutton_sm.svg' border='0' alt='Want to keep alive this project? Support me on Ko-fi' /></a>
</p>
<!-- ********** DO NOT EDIT THESE LINKS ********** -->

<!-- ********** REMOVE THIS MESSAGE WHEN THE MODULE IS FUNCTIONAL ********** -->
## <img src="https://raw.githubusercontent.com/AsBuiltReport/.github/main/assets/section-icons/in-development.svg" alt="" width="24" height="24" align="top"> THIS ASBUILTREPORT MODULE IS CURRENTLY IN DEVELOPMENT AND MIGHT NOT YET BE FUNCTIONAL

Microsoft Hyper-V As Built Report is a PowerShell module which works in conjunction with [AsBuiltReport.Core](https://github.com/AsBuiltReport/AsBuiltReport.Core).

[AsBuiltReport](https://github.com/AsBuiltReport/AsBuiltReport) is an open-sourced community project which utilises PowerShell to produce as-built documentation in multiple document formats for multiple vendors and technologies.

Please refer to the AsBuiltReport [website](https://www.asbuiltreport.com) for more detailed information about this project.

The report documents Hyper-V **per cluster instead of per server**. A target can be a failover cluster name, any cluster node or a standalone Hyper-V host. Cluster nodes are discovered automatically, and the report detects the environment type to decide which storage and networking sections are relevant:

| Environment type | Detected from |
|---|---|
| Standalone Hyper-V host | Host is not a cluster member |
| Failover cluster with shared block storage (3-tier) | Clustered disks on iSCSI, Fibre Channel or shared SAS, clustered storage pool without S2D |
| Failover cluster with Storage Spaces Direct | `S2DEnabled` on the cluster |
| Azure Local cluster | S2D cluster whose nodes run the Azure Local (Azure Stack HCI) edition |
| Failover cluster with SMB storage | Virtual hard disks or the default VHD path on an SMB 3 share |
| Mixed | More than one of the storage classes above |

The detection can be overridden in the report configuration (`Options.StorageTopology`). With `InfoLevel.Environment` set to 2, the report lists every check that led to the result.

This module is **read-only**. It only runs `Get-*` cmdlets on the documented hosts.

# <img src="https://raw.githubusercontent.com/AsBuiltReport/.github/main/assets/section-icons/getting-started.svg" alt="" width="28" height="28" align="top"> Getting Started
Below are the instructions on how to install, configure and generate a Microsoft Hyper-V As Built report.

## <img src="https://raw.githubusercontent.com/AsBuiltReport/.github/main/assets/section-icons/supported-versions.svg" alt="" width="24" height="24" align="top"> Supported Versions
<!-- ********** Update supported HyperV versions ********** -->
The Microsoft Hyper-V As Built Report supports the following versions;

- Windows Server 2016, 2019, 2022 and 2025 with the Hyper-V role (standalone and failover cluster)
- Azure Local (formerly Azure Stack HCI)

> [!NOTE]
> Version 0.2.0 is an early development release and has only been tested against a few clusters.

### PowerShell
This report is compatible with the following PowerShell versions;

<!-- ********** Update supported PowerShell versions ********** -->
| Windows PowerShell 5.1 |    PowerShell 7    |
|:----------------------:|:------------------:|
|   :white_check_mark:   | :white_check_mark: |

PowerShell 7 is supported on Windows only. The data on the documented hosts is always collected by the Windows PowerShell 5.1 WinRM endpoint of each host, so the in-box `Hyper-V` and `FailoverClusters` modules are used there in either case.

## <img src="https://raw.githubusercontent.com/AsBuiltReport/.github/main/assets/section-icons/language-support.svg" alt="" width="24" height="24" align="top"> Language Support
<!-- ********** Update supported languages ********** -->
The Microsoft Hyper-V As Built Report supports the following languages;

- English (US) (Default)
- German (Germany)

The language is selected with `Report.Language` in the report configuration (`en-US` or `de-DE`).

## <img src="https://raw.githubusercontent.com/AsBuiltReport/.github/main/assets/section-icons/system-requirements.svg" alt="" width="24" height="24" align="top"> System Requirements
<!-- ********** Update system requirements ********** -->
Windows PowerShell 5.1 or PowerShell 7 on Windows and the following PowerShell modules are required for generating a Microsoft Hyper-V As Built Report.

- [AsBuiltReport.Core Module](https://www.powershellgallery.com/packages/AsBuiltReport.Core/)
- [AsBuiltReport.Microsoft.HyperV Module](https://www.powershellgallery.com/packages/AsBuiltReport.Microsoft.HyperV/)

No additional modules are needed on the reporting machine. All data is collected through WinRM with the in-box modules on the documented hosts (`Hyper-V`, `FailoverClusters`, `Storage`, `NetAdapter`, `MPIO`, `iSCSI`).

### WinRM
- Use the **FQDN** of the cluster or host as target. IP addresses are rejected because Kerberos needs a DNS name, and node FQDNs are built from the cluster DNS domain.
- The report opens a session to the target and one session to every cluster node (no CredSSP, no double hop).
- Authentication, SSL and port are configurable under `Options`.

### <img src="https://raw.githubusercontent.com/AsBuiltReport/.github/main/assets/section-icons/required-privileges.svg" alt="" width="20" height="20" align="top"> Required Privileges
A member of the local Administrators group on every documented host. Several Hyper-V, Failover Clustering and Storage cmdlets do not return complete data with fewer rights. For failover clusters the account also needs read access to the cluster (Full Access is not required for `Get-*` cmdlets).

## <img src="https://raw.githubusercontent.com/AsBuiltReport/.github/main/assets/section-icons/module-installation.svg" alt="" width="24" height="24" align="top"> Module Installation

> [!NOTE]
> The module is not yet published to the PowerShell Gallery. Until then, install it from GitHub as described below.

### Quick Start (GitHub)
Run the following on the machine that generates the report (not on the Hyper-V hosts), in Windows PowerShell 5.1 or PowerShell 7. Nothing is installed on the documented hosts.

**1. Install AsBuiltReport.Core** from the PowerShell Gallery:
```powershell
Install-Module -Name AsBuiltReport.Core -Scope CurrentUser
```

**2. Download the module and copy it to your user module folder:**
```powershell
# Windows PowerShell 5.1 on older systems may need TLS 1.2 for GitHub
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$Zip = Join-Path $env:TEMP 'AsBuiltReport.Microsoft.HyperV.zip'
$Extract = Join-Path $env:TEMP 'AsBuiltReport.Microsoft.HyperV'
Invoke-WebRequest -Uri 'https://github.com/ex0th/AsBuiltReport.Microsoft.HyperV/archive/refs/heads/master.zip' -OutFile $Zip
Expand-Archive -Path $Zip -DestinationPath $Extract -Force

# Windows PowerShell 5.1 and PowerShell 7 use different user module folders
if ($PSVersionTable.PSEdition -eq 'Core') { $Edition = 'PowerShell' } else { $Edition = 'WindowsPowerShell' }
$ModuleRoot = Join-Path ([Environment]::GetFolderPath('MyDocuments')) "$Edition\Modules"
$Destination = Join-Path $ModuleRoot 'AsBuiltReport.Microsoft.HyperV'

if (Test-Path $Destination) { Remove-Item -Path $Destination -Recurse -Force }   # replaces an older copy
New-Item -ItemType Directory -Path $ModuleRoot -Force | Out-Null
Copy-Item -Path (Join-Path $Extract 'AsBuiltReport.Microsoft.HyperV-master\AsBuiltReport.Microsoft.HyperV') -Destination $Destination -Recurse
Get-ChildItem -Path $Destination -Recurse -File | Unblock-File
```
To use the module in both Windows PowerShell 5.1 and PowerShell 7, run step 2 in both shells.

**3. Check the installation** (open a new PowerShell window first):
```powershell
Get-Module -Name AsBuiltReport.Microsoft.HyperV -ListAvailable
```

**4. Create a report configuration and generate the first report:**
```powershell
New-AsBuiltReportConfig -Report Microsoft.HyperV -FolderPath 'C:\Reports' -Filename 'HyperV'
New-AsBuiltReport -Report Microsoft.HyperV -Target 'cluster01.example.com' -Credential (Get-Credential) `
    -ReportConfigFilePath 'C:\Reports\HyperV.json' -Format Html -OutputFolderPath 'C:\Reports' -EnableHealthCheck
```
On the first run, `New-AsBuiltReport` asks for the general AsBuiltReport settings (company name, mail settings and so on). The sections Configuration and Examples below describe the report options and more commands.

**Update:** repeat step 2. It replaces the existing copy. Create a new report configuration afterwards so that new settings are included.

**Uninstall:** delete the `AsBuiltReport.Microsoft.HyperV` folder from the module folder used in step 2.

### Manual Installation
If the reporting machine has no internet access:

1. Download the [code package](https://github.com/ex0th/AsBuiltReport.Microsoft.HyperV/archive/refs/heads/master.zip) on another machine and install `AsBuiltReport.Core` there with `Save-Module -Name AsBuiltReport.Core -Path <folder>` (this also saves its dependencies).
2. Copy the folders to the reporting machine and extract the zip file.
3. Copy the folder `AsBuiltReport.Microsoft.HyperV` (the inner one, containing the `.psd1` file) and the saved modules to a path listed in `$env:PSModulePath`, for example `Documents\WindowsPowerShell\Modules`. The folder name must stay `AsBuiltReport.Microsoft.HyperV`.
4. Unblock the downloaded files:
    ```powershell
    Get-ChildItem -Path "$([Environment]::GetFolderPath('MyDocuments'))\WindowsPowerShell\Modules" -Recurse -File | Unblock-File
    ```
5. Close and reopen the PowerShell window and continue with step 3 of the Quick Start.

### PowerShell Gallery
Once the module is published:
```powershell
# Install
Install-Module -Name AsBuiltReport.Microsoft.HyperV -Scope CurrentUser

# Update
Update-Module -Name AsBuiltReport.Microsoft.HyperV
```

## <img src="https://raw.githubusercontent.com/AsBuiltReport/.github/main/assets/section-icons/configuration.svg" alt="" width="24" height="24" align="top"> Configuration

The Microsoft Hyper-V As Built Report utilises a JSON file to allow configuration of report information, options, detail and healthchecks.

> [!IMPORTANT]
> Please remember to generate a new report JSON configuration file after each module update to ensure the report functions correctly.

A Microsoft Hyper-V report configuration file can be generated by executing the following command;
```powershell
New-AsBuiltReportConfig -Report Microsoft.HyperV -FolderPath <User specified folder> -Filename <Optional>
```

Executing this command will copy the default Microsoft Hyper-V report JSON configuration to a user specified folder.

All report settings can then be configured via the JSON file.

The following provides information of how to configure each schema within the report's JSON file.

<!-- ********** DO NOT CHANGE THE REPORT SCHEMA SETTINGS ********** -->
### Report
The **Report** schema provides configuration of the Microsoft Hyper-V report information.

| Sub-Schema          | Setting      | Default                                                                            | Description                                                                                     |
|---------------------|--------------|------------------------------------------------------------------------------------|-------------------------------------------------------------------------------------------------|
| Name                | User defined | Microsoft Hyper-V As Built Report | The name of the As Built Report                                                                 |
| Version             | User defined | 1.0                                                                                | The report version                                                                              |
| Status              | User defined | Released                                                                           | The report release status                                                                       |
| Language            | User defined | en-US                                                                              | The default report language. This can be customised if the report module provides multilingual support |
| ShowCoverPageImage  | true / false | true                                                                               | Toggle to enable/disable the display of the cover page image                                    |
| ShowTableOfContents | true / false | true                                                                               | Toggle to enable/disable table of contents                                                      |
| ShowHeaderFooter    | true / false | true                                                                               | Toggle to enable/disable document headers & footers                                             |
| ShowTableCaptions   | true / false | true                                                                               | Toggle to enable/disable table captions/numbering                                               |

### Options
The **Options** schema allows certain options within the report to be toggled on or off.

| Sub-Schema          | Setting                                                   | Default   | Description |
|---------------------|-----------------------------------------------------------|-----------|-------------|
| WinRMAuthentication | Default / Kerberos / Negotiate                            | Negotiate | Authentication used for all WinRM sessions |
| WinRMUseSSL         | true / false                                              | false     | Use WinRM over HTTPS |
| WinRMPort           | 0 / port number                                           | 0         | WinRM port, 0 uses the default port |
| StorageTopology     | Auto / S2D / iSCSI / FibreChannel / SharedSAS / SMB / Local | Auto    | Overrides the detected storage topology. Several values can be combined. |

<!-- ********** Add/Remove the number of InfoLevels as required ********** -->
### InfoLevel
The **InfoLevel** schema allows configuration of each section of the report at a granular level. The following sections can be set.

There are 6 levels (0-5) of detail granularity for each section as follows;

| Setting | InfoLevel         | Description                                                                                         |
|:-------:|-------------------|-----------------------------------------------------------------------------------------------------|
|    0    | Disabled          | Does not collect or display any information                                                         |
|    1    | Enabled / Summary | Provides summarised information for a collection of objects                                         |
|    2    | Adv Summary       | Provides condensed, detailed information for a collection of objects                                |
|    3    | Detailed          | Provides detailed information for individual objects                                                |
|    4    | Adv Detailed      | Provides detailed information for individual objects, as well as information for associated objects |
|    5    | Comprehensive     | Provides comprehensive information for individual objects, such as advanced configuration settings  |

The table below outlines the default and maximum InfoLevel settings for each section.

| Sub-Schema    | Default Setting | Maximum Setting |
|---------------|:---------------:|:---------------:|
| Environment   |        1        |        2        |
| Cluster       |        1        |        2        |
| LiveMigration |        1        |        2        |
| Host          |        1        |        2        |
| Networking    |        1        |        2        |
| StorageS2D    |        1        |        2        |
| Storage3Tier  |        1        |        2        |
| Consistency   |        1        |        2        |
| VirtualMachines |      0        |        2        |

### Healthcheck
The **Healthcheck** schema is used to toggle health checks on or off.

| Sub-Schema                      | Setting      | Default | Description                                                                  | Highlight                                                                                                   |
|---------------------------------|--------------|---------|------------------------------------------------------------------------------|-------------------------------------------------------------------------------------------------------------|
| Environment.NodeReachability    | true / false | true    | Highlights clusters where not every node could be reached                    | ![Critical](https://raw.githubusercontent.com/AsBuiltReport/.github/main/assets/highlight-swatches/FEDDD7.svg) Critical state |
| Environment.HyperVRole          | true / false | true    | Highlights hosts on which the Hyper-V role is not installed                  | ![Critical](https://raw.githubusercontent.com/AsBuiltReport/.github/main/assets/highlight-swatches/FEDDD7.svg) Critical state |
| Cluster.NodeState               | true / false | true    | Highlights nodes that are down (critical) or paused/joining (warning)        | ![Critical](https://raw.githubusercontent.com/AsBuiltReport/.github/main/assets/highlight-swatches/FEDDD7.svg) Critical state ![Warning](https://raw.githubusercontent.com/AsBuiltReport/.github/main/assets/highlight-swatches/FFF4C7.svg) Warning state |
| Cluster.NodeOSBuildConsistency  | true / false | true    | Highlights nodes whose OS build (incl. UBR) differs from the majority build  | ![Warning](https://raw.githubusercontent.com/AsBuiltReport/.github/main/assets/highlight-swatches/FFF4C7.svg) Warning state |
| Cluster.QuorumWitness           | true / false | true    | Highlights clusters without a quorum witness (critical for two voting nodes) | ![Critical](https://raw.githubusercontent.com/AsBuiltReport/.github/main/assets/highlight-swatches/FEDDD7.svg) Critical state ![Warning](https://raw.githubusercontent.com/AsBuiltReport/.github/main/assets/highlight-swatches/FFF4C7.svg) Warning state |
| Cluster.QuorumWitnessState      | true / false | true    | Highlights a witness resource that is not online                             | ![Critical](https://raw.githubusercontent.com/AsBuiltReport/.github/main/assets/highlight-swatches/FEDDD7.svg) Critical state |
| Cluster.QuorumWitnessLocation   | true / false | true    | Highlights a file share witness that is hosted by a virtual machine of the same cluster | ![Critical](https://raw.githubusercontent.com/AsBuiltReport/.github/main/assets/highlight-swatches/FEDDD7.svg) Critical state |
| Cluster.DynamicQuorum           | true / false | true    | Highlights clusters with dynamic quorum disabled                             | ![Warning](https://raw.githubusercontent.com/AsBuiltReport/.github/main/assets/highlight-swatches/FFF4C7.svg) Warning state |
| Cluster.NetworkState            | true / false | true    | Highlights cluster networks and interfaces that are down or failed (critical) or otherwise not up (warning) | ![Critical](https://raw.githubusercontent.com/AsBuiltReport/.github/main/assets/highlight-swatches/FEDDD7.svg) Critical state ![Warning](https://raw.githubusercontent.com/AsBuiltReport/.github/main/assets/highlight-swatches/FFF4C7.svg) Warning state |
| Cluster.NetworkRedundancy       | true / false | true    | Highlights clusters with fewer than two networks for cluster communication   | ![Warning](https://raw.githubusercontent.com/AsBuiltReport/.github/main/assets/highlight-swatches/FFF4C7.svg) Warning state |
| Cluster.RoleState               | true / false | true    | Highlights roles that failed (critical) or are partially online or pending (warning) | ![Critical](https://raw.githubusercontent.com/AsBuiltReport/.github/main/assets/highlight-swatches/FEDDD7.svg) Critical state ![Warning](https://raw.githubusercontent.com/AsBuiltReport/.github/main/assets/highlight-swatches/FFF4C7.svg) Warning state |
| Cluster.RoleDistribution        | true / false | true    | Highlights nodes that are up but own no roles while another node runs them (paused nodes are ignored); notes when all Cluster Shared Volumes have the same owner | ![Warning](https://raw.githubusercontent.com/AsBuiltReport/.github/main/assets/highlight-swatches/FFF4C7.svg) Warning state |
| Cluster.CsvState                | true / false | true    | Highlights Cluster Shared Volumes that are failed or offline (critical) or in maintenance mode (warning) | ![Critical](https://raw.githubusercontent.com/AsBuiltReport/.github/main/assets/highlight-swatches/FEDDD7.svg) Critical state ![Warning](https://raw.githubusercontent.com/AsBuiltReport/.github/main/assets/highlight-swatches/FFF4C7.svg) Warning state |
| Cluster.CsvRedirectedAccess     | true / false | true    | Highlights Cluster Shared Volumes with redirected I/O for a reason other than ReFS | ![Warning](https://raw.githubusercontent.com/AsBuiltReport/.github/main/assets/highlight-swatches/FFF4C7.svg) Warning state |
| Cluster.CsvFreeSpace            | true / false | true    | Highlights Cluster Shared Volumes with less than 20 % (warning) or 10 % (critical) free space | ![Critical](https://raw.githubusercontent.com/AsBuiltReport/.github/main/assets/highlight-swatches/FEDDD7.svg) Critical state ![Warning](https://raw.githubusercontent.com/AsBuiltReport/.github/main/assets/highlight-swatches/FFF4C7.svg) Warning state |
| Cluster.CauSelfUpdating         | true / false | true    | Highlights clusters without a Cluster-Aware Updating self-updating role or with the role offline | ![Warning](https://raw.githubusercontent.com/AsBuiltReport/.github/main/assets/highlight-swatches/FFF4C7.svg) Warning state |
| Cluster.CauLastRun              | true / false | true    | Highlights a last Cluster-Aware Updating run that did not succeed           | ![Warning](https://raw.githubusercontent.com/AsBuiltReport/.github/main/assets/highlight-swatches/FFF4C7.svg) Warning state |
| LiveMigration.MigrationNetwork  | true / false | true    | Highlights clusters that exclude every cluster network from live migration   | ![Critical](https://raw.githubusercontent.com/AsBuiltReport/.github/main/assets/highlight-swatches/FEDDD7.svg) Critical state |
| LiveMigration.HostMigrationEnabled | true / false | true | Highlights hosts with incoming and outgoing live migrations disabled         | ![Warning](https://raw.githubusercontent.com/AsBuiltReport/.github/main/assets/highlight-swatches/FFF4C7.svg) Warning state |
| LiveMigration.SettingsConsistency | true / false | true  | Highlights live migration settings that differ between hosts                 | ![Warning](https://raw.githubusercontent.com/AsBuiltReport/.github/main/assets/highlight-swatches/FFF4C7.svg) Warning state |
| LiveMigration.CredSSP           | true / false | true    | Highlights hosts that use CredSSP for live migration authentication           | ![Warning](https://raw.githubusercontent.com/AsBuiltReport/.github/main/assets/highlight-swatches/FFF4C7.svg) Warning state |
| Host.SchedulerType              | true / false | true    | Highlights hosts that use the classic hypervisor scheduler with SMT enabled  | ![Warning](https://raw.githubusercontent.com/AsBuiltReport/.github/main/assets/highlight-swatches/FFF4C7.svg) Warning state |
| Host.SecureBoot                 | true / false | true    | Highlights hosts with Secure Boot disabled                                   | ![Warning](https://raw.githubusercontent.com/AsBuiltReport/.github/main/assets/highlight-swatches/FFF4C7.svg) Warning state |
| Networking.SetLoadBalancing     | true / false | true    | Highlights SET switches that do not use Hyper-V port load balancing          | ![Warning](https://raw.githubusercontent.com/AsBuiltReport/.github/main/assets/highlight-swatches/FFF4C7.svg) Warning state |
| Networking.SetMemberState       | true / false | true    | Highlights members of SET switches that are not up (team without redundancy) | ![Warning](https://raw.githubusercontent.com/AsBuiltReport/.github/main/assets/highlight-swatches/FFF4C7.svg) Warning state |
| Networking.SetMemberLinkSpeed   | true / false | true    | Highlights SET switches whose members have different link speeds              | ![Warning](https://raw.githubusercontent.com/AsBuiltReport/.github/main/assets/highlight-swatches/FFF4C7.svg) Warning state |
| Networking.RdmaState            | true / false | true    | Highlights S2D hosts that use no RDMA on any storage path, and the RDMA capable adapters with RDMA disabled on their storage networks; management networks (Cluster and client) are never rated. Notes live migration over SMB without RDMA | ![Warning](https://raw.githubusercontent.com/AsBuiltReport/.github/main/assets/highlight-swatches/FFF4C7.svg) Warning state |
| Networking.RocePfc              | true / false | true    | Highlights RoCE adapters without priority flow control or with DCB disabled  | ![Warning](https://raw.githubusercontent.com/AsBuiltReport/.github/main/assets/highlight-swatches/FFF4C7.svg) Warning state |
| Networking.DcbxWilling          | true / false | true    | Highlights hosts with PFC that accept DCB settings from the switch (DCBX willing) | ![Warning](https://raw.githubusercontent.com/AsBuiltReport/.github/main/assets/highlight-swatches/FFF4C7.svg) Warning state |
| Networking.DcbTrafficClass      | true / false | true    | Highlights hosts with PFC and an SMB or cluster QoS policy but no ETS traffic class for that priority | ![Warning](https://raw.githubusercontent.com/AsBuiltReport/.github/main/assets/highlight-swatches/FFF4C7.svg) Warning state |
| Networking.VnicTeamMapping      | true / false | true    | Highlights RDMA host vNICs on multi-member SET switches without team mapping | ![Warning](https://raw.githubusercontent.com/AsBuiltReport/.github/main/assets/highlight-swatches/FFF4C7.svg) Warning state |
| StorageS2D.PoolHealth           | true / false | true    | Highlights storage pools that are not healthy                                | ![Critical](https://raw.githubusercontent.com/AsBuiltReport/.github/main/assets/highlight-swatches/FEDDD7.svg) Critical state ![Warning](https://raw.githubusercontent.com/AsBuiltReport/.github/main/assets/highlight-swatches/FFF4C7.svg) Warning state |
| StorageS2D.ReserveCapacity      | true / false | true    | Highlights pools with less unallocated capacity than one capacity drive per node (up to four) | ![Warning](https://raw.githubusercontent.com/AsBuiltReport/.github/main/assets/highlight-swatches/FFF4C7.svg) Warning state |
| StorageS2D.PhysicalDiskHealth   | true / false | true    | Highlights physical disks that are not healthy or retired                    | ![Warning](https://raw.githubusercontent.com/AsBuiltReport/.github/main/assets/highlight-swatches/FFF4C7.svg) Warning state |
| StorageS2D.VirtualDiskHealth    | true / false | true    | Highlights virtual disks that are not healthy                                | ![Critical](https://raw.githubusercontent.com/AsBuiltReport/.github/main/assets/highlight-swatches/FEDDD7.svg) Critical state ![Warning](https://raw.githubusercontent.com/AsBuiltReport/.github/main/assets/highlight-swatches/FFF4C7.svg) Warning state |
| StorageS2D.StorageJobs          | true / false | true    | Highlights running storage jobs (repair, rebalance)                          | ![Warning](https://raw.githubusercontent.com/AsBuiltReport/.github/main/assets/highlight-swatches/FFF4C7.svg) Warning state |
| StorageS2D.HealthFaults         | true / false | true    | Highlights current faults of the cluster Health Service                      | ![Critical](https://raw.githubusercontent.com/AsBuiltReport/.github/main/assets/highlight-swatches/FEDDD7.svg) Critical state ![Warning](https://raw.githubusercontent.com/AsBuiltReport/.github/main/assets/highlight-swatches/FFF4C7.svg) Warning state |
| Storage3Tier.PathRedundancy     | true / false | true    | Highlights shared disks with fewer than two paths and hosts with shared disks but without Multipath I/O | ![Warning](https://raw.githubusercontent.com/AsBuiltReport/.github/main/assets/highlight-swatches/FFF4C7.svg) Warning state |
| Storage3Tier.IscsiSession       | true / false | true    | Highlights iSCSI sessions that are not connected (critical) or not persistent (warning) | ![Critical](https://raw.githubusercontent.com/AsBuiltReport/.github/main/assets/highlight-swatches/FEDDD7.svg) Critical state ![Warning](https://raw.githubusercontent.com/AsBuiltReport/.github/main/assets/highlight-swatches/FFF4C7.svg) Warning state |
| Storage3Tier.ClusterDiskState   | true / false | true    | Highlights cluster disks that failed (critical) or are not online (warning)  | ![Critical](https://raw.githubusercontent.com/AsBuiltReport/.github/main/assets/highlight-swatches/FEDDD7.svg) Critical state ![Warning](https://raw.githubusercontent.com/AsBuiltReport/.github/main/assets/highlight-swatches/FFF4C7.svg) Warning state |
| Consistency.OperatingSystem     | true / false | true    | Highlights nodes whose edition, build or installation type differs           | ![Warning](https://raw.githubusercontent.com/AsBuiltReport/.github/main/assets/highlight-swatches/FFF4C7.svg) Warning state |
| Consistency.Hotfix              | true / false | true    | Highlights nodes on which hotfixes of the other nodes are missing            | ![Warning](https://raw.githubusercontent.com/AsBuiltReport/.github/main/assets/highlight-swatches/FFF4C7.svg) Warning state |
| Consistency.Hardware            | true / false | true    | Highlights nodes whose manufacturer, model, BIOS, processor or memory differs | ![Warning](https://raw.githubusercontent.com/AsBuiltReport/.github/main/assets/highlight-swatches/FFF4C7.svg) Warning state |
| Consistency.HyperVSettings      | true / false | true    | Highlights nodes whose default paths, NUMA spanning, enhanced session mode or default VM version differs | ![Warning](https://raw.githubusercontent.com/AsBuiltReport/.github/main/assets/highlight-swatches/FFF4C7.svg) Warning state |
| Consistency.Network             | true / false | true    | Highlights nodes whose virtual switches, host vNICs, NIC drivers, jumbo frames, RDMA or DCB differ | ![Warning](https://raw.githubusercontent.com/AsBuiltReport/.github/main/assets/highlight-swatches/FFF4C7.svg) Warning state |
| Consistency.Storage             | true / false | true    | Highlights nodes whose MPIO settings, disk firmware or iSCSI targets differ  | ![Warning](https://raw.githubusercontent.com/AsBuiltReport/.github/main/assets/highlight-swatches/FFF4C7.svg) Warning state |
| Consistency.Features            | true / false | true    | Highlights nodes on which roles or features of the other nodes are missing   | ![Warning](https://raw.githubusercontent.com/AsBuiltReport/.github/main/assets/highlight-swatches/FFF4C7.svg) Warning state |
| VirtualMachines.Checkpoints     | true / false | true    | Highlights virtual machines with checkpoints                                 | ![Warning](https://raw.githubusercontent.com/AsBuiltReport/.github/main/assets/highlight-swatches/FFF4C7.svg) Warning state |
| VirtualMachines.NotClustered    | true / false | true    | Highlights virtual machines on cluster nodes that are not clustered roles    | ![Warning](https://raw.githubusercontent.com/AsBuiltReport/.github/main/assets/highlight-swatches/FFF4C7.svg) Warning state |
| VirtualMachines.ConfigurationVersion | true / false | true | Highlights virtual machines with a configuration version below the host default | ![Warning](https://raw.githubusercontent.com/AsBuiltReport/.github/main/assets/highlight-swatches/FFF4C7.svg) Warning state |
| VirtualMachines.NetworkDisconnected | true / false | true | Highlights virtual machines with network adapters that are not connected to a switch | ![Warning](https://raw.githubusercontent.com/AsBuiltReport/.github/main/assets/highlight-swatches/FFF4C7.svg) Warning state |

## <img src="https://raw.githubusercontent.com/AsBuiltReport/.github/main/assets/section-icons/examples.svg" alt="" width="24" height="24" align="top"> Examples
<!-- ********** Add some examples. Use other AsBuiltReport modules as a guide. ********** -->

```powershell
# Document a failover cluster (nodes are discovered automatically) as HTML and Word
PS C:\> $Credential = Get-Credential
PS C:\> New-AsBuiltReport -Report Microsoft.HyperV -Target 'cluster01.example.com' -Credential $Credential -Format Html,Word -OutputFolderPath 'C:\Reports' -EnableHealthCheck

# Document a standalone Hyper-V host and a cluster in one report
PS C:\> New-AsBuiltReport -Report Microsoft.HyperV -Target 'hv01.example.com','cluster01.example.com' -Credential $Credential -Format Html -OutputFolderPath 'C:\Reports'
```

## Report Structure

The report follows the PScribo conventions used across AsBuiltReport modules, so exported documents can be processed by other tools:

- With `-EnableHealthCheck`, the last section of every cluster or host is the `Health Check Summary` with one row per finding and the columns `Area`, `Severity`, `Finding` and `Recommendation` (translated in other report languages). The sections contain the same findings below the tables they highlight.
- Tables that describe hosts have a `Host` or `Node` column with the node names as listed in `Cluster Nodes`.

- All headings are numbered. Sections are never excluded from the table of contents.
- Every table has a caption in the format `Table <n> - <Section> - <Object>`, for example `Table 3 - Cluster Nodes - CLU01`.
- List tables contain a single object, because PScribo removes captions from list tables with more than one row.

## Roadmap

| Area | Planned content |
|---|---|
| Storage: SMB | SMB shares used by Hyper-V, SMB Multichannel and SMB Direct |

