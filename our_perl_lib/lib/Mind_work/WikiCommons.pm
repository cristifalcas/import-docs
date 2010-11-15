package WikiCommons;

use warnings;
use strict;

use File::Path qw(make_path remove_tree);
use Unicode::Normalize 'NFD','NFC','NFKD','NFKC';
use File::Basename;
use File::Copy;
use Data::Dumper;
$Data::Dumper::Sortkeys = 1;
use XML::Simple;

our $start_time = 0;
our $clean_up = {};
our $url_sep = " -- ";
our $remote_work = "no";
our $real_path;

sub set_real_path {
    $real_path = shift;
}

sub is_remote {
    my $q=shift;
    $remote_work = $q || $remote_work;
    return $remote_work;
}

sub xmlfile_to_hash {
    my $file = shift;
    my $xml = new XML::Simple;
    return $xml->XMLin("$file");
}

sub hash_to_xmlfile {
    my ($hash, $name, $root_name) = @_;
    $root_name = "out" if ! defined $root_name;
    my $xs = new XML::Simple();
    my $xml = $xs->XMLout($hash,
		    NoAttr => 1,
		    RootName=>$root_name,
		    OutputFile => $name
		    );
}

sub cleanup {
    foreach my $key (keys %$clean_up) {
	if ($clean_up->{"$key"} eq "file") {
	    unlink("$key") or die "Could not delete the file $key: ".$!."\n";
	    delete $clean_up->{"$key"};
	}
    }
    foreach my $key (keys %$clean_up) {
	if ($clean_up->{$key} eq "dir") {
	    remove_tree("$key");
	} else {
	    die "caca $clean_up->{$key} for $key\n";
	}
    }
    $clean_up = {};
}

sub copy_dir {
    my ($from_dir, $to_dir) = @_;
    opendir my($dh), $from_dir or die "Could not open dir '$from_dir': $!";
    for my $entry (readdir $dh) {
#         next if $entry =~ /$regex/;
        my $source = "$from_dir/$entry";
        my $destination = "$to_dir/$entry";
        if (-d $source) {
	    next if $source =~ "\.?\.";
            mkdir $destination or die "mkdir '$destination' failed: $!" if not -e $destination;
            copy_dir($source, $destination);
        } else {
            copy($source, $destination) or die "copy failed: $source to $destination $!";
        }
    }
    closedir $dh;
    return;
}

sub write_file {
    my ($path,$text, $remove) = @_;
    $remove = 0 if not defined $remove;
    my ($name,$dir,$suffix) = fileparse($path, qr/\.[^.]*/);
    add_to_remove("$dir/$name$suffix", "file") if $remove ne 0;
    print "\tWriting file $name$suffix.\t". get_time_diff() ."\n";
    open (FILE, ">$path") or die "at generic write can't open file $path for writing: $!\n";
    ### don't decode/encode to utf8
    print FILE "$text";
    close (FILE);
}

sub get_time_diff {
    return (time() - $start_time);
}

sub get_urlsep {
    return "$url_sep";
}

sub makedir {
    my $dir = shift;
    my ($name_user, $pass_user, $uid_user, $gid_user, $quota_user, $comment_user, $gcos_user, $dir_user, $shell_user, $expire_user) = getpwnam scalar getpwuid $<;
    make_path ("$dir", {owner=>"$name_user", group=>"nobody", error => \my $err});
    if (@$err) {
    for my $diag (@$err) {
        my ($file, $message) = %$diag;
        if ($file eq '') { print "general error: $message.\n"; }
        else { print "problem unlinking $file: $message.\n"; }
    }
    die "Can't make dir $dir.\n";
    }
}

sub add_to_remove {
    my ($file, $type) = @_;
    $clean_up->{$file} = "$type";
}

