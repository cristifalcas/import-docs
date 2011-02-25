package WikiWork;

use warnings;
use strict;

use Mind_work::WikiCommons;
use Data::Dumper;
$Data::Dumper::Sortkeys = 1;
use MediaWiki::API;
# http://en.wikipedia.org/w/api.php
# http://www.mediawiki.org/wiki/API:Lists/es

our $wiki_site_path = "/var/www/html/wiki/";
our $wiki_url = "http://10.0.0.99/wiki";
# our $wiki_url = "http://localhost:1900/wiki";
our $wiki_user = 'wiki_auto_import';
our $wiki_pass = '!0wiki_auto_import@9';
our $mw;
our $array = ();

sub wiki_on_error {
    print "1. Error code: " . $mw->{error}->{code} . "\n";
    print "2. Error details: " . Dumper($mw->{error}->{details})."\n";
    $mw->{response}->{_request}->{_content}="*** deleted ***";
    print "3. Error response: " . Dumper($mw->{response})."\n";
    print "4. Error stacktrace: " . $mw->{error}->{stacktrace}."\n";
    die;
}

sub new {
    my $class = shift;
    my $self = {};
    if (WikiCommons::is_remote ne "yes" ) {
	$mw = MediaWiki::API->new({ api_url => "$wiki_url/api.php" }, retries  => 3) or die "coco";
	$mw->{config}->{on_error} = \&wiki_on_error;
	$mw->login( {lgname => $wiki_user, lgpassword => $wiki_pass } )
	    || die $mw->{error}->{code} . ': ' . $mw->{error}->{details};
    }
    bless($self, $class);
    return $self;
}

sub wiki_get_page {
  my $self = shift;
  my $page = $mw->get_page( { title => @_ } );
  return $page;
}

sub wiki_delete_page {
  my ($self, $title, $extra_files_path) = @_;
  my $page = $mw->get_page( { title => $title } );
#   $mw->login( {lgname => 'admin', lgpassword => '!0admin@9' } )
#     || die "Could not login with user admin: ".$mw->{error}->{code} . ': ' . $mw->{error}->{details}."\t". (WikiCommons::get_time_diff) ."\n";
  unless ( $page->{missing} ) {
    $mw->edit( { action => 'delete', title => $title, reason => 'no longer needed' } )
    || die "Could not delete url $title: ".$mw->{error}->{code} . ': ' . $mw->{error}->{details}."\t". (WikiCommons::get_time_diff) ."\n";
  }

    ## remove due to too many overwrites
  if ($extra_files_path ne "" ) {
    print "\t-Delete previous files from wiki.\t". (WikiCommons::get_time_diff) ."\n";
    my @cmd_output = `php "$wiki_site_path/maintenance/deleteBatch.php" --conf "$wiki_site_path/LocalSettings.php" "$extra_files_path"`;
#     print "@cmd_output\n";
    print "\t+Delete previous files from wiki.\t". (WikiCommons::get_time_diff) ."\n";
  }

#   $mw->login( {lgname => $wiki_user, lgpassword => $wiki_pass } )
#     || die "Could not login with user $wiki_user: ".$mw->{error}->{code} . ': ' . $mw->{error}->{details}."\t". (WikiCommons::get_time_diff) ."\n";
}

sub wiki_edit_page {
  my ($self, $title, $text) = @_;
  print "\t-Uploading page for url $title. ". (WikiCommons::get_time_diff) ."\n";
  my $page = $mw->get_page( { title => $title } );
  print "\tCreating a new page for url $title.\n" if ($page->{missing});
  my $timestamp = $page->{timestamp};
# php /var/www/html/wiki/maintenance/importTextFile.php --title "Manual De Utilizare MINDBill CSR 6.01.003 -- 6.01 -- 6.01.003 -- User Manuals -- MoldTel branded" "/media/share/Documentation/cfalcas/q/import_docs/work/workfor_svn_docs/Manual De Utilizare MINDBill CSR 6.01.003 -- 6.01 -- 6.01.003 -- User Manuals -- MoldTel branded"

  $mw->edit( { action => 'edit', title => $title, text => Encode::decode('utf8', $text) } )
      || die "Could not upload text for $title: ".$mw->{error}->{code} . ': ' . $mw->{error}->{details}."\t". (WikiCommons::get_time_diff) ."\n";
  print "\t+Uploading page for url $title. ". (WikiCommons::get_time_diff) ."\n";
}

sub wiki_import_files {
    my ($self, $file_path, $url) = @_;
    print "\t-Uploading files for url $url.\t". (WikiCommons::get_time_diff) ."\n";
    my @cmd_output = `php "$wiki_site_path/maintenance/importImages.php" --conf "$wiki_site_path/LocalSettings.php" --user="$wiki_user" --overwrite --check-userblock "$file_path"`;
    die "\tError $? for importImages.php.\n" if ($?);
    print "@cmd_output\n";
    print "\t+Uploading files for url $url.\t". (WikiCommons::get_time_diff) ."\n";
}

sub wiki_exists_page {
    my ($self, $title) = @_;
    my $page = $mw->get_page( { title => $title } );
    unless ( $page->{'*'} ) {
    return 0;
    }
    return 1;
}

sub wiki_geturl {
    return $wiki_url;
}

sub wiki_move_page {
    my ($self, $title, $new_title) = @_;
    $mw->edit( {
    action => 'move', from => "$title", to => "$new_title" } )
    || die "Could not move url $title to $new_title: ".$mw->{error}->{code} . ': ' . $mw->{error}->{details}."\t". (WikiCommons::get_time_diff)."\n";
}

sub wiki_get_nonredirects {
    my ($self, $ns) = @_;
    $array = ();
    $mw->list ( { action => 'query',
	    list => 'allpages', aplimit=>'5000',
	    apnamespace => "$ns", apfilterredir => "nonredirects" },
	{ max => 1000, hook => \&wiki_print_title } )
		|| die $mw->{error}->{code} . ': ' . $mw->{error}->{details};
    return $array;
}

sub wiki_get_redirects {
    my ($self, $ns) = @_;
    $array = ();
    $mw->list ( { action => 'query',
	    list => 'allpages', aplimit=>'5000',
	    apnamespace => "$ns", apfilterredir => "redirects" },
	{ max => 1000, hook => \&wiki_print_title } )
		|| die $mw->{error}->{code} . ': ' . $mw->{error}->{details};
    return $array;
}

sub wiki_get_all_pages {
    my ($self, $ns) = @_;
    $array = ();
    $mw->list ( { action => 'query',
	    list => 'allpages', aplimit=>'5000',
	    apnamespace => "$ns" },
	{ max => 1000, hook => \&wiki_print_title } )
		|| die $mw->{error}->{code} . ': ' . $mw->{error}->{details};
    return $array;
} 

sub wiki_get_pages_using {
    my ($self, $file) = @_;
    $array = ();
    $mw->list ( { action => 'query',
	    list => 'imageusage', iulimit=>'5000',
	    iutitle => "$file" },
	{ max => 1000, hook => \&wiki_print_title } )
		|| die $mw->{error}->{code} . ': ' . $mw->{error}->{details};
    return $array;
} 

sub wiki_print_title {
    my ( $ref) = @_;
    foreach (@$ref) {
	push @$array, $_->{title};
    }
}

return 1;
