#!/usr/bin/perl -w

use Cwd 'abs_path';
use File::Basename;
use File::Copy;
use File::Find;
use URI::Escape;
# http://www.mediawiki.org/wiki/API:Query_-_Lists
use lib (fileparse(abs_path($0), qr/\.[^.]*/))[1]."../our_perl_lib/lib";

use MediaWiki::API;

my $mw = MediaWiki::API->new();

$mw->{config}->{api_url} = 'http://10.0.0.99/wiki/api.php';
$mw->login( {lgname => 'admin', lgpassword => '!0admin@9' } )
	    || die $mw->{error}->{code} . ': ' . $mw->{error}->{details};

sub all_redirects {
    my $ns = shift;
    $mw->list ( { action => 'query',
	    list => 'allpages',
	    apnamespace => "$ns", apfilterredir => "redirects" },
	{ max => 40000, hook => \&print_title } )
		|| die $mw->{error}->{code} . ': ' . $mw->{error}->{details};
}

sub print_title {
    my ($ref) = @_;
    foreach (@$ref) {
	print "$_->{title}\n";
    }
}

all_redirects(100)
