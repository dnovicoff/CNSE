#!/usr/bin/perl

use warnings;
use strict;

use JSON;
use Storable;
use Text::CSV;
use IPC::Open3;
use IO::Socket::INET;
use Net::Ping::External;
use Excel::Writer::XLSX;
use Excel::Writer::XLSX::Utility;
use Getopt::Long;

my $dry_run = 0;

my @patch_management_servers = qw(its081pl9rhp its193pl5sat its318pl5mgmt its320pl5mgmt its378pl5mgmt its406pl5mgmt its407pl5mgmt its423pl5mgmt its625ml5sat its627ml6sat itsdchrhel5-7gold itsdchrhel6-6gold itsdchrhel7-1gold);

GetOptions("dry-run" => \$dry_run) or die("Error in command line arguments\n");

use constant PARALLEL_PROCS => 10;

# Don't use SSH agent, too slow and buggy
delete $ENV{"SSH_AUTH_SOCK"};

my $script_functions = <<'__EOL__';

use IO::Socket::INET;
use strict;

sub run_command {
    my $label = shift;
    my $command = shift;
    my $output = qx($command);
    chomp $output;
    print "${label}=${output}\n";
}

sub run_command_code {
    my $label = shift;
    my $command = shift;
    my $output = qx($command);
    my $ret = $? >> 8;
    if ($ret == 0) {
        print "${label}=1\n";
    } else {
        print "${label}=0\n";
    }
}

sub check_process {
    my $label = shift;
    my $proc = shift;
    run_command_code($label, "pgrep $proc > /dev/null");
}

sub check_rpm {
    my $label = shift;
    my $rpm = shift;
    run_command_code($label, "rpm -q $rpm > /dev/null 2>&1");
}

sub check_port {
    my $label = shift;
    my $host = shift;
    my $port = shift;
    my $sock = IO::Socket::INET->new(
        PeerAddr => $host,
        PeerPort => $port,
        Proto => 'tcp',
        Timeout => 5,
    );
    if (defined $sock) {
        print "${label}=1\n";
    } else {
        print "${label}=0\n";
    }
}

__EOL__

my $script_admin = "$script_functions\n" . <<'__EOL__';
run_command "success", "echo 1";
run_command "hostname", "hostname -s";
run_command "ips", "/sbin/ip addr | grep 'inet ' | grep -v 'host lo' | awk '{print \$2}' | cut -d/ -f1 | tr -s '\n' ',' | sed -e 's/,\$//'";
run_command "ipv6", "/sbin/ip addr | grep ' inet6 ' | wc -l";
check_process "netmanproc", "NetworkManager";
run_command_code "netmanstartup", "/sbin/chkconfig --list NetworkManager | grep ':on'";
run_command "date", "date +%s";
run_command "itmproc", "ps -ef | grep \"/opt/tivoli/itm\" | grep -v grep | wc -l";
run_command_code "itmfile", "[ -f /opt/tivoli/itm/bin/ITMhostName ]";
run_command "auditmtab", "cat /etc/mtab | grep ' /var/log/audit ' | wc -l";
run_command "auditdisk", "df -P -l --block-size=1M | grep ' /var/log/audit\$'";
run_command "lsbrelease", "(test -r /etc/centos-release && cat /etc/centos-release) || (test -r /etc/oracle-release && cat /etc/oracle-release) || (test -r /etc/SuSE-release && head -n 1 /etc/SuSE-release) || (test -x /usr/bin/lsb_release && lsb_release -d) || (test -r /etc/redhat-release && cat /etc/redhat-release)";
run_command "HWManufacturer", "sudo dmidecode | grep -e 'Manufacturer' | head -1";
run_command "HWProductName", "sudo dmidecode | grep -e 'Product Name' | head -1";
run_command "HWSerialNumber", "sudo dmidecode | grep -e 'Serial Number' | head -1";
__EOL__

my $script_primary = "$script_admin\n" . <<'__EOL__';
check_rpm "chefrpm", "chef";
check_port "chef443", "10.108.64.124", 443;
check_port "spacewalk80", "10.108.64.125", 80;
check_port "spacewalk443", "10.108.64.125", 443;
check_port "spacewalk5222", "10.108.64.125", 5222;
check_process "ossecproc", "ossec";
check_rpm "ossecrpm", "ossec-hids-client";
check_port "ossecprod1515", "10.108.111.67", 1515;
check_port "ossecnonprod1515", "10.108.220.129", 1515;
check_process "zabbixproc", "zabbix_agentd";
check_rpm "zabbixrpm", "zabbix-agent";
check_port "zabbixproxy10051", "10.108.111.56", 10051;
check_port "syslogprod514", "10.108.111.66", 514;
check_port "syslognonprod514", "10.108.220.128", 514;
check_port "mgmtproxy80", "10.108.64.241", 80;
__EOL__

sub validate_headers {
    my $filename = shift;
    my $row = shift;
    my $headers = shift;
    if (!defined $row || scalar(@$row) == 0) {
        die "No headers found in $filename\n";
    }
    if (scalar(@$row) != scalar(@$headers)) {
        die "Header mismatch in $filename - expected ".scalar(@$headers).", got ".scalar(@$row)."\n";
    }

    for (my $i=0; $i < @$headers; $i++) {
        my $column = $$row[$i];
        my $header = $$headers[$i];
        if ($column ne $header) {
            die "Header mismatch in $filename - expected $header, got $column\n";
        }
    }
}

sub check_icmp {
    my $host = shift;
    unless ($host) {
        warn "check_icmp(): host cannot be empty!\n";
        return 3;
    }
    my $res = Net::Ping::External::ping(hostname => $host, timeout => 5);
    my $code = $res ? 0 : 1;
    return $code;
}

sub check_port {
    my $host = shift;
    my $port = shift;
    unless ($host) {
        warn "check_port(): host cannot be empty!\n";
        return 3;
    }
    unless ($port) {
        warn "check_port(): port cannot be empty!\n";
        return 3;
    }
    unless ($port =~ m/^\d+$/) {
        warn "check_port(): port must be a valid number: $port\n";
        return 3;
    }
    if ($port < 1 || $port > 65535) {
        warn "check_port(): port must be between 1 and 65535: $port\n";
        return 3;
    }
    my $sock = IO::Socket::INET->new(
        PeerAddr => $host,
        PeerPort => $port,
        Proto => 'tcp',
        Timeout => 2,
    );
    my $ret = defined $sock ? 0 : 1;
    return $ret;
}

sub headless_ssh {
    my $host = shift;
    my $command = shift;

    return _headless_ssh_internal($host, $command, -1);
}

sub headless_ssh_script {
    my $host = shift;
    my $interpreter = shift;
    my $script = shift;
    my $timeout = shift;

    my $pid = -1;
    my $output = '';
    my @ssh_options = ("-o UserKnownHostsFile=/dev/null", "-o StrictHostKeyChecking=no", "-o ConnectTimeout=5", "-o PasswordAuthentication=no", "-o BatchMode=yes", "-o IdentitiesOnly=yes", "-o IdentityFile=~/.ssh/id_rsa", "-o ForwardX11=no", "-o ForwardX11Trusted=no", "-o ProxyCommand=none");

    eval {
        local $SIG{ALRM} = sub { die "alarm\n"; };
        alarm $timeout;
        $pid = open3(*WTR, *RDR, *ERR, "ssh", @ssh_options, $host, $interpreter);

        print WTR $script;

        close WTR;

        waitpid($pid, 0);

        while (<RDR>) {
            chomp;
            $output .= "$_\n";
        }

        close RDR;
        close ERR;

        alarm 0;
    };
    if ($@) {
        if ($@ eq "alarm\n") {
            if ($pid != -1) {
                kill 'KILL', $pid;
            }
        } else {
            die
        }
    }

    chomp $output;
    return $output;
}

sub headless_ssh_timeout {
    my $host = shift;
    my $command = shift;
    my $timeout = shift;

    return _headless_ssh_internal($host, $command, $timeout);
}

