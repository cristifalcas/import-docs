use Cwd 'abs_path';
use File::Basename;
use File::Copy;
use File::Find;

use lib (fileparse(abs_path($0), qr/\.[^.]*/))[1]."./our_perl_lib/lib";

use MediaWiki::API;

my $mw = MediaWiki::API->new();


$mw->{config}->{api_url} = 'http://10.0.0.99/wiki/api.php';

sub all_pages {
$mw->list ( { action => 'query',
	list => 'allpages',
	aplimit=>'500' },
    { max => 40000, hook => \&print_articles } )
            || die $mw->{error}->{code} . ': ' . $mw->{error}->{details};
}

sub all_links {
$mw->list ( { action => 'query',
	list => 'alllinks',
	allimit=>'500' },
    { max => 40000, hook => \&print_articles } )
            || die $mw->{error}->{code} . ': ' . $mw->{error}->{details};
}

sub all_deleted {
$mw->list ( { action => 'query',
	list => ' deletedrevs',
	drlimit=>'500' },
    { max => 40000, hook => \&print_articles } )
            || die $mw->{error}->{code} . ': ' . $mw->{error}->{details};
}

# print the name of each article
sub print_articles {
    my ($ref) = @_;
    foreach (@$ref) {
	print "$_->{title}\n";
    }
}

#all_pages
all_links
#all_deleted
