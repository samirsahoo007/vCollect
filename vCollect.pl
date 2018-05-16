#!/usr/bin/perl -w

#use strict;
use warnings;
use Data::Dumper;
use VMware::VILib;
use VMware::VIRuntime;
use POSIX qw(:sys_wait_h);
$|++;

my $scriptVersion = 1.0;

if (!defined( $ARGV[0]) || $ARGV[0] =~ /[-]-h[elp]/i)
{
    my $cmd = "perl ".$0." --server server_name_or_ip --username username ".
                  "--password password";
    print "Usage:\n",$cmd,"\n\n";
    exit;
}

my $util=Utils->new();
# Step 1: Import the vSphere SDK for Perl Modules.
my %opts = (
      entity => {
      type => "=s",
      variable => "VI_ENTITY",
      help => "ManagedEntity type: HostSystem, VMs etc",
      required => 0,
      },
);

my %data = ();
my %features = ();
my %servicesH = ();
my @allFeatures = ();
my @hostsProcessed = ();
my %server_models = ();
my %operating_systems = ();
my %vms_all_adv_params = ();
my $count_clusterHA = 0;
my $gsxCount = 0;
my $vpxCount = 0;
my $esxiCount = 0;
my $protectedvmcounter = 0;
my $vmcounter = 0;
my $protecteddatastorecounter = 0;
my $unprotectedvmcounter = 0;
my %SSDHash = ();
my %SSDCount = ();
my @detectedHostsList = ();
my %hostsClusterMap = ();
my @all_features = ();
my %dataPoint_multipathing = ();
my $totalUncommittedStorage = 0;
my $totalCpuCount = 0;
my %zerto_replication = (
                            "Zerto" => {
                                "is_used"          => "no",
                                "discovery_source" => "VMware vCenter",
                                "additional_info"  => "N/A"
                            }
                        );
my %vsphere_replication = (
                              "vSphere_Replication" => {
                                  "is_used"          => "no",
                                  "discovery_source" => "VMware vCenter",
                                  "additional_info"  => "N/A"
                              }
                          );
my %srm_replication = (
                            "VMware_SRM" => {
                                "is_used"          => "no",
                                "discovery_source" => "VMware SRM",
                                "additional_info"  => "N/A"
                            }
                        );
my %storage_replication = (
                            "Storage_Replication" => {
                                "is_used"          => "no",
                                "discovery_source" => "VMware SRM",
                                "additional_info"  => "N/A"
                            }
                        );

=head
Entity Mapping to REMEMBER
'vm' => 'VirtualMachine',
'host' => 'HostSystem',
'cluster' => 'ComputeResource',
'datacenter' => 'Datacenter',
'rp' => 'ResourcePool',
'network' => 'Network',
'dvs' => 'DistributedVirtualSwitch',
folder' => 'Folder',
'vapp' => 'ResourcePool',
'datastore' => 'Datastore'
=cut

# Step 2: (Optional) Define Script-Specific Command-Line Options.
Opts::add_options(%opts);
Opts::parse();
Opts::validate();
my $serverAddress=Opts::get_option('server');
my $username=Opts::get_option('username');
my $password=Opts::get_option('password');
#print Dumper \%opts;exit;

my ($uniqueID,$startTime,$endTime);
my ($hostCount,$vmCount,$vmdkCount,$datastoreCount,$lunCount,$clusterCount) = 
    (0,0,0,0,0,0);

###### Comment out the fork part and test the subroutine here ######
=head
Util::connect();
#&getvAppsInfo;
#&getSSDdetails;
#&getDatastoreInfo;
#&getClusterInfo;
#&getHostsInfo;
#&getHostStorageInfo;
#&getMultiPathInfoUsingCommand("10.200.60.31");
#&getVMInfo;
&getSolutionManagerInfo;
#&getApplicationServicesInfo;
#&getFeaturesInfo;
&generateReportPrintSummary;
Util::disconnect();
=cut
###### END ######

sub clear_screen {
	my $clear_string = `clear`;
	print $clear_string;
}

sub print_start_collection {
	my ($str,$time) =@_;
	my $len = map $_, $str =~ /(.)/gs;
	print "$str ";
	my $rep = 100 - $len;
	print "." x $rep;
    if(!defined($time)){
		print " Done\n";
	}else{
		#print " Done ($time)\n";
        print " Done\n";
	}
	return;
}


my $copyright = "VIRTUAL ENVIRONMENT ASSESSMENT TOOL\n\n
Copyright (c) 2016 Veritas Technologies LLC. All rights reserved.
Veritas and the Veritas Logo are trademarks or registered trademarks of
Veritas Technologies Corporation or its affiliates in the U.S. and other
countries. Other names may be trademarks of their respective owners.

Press [Return] to continue:";
clear_screen();
print "$copyright";<STDIN>;
clear_screen();


$util->printHeading_stdout("Starting Data Collection in the vCenter Environment...");
my $reportName = $util->getReportName();
my $txtreportName = $reportName. ".txt";
open(my $fh, '>', $txtreportName) or die "Could not open file '$txtreportName' $!";
defined(my $pid = fork) or die "Couldn't fork: $!";
if (!$pid) { # Child
    # Step 3: Connect to the vCenter
    print_start_collection("Connecting to the vCenter");
    Util::connect();

    # Data collection subroutines
    &getvCenterInfo;
    &getFeaturesInfo;
    &getClusterInfo;
    &getHostsInfo;
    &getVMInfo;
    &getDatastoreInfo;
    &getHostStorageInfo;
    &getvAppsInfo;
    &getSolutionManagerInfo;
    &getApplicationServicesInfo;
    print "\n\nData Collection completed successfully.\n\n";
    #<STDIN>;
    #clear_screen();
    &generateReportPrintSummary;
    close $fh;
    Util::disconnect();
} else { # Parent
    print "\n";
    while (! waitpid($pid, WNOHANG)) {
        my @loading = qw(| / * \\);
        foreach my $symbol(@loading){
            print $symbol."\r\r";
            sleep 1;
        }
    }
    print "\n";
}