sub _headless_ssh_internal {
    my $host = shift;
    my $command = shift;
    my $timeout = shift;

    my $pid = -1;
    my $output = '';
    my @ssh_options = ("-n", "-o UserKnownHostsFile=/dev/null", "-o StrictHostKeyChecking=no", "-o ConnectTimeout=5", "-o PasswordAuthentication=no", "-o BatchMode=yes", "-o IdentitiesOnly=yes", "-o IdentityFile=~/.ssh/id_rsa", "-o ForwardX11=no", "-o ForwardX11Trusted=no", "-o ProxyCommand=none");

    if ($timeout > 0) {
        eval {
            local $SIG{ALRM} = sub { die "alarm\n"; };
            alarm $timeout;
            $pid = open3(*WTR, *RDR, *ERR, "ssh", @ssh_options, $host, $command);
            while (<RDR>) {
                chomp;
                $output .= "$_\n";
            }
            alarm 0;
        };
        if ($@) {
            if ($@ eq "alarm\n") {
                if ($pid != -1) {
                    kill 'KILL', $pid;
                }
            } else {
                die
            }
        }
    } else {
        $pid = open3(*WTR, *RDR, *ERR, "ssh", @ssh_options, $host, $command);
        while (<RDR>) {
            chomp;
            $output .= "$_\n";
        }
    }

    chomp $output;

    close WTR;
    close RDR;
    close ERR;

    waitpid($pid, 0);

    return $output;
}

sub ssh_check_remote_port {
    my $srchost = shift;
    my $dsthost = shift;
    my $dstport = shift;
    unless ($srchost) {
        warn "ssh_check_remote_port(): src_host cannot be empty!\n";
        return 3;
    }
    unless ($dsthost) {
        warn "ssh_check_remote_port(): dst_host cannot be empty!\n";
        return 3;
    }
    unless ($dstport) {
        warn "ssh_check_remote_port(): dst_port cannot be empty!\n";
        return 3;
    }
    unless ($dstport =~ /^\d+$/) {
        warn "ssh_check_remote_port(): dst_port must be a valid number: $dstport\n";
        return 3;
    }
    if ($dstport < 1 || $dstport > 65535) {
        warn "ssh_check_remote_port(): dst_port must be between 1 and 65535: $dstport\n";
        return 3;
    }
    my $output = headless_ssh_timeout($srchost, "bash -c \"cat < /dev/null 2> /dev/null > /dev/tcp/$dsthost/$dstport\" && echo 1", 5);
    return $output eq "1";
}

sub get_status_block {
    my $service = shift;
    my $status = shift;
    return "$service $status";
}

sub get_status_icmp {
    my $host = shift;
    my $service = "ICMP";
    my $code = check_icmp($host);
    if ($code == 0) {
        return get_status_block($service, "UP");
    } else {
        return get_status_block($service, "DOWN");
    }
}

sub get_status_remote_port {
    my $service = shift;
    my $code = shift;
    if ($code) {
        return get_status_block($service, "OPEN");
    } else {
        return get_status_block($service, "CLOSE");
    }
}

sub get_status_ssh_remote_port {
    my $service = shift;
    my $srchost = shift;
    my $dsthost = shift;
    my $dstport = shift;
    my $code = ssh_check_remote_port($srchost, $dsthost, $dstport);
    if ($code) {
        return get_status_block($service, "OPEN");
    } else {
        return get_status_block($service, "CLOSE");
    }
}

sub get_status_ssh {
    my $host = shift;
    my $service = "SSH";
    my $ret = check_port($host, 22);
    if ($ret == 0) {
        my $output = headless_ssh($host, "echo 1");
        if ($output eq "1") {
            my $status = get_status_block($service, "UP");
            return ($status, 1);
        } else {
            my $status = get_status_block($service, "AUTH");
            return ($status, 0);
        }
    } else {
        my $status = get_status_block($service, "DOWN");
        return ($status, 0);
    }
}

sub get_status_hostname {
    my $hostname = shift;
    my $real_hostname = shift;
    my $service = "HOSTNAME";
    $real_hostname = lc($real_hostname);
    $hostname = lc($hostname);
    if ($real_hostname eq $hostname) {
        return get_status_block($service, "OK");
    } else {
        if ($hostname =~ m/^[a-z]{3}[0-9]{3}/ && substr($real_hostname, 0, 6) eq substr($hostname, 0, 6)) {
            return get_status_block($service, "WARN");
        } else {
            return get_status_block($service, "BAD");
        }
    }
}

sub check_ips {
    my $hostname = shift;
    my $host_ips = shift;
    my $real_ips = shift;
    my @iplist = map { $_->{ip} } @$host_ips;
    foreach my $ip (split(/,/, $real_ips)) {
        # Exception for clustered IP
        if (lc($hostname) eq 'its323pl5mgmt' || lc($hostname) eq 'its322pl5mgmt') {
            if ($ip eq '10.108.19.55') {
                next;
            }
        }
        unless (grep(/^\Q$ip\E$/, @iplist)) {
            if ($ip !~ /^127\./ && $ip !~ /^192\.168\./) {
                return 0;
            }
        }
    }
    return 1;
}

sub get_status_ips {
    my $hostname = shift;
    my $host_ips = shift;
    my $real_ips = shift;
    my $service = "IPs";
    my $ret = check_ips($hostname, $host_ips, $real_ips);
    if ($ret) {
        return get_status_block($service, "OK");
    } else {
        return get_status_block($service, "BAD");
    }
}

sub get_status_ipv6 {
    my $ipv6 = shift;
    my $service = "IPv6";
    if ($ipv6) {
        return get_status_block($service, "ON");
    } else {
        return get_status_block($service, "OFF");
    }
}

sub get_status_date {
    my $date = shift;
    my $service = "Date";
    if ($date =~ m/^\d+$/) {
        my $delta = abs($date - time());
        if ($delta < 600) {
            return get_status_block($service, "OK");
        } else {
            return get_status_block($service, "BAD");
        }
    } else {
        return get_status_block($service, "BAD");
    }
}

sub get_status_chef {
    my $chefrpm = shift;
    my $chef_server = shift;
    my $service = "Chef";
    if ($chef_server) {
        return get_status_block($service, "OK");
    } elsif ($chefrpm) {
        return get_status_block($service, "SETUP");
    } else {
        return get_status_block($service, "RPM");
    }
}

sub get_status_chef_offline {
    my $chef_server = shift;
    my $service = "Chef";
    if ($chef_server) {
        return get_status_block($service, "OK");
    } else {
        return get_status_block($service, "UNKNOWN");
    }
}

sub get_status_spacewalk {
    my $spacewalk_server = shift;
    my $os = shift;
    my $service = "Spacewalk";
    if ($spacewalk_server) {
        return get_status_block($service, "OK");
    } else {
        if ($os =~ m/^Red Hat Enterprise Linux (?:5|6|7)/i) {
            return get_status_block($service, "BAD");
        } else {
            return "";
        }
    }
}

sub get_patches_spacewalk {
    my $spacewalk_server = shift;
    if ($spacewalk_server) {
        return $spacewalk_server->{patches};
    } else {
        return -1;
    }
}

sub get_status_hardware_manufacturer  {
    my $results = shift;
    my $service = "HWManufacturer";
    if ($results)  {
        $results =~ s/\s*//g;
	$results =~ s/^Manufacturer://g;
    }  else  {
        $results = "Not Known";
    }
   return get_status_block("", $results);
}

sub get_status_hardware_product_name  {
    my $results = shift;
    my $service = "HWProductName";
    if ($results)  {
        $results =~ s/\s*//g;
	$results =~ s/^ProductName://g;
    }  else  {
        $results = "Not Known";
    }
   return get_status_block("", $results);
}

sub get_status_hardware_serial_number  {
    my $results = shift;
    my $service = "HWSerialNumber";
    if ($results)  {
        $results =~ s/\s*//g;
	$results =~ s/^SerialNumber://g;
    }  else  {
        $results = "Not Known";
    }
   return get_status_block("", $results);
}

sub get_status_ossec {
    my $ossecproc = shift;
    my $ossecrpm = shift;
    my $service = "OSSEC";
    if ($ossecproc) {
        return get_status_block($service, "OK");
    } elsif($ossecrpm) {
        return get_status_block($service, "SETUP");
    } else {
        return get_status_block($service, "RPM");
    }
}

sub get_status_network_manager {
    my $netmanproc = shift;
    my $netmanstartup = shift;
    my $service = "NM";
    if ($netmanstartup) {
        return get_status_block($service, "ENABLED");
    } elsif ($netmanproc) {
        return get_status_block($service, "RUNNING");
    } else {
        return get_status_block($service, "DISABLED");
    }
}

