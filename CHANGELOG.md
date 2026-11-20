# :arrows_clockwise: Microsoft Hyper-V As Built Report Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

##### This project is community maintained and has no sponsorship from Microsoft, its employees or any of its affiliates.

## [0.1.0] - Unreleased

### Added

- Initial module scaffold from the AsBuiltReport Plaster template (Windows PowerShell 5.1)
- Target discovery: failover cluster name, cluster node or standalone host (FQDN); cluster nodes are discovered automatically and each cluster is documented once
- Read-only WinRM data collection with one session per node; configurable authentication, SSL and port
- Environment type detection (standalone, 3-tier shared block storage, Storage Spaces Direct, Azure Local, SMB, mixed) with optional manual override
- `Environment Type` section with detection evidence (InfoLevel 2)
- `Cluster Overview` section with cluster configuration and node summary including OS build per node
- Health checks for node reachability, Hyper-V role, node state and OS build consistency between nodes
- Detection evidence for the Hyper-V role per host, physical disk resources, Cluster Shared Volumes, Scale-Out File Server roles and SMB shares that hold virtual hard disks
- Readable values for the cluster functional level and the auto balancer mode and level
- en-US language file
- Pester tests for the environment classification, report configuration, report conventions and localization data

### Fixed

- Fibre Channel disks and initiator ports were not detected because the Storage module reports `FibreChannel`, not `Fibre Channel`
- Clustered Storage Spaces volumes (bus type `Spaces`) are now counted as S2D or shared SAS evidence
- Node names are spelled the same way in all sections (taken from the cluster)
- Empty fault domain levels (e.g. `Rack:`) are no longer shown
- The OS build of each node is collected once during discovery instead of a second time for the cluster overview
- `Invoke-Tests.ps1` now fails when a test file fails during discovery, and pins Pester to 5.x
- The Pester workflow uses Pester 5.x and AsBuiltReport.Core 1.6.4 and runs on Windows only
- The Pester workflow file was rejected by GitHub because step-level `shell` does not accept matrix expressions; the shell is now set in the job defaults
