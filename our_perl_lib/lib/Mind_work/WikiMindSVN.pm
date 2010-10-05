package WikiMindSVN;

use warnings;
use strict;

use Switch;
use File::Find;
use Cwd 'abs_path';
use File::Basename;

our $pages_toimp_hash = {};
our $count_files;
our $url_sep;

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
	$rest =~ s/^v?($main\/|$main$)//gi;
	$rest =~ s/^v?($ver\/|$main$)//gi;
	$rest =~ s/^v?($ver_fixed\/|$main$)//gi;
    }
    $rest =~ s/\/{1,}/\//g;
    $rest =~ s/^Documents\///;
    $rest =~ s/\//$url_sep/g;
    return $rest;
}

sub add_document {
#     my $self = shift;
    my $doc_file = abs_path(shift);
    my $dir_type = shift;
    my $path_file = shift;
    my $url_sep = shift;
    my $doc_filesize = -s "$doc_file";
    return if ($doc_filesize == 0);
    my $basic_url = ""; my $rest = ""; my $customer = "";
    my $main = ""; my $ver = ""; my $ver_fixed = ""; my $big_ver = "";
    my $rel_path = ""; my $svn_url = "";
    my $str = $doc_file;
    #  remove svn_dir
    $str =~ s/^$path_file\/$dir_type\///;
    $rel_path = "$dir_type/$str";
    $svn_url = find_svn_helper ($doc_file, $path_file);
    my ($name,$dir,$suffix) = fileparse($str, qr/\.[^.]*/);
#     stop_for_users;

    my @values = split('\/', $str);

    return 1 if ($name =~ m/^B[[:digit:]]{4,}\s+/);
    ## when importing B12345: the url is B12345 - name and we will make a redirect from B12345

    switch ("$dir_type") {
    case "Projects" {
        ($main, $ver, $ver_fixed, $big_ver) = WikiCommons::check_vers ($values[0], $values[1]);
        my $fixed_name = WikiCommons::fix_name ($name, $customer, $main, $ver);
        $rest = fix_rest_dirs ($str, quotemeta $values[$#values], $main, $ver, $ver_fixed);
        $basic_url = "$fixed_name$url_sep$main$url_sep$ver_fixed";
    }
    case "Docs" {
        ($main, $ver, $ver_fixed, $big_ver) = WikiCommons::check_vers ($values[0], $values[1]);
        my $fixed_name = WikiCommons::fix_name ($name, $customer, $main, $ver);
        $rest = fix_rest_dirs ($str, quotemeta $values[$#values], $main, $ver, $ver_fixed);
        $basic_url = "$fixed_name$url_sep$main$url_sep$ver_fixed";
    }
    case "Projects_Deployment" {
        ($main, $ver, $ver_fixed, $big_ver) = WikiCommons::check_vers ($values[0], $values[1]);
        my $fixed_name = WikiCommons::fix_name ($name, $customer, $main, $ver);
        $rest = fix_rest_dirs ($str, quotemeta $values[$#values], $main, $ver, $ver_fixed);
        $basic_url = "$fixed_name$url_sep$main$url_sep$ver_fixed";
    }
    case "Docs_Customizations" {
        ($main, $ver, $ver_fixed, $big_ver) = WikiCommons::check_vers ($values[1], $values[2]);
        $customer = $values[0];        $str =~ s/^$customer\///;
        my $fixed_name = WikiCommons::fix_name ($name, $customer, $main, $ver);
        $rest = fix_rest_dirs ($str, quotemeta $values[$#values], $main, $ver, $ver_fixed);
        $basic_url = "$fixed_name$url_sep$main$url_sep$ver_fixed$url_sep$customer";
    }
    case "Projects_Customizations" {
        ($main, $ver, $ver_fixed, $big_ver) = WikiCommons::check_vers ($values[1], $values[2]);
        $customer = $values[0];        $str =~ s/^$customer\///;
        my $fixed_name = WikiCommons::fix_name ($name, $customer, $main, $ver);
        $rest = fix_rest_dirs ($str, quotemeta $values[$#values], $main, $ver, $ver_fixed);
        $basic_url = "$fixed_name$url_sep$main$url_sep$ver_fixed$url_sep$customer";
    }
    case "Projects_Deployment_Customization" {
        $customer = $values[0];        $str =~ s/^$customer\///;
        my $fixed_name = WikiCommons::fix_name ($name, $customer);
        $rest = fix_rest_dirs ($str, quotemeta $values[$#values]);
        $basic_url = "$fixed_name$url_sep$customer";
    }
    case "Projects_Common" {
        $rest = fix_rest_dirs ($str, quotemeta $values[$#values]);
        $customer = "_Common for all customers_";
        my $fixed_name = WikiCommons::fix_name ($name, $customer);
        $basic_url = "$fixed_name";
    }
    case "Projects_Deployment_Common" {
        $rest = fix_rest_dirs ($str, quotemeta $values[$#values]);
        $customer = "_Common for all customers_";
        my $fixed_name = WikiCommons::fix_name ($name, $customer);
        $basic_url = "$fixed_name";
    }
    case "SCDocs" {
        $rest = fix_rest_dirs ($str, quotemeta $values[$#values]);
        $customer = "$dir_type$url_sep$rest";
        my $fixed_name = WikiCommons::fix_name ($name, $customer);
        $basic_url = "$fixed_name";
    }
    else { print "Unknown document type: $dir_type.\n" }
    }

    my $simple_url = "";
    if ($rest ne "") {
	$simple_url = "$basic_url$url_sep$rest";
    } else {
	$simple_url = "$basic_url";
    }
    my $full_url = "$simple_url$url_sep$dir_type";
    my $page_url = $simple_url;
    $customer =~ s/(\w+)/\u\L$1/g;

    ### Release Notes
    if ($dir =~ /\/(.*? )?Release Notes\//i) {
	$ver_fixed = $ver_fixed.$url_sep."RN" if $ver_fixed ne "";
	$main = $main.$url_sep."RN" if $main ne "";
	$big_ver = $big_ver.$url_sep."RN" if $big_ver ne "";
	$customer = $customer.$url_sep."RN" if $customer ne "";
	$page_url =~ s/(($url_sep)($customer )?Release Notes)|(($url_sep)All Release Notes)//g;
	$page_url = "Release Notes".$url_sep.$page_url;
	$rest =~ s/(($url_sep)($customer )?Release Notes)|(($customer )?Release Notes$url_sep)|(^($customer )?Release Notes$)|(($url_sep)All Release Notes)//g;
    }

    WikiCommons::generate_categories($ver_fixed, $main, $big_ver, $customer, $dir_type);
    die "We already have url $page_url from $doc_file with \n". Dumper($pages_toimp_hash->{$page_url}) .".\t". (WikiCommons::get_time_diff) ."\n" if (exists $pages_toimp_hash->{$page_url});

    ++$count_files;
    print "\tNumber of files: ".($count_files)."\t". (WikiCommons::get_time_diff) ."\n" if ($count_files%100 == 0);

    chomp $page_url;
    die "No page for $doc_file.\n" if ($page_url eq "" );

    my @categories = ();
    push @categories, $ver_fixed;
    push @categories, $main;
    push @categories, $big_ver;
    push @categories, $customer;
    $pages_toimp_hash->{$page_url} = [WikiCommons::get_file_md5($doc_file), $rel_path, $svn_url, "link", \@categories];
}

sub get_documents {
    my $self = shift;
    my @APPEND_DIRS=("Docs", "Docs_Customizations", "Projects", "Projects_Common", "Projects_Customizations", "Projects_Deployment", "Projects_Deployment_Common", "Projects_Deployment_Customization", "SCDocs");
    foreach my $append_dir (@APPEND_DIRS) {
	print "-Searching for files in $append_dir.\t". (WikiCommons::get_time_diff) ."\n";
	$count_files = 0;
	find sub { add_document ($File::Find::name, $append_dir, "$self->{path_files}", "$self->{url_sep}") if -f && (/(\.doc|\.docx|\.rtf)$/i) }, "$self->{path_files}/$append_dir" if  (-d "$self->{path_files}/$append_dir");
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