sub get_status_auditd {
    my $auditmtab = shift;
    my $auditdisk = shift;
    my $service = "Auditd";
    if ($auditmtab =~ m/^\d+$/ && $auditmtab > 0) {
        $auditdisk = trim($auditdisk);
        my @diskparts = split(/\s+/, $auditdisk);
        if (scalar(@diskparts) > 1 && $diskparts[1] =~ m/^\d+$/ && $diskparts[1] >= 4500) {
            return get_status_block($service, "OK");
        } else {
            return get_status_block($service, "RESIZE");
        }
    } else {
        return get_status_block($service, "MISSING");
    }
}

sub get_lsb_release {
    my $lsbrelease = shift;
    $lsbrelease = '' if not defined $lsbrelease;
    $lsbrelease =~ s/^\s*Description:\s+//s;

    return $lsbrelease;
}

sub get_status_zabbix {
    my $zabbixrpm = shift;
    my $zabbix_server = shift;
    my $host = shift;
    my $service = "Zabbix Agent";
    if (defined $zabbix_server) {
        return get_status_block($service, "OK");
    } elsif($zabbixrpm) {
        return get_status_block($service, "SETUP");
    } else {
        return get_status_block($service, "RPM");
    }
}

sub get_status_itm {
    my $itmproc = shift;
    my $itmfile = shift;
    my $service = "ITM";
    if ($itmproc =~ m/^\d+$/ && $itmproc > 0) {
        return get_status_block($service, "OK");
    } else {
        if ($itmfile ne "1") {
            return get_status_block($service, "MISSING");
        } else {
            return get_status_block($service, "SETUP");
        }
    }
}

sub get_admin_ip {
    my $host_ips = shift;
    # Check for admin IP
    foreach my $info (@$host_ips) {
        my $iptype = $info->{iptype};
        if (lc($iptype) eq 'admin') {
            return $info->{ip};
        }
    }
    return undef;
}

sub get_primary_ip {
    my $host_ips = shift;
    if (scalar @$host_ips == 1) {
        my $info = $$host_ips[0];
        if (lc($info->{iptype}) ne 'admin') {
            return $info->{ip};
        }
    }

    # Try for Primary IP
    my $hostinfo = undef;
    foreach my $info (@$host_ips) {
        my $iptype = $info->{iptype};
        if (lc($iptype) eq 'primary') {
            # Multiple Primary IPs, something is wrong
            if (defined $hostinfo) {
                return undef;
            } else {
                $hostinfo = $info;
            }
        }
    }
    return $hostinfo->{ip};
}

sub get_chef_servers {
    my $workstation_ip = shift;
    my $chef_servers = shift;

    my $command = qq{knife search "*:*" --format json -a name -a hostname -a patchgroup};

    my $output = headless_ssh_timeout($workstation_ip, $command, 300);
    my $output_decoded = decode_json($output);

    foreach my $entry (@{$output_decoded->{rows}}) {
        foreach my $key (keys %{$entry}) {
            my $row = $entry->{$key};
            my $chefname = lc($row->{name});
            my $hostname = $row->{hostname} ? lc($row->{hostname}) : '';
            my $patchgroup = $row->{patchgroup} ? $row->{patchgroup} : '';
            if (lc($patchgroup) eq 'unsorted') {
                $patchgroup = "";
            }
            $chef_servers->{$hostname} = { hostname => $hostname, patchgroup => $patchgroup, chefname => $chefname };
        }
    }
}

sub get_spacewalk_servers {
    my $spacewalk_ip = shift;
    my $spacewalk_servers = shift;

    my $script = <<'__EOL__';
use warnings;
use strict;

use DBI;

my $dbh = DBI->connect("dbi:Pg:dbname=rhnschema;host=localhost", "rhnuser", "rhnpw", { RaiseError => 1 });

#(SELECT sg.name FROM rhnservergroup sg JOIN rhnservergroupmembers sgm ON (sg.id = sgm.server_group_id) WHERE sg.group_type IS NULL AND sgm.server_id = s.id) AS group_name,

my $sth = $dbh->prepare(qq{SELECT s.name AS server_name,
(SELECT count(DISTINCT p.name_id) as count FROM rhnpackage p, rhnserverneededpackagecache snpc WHERE snpc.server_id = s.id AND p.id = snpc.package_id) AS outdated_packages FROM rhnserver s});

$sth->execute;
while (my $row = $sth->fetchrow_hashref) {
    my $server_name = $row->{server_name};
    my $outdated_packages = $row->{outdated_packages};
    print "$server_name|$outdated_packages\n";
}

$dbh->disconnect;
__EOL__

    my $output = headless_ssh_script($spacewalk_ip, "/usr/bin/perl", $script, 300);
    open my $spacewalk_fh, '<', \$output or die $!;
    while (my $row = <$spacewalk_fh>) {
        chomp $row;
        my @parts = split(/\|/, $row);
        my $hostname = $parts[0];
        my $patches = $parts[1];
        $spacewalk_servers->{lc($hostname)} = { hostname => $hostname, patches => $patches };
    }
    close $spacewalk_fh;
}

sub get_zabbix_servers {
    my $zabbix_ip = shift;
    my $zabbix_servers = shift;

    my $script = <<'__EOL__';
use warnings;
use strict;

use DBI;

my $dbh = DBI->connect("dbi:Pg:dbname=zabbix;host=localhost", "zabbix", "DWtN9qnBqcHDPTz3", { RaiseError => 1 });

my $sth = $dbh->prepare(qq{SELECT host FROM hosts WHERE available != 0});

$sth->execute;
while (my $row = $sth->fetchrow_hashref) {
    my $host = $row->{host};
    print "$host\n";
}

$dbh->disconnect;
__EOL__

    my $output = headless_ssh_script($zabbix_ip, "/usr/bin/perl", $script, 300);
    open my $zabbix_fh, '<', \$output or die $!;
    while (my $row = <$zabbix_fh>) {
        chomp $row;
        my @parts = split(/\|/, $row);
        my $host = $parts[0];
        $zabbix_servers->{lc($host)} = { host => $host };
    }
    close $zabbix_fh;
}

sub get_server_results {
    my $host = shift;
    my $script = shift;
    my $output = headless_ssh_script($host, "/usr/bin/perl", $script, 120);
    my %hash = ();
    open my $fh, '<', \$output or die $!;

    while (my $row = <$fh>) {
        chomp $row;
        my @parts = split(/=/, $row);
        
        $hash{$parts[0]} = $parts[1]; 
    }
    close $fh or die $!;
    return %hash;
}

sub read_csv_data {
    my $csv_file = shift;
    open my $csv_fh, "<", $csv_file or die $!;
    my $csv = Text::CSV->new( { binary => 1, eol => $/ }) or die Text::CSV->error_diag();
    validate_headers($csv_file, $csv->getline($csv_fh),
        [ "svr_name", "svr_sys_class_name", "svr_os", "svr_support_group", "svr_short_description", "ip_name", "ip_u_ip_type", "svr_u_owner_department", "svr_u_billing_department", "svr_u_patch_level", "svr_location", "svr_u_type", "svr_start_date" ]);

    my $data = {
        linux_servers => [],
        zlinux_servers => [],
        engineering_servers => [],
        uniteny_servers => [],
        appliances => [],
    };

    my $ip_data = {};

    # Read in CSV Data
    while (my $row = $csv->getline($csv_fh)) {
        my $server_name = trim($row->[0]);
        my $server_class = trim($row->[1]);
        my $os = trim($row->[2]);
        my $support_group = trim($row->[3]);
        my $description = trim($row->[4]);
        my $ip = trim($row->[5]);
        my $iptype = trim($row->[6]);
        my $owner_dept = trim($row->[7]);
        my $billing_dept = trim($row->[8]);
        my $patchlevel = trim($row->[9]);
        my $location = trim($row->[10]);
        my $svrtype = trim($row->[11]);
        my $start_date = trim($row->[12]);

        my $data_entry = {
            server_name   => $server_name,
            server_class  => $server_class,
            os            => $os,
            support_group => $support_group,
            description   => $description,
            owner_dept    => $owner_dept,
            billing_dept  => $billing_dept,
            patchlevel    => $patchlevel,
            location      => $location,
            svrtype       => $svrtype,
            start_date    => $start_date,
        };

        if (!exists $ip_data->{$server_name}) {
            $ip_data->{$server_name} = [];

            if ($server_class =~ m/appliance/i) {
                push @{$data->{appliances}}, $data_entry;
            } elsif ($support_group =~ m/engineer/i) {
                push @{$data->{engineering_servers}}, $data_entry;
            } elsif ($billing_dept =~ m/uniteny/i) {
                push @{$data->{uniteny_servers}}, $data_entry;
            } elsif ($support_group =~ m/zLinux/i) {
                push @{$data->{zlinux_servers}}, $data_entry;
            } else {
                push @{$data->{linux_servers}}, $data_entry;
            }
        }

        if ($ip) {
            # Check if IP is previously recorded
            unless (grep { $_ eq $ip } map { $_->{ip} } @{$ip_data->{$server_name}}) {
                push @{$ip_data->{$server_name}}, { ip => $ip, iptype => $iptype };
            }
        }
    }

    close $csv_fh;

    # Fill IP Data
    foreach my $key (keys %{$data}) {
        foreach my $server (@{$data->{$key}}) {
            my $server_ips = $ip_data->{$server->{server_name}};

            $server->{admin_ip} = get_admin_ip($server_ips);
            $server->{primary_ip} = get_primary_ip($server_ips);
            $server->{server_ips} = $server_ips;
            my @addrs = map { $_->{iptype}.':'.$_->{ip} } @$server_ips;
            $server->{server_ips_text} = join(' - ', @addrs);
        }
    }

    return $data;
}

