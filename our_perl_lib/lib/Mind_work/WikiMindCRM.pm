package WikiMindCRM;

use warnings;
use strict;

use Data::Dumper;
use File::Find;
use Cwd 'abs_path';
use File::Basename;

our $pages_toimp_hash = {};
our $count_files;

sub new {
    my $class = shift;
    my $self = { path_files => shift , url_sep => shift};
    bless($self, $class);
    return $self;
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
    die "Too many.\n" if scalar @values != 2;
    my $md5 = $rel_path;
    my $sr = $values[1];
    $sr =~ s/^0*//;
    $sr = (split '_', $sr)[0];
    my $page_url = 'CRM:'."$values[0]".$url_sep."$sr";
    chomp $page_url;
    die "No page for $doc_file.\n" if ($page_url eq "" );

    my @categories = ($values[0], 'CRM');

    ++$count_files;
    print "\tNumber of files: ".($count_files)."\t". (WikiCommons::get_time_diff) ."\n" if ($count_files%1000 == 0);

    die "Page already exists.: $page_url\n" if exists $pages_toimp_hash->{$page_url};
    $pages_toimp_hash->{$page_url} = [$md5, $rel_path, "", "real", \@categories];
}

sub get_documents {
    my $self = shift;
    my $path_files = $self->{path_files};
    print "-Searching for files in CRM dir.\t". (WikiCommons::get_time_diff) ."\n";
    find sub { add_document ($File::Find::name, "$self->{path_files}", "$self->{url_sep}") if -f && (/\.wiki$/i) }, "$self->{path_files}/" if  (-d "$self->{path_files}");
    print "+Searching for files in CRM dir.\t". (WikiCommons::get_time_diff) ."\n";
    return $pages_toimp_hash;
}

return 1;
