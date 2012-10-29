package WikiMindUsers;

use warnings;
use strict;

use File::Find;
use File::Basename;
use Cwd 'abs_path';
use Data::Dumper;
$Data::Dumper::Sortkeys = 1;
use Log::Log4perl qw(:easy);

our $pages_toimp_hash = {};
our $general_categories_hash = {};
our $duplicates = {};
our $disabled = {};

sub new {
    my $class = shift;
    my $self = { path_files => abs_path(shift)};
    bless($self, $class);
    return $self;
}

sub get_disabled_pages {
    return $disabled;
}

sub get_categories {
    return $general_categories_hash;
}

sub generate_categories {
    my ($ver, $main, $big_ver, $customer, $dir_type) = @_;
    ## $general_categories_hash->{5.01.019}->{5.01} means that 5.01.019 will be in 5.01 category
}

sub add_document {
    my $doc_file = abs_path(shift);
    my $path_files = shift;
    my $rel_path = "$doc_file";
    $rel_path =~ s/^$path_files\///;
    my ($name,$dir,$suffix) = fileparse("$doc_file", qr/\.[^.]*/);
    my $customer = "";
    my $page_url = "";
    my @categories = ();
    my $main = ""; my $ver = ""; my $ver_fixed = ""; my $big_ver = ""; my $ver_sp = ""; my $ver_id = "";
    $name =~ s/(^\s+)|(\s+$)//;

    if (-f "$dir/$name.txt") {
	local( $/, *FILEHANDLE ) ;
	open (FILEHANDLE, "$dir/$name.txt") or LOGDIE $!."\t". (WikiCommons::get_time_diff) ."\n";
# 	my @text = <FILEHANDLE>;
	my $text1 = <FILEHANDLE>;
	close (FILEHANDLE);
	$text1 =~ s/\n+/\n/gsm;
	my @text = split "\n", $text1;
	chomp(@text);
	my $q = (split ('=', $text[2]))[1];
	@categories = split ',', $q if defined $q && $q !~ m/^\s*$/;
	push @categories, "Users Automatically imported";
	for (my $i=0;$i<@categories;$i++) { $categories[$i] =~ s/(^\s+|\s+$)//g; };
	my $version = (split ('=', $text[0]))[1];
	if ( defined $version ) {
	    $version =~ s/(^\s+|\s+$)//g;
	} else {
	    $version = "";
	}
	$customer = (split ('=', $text[1]))[1];
	if ( defined $customer ) {
	    $customer =~ s/(^\s+|\s+$)//g;
# 	    $customer = WikiCommons::capitalize_string( $customer, "first"  );
	    my $tmp = $customer;
	    $customer = WikiCommons::get_correct_customer($customer);
	    $customer = $tmp if ! defined $customer;
	    push @categories, $customer;
	} else {
	    $customer = "";
	}

	my $url_sep = WikiCommons::get_urlsep;
	my $done = (split ('=', $text[3]))[1];
	return if ! defined $done;
	$done =~ s/(^\s+|\s+$)//g;
	if ($done ne "") {
	    ($big_ver, $main, $ver, $ver_fixed, $ver_sp, $ver_id) = WikiCommons::check_vers ( $version, $version) if ($version ne "" );
# 	    WikiCommons::generate_categories($ver_fixed, $main, $big_ver, $customer, "Users documents");
	    my $fixed_name = $name;
	    $fixed_name = WikiCommons::fix_name ($name, $customer, $big_ver, $main, $ver, $ver_sp, $ver_id) if ($version ne "" );
	    $page_url = "$fixed_name$url_sep$ver_fixed$url_sep$customer";
	    $page_url =~ s/($url_sep){2,}/$url_sep/g;
	    $page_url =~ s/(^$url_sep)|($url_sep$)//;
	    chomp $page_url;
	    $page_url = WikiCommons::normalize_text( $page_url );
	    $page_url = WikiCommons::capitalize_string( $page_url, 'first' );
	    if ($done !~ m/yes/i) {
		$disabled->{$page_url} = "";
		return;
	    }
	} else {
	    return;
	}
    } else {
	INFO "Invalid users doc. txt file missing: $dir/$name.txt.\n";
	return;
    }

    LOGDIE "Url is empty.\n" if $page_url eq '';

    if (exists $pages_toimp_hash->{$page_url}) {
	$duplicates->{$page_url}->{$doc_file} = 1;
	return 0;
    }

    INFO "No txt page for $doc_file.\n" if ($page_url eq "" );
    $pages_toimp_hash->{$page_url} = [WikiCommons::get_file_md5($doc_file), "$rel_path", "", "link", \@categories];
}

sub get_documents {
    my $self  = shift;
    my $url_sep = WikiCommons::get_urlsep;
    find sub { add_document ($File::Find::name, "$self->{path_files}", "$url_sep") if -f && (/(\.doc|\.docx|\.rtf|\.xls|\.xlsx|\.odt)$/i) }, "$self->{path_files}";

    foreach my $url (sort keys %$duplicates) {
	my $first_path = "$self->{path_files}/$pages_toimp_hash->{$url}[1]";
	my $txt = "We already have url $url.\nIt is the same as\n\t$first_path";
	foreach my $file (keys %{$duplicates->{$url}}){
	    $txt .= "\n\t$file";
	}
	foreach my $file (keys %{$duplicates->{$url}}){
	    my ($name,$dir,$suffix) = fileparse("$file", qr/\.[^.]*/);
	    WikiCommons::write_file("$dir/$name.error", $txt);
	}
	my ($name,$dir,$suffix) = fileparse("$first_path", qr/\.[^.]*/);
	WikiCommons::write_file("$dir/$name.error", $txt);
	delete $pages_toimp_hash->{$url};
    }
    return $pages_toimp_hash;
}

return 1;