sub get_missing_ips {
    my $csv_data = shift;

    my $missing_ips = [];
    my @hosts = sort { lc($a->{server_name}) cmp lc($b->{server_name}) } @{$csv_data->{linux_servers}};

    foreach my $host (@hosts) {
        my $admin_ip = $host->{admin_ip};
        my $primary_ip = $host->{primary_ip};

        if ((!defined $admin_ip) && (!defined $primary_ip)) {
            push @{$missing_ips}, $host;
        }
    }

    return $missing_ips;
}

sub process_linux_servers {
    my $csv_data = shift;
    my $columns = shift;
    my $chef_servers = shift;
    my $spacewalk_servers = shift;
    my $zabbix_servers = shift;
    my $patching_servers = shift;

    my $results = {};
    my $processes = {};

    my @hosts = sort { lc($a->{server_name}) cmp lc($b->{server_name}) } @{$csv_data->{linux_servers}};


    foreach my $host (@hosts) {
	print "Process Linux Servers: ".$host->{server_name}."\n";
        # Block and wait for process to finish if more than PARALLEL_PROCS are spawned
        process_results($processes, PARALLEL_PROCS, $columns, $results);

        my $server_name = $host->{server_name};

        if (defined $host->{admin_ip} || defined $host->{primary_ip}) {
            my $chef_server = undef;
            if (exists $chef_servers->{lc($server_name)}) {
                $chef_server = $chef_servers->{lc($server_name)};
            }

            my $spacewalk_server = undef;
            if (exists $spacewalk_servers->{lc($server_name)}) {
                $spacewalk_server = $spacewalk_servers->{lc($server_name)};
            } elsif (grep(/^\Q$server_name\E$/i, @$patching_servers)) {
                $spacewalk_server = {
                    hostname => $server_name,
                    patches  => 0,
                };
            }

            my $zabbix_server = undef;
            if (exists $zabbix_servers->{lc($server_name)}) {
                $zabbix_server = $zabbix_servers->{lc($server_name)};
            }

            if ($dry_run) {
                my $mem = '';
                open(my $psuedo_fh, '+<', \$mem) or die $!;

                $processes->{-1} = $psuedo_fh;

                check_server($psuedo_fh, $host, $chef_server, $spacewalk_server, $zabbix_server);

                seek($psuedo_fh, 0, 0);
            } else {
                # Create pipe for IPC between parent and child processes
                pipe(my $reader_fh, my $writer_fh);
                # Running check_server() in child process to run multiple server concurrently
                my $pid = fork();
                if ($pid) {
                    $processes->{$pid} = $reader_fh;
                    close $writer_fh;
                } elsif ($pid == 0) {
                    close $reader_fh;
                    check_server($writer_fh, $host, $chef_server, $spacewalk_server, $zabbix_server);
                    close $writer_fh;
                    exit;
                }
            }
        }
    }

    # Collect results for all remaining processes
    process_results($processes, 1, $columns, $results);

    return $results;
}

sub have_os_patches {
    my $os = shift;

    if ($os =~ m/^Red Hat Enterprise Linux (\d+)/i) {
        if ($1 >= 5) {
            return 1;
        }
    }

    return 0;
}

sub is_patchable_os {
    my $os = shift;

    if ($os =~ m/^Red Hat Enterprise Linux (\d+)/i) {
        if ($1 >= 4) {
            return 1;
        }
    } elsif ($os =~ m/^Oracle Linux Server (\d+)/i) {
        if ($1 >= 5) {
            return 1;
        }
    } elsif ($os =~ m/^SUSE Linux (\d+)/i) {
        if ($1 >= 10) {
            return 1;
        }
    }
    return 0;
}

sub is_unsupported {
    my $os = shift;

    if ($os =~ m/^Red Hat Enterprise Linux (\d+)/i) {
        if ($1 < 5) {
            return 1;
        }
    } elsif ($os =~ m/^Oracle Linux Server (\d+)/i) {
        if ($1 < 5) {
            return 1;
        }
    } elsif ($os =~ m/^SUSE Linux (\d+)/i) {
        if ($1 < 11) {
            return 1;
        }
    } elsif ($os =~ m/^CentOS/i) {
        return 1;
    }
    return 0;
}

sub process_patching_linux_results {
    my $linux_results = shift;
    my $missing_results = shift;

    my $patching_results = {};

    foreach my $key (keys %{$linux_results}) {
        my $data = $linux_results->{$key};
        my $server_name = $data->{server_name};
        my $location = $data->{location};
        my $patches = $data->{spacewalk_patches};
        my $os = $data->{os};
        my $billing_dept = $data->{billing_dept};

        if (!defined $patching_results->{$location}) {
            $patching_results->{$location} = {};
        }

        if (!defined $patching_results->{$location}->{$billing_dept}) {
            $patching_results->{$location}->{$billing_dept} = {
                location          => $location,
                billing_dept      => $billing_dept,
                patched           => 0,
                patching_underway => 0,
                under_review      => 0,
                unsupported       => 0,
            };
        }

        my $location_patches = $patching_results->{$location}->{$billing_dept};

        if (is_patchable_os($os)) {
            if ($patches >= 0) {
                if (is_unsupported($os)) {
                    $$location_patches{unsupported}++;
                } else {
                    $$location_patches{patched}++;
                }
            } elsif (have_os_patches($os)) {
                $$location_patches{patching_underway}++;
            } else {
                $$location_patches{under_review}++;
            }
        } elsif (is_unsupported($os)) {
            $$location_patches{unsupported}++;
        } else {
            $$location_patches{under_review}++;
        }
    }

    foreach my $data (@$missing_results) {
        my $location = $data->{location};
        my $os = $data->{os};
        my $billing_dept = $data->{billing_dept};

        if (!defined $patching_results->{$location}) {
            $patching_results->{$location} = {};
        }

        if (!defined $patching_results->{$location}->{$billing_dept}) {
            $patching_results->{$location}->{$billing_dept} = {
                location          => $location,
                billing_dept      => $billing_dept,
                patched           => 0,
                patching_underway => 0,
                under_review      => 0,
                unsupported       => 0,
            };
        }

        my $location_patches = $patching_results->{$location}->{$billing_dept};

        if (is_patchable_os($os)) {
            if (have_os_patches($os)) {
                $$location_patches{patching_underway}++;
            } else {
                $$location_patches{under_review}++;
            }
        } elsif (is_unsupported($os)) {
            $$location_patches{unsupported}++;
        } else {
            $$location_patches{under_review}++;
        }
    }

    return $patching_results;
}

sub process_servers_by_location {
    my $data = shift;

    my $results = {};

    foreach my $entry (@$data) {
        my $location = $entry->{location};
        if (!defined $results->{$location}) {
            $results->{$location} = {
                location    => $location,
                total       => 0,
            };
        }

        my $result = $results->{$location};
        $$result{total}++;
    }

    return $results;
}

