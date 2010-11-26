package WikiMindSVN;

use warnings;
use strict;

use Switch;
use File::Find;
use Cwd 'abs_path';
use File::Basename;
use Data::Dumper;
$Data::Dumper::Sortkeys = 1;

our $pages_toimp_hash = {};
our $general_categories_hash = {};
our $count_files;
my $pages_ver = {};

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
    my ($ver, $main, $big_ver, $customer, $dir_type, $name) = @_;
    ## $general_categories_hash->{5.01.019}->{5.01} means that 5.01.019 will be in 5.01 category
    if ($ver ne "") {
	$general_categories_hash->{$ver}->{$main} = 1 if $ver ne $main;
	$general_categories_hash->{$ver}->{$big_ver} = 1 if $big_ver ne "";
	$general_categories_hash->{$ver}->{$customer} = 1 if $customer ne "";
	$general_categories_hash->{$ver}->{$dir_type} = 1 if $dir_type ne "";
    }

    if ($main ne "") {
	$general_categories_hash->{$main}->{$big_ver} = 1 if $big_ver ne "";
	$general_categories_hash->{$main}->{$customer} = 1 if $customer ne "";
	$general_categories_hash->{$main}->{$dir_type} = 1 if $dir_type ne "";
	$general_categories_hash->{$main}->{'Mind SVN autoimport'} = 1;
    }

    if ($customer ne "") {
	$general_categories_hash->{$customer}->{$dir_type} = 1 if $dir_type ne "";
	$general_categories_hash->{$customer}->{'MIND_Customers'} = 1;
	$general_categories_hash->{$customer}->{'Mind SVN autoimport'} = 1;
    }

    $general_categories_hash->{$name}->{'All SVN Documents'} = 1 if $name ne "";
    $general_categories_hash->{$big_ver}->{'Mind SVN autoimport'} = 1 if $big_ver ne "";
    $general_categories_hash->{$dir_type}->{'Mind SVN autoimport'} = 1 if $dir_type ne "";
    $general_categories_hash->{'Mind SVN autoimport'} = 1;
    $general_categories_hash->{'All SVN Documents'} = 1;
    $general_categories_hash->{'MIND_Customers'} = 1;

    ## Release Notes categories
    my $url_sep = WikiCommons::get_urlsep;
    $general_categories_hash->{$main}->{'Release Notes'} = 1 if $main =~ /($url_sep)RN$/;
    $general_categories_hash->{$customer}->{'Release Notes'} = 1 if $customer =~ /($url_sep)RN$/;
    $general_categories_hash->{$big_ver}->{'Release Notes'} = 1 if $big_ver =~ /($url_sep)RN$/;
}

sub fix_rest_dirs {
    my ($rest, $filename, $main, $ver) = @_;
    $rest =~ s/\/$filename$//;

    if (defined $main || defined $ver) {
	$rest =~ s/(^v?$main(\/|$))|((\/|^)v?$main$)//gi;
	$rest =~ s/(^v?$ver(\/|$))|((\/|^)v?$ver$)//gi;
	$rest =~ s/(^v?$ver(\/|$))|((\/|^)v?$ver)//gi;
	$rest =~ s/(^v?$main(\/|$))|((\/|^)v?$main)//gi;
    }

    $rest =~ s/\/{1,}/\//g;
    $rest =~ s/^Documents\///;
    my $url_sep = WikiCommons::get_urlsep;
    $rest =~ s/\//$url_sep/g;

    return $rest;
}

