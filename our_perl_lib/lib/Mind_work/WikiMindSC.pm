package WikiMindSC;

use warnings;
use strict;

use DBI;
use Data::Dumper;
$Data::Dumper::Sortkeys = 1;
use Log::Log4perl qw(:easy);
use File::Path qw(make_path remove_tree);

our $pages_toimp_hash = {};
our $general_categories_hash = {};

my ($wikidb_server, $wikidb_name, $wikidb_user, $wikidb_pass) = ();
open(FH, "/var/www/html/wiki/LocalSettings.php") or LOGDIE "Can't open file for read: $!.\n";
while (<FH>) {
  $wikidb_server = $2 if $_ =~ m/^(\s*\$wgDBserver\s*=\s*\")(.+)(\"\s*;\s*)$/;
  $wikidb_name = $2 if $_ =~ m/^(\s*\$wgDBname\s*=\s*\")(.+)(\"\s*;\s*)$/;
  $wikidb_user = $2 if $_ =~ m/^(\s*\$wgDBuser\s*=\s*\")(.+)(\"\s*;\s*)$/;
  $wikidb_pass = $2 if $_ =~ m/^(\s*\$wgDBpassword\s*=\s*\")(.+)(\"\s*;\s*)$/;
}
close(FH);
my $dbh_mysql = DBI->connect("DBI:mysql:database=$wikidb_name;host=$wikidb_server", "$wikidb_user", "$wikidb_pass");

sub new {
    my $class = shift;
    my $self = { path_files => shift , url_sep => shift};
    bless($self, $class);
    return $self;
}

sub get_categories {
    return $general_categories_hash;
}

sub generate_categories {
    my ($ver, $main, $big_ver, $customer, $dir_type) = @_;
#     ## $general_categories_hash->{5.01.019}->{5.01} means that 5.01.019 will be in 5.01 category
}

sub get_documents {
    my $self = shift;
    my $path_files = $self->{path_files};
    opendir(DIR, "$path_files") || LOGDIE "Cannot open directory $path_files.\n";
    my @all = grep { (!/^\.\.?$/) && -d "$path_files/$_" } readdir(DIR);
    closedir(DIR);

    my $total = @all;
    my $count = 0;
    my $url_sep = WikiCommons::get_urlsep;
    INFO "-Searching for files in SC dir.\n";
    foreach my $node (sort @all) {
	$count++;
	INFO "\tDone $count from a total of $total.\n" if ($count%2000 == 0);
	my $md5 = $node;
	my $ret = $dbh_mysql->selectrow_array("select FILES_INFO_CRT from mind_sc_ids_versions where SC_ID='$node'");
	if (! defined $ret) {
	    ERROR "Could not find id=$node in mind_sc_ids_versions table. Delete $path_files/$node.\n";
	    remove_tree("$path_files/$node"); 
	    next;
	}

	my @data = split "\n", $ret;

	my @categories = ();
	my $info_crt_h ;
# 	my $url_namespace = "SC_iPhonex_Bug";
	my $url_namespace = "";
	foreach my $line (@data) {
	    $line .= " " if $line =~ m/^(.*)\;$/;
	    my @tmp = split ';', $line;
	    chomp @tmp;

	    if ($tmp[0] eq "Categories") {
		foreach my $q (@tmp) {
		    $q =~ s/(^\s*)|(\s*$)//g;
		    if ($q =~ m/^has_deployment/i){
			my $has_deployment = $q;$has_deployment =~ s/^has_deployment\s+//;
			ERROR "WTF is this: has_deployment = $has_deployment\n".Dumper(@data) if $has_deployment ne 'Y';
			push @categories, $q;
# INFO "$has_deployment\n";
		    }
		    next if $q !~ "^ChangeType";
		    my $sc_type = $q;
		    $sc_type =~ s/^ChangeType\s+//;
		    push @categories, $q;
		    if ($sc_type ne "Change" && $sc_type ne "Bug") {
			ERROR "\tSC type is unknown: $sc_type.\n";
			$sc_type = "Bug";
		    }
		    if ( $path_files =~ m/canceled/i ) {
			$url_namespace = "SC_Canceled";
		    } elsif ($node =~ m/^B/i) {
			$url_namespace = "SC_iPhonex_$sc_type";
		    } elsif ($node =~ m/^F/i) {
			$url_namespace = "SC_SIP_$sc_type";
		    } elsif ($node =~ m/^I/i) {
			$url_namespace = "SC_Sentori_$sc_type";
		    } elsif ($node =~ m/^H/i) {
			$url_namespace = "SC_Infrastructure_$sc_type";
		    } elsif ($node =~ m/^R/i) {
			$url_namespace = "SC_PaymentManager_$sc_type";
		    } elsif ($node =~ m/^D/i) {
			$url_namespace = "SC_PhonexONE_$sc_type";
		    } elsif ($node =~ m/^E/i) {
			$url_namespace = "SC_CMS_$sc_type";
		    } elsif ($node =~ m/^G/i) {
			$url_namespace = "SC_MindReporter_$sc_type";
		    } elsif ($node =~ m/^S/i) {
			$url_namespace = "SC_Simulators_$sc_type";
		    } elsif ($node =~ m/^T/i) {
			$url_namespace = "SC_Nagios_$sc_type";
		    } elsif ($node =~ m/^Z/i) {
			$url_namespace = "SC_Other_$sc_type";
		    } elsif ($node =~ m/^K/i) {
			$url_namespace = "SC_Abacus_$sc_type";
		    } elsif ($node =~ m/^A/i) {
			$url_namespace = "SC_PhonEX_$sc_type";
		    } elsif ($node =~ m/^P/i) {
			$url_namespace = "SC_Plugins_$sc_type";
		    } else {
LOGDIE "no namespace here 1: $node.\n".Dumper(@data);
			$url_namespace = "SC_iPhonex_$sc_type";
		    }
		    push @categories, "RealNameSpace ".$url_namespace;
		    next;

		    if ($q =~ m/^customer /i){
			my $customer = $q; $customer =~ s/^customer //i;
			next if $customer =~ m/^\s*$/;
			$customer = $customer.$url_sep."SC";
			push @categories, "customer ".$customer;
		    } elsif ($q =~ m/^version /i) {
			my $w = $q; $w =~ s/^version //i; $w =~ s/\.$//;
			next if $w =~ m/^\s*$/;
			$w =~ s/\s+p\s*//i;

			my ($big_ver, $main, $ver, $ver_fixed, $ver_sp, $ver_id) = WikiCommons::check_vers ( $w, $w);
			$big_ver = $big_ver.$url_sep."SC";
			$main = $main.$url_sep."SC";
			$ver_fixed = $ver_fixed.$url_sep."SC";
			push @categories, "version_b ".$big_ver;
			push @categories, "version_m ".$main;
			push @categories, "version_v ".$ver_fixed;
		    } else {
			LOGDIE "Unknown category in $line: $q.\n";
		    }
		}
# 		next;
	    } else {
		$md5 .= "$tmp[2]" if defined $tmp[2];
		LOGDIE "Wrong number of fields for line $line in $node.\n" if @tmp < 4 || @tmp > 5;
		$info_crt_h->{$tmp[0]}->{'name'} = "$tmp[1]";
		$info_crt_h->{$tmp[0]}->{'size'} = "$tmp[2]";
		$info_crt_h->{$tmp[0]}->{'revision'} = "$tmp[3]";
		$info_crt_h->{$tmp[0]}->{'date'} = "$tmp[4]" if defined $tmp[4];
	    }
	}
LOGDIE "no namespace here 2: $node.\n".Dumper(@data) if $url_namespace eq "";
	$pages_toimp_hash->{"$url_namespace:$node"} = [$md5." redirect", "$node", $info_crt_h, "real", \@categories];
	$pages_toimp_hash->{"SC:$node"} = [$md5, "$node", $info_crt_h, "real", \@categories];
    }
    INFO "\tDone $count from a total of $total.\n" if ($count%500 != 0);
    INFO "+Searching for files in SC dir.\n";
# INFO Dumper($pages_toimp_hash);exit 1;
    return $pages_toimp_hash;
}

return 1;