sub check_server {
    my $writer_fh = shift;
    my $host = shift;
    my $chef_server = shift;
    my $spacewalk_server = shift;
    my $zabbix_server = shift;

    my $server_name = $host->{server_name};
    my $os = $host->{os};
    my $server_ips = $host->{server_ips};
    my $support_group = $host->{support_group};
    my $description = $host->{description};
    my $owner_dept = $host->{owner_dept};
    my $billing_dept = $host->{billing_dept};
    my $patchlevel = $host->{patchlevel};
    my $location = $host->{location};
    my $server_type = $host->{svrtype};
    my $start_date = $host->{start_date};

    my $status_admin = 0;
    my $status_primary = 0;

    my $admin_ip = '';
    my $admin_icmp = '';
    my $admin_ssh = '';

    if (defined $host->{admin_ip}) {
        $admin_ip = $host->{admin_ip};
        if (!$dry_run) {
            $admin_icmp = get_status_icmp($admin_ip);
            ($admin_ssh, $status_admin) = get_status_ssh($admin_ip);
        }
    }

    my $primary_ip = '';
    my $primary_icmp = '';
    my $primary_ssh = '';

    if (defined $host->{primary_ip}) {
        $primary_ip = $host->{primary_ip};
        if (!$dry_run) {
            $primary_icmp = get_status_icmp($primary_ip);
            ($primary_ssh, $status_primary) = get_status_ssh($primary_ip);
        }
    }

    my $ssh_ip = undef;
    if ($status_admin) {
        $ssh_ip = $admin_ip;
    } elsif ($status_primary) {
        $ssh_ip = $primary_ip;
    }

    my $hostname = '';
    my $ips = '';
    my $ipv6 = '';
    my $networkmanager = '';
    my $date = '';
    my $tivoli = '';
    my $auditd = '';
    my $chef_client = '';
    my $knife_22 = '';
    my $chef_443 = '';
    my $spacewalk_client = '';
    my $spacewalk_patches = -1;
    my $spacewalk_80 = '';
    my $spacewalk_443 = '';
    my $spacewalk_5222 = '';
    my $ossec = '';

    my $hwmanufacturer = '';
    my $hwproductname = '';
    my $hwserialnumber = '';

    my $ossec_prod_1515 = '';
    my $ossec_nonprod_1515 = '';
    my $zabbix_agent = '';
    my $zabbix_proxy_10051 = '';
    my $zabbix_master_10050 = '';
    my $zabbix_proxy_10050 = '';
    my $syslog_prod_514 = '';
    my $syslog_non_prod_514 = '';
    my $proxy_80 = '';
    my $lsb_release = '';
    my $patch_group = '';

    if (defined $ssh_ip) {
        my %results;
        if (defined $primary_ip) {
            %results = get_server_results($ssh_ip, $script_primary);
        } else {
            %results = get_server_results($ssh_ip, $script_admin);
        }
        $hostname = get_status_hostname($server_name, $results{hostname});
        $ips = get_status_ips($server_name, $server_ips, $results{ips});
        $ipv6 = get_status_ipv6($results{ipv6});
        $networkmanager = get_status_network_manager($results{netmanproc}, $results{netmanstartup});
        $date = get_status_date($results{date});
        $tivoli = get_status_itm($results{itmproc}, $results{itmfile});
        $auditd = get_status_auditd($results{auditmtab}, $results{auditdisk});

	$hwmanufacturer = get_status_hardware_manufacturer($results{HWManufacturer});
	$hwproductname = get_status_hardware_product_name($results{HWProductName});
	$hwserialnumber = get_status_hardware_serial_number($results{HWSerialNumber});
        if (defined $primary_ip) {
            $chef_client = get_status_chef($results{chefrpm}, $chef_server);
            $knife_22 = get_status_ssh_remote_port("Knife 22/TCP", "10.108.19.17", $primary_ip, 22);
            $chef_443 = get_status_remote_port("Chef 443/TCP", $results{chef443});
            $spacewalk_client = get_status_spacewalk($spacewalk_server, $os);
            $spacewalk_patches = get_patches_spacewalk($spacewalk_server);
            $spacewalk_80 = get_status_remote_port("Spacewalk 80/TCP", $results{spacewalk80});
            $spacewalk_443 = get_status_remote_port("Spacewalk 443/TCP", $results{spacewalk443});
            $spacewalk_5222 = get_status_remote_port("Spacewalk 5222/TCP", $results{spacewalk5222});
            $ossec = get_status_ossec($results{ossecproc}, $results{ossecrpm});
            $ossec_prod_1515 = get_status_remote_port("OSSEC Register Production 1515/TCP", $results{ossecprod1515});
            $ossec_nonprod_1515 = get_status_remote_port("OSSEC Register Non-Prod 1515/TCP", $results{ossecnonprod1515});
            $zabbix_agent = get_status_zabbix($results{zabbixrpm}, $zabbix_server);
            $zabbix_proxy_10051 = get_status_remote_port("Zabbix Proxy 10051/TCP", $results{zabbixproxy10051});
            if ($results{zabbixproc}) {
                $zabbix_master_10050 = get_status_ssh_remote_port("Zabbix from Master 10050/TCP", "10.108.19.47", $primary_ip, 10050);
                $zabbix_proxy_10050 = get_status_ssh_remote_port("Zabbix from Proxy 10050/TCP", "10.108.19.48", $primary_ip, 10050);
            }
            $syslog_prod_514 = get_status_remote_port("Syslog Production 514/TCP", $results{syslogprod514});
            $syslog_non_prod_514 = get_status_remote_port("Syslog Non-Prod 514/TCP", $results{syslognonprod514});
            $proxy_80 = get_status_remote_port("Mgmt Proxy 80/TCP", $results{mgmtproxy80});
        } else {
            $chef_client = get_status_chef_offline($chef_server);
            $spacewalk_client = get_status_spacewalk($spacewalk_server, $os);
            $spacewalk_patches = get_patches_spacewalk($spacewalk_server);
        }
        $lsb_release = get_lsb_release($results{lsbrelease});
    } else {
        $chef_client = get_status_chef_offline($chef_server);
        $spacewalk_client = get_status_spacewalk($spacewalk_server, $os);
        $spacewalk_patches = get_patches_spacewalk($spacewalk_server);
    }

    if ($chef_server && $chef_server->{patchgroup}) {
        if ($patchlevel) {
            if ($chef_server->{patchgroup} eq $patchlevel) {
                $patch_group = $chef_server->{patchgroup};
            } else {
                $patch_group = $chef_server->{patchgroup} ." !";
            }
        } else {
            $patch_group = $chef_server->{patchgroup} . ' ?';
        }
    } else {
        $patch_group = $patchlevel;
    }

    my %data = (
        server_name => $server_name,
        admin_ip => $admin_ip,
        admin_icmp => $admin_icmp,
        admin_ssh => $admin_ssh,
        primary_ip => $primary_ip,
        primary_icmp => $primary_icmp,
        primary_ssh => $primary_ssh,
        hostname => $hostname,
        ips => $ips,
        ipv6 => $ipv6,
        networkmanager => $networkmanager,
        date => $date,
        tivoli => $tivoli,
        auditd => $auditd,
        chef_client => $chef_client,
        knife_22 => $knife_22,
        chef_443 => $chef_443,
        spacewalk_client => $spacewalk_client,
        spacewalk_patches => $spacewalk_patches,
        spacewalk_80 => $spacewalk_80,
        spacewalk_443 => $spacewalk_443,
        spacewalk_5222 => $spacewalk_5222,

	HWManufacturer => $hwmanufacturer,
	HWProductName => $hwproductname,
	HWSerialNumber => $hwserialnumber,

        ossec => $ossec,
        ossec_prod_1515 => $ossec_prod_1515,
        ossec_nonprod_1515 => $ossec_nonprod_1515,
        zabbix_agent => $zabbix_agent,
        zabbix_proxy_10051 => $zabbix_proxy_10051,
        zabbix_master_10050 => $zabbix_master_10050,
        zabbix_proxy_10050 => $zabbix_proxy_10050,
        syslog_prod_514 => $syslog_prod_514,
        syslog_non_prod_514 => $syslog_non_prod_514,
        proxy_80 => $proxy_80,
        lsb_release => $lsb_release,
        os => $os,
        server_type => $server_type,
        patch_group => $patch_group,
        location => $location,
        support_group => $support_group,
        owner_dept => $owner_dept,
        billing_dept => $billing_dept,
        start_date => $start_date,
        description => $description,
    );

    # Write data to pipe for retrieval in parent process
    Storable::store_fd(\%data, $writer_fh);
}