sub normalize_text {
    my $str = shift;
    ## from http://www.ahinea.com/en/tech/accented-translate.html
    for ( $str ) {  # the variable we work on
	##  convert to Unicode first
	##  if your data comes in Latin-1, then uncomment:
	$_ = Encode::decode( 'utf8', $_ );

	s/\xe4/ae/g;  ##  treat characters ä ñ ö ü ÿ
	s/\xf1/ny/g;  ##  this was wrong in previous version of this doc
	s/\xf6/oe/g;
	s/\xfc/ue/g;
	s/\xff/yu/g;
	## various apostrophes   http://www.mikezilla.com/exp0012.html
	s/\x{02B9}/\'/g;
	s/\x{2032}/\'/g;
	s/\x{0301}/\'/g;
	s/\x{02C8}/\'/g;
	s/\x{02BC}/\'/g;
	s/\x{2019}/\'/g;

	$_ = NFD( $_ );   ##  decompose (Unicode Normalization Form D)
	s/\pM//g;         ##  strip combining characters

	# additional normalizations:

	s/\x{00df}/ss/g;  ##  German beta “ß” -> “ss”
	s/\x{00c6}/AE/g;  ##  Æ
	s/\x{00e6}/ae/g;  ##  æ
	s/\x{0132}/IJ/g;  ##  ?
	s/\x{0133}/ij/g;  ##  ?
	s/\x{0152}/Oe/g;  ##  Œ
	s/\x{0153}/oe/g;  ##  œ

	tr/\x{00d0}\x{0110}\x{00f0}\x{0111}\x{0126}\x{0127}/DDddHh/; # ÐÐðdHh
	tr/\x{0131}\x{0138}\x{013f}\x{0141}\x{0140}\x{0142}/ikLLll/; # i??L?l
	tr/\x{014a}\x{0149}\x{014b}\x{00d8}\x{00f8}\x{017f}/NnnOos/; # ???Øø?
	tr/\x{00de}\x{0166}\x{00fe}\x{0167}/TTtt/;                   # ÞTþt

	s/[^\0-\x80]//g;  ##  clear everything else; optional
    }
    return Encode::encode( 'utf8', $str );  ;
}

sub get_file_md5 {
    my $doc_file = shift;
    open(FILE, $doc_file) or die "Can't open '$doc_file': $!\n";
    binmode(FILE);
    my $doc_md5 = Digest::MD5->new->addfile(*FILE)->hexdigest;
    close(FILE);
#     my $doc_md5 = "123";
    return $doc_md5;
}

