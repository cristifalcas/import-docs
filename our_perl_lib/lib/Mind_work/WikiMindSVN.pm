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
    my ($ver, $main, $big_ver, $customer, $dir_type) = @_;
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

    $general_categories_hash->{$big_ver}->{'Mind SVN autoimport'} = 1 if $big_ver ne "";
    $general_categories_hash->{$dir_type}->{'Mind SVN autoimport'} = 1 if $dir_type ne "";
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
    if ($str =~ m/.*\/([^\/]+)(branded|users? manuals?)\//i) {
# 	print "$1\t\t$2\n";
	$customer = "$1";
    }


    switch ("$dir_type") {
    case "Projects" {
        ($big_ver, $main, $ver, $ver_fixed, $ver_sp, $ver_id) = WikiCommons::check_vers ( $values[0], $values[1]);
        $fixed_name = WikiCommons::fix_name ($name, $customer, $big_ver, $main, $ver, $ver_sp, $ver_id);
        $rest = fix_rest_dirs ($str, quotemeta $values[$#values], $values[0], $values[1]);
	if ($customer eq "") {
	    $basic_url = "$fixed_name$url_sep$ver_fixed";
	} else {
	    $basic_url = "$fixed_name$url_sep$ver_fixed$url_sep$customer";
	}
    }
    case "Docs" {
        ($big_ver, $main, $ver, $ver_fixed, $ver_sp, $ver_id) = WikiCommons::check_vers ( $values[0], $values[1]);
# print "xxx:$values[0], $values[1]\n";
        $fixed_name = WikiCommons::fix_name ($name, $customer, $big_ver, $main, $ver, $ver_sp, $ver_id);
        $rest = fix_rest_dirs ($str, quotemeta $values[$#values], $values[0], $values[1]);
	if ($customer eq "") {
	    $basic_url = "$fixed_name$url_sep$ver_fixed";
	} else {
	    $basic_url = "$fixed_name$url_sep$ver_fixed$url_sep$customer";
	}
    }
    case "Projects_Deployment" {
        ($big_ver, $main, $ver, $ver_fixed, $ver_sp, $ver_id) = WikiCommons::check_vers ( $values[0], $values[0]);
        $fixed_name = WikiCommons::fix_name ($name, $customer, $big_ver, $main, $ver, $ver_sp, $ver_id);
        $rest = fix_rest_dirs ($str, quotemeta $values[$#values], $values[0], $values[0]);
	if ($customer eq "") {
	    $basic_url = "$fixed_name$url_sep$ver_fixed";
	} else {
	    $basic_url = "$fixed_name$url_sep$ver_fixed$url_sep$customer";
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
        $basic_url = "$fixed_name$url_sep$ver_fixed$url_sep$customer";
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
        $basic_url = "$fixed_name$url_sep$ver_fixed$url_sep$customer";
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
	    $basic_url = "$fixed_name$url_sep$ver_fixed$url_sep$customer";
	} else {
	    $basic_url = "$fixed_name$url_sep$customer";
	}
    }
    case "Projects_Common" {
        $rest = fix_rest_dirs ($str, quotemeta $values[$#values]);
        $customer = "_Common for all customers_";
        $fixed_name = WikiCommons::fix_name ($name, $customer);
        $basic_url = "$fixed_name";
    }
    case "Projects_Deployment_Common" {
	if ( scalar @values == 1 ) {
	    $rest = "";
	} else {
	    $rest = fix_rest_dirs ($str, quotemeta $values[$#values]);
	}
        $customer = "_Common for all customers_";
        $fixed_name = WikiCommons::fix_name ( $name, $customer );
        $basic_url = "$fixed_name";
    }
    case "SC" {
	$basic_url = "$name";
	return 1;
    }
    else { die "Unknown document type: $dir_type.\n" }
    }

    my $page_url = "$basic_url";
    chomp $page_url;
    $page_url = WikiCommons::normalize_text( $page_url );
    $page_url = WikiCommons::capitalize_string( $page_url, 'first' );
    my $page_url_caps = WikiCommons::capitalize_string( $page_url, 'small' );
    die "No page for $doc_file.\n" if ($page_url eq "" );

    ++$count_files;
    print "\tNumber of files: ".($count_files)."\t". (WikiCommons::get_time_diff) ."\n" if ($count_files%100 == 0);

    ### Release Notes
    if ($dir =~ /\/(.*? )?Release Notes\//i) {
	return 1 if $ver_fixed lt "5.00";
	$page_url =~ s/(($url_sep)($customer )?Release Notes)|(($url_sep)All Release Notes)//g;

	my $q = $basic_url;
	$q =~ s/$url_sep$ver_fixed\s*//;
	$q =~ s/$url_sep$ver\s*//;
	my $nodot_ver = $ver;
	$nodot_ver =~ s/\.//g;
	$q =~ s/RN$nodot_ver\s*//;
	$q =~ s/\s*$ver_id\s*//;
	$q =~ s/\s*$ver_sp\s*//;
	$q =~ s/$url_sep(Release Notes|PDF|All Release Notes)//gi;
	$q = "RN:$ver $ver_id $ver_sp $q$url_sep$rest";
# 	$page_url = "RN:$page_url";
	$page_url=$q;
	$page_url =~ s/\s+/ /g;

	$ver_fixed = $ver_fixed.$url_sep."RN" if $ver_fixed ne "";
	$main = $main.$url_sep."RN" if $main ne "";
	$big_ver = $big_ver.$url_sep."RN" if $big_ver ne "";
	$customer = $customer.$url_sep."RN" if $customer ne "";
	my @categories = ();
	push @categories, $main;
	push @categories, $big_ver;
	generate_categories("", $main, $big_ver, "", $dir_type);
	die "RN $page_url already exists:\n\t$rel_path\n".Dumper($pages_toimp_hash->{$page_url}) if exists $pages_toimp_hash->{$page_url};
	$pages_toimp_hash->{$page_url} = [WikiCommons::get_file_md5($doc_file), $rel_path, $svn_url, "link", \@categories];
	return 0;
    }

    my $full_ver = "$ver $ver_id $ver_sp";
    my @categories = ();
    push @categories, $ver_fixed;
    push @categories, $main;
    push @categories, $big_ver;
    push @categories, $customer;

    return 1 if $ver_fixed lt "5.00" && $ver_fixed ne "";
    return 0 if (exists $pages_ver->{$page_url_caps}->{'ver'} && $pages_ver->{$page_url_caps}->{'ver'} gt "$full_ver");

    generate_categories($ver_fixed, $main, $big_ver, $customer, $dir_type);

    if (exists $pages_ver->{$page_url_caps}->{'ver'} && "$pages_ver->{$page_url_caps}->{'ver'}" eq "$full_ver") {
	my $new = WikiCommons::svn_info("$path_file/$rel_path", "", "");
	if (defined $new) {$new =~ s/^.*?\nChecksum: (.*?)\n.*?$/$1/gs; chomp $new;}
	my $old = WikiCommons::svn_info("$path_file/$pages_toimp_hash->{$page_url}[1]", "", "");
	if (defined $old) {$old =~ s/^.*?\nChecksum: (.*?)\n.*?$/$1/gs; chomp $old;}
	if (! defined $new || ! defined $old || $new ne $old) {
	    my $id = 1;
	    if (exists $pages_ver->{$page_url_caps}->{'id'}) {
		$id = $pages_ver->{$page_url_caps}->{'id'} + 1;
	    }
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

return 1;