sub process_results {
    my $processes = shift;
    my $max_processes = shift;
    my $columns = shift;
    my $results = shift;

    while (scalar(%{$processes}) && ($dry_run || scalar(keys(%{$processes})) >= $max_processes)) {
        my $output_fh;
        if ($dry_run) {
            $output_fh = delete $processes->{-1};
        } else {
            my $kid = waitpid(-1, 0);
            $output_fh = delete $processes->{$kid};
        }
        my $data = Storable::fd_retrieve($output_fh);
        $results->{lc($data->{server_name})} = $data;

        close $output_fh;

        if ($dry_run) {
            last;
        }
    }
}

sub create_worksheet {
    my $workbook = shift;
    my $name = shift;
    my $headers = shift;
    my $header_format = shift;
    my $options_override = shift;

    my %options = (
        freeze_header_only => 0,
    );

    if (defined $options_override) {
        @options{keys %$options_override} = values %$options_override;
    }

    my $worksheet = $workbook->add_worksheet($name);
    $worksheet->set_row(0, undef, $header_format); # Header Format
    if ($options{freeze_header_only}) {
        $worksheet->freeze_panes(1, 0);
    } else {
        $worksheet->freeze_panes(1, 1);
    }

    my $col = 0;
    foreach my $header (@$headers) {
        $worksheet->write(0, $col, $header->{name});
        $worksheet->set_column($col, $col, $header->{width});

        $col++;
    }

    return $worksheet;
}

sub write_worksheet_rows {
    my $worksheet = shift;
    my $columns = shift;
    my $data = shift;

    my $x = 1;

    foreach my $row (@{$data}) {
        for (my $i=0; $i < @{$columns}; $i++) {
            $worksheet->write($x, $i, $row->{$columns->[$i]->{key}});

        }
        $x++;
    }

    $worksheet->autofilter(0, 0, $x - 1, @{$columns} - 1);
}

sub write_worksheet_summary {
    my $worksheet = shift;
    my $header_format = shift;
    my $subheader_format = shift;
    my $large_format = shift;
    my $bold_format = shift;
    my $summary_columns = shift;
    my $linux_columns = shift;
    my $linux_data = shift;
    my $missing_data = shift;
    my $engineering_data = shift;
    my $uniteny_data = shift;
    my $appliance_data = shift;
    my $zlinux_data = shift;

    my $x = 2;

    my $linux_patching = process_patching_linux_results($linux_data, $missing_data);

    my @grand_total_cells = ();

    write_summary_results_linux($worksheet, $header_format, $subheader_format, $bold_format, $large_format, $linux_columns, $linux_patching, \$x, \@grand_total_cells);
    write_summary_results_with_header($worksheet, $subheader_format, $bold_format, $summary_columns, "Engineering", $engineering_data, \$x, \@grand_total_cells);
    write_summary_results_with_header($worksheet, $subheader_format, $bold_format, $summary_columns, "UniteNY", $uniteny_data, \$x, \@grand_total_cells);
    write_summary_results_with_header($worksheet, $subheader_format, $bold_format, $summary_columns, "Appliances", $appliance_data, \$x, \@grand_total_cells);
    write_summary_results_with_header($worksheet, $subheader_format, $bold_format, $summary_columns, "zLinux", $zlinux_data, \$x, \@grand_total_cells);

    $worksheet->merge_range($x, 0, $x, @$summary_columns - 1, '', $bold_format);
    $x++;

    my $grand_total = '=' . join('+', @grand_total_cells);

    $worksheet->write($x, 0, 'Grand Total:', $large_format);
    $worksheet->write($x, @$summary_columns - 1, $grand_total, $large_format);
}

sub write_summary_results_linux {
    my $worksheet = shift;
    my $header_format = shift;
    my $subheader_format = shift;
    my $bold_format = shift;
    my $large_format = shift;
    my $columns = shift;
    my $linux_patching = shift;
    my $x_ref = shift;
    my $grand_total_cells = shift;


    $worksheet->merge_range($$x_ref, 0, $$x_ref, @$columns - 1, "Linux Servers", $subheader_format);
    $$x_ref++;
    $$x_ref++;

    my @total_rows = ();

    foreach my $location (sort keys %{$linux_patching}) {
        $worksheet->merge_range($$x_ref, 0, $$x_ref, @$columns - 1, $location, $header_format); 
        $$x_ref++;

        my $location_results = $linux_patching->{$location};

        write_summary_results($worksheet, $subheader_format, $bold_format, $columns, $location_results, $x_ref);
        my $total_row = $$x_ref - 2; # The row with totals is two lines back
        push @total_rows, $total_row;
    }

    $worksheet->write($$x_ref, 0, 'Linux Total:', $large_format);
    for (my $i=1; $i < @{$columns}; $i++) {
        my @total_cells = ();
        foreach my $row (@total_rows) {
            my $cell = xl_rowcol_to_cell($row, $i, 1, 0);
            push @total_cells, $cell;
        }
        my $linux_total = '=' . join('+', @total_cells);

        $worksheet->write($$x_ref, $i, $linux_total, $large_format);

        if ($columns->[$i]->{key} eq 'total') {
            my $total_cell = xl_rowcol_to_cell($$x_ref, $i, 1, 1);
            push @$grand_total_cells, $total_cell;
        }
    }
    $$x_ref++;

    $worksheet->merge_range($$x_ref, 0, $$x_ref, @$columns - 1, '', $bold_format);
    $$x_ref++;
}

sub write_summary_results_with_header {
    my $worksheet = shift;
    my $subheader_format = shift;
    my $bold_format = shift;
    my $columns = shift;
    my $header = shift;
    my $results = shift;
    my $x_ref = shift;
    my $grand_total_cells = shift;

    my $location_results = process_servers_by_location($results);

    $worksheet->merge_range($$x_ref, 0, $$x_ref, @$columns - 1, $header, $subheader_format);
    $$x_ref++;

    write_summary_results($worksheet, $subheader_format, $bold_format, $columns, $location_results, $x_ref);

    for (my $i=1; $i < @{$columns}; $i++) {
        if ($columns->[$i]->{key} eq 'total') {
            my $total_row = $$x_ref - 2; # The row with totals is two lines back
            my $total_cell = xl_rowcol_to_cell($total_row, $i, 1, 1);
            push @$grand_total_cells, $total_cell;
        }
    }
}

sub write_summary_results {
    my $worksheet = shift;
    my $subheader_format = shift;
    my $bold_format = shift;
    my $columns = shift;
    my $results = shift;
    my $x_ref = shift;

    my %value_cells = ();

    my $first_row = $$x_ref;
    foreach my $key (sort keys %$results) {
        my $row = $results->{$key};
        for (my $i=0; $i < @{$columns}; $i++) {
            my $column_key = $columns->[$i]->{key};
            my $value = $row->{$column_key};
            if (defined $value) {
                $worksheet->write($$x_ref, $i, $value);
                $value_cells{$column_key} = 1;
            } elsif ($column_key eq 'total') {
                my $first_cell = xl_rowcol_to_cell($$x_ref, 1, 0, 1);
                my $last_cell = xl_rowcol_to_cell($$x_ref, $i-1, 0, 1);
                $worksheet->write($$x_ref, $i, "=SUM(${first_cell}:${last_cell})");
                $value_cells{$column_key} = 1;
            }
        }
        $$x_ref++;
    }

    my $last_row = $$x_ref - 1;

    if ($last_row > $first_row) {
        # multiple billing departments for location
        $worksheet->write($$x_ref, 0, 'Total:', $bold_format);
        for (my $i=1; $i < @{$columns}; $i++) {
            my $column_key = $columns->[$i]->{key};
            if ($value_cells{$column_key}) {
                my $first_cell = xl_rowcol_to_cell($first_row, $i, 1, 0);
                my $last_cell = xl_rowcol_to_cell($last_row, $i, 1, 0);
                $worksheet->write($$x_ref, $i, "=SUM(${first_cell}:${last_cell})", $bold_format);
            }
        }
        $$x_ref++;
    }

    $worksheet->merge_range($$x_ref, 0, $$x_ref, @$columns - 1, '', $bold_format);
    $$x_ref++;
}

