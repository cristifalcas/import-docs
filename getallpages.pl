#!/usr/bin/perl -w

use Cwd 'abs_path';
use File::Basename;
use File::Copy;
use File::Find;
use URI::Escape;
# http://www.mediawiki.org/wiki/API:Query_-_Lists
use lib (fileparse(abs_path($0), qr/\.[^.]*/))[1]."./our_perl_lib/lib";

use MediaWiki::API;

my $mw = MediaWiki::API->new();

$mw->{config}->{api_url} = 'http://10.0.0.99/wiki/api.php';
$mw->login( {lgname => 'admin', lgpassword => '!0admin@9' } )
	    || die $mw->{error}->{code} . ': ' . $mw->{error}->{details};

sub all_pages {
    my $ns = shift;
    $mw->list ( { action => 'query',
	    list => 'allpages',
	    apnamespace => "$ns" },
	{ max => 40000, hook => \&print_title } )
		|| die $mw->{error}->{code} . ': ' . $mw->{error}->{details};
}

sub all_links {
$mw->list ( { action => 'query',
	list => 'alllinks' },
    { max => 40000, hook => \&print_title } )
            || die $mw->{error}->{code} . ': ' . $mw->{error}->{details};
}

sub all_categories {
$mw->list ( { action => 'query',
	list => 'allcategories' },
    { max => 40000, hook => \&print_title } )
            || die $mw->{error}->{code} . ': ' . $mw->{error}->{details};
}

sub all_images {
$mw->list ( { action => 'query',
	list => 'allimages' },
    { max => 40000, hook => \&print_url } )
            || die $mw->{error}->{code} . ': ' . $mw->{error}->{details};
}

# print the name of each article
sub print_title {
    my ($ref) = @_;
    foreach (@$ref) {
	print "$_->{title}\n";
    }
}

sub print_url {
    my ($ref) = @_;
    foreach (@$ref) {
	my @arr = split '/', $_->{"url"};
	my $name = uri_unescape(pop @arr);
	my $pages = $mw->list ( { action => 'query',
		list => 'imageusage',
		iulimit=>'1',
		iutitle=>"File:$name" },
	    ) || die $mw->{error}->{code} . ': ' . $mw->{error}->{details};
	if ( ! scalar @{$pages} ) {
	    print "File:$name\n";
# 	    print "\t$_->{url}\n";
	    $mw->edit( { action => 'delete', title => "File:$name", reason => 'old' } )
		|| print $mw->{error}->{code} . ': ' . $mw->{error}->{details}."\n";
	 }
    }
}

# all_categories
# all_pages (0) ;
# all_pages (14) ## categories
# all_links
all_images
