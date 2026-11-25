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
- `Cluster Quorum` section with quorum model, witness (disk, file share or cloud) and the assigned and current vote of every node; node votes are no longer listed in the cluster overview
- Health checks for a missing quorum witness (critical for two voting nodes), a witness that is not online and disabled dynamic quorum
- `Cluster Networks` section with role, state, subnets and live migration use of every cluster network, and the network interfaces of every node
- Health checks for cluster networks and interfaces that are not up and for clusters with fewer than two networks for cluster communication
- `Live Migration` section with the cluster settings (networks, parallel migrations, SMB bandwidth limit) and the Hyper-V live migration settings of every host, also for standalone hosts; new `InfoLevel.LiveMigration`
- Health checks for clusters that exclude every network from live migration, hosts with live migration disabled and live migration settings that differ between hosts
- `Cluster Roles` section with type, owner node, state, priority, preferred owners and failover settings of every clustered role
- `Cluster Shared Volumes` section with path, owner, state, I/O mode per node, capacity and free space
- `Cluster-Aware Updating` section with the self-updating role, its schedule and options and the last updating run
- `Hyper-V Hosts` section with the Hyper-V specific host settings that AsBuiltReport.Microsoft.Windows does not cover: hypervisor scheduler, virtualization-based security and running security services, Secure Boot, TPM, VM configuration versions, enhanced session mode, GPU partitioning, Discrete Device Assignment and virtual Fibre Channel SANs; new `InfoLevel.Host`
- Health checks for hosts with the classic hypervisor scheduler and SMT and for hosts with Secure Boot disabled
- Health checks for failed or partially online roles, Cluster Shared Volumes that are not online, use redirected I/O (ReFS is expected and ignored) or run out of free space, a missing or offline CAU self-updating role and a failed last CAU run
- Detection evidence for the Hyper-V role per host, physical disk resources, Cluster Shared Volumes, Scale-Out File Server roles and SMB shares that hold virtual hard disks
- Readable values for the cluster functional level and the auto balancer mode and level
- en-US and de-DE language files; fixed wording in the detection evidence is translated as well
- PowerShell 7 support on Windows (Windows PowerShell 5.1 remains supported); PSScriptAnalyzer checks the syntax for both versions
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
