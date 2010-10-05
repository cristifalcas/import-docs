package WikiMindUsers;

use warnings;
use strict;

use File::Find;
use File::Basename;
use Cwd 'abs_path';
use Data::Dumper;

our $pages_toimp_hash = {};

sub new {
    my $class = shift;
    my $self = { path_files => abs_path(shift) , url_sep => shift };
    bless($self, $class);
    return $self;
}

sub add_document {
    my $doc_file = abs_path(shift);
    my $path_files = shift;
    my $url_sep = shift;
    my $rel_path = "$doc_file";
    $rel_path =~ s/^$path_files\///;
    my ($name,$dir,$suffix) = fileparse("$doc_file", qr/\.[^.]*/);
    my $customer = "";
    my $page_url = "";
    my @categories = ();
    my $main = ""; my $ver = ""; my $ver_fixed = ""; my $big_ver = "";

    if (-f "$dir/$name.txt") {
	open (FILEHANDLE, "$dir/$name.txt") or die $!."\t". (WikiCommons::get_time_diff) ."\n";
	my @text = <FILEHANDLE>;
	close (FILEHANDLE);

	chomp(@text);
	@categories = split ',', (split ('=', $text[2]))[1];
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
	    push @categories, $customer;
	} else {
	    $customer = "";
	}
	my $done = (split ('=', $text[3]))[1]; $done =~ s/(^\s+|\s+$)//g;
	if ($done eq "yes") {
	    ($main, $ver, $ver_fixed, $big_ver) = WikiCommons::check_vers ($version, $version) if ($version ne "" );
	    WikiCommons::generate_categories($ver_fixed, $main, $big_ver, $customer, "Users documents");
	    my $fixed_name = $name;
	    $fixed_name = WikiCommons::fix_name ($name, $customer, $main, $ver) if ($version ne "" );
	    $page_url = "$fixed_name$url_sep$main$url_sep$ver_fixed$url_sep$customer";
	    $page_url =~ s/($url_sep){2,}/$url_sep/g;
	    $page_url =~ s/(^$url_sep)|($url_sep$)//;
	} else {
	    return;
	}
    } else {
	print "Invalid users doc. txt file missing: $dir/$name.txt.\n";
	return;
    }
    chomp $page_url;
    die "Url is empty.\n" if $page_url eq '';
    die "We already have url $page_url from $doc_file with \n". Dumper($pages_toimp_hash->{$page_url}) .".\t". (WikiCommons::get_time_diff) ."\n" if (exists $pages_toimp_hash->{$page_url});

    print "No txt page for $doc_file.\n" if ($page_url eq "" );
    $pages_toimp_hash->{$page_url} = [WikiCommons::get_file_md5($doc_file), "$rel_path", "", "link", \@categories];
}

sub get_documents {
    my $self  = shift;
    find sub { add_document ($File::Find::name, "$self->{path_files}", "$self->{url_sep}") if -f && (/(\.doc|\.docx|\.rtf)$/i) }, "$self->{path_files}";
    return $pages_toimp_hash;
}

return 1;