sub add_document {
    my ($doc_file,$dir_type, $path_file) = @_;

    $doc_file = abs_path($doc_file);
    my $doc_filesize = -s "$doc_file";
    return if ($doc_filesize == 0);
    my $basic_url = ""; my $rest = ""; my $customer = "";
    my $main = ""; my $ver = ""; my $ver_fixed = ""; my $big_ver = ""; my $ver_sp = ""; my $ver_id = "";
    my $rel_path = ""; my $svn_url = ""; my $fixed_name = "";
    my $known_customer = 1;

    my $str = $doc_file;
    #  remove svn_dir
    $str =~ s/^$path_file\/$dir_type\///;
    $rel_path = "$dir_type/$str";
    $svn_url = find_svn_helper ($doc_file, $path_file);
    my ($name,$dir,$suffix) = fileparse($str, qr/\.[^.]*/);

    my @values = split('\/', $str);

    $dir_type = "SC" if ($name =~ m/^B[[:digit:]]{4,}\s+/);
    my $url_sep = WikiCommons::get_urlsep;
    $customer = "$1" if ($str =~ m/.*\/([^\/]+)(branded|users? manuals?)\//i);

    switch ("$dir_type") {
    case "Projects" {
        ($big_ver, $main, $ver, $ver_fixed, $ver_sp, $ver_id) = WikiCommons::check_vers ( $values[0], $values[1]);
        $fixed_name = WikiCommons::fix_name ($name, $customer, $big_ver, $main, $ver, $ver_sp, $ver_id);
        $rest = fix_rest_dirs ($str, quotemeta $values[$#values], $values[0], $values[1]);
	if ($customer eq "") {
	    $basic_url = "$url_sep$ver_fixed";
	} else {
	    $basic_url = "$url_sep$ver_fixed$url_sep$customer";
	}
    }
    case "Docs" {
        ($big_ver, $main, $ver, $ver_fixed, $ver_sp, $ver_id) = WikiCommons::check_vers ( $values[0], $values[1]);
# print "xxx:$values[0], $values[1]\n";
        $fixed_name = WikiCommons::fix_name ($name, $customer, $big_ver, $main, $ver, $ver_sp, $ver_id);
        $rest = fix_rest_dirs ($str, quotemeta $values[$#values], $values[0], $values[1]);
	if ($customer eq "") {
	    $basic_url = "$url_sep$ver_fixed";
	} else {
	    $basic_url = "$url_sep$ver_fixed$url_sep$customer";
	}
    }
    case "Projects_Deployment" {
        ($big_ver, $main, $ver, $ver_fixed, $ver_sp, $ver_id) = WikiCommons::check_vers ( $values[0], $values[0]);
        $fixed_name = WikiCommons::fix_name ($name, $customer, $big_ver, $main, $ver, $ver_sp, $ver_id);
        $rest = fix_rest_dirs ($str, quotemeta $values[$#values], $values[0], $values[0]);
	if ($customer eq "") {
	    $basic_url = "$url_sep$ver_fixed";
	} else {
	    $basic_url = "$url_sep$ver_fixed$url_sep$customer";
	}
    }
    case "Docs_Customizations" {
        ($big_ver, $main, $ver, $ver_fixed, $ver_sp, $ver_id) = WikiCommons::check_vers ( $values[1], $values[2]);
        $customer = $values[0];
        $str =~ s/^$customer\///;
	my $customer_good = WikiCommons::get_correct_customer($customer);
	if (defined $customer_good) {
	    $customer = $customer_good;
	} else {
	    $known_customer = 0;
	}
        $str =~ s/^$customer\///;
	my $q = "";
	$q = $values[2] if $values[2] =~ m/^\s*v?[0-9]{1,}(\.[0-9]{1,})*\s*([a-z0-9 ]{1,})?\s*(SP\s*[0-9]{1,}(\.[0-9]{1,})*)?\s*(demo)?\s*$/;

        $fixed_name = WikiCommons::fix_name ( $name, $values[0], $big_ver, $main, $ver, $ver_sp, $ver_id);
        $rest = fix_rest_dirs ($str, quotemeta $values[$#values], $values[1], $q);
        $basic_url = "$url_sep$ver_fixed$url_sep$customer";
    }
    case "Projects_Customizations" {
        ($big_ver, $main, $ver, $ver_fixed, $ver_sp, $ver_id) = WikiCommons::check_vers ( $values[1], $values[2]);
        $customer = $values[0];
        $str =~ s/^$customer\///;
	my $customer_good = WikiCommons::get_correct_customer($customer);
	if (defined $customer_good) {
	    $customer = $customer_good;
	} else {
	    $known_customer = 0;
	}
        $str =~ s/^$customer\///;

        $fixed_name = WikiCommons::fix_name ($name, $values[0], $big_ver, $main, $ver, $ver_sp, $ver_id);
        $rest = fix_rest_dirs ($str, quotemeta $values[$#values], $values[1], $values[2]);
        $basic_url = "$url_sep$ver_fixed$url_sep$customer";
    }
    case "Projects_Deployment_Customization" {
        $customer = $values[0];
        $str =~ s/^$customer\///;
	my $customer_good = WikiCommons::get_correct_customer($customer);
	if (defined $customer_good) {
	    $customer = $customer_good;
	} else {
	    $known_customer = 0;
	}
        $str =~ s/^$customer\///;

	my $ver_o = "";
	if ( scalar @values == 2 ) {
	    $rest = "";
	} else {
	    $ver_o = $values[1] if $values[1] =~ m/^v?[[:digit:]]{1,}(\.[[:digit:]]{1,}){0,}( )?([a-z]*?[[:digit:]]{1,})$/i;
	    $ver_o = $values[$#values-1] if $values[$#values-1] =~ m/^v?[[:digit:]]{1,}(\.[[:digit:]]{1,}){0,}( )?([a-z]*?[[:digit:]]{0,})$/i;
	    if ($ver_o ne '' ){
		($big_ver, $main, $ver, $ver_fixed, $ver_sp, $ver_id) = WikiCommons::check_vers ( $ver_o, $ver_o);
		$rest = fix_rest_dirs ($str, quotemeta $values[$#values], $ver_o, $ver_o);
	    } else {
		$rest = fix_rest_dirs ($str, quotemeta $values[$#values]);
	    }
	}

        $fixed_name = WikiCommons::fix_name ( $name, $values[0], $big_ver, $main, $ver, $ver_sp, $ver_id);
	if ($ver ne '' ){
	    $basic_url = "$url_sep$ver_fixed$url_sep$customer";
	} else {
	    $basic_url = "$url_sep$customer";
	}
    }
    case "Projects_Common" {
        $rest = fix_rest_dirs ($str, quotemeta $values[$#values]);
        $customer = "_Common for all customers_";
        $fixed_name = WikiCommons::fix_name ($name, $customer);
        $basic_url = "";
    }
    case "Projects_Deployment_Common" {
	if ( scalar @values == 1 ) {
	    $rest = "";
	} else {
	    $rest = fix_rest_dirs ($str, quotemeta $values[$#values]);
	}
        $customer = "_Common for all customers_";
        $fixed_name = WikiCommons::fix_name ( $name, $customer );
        $basic_url = "";
    }
    case "SC" {
	$basic_url = "$name";
	return 1;
    }
    else { die "Unknown document type: $dir_type.\n" }
    }

    $fixed_name = fix_naming($fixed_name, $customer) if ($dir !~ /\/(.*? )?Release Notes\//i);
    $fixed_name = WikiCommons::normalize_text( $fixed_name );
    $fixed_name = WikiCommons::capitalize_string( $fixed_name, 'first' );
    my $page_url = "$fixed_name$basic_url";
    my $page_url_caps = WikiCommons::capitalize_string( $page_url, 'small' );
    die "No page for $doc_file.\n" if ($page_url eq "" );

    ++$count_files;
    print "\tNumber of files: ".($count_files)."\t". (WikiCommons::get_time_diff) ."\n" if ($count_files%100 == 0);

    ### Release Notes
    if ($dir =~ /\/(.*? )?Release Notes\//i) {
	return 1 if $ver_fixed lt "5.00";
	$page_url = $fixed_name;
	my $nodot_ver = $ver;
	$nodot_ver =~ s/\.//g;
	$page_url =~ s/RN$nodot_ver\s*//;
	$page_url =~ s/(General|All)? Release Notes|PDF//gi;
	$page_url = "$page_url $ver_id" if $page_url !~ m/$ver_id/gi;
	$page_url = "RN:$ver $page_url$url_sep$rest";
	$page_url =~ s/\s+/ /g;

	$main = $main.$url_sep."RN" if $main ne "";
	$big_ver = $big_ver.$url_sep."RN" if $big_ver ne "";
	my @categories = ();
	push @categories, $main;
	push @categories, $big_ver;
	generate_categories("", $main, $big_ver, "", $dir_type, "");
	die "RN $page_url already exists:\n\t$rel_path\n".Dumper($pages_toimp_hash->{$page_url}) if exists $pages_toimp_hash->{$page_url};
# 	$pages_toimp_hash->{$page_url} = [WikiCommons::get_file_md5($doc_file), $rel_path, $svn_url, "link", \@categories];
	$pages_toimp_hash->{$page_url} = [1, $rel_path, $svn_url, "link", \@categories];
	return 0;
    }

    my $full_ver = "$ver $ver_id $ver_sp";

    return 1 if $ver_fixed lt "5.00" && $ver_fixed ne "";
    return 0 if (exists $pages_ver->{$page_url_caps}->{'ver'} && $pages_ver->{$page_url_caps}->{'ver'} gt "$full_ver");

    my @categories = ();
    if ($fixed_name !~ m/^DB Changes For/i) {
	push @categories, $ver_fixed;
	push @categories, $main;
	push @categories, $big_ver;
	push @categories, $customer;
	push @categories, $fixed_name;
	generate_categories($ver_fixed, $main, $big_ver, $customer, $dir_type, $fixed_name);
    }

# print "2. $page_url\n";

    if (exists $pages_ver->{$page_url_caps}->{'ver'} && "$pages_ver->{$page_url_caps}->{'ver'}" eq "$full_ver") {

	my $new = WikiCommons::svn_info("$path_file/$rel_path", "", "");
	if (defined $new) {
	    $new =~ s/^.*?\nChecksum: (.*?)\n.*?$/$1/gs;
	    chomp $new;
	} else {
	    $new = WikiCommons::get_file_md5($doc_file);
	}

	my $old = WikiCommons::svn_info("$path_file/$pages_toimp_hash->{$page_url}[1]", "", "");
	if (defined $old) {
	    $old =~ s/^.*?\nChecksum: (.*?)\n.*?$/$1/gs;
	    chomp $old;
	} else {
	    $old = $pages_toimp_hash->{$page_url}[0];
	}

	if ($new ne $old) {
	    my $id = 1;
	    $id = $pages_ver->{$page_url_caps}->{'id'} + 1 if (exists $pages_ver->{$page_url_caps}->{'id'});
	    $page_url .= "$url_sep"."$id";
	    $pages_ver->{$page_url_caps}->{'id'} = $id;
	}
    }

    $pages_toimp_hash->{$page_url} = [WikiCommons::get_file_md5($doc_file), $rel_path, $svn_url, "link", \@categories];
    $pages_ver->{$page_url_caps}->{'ver'} = "$full_ver";

#     push(@{$pages_ver->{"$fixed_name$url->{'ver'}_sep$ver_without_sp"}}, $ver_sp);
}

sub get_documents {
    my $self = shift;
    my @APPEND_DIRS=("Docs", "Docs_Customizations", "Projects", "Projects_Common", "Projects_Customizations", "Projects_Deployment", "Projects_Deployment_Common", "Projects_Deployment_Customization");
    my $url_sep = WikiCommons::get_urlsep;
    foreach my $append_dir (@APPEND_DIRS) {
	print "-Searching for files in $append_dir.\t". (WikiCommons::get_time_diff) ."\n";
	$count_files = 0;
	find sub { add_document ($File::Find::name, $append_dir, "$self->{path_files}", "$url_sep") if -f && (/(\.doc|\.docx|\.rtf)$/i) }, "$self->{path_files}/$append_dir" if  (-d "$self->{path_files}/$append_dir");
	find sub { add_document ($File::Find::name, $append_dir, "$self->{path_files}", "$url_sep") if -f && /.*parameter.*Description.*\.xls$/i }, "$self->{path_files}/$append_dir" if  (-d "$self->{path_files}/$append_dir");
	print "\tTotal number of files: ".($count_files)."\t". (WikiCommons::get_time_diff) ."\n";
	print "+Searching for files in $append_dir.\t". (WikiCommons::get_time_diff) ."\n";
    }

    return $pages_toimp_hash;
}

sub find_svn_helper {
    my $doc_file = shift;
    my $path_file = shift;
    my ($name,$dir,$suffix) = fileparse($doc_file, qr/\.[^.]*/);
    my $tmp = $dir;
    my $q = quotemeta 'svn_helper_trunk_info.txt';
    do {
	if (-e "$dir/svn_helper_trunk_info.txt") {
	    $tmp =~ s/^$dir//;
	    open(SVN, "$dir/svn_helper_trunk_info.txt");
	    my @svn_info_text = <SVN>;
	    close SVN;
	    my $svn_url = (split ('=', $svn_info_text[0]))[1];
	    $svn_url =~ s/(^\s+|(\/)?\s+$)//g;
	    return "$svn_url$tmp\/$name$suffix";
	}
	$dir = dirname($dir);
    } while ($dir ne "$path_file");
    die "should have found a wiki helper until now for $doc_file: dir $dir svndir $path_file.\t". (WikiCommons::get_time_diff) ."\n";
}

sub fix_naming {
    my ($fixed_name, $customer) = @_;
# print "1. $fixed_name\n";

    $fixed_name =~ s/^$customer|$customer$//gi;
    ## Specific updates
    $fixed_name =~ s/\s+ver\s*$//i;
    $fixed_name =~ s/\s+for\s*$//i;
    $fixed_name =~ s/jinny/Jinny/gi;
    $fixed_name =~ s/^User Guide|User Guide$//i;
    $fixed_name =~ s/^User Manual|User Manual$//i;

    $fixed_name =~ s/^\budr\b/UDR/i;
#     $fixed_name = "$1" if ($fixed_name =~ m/^GN (.*)/);

    $fixed_name = "CDR Drivers - 3G" if ($fixed_name =~ m/^3G CDR Drivers$/i);
    $fixed_name = "Administrator" if ($fixed_name =~ m/^Administrator User Manual 5.3$/i);
    $fixed_name = "Administrator" if ($fixed_name =~ m/^Administrator Manuel D'Utilisation$/i);
    $fixed_name = "Auxiliary Module Applications" if ($fixed_name =~ m/^Auxiliary Applications 5.3$/i);
    $fixed_name = "Billing" if ($fixed_name =~ m/^BillingUserManual5.0-Rev12$/i);
    $fixed_name = "Billing" if ($fixed_name =~ m/^BillingUserManual5.01-Rev12$/i);
    $fixed_name = "Billing" if ($fixed_name =~ m/^BillingUserManual5.01-Rev13Kenan$/i);
    $fixed_name = "Business Processes Deployment" if ($fixed_name =~ m/^Business Processes Deployment 601$/i);
    $fixed_name = "Cashier" if ($fixed_name =~ m/^Cashier5.21.Rev10$/i);
    $fixed_name = "Cashier" if ($fixed_name =~ m/^Cashier Manuel D'Utilisation$/i);
    $fixed_name = "CallShop" if ($fixed_name =~ m/^5.31.005 CallShop Manuel d'Utilisation$/i);
    $fixed_name = "CDR Export" if ($fixed_name =~ m/^CDR Export User Guide 5.0$/i);
    $fixed_name = "Cisco User Manual" if ($fixed_name =~ m/^Cisco 5.31.001 User Manual$/i);
    $fixed_name = "Cisco SSG Configuration" if ($fixed_name =~ m/^Cisco SSG Configuration UserManuall5.0$/i);
    $fixed_name = "Collector" if ($fixed_name =~ m/^Collector 5.3$/i);
    $fixed_name = "Correlation" if ($fixed_name =~ m/^Correlation Rev10$/i);
    $fixed_name = "Configuration Parameters" if ($fixed_name =~ m/^ConfigurationParameters$/i);
    $fixed_name = "Dashboard" if ($fixed_name =~ m/^Dashboard5.30$/i);
    $fixed_name = "DB Documentation" if ($fixed_name =~ m/^5.31 DB Documentation$/i);
    $fixed_name = "EDI For Payment" if ($fixed_name =~ m/^EDI For Payment 5.21$/i);
    $fixed_name = "ETL Staging Area - DB Documentation" if ($fixed_name =~ m/^DB Documentation ETLStagingArea$/i);
    $fixed_name = "ETL Installation Guide" if ($fixed_name =~ m/^ETL INSTALLATION GUIDE$/i);
    $fixed_name = "Guard" if ($fixed_name =~ m/^Guard Rev13$/i);
    $fixed_name = "Guard" if ($fixed_name =~ m/^GN Guard Manuel d'Utilisation$/i);
    $fixed_name = "Install Cisco Rev10" if ($fixed_name =~ m/^InstallCisco5.0InstallB-Rev10$/i);
    $fixed_name = "Install Cisco Rev11" if ($fixed_name =~ m/^InstallCisco5.0InstallA-Rev11$/i);
    $fixed_name = "IGuard80" if ($fixed_name =~ m/^IGuard80-Rev10$/i);
    $fixed_name = "Invoice Generation" if ($fixed_name =~ m/^Invoice Generation 5.30$/i);
    $fixed_name = "Invoice Generation" if ($fixed_name =~ m/^Invoice Generation 5.31$/i);
    $fixed_name = "Itraf80" if ($fixed_name =~ m/^Itraf80-Rev10$/i);
    $fixed_name = "Interception Monitor" if ($fixed_name =~ m/^Interception 5.2Monitor Rev11$/i);
    $fixed_name = "LDAP SunOne Provisioning Client" if ($fixed_name =~ m/^LDAPSunOne Provisioning Client 5.31.001$/i);

    $fixed_name = "Manager" if ($fixed_name =~ m/^Manager User Manual 5.21-Rev.11$/i);
    $fixed_name = "Manager" if ($fixed_name =~ m/^Manager User Manual 5.3$/i);
    $fixed_name = "Manager" if ($fixed_name =~ m/^Manager Manuel D'Utilisation$/i);
    $fixed_name = "Multisite Failover Manager" if ($fixed_name =~ m/^MultisiteFailoverManager5.01$/i);
    $fixed_name = "CSR - Manual De Utilizare MINDBill" if ($fixed_name =~ m/^Manual De Utilizare MINDBill CSR$/i);
    $fixed_name = "Rapoarte MINDBill - Manual De Utilizare" if ($fixed_name =~ m/^Manual de Utilizare Rapoarte MINDBill$/i);
    $fixed_name = "CSR - Manual De Utilizare MINDBill" if ($fixed_name =~ m/^Modules Deployment (6.01|6.50|6.60|7.00)$/i);
    $fixed_name = "Neils Revision" if ($fixed_name =~ m/^50001neilsrevision$/i);
    $fixed_name = "New Features Summary" if ($fixed_name =~ m/^New Features Summary MIND-IPhonEX 5.30.010$/i);
    $fixed_name = "New Features Summary" if ($fixed_name =~ m/^New Features Summary MIND-IPhonEX 5.30.013$/i);
    $fixed_name = "Open View Operation" if ($fixed_name =~ m/^OpenViewOperations5.30$/i);

    $fixed_name = "Parameters Description" if ($fixed_name =~ m/^Parameter Description Ver 601$/i);
    $fixed_name = "Parameters Description" if ($fixed_name =~ m/^Parameter Description 6.00$/i);
    $fixed_name = "Parameters Description" if ($fixed_name =~ m/^Parameters? Descriptions?/i);

    $fixed_name =~ s/Provisionig/Provisioning/;
    $fixed_name = "Provisioning Clients" if ($fixed_name =~ m/^Provisioning Client$/i);

    $fixed_name = "Pre-Release" if ($fixed_name =~ m/^5.0Pre-Release$/i);
    $fixed_name = "Process Configuration Documentation PackageChange" if ($fixed_name =~ m/^6.01 Process Configuration Documentation PackageChange$/i);
    $fixed_name = "Product Description" if ($fixed_name =~ m/^Product Description 5.21-Rev.12$/i);
    $fixed_name = "Product Description" if ($fixed_name =~ m/^Product Description5.3$/i);
    $fixed_name = "Product Description" if ($fixed_name =~ m/^ProductDescription 5.0$/i);

    $fixed_name = "Provisioning Solution" if ($fixed_name =~ m/^Provisioning Solution UserManual5.0$/i);
    $fixed_name = "Reports" if ($fixed_name =~ m/^Reports Guide D'Utilisation$/i);
    $fixed_name = "Resource Management" if ($fixed_name =~ m/^Resource Management Manuel D'Utilisation$/i);
    $fixed_name = "Rule Rating Editor" if ($fixed_name =~ m/^Rule-Rating-Editor-Rev10$/i);

    $fixed_name = "Rapoarte Crystal - Interconnect" if ($fixed_name =~ m/^Manual De Utilizare MINDBill 6.01 Rapoarte Crystal - Interconnect$/i);
    $fixed_name = "Release Notes V3" if ($fixed_name =~ m/^5.2x Release Notes V3$/i);
    $fixed_name = "Reports User Guide" if ($fixed_name =~ m/^Reports User Guide For$/i);
    $fixed_name = "System Overview" if ($fixed_name =~ m/^5.00.015 System Overview$/i);
    $fixed_name = "Task Scheduler" if ($fixed_name =~ m/^Task Scheduler User Guide 5.3$/i);
    $fixed_name = "UDR Distribution" if ($fixed_name =~ m/^UDRDistributionUserGuide5.01-Rev10$/i);
    $fixed_name = "User Activity" if ($fixed_name =~ m/^UserActivity5.30$/i);
    $fixed_name = "Administrator" if ($fixed_name =~ m/^AdminUserManual5.02-Rev15$/i);
    $fixed_name = "Billing Vodafone" if ($fixed_name =~ m/^BillingUserManual5.02-rev14Vodafone$/i);
    $fixed_name = "Dialup CDR And Invoice Generation" if ($fixed_name =~ m/^Dialup CDR And Invoice Generation 521$/i);
    $fixed_name = "Vendors Support" if ($fixed_name =~ m/^VendorsSupport$/i);
    $fixed_name = "User Activity" if ($fixed_name =~ m/^UserActivity5 30$/i);
    $fixed_name = "Checkpoint LEA Configuration" if ($fixed_name =~ m/^Checkpoint LEAconfiguration$/i);
    $fixed_name = "High Availability" if ($fixed_name =~ m/^HighAvailability$/i);
    $fixed_name = "LEA Client Installation" if ($fixed_name =~ m/^LEAClientInstallation$/i);
    $fixed_name = "Load Balancing" if ($fixed_name =~ m/^LoadBalancing$/i);
    $fixed_name = "Parsing Rules" if ($fixed_name =~ m/^ParsingRules$/i);

    $fixed_name = "Plugin Point In Recalc" if ($fixed_name =~ m/^PluginPointInRecalc$/i);
    $fixed_name = "Processor Logs Files" if ($fixed_name =~ m/^ProcessorLogsFiles$/i);
    $fixed_name = "Proxy Manager Server" if ($fixed_name =~ m/^ProxyManagerServer$/i);
    $fixed_name = "Statistics Description" if ($fixed_name =~ m/^StatisticsDescription$/i);
    $fixed_name = "DB Documentation$1" if ($fixed_name =~ m/6.00 DB Documentation(.*)/);
    $fixed_name = "DB Import" if ($fixed_name =~ m/^DBImport$/i);
    $fixed_name = "Display CDR Field Instructions" if ($fixed_name =~ m/^DisplayCDRFieldInstructions$/i);
    $fixed_name = "Fix Invoice XML Deployment" if ($fixed_name =~ m/^FixInvoiceXML Deployment$/i);
    $fixed_name = "Install Oracle 10g Veracity" if ($fixed_name =~ m/^InstallOracle10g Veracity$/i);
    $fixed_name = "Business Processes Monitoring Deployment" if ($fixed_name =~ m/^BP Monitoring Deployment$/i);
    $fixed_name = "System - DB Documentation" if ($fixed_name =~ m/^DB Documentation Syetem$/i);
    $fixed_name = "Sebanci Telecom EPay Credit Adapter API" if ($fixed_name =~ m/^Sabanci Telecom EPay Credit Adapter API$/i);
    $fixed_name = "SES VF Greece QS Product Description" if ($fixed_name =~ m/^SES VF Greece QS ProductDescription$/i);
    $fixed_name = "SNMP Client Paramaters Descriptions" if ($fixed_name =~ m/^SNMPClient Paramaters Descriptions$/i);

    $fixed_name = "User Activity Tracker" if ($fixed_name =~ m/^User Activity Tracker Manuel D'Utilisation$/i);
    $fixed_name = "VOIPCDR Upgrade Procedure" if ($fixed_name =~ m/^VOIPCDR Upgrade Procedure 601$/i);
    $fixed_name = "WebBill" if ($fixed_name =~ m/^5.3 WebBill User Manual/i);
    $fixed_name = "WebBill" if ($fixed_name =~ m/^WebBill 5.2 User Manual/i);
    $fixed_name = "WebBill" if ($fixed_name =~ m/^WebBillUserManual5.0-Rev10$/i);
    $fixed_name = "WebBill" if ($fixed_name =~ m/^WebBillUserManual5.01-Rev11$/i);
    $fixed_name = "WebClient" if ($fixed_name =~ m/^WebClient5.0-Rev11$/i);
    $fixed_name = "WebClient" if ($fixed_name =~ m/^WebClient5.30$/i);
    $fixed_name = "WebClient" if ($fixed_name =~ m/^WebClient5.01-Rev11$/i);
    $fixed_name = "WebClient" if ($fixed_name =~ m/^WebClient Manuel D'Utilisation$/i);

    $fixed_name =~ s/Wizards API/Wizard API/;
    $fixed_name = "IPE Monitor$1" if ($fixed_name =~ m/^IPEMonitor(.*)$/i);
    $fixed_name = "Radius Paramaters$1" if ($fixed_name =~ m/^RadiusParamaters(.*)$/i);

    $fixed_name = "$1 - Data Dictionary Tables" if ($fixed_name =~ m/Data Dictionary Tables\s*-?\s*(.*)/i && defined $1 && $1 !~ m/^\s*$/);
    $fixed_name = "$1 - DB Documentation" if ($fixed_name =~ m/DB Documentation\s*-?\s*([a-z0-9]{1,})/i && defined $1 && $1 !~ m/^\s*$/);

    $fixed_name =~ s/^\s*|\s*$//g;
# print "2. $fixed_name\n" if $fixed_name =~ m/WebBill/;
    return $fixed_name;
}

return 1;

