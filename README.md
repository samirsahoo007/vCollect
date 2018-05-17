# vCollect
Contact: samir.sahoo007@gmail.com

vCollect gathers various information from your vCenter environment. It uses this information to generate a xml report. To view the report in html format you can upload this xml report to the SORT website, where you can view, analyze or share them with others.

Information gathered by vCollect

The tool collects and reports the following details. The data is stored both in text and xml format.

    Number of
        vSphere HA Clusters
        Total available storage
        ESXi Hosts
        Total allocated storage
        Virtual Machines (both total and protected)
        Total used storage
        Datastores (both total and protected)
        Total replicated storage
        LUNs (both total and replicated)
        External storage systems
    Server model technologies and storage types
        Server models: HP Proliant (60), Cisco UCS C250 (21), IBM x3750 M4 (15)
        Storage Types: NAS (10%), SAN . FC (80%), DAS (10%)
    VM Operating Systems and their count (e.g Windows (201), Linux (398), Solaris (94) )
    vCenter freatures in use (e.g vSphere HA, DRS, VM Monitoring, VMware APP HA, FT, SRM)
    No of vApps identified and their name along with no of virtual machines using them
    Application services discovered on VMs (e.g smtpd(5), NTP Daemon(3), CIM server (9))
    Average number of VMs per
        ESXi Host
        CPU
    Replication technology and their discovery source
    Virtual Applications
        total no of virtual applications (vApps)
        group type (e.g vApp)
        group name (e.g Sharepoint PROD, Microsoft System Center)
        no of VMs using the vApp
        Discovery Source
    In-Server Solid State Drives (SSD)
        No of SSDs detected
        No of ESXis hosts having SSDs
        Total SSD size
        Total available storage
        Vendor name (e.g Fusion, IBM)
    Application services
        Name and total no of application services found on virtual machines
        No of VMs having particular application service
    I/O Multipath
        Types of I/O Multipathing
        Total no of I/O paths configured
        No of hosts having multipath
        MPIO Software (e.g. Native, EMC PowerPath, Hitachi Dynamic Link Manager, NAS / DAS)
    vCenter Operations Manager and Similar Solutions
        Name, Version and Discovery source of Management Solution



Prerequisites:
=============

You should install one of the vSphere Command-Line Interface (CLI) versions:

    vSphere CLI 5.1
    vSphere CLI 5.5

For vSphere CLI 5.1, vSphere CLI 5.5 see detailed requirements from the following:

    vSphere CLI 5.1
    This tool supports both 32 bit and 64 bit of the following Linux distributions along with VMware vSphere CLI 5.1 installed on it:
        Red Hat Enterprise Linux 5.5 Server
        SLES 10 SP1
        SLES 11
        SLES 11 SP1
        Ubuntu 10.04

    vSphere CLI 5.5:
    This tool supports both 32 bit and 64 bit of the following Linux distributions:
        Red Hat Enterprise Linux (RHEL) 6.3 (Server)
        Red Hat Enterprise Linux (RHEL) 5.5 (Server)
        Ubuntu 10.04.1 (LTS)
        SLES 11
        SLES 11 SP2

Usage:

$ ./vCollect.pl --server <vCenter ip address> --username <username> --password <password>

    server : vCenter IP Address
    username : username to login to the vCenter server.
    password : password for the username