sub capitalize_string {
    my ($str,$type) = @_;
    if ($type eq "first") {
	$str =~ s/\b(\w)/\U$1/g;
    } elsif ($type eq "all") {
	$str =~ s/([\w']+)/\u\L$1/g;
    } else {
	die "Capitalization: first (only first letter is capital) or all (first letter is capital and the rest remain the same.)\n";
    }
    return $str;
}

sub fix_name {
    my ($name, $customer, $big_ver, $main, $ver, $ver_sp, $ver_id) = @_;

    my $fixed_name = $name;
    $fixed_name = normalize_text($fixed_name);

    $fixed_name =~ s/^User Guide|User Guide$//i;
    $fixed_name =~ s/^User Manual|User Manual$//i;

    $customer = capitalize_string($customer, "all");

    $fixed_name =~ s/^\s?$customer[-_ \t]//i;
    $fixed_name =~ s/[-_ \t]$customer\s*$//i;

    $fixed_name =~ s/^\s?(MIND[-_ \t]?)?iphonex//i;
    $fixed_name =~ s/^\s?(MIND[-_ \t]?)?MINDBil[l]?//i;
    $fixed_name =~ s/^\s?mind[-_ \t]?//i;

    $fixed_name =~ s/^\s?$customer[-_ \t]//i;
    $fixed_name =~ s/[-_ \t]$customer\s*$//i;

    $fixed_name =~ s/jinny/Jinny/gi;
    $fixed_name =~ s/([[:digit:]])_/$1\./gi;
    $fixed_name =~ s/_/\ /gi;
    my $yet_another_version_style = $ver;
    if (defined $ver && defined $main) {
	$fixed_name =~ s/(^\s?[v]?$ver\s*$ver_id\s*$ver_sp\s+)|(\s+[v]?$ver\s*$ver_id\s*$ver_sp\s+$)//i;
	$fixed_name =~ s/(^\s?[v]?$ver\s*$ver_sp\s+)|(\s+[v]?$ver\s*$ver_sp\s+$)//i;
	$fixed_name =~ s/(^\s?[v]?$ver\s*$ver_id\s+)|(\s+[v]?$ver\s*$ver_id\s+$)//i;
	$fixed_name =~ s/(^\s?[v]?$ver\s+)|(\s+[v]?$ver\s*$)//i;
	$fixed_name =~ s/(^\s?[v]?$main\s+)|(\s+[v]?$main\s*$)//i;
	$fixed_name =~ s/(^\s?[v]?$big_ver\s+)|(\s+[v]?$big_ver\s*$)//i;
	my $aver = $ver;
	my $amain = $main;
	$aver =~ s/\.//g;
	$amain =~ s/\.//g;
	$fixed_name =~ s/(^\s?[v]?$aver\s*)|(\s+[v]?$aver\s*$)//i;
	$fixed_name =~ s/(^\s?[v]?$amain\s*)|(\s+[v]?$amain\s*$)//i;
    }
    $fixed_name =~ s/\s+ver\s*$//i;

    $fixed_name =~ s/^\s*-\s+//;
    $fixed_name =~ s/\s+/ /g;

    ## Specific updates
    $fixed_name = capitalize_string($fixed_name, "first");
    $fixed_name =~ s/^\budr\b/UDR/i;
    $fixed_name = "$1" if ($fixed_name =~ "^GN (.*)");
    $fixed_name = "Billing" if ($fixed_name eq "BillingUserManual5.0-Rev12");
    $fixed_name = "Billing Rev12" if ($fixed_name eq "BillingUserManual5.01-Rev12");
    $fixed_name = "Billing Rev13" if ($fixed_name eq "BillingUserManual5.01-Rev13Kenan");
    $fixed_name = "CallShop Manuel D\'Utilisation" if ($fixed_name eq "5.31.005 CallShop Manuel D\'Utilisation");
    $fixed_name = "Cashier" if ($fixed_name eq "Cashier5.21.Rev10");
    $fixed_name = "Cisco SSG Configuration" if ($fixed_name eq "Cisco SSG Configuration UserManuall5.0");
    $fixed_name = "Collector" if ($fixed_name eq "Collector 5.3");
    $fixed_name = "Correlation" if ($fixed_name eq "Correlation Rev10");
    $fixed_name = "Dashboard" if ($fixed_name eq "Dashboard5.30");
    $fixed_name = "DB Documentation" if ($fixed_name eq "5.31 DB Documentation");
    $fixed_name = "Guard" if ($fixed_name eq "Guard Rev13");
    $fixed_name = "Install Cisco Rev10" if ($fixed_name eq "InstallCisco5.0InstallB-Rev10");
    $fixed_name = "Install Cisco Rev11" if ($fixed_name eq "InstallCisco5.0InstallA-Rev11");
    $fixed_name = "Interception Monitor" if ($fixed_name eq "Interception 5.2Monitor Rev11");
    $fixed_name = "Manager" if ($fixed_name eq "Manager User Manual 5.21-Rev.11");
    $fixed_name = "Manager" if ($fixed_name eq "Manager User Manual 5.3");
    $fixed_name = "Multisite Failover Manager" if ($fixed_name eq "MultisiteFailoverManager5.01");
    $fixed_name = "Neils Revision" if ($fixed_name eq "50001neilsrevision");
    $fixed_name = "New Features Summary" if ($fixed_name eq "New Features Summary MIND-IPhonEX 5.30.010");
    $fixed_name = "New Features Summary" if ($fixed_name eq "New Features Summary MIND-IPhonEX 5.30.013");
    $fixed_name = "Open View Operation" if ($fixed_name eq "OpenViewOperations5.30");
    $fixed_name = "Pre-Release" if ($fixed_name eq "5.0Pre-Release");
    $fixed_name = "Process Configuration Documentation PackageChange" if ($fixed_name eq "6.01 Process Configuration Documentation PackageChange");
    $fixed_name = "Product Description" if ($fixed_name eq "Product Description 5.21-Rev.12");
    $fixed_name = "Product Description" if ($fixed_name eq "Product Description5.3");
    $fixed_name = "Product Description" if ($fixed_name eq "ProductDescription 5.0");
    $fixed_name = "Rapoarte Crystal - Interconnect" if ($fixed_name eq "Manual De Utilizare MINDBill 6.01 Rapoarte Crystal - Interconnect");
    $fixed_name = "Release Notes V3" if ($fixed_name eq "5.2x Release Notes V3");
    $fixed_name = "Reports User Guide" if ($fixed_name eq "Reports User Guide For");
    $fixed_name = "System Overview" if ($fixed_name eq "5.00.015 System Overview");
    $fixed_name = "Task Scheduler" if ($fixed_name eq "Task Scheduler User Guide 5.3");
    $fixed_name = "UDR Distribution" if ($fixed_name eq "UDRDistributionUserGuide5.01-Rev10");
    $fixed_name = "User Activity" if ($fixed_name eq "UserActivity5.30");
    $fixed_name = "WebBill" if ($fixed_name eq "5.3 WebBill");
    $fixed_name = "WebBill" if ($fixed_name eq "WebBill 5.2");
    $fixed_name = "WebBill" if ($fixed_name eq "WebBillUserManual5.0-Rev10");
    $fixed_name = "WebBill" if ($fixed_name eq "WebBillUserManual5.01-Rev11");
    $fixed_name = "WebClient" if ($fixed_name eq "WebClient5.0-Rev11");
    $fixed_name = "WebClient" if ($fixed_name eq "WebClient5.30");
    $fixed_name = "WebClient" if ($fixed_name eq "WebClient5.01-Rev11");
    $fixed_name = "Dialup CDR And Invoice Generation" if ($fixed_name eq "Dialup CDR And Invoice Generation 521");
    $fixed_name = "Vendors Support" if ($fixed_name eq "VendorsSupport");
    $fixed_name = "User Activity" if ($fixed_name eq "UserActivity5 30");
    $fixed_name = "IPE Monitor$1" if ($fixed_name =~ "IPEMonitor(.*)");
    $fixed_name = "Radius Paramaters$1" if ($fixed_name =~ "RadiusParamaters(.*)");
    $fixed_name = "Checkpoint LEA Configuration" if ($fixed_name eq "Checkpoint LEAconfiguration");
    $fixed_name = "High Availability" if ($fixed_name eq "HighAvailability");
    $fixed_name = "LEA Client Installation" if ($fixed_name eq "LEAClientInstallation");
    $fixed_name = "Load Balancing" if ($fixed_name eq "LoadBalancing");
    $fixed_name = "Parsing Rules" if ($fixed_name eq "ParsingRules");
    $fixed_name = "Plugin Point In Recalc" if ($fixed_name eq "PluginPointInRecalc");
    $fixed_name = "Processor Logs Files" if ($fixed_name eq "ProcessorLogsFiles");
    $fixed_name = "Proxy Manager Server" if ($fixed_name eq "ProxyManagerServer");
    $fixed_name = "Statistics Description" if ($fixed_name eq "StatisticsDescription");
    $fixed_name = "CallShop Manuel D\'Utilisation" if ($fixed_name eq "5.31.005 CallShop Manuel D\'Utilisation");
    $fixed_name = "DB Documentation$1" if ($fixed_name =~ "6.00 DB Documentation(.*)");
    $fixed_name = "DB Import" if ($fixed_name eq "DBImport");
    $fixed_name = "Display CDR Field Instructions" if ($fixed_name eq "DisplayCDRFieldInstructions");
    $fixed_name = "Fix Invoice XML Deployment" if ($fixed_name eq "FixInvoiceXML Deployment");

    $fixed_name =~ s/(^\s*)|(\s*$)//;

    return $fixed_name;
}

sub check_vers {
    my ($main, $ver) = @_;
    die "main $main or ver $ver is not defined.\n" if (! defined $main || ! defined $ver);
#     ver:
#     V7.00.001 SP28 DEMO
#     V5.01.008OMP
#     V5.31.006 GN SP01.004.2
#     User Manuals

#     main:
#     5.31.006
#     V6.01.003 SP40
#
    my $ver_fixed = ""; my $ver_sp = ""; my $ver_id = ""; my $main_sp = "";
    my $main_v = ""; my $ver_v = ""; my $big_ver = "";

    my $regexp_main = qr/^\s*v?[0-9]{1,}(\.[0-9]{1,})*\s*([a-z0-9 ]{1,})?\s*(SP\s*[0-9]{1,}(\.[0-9]{1,})*)?$/is;
    my $regexp_ver = qr/^\s*v?[0-9]{1,}(\.[0-9]{1,})*\s*([a-z0-9 ]{1,})?\s*(SP\s*[0-9]{1,}(\.[0-9]{1,})*)?\s*(demo)?\s*$/is;

    die "Main version $main is not correct.\n" if $main !~ m/$regexp_main/i;
#     die "Ver version $ver is not correct.\n" if $ver !~ m/$regexp_ver/i;
    $ver =$main if $ver !~ m/$regexp_ver/i;

    ### make versions like N.NN and remove any leading v
    $main = $main."0" if $main =~ m/^v?[[:digit:]]{1,}\.[[:digit:]]$/i;
    $main = $main.".00" if $main =~ m/^v?[[:digit:]]{1,}$/i;
    $main =~ s/\s*v//i;
    $ver = $ver."0" if $ver =~ m/^v?[[:digit:]]{1,}\.[[:digit:]]$/i;
    $ver = $ver.".00" if $ver =~ m/^v?[[:digit:]]{1,}$/i;
    $ver =~ s/\s*v//i;

    ### extract SPN.NN.NNN and remove it from versions
    $main_sp = $2 if $main =~ m/^(.*)?(SP\s*[0-9]{1,}(\.[0-9]{1,})*)(.*)?$/i;
    $main =~ s/$main_sp// if $main_sp ne "";
    $ver_sp = $2 if $ver =~ m/^(.*)?(SP\s*[0-9]{1,}(\.[0-9]{1,})*)(.*)?$/i;
    $ver =~ s/\s*$ver_sp\s*// if $ver_sp ne "";

    ### from main keep only N.NN
    if ($main =~ m/^([0-9]{1,}\.[0-9]{2})(\.[0-9]{1,})*\s*([a-z0-9 ]{1,})?(.*)?$/i){
	$main_v = "$1";
    }

    ### from ver extract any identificator
    if ($ver =~ m/^([0-9]{1,}(\.[0-9]{1,})*)\s*([a-z0-9 ]{1,})?$/i){
	$ver_v = "$1";
	$ver_id = "$3" if defined $3;
    }

    ### if we don't have an identificator, ver_fixed will be main, otherwise $ver
    if ($ver_id ne "" ){
	$ver_fixed = "$ver_v $ver_id";
    } else {
	$ver_fixed = "$main_v";
    }

    $big_ver = $1 if $main =~ m/^([0-9]{1,})((\.[0-9]{1,})*)(.*)$/i;

    $big_ver =~ s/(^\s*|\s*$)//g;
    $main_v =~ s/(^\s*|\s*$)//g;
    $ver_v =~ s/(^\s*|\s*$)//g;
    $ver_fixed =~ s/(^\s*|\s*$)//g;
    $ver_sp =~ s/(^\s*|\s*$)//g;

    die "Main $main_v is not like version $ver_v.\n" if $ver_v !~ m/^$main_v/;

    return $big_ver, $main_v, $ver_v, $ver_fixed, $ver_sp, $ver_id;
}

sub generate_html_file {
    my $doc_file = shift;
    my ($name,$dir,$suffix) = fileparse($doc_file, qr/\.[^.]*/);
    my $result;
    print "\t-Generating html file from $name$suffix.\t". (get_time_diff) ."\n";
    eval {
	local $SIG{ALRM} = sub { die "alarm\n" };
	alarm 1800;
	$result = `python ./unoconv -f html "$doc_file"`;
	alarm 0;
    };
    if ($@) {
	die "Timed out.\n";
    } else {
	print "\tFinished.\n";
    }

#    my $result = `/usr/bin/ooffice "$doc_file" -headless -invisible "macro:///Standard.Module1.runall()"`;
    print "\t+Generating html file from $name$suffix.\t". (get_time_diff) ."\n";
}

sub reset_time {
    $start_time = time();
}

sub array_diff {
    print "-Compute difference and uniqueness.\n";
    my ($arr1, $arr2) = @_;
    my (@only_in_arr1, @only_in_arr2, @common) = ();
## union: all, intersection: common, difference: unique in a and b
    my (@union, @intersection, @difference) = ();
    my %count = ();
    foreach my $element (@$arr1, @$arr2) { $count{"$element"}++ }
    foreach my $element (sort keys %count) {
	push @union, $element;
	push @{ $count{$element} > 1 ? \@intersection : \@difference }, $element;
# 	push @difference, $element if $count{$element} <= 1;
    }
    print "\tdifference done.\n";

    my $arr1_hash = ();
    $arr1_hash->{$_} = 1 foreach (@$arr1);

    foreach my $element (@difference) {
	if (exists $arr1_hash->{$element}) {
	    push @only_in_arr1, $element;
	} else {
	    push @only_in_arr2, $element;
	}
    }
    print "+Compute difference and uniqueness.\n";
    return \@only_in_arr1,  \@only_in_arr2,  \@intersection;
}

sub get_correct_customer{
    my $name = shift;
    return $name if $name =~ m/^\s*$/;
    return "MSTelcom" if $name eq "MSTelecom";
    return $name if $name eq "MINDUK_EMP";
    return "Mobee" if $name eq "MobeeTel";
    return "CWP" if $name eq "CWPanama";
    return "EastLink" if $name eq "EastLink";

    my $customers = WikiCommons::xmlfile_to_hash ("$real_path/customers.xml");
    my $crm_name = "";
    foreach my $nr (sort keys %$customers){
	$crm_name = $customers->{$nr}->{'displayname'};
	if ($crm_name =~ m/$name/i){
	    $crm_name = $name;
	    last;
	}
    }
# print "$name\t$crm_name\n";
    print "Customer $name could not be found in customers list.\n", return $name if $crm_name ne $name;
    return $crm_name;
}

return 1;