sub trim {
    my $string = shift;
    $string =~ s/^\s+//s;
    $string =~ s/\s+$//s;
    return $string;
}

my $summary_columns = [{
    key   => "location",
    name  => "Info",
    width => 65
},{
    key   => "patched",
    name  => "Fully\nPatched",
    width => 12
},{
    key   => "patching_underway",
    name  => "Patching\nUnderway",
    width => 12
},{
    key   => "under_review",
    name  => "Under\nReview",
    width => 12
},{
    key   => "unsupported",
    name  => "Unsupported",
    width => 12
},{
    key   => "total",
    name  => "Total",
    width => 12
}];

my $linux_summary_columns = [{
    key   => "billing_dept",
    name  => "Info",
    width => 65
},{
    key   => "patched",
    name  => "Fully\nPatched",
    width => 13
},{
    key   => "patching_underway",
    name  => "Patching\nUnderway",
    width => 12
},{
    key   => "under_review",
    name  => "Under\nReview",
    width => 12
},{
    key   => "unsupported",
    name  => "Unsupported",
    width => 12
},{
    key   => "total",
    name  => "Total",
    width => 12
}];

my $servers_columns = [{
    key   => "server_name",
    name  => "Server Name",
    width => 28
},{
    key   => "admin_ip",
    name  => "Admin IP",
    width => 15
},{
    key   => "admin_icmp",
    name  => "Admin ICMP",
    width => 13
},{
    key   => "admin_ssh",
    name  => "Admin SSH",
    width => 13
},{
    key   => "primary_ip",
    name  => "Primary IP",
    width => 15
},{
    key   => "primary_icmp",
    name  => "Primary ICMP",
    width => 13
},{
    key   => "primary_ssh",
    name  => "Primary SSH",
    width => 13
},{
    key   => "hostname",
    name  => "Hostname",
    width => 17
},{
    key   => "ips",
    name  => "IPs",
    width => 9
},{
    key   => "ipv6",
    name  => "IPv6",
    width => 9
},{
    key   => "networkmanager",
    name  => "NetworkManager",
    width => 16
},{
    key   => "date",
    name  => "Date",
    width => 9
},{
    key   => "tivoli",
    name  => "Tivoli Monitoring",
    width => 16
},{
    key   => "auditd",
    name  => "Auditd",
    width => 15
},{
    key   => "chef_client",
    name  => "Chef Client",
    width => 15
},{
    key   => "knife_22",
    name  => "Knife 22/TCP",
    width => 17
},{
    key   => "chef_443",
    name  => "Chef 443/TCP",
    width => 19
},{
    key   => "spacewalk_client",
    name  => "Spacewalk Client",
    width => 16
},{
    key   => "spacewalk_patches",
    name  => "Patches",
    width => 8
},{
    key   => "spacewalk_80",
    name  => "Spacewalk 80/TCP", 
    width => 23
},{
    key   => "spacewalk_443",
    name  => "Spacewalk 443/TCP", 
    width => 24
},{
    key   => "spacewalk_5222",
    name  => "Spacewalk 5222/TCP", 
    width => 25
},{
    key   => "ossec",
    name  => "OSSEC",
    width => 15
},{
    key   => "ossec_prod_1515",
    name  => "OSSEC Register Production 1515/TCP", 
    width => 39
},{
    key   => "ossec_nonprod_1515",
    name  => "OSSEC Register Non-Prod 1515/TCP", 
    width => 38
},{
    key   => "zabbix_agent",
    name  => "Zabbix Agent", 
    width => 17
},{
    key   => "zabbix_proxy_10051",
    name  => "Zabbix Proxy 10051/TCP",
    width => 28
},{
    key   => "zabbix_master_10050",
    name  => "Zabbix from Master 10050/TCP",
    width => 34
},{
    key   => "zabbix_proxy_10050",
    name  => "Zabbix from Proxy 10050/TCP",
    width => 34
},{
    key   => "syslog_prod_514",
    name  => "Syslog Production 514/TCP",
    width => 30
},{
    key   => "syslog_non_prod_514",
    name  => "Syslog Non-Prod 514/TCP",
    width => 29
},{
    key   => "proxy_80",
    name  => "Mgmt Proxy 80/TCP",
    width => 25
},{
    key   => "lsb_release",
    name  => "LSB Release",
    width => 57
},{
    key   => "os",
    name  => "ITSM Operating System",
    width => 32
},{
    key   => "server_type",
    name  => "Server Type",
    width => 11
},{
    key   => "patch_group",
    name  => "Patch Group",
    width => 23
},{
    key   => "location",
    name  => "Location",
    width => 42
},{
    key   => "support_group",
    name  => "Support Group",
    width => 23
},{
    key   => "owner_dept",
    name  => "Owner Dept",
    width => 27
},{
    key   => "billing_dept",
    name  => "Billing Dept",
    width => 46
},{
    key   => "start_date",
    name  => "Start Date",
    width => 18
},{
    key   => "description",
    name  => "Description",
    width => 100
},{
    key   => "HWManufacturer",
    name  => "Hardware Manufacturer",
    width => 15
},{
    key   => "HWProductName",
    name  => "Hardware Product Name",
    width => 15
},{
    key   => "HWSerialNumber",
    name  => "Hardware Serial Number",
    width => 15
}];

my $missing_columns = [{
    key   => "server_name",
    name  => "Server Name",
    width => 28
},{
    key   => "os",
    name  => "ITSM Operating System",
    width => 32
},{
    key   => "location",
    name  => "Location",
    width => 42
},{
    key   => "support_group",
    name  => "Support Group",
    width => 23
},{
    key   => "owner_dept",
    name  => "Owner Dept",
    width => 27
},{
    key   => "billing_dept",
    name  => "Billing Dept",
    width => 46
},{
    key   => "start_date",
    name  => "Start Date",
    width => 18
},{
    key   => "description",
    name  => "Description",
    width => 100
},{
    key   => "server_ips_text",
    name  => "IPs",
    width => 100
}];

my $appliance_columns = [{
    key   => "server_name",
    name  => "Server Name",
    width => 28
},{
    key   => "primary_ip",
    name  => "Primary IP",
    width => 15
},{
    key   => "os",
    name  => "ITSM Operating System",
    width => 32
},{
    key   => "location",
    name  => "Location",
    width => 42
},{
    key   => "support_group",
    name  => "Support Group",
    width => 23
},{
    key   => "owner_dept",
    name  => "Owner Dept",
    width => 27
},{
    key   => "billing_dept",
    name  => "Billing Dept",
    width => 46
},{
    key   => "start_date",
    name  => "Start Date",
    width => 18
},{
    key   => "description",
    name  => "Description",
    width => 100
}];

my $zlinux_columns = [{
    key   => "server_name",
    name  => "Server Name",
    width => 28
},{
    key   => "primary_ip",
    name  => "Primary IP",
    width => 15
},{
    key   => "os",
    name  => "ITSM Operating System",
    width => 32
},{
    key   => "location",
    name  => "Location",
    width => 42
},{
    key   => "support_group",
    name  => "Support Group",
    width => 23
},{
    key   => "owner_dept",
    name  => "Owner Dept",
    width => 27
},{
    key   => "billing_dept",
    name  => "Billing Dept",
    width => 46
},{
    key   => "start_date",
    name  => "Start Date",
    width => 18
},{
    key   => "description",
    name  => "Description",
    width => 100
}];

my $engineering_columns = [{
    key   => "server_name",
    name  => "Server Name",
    width => 28
},{
    key   => "primary_ip",
    name  => "Primary IP",
    width => 15
},{
    key   => "os",
    name  => "ITSM Operating System",
    width => 32
},{
    key   => "location",
    name  => "Location",
    width => 42
},{
    key   => "support_group",
    name  => "Support Group",
    width => 23
},{
    key   => "owner_dept",
    name  => "Owner Dept",
    width => 27
},{
    key   => "billing_dept",
    name  => "Billing Dept",
    width => 46
},{
    key   => "start_date",
    name  => "Start Date",
    width => 18
},{
    key   => "description",
    name  => "Description",
    width => 100
}];