sub generateReportPrintSummary{
    my $reportTags = $util->getReportGenerationTags;
    $data{"REPORT"} = $reportTags->{"REPORT"};
    my %veat_report= ();
    $veat_report{"VEAT_REPORT"} = \%data;
    my $xmlTags = $util->generateTags(\%veat_report);
    #print $xmlTags,"\n";
    my $xmlreportName = $reportName . ".xml";
    $util->writeToXml($xmlreportName,$xmlTags);

    #print Dumper (\%server_models);
    my $string = "About The Environment(in numbers)";
    $util->printHeading($string);
    #printf('%-40s%-40s%-40s%-40s',
    #    "Group Type", "Group Name", "Number of VMs", "Discovery Source");
    #print "Number of vSphere HA Clusters: ",$count_clusterHA,"\n";
    printf $fh ("%-45s%-40d", "Number of vSphere HA Clusters: ",$count_clusterHA);
    print $fh "\n";
    printf $fh ("%-45s%-40d",  "Number of ESXi(ESX Server product) Hosts: ",
        $esxiCount);
    print $fh "\n";
    printf $fh ("%-45s%-40d",  "Number of GSX(GSX Server product) Hosts: ",
        $gsxCount);
    print $fh "\n";
    printf $fh ("%-45s%-40d",  "Number of VPX(VirtualCenter product) Hosts: ",
        $vpxCount);
    print $fh "\n";
    printf $fh ("%-45s%-40s", "Number of Virtual Machines (protected): ",$vmcounter.
        "(".$protectedvmcounter.")");
    print $fh "\n";
    printf $fh ("%-45s%-40s", "Number of Datastores (protected): ",$datastoreCount.
        "(".$protecteddatastorecounter.")");
    print $fh "\n";
    printf $fh ("%-45s%-40s", "Number of LUNs (replicated): ",
        $data{"vCenter"}{"vCenter_env_info"}{"lun_count"}{"total"}."(".
        $data{"vCenter"}{"vCenter_env_info"}{"lun_count"}{"replicated"}.")");
    print $fh "\n";
    my $totalStorageSizeInBytes = 
        $data{"vCenter"}{"vCenter_env_info"}{"storage_size"}{"total_in_bytes"};
    my $totalStorageSize = 
        $data{"vCenter"}{"vCenter_env_info"}{"storage_size"}{"total"};
    printf $fh ("%-45s%-40s", "Total storage: ",$totalStorageSize);
    print $fh "\n";
    my $availableStorageSize = 
        $data{"vCenter"}{"vCenter_env_info"}{"storage_size"}{"free"};
    printf $fh ("%-45s%-40s", "Total available/free storage: ",
        $availableStorageSize);
    print $fh "\n";
    printf $fh ("%-45s%-40s", "Total used storage: ",
        $data{"vCenter"}{"vCenter_env_info"}{"storage_size"}{"used"});
    print $fh "\n";
    printf $fh ("%-45s%-40s", "Total allocated storage: ",
        $data{"vCenter"}{"vCenter_env_info"}{"storage_size"}{"allocated"});
    print $fh "\n";
    printf $fh("%-45s%-40s", "Total replicated storage: ",
        $data{"vCenter"}{"vCenter_env_info"}{"storage_size"}{"replicated"});
    print $fh "\n";
    #printf("%-45s%-40s",  "Number of external storage systems: ",
    #    $data{"vCenter"}{"vCenter_env_info"}{"storage_system_count"}{"local_storage"}{"external"});
    #print "\n";
    $string = "Technologies and Features Used:";
    $util->printHeading($string);
    printf $fh ("%-25s", "Server Models: ");
    my $separator=", ";
    my @serverArr = keys %server_models;
    my $j = 0;
    foreach my $serverK (@serverArr){
        my $str = $serverK."(".$server_models{$serverK}.")";
        $str .= $separator unless ($j == $#serverArr);
        $j++;
        print $fh $str;
    }
    print $fh "\n";
    printf $fh ("%-25s%-25s", "Storage Types: ", "NAS(".
        $data{"vCenter"}{"vCenter_env_info"}{"storage_types"}{"nas"}."), ".
        "SAN - FC(".
        $data{"vCenter"}{"vCenter_env_info"}{"storage_types"}{"fc-san"}."), ".
        "SAN - iSCSI(".
        $data{"vCenter"}{"vCenter_env_info"}{"storage_types"}{"iscsi-san"}."), ".
        "DAS(".$data{"vCenter"}{"vCenter_env_info"}{"storage_types"}{"das"}.")");
    print $fh "\n";
    printf $fh ("%-25s%-25s", "Features: ",join(", ",@allFeatures));
    print $fh "\n";
    printf $fh ("%-25s", "VM Operating Systems: ");
    #print Dumper \%operating_systems;
    my @osArr = keys %operating_systems;
    my $i = 0;
    foreach my $osK (@osArr){
        my $s = $osK."(".$operating_systems{$osK}.")";
        $s .= $separator unless ($i == $#osArr);
        $i++;
        print $fh $s;
    }

    print $fh "\n";
    $string = "Virtual Applications:";
    $util->printHeading($string);
    printf $fh ('%-40s%-40s%-40s%-40s',
        "Group Type", "Group Name", "Number of VMs", "Discovery Source");
    print $fh "\n";
    foreach my $vApp(@{$data{"vCenter"}{"virtual_apps"}}){
        printf $fh ('%-40s%-40s%-40s%-40s',
                    $vApp->{"virtual_app"}{"vapp_group_type"},
                    $vApp->{"virtual_app"}{"vapp_name"},
                    $vApp->{"virtual_app"}{"vm_count"},
                    $vApp->{"virtual_app"}{"vapp_discovery_source"});
        print $fh "\n";
    }

    $string = "In-Server Solid State Drives (SSD):";
    $util->printHeading($string);
    my $totalSSDs = 0;
    foreach my $vendor (keys %SSDCount){
        $totalSSDs += $SSDCount{$vendor}{'count'};
    }
    print $fh $totalSSDs." SSD disks detected in ".$esxiCount." ESXi hosts\n";
    my $totalSSDCapacity = 0;
    my $totalSSDCapacityInBytes = 0;
    #print Dumper \%SSDHash;
    my %SSDHostAdditionalInfoMap = ();
    foreach my $hostname (keys %SSDHash) {
        foreach my $ele (@{$SSDHash{$hostname}->{"SSDs"}}){
            $totalSSDCapacity += $ele->{"size_in_gb"};
            $totalSSDCapacityInBytes += $ele->{"size_in_bytes"};
            $SSDHostAdditionalInfoMap{$ele->{"vendor"}}{"disk_count"}++;
            if (exists $SSDHostAdditionalInfoMap{$ele->{"vendor"}}{"hosts"} &&
                scalar @{$SSDHostAdditionalInfoMap{$ele->{"vendor"}}{"hosts"}}){
                my @hostArr =
                    @{$SSDHostAdditionalInfoMap{$ele->{"vendor"}}{"hosts"}};
                if (!grep /$hostname/,@hostArr){
                    push @{$SSDHostAdditionalInfoMap{$ele->{"vendor"}}{"hosts"}},
                        $hostname;
                }
            } else {
                push @{$SSDHostAdditionalInfoMap{$ele->{"vendor"}}{"hosts"}},
                    $hostname;
            }

            $SSDHostAdditionalInfoMap{$ele->{"vendor"}}{"size_in_gb"} +=
                $ele->{"size_in_gb"};
        }
    }
=head
print Dumper \%SSDHostAdditionalInfoMap;
e.g.
$VAR1 = {
          'INTEL' => {
                       'hosts' => [
                                    '10.200.60.36',
                                    '10.200.60.31'
                                  ],
                       'size_in_gb' => 40,
                       'disk_count' => 2
                     },
          'STEC' => {
                      'hosts' => [
                                   '10.200.60.32'
                                 ],
                      'size_in_gb' => 109,
                      'disk_count' => 2
                    },
          'DGC' => {
                     'hosts' => [
                                  '10.200.60.32',
                                  '10.200.60.36',
                                  '10.200.60.31'
                                ],
                     'size_in_gb' => 248,
                     'disk_count' => 6
                   }
        };

=cut
    
    
    my $ssd_size_percent_of_available = 
        ($totalSSDCapacityInBytes / $totalStorageSizeInBytes) * 100;
    $ssd_size_percent_of_available = 
        sprintf("%.2f",$ssd_size_percent_of_available);
    print $fh "Total SSD size: ".$totalSSDCapacity." GB (". 
        $ssd_size_percent_of_available. "% of total available storage)\n\n";
    printf $fh ('%-40s%-40s%-40s', "Vendor ", "No of hosts", "Additional info");
    print $fh "\n";
    foreach my $vendor (keys %SSDHostAdditionalInfoMap){
        printf $fh ('%-40s%-40s%-40s', 
                     $vendor,
                     scalar @{$SSDHostAdditionalInfoMap{$vendor}{"hosts"}},
                     $SSDHostAdditionalInfoMap{$vendor}{"disk_count"}." disks");
        printf $fh "\n";
        printf $fh ('%100s', 
            "Total size is ".
            $SSDHostAdditionalInfoMap{$vendor}{"size_in_gb"}." GB");
    }
    print $fh "\n";

    $string = "Consolidation Ratios";
    $util->printHeading($string);
    my $avgVMsPerEsx = $util->getCeiledDivVal($vmcounter, $esxiCount);
    printf $fh ("%-40s%-40s", "Average number of VMs per ESXi Host: ",
        $avgVMsPerEsx);
    print $fh "\n";
    my $avgVMsPerCpu = $util->getCeiledDivVal($vmcounter, $totalCpuCount);
    printf $fh ("%-40s%-40s", "Average number of VMs per CPU: ",$avgVMsPerCpu);
    print $fh "\n\n";
    printf $fh ('%-40s%-40s%-40s%-40s',
        "Cluster", "Total Memory", "Total Number of CPU", 
        "Number of hosted VMs (Running)");
    print $fh "\n";
    my $hostedVMsCount = 0;
    my $hostedVMsRunningCount = 0;
    foreach my $clus(@{$data{"vCenter"}{"clusters"}}){
        foreach my $esxi (@{$clus->{"cluster"}{"ESXis"}}){
            foreach my $vms($esxi->{"ESXi"}{"VMs"}){
                foreach my $vm(@$vms){
                    #print $fh "VM Name===> ",$vm->{"VM"}{"name"},"\n";
                    $hostedVMsCount += 1;
                    if ($vm->{"VM"}{"is_running"} eq "yes"){
                        $hostedVMsRunningCount += 1;
                    }
                }
            }
        }
        my $totalMemory = $util->convert_bytes_to_human_readable(
            $clus->{"cluster"}{"total_memory"}, 1024);
            printf $fh ('%-40s%-40s%-40s%-40s',
                $clus->{"cluster"}{"name"}, $totalMemory,
                $clus->{"cluster"}{"total_cpu_cores"},
                $hostedVMsCount."(".$hostedVMsRunningCount.")");
    }
    
    print $fh "\n";
    $string = "I/O Multipath:";
    $util->printHeading($string);
    print $fh "A total of ".$dataPoint_multipathing{"io_paths_total"}.
        " I/O paths are configured.\n".
        "The following identifies MPIO solutions in use.\n\n";
    printf $fh ('%-40s%-40s%-40s',
        "MPIO Software", "Number of hosts", "Storage systems");
    print $fh "\n";
    #print Dumper \%dataPoint_multipathing,"\n";
    foreach my $mpio_software(keys %dataPoint_multipathing){
        next if ($mpio_software eq "io_paths_total");
        my $hostCount = $util->uniq(
            $dataPoint_multipathing{$mpio_software}{"hosts"}
        );
        my @storage_systems = 
            @{$dataPoint_multipathing{$mpio_software}{"storage_system"}};
        printf $fh ('%-40s%-40s%-40s',
            $mpio_software, scalar @$hostCount, join(",",@storage_systems));
        print $fh "\n";
    }

    print $fh "\n\n";
    printf $fh ('%-70s%-40s%-40s',
        "Management Solution", "Version", "Discovery Source");
    print $fh "\n","-" x 150,"\n";
    foreach my $opsMgr(@{$data{"vCenter"}{"operation_managers"}}){
        printf $fh ('%-70s%-40s%-40s',
            $opsMgr->{"operation_manager"}->{"om_name"},
            $opsMgr->{"operation_manager"}->{"om_version"},
            $opsMgr->{"operation_manager"}->{"om_discovery_source"});
        print $fh "\n";
    }
    print "\n";
    print "The XML report ".$reportName.".xml is generated successfully in ".
        "the current working directory.\n\n"."You can upload it to the ".
        "following SORT webpage to view the report in html format.\n";

    print "\nhttps://sort.veritas.com/veat_dc/upload_report\n";

    print "\nYou can also view the text report ".$reportName.
        ".txt which is generated in the current working directory.\n";
}

sub getvCenterInfo {
	$startTime = time();

	my $sc = Vim::get_service_content();
        $data{"vCenter"}{"name"} = $sc->about->fullName;
	$data{"vCenter"}{"uuid"} = $sc->about->instanceUuid;
	$data{"vCenter"}{"version"} = $sc->about->version;
	$data{"vCenter"}{"host"} = $serverAddress;
			
	$endTime = time();
	print_start_collection("Retrieving vCenter Environment Information".
            " (Total Time : ". ($endTime - $startTime) . " seconds)");
	#print "\nvCenter Info took " . ($endTime - $startTime) . " seconds\n\n";
}

sub getFeaturesInfo {
        $startTime = time();

        my $sc = Vim::get_service_content();
        # Licenses
        my ($hostType,$apiType,$apiVersion) = 
            ($sc->about->productLineId,$sc->about->apiType,$sc->about->version);
        my $licenseMgr = Vim::get_view (mo_ref => $sc->licenseManager);
        my $licenses = $licenseMgr->licenses;
        my $feature;
        foreach my $license(@$licenses) {
            my $licenseProperties = $license->properties;
                foreach my $licenseProperty(@$licenseProperties) {
                    #print $licenseProperty->key,"\n";
                    if($licenseProperty->key eq 'feature') {
                        my $featureDetails = $licenseProperty->value;
                        $feature = $featureDetails->value;
                    } else {
                        if(($licenseProperty->key eq 'expirationHours') or 
                            ($licenseProperty->key eq 'expirationMinutes' ) or 
                            ($licenseProperty->key eq 'expirationDate' ) ) {
                                $feature = $licenseProperty->value; 
                        }
                    }
                    if ($feature and !grep /$feature/,@allFeatures){
                        my %f = ();
                        $f{"feature"}{"name"} = $feature;
                        push @{$data{"vCenter"}{"vCenter_env_info"}{"features"}}, \%f;
                        push @allFeatures,$feature;
                    }
                }
        }
        #print Dumper \%data;
        $endTime = time();
	print_start_collection("Retrieving vCenter Features Information".
            " (Total Time : ". ($endTime - $startTime) . " seconds)");
        #print "\nvCenter Features Info took " . ($endTime - $startTime) . " seconds\n\n";
}

sub getVMInfo {
    $startTime = time();
    #vm string keys
    #s_vm,vcInstanceUUID,vmUuid,vmState,vmOS,vmCPU,vmMem,vmNic,vmDisk,
    # vmCPUUsage,vmMemUsage,vmCPUResv,vmMemResv,vmStorageTot,vmStorageUsed,
    # vmUptime,vmFT,vmVHW
    #vmdk string keys
    #s_vmdk,vcInstanceUUID,vmdkKey,vmdkType,vmdkCapacity

    my $vms = Vim::find_entity_views(view_type => 'VirtualMachine');
    my $storage_count = 0;
    #$vmcounter = scalar @$vms;
    foreach my $vm (@$vms) {
        # print Dumper($vm),"\n";
        my $vmName = $vm->name;
        #print "Processing VM ",$vmName,"\n";
        # If it's a template then don't count it as VM
        # get-vm command doesn't report this.
        if ($vm->config->template) {
            next;
        }
        $vmcounter++;

        my $vmUuid = $vm->summary->config->instanceUuid;
        my $vmState = $vm->summary->runtime->powerState->val;
        my $vmOS = $vm->summary->config->guestFullName;
        #$vmOS =~ s/,//g;
        my $vmCPU = $vm->summary->config->numCpu;
        my $vmMem = $vm->summary->config->memorySizeMB;
        my $vmNic = $vm->summary->config->numEthernetCards;
        my $vmDisk = $vm->summary->config->numVirtualDisks;
        # MHZ
        my $vmCPUUsage = $vm->summary->quickStats->overallCpuUsage;
        # MB
        my $vmMemUsage = $vm->summary->quickStats->guestMemoryUsage;
        # MHZ
        my $vmCPUResv = $vm->summary->config->cpuReservation;
        # MB
        my $vmMemResv = $vm->summary->config->memoryReservation;
        # Guest Information
        my $vmGuestId = $vm->guest->guestId;
        my $vmGuestIpAddress = $vm->guest->ipAddress;
        my $vmGuestState = $vm->guest->guestState;
        my $vmGuestFamily = $vm->guest->guestFamily;
        $vmGuestFamily = $util->trim($vmGuestFamily);
        #print "GuestFamily: ".$vmGuestFamily,"\n";
        #print "vmOS: ".$vmOS,"\n";
        #print "vmGuestState: ".$vmGuestState,"\n";

        # Logic to find appropriate Operating system
        my $osType= (split(/Guest/,$vmGuestFamily))[0];

        if ($vmGuestFamily =~ /^\s*$/ or $vmGuestFamily =~ /unknown/i){
            if ($vmOS and $vmOS =~ /windows/i){
                $osType = "windows";
            } else {
                $osType = "unknown";
            }
        }
        $operating_systems{$osType} += 1;

        my $vmStorageTot = $vm->summary->{'storage'}{'committed'}; 
        if ($vm->summary->{'storage'}{'uncommitted'}){
            $vmStorageTot += $vm->summary->{'storage'}{'uncommitted'};
        }
        my $vmStorageUsed = $vm->{'summary'}{'storage'}{'committed'};
        $totalUncommittedStorage += $vm->summary->{'storage'}{'uncommitted'};
        my $vmUptime = ($vm->summary->quickStats->uptimeSeconds ? 
            $vm->summary->quickStats->uptimeSeconds : "N/A");
        my $vmFT = $vm->summary->runtime->faultToleranceState->val;
        my $vmVHW = $vm->{'vim'}{'service_content'}{'about'}{'version'};
        $vmCount++;
	
        my $devices = $vm->{'config'}{'hardware'}{'device'};
        foreach my $device (@$devices) {
            my $vmdkKey = $vmUuid;
            $vmdkKey .= "-" . $device->key if ($device->key);
            my $vmdkType = "";
            if($device->isa('VirtualDisk')) {
                my $vmdkCapacity = $device->capacityInKB;
                $vmdkCount++;
            }
        }
        $storage_count += scalar(@$devices);
        &getReplicationInfo($vm);
    }
    $data{"vCenter"}{"vCenter_env_info"}{"vm_count"}{"total"} = $vmcounter;
    push @{$data{"vCenter"}{"replication"}}, 
        (\%zerto_replication, \%vsphere_replication, 
        \%srm_replication, \%storage_replication);
    #$data{"vCenter_env_info"}{"storage_system_count"} = $storage_count; 
    $endTime = time();
    print_start_collection("Retrieving Virtual Machines and Replication Information".
        " (Total Time : ". ($endTime - $startTime) . " seconds)");
    #print "\nVM Info took " . ($endTime - $startTime) . " seconds\n\n";
}

# The VMs configuration contains some interesting properties. Note that these 
# properties do not generally exist on a VM unless it has been configured for 
#vSphere Replication. Also important to note, the properties continue to exist
# even after replication has been un-configured, but many of the values get 
#blanked out. As far as I can tell, as long as there is a valid value for 
#hbr_filter.destination and the hbr_filter.pause is .false,. the VM is 
#replicating just fine.
sub getReplicationInfo {
    my ($vm_view) = @_;

    my ($cond1, $cond2, $cond3) = (0, 0, 0);
    my $extraConf = "";#$vm_view->config->extraConfig;
    eval { $extraConf = $vm_view->config->extraConfig; };
    #$data{"vCenter"}{"replication"} = [];
    #print Dumper $extraConf;
    if (!$@){
        foreach my $conf(@$extraConf) {
            if ($conf->key eq "hbr_filter.destination"){
                #print "Host based replication(HBR) detected\n";
                $cond1 = 1;
            }
            if ($conf->key eq "hbr_filter.pause" and $conf->value eq "false"){
                $cond2 = 1;
            }
            if ($conf->key eq "com.zerto.appliancetype" and $conf->value == 1){
                $cond3 = 1;
            }
        }
    }

    if ($cond3){
        $zerto_replication{"Zerto"}{"is_used"} = "yes";
        #print "Replication configured on VM ",$vm_view->name.
        #    "\n Replication Type: Zerto ".
        #    "        Discovery Source: VMware vCenter","\n";
    }

    if ($cond1 && $cond2){
        $vsphere_replication{"vSphere_Replication"}{"is_used"} = "yes";
        #print "Replication configured on VM ",$vm_view->name.
        #    "\n Replication Type: vSphere Replication ".
        #    "        Discovery Source: VMware vCenter","\n";
    }
}

sub getApplicationServicesInfo {
    $startTime = time();
    my @vmw_apps = ();
    my $sc = Vim::get_service_content();

    my $host_views = Vim::find_entity_views(view_type => 'HostSystem');
    foreach my $host_view(@$host_views){


=head
    my $vms = Vim::get_views(mo_ref_array => $host_view->vm);
    ######################
    # VM TAG
    ######################
    foreach my $vm(@$vms){
        if(defined($vm->tag)) {
            my $vmTags = $vm->tag;
            my $tagString = $vm->name.$vm->key;
            push @vmw_apps, $tagString;
            print "tagString = $tagString\n";
        } else {
            print "vm->tag is not defined for ",$vm->name,"\n";
        }
    }
    }
=cut

=way1
    my $services = $host_view->config->service->service;
        if($services) {
            my $serviceString = "";
            foreach(@$services) {
                $serviceString .= $_->label;
                if($_->sourcePackage) {
                    $serviceString .= $_->sourcePackage->sourcePackageName;
                    print "Service name: ",$_->label,"\n";
                } else { $serviceString .= "N/A"; }
                $serviceString .= $_->policy.(($_->running) ? "YES" : "NO");
                #print "serviceString = $serviceString\n";
            }
        }
=cut
        my $services = Vim::get_view(
                            mo_ref => $host_view->configManager->serviceSystem,
                            properties => ['serviceInfo']
                        )->serviceInfo->service;
        #print Dumper $services;exit;
        foreach my $service(@$services)
        {
            my $srvkey = $service->key;
            my $srvname = $service->label;
            #print $srvname,"\r";
            $servicesH{$srvname}{"running"} += $service->running;
            $servicesH{$srvname}{"total"} += 1;
            #print "Service name: ",$srvname,"\n";
        }
    }
    $data{"vCenter"}{"applications"} = [];
    foreach my $appServ(keys %servicesH){
        my %application = ();
        $application{"application"}{"app_name"}=$appServ;
        $application{"application"}{"vm_count"}=$servicesH{$appServ}{"total"};
        $application{"application"}{"running"}=$servicesH{$appServ}{"running"};
        push @{$data{"vCenter"}{"applications"}}, \%application;
    }
    
    $endTime = time();
    print_start_collection("Retrieving Application Services Information".
        " (Total Time : ". ($endTime - $startTime) . " seconds)");
    #print "\nApplication Services Info took " . ($endTime - $startTime) . " seconds\n\n";
    #print Dumper \%data,"\n";
}

# Make sure that getVMInfo is called before this subroutine. Otherwise this
# would result into providing incorrect information
sub getDatastoreInfo {
    $startTime = time();
    # s_datastore,vcInstanceUUID,dsUuid,dsType,dsSSD,dsVMFSVersion,
    # dsCapacity,dsFree,dsVMs;
    my @dsUuids = ();
    my @duplicateDsUuids = ();

    my $datastores = Vim::find_entity_views(view_type => 'Datastore');
    my ($storageSizeTotal, $dsFree, $replicatedStorageSizeTotal) = (0, 0, 0);
    foreach my $datastore (@$datastores) {
        #print Dumper($datastore),"\n";exit;
        my ($dsId, $dsUuid) = ("", "");
        my $dsName = $datastore->name;
        if ($datastore->{'mo_ref'}->value){
            $dsId .= "-" . $datastore->{'mo_ref'}->value;
        }
        my $dsType = $datastore->{'summary'}->type;
        $dsUuid = $datastore->{'summary'}->url;
        $dsUuid =~ s/\/$//;
        $dsUuid = (split(/\//,$dsUuid))[-1];
        my $dsSSD = "false";
        my $dsVMFSVersion = "N/A";
        #print Dumper $datastore,"\n";
        if($dsType eq "VMFS") {
            $dsSSD = ($datastore->{'info'}->vmfs->ssd ? "true" : "false");
            #print Dumper $datastore->{'info'}->vmfs,"\n";
            $dsVMFSVersion = $datastore->{'info'}->vmfs->version;
            #print("\"$datastore\" is not SSD backed!\n\n","red");
            # Note that SSD backed doesn't imply that it's an SSD
            # It is SSD-Backed datasote, not SSD
        }
        # BYTES
        my $dsCapacity = $datastore->{'summary'}->capacity;
        $storageSizeTotal += $dsCapacity;
        # BYTES
        $dsFree = $datastore->{'summary'}->freeSpace;
        if (grep /$dsUuid/, @dsUuids){
            #print "Duplicate datastore found UUID=$dsUuid\n";
            $replicatedStorageSizeTotal += $dsCapacity;
            push @duplicateDsUuids, $dsUuid;
        }
        #print "dsName=$dsName\ndsId=$dsId\nuuid=$dsUuid\ndsFree=$dsFree\n".
        #    "dsCapacity=$dsCapacity\nreplicatedStorageSizeTotal=".
        #    "$replicatedStorageSizeTotal","\n";
        my $dsVMs = scalar(@{Vim::get_views(
                                               mo_ref_array => $datastore->vm, 
                                               properties => ['name']
                                           )
                            }
                          );
        push @dsUuids, $dsUuid;
        $datastoreCount++;
    }
    $data{"vCenter"}{"vCenter_env_info"}{"datastore_count"}{"total"} = 
        $datastoreCount;
    $data{"vCenter"}{"vCenter_env_info"}{"datastore_count"}{"replicated"} = 
        $#duplicateDsUuids + 1;
    $data{"vCenter"}{"vCenter_env_info"}{"storage_size"}{"total_in_bytes"} = 
        $storageSizeTotal;
    $data{"vCenter"}{"vCenter_env_info"}{"storage_size"}{"total"} = 
        $util->convert_bytes_to_human_readable($storageSizeTotal,1024);
    $data{"vCenter"}{"vCenter_env_info"}{"storage_size"}{"free"} = 
        $util->convert_bytes_to_human_readable($dsFree,1024);
    my $used = $storageSizeTotal - $dsFree;
    $data{"vCenter"}{"vCenter_env_info"}{"storage_size"}{"used"} = 
        $util->convert_bytes_to_human_readable($used, 1024);
    my $allocated = $used + $totalUncommittedStorage;
    $data{"vCenter"}{"vCenter_env_info"}{"storage_size"}{"allocated"} = 
        $util->convert_bytes_to_human_readable($allocated, 1024);
    $data{"vCenter"}{"vCenter_env_info"}{"storage_size"}{"replicated"} = 
        $util->convert_bytes_to_human_readable($replicatedStorageSizeTotal,1000);
    #print Dumper(\%data);
    $endTime = time();
    print_start_collection("Retrieving Datastore Information".
        " (Total Time : ". ($endTime - $startTime) . " seconds)");
    #print "\nDatastore Info took " . ($endTime - $startTime) . " seconds\n\n";
}

sub getClusterInfo {
    #print "Retrieving vSphere HA Cluster Information...";
    $startTime = time();
    # s_cluster,vcInstanceUUID,clusterUuid,clusterTotCpu,clusterTotMem,
    # clusterAvailCpu,clusterAvailMem,clusterHA,clusterDRS,clusterHost,
    # clusterDatastore,clusterVM
    my $clusters = Vim::find_entity_views(
                       view_type => 'ClusterComputeResource'
                   );
    my $count_clusterDRS = 0;
    
    $data{"vCenter"}{"clusters"} = [];
    foreach my $cluster (@$clusters) {
        my $hic = Vim::get_views(
                                    mo_ref_array => $cluster->host,
                                    properties => ['name']
                                );
        my $clusterName = $cluster->name;
        foreach my $x(@$hic) {
            $hostsClusterMap{$x->{'name'}} = $clusterName;
            #push @hostsInClusters,$x->{'name'};
        }

        my %clusterDetails = ();
        #print Dumper($cluster),"\n";exit;
        $clusterDetails{"cluster"}{"name"} = $clusterName;
        my $clusterUuid = $uniqueID;
        if ($cluster->{'mo_ref'}->value){
            $clusterUuid .= "-" . $cluster->{'mo_ref'}->value;
        }
        # Ref: https://www.vmware.com/support/developer/vc-sdk/visdk25pubs/ReferenceGuide/vim.ComputeResource.Summary.html
        #$clusterDetails{"cluster"}{"total_memory"} = 
        #    $cluster->{'summary'}->totalMemory;
        # totalCpu: Aggregated CPU resources of all hosts, in MHz.
        $clusterDetails{"cluster"}{"total_cpu_MHz"} = 
            $cluster->{'summary'}->totalCpu;
        # numCpuCores: Number of physical CPU cores. Physical CPU cores are 
        # the processors contained by a CPU package.
        $clusterDetails{"cluster"}{"total_cpu_cores"} = 
            $cluster->{'summary'}->numCpuCores;
        # numCpuThreads: Aggregated number of CPU threads.
        $clusterDetails{"cluster"}{"total_cpu_threads"} = 
            $cluster->{'summary'}->numCpuThreads;
        # totalMemory: Aggregated memory resources of all hosts, in bytes.
        $clusterDetails{"cluster"}{"total_memory"} = 
            $cluster->{'summary'}->totalMemory;
        
        $clusterDetails{"cluster"}{"name"} = $clusterName;
        $clusterDetails{"cluster"}{"ESXis"} = [];
        my ($clusterHA,$clusterDRS) = ("N/A","N/A");
        my $protected = 0;
        if($cluster->{'configurationEx'}->isa('ClusterConfigInfoEx')) {
            if ($cluster->{'configurationEx'}->dasConfig->enabled){
                #print "Cluster detected with DAS configuration. Name: ",
                #    $clusterName,"\n";
                $count_clusterHA++;
                $protected=1;
            } elsif ($cluster->{'configurationEx'}->drsConfig->enabled){
                #print "Cluster detected with DRS configuration. Name: ",
                #    $clusterName,"\n";
                $count_clusterDRS++;
                $protected=1;
            } else {
                # TODO
            }
        }

        #print "No of HA clusters are $count_clusterHA\n";
        #print "No of DRS clusters are $count_clusterDRS\n";
        #print Dumper($cluster),"\n";
        #print Dumper($cluster->{'configurationEx'}),"\n";
        my $clusterHost = $cluster->{'summary'}->numHosts;
        my $clusterDatastore = scalar(@{Vim::get_views(
                                      mo_ref_array => $cluster->{'datastore'},
                                      properties => ['name']
                                      )});
        if ($protected){
            $protecteddatastorecounter += $clusterDatastore;
        }
        
        #my $clusterVM = scalar(@{Vim::find_entity_views(
        #                                       view_type => 'VirtualMachine',
        #                                       begin_entity => $cluster,
        #                                       properties => ['name']
        #                                       )});
        $clusterCount++;

        # Cluster->VM mapping
        # START
        # Getting VMs per cluster
        # my $clusterName ="cluster1";
        # print "ClusetName => $clusterName\n";
        #my $cluster_view = Vim::find_entity_view (
        #                             view_type => 'ClusterComputeResource',
        #                             filter => {'name' => qr/^$clusterName/i} 
        #                             );
        #if($cluster_view) {
        #    my $vmviews = Vim::find_entity_views(
        #                                     view_type => 'VirtualMachine',
        #                                     begin_entity => $cluster_view,
        #                                     properties => [ 'name' ] 
        #                                 );
            # print "VMs residing on it are... \n";
        #    foreach my $vm_ref(@$vmviews) {
                #print $vm_ref->name."\n";
                #print Dumper($vm_ref),"\n";exit;
        #    }
        #}
        # END

        # Cluster->Host->VMs mapping
        # START
###### Host part moved from here ##########
        my $getHostsHashref = ();
        $getHostsHashref = &getHostsInfo($cluster);#;\@ESXis;
        $clusterDetails{"cluster"}{"ESXis"} = $getHostsHashref->{"ESXis"};#;\@ESXis;
        #$clusterDetails{"cluster"}{"ESXis"} = \@ESXis;
        #print Dumper(\%data);exit;
        push @{$data{"vCenter"}{"clusters"}}, \%clusterDetails;
    }
    $data{"vCenter"}{"vCenter_env_info"}{"ha_cluster"} = $count_clusterHA;
    $data{"vCenter"}{"vCenter_env_info"}{"datastore_count"}{"protected"} = 
        $protecteddatastorecounter;
    $data{"vCenter"}{"vCenter_env_info"}{"vm_count"}{"protected"} = 
        $protectedvmcounter;
#    print Dumper(\%data),"\n";
    $endTime = time();
    #print "\nCluster Info took " . ($endTime - $startTime) . " seconds\n\n";
}

sub getMultiPathInfoUsingCommand{
    my ($viHost) = @_;
    $startTime = time();
    # esxcli --server 10.200.59.107 --username Administrator@vsphere.local --password Passw0rd@123 --thumbprint 1F:CE:20:AE:FD:97:42:DA:A7:EC:7F:7E:B2:6D:4E:A2:F3:5A:2C:9C --vihost 10.200.60.31 storage core path list 
    # esxcli --server 10.200.59.107 --username Administrator@vsphere.local --password Passw0rd@123  --vihost 10.200.60.31 storage core path list
    my $cmd = "esxcli --server ".$serverAddress." --username ".$username.
        " --password ".$password." --vihost ".$viHost.
        " storage core path list";
    my ($cmdResult,$cmdExit) = $util->run_cmd($cmd);
    #print $cmdResult;
=head
   sas.5000000000000000-sas.500000e01947e132-naa.500000e01947e130
   UID: sas.5000000000000000-sas.500000e01947e132-naa.500000e01947e130
   Runtime Name: vmhba2:C0:T0:L0
   Device: naa.500000e01947e130
   Device Display Name: FUJITSU Serial Attached SCSI Disk (naa.500000e01947e130)
   Adapter: vmhba2
   Channel: 0
   Target: 0
   LUN: 0
   Plugin: NMP
   State: active
   Transport: sas
   Adapter Identifier: sas.5000000000000000
   Target Identifier: sas.500000e01947e132
   Adapter Transport Details: 5000000000000000
   Target Transport Details: 500000e01947e132
   Maximum IO Size: 4194304
=cut

    my @hostMultiPath = ();
    my ($lunUID, $storageSystem, $mpioSoftware, $transport, $maxIOSize, $tmp);
    if (!$cmdExit){
        my @arr = split(/\n/,$cmdResult);
        foreach my $line (@arr){
            my %hostPath = ();
            if ($line =~ /UID:/){
                $tmp = (split(/:/,$line,2))[1];
                $lunUID = $util->trim($tmp);
            }
            if ($line =~ /Device Display Name:/){
                $tmp = (split(/:/,$line))[1];
                my $deviceDisplayName = $util->trim($tmp);
                $storageSystem = (split(/\(/,$deviceDisplayName))[0];
            }
            if ($line =~ /Plugin:/){
                $tmp = (split(/:/,$line))[1];
                $mpioSoftware = $util->trim($tmp);
            }
            if ($line =~ /Transport:/){
                $tmp = (split(/:/,$line))[1];
                $transport = $util->trim($tmp);
            }
            if ($line =~ /Maximum IO Size:/){
                $tmp = (split(/:/,$line))[1];
                $maxIOSize = $util->trim($tmp);
                $hostPath{$lunUID}{"max_io_size"} = $maxIOSize; 
                $hostPath{$lunUID}{"storage_system"} = 
                    $util->trim($storageSystem);
                $hostPath{$lunUID}{"iomp_software"} = $mpioSoftware; 
                $hostPath{$lunUID}{"transport"} = $transport; 
                $hostPath{$lunUID}{"storage_system"} = $util->trim(
                                                           $storageSystem
                                                       );
                if ($storageSystem =~ /Local/i and $storageSystem =~ /CD-ROM/i)
                {next;}
                push @hostMultiPath, \%hostPath;# if (keys %hostPath);
            }
        }
    }
    #print Dumper \@hostMultiPath;
    $endTime = time();
    print_start_collection("Retrieving multipathing information for host - $viHost".
        " (Total Time : ". ($endTime - $startTime) . " seconds)");
    return \@hostMultiPath;
}

sub getHostsInfo{
    my ($cluster) = @_;
    my $host_views = ""; #Vim::find_entity_views(view_type => 'HostSystem');
    #print Dumper $hosts;
    my %ssdDetails = ();
    my $subName = (caller(0))[3];
    #if ($subName eq "getClusterInfo" and $cluster){
    if ($cluster){
        $host_views = Vim::find_entity_views(
                                           view_type => 'HostSystem',
                                           begin_entity => $cluster
                                       );
    } else {
        $host_views = Vim::find_entity_views(view_type => 'HostSystem');
    }
    #print Dumper \%hostsClusterMap;
=head
    foreach my $host(@$host_views){
        print "HostName => ", $host->name,"\n";
    }
        ########## Get a view of the ESX Hosts in the specified Cluster
        my $host_views = Vim::find_entity_views(
                                           view_type => 'HostSystem',
                                           begin_entity => $cluster
                                       );
=cut
        my @hostsInCluster = keys %hostsClusterMap;
        my %hostsHash = ();
        my @ESXis = ();
        foreach my $host (@$host_views) {
            #print Dumper $host;exit;
            #print "hostName => ",$host->name,"\n";
            # if the following condition is satisfied then the ESXi information
            # is already collected for the cluster; No need to collect it again
            my $hostName = $host->name;
            if (grep /$hostName/, @hostsProcessed){
                #print "Host already processed => ", $host->name,"\n";
                next;
            }
            my %esxH = ();
            $esxH{"ESXi"}{"hostname"} = $host->name;
            my $server_model = $host->hardware->systemInfo->model;
            $esxH{"ESXi"}{"hardware"}{"server_model"} = $server_model;
            $server_models{$server_model} += 1;;
            $esxH{"ESXi"}{"hardware"}{"cpu_count"} = 
                $host->summary->hardware->numCpuPkgs;
            $totalCpuCount += $host->summary->hardware->numCpuPkgs;
            $esxH{"ESXi"}{"hardware"}{"memory"} = 
                $util->convert_bytes_to_human_readable(
                                          $host->summary->hardware->memorySize,
                                          1024
                                      );
            my @SSDs = ();
            my $scsiLuns = $host->config->storageDevice->scsiLun;
            my %lun_to_displayName_map = ();
            my %lunUUID_to_vendor_map = ();
            my %ssdRestructured = ();
            my @newArrHumanReadableSize = ();
            #&getSSDdetails($host);
            foreach my $scsiLun(@$scsiLuns){
                $lun_to_displayName_map{$scsiLun->key} = $scsiLun->displayName;
                $lunUUID_to_vendor_map{$scsiLun->uuid} = 
                    $util->trim($scsiLun->vendor);
                if ((exists $scsiLun->{"ssd"}) and ($scsiLun->ssd eq "1")){
                    # Note that it is an SSD-Backed Lun, not SSD
                    # print "SSD-Backed lun\n";
                    my $blockSize = $scsiLun->capacity->blockSize;
                    my $blocks = $scsiLun->capacity->block;
                    my $vendor = $util->trim($scsiLun->vendor);
                    my $size = $util->convert_bytes_to_human_readable(
                                                          $blocks * $blockSize,
                                                          1024
                                                      );
                    $ssdDetails{$vendor}{$size} += 1;
                }
                #print Dumper(\%ssdDetails);
            }
            foreach my $ssdK (keys %ssdDetails){
                my $sz = (keys %{$ssdDetails{$ssdK}})[0];
                $ssdRestructured{"ssd"}{"vendor"} = $ssdK;
                $ssdRestructured{"ssd"}{"storage"} = $sz;
                $ssdRestructured{"ssd"}{"disk_count"} = $ssdDetails{$ssdK}{$sz};
            }
            #print Dumper \%ssdRestructured;

            my $newSSDsArr = $util->count_hash_occurences_in_array(\@SSDs);
            foreach my $newSSDele(@$newSSDsArr){
                $newSSDele->{"storage"} = 
                    $util->convert_bytes_to_human_readable(
                                                      $newSSDele->{"storage"},
                                                      1024
                                                  );
                push @newArrHumanReadableSize,$newSSDele;
            }
            $esxH{"ESXi"}{"hardware"}{"SSDs"} = \@newArrHumanReadableSize;
            push @{$esxH{"ESXi"}{"hardware"}{"SSDs"}}, \%ssdRestructured;
            
            $esxH{"ESXi"}{"hardware"}{"io_multipaths"} = [];
            #$esxH{"ESXi"}{"hardware"}{"transports"} = [];
            $esxH{"ESXi"}{"hardware"}{"storages"} = [];
            my $multipathInfo=$host->config->storageDevice->multipathInfo->lun;
            my $MultiPaths = &getMultiPathInfoUsingCommand(
                                                                $host->name
                                                            );
            my %softwareCount = ();
            foreach my $path(@$MultiPaths){
                my $lunUID = (keys %$path)[0];
                my $iomp_software = $path->{$lunUID}->{"iomp_software"};
                #print "\$lunUID=$lunUID\n";
                #print "\$iomp_software=$iomp_software\n";
                $softwareCount{$iomp_software}++;
                if (exists $dataPoint_multipathing{$iomp_software}{"hosts"}){
                    push @{$dataPoint_multipathing{$iomp_software}{"hosts"}},
                        $host->name
                        unless (
                           grep /$hostName/,
                           @{$dataPoint_multipathing{$iomp_software}{"hosts"}}
                        );
                } else {
                    push @{$dataPoint_multipathing{$iomp_software}{"hosts"}},
                        $host->name;
                }
                if (exists $dataPoint_multipathing{$iomp_software}{"storage_system"}){
                    my $lunUID_storage = $path->{$lunUID}->{"storage_system"};
                    push @{$dataPoint_multipathing{$iomp_software}{"storage_system"}},
                         $lunUID_storage
                        unless (
                            grep /$lunUID_storage/,
                            @{$dataPoint_multipathing{$iomp_software}{"storage_system"}}
                        );
                } else {
                    push @{$dataPoint_multipathing{$iomp_software}{"storage_system"}},
                         $path->{$lunUID}->{"storage_system"};
                }
                #$softwareCount{"iomp_software"}{$iomp_software}++;
            }
            #print Dumper \%softwareCount;
            
            foreach my $swCnt(keys %softwareCount){
                my %multipathDetails = ();
                $multipathDetails{"io_multipath"}{"io_paths"} = 
                    $softwareCount{$swCnt};
                $dataPoint_multipathing{"io_paths_total"} += 
                    $softwareCount{$swCnt};
                my $storage_systems = 
                    join (", ", @{$dataPoint_multipathing{$swCnt}{"storage_system"}});
                if ($swCnt eq "NMP"){
                    $swCnt = "Native";
                }
                $multipathDetails{"io_multipath"}{"iomp_software"} = $swCnt; 
                $multipathDetails{"io_multipath"}{"storage_system"} = 
                    $storage_systems;
                push @{$esxH{"ESXi"}{"hardware"}{"io_multipaths"}}, 
                    \%multipathDetails;
            }
            #my %lunPath_to_transport_mapping = ();
            foreach my $mpInfolun (@$multipathInfo){
=head
                my %multipathDetails = ();
                my $lun = $mpInfolun->lun;
                $multipathDetails{"io_multipath"}{"io_paths"} = 
                    scalar @{$mpInfolun->path};
                $multipathDetails{"io_multipath"}{"iomp_software"} = 
                    $lun_to_displayName_map{$lun};
                push @{$esxH{"ESXi"}{"hardware"}{"io_multipaths"}}, 
                    \%multipathDetails;
=cut
                my $lunId = $mpInfolun->id;
                foreach my $path (@{$mpInfolun->path}){
                    my %transportToVendor = ();
                    my $lunPath = $path->lun;
                    my $transport = $path->transport;
                    my $transport_protocol = (split(/=/,$transport))[0]; 
                    #$lunPath_to_transport_mapping{$lunPath} = $transport_protocol;
                    $transportToVendor{"storage"}{"storage_protocol"} = 
                        $transport_protocol;
                    $transportToVendor{"storage"}{"vendor"} = 
                        $lunUUID_to_vendor_map{$lunId};
                    push @{$esxH{"ESXi"}{"hardware"}{"storages"}}, 
                        \%transportToVendor;
                }
            }
            my @features = ();
            $esxH{"ESXi"}{"features"} = [];
            
            my $featureCapabilities = $host->config->featureCapability;
            foreach my $f(@$featureCapabilities){
                my %feature = ();
                if ($f->value eq "1"){
                    $feature{"feature"} = $f->featureName;
                    push @{$esxH{"ESXi"}{"features"}}, \%feature;
                    push @all_features, $f->featureName;
                }
            }
            ########## Get a view of the current host
            my $host_view = Vim::find_entity_view(
                                             view_type => 'HostSystem',
                                             filter => { name => $host->name } 
                                         );

            ########## Get a view of the Virtual Machines on the current host
            my $vm_views = Vim::find_entity_views(
                                             view_type => 'VirtualMachine',
                                             begin_entity => $host_view 
                                         );

            ########## Print information on the VMs and the Hosts
            # print 'Hostname => ', $host->name,"\n";
            # print Dumper $vm_views; exit;
            $esxH{"ESXi"}{"VMs"} = [];
            foreach my $vmref (@$vm_views) {
                my %vmDetails = ();
                # Skip if it's a template
                next if $vmref->config->template;
                $vmDetails{"VM"}{"name"} =  $vmref->name;
                if ($vmref->guest->guestState eq "running"){
                    $vmDetails{"VM"}{"is_running"} = "yes";
                } else {
                    $vmDetails{"VM"}{"is_running"} = "no";
                }
                $vmDetails{"VM"}{"os_name"} = 
                    $vmref->summary->config->guestFullName;
                ## HA PROTECTION ##
                if($vmref->runtime->dasVmProtection) {
                    if ($vmref->runtime->dasVmProtection->dasProtected){
                        $vmDetails{"VM"}{"is_protected"} = "yes";
                        $protectedvmcounter++;
                    } else {
                        $vmDetails{"VM"}{"is_protected"} = "no";
                        $unprotectedvmcounter++;
                    }
                } else {
                    $vmDetails{"VM"}{"is_protected"} = "not configured";
                }
                push @{$esxH{"ESXi"}{"VMs"}},\%vmDetails;
                # print "VM name => ", $vmref->name."\n";
                # print Dumper($vmref),"\n";exit;
            }
            #$hostcounter++;
            # END
        push @ESXis, \%esxH;
        $hostsHash{"ESXis"} = \@ESXis;
        #return \@ESXis;
        if ($subName ne "getClusterInfo" and !grep /$hostName/,@hostsInCluster)
        {
            $hostsHash{"hostcounter"} = scalar @$host_views;
            $data{"vCenter"}{"vCenter_env_info"}{"ESXi_count"} = 
                $hostsHash{"hostcounter"};
            push @{$data{"vCenter"}{"ESXis"}},\%esxH;
        }
        push @hostsProcessed, $host->name;
    }
    return \%hostsHash;
}

# Get vApp info
sub getvAppsInfo {
    $startTime = time();
    my $vapp_views = Vim::find_entity_views(view_type => 'VirtualApp');
    #print Dumper $vapp_views;
    if (scalar @$vapp_views){
        $data{"vCenter"}{"virtual_apps"} = [];
        foreach my $vapp_view(@$vapp_views){
            my %vAppDetails = ();
            $vAppDetails{"virtual_app"}{"vapp_name"} = $vapp_view->name;
            $vAppDetails{"virtual_app"}{"vapp_group_type"} = "vApps";
            $vAppDetails{"virtual_app"}{"vapp_discovery_source"} = 
                "VMware vCenter: vApp";
            if ($vapp_view->vAppConfig->entityConfig){
                $vAppDetails{"virtual_app"}{"vm_count"} = 
                    scalar @{$vapp_view->vAppConfig->entityConfig};
            } else {
                # Unable to find any VM in this vApp!
                $vAppDetails{"virtual_app"}{"vm_count"} = 0;
            }
            push @{$data{"vCenter"}{"virtual_apps"}},\%vAppDetails;
        }
    } else {
        $data{"vCenter"}{"virtual_apps"} = "N/A(No vApp found)";
    }
    $endTime = time();
    print_start_collection("Retrieving vApps Information".
        " (Total Time : ". ($endTime - $startTime) . " seconds)");
    #print Dumper $data{"vCenter"}{"virtual_apps"},"\n";
    #print "\nvApps Info took " . ($endTime - $startTime) . " seconds\n\n";
}

sub getHostStorageInfo {
    #print_start_collection("Retrieving Host Storage and SSD Information");
    $startTime = time();

    my $hosts = Vim::find_entity_views(view_type => 'HostSystem');
    my $hostCount = scalar @$hosts;

    my @uuids = ();
    my $totalStorageReplicated = 0;
    my %storageProtocol = (
                              "fc" => {"count" => 0, "hosts" => []},
                              "iscsi" => {"count" => 0, "hosts" => []},
                              "nas" => {"count" => 0, "hosts" => []},
                              "local" => {"count" => 0, "hosts" => []},
                          );
    my ($cdrom,$idecontroller,$pcicontroller,$ps2controller,$paracontroller,
        $buscontroller,$lsicontroller,$lsilogiccontroller,$siocontroller,
        $usbcontroller,$disk,$e1000ethernet,$pcnet32ethernet,$vmxnet2ethernet,
        $vmxnet3ethernet,$floppy,$keyboard,$videocard,$vmci,$vmi,$parallelport,
        $pcipassthrough,$pointingdevice,$scsipassthrough,$serialport,
        $ensoniqsoundcard,$blastersoundcard) = 
            (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0);
    my $usb = 0;
    
    foreach my $host (@$hosts) {
        my $hostName = $host->name;
        push @detectedHostsList, $hostName;
        if($host->config->product->productLineId =~ m/esx/i) {
            $esxiCount++;
            #print "Processing " . $hostName . "\n";
            &getSSDdetails($host);
            #print "host ",$host->config->product->productLineId,"\n";
            my $host_version = $host->config->product->fullName;
            #&getHostStorage($host);
            my $storageSys = Vim::get_view(mo_ref => $host->configManager->storageSystem);
            my $hbas = $storageSys->storageDeviceInfo->hostBusAdapter;
            my $adapters = $storageSys->storageDeviceInfo->plugStoreTopology->adapter;
            my $scsiAdapters = $storageSys->storageDeviceInfo->scsiTopology->adapter;
            my $paths = $storageSys->storageDeviceInfo->plugStoreTopology->path;
            my $luns = $storageSys->storageDeviceInfo->multipathInfo->lun;
            my $fsInfo = $storageSys->fileSystemVolumeInfo->mountInfo;

            my %devices = ();
            foreach my $scsiAdapter (@$scsiAdapters) {
                my $adapter = $scsiAdapter->adapter;
                $adapter =~ s/.*-//g;
                my $targets = $scsiAdapter->target;
                foreach my $target (@$targets) {
                    my $luns = $target->lun;
                    foreach my $lun (@$luns) {
                        $devices{$adapter . "=" . $lun->key} = "yes";
                    }
                }
            }
        my %deviceCount = ();
        for my $key ( keys %devices) {
                my ($adpt,$lun) = split("=",$key);
                $deviceCount{$adpt} +=1;
        }

        my %pathCount = ();
        my $storageString;
        foreach my $hba(sort {$a->device cmp $b->device}@$hbas) {
                foreach my $adapter(@$adapters) {
                        if($adapter->adapter eq $hba->key) {
                                my $paths = $adapter->path;
                                if($paths) {
                                        $pathCount{$hba->device} = @$paths;
                                } else {
                                        $pathCount{$hba->device} = 0;
                                }
                        }
                }
                my $type;
                if($hba->isa("HostBlockHba")) {
                        $type = "Block";
                } elsif($hba->isa("HostFibreChannelHba")) {
                        $type = "FC";
                } elsif($hba->isa("HostInternetScsiHba")) {
                        $type = "iSCSI";
                } elsif($hba->isa("HostParallelScsiHba")) {
                        $type = "Parallel";
                } else {
                        $type = "Unknown";
                }
                $storageString .= $hba->device . $type . $pathCount{$hba->device} . (defined($deviceCount{$hba->device}) ? $deviceCount{$hba->device} : 0);
        }

        my $storagePathString;
        foreach my $path (@$paths) {
                my $adapter = $path->adapter;
                $adapter =~ s/.*-//g;
                my $pathName = $path->name;
                $pathName =~ s/,/ /g;
                my $hba = $adapter . ":C" . $path->channelNumber . ":T" . $path->targetNumber . ":L" . $path->lunNumber;
                $storagePathString .= $hba . $pathName;
        }
        foreach my $lun (sort @$luns) {
                my $paths = $lun->path;
                foreach my $path (@$paths) {
                        my $adapter = $path->adapter;
                        $adapter =~ s/.*-//g;
                        my $type = $path->adapter;
                        $type =~ s/key-vim.host.//g;
                        my $naa = $path->key;
                        $naa =~ s/.*-//g;
                        my $policy = $lun->policy->policy;
                        my $prefer = "N/A";
                        my $pathName = $path->name;
                        $pathName =~ s/,/ /g;
                        if($lun->policy->isa("HostMultipathInfoFixedLogicalUnitPolicy")) {
                                $prefer = $lun->policy->prefer;
                        }

                        foreach my $fs (@$fsInfo) {
                                next if($fs->volume->isa("HostNasVolume") or $fs->volume->isa("HostVfatVolume"));
                                #print Dumper $fs->volume,"\n";
                                #print "naa = $naa\n";

                                if($type =~ m/FibreChannelHba/ && $fs->volume->isa("HostVmfsVolume")) {
                                        if($fs->volume->extent->[0]->diskName eq $naa) {
                                            $storageProtocol{"fc"}{"count"} += 1;
                                            if (!grep /$hostName/,@{$storageProtocol{"fc"}{"hosts"}}){
                                                push @{$storageProtocol{"fc"}{"hosts"}}, $hostName;
                                            }
                                        }
                                }elsif($type =~ m/InternetScsiHba/ && $fs->volume->isa("HostVmfsVolume")) {
                                        if($fs->volume->extent->[0]->diskName eq $naa) {
                                            $storageProtocol{"iscsi"}{"count"} += 1;
                                            if (!grep /$hostName/,@{$storageProtocol{"iscsi"}{"hosts"}}){
                                                push @{$storageProtocol{"iscsi"}{"hosts"}}, $hostName;
                                            }
                                        }
                                }elsif($type =~ m/BlockHba/ || $type =~ m/ParallelScsiHba/) {
                                        my $DISKNAME = "";
                                        eval { $DISKNAME = $fs->volume->extent->[0]->diskName; };
                                        if (!$@ and $DISKNAME eq $naa) {
                                            $storageProtocol{"local"}{"count"} += 1;
                                            if (!grep /$hostName/,@{$storageProtocol{"local"}{"hosts"}}){
                                                push @{$storageProtocol{"local"}{"hosts"}}, $hostName;
                                            }
                                        }
                                }
                        }
                }
        }
        foreach my $fs (@$fsInfo) {
            if($fs->volume->isa("HostNasVolume")) {
                $storageProtocol{"nas"}{"count"} += 1;
                if (!grep /$hostName/,@{$storageProtocol{"nas"}{"hosts"}}){
                    push @{$storageProtocol{"nas"}{"hosts"}}, $hostName;
                }
            }
        }
        } elsif($host->config->product->productLineId =~ m/gsx/i) {
            $gsxCount++;
        } elsif($host->config->product->productLineId =~ m/vpx/i) {
            $vpxCount++;
        }
         ###### and ends here ######

        my $host_view = Vim::find_entity_view(view_type => 'HostSystem');
        #print "Hostname => ",$host->name,"\n";
        my $storage = Vim::get_view(
                          mo_ref => $host_view->configManager->storageSystem,
                          properties => ['storageDeviceInfo']
                      );
        my $luns = $storage->storageDeviceInfo->scsiLun;
        foreach my $lun (@$luns) {
            if($lun->lunType eq "disk" && $lun->isa('HostScsiDisk')) {
                my $lunUuid = $lun->uuid;
                # If same uuid is found again then it must be a replicated lun
                if (grep /$lunUuid/,@uuids){
                    my $lunCapacity = 
                        $lun->capacity->block * $lun->capacity->blockSize;
                    $totalStorageReplicated += $lunCapacity;
                }
                push @uuids, $lunUuid;
            }
        }

        my $vm_views = Vim::find_entity_views(
                                             view_type => 'VirtualMachine',
                                             begin_entity => $host_view 
                                         );

        foreach my $vm(@$vm_views){
            next if(!defined($vm->config));

            #print Dumper $vm;exit;
            if(!$vm->config->template) {
                my $devices = $vm->config->hardware->device;
                foreach my $device (@$devices) {
                    if($device->isa('VirtualCdrom')) {
                        $cdrom++;
                    }elsif($device->isa('VirtualController')) {
                        if($device->isa('VirtualIDEController')) {
                            $idecontroller++;
                        }elsif($device->isa('VirtualPCIController')) {
                            $pcicontroller++;
                        }elsif($device->isa('VirtualPS2Controller')) {
                            $ps2controller++;
                        }elsif($device->isa('VirtualSCSIController')) {
                            if($device->isa('ParaVirtualSCSIController')) {
                                $paracontroller++;
                            }elsif($device->isa('VirtualBusLogicController')) {
                                $buscontroller++;
                            }elsif($device->isa('VirtualLsiLogicController')) {
                                $lsicontroller++;
                            }elsif($device->isa('VirtualLsiLogicSASController')) {
                                $lsilogiccontroller++;
                            }
                        }elsif($device->isa('VirtualSIOController')) {
                            $siocontroller++;
                        }elsif($device->isa('VirtualUSBController')) {
                            $usbcontroller++;
                        }
                    }elsif($device->isa('VirtualDisk')) {
                        $disk++;
                    }elsif($device->isa('VirtualEthernetCard')) {
                        if($device->isa('VirtualE1000')) {
                            $e1000ethernet++;
                        }elsif($device->isa('VirtualPCNet32')) {
                            $pcnet32ethernet++;
                        }elsif($device->isa('VirtualVmxnet')) {
                            if($device->isa('VirtualVmxnet2')) {
                                $vmxnet2ethernet++;
                            }elsif($device->isa('VirtualVmxnet3')) {
                                $vmxnet3ethernet++;
                            }
                        }
                    }elsif($device->isa('VirtualFloppy')) {
                        $floppy++;
                    }elsif($device->isa('VirtualKeyboard')) {
                        $keyboard++;
                    }elsif($device->isa('VirtualMachineVideoCard')) {
                        $videocard++;
                    }elsif($device->isa('VirtualMachineVMCIDevice')) {
                        $vmci++;
                    }elsif($device->isa('VirtualMachineVMIROM')) {
                        $vmi++;
                    }elsif($device->isa('VirtualParallelPort')) {
                        $parallelport++;
                    }elsif($device->isa('VirtualPCIPassthrough')) {
                        $pcipassthrough++;
                    }elsif($device->isa('VirtualPointingDevice')) {
                        $pointingdevice++;
                    }elsif($device->isa('VirtualSCSIPassthrough')) {
                        $scsipassthrough++;
                    }elsif($device->isa('VirtualSerialPort')) {
                        $serialport++;
                    }elsif($device->isa('VirtualSoundCard')) {
                        if($device->isa('VirtualEnsoniq1371')) {
                            $ensoniqsoundcard++;
                        }elsif($device->isa('VirtualSoundBlaster16')) {
                            $blastersoundcard++;
                        }
                    }elsif($device->isa('VirtualUSB')) {
                        $usb++;
                    }
                }
            }
        }
    }
    my $storageCount = $storageProtocol{"iscsi"}{"count"} +
                            $storageProtocol{"fc"}{"count"} +
                            $storageProtocol{"nas"}{"count"} +
                            $storageProtocol{"local"}{"count"};
    #print "Storage protocols are ", Dumper(\%storageProtocol),"\n";
    $data{"vCenter"}{"vCenter_env_info"}{"storage_system_count"}{"local_storage"}{"total"} = 
        $storageProtocol{"local"}{"count"};
    #$data{"vCenter"}{"vCenter_env_info"}{"storage_system_count"}{"local_storage"}{"external"} = 
    #    $usb;
    $data{"vCenter"}{"vCenter_env_info"}{"storage_system_count"}{"network_storage"} = 
        $storageProtocol{"fc"}{"count"} + $storageProtocol{"iscsi"}{"count"} + 
        $storageProtocol{"nas"}{"count"};
    my $nasPercent = ( $storageProtocol{"nas"}{"count"} / $storageCount ) * 100;
    my $fcPercent = ( $storageProtocol{"fc"}{"count"} / $storageCount ) * 100;
    my $iscsiPercent = ( $storageProtocol{"iscsi"}{"count"} / $storageCount ) * 100;
    my $dasPercent = ( $storageProtocol{"local"}{"count"} / $storageCount ) * 100;
    $data{"vCenter"}{"vCenter_env_info"}{"storage_types"}{"nas"}=$nasPercent."%";
    $data{"vCenter"}{"vCenter_env_info"}{"storage_types"}{"fc-san"}=$fcPercent."%";
    $data{"vCenter"}{"vCenter_env_info"}{"storage_types"}{"iscsi-san"}=$iscsiPercent."%";
    $data{"vCenter"}{"vCenter_env_info"}{"storage_types"}{"das"}=$dasPercent."%";
    my @uniqUuids = @{$util->uniq(\@uuids)};
    $data{"vCenter"}{"vCenter_env_info"}{"lun_count"}{"total"} = scalar @uuids;
    $data{"vCenter"}{"vCenter_env_info"}{"lun_count"}{"replicated"} = 
        $#uuids - $#uniqUuids;
    #print Dumper \%data;
    $endTime = time();
    #print "\nHost Storage Info took ".($endTime - $startTime) . " seconds\n\n";
}

# Get vCenter Operations Manager and Similar Solutions info
sub getSolutionManagerInfo{
    $startTime = time();

    my $solMgr = Vim::get_view(
                        mo_ref => Vim::get_service_content()->extensionManager
                    );
    $data{"vCenter"}{"operation_managers"} = []; 
    foreach my $extn (@{$solMgr->extensionList}){
        # if (exists $extn->{"extendedProductInfo"}){
        my %om_details = ();
        next if ($extn->description->label eq "description");
        $om_details{"operation_manager"}{"om_name"} = $extn->description->label;
        my $discovery_source = (split(/=/,$extn))[0];
        $discovery_source = $util->trim($discovery_source);
        if ($discovery_source eq "Extension"){
            $om_details{"operation_manager"}{"om_discovery_source"} = 
                "VMware vCenter: Extension"; 
        } elsif ($discovery_source eq "vApp") {
            $om_details{"operation_manager"}{"om_discovery_source"} = 
                "VMware vCenter: vApp";
        }else {
            $om_details{"operation_manager"}{"om_discovery_source"} = 
                $discovery_source; 
        }
        $om_details{"operation_manager"}{"om_version"} = $extn->version;
        $om_details{"operation_manager"}{"om_description"} = 
            $extn->description->summary;
        push @{$data{"vCenter"}{"operation_managers"}}, \%om_details;
#        }
    }
    #print Dumper $data{"vCenter"}{"operation_managers"};
    $endTime = time();
    print_start_collection("Retrieving Solution Manager Information".
        " (Total Time : ". ($endTime - $startTime) . " seconds)");
    #print "\nSolution Manager Storage Info took " . 
    #    ($endTime - $startTime) . " seconds\n\n";
}

sub getSSDdetails{
    my ($host) = @_;
    $startTime = time();
    # esxcli --server 10.200.59.107 --username Administrator@vsphere.local --password Passw0rd@123 --vihost 10.200.60.31 storage core device list
    # esxcli --server 10.200.59.107 --username Administrator@vsphere.local --password Passw0rd@123 --thumbprint 1F:CE:20:AE:FD:97:42:DA:A7:EC:7F:7E:B2:6D:4E:A2:F3:5A:2C:9C --vihost 10.200.60.31 storage core device list
    my $cmd = "esxcli --server ".$serverAddress." --username ".$username.
        " --password ".$password." --vihost ".$host->name.
        " storage core device list";
    my ($cmdResult,$cmdExit) = $util->run_cmd($cmd);
    my ($vendor, $size, $tmp);
    if (!$cmdExit){
        my @arr = split(/\n/,$cmdResult);
        foreach my $line (@arr){
            if ($line =~ /Vendor:/){
                $tmp = (split(/:/,$line))[1];
                $vendor = $util->trim($tmp);
            }
            # Note that the Size here is in MB
            if ($line =~ /Size:/){
                $tmp = (split(/:/,$line))[1];
                $size = $util->trim($tmp);
            }
            if ($line =~ /Is SSD: true/){
                my %vendorSizeMap = ();
                $vendorSizeMap{"vendor"} = $vendor;
                $vendorSizeMap{"size_in_mb"} = $size;
                $vendorSizeMap{"size_in_bytes"} = $size*1024*1024;
                $vendorSizeMap{"size_in_gb"} = $util->convert_MB_to_GB($size);
                push @{$SSDHash{$host->name}{"SSDs"}}, \%vendorSizeMap;
                $SSDCount{$vendor}{"count"}++;
            }
        }
    }
    #print Dumper \%SSDHash,"\n";
    #print Dumper \%SSDCount,"\n";
    $endTime=time();
    print_start_collection("Retrieving SSD information for host - $host->{name}".
        " (Total Time : ". ($endTime - $startTime) . " seconds)");
    return 1;
}

package Utils;
use strict;
use warnings;
use POSIX qw(ceil);
my $tags="";

sub new{
    my $class = shift;
    my $self = {};
    bless $self, $class;
    return $self;
}

sub trim{
    my ($self, $string) = @_;
    unless ($string){
        return "";
    }
    $string =~s/^\s+//;
    $string =~s/\s+$//;
    $string =~s/\n+$//;
    return $string;
}

# Counts the no of occurence of same hash in the array
sub count_hash_occurences_in_array{
    my ($self, $arrOfHash) = @_;
    my @uniqArr = ();
    foreach my $eleH(@$arrOfHash){
        my $found = 0;
        if (scalar @uniqArr == 0){
            push @uniqArr, $eleH;
        }
        foreach my $ueH(@uniqArr){
            if (exists $ueH->{"storage"} and exists $ueH->{"vendor"}){
                if (($eleH->{"storage"} == $ueH->{"storage"}) and
                    ($eleH->{"vendor"} eq $ueH->{"vendor"})) {
                    $ueH->{"disk_count"}++;
                    $found = 1;
                }
            }
        }
        if (!$found){
            $eleH->{"disk_count"} = 1;
            push @uniqArr, $eleH;
        }
    }
    return \@uniqArr;
}

# arguments:
#       i. Size in bytes
#       ii. 1000 or 1024(optional)
# returns: Size in human readable form e.g. 123K, 2M, 6GB
# SIZE may be (or may be an integer optionally followed by) one of following:
# kB 1000, KB(or KiB) 1024, mB 1000*1000, MB(or MiB) 1024*1024, and so on
# for GB, TB, PB, EB, ZB, YB, XB(Xenotta), SB(Shilentno), DB(Domegemegrotte).
# The International Engineering Community(IEC) has developed a standard in 2000,
# which is sadly being ignored by the computer industry. This standard basically 
# says that 1000 bytes is a kilobyte, 1000KB are one MB and so on. The 
# abbreviations are KB, MB, GB and so on. The widely used 1024 bytes=1kilobyte 
# should instead by called 1024 bytes = 1 Kibibyte (KiB),1024KiB=1Mebibyte(MiB),
# 1024 MiB = 1 Gibibyte (GiB) and so on.
# Basically, that is a mish-mash of the ancient 70s convention of using kB for 
# 1000 Bytes and KB for 1024 Bytes, and an abuse of the SI definitions of M and 
# G prefixes. Actually, there is no mB or gB convention, although that would have 
# been logic in the original convention.
# Unfortunately, Microsoft decided to use the following conventions and now the 
# whole world uses it:

#    1 KB = 1024 Bytes
#    1 MB = 1024 * 1024 Bytes
#    1 GB = 1024 * 1024 * 1024 Bytes.
# So we'll follow the same convention here

sub convert_bytes_to_human_readable{
    my ($self,$size,$division_component) = @_;
    my $div_comp=1024;
    if($division_component && $division_component==1000){
        $div_comp=1000;
    }
    $size = sprintf("%.1f",$size);
    $division_component = sprintf("%.1f",$division_component);
    my %size_map = (
                     1=>{1000=>"kB",1024=>"KB"},
                     2=>{1000=>"mB",1024=>"MB"},
                     3=>{1000=>"gB",1024=>"GB"},
                     4=>{1000=>"tB",1024=>"TB"},
                     5=>{1000=>"pB",1024=>"PB"},
                     6=>{1000=>"eB",1024=>"EB"},
                     7=>{1000=>"zB",1024=>"ZB"},
                     8=>{1000=>"yB",1024=>"YB"},
                     9=>{1000=>"xB",1024=>"XB"}
                   );
    my $i=0;
    unless($size){
        return "-";
    }
    while ($size >= $div_comp){
        $size = $size/$div_comp;
        $i++;
    }

    # If we see the output of df and df -h, we can notice that
    # linux converts the next integer while converting to GB/MB
    # instead of showing two/more decimals. Hence the following
    # line is commented and POSIX ceil is used here
    #my $human_readable_size = sprintf("%.2f",$size);
    #print "size=$size\n";
    #print "i=$i\n";
    #print "div_component=$div_comp\n";
    #my $human_readable_size = ceil($size)." ".$size_map{$i}{$div_comp};
    my $newSize = sprintf("%.3f", $size);
    my $human_readable_size = $newSize." ".$size_map{$i}{$div_comp};
    return $human_readable_size;
}

# Input: Size in MB
# Output: Size in GB
sub convert_MB_to_GB{
    my ($self,$size_in_mb) = @_;
    $size_in_mb = sprintf("%.1f", $size_in_mb);
    my $size_in_gb = $size_in_mb/1024.0;
    #$size_in_gb = ceil($size_in_gb);
    $size_in_gb = sprintf("%.3f", $size_in_gb);
    return $size_in_gb;
}

sub uniq{
    my ($self, $elements) = @_;

    my %seen = ();
    my @uniqElements = ();
    foreach my $item (@$elements) {
        unless ($seen{$item}) {
            $seen{$item} = 1;
            push(@uniqElements, $item);
        }
    }
    return \@uniqElements;
}

sub generateTags{
    my ($self, $HOH) = @_;
    if (scalar (keys %$HOH)){
        foreach my $k (keys %$HOH){
            if (ref $HOH->{$k} eq "ARRAY" and scalar @{$HOH->{$k}})
            {
                $tags .= "\n<$k>";
                foreach my $k2 (@{$HOH->{$k}}){
                    $self->generateTags($k2);
                }
                $tags .= "\n</$k>";
            } else {
                $self->tagging($HOH->{$k},$k);
           }
        }
    }
    return $tags;
}

sub tagging{
    my ($self, $H,$k) = @_;
    if (ref $H eq "HASH")
    {
        $tags .= "\n<$k>";
        $self->generateTags($H);
        $tags .= "\n</$k>";
    } else {
        $tags .= "\n  <$k>";
        if (defined $H){
            if (ref $H eq "ARRAY" and scalar @$H == 0){
                $tags .= "";
            } else {
                $tags .= $H;
            }
        }
        $tags .= "</$k>";
    }
}

sub getDateTime{
    my ($self) = @_;
    my %dttime = ();
    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);

    $dttime{year }  = sprintf "%04d",($year + 1900);  ## four digits to specify the year
    $dttime{mon  }  = sprintf "%02d",($mon + 1);      ## zeropad months
    $dttime{mday }  = sprintf "%02d",$mday;           ## zeropad day of the month
    $dttime{wday }  = sprintf "%02d",$wday + 1;       ## zeropad day of week; sunday = 1;
    $dttime{yday }  = sprintf "%02d",$yday;           ## zeropad nth day of the year
    $dttime{hour }  = sprintf "%02d",$hour;           ## zeropad hour
    $dttime{min  }  = sprintf "%02d",$min;            ## zeropad minutes
    $dttime{sec  }  = sprintf "%02d",$sec;            ## zeropad seconds
    $dttime{isdst}  = $isdst;

    return "$dttime{year}-$dttime{mon}-$dttime{mday} $dttime{hour}:$dttime{min}:$dttime{sec}";
}

sub getReportGenerationTags{
    my ($self) = @_;
    my %reportTags = ();
    $reportTags{"REPORT"}{"REPORTTIME"} = $self->getDateTime;
    $reportTags{"REPORT"}{"VERSION"} = "1.0";
    return \%reportTags;
}

sub getReportName{
    my ($self) = @_;
    my $timeStamp = $self->getDateTime;#2016-01-18 15:41:02
    $timeStamp =~ s/-//g;
    $timeStamp =~ s/://g;
    $timeStamp =~ s/\s+/_/g;
    $self->{"reportName"} = "VEAT_REPORT_".$timeStamp;
    return $self->{"reportName"};
}

sub writeToXml{
    my ($self,$fileName,$xmlContents) = @_;
    my $string = "<?xml version=\"1.0\" ?>";
    open (FH, ">", $fileName);
    print FH $string; 
    print FH $xmlContents;
    close FH;
    $self->{"reportFileName"} = $fileName;
}

# Returns result and exit code
# exit code 0 in case of command success and nonzero in case of failure
sub run_cmd{
    my ($self,$cmd) = @_;
    my $result = `$cmd 2>&1`;
    return ($result, $?);
}
sub printHeading_stdout{
    my ($self, $str) = @_;
    my @charArr = split(//,$str);
    my $charCnt = scalar @charArr;
    print "\n",$str,"\n","-" x $charCnt,"\n";
}
sub printHeading{
    my ($self, $str) = @_;
    my @charArr = split(//,$str);
    my $charCnt = scalar @charArr;
    print $fh "\n",$str,"\n","-" x $charCnt,"\n";
}

sub getCeiledDivVal{
    my ($self, $val1, $val2) = @_;
    my $float1 = sprintf '%.2f', $val1; 
    my $float2 = sprintf '%.2f', $val2;
    return ceil($float1/$float2);
}
1;
