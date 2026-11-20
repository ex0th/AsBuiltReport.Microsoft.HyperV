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
> Version 0.1.0 is an early development release and has not yet been validated against live clusters.

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

### PowerShell
<!-- ********** Add installation for any additional PowerShell module(s) ********** -->
```powershell
# Install
install-module AsBuiltReport.Microsoft.HyperV -Force

# Update
update-module AsBuiltReport.Microsoft.HyperV -Force
```

### GitHub
If you are unable to use the PowerShell Gallery, you can still install the module manually. Ensure you repeat the following steps for the [system requirements](https://github.com/AsBuiltReport/AsBuiltReport.Microsoft.HyperV#wrench-system-requirements) also.

1. Download the code package / [latest release](https://github.com/AsBuiltReport/AsBuiltReport.Microsoft.HyperV/releases/latest) zip from GitHub
2. Extract the zip file
3. Copy the folder `AsBuiltReport.Microsoft.HyperV` to a path that is set in `$env:PSModulePath`.
4. Open a PowerShell terminal window and unblock the downloaded files with
    ```powershell
    $path = (Get-Module -Name AsBuiltReport.Microsoft.HyperV -ListAvailable).ModuleBase; Unblock-File -Path $path\*.psd1; Unblock-File -Path $path\Src\Public\*.ps1; Unblock-File -Path $path\Src\Private\*.ps1
    ```
5. Close and reopen the PowerShell terminal window.

_Note: You are not limited to installing the module to those example paths, you can add a new entry to the environment variable PSModulePath if you want to use another path._

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
| Cluster.DynamicQuorum           | true / false | true    | Highlights clusters with dynamic quorum disabled                             | ![Warning](https://raw.githubusercontent.com/AsBuiltReport/.github/main/assets/highlight-swatches/FFF4C7.svg) Warning state |
| Cluster.NetworkState            | true / false | true    | Highlights cluster networks and interfaces that are down or failed (critical) or otherwise not up (warning) | ![Critical](https://raw.githubusercontent.com/AsBuiltReport/.github/main/assets/highlight-swatches/FEDDD7.svg) Critical state ![Warning](https://raw.githubusercontent.com/AsBuiltReport/.github/main/assets/highlight-swatches/FFF4C7.svg) Warning state |
| Cluster.NetworkRedundancy       | true / false | true    | Highlights clusters with fewer than two networks for cluster communication   | ![Warning](https://raw.githubusercontent.com/AsBuiltReport/.github/main/assets/highlight-swatches/FFF4C7.svg) Warning state |
| LiveMigration.MigrationNetwork  | true / false | true    | Highlights clusters that exclude every cluster network from live migration   | ![Critical](https://raw.githubusercontent.com/AsBuiltReport/.github/main/assets/highlight-swatches/FEDDD7.svg) Critical state |
| LiveMigration.HostMigrationEnabled | true / false | true | Highlights hosts with incoming and outgoing live migrations disabled         | ![Warning](https://raw.githubusercontent.com/AsBuiltReport/.github/main/assets/highlight-swatches/FFF4C7.svg) Warning state |
| LiveMigration.SettingsConsistency | true / false | true  | Highlights live migration settings that differ between hosts                 | ![Warning](https://raw.githubusercontent.com/AsBuiltReport/.github/main/assets/highlight-swatches/FFF4C7.svg) Warning state |

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

- All headings are numbered. Sections are never excluded from the table of contents.
- Every table has a caption in the format `Table <n> - <Section> - <Object>`, for example `Table 3 - Cluster Nodes - CLU01`.
- List tables contain a single object, because PScribo removes captions from list tables with more than one row.

## Roadmap

| Area | Planned content |
|---|---|
| Cluster | Cluster roles, Cluster-Aware Updating |
| Host | Hardware, OS build, Hyper-V host settings (paths, NUMA spanning, migration), physical NICs |
| Networking | Virtual switches including SET, host vNICs, RDMA, DCB/QoS (PFC, ETS) |
| Storage: S2D / Azure Local | Storage pool, physical disks and cache, virtual disks with resiliency and tiers, fault domains |
| Storage: 3-tier | iSCSI targets and sessions, Fibre Channel ports, MPIO policies, CSV and cluster disks |
| Storage: SMB | SMB shares used by Hyper-V, SMB Multichannel and SMB Direct |
| Consistency | Node-to-node comparison (patch level, virtual switches, networks) as health checks |
| Virtual machines | Optional VM inventory (InfoLevel 0 by default) |