my $uniteny_columns = [{
    key   => "server_name",
    name  => "Server Name",
    width => 28
},{
    key   => "primary_ip",
    name  => "Primary IP",
    width => 15
},{
    key   => "os",
    name  => "ITSM Operating System",
    width => 32
},{
    key   => "location",
    name  => "Location",
    width => 42
},{
    key   => "support_group",
    name  => "Support Group",
    width => 23
},{
    key   => "owner_dept",
    name  => "Owner Dept",
    width => 27
},{
    key   => "billing_dept",
    name  => "Billing Dept",
    width => 46
},{
    key   => "start_date",
    name  => "Start Date",
    width => 18
},{
    key   => "description",
    name  => "Description",
    width => 100
}];

my $excel_file = "Linux-Servers-ITSM-Data.xlsx";

unlink($excel_file);

if (-e $excel_file) {
    die("Could not remove old Excel file!\n");
}

my $csv_data = read_csv_data("u_cmdb_ci_server_ip_app_inst.csv");

my $chef_servers = {};
my $spacewalk_servers = {};
my $zabbix_servers = {};

get_chef_servers("10.108.19.17", $chef_servers); # production
get_chef_servers("10.108.19.56", $chef_servers); # lab

get_spacewalk_servers("10.108.19.10", $spacewalk_servers); # production
get_spacewalk_servers("10.108.19.100", $spacewalk_servers); # lab

get_zabbix_servers("10.108.19.47", $zabbix_servers); # zabbix

my $missing_ips = get_missing_ips($csv_data);
my $linux_results = process_linux_servers($csv_data, $servers_columns, $chef_servers, $spacewalk_servers, $zabbix_servers, \@patch_management_servers);

my $workbook = Excel::Writer::XLSX->new($excel_file) or die("Cannot create new Excel file!\n");

my $red_format = $workbook->add_format(
    bg_color => '#FFC7CE',
    color    => '#9C0006',
);

my $yellow_format = $workbook->add_format(
    bg_color => '#FFEB9C',
    color    => '#9C6500',
);

my $green_format = $workbook->add_format(
    bg_color => '#C6EFCE',
    color    => '#006100',
);

my $header_format = $workbook->add_format(
    bold         => 1, # yes
    color        => '#44546A',
    bottom       => 2, # border type #2 (solid : weight 2)
    bottom_color => '#9BC2E6',
    align        => 'left',
    text_wrap    => 1,
);

my $subheader_format = $workbook->add_format(
    bold         => 1, # yes
    color        => '#44546A',
    bottom       => 5, # border type #5 (solid : weight 3)
    bottom_color => '#9BC2E6',
    size         => 13, # font size 13
    align        => 'center',
);

my $bold_format = $workbook->add_format(
    bold         => 1,
);

my $large_format = $workbook->add_format(
    bold         => 1,
    size         => 13,
);

my $summary_ws = create_worksheet($workbook, "Summary", $summary_columns, $header_format, { freeze_header_only => 1 });
my $servers_ws = create_worksheet($workbook, "Linux Servers", $servers_columns, $header_format);
my $missing_ws = create_worksheet($workbook, "Missing IPs", $missing_columns, $header_format);
my $engineering_ws = create_worksheet($workbook, "Engineering", $uniteny_columns, $header_format);
my $uniteny_ws = create_worksheet($workbook, "UniteNY", $uniteny_columns, $header_format);
my $appliance_ws = create_worksheet($workbook, "Appliances", $appliance_columns, $header_format);
my $zlinux_ws = create_worksheet($workbook, "zLinux", $appliance_columns, $header_format);

# Port
$servers_ws->conditional_formatting('$B:$AG', {
    type     => 'text',
    criteria => 'containsText',
    value    => 'OPEN',
    format   => $green_format
});

# Port
$servers_ws->conditional_formatting('$B:$AG', {
    type     => 'text',
    criteria => 'containsText',
    value    => 'CLOSE',
    format   => $red_format
});

# Port
$servers_ws->conditional_formatting('$B:$AG', {
    type     => 'text',
    criteria => 'containsText',
    value    => 'DOWN',
    format   => $red_format
});

# SSH
$servers_ws->conditional_formatting('$D:$G', {
    type     => 'text',
    criteria => 'containsText',
    value    => 'AUTH',
    format   => $yellow_format
});

# Misc
$servers_ws->conditional_formatting('$B:$AG', {
    type     => 'text',
    criteria => 'containsText',
    value    => 'BAD',
    format   => $red_format
});

# Patch Group
$servers_ws->conditional_formatting('$AJ:$AJ', {
    type     => 'text',
    criteria => 'containsText',
    value    => '~?',
    format   => $yellow_format
});

# Patch Group
$servers_ws->conditional_formatting('$AJ:$AJ', {
    type     => 'text',
    criteria => 'containsText',
    value    => '!',
    format   => $red_format
});

# NetworkManager
$servers_ws->conditional_formatting('$K:$K', {
    type     => 'text',
    criteria => 'containsText',
    value    => 'DISABLED',
    format   => $green_format
});

# NetworkManager
$servers_ws->conditional_formatting('$K:$K', {
    type     => 'text',
    criteria => 'containsText',
    value    => 'RUNNING',
    format   => $yellow_format
});

# NetworkManager
$servers_ws->conditional_formatting('$K:$K', {
    type     => 'text',
    criteria => 'containsText',
    value    => 'ENABLED',
    format   => $red_format
});

# IPv6
$servers_ws->conditional_formatting('$J:$J', {
    type     => 'text',
    criteria => 'containsText',
    value    => 'ON',
    format   => $red_format
});

# Auditd
$servers_ws->conditional_formatting('$N:$N', {
    type     => 'text',
    criteria => 'containsText',
    value    => 'RESIZE',
    format   => $yellow_format
});

# Patches
$servers_ws->conditional_formatting('$S:$S', {
    type     => 'cell',
    criteria => '=',
    value    => 0,
    format   => $green_format
});

# Hostname
$servers_ws->conditional_formatting('$H:$H', {
    type     => 'text',
    criteria => 'containsText',
    value    => 'WARN',
    format   => $red_format
});

# Misc Software
$servers_ws->conditional_formatting('$L:$Z', {
    type     => 'text',
    criteria => 'containsText',
    value    => 'MISSING',
    format   => $red_format
});

# Misc Software
$servers_ws->conditional_formatting('$L:$Z', {
    type     => 'text',
    criteria => 'containsText',
    value    => 'RPM',
    format   => $red_format
});

# Misc Software
$servers_ws->conditional_formatting('$L:$Z', {
    type     => 'text',
    criteria => 'containsText',
    value    => 'SETUP',
    format   => $yellow_format
});

# Misc Software
$servers_ws->conditional_formatting('$L:$Z', {
    type     => 'text',
    criteria => 'containsText',
    value    => 'OK',
    format   => $green_format
});

my @linux_results_sorted = map { $linux_results->{$_} } sort keys %{$linux_results};
my @engineering_servers = sort { lc($a->{server_name}) cmp lc($b->{server_name}) } @{$csv_data->{engineering_servers}};
my @uniteny_servers = sort { lc($a->{server_name}) cmp lc($b->{server_name}) } @{$csv_data->{uniteny_servers}};
my @appliances = sort { lc($a->{server_name}) cmp lc($b->{server_name}) } @{$csv_data->{appliances}};
my @zlinux_servers = sort { lc($a->{server_name}) cmp lc($b->{server_name}) } @{$csv_data->{zlinux_servers}};

write_worksheet_summary($summary_ws, $header_format, $subheader_format, $large_format, $bold_format, $summary_columns, $linux_summary_columns, $linux_results, $missing_ips, \@engineering_servers, \@uniteny_servers, \@appliances, \@zlinux_servers);
write_worksheet_rows($servers_ws, $servers_columns, \@linux_results_sorted);
write_worksheet_rows($missing_ws, $missing_columns, $missing_ips);
write_worksheet_rows($engineering_ws, $engineering_columns, \@engineering_servers);
write_worksheet_rows($uniteny_ws, $uniteny_columns, \@uniteny_servers);
write_worksheet_rows($appliance_ws, $appliance_columns, \@appliances);
write_worksheet_rows($zlinux_ws, $zlinux_columns, \@zlinux_servers);

$workbook->close();