package WikiMindCRM;

use warnings;
use strict;

use Data::Dumper;
$Data::Dumper::Sortkeys = 1;
use Log::Log4perl qw(:easy);
use File::Find;
use Cwd 'abs_path';
use File::Basename;

our $pages_toimp_hash = {};
our $general_categories_hash = {};
our $count_files;
our $domain;

sub new {
    my $class = shift;
    my $self = { path_files => shift, domain => shift };
    bless($self, $class);
    $domain = $self->{domain};
    return $self;
}

sub get_categories {
    return $general_categories_hash;
}

sub add_document{
    my ($doc_file, $path_file, $url_sep) = @_;
    $doc_file = abs_path($doc_file);
    my $doc_filesize = -s "$doc_file";
    return if ($doc_filesize == 0);

    my $str = $doc_file;
    $str =~ s/^$path_file\/?//;
    my $rel_path = $str;
    my ($name,$dir,$suffix) = fileparse($str, qr/\.[^.]*/);

    my @values = split('\/', $str);
    LOGDIE "Too many.\n" if scalar @values != 2;
    my $md5 = $rel_path;
    my $sr = $values[1];
    $sr =~ s/^0*//;
    $sr = (split '_', $sr)[0];
    my $ns = "";
    if ($domain =~ m/^iphonex$/i) {
        $ns = "CRM_iPhonex";
    } elsif ($domain =~ m/^phonexone$/i) {
        $ns = "CRM_PhonexONE";
    } elsif ($domain =~ m/^sentori$/i) {
        $ns = "CRM_Sentori";
    } elsif ($domain =~ m/^docs$/i) {
        return; ##empty old crm
    } else {
      LOGDIE "Domain should be mind, phonex, sentori.\n";
    }
    my $page_url = "$values[0]".$url_sep."$sr";
    chomp $page_url;
    LOGDIE "No page for $doc_file.\n" if ($page_url eq "" );

#     my @categories = ($values[0], 'CRM');
#     my $customer = (split ":",$values[0])[1];
# INFO Dumper($values[0], $customer);
    $general_categories_hash->{"$values[0]$url_sep"."CRM"}->{"CRM"} = 1;
    $general_categories_hash->{"$values[0]$url_sep"."CRM"}->{"$values[0]"} = 1;

    ++$count_files;
    INFO "\tNumber of files: ".($count_files)."\t". (WikiCommons::get_time_diff) ."\n" if ($count_files%1000 == 0);

    LOGDIE "Page already exists.: $ns$page_url\n" if exists $pages_toimp_hash->{"$ns:$page_url"};
    $pages_toimp_hash->{"$ns:$page_url"} = [$md5." redirect", $rel_path, "", "real"];
    $pages_toimp_hash->{"CRM:$page_url"} = [$md5, $rel_path, "", "real"];
}

sub get_documents {
    my $self = shift;
    my $path_files = $self->{path_files};
    my $url_sep = WikiCommons::get_urlsep;
    INFO "-Searching for files in CRM dir.\t". (WikiCommons::get_time_diff) ."\n";
    find sub { add_document ($File::Find::name, "$self->{path_files}", "$url_sep") if -f && (/\.wiki$/i) }, "$self->{path_files}/" if  (-d "$self->{path_files}");
    INFO "+Searching for files in CRM dir.\t". (WikiCommons::get_time_diff) ."\n";
    return $pages_toimp_hash;
}

return 1;
