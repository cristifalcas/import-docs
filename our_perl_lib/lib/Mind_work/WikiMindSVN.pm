package WikiMindSVN;

use warnings;
use strict;

# use Switch;
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
# 	$general_categories_hash->{$customer}->{$dir_type} = 1 if $dir_type ne "";
# 	$general_categories_hash->{$customer}->{'MIND_Customers'} = 1;
# 	$general_categories_hash->{$customer}->{'Mind SVN autoimport'} = 1;
    }

    $general_categories_hash->{$big_ver}->{'Mind SVN autoimport'} = 1 if $big_ver ne "";
    $general_categories_hash->{$dir_type}->{'Mind SVN autoimport'} = 1 if $dir_type ne "";
    $general_categories_hash->{$name}->{'All SVN Documents'} = 1 if $name ne "";

    $general_categories_hash->{'Mind SVN autoimport'} = 1;
    $general_categories_hash->{'All SVN Documents'} = 1;
#     $general_categories_hash->{'MIND_Customers'} = 1;
    $general_categories_hash->{'Release Notes'} = 1;

    ## Release Notes categories
    my $url_sep = WikiCommons::get_urlsep;
    $general_categories_hash->{$main}->{'Release Notes'} = 1 if $main =~ / RN$/;
    $general_categories_hash->{$customer}->{'Release Notes'} = 1 if $customer =~ / RN$/;
    $general_categories_hash->{$big_ver}->{'Release Notes'} = 1 if $big_ver =~ / RN$/;
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

    my $url_sep = WikiCommons::get_urlsep;
    if ($str =~ m/.*\/([^\/]+)(branded|users? manuals?)\//i) {
	$customer = "$1";
	my $q = $customer;
	$customer = WikiCommons::get_correct_customer($customer);
	if (! defined $customer) {
	    print "EE** Unknown customer $q from file $doc_file.\n";
	    $customer = "";
	}
    }

    if ($dir_type eq "Projects") {
        ($big_ver, $main, $ver, $ver_fixed, $ver_sp, $ver_id) = WikiCommons::check_vers ( $values[0], $values[1]);
        $fixed_name = WikiCommons::fix_name ($name, $customer, $big_ver, $main, $ver, $ver_sp, $ver_id);
        $rest = fix_rest_dirs ($str, quotemeta $values[$#values], $values[0], $values[1]);
	$basic_url = "$url_sep$ver_fixed";
    } elsif ($dir_type eq "Docs" || $dir_type eq "Docs_POS" || $dir_type eq "Docs_SIPServer" || $dir_type eq "Docs_PaymentManager_Deployment") {
        ($big_ver, $main, $ver, $ver_fixed, $ver_sp, $ver_id) = WikiCommons::check_vers ( $values[0], $values[1]);
        $fixed_name = WikiCommons::fix_name ($name, $customer, $big_ver, $main, $ver, $ver_sp, $ver_id);
        $rest = fix_rest_dirs ($str, quotemeta $values[$#values], $values[0], $values[1]);
	$basic_url = "$url_sep$ver_fixed";
    } elsif ($dir_type eq "Projects_Deployment") {
        ($big_ver, $main, $ver, $ver_fixed, $ver_sp, $ver_id) = WikiCommons::check_vers ( $values[0], $values[0]);
        $fixed_name = WikiCommons::fix_name ($name, $customer, $big_ver, $main, $ver, $ver_sp, $ver_id);
        $rest = fix_rest_dirs ($str, quotemeta $values[$#values], $values[0], $values[0]);
	$basic_url = "$url_sep$ver_fixed";
    } elsif ($dir_type eq "Docs_Customizations") {
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
        $basic_url = "$url_sep$ver_fixed";
    } elsif ($dir_type eq "Projects_Customizations") {
        $customer = $values[0];
	my $q = $values[1];
	$q =~ s/\s+$customer//;
	$customer = WikiCommons::get_correct_customer('pelephone') if defined $values[5] && $values[5] =~ m/pelephone/i;
        ($big_ver, $main, $ver, $ver_fixed, $ver_sp, $ver_id) = WikiCommons::check_vers ( $q, $values[2]);
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
        $basic_url = "$url_sep$ver_fixed";
    } elsif ($dir_type eq "Projects_Deployment_Customization") {
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
	    $basic_url = "$url_sep$ver_fixed";
	}
    } elsif ($dir_type eq "Projects_Common") {
        $rest = fix_rest_dirs ($str, quotemeta $values[$#values]);
#         $customer = "_Common for all customers_";
        $fixed_name = WikiCommons::fix_name ( $name, $customer );
    } elsif ($dir_type eq "Projects_Deployment_Common" || $dir_type eq "Docs_PaymentManager") {
	if ( scalar @values == 1 ) {
	    $rest = "";
	} else {
	    $rest = fix_rest_dirs ($str, quotemeta $values[$#values]);
	}
        $fixed_name = WikiCommons::fix_name ( $name, $customer );
    } else { die "Unknown document type: $dir_type.\n" }

    $basic_url = "$basic_url$url_sep$customer" if ($customer ne "");

    if ($dir_type eq "Docs_POS" && $name !~ m/^B[[:digit:]]{4,}\s+/) {
	$fixed_name =~ s/$ver//g;
	$fixed_name =~ s/^\s?pos[-_ \t]?//i;
	$fixed_name = "POS $fixed_name";
    } elsif ($dir_type eq "Docs_SIPServer" && $name !~ m/^B[[:digit:]]{4,}\s+/) {
	$fixed_name =~ s/$ver//g;
	$fixed_name =~ s/^\s?sip[-_ \t]?//i;
	$fixed_name = "SIP $fixed_name";
    } elsif ($dir_type eq "Docs_PaymentManager_Deployment" || $dir_type eq "Docs_PaymentManager") {
	$fixed_name = "PMG $fixed_name";
    }

    $fixed_name = fix_naming($fixed_name, $customer) if ($dir !~ /\/(.*? )?Release Notes\//i);
    $fixed_name = WikiCommons::normalize_text( $fixed_name );
    $fixed_name = WikiCommons::capitalize_string( $fixed_name, 'first' );
    $fixed_name =~ s/[\+\$]/ /g;
    $fixed_name =~ s/\s+/ /g;
    my $page_url = "$fixed_name$basic_url";
#     my $page_url_caps = WikiCommons::capitalize_string( $page_url, 'small' );
    die "No page for $doc_file.\n" if ($page_url eq "");

    ++$count_files;
    print "\tNumber of files: ".($count_files)."\t". (WikiCommons::get_time_diff) ."\n" if ($count_files%100 == 0);
    ### SC notes
    if ($name =~ m/^B[[:digit:]]{4,}\s+/){
	$page_url = "SVN_SC:$page_url";
	my @categories = ();
	$main = "$main$url_sep"."SVN_SC", push @categories, $main if $main ne "";
	$big_ver = "$big_ver$url_sep"."SVN_SC", push @categories, $big_ver if $big_ver ne "";
	## $ver, $main, $big_ver, $customer, $dir_type, $name
	generate_categories("", $main, $big_ver, "", "SVN SC Documents", "");
#  	push @categories, $customer;
	$pages_toimp_hash->{$page_url} = [WikiCommons::get_file_md5($doc_file), $rel_path, $svn_url, "link", \@categories];
	return 0;
    }

    ### Release Notes
    if ($dir =~ /\/(.*? )?Release Notes\//i) {
	return 1 if $ver_fixed lt "5.00" && ($dir_type ne "Docs_SIPServer" && $dir_type ne "Docs_PaymentManager_Deployment" && $dir_type ne "Docs_PaymentManager");
	$page_url = $fixed_name;
	my $nodot_ver = $ver;
	$nodot_ver =~ s/\.//g;
	$page_url =~ s/RN$nodot_ver\s*//;
	$page_url =~ s/(General|All)? Release Notes|PDF//gi;
	$page_url = "$page_url $ver_id" if $page_url !~ m/$ver_id/gi;
	$page_url = "$ver $page_url$url_sep$rest";
	$page_url =~ s/\s+/ /g;

# 	$main = $main.$url_sep."RN" if $main ne "";
# 	$big_ver = $big_ver.$url_sep."RN" if $big_ver ne "";
	if ($dir_type eq "Docs_PaymentManager_Deployment" || $dir_type eq "Docs_PaymentManager") {
	    $page_url = "PMG $page_url";
	    $main = "$main$url_sep"."PMG RN" if $main ne "";
	    $big_ver = "$big_ver$url_sep"."PMG RN" if $big_ver ne "";
	} elsif ($dir_type eq "Docs_SIPServer") {
	    $page_url = "SIP $page_url";
	    $main = "$main$url_sep"."SIP RN" if $main ne "";
	    $big_ver = "$big_ver$url_sep"."SIP RN" if $big_ver ne "";
	} elsif ($dir_type eq "Docs_POS") {
	    $page_url = "POS $page_url";
	    $main = "$main$url_sep"."POS RN" if $main ne "";
	    $big_ver = "$big_ver$url_sep"."POS RN" if $big_ver ne "";
	} else {
	    $page_url = "Mind $page_url";
	    $main = "$main$url_sep"."RN" if $main ne "";
	    $big_ver = "$big_ver$url_sep"."RN" if $big_ver ne "";
	}
	$page_url = "RN:$page_url";
	my @categories = ();
	push @categories, $main;
	push @categories, $big_ver;

	generate_categories("", $main, $big_ver, "", "SVN RN Documents", "");
	die "RN $page_url already exists:\n\t$rel_path\n".Dumper($pages_toimp_hash->{$page_url}) if defined $pages_toimp_hash->{$page_url};
	$pages_toimp_hash->{$page_url} = [WikiCommons::get_file_md5($doc_file), $rel_path, $svn_url, "link", \@categories];
	return 0;
    }

    $page_url = "SVN:$page_url";

    my $full_ver = "$ver $ver_id $ver_sp";
# print "2. $page_url\n";
    return 1 if $ver_fixed lt "5.00" && $ver_fixed ne "" && ($dir_type ne "Docs_SIPServer" && $dir_type ne "Docs_PaymentManager_Deployment"&& $dir_type ne "Docs_PaymentManager");
    if (defined $pages_ver->{$page_url}->{'ver'} ){
	if ($pages_ver->{$page_url}->{'ver'} gt "$full_ver"){
# print "skip $full_ver because we have $pages_ver->{$page_url}->{'ver'}\n";
	    return 0;
	} elsif ($pages_ver->{$page_url}->{'ver'} eq $full_ver) {
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
		$id = $pages_ver->{$page_url}->{'id'} + 1 if (defined $pages_ver->{$page_url}->{'id'});
# print "add extra $page_url because $full_ver is the same as $pages_ver->{$page_url}->{'ver'}\n";
		my $new_url = $page_url."$url_sep"."$id";
		push(@{$pages_ver->{$page_url}->{'urls'}}, $new_url);
		$page_url = $new_url;
		$pages_ver->{$page_url}->{'id'} = $id;
	    } else {
		return 0;
	    }
	} else {
	    ### this is less then
	    ### remove all previous urls
	    foreach my $url ( @{$pages_ver->{$page_url}->{'urls'}} ){
# print "remove previous url $url because $full_ver is greater then ".$pages_ver->{$page_url}->{'ver'}."\n";
		delete $pages_toimp_hash->{$url};
	    }
	    delete $pages_ver->{$page_url};
	}
    } else {
	### this is for new urls
# print "add new $page_url\n";
    }
#     return 0 if (exists $pages_ver->{$page_url}->{'ver'} && $pages_ver->{$page_url}->{'ver'} gt "$full_ver");
    my @categories = ();
    if ($fixed_name !~ m/^DB Changes (For|from)/i) {
	push @categories, $ver_fixed;
	push @categories, $main;
	push @categories, $big_ver;
	push @categories, $customer;
	my $correct_category;
	if ($dir_type eq "Docs_PaymentManager_Deployment" || $dir_type eq "Docs_PaymentManager") {
	    $correct_category = "Payment Manager";
	} elsif ($dir_type eq "Docs_SIPServer") {
	    $correct_category = "SIP Server";
	} else {
	    $correct_category = get_correct_category($fixed_name);
	}
	push @categories, $correct_category;
	generate_categories($ver_fixed, $main, $big_ver, $customer, $dir_type, $correct_category);
    }

    $pages_toimp_hash->{$page_url} = [WikiCommons::get_file_md5($doc_file), $rel_path, $svn_url, "link", \@categories];
    $pages_ver->{$page_url}->{'ver'} = "$full_ver";
# print "2. $page_url\n";

#     push(@{$pages_ver->{"$fixed_name$url->{'ver'}_sep$ver_without_sp"}}, $ver_sp);
}

sub get_correct_category {
    my $name = shift;
    ## prefer crystal reports before boe
    return "Crystal Reports" if $name =~ m/^Crystal[ -_]Reports([ -_](list|Parameters))?\b/i || $name =~ m/BOE XI/i;
#     return "BOE" if $name =~ m/BOE XI/i;
    return "CDR Drivers" if $name =~ m/^CDR Drivers/i;
#     return "DocRepository" if $name =~ m/^DocRepository\b/i;
    return "EDI" if $name =~ m/^EDI\b/i;
    return "ETL" if $name =~ m/\betl\b/i;
    return "Flexible Engine" if $name eq "Flexible Engine Manual";
    return "General Ledger" if $name =~ m/^General Ledger\b/i;
    return "IPE" if $name =~ m/^IPE\b/i;
    return "JBoss" if $name =~ m/\bJBoss\b/i;
    return "JBPM" if $name =~ m/\bJBPM\b/i;
    return "LEA" if $name =~ m/\bLEA\b/i;
#     return "OMS" if $name =~ m/^OMS\b/i;
    return "Payment Processor" if $name =~ m/^Payment Processor\b/i;
    return "POS" if $name =~ m/^POS\b/i;
    return "Processor" if $name =~ m/^Processor\b/i;
    return "Provisioning Clients" if $name =~ m/^Provisioning Client\b/i;
    return "SES" if $name =~ m/^SES\b/i;
    return "User Activity" if $name =~ m/^User Activity\b/i;
    return "Vertex" if $name =~ m/^Vertex\b/i;
    return "Web Services SDK" if $name =~ m/^Web Services SDK\b/i;
    return "Workflow" if $name =~ m/^Workflow\b/i;
    return "Database Documentation" if $name =~ m/(DB Documentation|Data Dictionary Tables)$/i;
    return "SIP Server" if $name =~ m/^SIP Server\b/i;
    return $name;
}

sub get_documents {
    my $self = shift;
    my @APPEND_DIRS=("Docs", "Docs_Customizations", "Docs_POS", "Docs_PaymentManager", "Docs_PaymentManager_Deployment", "Docs_SIPServer", "Projects", "Projects_Common", "Projects_Customizations", "Projects_Deployment", "Projects_Deployment_Common", "Projects_Deployment_Customization");
    my $url_sep = WikiCommons::get_urlsep;
    foreach my $append_dir (@APPEND_DIRS) {
	print "-Searching for files in $append_dir.\t". (WikiCommons::get_time_diff) ."\n";
	$count_files = 0;
	find ({
	    wanted => sub { add_document ($File::Find::name, $append_dir, "$self->{path_files}", "$url_sep") if -f && (/(\.doc|\.docx|\.rtf)$/i || /.*parameter.*Description.*\.xls$/i) },},
	    "$self->{path_files}/$append_dir"
	    ) if  (-d "$self->{path_files}/$append_dir");
# 	find ({
# 	    wanted => sub { add_document ($File::Find::name, $append_dir, "$self->{path_files}", "$url_sep") if -f && /.*parameter.*Description.*\.xls$/i },},
# 	    "$self->{path_files}/$append_dir"
# 	    ) if  (-d "$self->{path_files}/$append_dir");
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
# print "1a. $fixed_name\n";

    $fixed_name =~ s/^$customer|$customer$//gi;
    ## Specific updates
    $fixed_name =~ s/\s+ver\s*$//i;
    $fixed_name =~ s/\s+for\s*$//i;
    $fixed_name =~ s/jinny/Jinny/gi;
    $fixed_name =~ s/^User Guide\s*|\s*User Guide$//i;
    $fixed_name =~ s/^User Manual\s*|\s*User Manual$//i;
    $fixed_name =~ s/^\budr\b/UDR/i;
    $fixed_name =~ s/Wizards API/Wizard API/;
    $fixed_name =~ s/Provisionig/Provisioning/;
    $fixed_name =~ s/ASCLogFiles/ASC Log Files/;
    $fixed_name =~ s/FinanceLogFiles/Finance Log Files/;
    $fixed_name =~ s/RTSLogsFiles/RTS Logs Files/;
    $fixed_name =~ s/GenericCleanup/Generic Cleanup/;
    $fixed_name =~ s/^(Cyprus ?Telekom|Cyprus )([ _-]mind[ _-])?//i;
    $fixed_name =~ s/^Alon( )?Cellular([ _-]mind[ _-])?//i;
    $fixed_name =~ s/^Alon\s+([ _-]mind[ _-])?//i;

    $fixed_name = "IPE Monitor$1" if ($fixed_name =~ m/^IPEMonitor(.*)$/i);
    $fixed_name = "Radius Paramaters$1" if ($fixed_name =~ m/^RadiusParamaters(.*)$/i);
    $fixed_name = "Parameters Description" if ($fixed_name =~ m/Parameters? Descriptions?/i);
    $fixed_name = "$1 - Data Dictionary Tables" if ($fixed_name =~ m/^Data Dictionary Tables\s*-?\s*(.*)$/i && defined $1 && $1 !~ m/^\s*$/);
    return "Partner Management - DB Documentation" if ($fixed_name eq "DB Documentation Partner Mng");
    return "Resource Management - DB Documentation" if ($fixed_name eq "DB Documentation Resource Mng");
    return "Resource Management - DB Documentation" if ($fixed_name eq "6.00 DB Documentation Resource Mng");
    return "Partner Management - DB Documentation" if ($fixed_name eq "6.00 DB Documentation Partner Mng");
    return "System - DB Documentation" if ($fixed_name eq "DB Documentation Syetem");
    return "Digital TV" if ($fixed_name eq "Digital TV 5.31.001");
    return "Dynamic Soft" if ($fixed_name eq "Dynamic Soft 5.30.017");

    $fixed_name =~ s/^Resource Mng/Resource Management/;
    $fixed_name =~ s/^Partner Mng/Partner Management/;
    $fixed_name = "$2 - DB Documentation" if ($fixed_name =~ m/^(6.00)?\s*DB Documentation\s*-?\s*([a-z0-9]{1,})$/i && defined $2 && $2 !~ m/^\s*$/);

    #Billing Crystal Reports invoice jbpm mediation rating reports Resource Management system
#     return "POS - $2" if ($fixed_name =~ m/^POS\s+(-\s+)?(.*)$/i && defined $2 && $2 !~ m/^\s*$/);
    return "General Configuration Parameters" if ($fixed_name eq "Configuration Parameters" || $fixed_name eq "General Config Parameters" || $fixed_name eq "ConfigurationParameters");
    return "Modules Deployment" if ($fixed_name =~ m/Modules Deployment (6.01|6.50|6.60|7.00)/i);
    return "Administrator" if ($fixed_name eq "Administrator User Manual 5.3");
    return "Auxiliary Module Applications" if ($fixed_name eq "Auxiliary Applications 5.3");
    return "Billing" if ($fixed_name eq "BillingUserManual5.0-rev12");
    return "Billing" if ($fixed_name eq "BillingUserManual5.01-rev12");
    return "Billing" if ($fixed_name eq "BillingUserManual5.01-rev13Kenan");
    return "Business Processes Deployment" if ($fixed_name eq "Business Processes Deployment 601");
    return "Cashier" if ($fixed_name eq "Cashier5.21.rev10");
    return "CDR Export" if ($fixed_name eq "CDR Export User Guide 5.0");
    return "CDR Drivers - 3G" if ($fixed_name eq " 3G CDR Drivers");
    return "Cisco User Manual" if ($fixed_name eq "Cisco 5.31.001");
    return "Cisco SSG Configuration" if ($fixed_name eq "Cisco SSG Configuration UserManuall5.0");
    return "Collector" if ($fixed_name eq "Collector 5.3");
    return "Correlation" if ($fixed_name eq "Correlation rev10");
    return "Dashboard" if ($fixed_name eq "Dashboard5.30");
    return "DB Documentation" if ($fixed_name eq "5.31 DB Documentation");
    return "EDI For Payment" if ($fixed_name eq "EDI for Payment 5.21");
    return "EDI For Payment" if ($fixed_name eq "EDI for Payments");
    return "ETL Staging Area - DB Documentation" if ($fixed_name eq "ETLStagingArea - DB Documentation");
    return "ETL Installation Guide" if ($fixed_name eq "ETL INSTALLATION GUIDE");
    return "Guard" if ($fixed_name eq "Guard rev13");
    return "Install Cisco Rev10" if ($fixed_name eq "installCisco5.0InstallB-rev10");
    return "Install Cisco Rev11" if ($fixed_name eq "installCisco5.0InstallA-rev11");
    return "IGuard80" if ($fixed_name eq "iGuard80-rev10");
    return "Invoice Generation" if ($fixed_name eq "Invoice generation 5.30");
    return "Invoice Generation" if ($fixed_name eq "Invoice generation 5.31");
    return "Itraf80" if ($fixed_name eq "itraf80-rev10");
    return "Interception Monitor" if ($fixed_name eq "Interception 5.2Monitor rev11");

    return "Provisioning Client - LDAP SunOne" if ($fixed_name eq "LDAPSunOne Provisioning Client 5.31.001");
    return "Provisioning Client - Ericsson" if ($fixed_name eq "Ericsson Provisioning Client 5.31.001");
    return "Provisioning Client - GEMPlus" if ($fixed_name eq "GEMPlus Provisioning Client 5.31.001");
    return "Provisioning Client - HLR" if ($fixed_name eq "HLR Provisioning Client 5.31.001");
    return "Provisioning Client - IP Services" if ($fixed_name eq "IP Services Provisioning Client");
    return "Provisioning Client - IPGallery" if ($fixed_name eq "IPGallery Provisioning Client 5.31.001");
    return "Provisioning Client - Cisco" if ($fixed_name eq "Cisco Provisioning Client 5.31.001");
    return "Provisioning Client - Digital TV" if ($fixed_name eq "Digital TV Provisioning Client 5.31.001");
    return "Provisioning Client - Netspeak" if ($fixed_name eq "Netspeak Provisioning Client 5.31.001");
    return "Provisioning Client - Nortel" if ($fixed_name eq "Nortel Provisioning Client 5.31.001");
    return "Provisioning Client - Terayon" if ($fixed_name eq "Terayon Provisioning Client 5.31.001");
    return "Provisioning Client - Veraz" if ($fixed_name eq "Veraz Provisioning Client 5.31.001");
    return "Provisioning Client - AIW" if ($fixed_name eq "AIW Provisioning Client");
    return "Provisioning Client - ActionStreamer 3G" if ($fixed_name eq "ActionStreamer 3G Provisioning Client");
    return "Provisioning Client - ActionStreamer" if ($fixed_name eq "ActionStreamer Provisioning Client");
    return "Provisioning Client - ActionStreamer Wireline" if ($fixed_name eq "ActionStreamer Wireline Provisioning Client");
    return "Provisioning Client - BTS" if ($fixed_name eq "BTS Provisioning Client");

    return "Provisioning Clients" if ($fixed_name eq "Provisioning Client");

    return "Manager" if ($fixed_name eq "Manager User Manual 5.21-rev.11");
    return "Manager" if ($fixed_name eq "Manager User Manual 5.3");
    return "Multisite Failover Manager" if ($fixed_name eq "MultisiteFailoverManager5.01");
    return "CSR - Manual De Utilizare MINDBill" if ($fixed_name eq "Manual de utilizare MINDBill CSR");
    return "Reports - Manual De Utilizare" if ($fixed_name eq "Manual de Utilizare Rapoarte MINDBill");

    return "Neils Revision" if ($fixed_name eq "50001neilsrevision");
    return "New Features Summary" if ($fixed_name eq "New Features Summary MIND-IPhonEX 5.30.010");
    return "New Features Summary" if ($fixed_name eq "New Features Summary MIND-IPhonEX 5.30.013");
    return "Open View Operation" if ($fixed_name eq "OpenViewOperations5.30");

    return "Parameters Description" if ($fixed_name eq "Parameter Description Ver 601");
    return "Parameters Description" if ($fixed_name eq "Parameter Description 6.00");

    return "Pre-Release" if ($fixed_name eq "5.0Pre-Release");
    return "Process Configuration Documentation PackageChange" if ($fixed_name eq "6.01 Process Configuration Documentation PackageChange");
    return "Product Description" if ($fixed_name eq "Product Description 5.21-rev.12");
    return "Product Description" if ($fixed_name eq "Product Description5.3");
    return "Product Description" if ($fixed_name eq "ProductDescription 5.0");

    return "Provisioning Solution" if ($fixed_name eq "Provisioning Solution UserManual5.0");
    return "Provisioning API" if ($fixed_name eq "Provisioning API 5.20 v1.1");
    return "Rule Rating Editor" if ($fixed_name eq "Rule-Rating-Editor-rev10");

    return "Crystal Reports - Interconnect" if ($fixed_name eq "Manual de utilizare MINDBill 6.01 Rapoarte Crystal - Interconnect");
    return "Release Notes V3" if ($fixed_name eq "5.2x Release Notes V3");
    return "Reports User Guide" if ($fixed_name eq "Reports User Guide For");
    return "System Overview" if ($fixed_name eq "5.00.015 System Overview");
    return "Task Scheduler" if ($fixed_name eq "Task Scheduler User Guide 5.3");
    return "UDR Distribution" if ($fixed_name eq "UDRDistributionUserGuide5.01-rev10");
    return "User Activity" if ($fixed_name eq "UserActivity5.30");
    return "Administrator" if ($fixed_name eq "AdminUserManual5.02-rev15");
    return "Billing Vodafone" if ($fixed_name eq "BillingUserManual5.02-rev14Vodafone");
    return "Dialup CDR And Invoice Generation" if ($fixed_name eq "Dialup CDR and Invoice Generation 521");
    return "Vendors Support" if ($fixed_name eq "VendorsSupport");
    return "User Activity" if ($fixed_name eq "UserActivity5 30");
    return "Checkpoint LEA Configuration" if ($fixed_name eq "Checkpoint LEAconfiguration");
    return "High Availability" if ($fixed_name eq "HighAvailability");
    return "LEA Client Installation" if ($fixed_name eq "LEAClientInstallation");
    return "Load Balancing" if ($fixed_name eq "LoadBalancing");
    return "Parsing Rules" if ($fixed_name eq "ParsingRules");

    return "Plugin Point In Recalc" if ($fixed_name eq "PluginPointInRecalc");
    return "Processor Logs Files" if ($fixed_name eq "ProcessorLogsFiles");
    return "Proxy Manager Server" if ($fixed_name eq "ProxyManagerServer");
    return "Statistics Description" if ($fixed_name eq "StatisticsDescription");
    return "DB Import" if ($fixed_name eq "DBImport");
    return "Display CDR Field Instructions" if ($fixed_name eq "DisplayCDRFieldInstructions");
    return "Fix Invoice XML Deployment" if ($fixed_name eq "FixInvoiceXML deployment");
    return "Install Oracle 10g Veracity" if ($fixed_name eq "installOracle10g veracity");
    return "Business Processes Monitoring Deployment" if ($fixed_name eq "BP Monitoring Deployment");
    return "System Audit" if ($fixed_name eq "SA");
    return "Sebanci Telecom EPay Credit Adapter API" if ($fixed_name eq "Sabanci Telecom EPay Credit Adapter API");
    return "SES VF Greece QS Product Description" if ($fixed_name eq "SES VF Greece QS ProductDescription");
    return "SNMP Client Paramaters Descriptions" if ($fixed_name eq "SNMPClient Paramaters descriptions");

    return "VOIPCDR Upgrade Procedure" if ($fixed_name eq "VOIPCDR upgrade procedure 601");
    return "WebBill" if ($fixed_name eq "5.3 WebBill");
    return "WebBill" if ($fixed_name eq "WebBill 5.2");

    return "WebBill" if ($fixed_name eq "WebBillUserManual5.0-rev10");
    return "WebBill" if ($fixed_name eq "WebBillUserManual5.01-rev11");
    return "WebClient" if ($fixed_name eq "WebClient5.0-rev11");
    return "WebClient" if ($fixed_name eq "WebClient5.01-rev11");
    return "WebClient" if ($fixed_name eq "WebClient5.30");

    ### afripa documents
    return "WebClient" if ($fixed_name eq "GN WebClient Manuel d'Utilisation");
    return "Guard" if ($fixed_name eq "GN Guard Manuel d'Utilisation");
    return "Administrator" if ($fixed_name eq "GN Administrator Manuel d'Utilisation");
    return "Cashier" if ($fixed_name eq "GN Cashier Manuel d'Utilisation");
    return "CallShop" if ($fixed_name eq "CallShop Manuel d'Utilisation");
    return "CallShop" if ($fixed_name eq "5.31.005 CallShop Manuel d'Utilisation");
    return "Manager" if ($fixed_name eq "GN Manager Manuel d'Utilisation");
    return "Reports" if ($fixed_name eq "GN Reports Guide d'Utilisation");
    return "Resource Management" if ($fixed_name eq "GN Resource Management Manuel d'Utilisation");
    return "User Activity Tracker" if ($fixed_name eq "GN User Activity Tracker Manuel d'Utilisation");
    return "Product Description" if ($fixed_name eq "GN Description du Produit");
    return "Near Real Time Roaming Data Exchange Manager" if ($fixed_name eq '4.10.103 Near Real Time Roaming Data Exchange Manager (NRTRDEM)');
    return "Global Roaming Manager" if ($fixed_name eq '4.10.103 Global Roaming Manager (GRM)');

    $fixed_name =~ s/^\s*|\s*$//g;
# print "1c. $fixed_name\n";
    return $fixed_name;
}

return 1;

