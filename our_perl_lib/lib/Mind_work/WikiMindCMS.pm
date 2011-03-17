package WikiMindCMS;

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
    my ($name) = @_;
    ## $general_categories_hash->{5.01.019}->{5.01} means that 5.01.019 will be in 5.01 category
    $general_categories_hash->{'CMS All documents'} = 1;
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
    my $url_sep = WikiCommons::get_urlsep;

    $fixed_name = $name;
    $fixed_name = WikiCommons::normalize_text( $fixed_name );
    $fixed_name = WikiCommons::capitalize_string( $fixed_name, 'first' );
    my $page_url = "$fixed_name";
    $page_url =~ s/\s+/ /g;
    $page_url =~ s/(^\s+)|(\s+$)//;

    $count_files++;
    my @categories = ();
    if ($dir =~ m/\/(.*? )?Release Notes\//i || $page_url =~ m/Release Notes/i) {
	$page_url = "RN:$page_url$url_sep"."CMS";
    } else {
	$page_url = "CMS:$page_url";
	@categories = ('CMS All documents');
	generate_categories($page_url);
    }

    my $i = 0;
    while (1) {
	if ( exists $pages_toimp_hash->{"$page_url$i"} ){
	    $i++ ;
	} else {
	    last;
	}
    }
    $page_url = $page_url." - $i" if $i;
    $pages_toimp_hash->{$page_url} = [WikiCommons::get_file_md5($doc_file), $rel_path, $svn_url, "link", \@categories];
}

sub get_documents {
    my $self = shift;
    my @APPEND_DIRS=("Docs_CMS", "Docs_Phonex", "Docs_Sentori");
    my $url_sep = WikiCommons::get_urlsep;
    foreach my $append_dir (@APPEND_DIRS) {
	print "-Searching for files in $append_dir.\t". (WikiCommons::get_time_diff) ."\n";
	$count_files = 0;
	find ({
	    wanted => sub { add_document ($File::Find::name, $append_dir, "$self->{path_files}", "$url_sep") if -f && (/(\.doc|\.docx|\.rtf|\.xls)$/i) },},
	    "$self->{path_files}/$append_dir"
	    ) if  (-d "$self->{path_files}/$append_dir");
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

