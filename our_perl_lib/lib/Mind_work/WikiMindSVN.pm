package WikiMindSVN;

use warnings;
use strict;

use Switch;
use File::Find;
use Cwd 'abs_path';
use File::Basename;
use Data::Dumper;

our $pages_toimp_hash = {};
our $count_files;
our $url_sep;
my $pages_ver = {};

sub new {
    my $class = shift;
    my $self = { path_files => shift , url_sep => shift};
    $url_sep = "$self->{url_sep}";
    bless($self, $class);
    return $self;
}

sub fix_rest_dirs {
    my ($rest, $filename, $main, $ver, $ver_fixed) = @_;
    $rest =~ s/\/$filename$//;
    if (defined $main || defined $ver || defined $ver_fixed) {
	$rest =~ s/(^v?$main(\/|$))|((\/|^)v?$main$)//gi;
	$rest =~ s/(^v?$ver(\/|$))|((\/|^)v?$ver$)//gi;
	$rest =~ s/(^v?$ver_fixed(\/|$))|((\/|^)v?$ver_fixed$)//gi;
    }
    $rest =~ s/\/{1,}/\//g;
    $rest =~ s/^Documents\///;
    $rest =~ s/\//$url_sep/g;

    return $rest;
}

sub add_document {
    my ($doc_file,$dir_type, $path_file, $url_sep) = @_;

    $doc_file = abs_path($doc_file);
    my $doc_filesize = -s "$doc_file";
    return if ($doc_filesize == 0);
    my $basic_url = ""; my $rest = ""; my $customer = "";
    my $main = ""; my $ver = ""; my $ver_fixed = ""; my $big_ver = ""; my $ver_sp = ""; my $ver_without_sp = "";
    my $rel_path = ""; my $svn_url = ""; my $fixed_name = "";
    my $str = $doc_file;
    #  remove svn_dir
    $str =~ s/^$path_file\/$dir_type\///;
    $rel_path = "$dir_type/$str";
    $svn_url = find_svn_helper ($doc_file, $path_file);
    my ($name,$dir,$suffix) = fileparse($str, qr/\.[^.]*/);

    my @values = split('\/', $str);

    die "$dir_type $path_file values ".Dumper(@values) if scalar @values <=2 && ($dir_type ne 'Projects_Deployment' && $dir_type ne 'Projects_Deployment_Common' && $dir_type ne 'Projects_Deployment_Customization');

    $dir_type = "SC" if ($name =~ m/^B[[:digit:]]{4,}\s+/);

    switch ("$dir_type") {
    case "Projects" {
        ($main, $ver, $ver_fixed, $big_ver, $ver_sp, $ver_without_sp) = WikiCommons::check_vers ( $values[0], $values[1]);
        $fixed_name = WikiCommons::fix_name ($name, $customer, $main, $ver);
        $rest = fix_rest_dirs ($str, quotemeta $values[$#values], $main, $ver, $ver_fixed);
        $basic_url = "$fixed_name$url_sep$ver_without_sp";
    }
    case "Docs" {
        ($main, $ver, $ver_fixed, $big_ver, $ver_sp, $ver_without_sp) = WikiCommons::check_vers ( $values[0], $values[1]);
        $fixed_name = WikiCommons::fix_name ($name, $customer, $main, $ver);
        $rest = fix_rest_dirs ($str, quotemeta $values[$#values], $main, $ver, $ver_fixed);
        $basic_url = "$fixed_name$url_sep$ver_without_sp";
    }
    case "Projects_Deployment" {
	my $tmp = "";
	if ( scalar @values == 2 ) {
	    $tmp = $values[0];
	} else {
	    $tmp = $values[1];
	}
        ($main, $ver, $ver_fixed, $big_ver, $ver_sp, $ver_without_sp) = WikiCommons::check_vers ( $values[0], $tmp);
        $fixed_name = WikiCommons::fix_name ($name, $customer, $main, $ver);
        $rest = fix_rest_dirs ($str, quotemeta $values[$#values], $main, $ver, $ver_fixed);
        $basic_url = "$fixed_name$url_sep$ver_without_sp";
    }
    case "Docs_Customizations" {
        ($main, $ver, $ver_fixed, $big_ver, $ver_sp, $ver_without_sp) = WikiCommons::check_vers ( $values[1], $values[2]);
        $customer = $values[0];        $str =~ s/^$customer\///;
        $fixed_name = WikiCommons::fix_name ( $name, $customer, $main, $ver);
        $rest = fix_rest_dirs ($str, quotemeta $values[$#values], $main, $ver, $ver_fixed);
        $basic_url = "$fixed_name$url_sep$ver_without_sp$url_sep$customer";
    }
    case "Projects_Customizations" {
        ($main, $ver, $ver_fixed, $big_ver, $ver_sp, $ver_without_sp) = WikiCommons::check_vers ( $values[1], $values[2]);
        $customer = $values[0];        $str =~ s/^$customer\///;
        $fixed_name = WikiCommons::fix_name ($name, $customer, $main, $ver);
        $rest = fix_rest_dirs ($str, quotemeta $values[$#values], $main, $ver, $ver_fixed);
        $basic_url = "$fixed_name$url_sep$ver_without_sp$url_sep$customer";
    }
    case "Projects_Deployment_Customization" {
        $customer = $values[0];        $str =~ s/^$customer\///;
	if ( scalar @values == 2 ) {
	    $rest = "";
	} else {
	    $ver = $values[1], $main = $ver if $values[1] =~ m/^v?[[:digit:]]{1,}(\.[[:digit:]]{1,}){0,}( )?([a-z]*?[[:digit:]]{1,})$/i;
	    $ver = $values[$#values-1], $main = $ver if $values[$#values-1] =~ m/^v?[[:digit:]]{1,}(\.[[:digit:]]{1,}){0,}( )?([a-z]*?[[:digit:]]{0,})$/i;
	    if ($ver ne '' ){
		($main, $ver, $ver_fixed, $big_ver, $ver_sp, $ver_without_sp) = WikiCommons::check_vers ( $main, $ver);
		$rest = fix_rest_dirs ($str, quotemeta $values[$#values], $main, $ver, $ver_fixed);
	    } else {
		$rest = fix_rest_dirs ($str, quotemeta $values[$#values]);
	    }
	}
        $fixed_name = WikiCommons::fix_name ( $name, $customer, $main, $ver);
	if ($ver ne '' ){
	    $basic_url = "$fixed_name$url_sep$ver_without_sp$url_sep$customer";
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
    case "SCDocs" {
        $rest = fix_rest_dirs ($str, quotemeta $values[$#values]);
        $customer = "$dir_type$url_sep$rest";
        $fixed_name = WikiCommons::fix_name ($name, $customer);
        $basic_url = "$fixed_name";
    }
    case "SC" {
	$basic_url = "$name";
	return 1;
    }
    else { print "Unknown document type: $dir_type.\n" }
    }

    my $simple_url = "";
    if ($rest ne "") {
	$simple_url = "$basic_url$url_sep$rest";
    } else {
	$simple_url = "$basic_url";
    }
    my $page_url = $simple_url;

    ### Release Notes
    if ($dir =~ /\/(.*? )?Release Notes\//i && $dir_type ne "SC") {
	$ver_without_sp = $ver_without_sp.$url_sep."RN" if $ver_without_sp ne "";
	$main = $main.$url_sep."RN" if $main ne "";
	$big_ver = $big_ver.$url_sep."RN" if $big_ver ne "";
	$customer = $customer.$url_sep."RN" if $customer ne "";
	$page_url =~ s/(($url_sep)($customer )?Release Notes)|(($url_sep)All Release Notes)//g;
	$page_url = "Release Notes".$url_sep.$page_url;
	$basic_url = "$page_url$url_sep$customer";
	$rest =~ s/(($url_sep)($customer )?Release Notes)|(($customer )?Release Notes$url_sep)|(^($customer )?Release Notes$)|(($url_sep)All Release Notes)//g;
    }

    die "Same SP already exists.\n" if exists $pages_ver->{$page_url} && "$pages_ver->{$page_url}" eq "$ver_sp";

    my @categories = ();
    push @categories, $ver_without_sp;
    push @categories, $main;
    push @categories, $big_ver;
    push @categories, $customer;
    WikiCommons::generate_categories($ver_without_sp, $main, $big_ver, $customer, $dir_type);

    ++$count_files;
    print "\tNumber of files: ".($count_files)."\t". (WikiCommons::get_time_diff) ."\n" if ($count_files%100 == 0);

    chomp $page_url;
    die "No page for $doc_file.\n" if ($page_url eq "" );

    if (exists $pages_ver->{$page_url} && $pages_ver->{$page_url} gt "$ver_sp") {
# 	print "Ignore new page $page_url from\n\t\t$rel_path\n\tbecause new SP $ver_sp is smaller then $pages_ver->{$page_url}.\n"
    } else {
# 	print "Replace old url $page_url from\n\t\t$pages_toimp_hash->{$page_url}[1]\n\twith the doc from\n\t\t$rel_path\n\tbecause new SP $ver_sp is bigger then $pages_ver->{$page_url}.\n" if (exists $pages_toimp_hash->{$page_url});
	$pages_toimp_hash->{$page_url} = [WikiCommons::get_file_md5($doc_file), $rel_path, $svn_url, "link", \@categories];
# $pages_toimp_hash->{$page_url} = ["$page_url", $rel_path, $svn_url, "link", \@categories];
	$pages_ver->{$page_url} = "$ver_sp";
    }
#     push(@{$pages_ver->{"$fixed_name$url_sep$ver_without_sp"}}, $ver_sp);
}

sub get_documents {
    my $self = shift;
    my @APPEND_DIRS=("Docs", "Docs_Customizations", "Projects", "Projects_Common", "Projects_Customizations", "Projects_Deployment", "Projects_Deployment_Common", "Projects_Deployment_Customization", "SCDocs");
    foreach my $append_dir (@APPEND_DIRS) {
	print "-Searching for files in $append_dir.\t". (WikiCommons::get_time_diff) ."\n";
	$count_files = 0;
	find sub { add_document ($File::Find::name, $append_dir, "$self->{path_files}", "$self->{url_sep}") if -f && (/(\.doc|\.docx|\.rtf)$/i) }, "$self->{path_files}/$append_dir" if  (-d "$self->{path_files}/$append_dir");
	find sub { add_document ($File::Find::name, $append_dir, "$self->{path_files}", "$self->{url_sep}") if -f && /.*parameter.*Description.*\.xls$/i }, "$self->{path_files}/$append_dir" if  (-d "$self->{path_files}/$append_dir");
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

