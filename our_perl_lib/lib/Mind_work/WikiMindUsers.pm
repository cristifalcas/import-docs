package WikiMindUsers;

use warnings;
use strict;

use File::Find;
use File::Basename;
use Cwd 'abs_path';
use Data::Dumper;
$Data::Dumper::Sortkeys = 1;

our $pages_toimp_hash = {};
our $general_categories_hash = {};

sub new {
    my $class = shift;
    my $self = { path_files => abs_path(shift)};
    bless($self, $class);
    return $self;
}

sub get_categories {
    return $general_categories_hash;
}

sub generate_categories {
    my ($ver, $main, $big_ver, $customer, $dir_type) = @_;
    ## $general_categories_hash->{5.01.019}->{5.01} means that 5.01.019 will be in 5.01 category
    $general_categories_hash->{$ver}->{$main} = 1 if $ver ne "" && $ver ne $main;
    $general_categories_hash->{$ver}->{$big_ver} = 1 if $ver ne "" && $big_ver ne "";
    $general_categories_hash->{$ver}->{$customer} = 1 if $big_ver ne "" && $customer ne "";
    $general_categories_hash->{$ver}->{$dir_type} = 1 if $big_ver ne "" && $dir_type ne "";

    $general_categories_hash->{$main}->{$big_ver} = 1 if $main ne "" && $big_ver ne "";
    $general_categories_hash->{$main}->{$customer} = 1 if $main ne "" && $customer ne "";
    $general_categories_hash->{$main}->{$dir_type} = 1 if $main ne "" && $dir_type ne "";
    $general_categories_hash->{$main}->{'Mind Documentation autoimport'} = 1 if $main ne "";

    $general_categories_hash->{$customer}->{$dir_type} = 1 if $customer ne "" && $dir_type ne "";
    $general_categories_hash->{$customer}->{'MIND_Customers'} = 1 if $customer ne "";
    $general_categories_hash->{$customer}->{'Mind Documentation autoimport'} = 1 if $customer ne "";

    $general_categories_hash->{$big_ver}->{'Mind Documentation autoimport'} = 1 if $big_ver ne "";
    $general_categories_hash->{$dir_type}->{'Mind Documentation autoimport'} = 1 if $dir_type ne "";
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
# 	    $customer = WikiCommons::capitalize_string( $customer, "first"  );
	    $customer = WikiCommons::get_correct_customer($customer);
	    push @categories, $customer;
	} else {
	    $customer = "";
	}

	my $url_sep = WikiCommons::get_urlsep;
	my $done = (split ('=', $text[3]))[1]; $done =~ s/(^\s+|\s+$)//g;
	if ($done eq "yes") {
	    ($big_ver, $main, $ver, $ver_fixed, $ver_sp, $ver_id) = WikiCommons::check_vers ( $version, $version) if ($version ne "" );
# 	    WikiCommons::generate_categories($ver_fixed, $main, $big_ver, $customer, "Users documents");
	    my $fixed_name = $name;
	    $fixed_name = WikiCommons::fix_name ($name, $customer, $big_ver, $main, $ver, $ver_sp, $ver_id) if ($version ne "" );
# 	    generate_categories($ver_fixed, $main, $big_ver, $customer, "Users documents");
# 	    $page_url = "$fixed_name$url_sep$main$url_sep$ver_fixed$url_sep$customer";
	    $page_url = "$fixed_name$url_sep$ver_fixed$url_sep$customer";
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
    my $url_sep = WikiCommons::get_urlsep;
    find sub { add_document ($File::Find::name, "$self->{path_files}", "$url_sep") if -f && (/(\.doc|\.docx|\.rtf)$/i) }, "$self->{path_files}";
    return $pages_toimp_hash;
}

return 1;
